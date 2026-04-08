import Foundation

/// In-memory + disk cache of usage entries indexed by day.
/// On startup: load disk cache → scan only new/modified files → merge → save cache.
/// Scans newest files first for progressive UI updates.
actor UsageCache {
    private let reader: UsageReader
    private let cacheFileURL: URL

    /// Cache: date string -> entries for that day.
    private var dayCache: [String: [UsageEntry]] = [:]
    private var allEntries: [UsageEntry] = []
    /// Tracks file modification times to skip unchanged files.
    private var fileModTimes: [String: TimeInterval] = [:]
    private(set) var isFullScanDone = false

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f
    }()

    var onDataReady: (@Sendable ([UsageEntry], [DailyUsage], [HourlyUsage], [MonthlyUsage]) -> Void)?
    var onProgress: (@Sendable (Int, Int) -> Void)?

    init(reader: UsageReader) {
        self.reader = reader
        self.cacheFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claudebar-cache.json")
    }

    func setProgress(_ cb: @escaping @Sendable (Int, Int) -> Void) { onProgress = cb }
    func setDataCallback(_ cb: @escaping @Sendable ([UsageEntry], [DailyUsage], [HourlyUsage], [MonthlyUsage]) -> Void) { onDataReady = cb }

    // MARK: - Full scan (incremental with disk cache)

    func fullScan() async {
        // 1. Load disk cache
        loadDiskCache()
        let cachedDayCount = dayCache.count

        if cachedDayCount > 0 {
            // Immediately publish cached data
            publishCurrentData()
            NSLog("[ClaudeBar] Cache: loaded \(cachedDayCount) days from disk")
        }

        // 2. Find files, skip unchanged ones
        let path = await reader.getDataPath()
        let allFiles = findJSONLFilesSorted(at: path)
        let filesToScan = allFiles.filter { url in
            let key = url.lastPathComponent
            let currentMod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let cachedMod = fileModTimes[key] ?? 0
            return currentMod > cachedMod
        }

        let total = filesToScan.count
        NSLog("[ClaudeBar] Cache: \(allFiles.count) total files, \(total) new/modified to scan")

        if total == 0 {
            isFullScanDone = true
            return
        }

        // 3. Scan new/modified files (newest first, progressive output)
        var processedHashes = Set(allEntries.map { "\($0.messageId):\($0.requestId)" })
        var batch: [UsageEntry] = []
        var batchCount = 0

        for (i, file) in filesToScan.enumerated() {
            let entries = parseFile(file, processedHashes: &processedHashes)
            batch.append(contentsOf: entries)
            batchCount += 1

            // Track this file's mtime
            let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            fileModTimes[file.lastPathComponent] = mod

            onProgress?(i + 1, total)

            // Publish progressively + save cache incrementally
            if batchCount == 10 || batchCount % 100 == 0 || i == total - 1 {
                indexEntries(batch)
                batch.removeAll(keepingCapacity: true)
                publishCurrentData()
                saveDiskCache()
            }

            try? await Task.sleep(for: .milliseconds(30))
        }

        // 4. Save cache to disk
        saveDiskCache()
        isFullScanDone = true
        NSLog("[ClaudeBar] Cache: scan done, \(dayCache.count) days total")
    }

    // MARK: - Incremental refresh (every 30s)

    func refreshRecent() async {
        let entries = await reader.loadEntries(hoursBack: 6)
        let todayKey = dayFmt.string(from: Date())
        dayCache[todayKey] = entries.filter { dayFmt.string(from: $0.timestamp) == todayKey }
        rebuildAllEntries()
    }

    // MARK: - Query

    func getEntries(hoursBack: Int) -> [UsageEntry] {
        let cutoff = Date().addingTimeInterval(-Double(hoursBack) * 3600)
        return allEntries.filter { $0.timestamp >= cutoff }
    }

    func getDailyUsage() -> [DailyUsage] {
        dayCache.map { (key, entries) in
            DailyUsage(id: key, date: entries.first?.timestamp ?? Date(), entries: entries)
        }.sorted { $0.date < $1.date }
    }

    func getHourlyUsage(hoursBack: Int = 24) -> [HourlyUsage] {
        UsageAggregator.buildHourlyUsage(from: getEntries(hoursBack: hoursBack))
    }

    func getMonthlyUsage() -> [MonthlyUsage] {
        UsageAggregator.buildMonthlyUsage(from: allEntries)
    }

    // MARK: - Publish

    private func publishCurrentData() {
        let entries = getEntries(hoursBack: 168)
        let daily = getDailyUsage()
        let hourly = getHourlyUsage(hoursBack: 24)
        let monthly = getMonthlyUsage()
        onDataReady?(entries, daily, hourly, monthly)
    }

    // MARK: - Disk cache

    private struct DiskCache: Codable {
        struct DayData: Codable {
            let date: String
            let entries: [CodableEntry]
        }
        struct CodableEntry: Codable {
            let timestamp: Double
            let inputTokens: Int
            let outputTokens: Int
            let cacheCreationTokens: Int
            let cacheReadTokens: Int
            let costUSD: Double
            let model: String
            let messageId: String
            let requestId: String
            let sessionId: String
        }
        let days: [DayData]
        let fileModTimes: [String: Double]
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let cache = try? JSONDecoder().decode(DiskCache.self, from: data)
        else { return }

        fileModTimes = cache.fileModTimes

        for day in cache.days {
            let entries = day.entries.map { e in
                UsageEntry(
                    timestamp: Date(timeIntervalSince1970: e.timestamp),
                    inputTokens: e.inputTokens, outputTokens: e.outputTokens,
                    cacheCreationTokens: e.cacheCreationTokens, cacheReadTokens: e.cacheReadTokens,
                    costUSD: e.costUSD, model: e.model,
                    messageId: e.messageId, requestId: e.requestId, sessionId: e.sessionId
                )
            }
            dayCache[day.date] = entries
        }
        rebuildAllEntries()
    }

    private func saveDiskCache() {
        let todayKey = dayFmt.string(from: Date())
        let days = dayCache.compactMap { (key, entries) -> DiskCache.DayData? in
            // Don't cache today (it's still changing)
            guard key != todayKey else { return nil }
            return DiskCache.DayData(
                date: key,
                entries: entries.map { e in
                    DiskCache.CodableEntry(
                        timestamp: e.timestamp.timeIntervalSince1970,
                        inputTokens: e.inputTokens, outputTokens: e.outputTokens,
                        cacheCreationTokens: e.cacheCreationTokens, cacheReadTokens: e.cacheReadTokens,
                        costUSD: e.costUSD, model: e.model,
                        messageId: e.messageId, requestId: e.requestId, sessionId: e.sessionId
                    )
                }
            )
        }

        let cache = DiskCache(days: days, fileModTimes: fileModTimes)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFileURL, options: .atomic)
            NSLog("[ClaudeBar] Cache: saved \(days.count) days to disk (\(data.count / 1024)KB)")
        }
    }

    // MARK: - Private

    private func indexEntries(_ entries: [UsageEntry]) {
        for entry in entries {
            let key = dayFmt.string(from: entry.timestamp)
            dayCache[key, default: []].append(entry)
        }
        for key in dayCache.keys {
            dayCache[key]?.sort { $0.timestamp < $1.timestamp }
        }
        rebuildAllEntries()
    }

    private func rebuildAllEntries() {
        allEntries = dayCache.values.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
    }

    private func findJSONLFilesSorted(at path: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: path, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )
        var files: [(url: URL, mod: Date)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let mod = (try? url.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast
            files.append((url, mod))
        }
        files.sort { $0.mod > $1.mod }
        return files.map(\.url)
    }

    private func parseFile(_ fileURL: URL, processedHashes: inout Set<String>) -> [UsageEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmtNoFrac = ISO8601DateFormatter()
        isoFmtNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [UsageEntry] = []
        for line in content.components(separatedBy: .newlines) {
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else { continue }
            guard let jd = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let ts = json["timestamp"] as? String,
                  let timestamp = isoFmt.date(from: ts) ?? isoFmtNoFrac.date(from: ts)
            else { continue }

            let msg = json["message"] as? [String: Any]
            let usage = msg?["usage"] as? [String: Any]
            let inp = (usage?["input_tokens"] as? Int) ?? 0
            let out = (usage?["output_tokens"] as? Int) ?? 0
            guard inp > 0 || out > 0 else { continue }

            let mid = (json["message_id"] as? String) ?? (msg?["id"] as? String) ?? ""
            let rid = (json["requestId"] as? String) ?? (json["request_id"] as? String) ?? ""
            let hash = "\(mid):\(rid)"
            guard !hash.isEmpty, !processedHashes.contains(hash) else { continue }
            processedHashes.insert(hash)

            let cc = (usage?["cache_creation_input_tokens"] as? Int) ?? 0
            let cr = (usage?["cache_read_input_tokens"] as? Int) ?? 0
            let model = (msg?["model"] as? String) ?? "unknown"
            let cost = CostCalculator.calculateCost(model: model, inputTokens: inp, outputTokens: out, cacheCreationTokens: cc, cacheReadTokens: cr)

            entries.append(UsageEntry(
                timestamp: timestamp, inputTokens: inp, outputTokens: out,
                cacheCreationTokens: cc, cacheReadTokens: cr, costUSD: cost, model: model,
                messageId: mid, requestId: rid, sessionId: (json["sessionId"] as? String) ?? ""
            ))
        }
        return entries
    }
}
