import Foundation

/// Reads and parses Claude Code usage data from JSONL files in ~/.claude/projects/.
/// Supports staged loading: recent first, then weekly, then historical.
actor UsageReader {
    private let dataPath: URL
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
            // Throttle between files to keep CPU low
            Thread.sleep(forTimeInterval: 0.05)
        }

        allEntries.sort { $0.timestamp < $1.timestamp }
        NSLog("[ClaudeBar] Loaded \(allEntries.count) entries from \(files.count) files (last \(hoursBack)h)")
        return allEntries
    }

    /// Incrementally load more entries, merging with existing ones.
    func loadMoreEntries(hoursBack: Int, existingHashes: Set<String>) -> [UsageEntry] {
        let cutoff = Date().addingTimeInterval(-Double(hoursBack) * 3600)
        processedHashes = existingHashes

        let files = findJSONLFiles(modifiedAfter: cutoff)
        var newEntries: [UsageEntry] = []

        for file in files {
            let entries = processFile(file, cutoff: cutoff)
            newEntries.append(contentsOf: entries)
            Thread.sleep(forTimeInterval: 0.01)
        }

        newEntries.sort { $0.timestamp < $1.timestamp }
        return newEntries
    }

    /// Build session blocks from entries using 5-hour windows.
    func buildSessionBlocks(from entries: [UsageEntry]) -> [SessionBlock] {
        guard !entries.isEmpty else { return [] }

        let windowSeconds = Double(ClaudePlan.sessionWindowHours) * 3600
        var blocks: [SessionBlock] = []
        var currentEntries: [UsageEntry] = []
        var blockStart = entries[0].timestamp

        for entry in entries {
            if entry.timestamp.timeIntervalSince(blockStart) > windowSeconds {
                if !currentEntries.isEmpty {
                    blocks.append(makeBlock(entries: currentEntries, start: blockStart, windowSeconds: windowSeconds))
                }
                currentEntries = []
                blockStart = entry.timestamp
            }
            currentEntries.append(entry)
        }

        if !currentEntries.isEmpty {
            let blockEnd = blockStart.addingTimeInterval(windowSeconds)
            blocks.append(SessionBlock(
                id: isoFormatter.string(from: blockStart), startTime: blockStart,
                endTime: blockEnd, entries: currentEntries, isActive: Date() < blockEnd
            ))
        }

        return blocks
    }

    /// Load ALL entries (no time filter, for full history).
    func loadAllEntries() -> [UsageEntry] {
        processedHashes.removeAll()
        let veryOld = Date.distantPast
        let files = findJSONLFiles(modifiedAfter: veryOld)
        NSLog("[ClaudeBar] Loading all: \(files.count) files")
        var allEntries: [UsageEntry] = []
        for file in files {
            let entries = processFile(file, cutoff: veryOld)
            allEntries.append(contentsOf: entries)
            Thread.sleep(forTimeInterval: 0.05)
        }
        allEntries.sort { $0.timestamp < $1.timestamp }
        NSLog("[ClaudeBar] Loaded all: \(allEntries.count) entries")
        return allEntries
    }

    /// Build daily usage aggregations.
    func buildDailyUsage(from entries: [UsageEntry]) -> [DailyUsage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        return grouped.map { (date, entries) in
            DailyUsage(id: fmt.string(from: date), date: date,
                       entries: entries.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.date < $1.date }
    }

    /// Build hourly usage aggregations.
    func buildHourlyUsage(from entries: [UsageEntry]) -> [HourlyUsage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: entry.timestamp)
            return calendar.date(from: comps) ?? entry.timestamp
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH"

        return grouped.map { (hour, entries) in
            HourlyUsage(id: fmt.string(from: hour), hour: hour,
                        entries: entries.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.hour < $1.hour }
    }

    /// Build monthly usage aggregations.
    func buildMonthlyUsage(from entries: [UsageEntry]) -> [MonthlyUsage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.timestamp)
            return calendar.date(from: comps) ?? entry.timestamp
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"

        return grouped.map { (month, entries) in
            MonthlyUsage(id: fmt.string(from: month), month: month,
                         entries: entries.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.month < $1.month }
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
