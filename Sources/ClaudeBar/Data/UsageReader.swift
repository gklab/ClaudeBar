import Foundation

/// Reads and parses Claude Code usage data from JSONL files in ~/.claude/projects/.
/// Supports staged loading: recent first, then weekly, then historical.
actor UsageReader {
    let dataPath: URL

    func getDataPath() -> URL { dataPath }
    private var processedHashes: Set<String> = []
    private let isoFormatter: ISO8601DateFormatter
    private let isoFormatterNoFrac: ISO8601DateFormatter

    init(dataPath: URL? = nil) {
        if let dataPath {
            self.dataPath = dataPath
        } else {
            self.dataPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects")
        }
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatterNoFrac = ISO8601DateFormatter()
        self.isoFormatterNoFrac.formatOptions = [.withInternetDateTime]
    }

    /// Load entries for a specific time window. Files are filtered by mtime.
    func loadEntries(hoursBack: Int) -> [UsageEntry] {
        processedHashes.removeAll()
        let cutoff = Date().addingTimeInterval(-Double(hoursBack) * 3600)

        let files = findJSONLFiles(modifiedAfter: cutoff)
        var allEntries: [UsageEntry] = []

        for file in files {
            let entries = processFile(file, cutoff: cutoff)
            allEntries.append(contentsOf: entries)
            Thread.sleep(forTimeInterval: 0.05)
        }

        allEntries.sort { $0.timestamp < $1.timestamp }
        return allEntries
    }

    // MARK: - Private

    private func findJSONLFiles(modifiedAfter cutoff: Date) -> [URL] {
        guard FileManager.default.fileExists(atPath: dataPath.path) else { return [] }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: dataPath, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )

        var files: [(url: URL, mod: Date)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let vals = try? url.resourceValues(forKeys: keys),
                  let mod = vals.contentModificationDate, mod >= cutoff
            else { continue }
            files.append((url, mod))
        }

        // Process most recently modified files first
        files.sort { $0.mod > $1.mod }
        return files.map(\.url)
    }

    private func processFile(_ fileURL: URL, cutoff: Date) -> [UsageEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        var entries: [UsageEntry] = []
        let lines = content.components(separatedBy: .newlines)
        var linesProcessed = 0

        for line in lines {
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else { continue }
            linesProcessed += 1
            // Throttle within large files to prevent CPU saturation
            if linesProcessed % 20 == 0 { Thread.sleep(forTimeInterval: 0.005) }

            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let entry = mapToUsageEntry(json)
            else { continue }

            if entry.timestamp < cutoff { continue }

            let hash = "\(entry.messageId):\(entry.requestId)"
            guard !hash.isEmpty, !processedHashes.contains(hash) else { continue }
            processedHashes.insert(hash)

            entries.append(entry)
        }

        return entries
    }

    private func mapToUsageEntry(_ data: [String: Any]) -> UsageEntry? {
        guard let ts = data["timestamp"] as? String, let timestamp = parseTimestamp(ts) else { return nil }
        let tokens = extractTokens(from: data)
        guard tokens.input > 0 || tokens.output > 0 else { return nil }

        let model = extractModel(from: data)
        let cost = CostCalculator.calculateCost(
            model: model, inputTokens: tokens.input, outputTokens: tokens.output,
            cacheCreationTokens: tokens.cacheCreation, cacheReadTokens: tokens.cacheRead
        )
        let message = data["message"] as? [String: Any]
        return UsageEntry(
            timestamp: timestamp, inputTokens: tokens.input, outputTokens: tokens.output,
            cacheCreationTokens: tokens.cacheCreation, cacheReadTokens: tokens.cacheRead,
            costUSD: cost, model: model,
            messageId: (data["message_id"] as? String) ?? (message?["id"] as? String) ?? "",
            requestId: (data["requestId"] as? String) ?? (data["request_id"] as? String) ?? "",
            sessionId: (data["sessionId"] as? String) ?? ""
        )
    }

    private struct TokenData { var input = 0; var output = 0; var cacheCreation = 0; var cacheRead = 0 }

    private func extractTokens(from data: [String: Any]) -> TokenData {
        let msg = data["message"] as? [String: Any]
        let sources: [[String: Any]?] = [
            msg?["usage"] as? [String: Any],
            data["usage"] as? [String: Any],
            data,
        ]
        for case let s? in sources {
            let i = (s["input_tokens"] as? Int) ?? (s["inputTokens"] as? Int) ?? 0
            let o = (s["output_tokens"] as? Int) ?? (s["outputTokens"] as? Int) ?? 0
            if i > 0 || o > 0 {
                return TokenData(
                    input: i, output: o,
                    cacheCreation: (s["cache_creation_input_tokens"] as? Int) ?? (s["cache_creation_tokens"] as? Int) ?? 0,
                    cacheRead: (s["cache_read_input_tokens"] as? Int) ?? (s["cache_read_tokens"] as? Int) ?? 0
                )
            }
        }
        return TokenData()
    }

    private func extractModel(from data: [String: Any]) -> String {
        (data["message"] as? [String: Any])?["model"] as? String ?? data["model"] as? String ?? "unknown"
    }

    private func parseTimestamp(_ str: String) -> Date? {
        isoFormatter.date(from: str) ?? isoFormatterNoFrac.date(from: str)
    }

    private func makeBlock(entries: [UsageEntry], start: Date, windowSeconds: Double) -> SessionBlock {
        SessionBlock(id: isoFormatter.string(from: start), startTime: start,
                     endTime: start.addingTimeInterval(windowSeconds), entries: entries, isActive: false)
    }
}
