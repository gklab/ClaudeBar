import Foundation
import Observation

/// Central observable state container.
/// Uses UsageCache for efficient data access: full scan once, then incremental updates.
@MainActor
@Observable
final class UsageStore {
    // API data
    private(set) var fiveHourPercent: Double = 0
    private(set) var fiveHourResetsAt: Date?
    private(set) var sevenDayPercent: Double = 0
    private(set) var sevenDayResetsAt: Date?
    private(set) var extraUsage: UsageAPI.ExtraUsage?
    private(set) var apiError: String?
    private(set) var lastAPIUpdate: Date?

    // Cached aggregated data (derived from UsageCache, updated on refresh)
    private(set) var entries: [UsageEntry] = []
    private(set) var dailyUsage: [DailyUsage] = []
    private(set) var hourlyUsage: [HourlyUsage] = []
    private(set) var monthlyUsage: [MonthlyUsage] = []
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var isLoadingHistory = false
    private(set) var isEstimated = false
    private(set) var loadingProgress: String = ""
    private(set) var loadingPercent: Double = 0

    private let cache: UsageCache
    private let settings: SettingsStore
    private var localTimer: Timer?

    private static let cal5hKey = "claudebar_cost_per_percent_5h"
    private static let cal7dKey = "claudebar_cost_per_percent_7d"
    private static let reset5hKey = "claudebar_last_reset_5h"
    private static let reset7dKey = "claudebar_last_reset_7d"

    private var costPerPercent5h: Double {
        get { UserDefaults.standard.double(forKey: Self.cal5hKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cal5hKey) }
    }
    private var costPerPercent7d: Double {
        get { UserDefaults.standard.double(forKey: Self.cal7dKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cal7dKey) }
    }
    private var savedResetAt5h: Date? {
        get { UserDefaults.standard.object(forKey: Self.reset5hKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.reset5hKey) }
    }
    private var savedResetAt7d: Date? {
        get { UserDefaults.standard.object(forKey: Self.reset7dKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.reset7dKey) }
    }

    private static let window5h: TimeInterval = 5 * 3600
    private static let window7d: TimeInterval = 7 * 24 * 3600

    init(settings: SettingsStore) {
        self.settings = settings
        let path = NSString(string: settings.dataPath).expandingTildeInPath
        let reader = UsageReader(dataPath: URL(fileURLWithPath: path))
        self.cache = UsageCache(reader: reader)

        // Restore reset times
        if let saved = savedResetAt5h {
            fiveHourResetsAt = Self.projectReset(from: saved, period: Self.window5h)
        }
        if let saved = savedResetAt7d {
            sevenDayResetsAt = Self.projectReset(from: saved, period: Self.window7d)
        }
    }

    private static func projectReset(from knownReset: Date, period: TimeInterval) -> Date {
        var next = knownReset
        while next < Date() { next = next.addingTimeInterval(period) }
        return next
    }

    // MARK: - Expiry

    private var is5hExpired: Bool {
        guard let r = fiveHourResetsAt else { return false }; return Date() > r
    }
    private var is7dExpired: Bool {
        guard let r = sevenDayResetsAt else { return false }; return Date() > r
    }

    var effective5hPercent: Double { is5hExpired && !isEstimated ? 0 : fiveHourPercent }
    var effective7dPercent: Double { is7dExpired && !isEstimated ? 0 : sevenDayPercent }
    var sessionUsagePercent: Double { effective5hPercent / 100.0 }
    var weeklyUsagePercent: Double { effective7dPercent / 100.0 }

    var sessionResetIn: TimeInterval? {
        guard let r = fiveHourResetsAt, Date() < r else { return nil }; return r.timeIntervalSinceNow
    }
    var weeklyResetIn: TimeInterval? {
        guard let r = sevenDayResetsAt, Date() < r else { return nil }; return r.timeIntervalSinceNow
    }

    // MARK: - Session data (from cached entries)

    var currentSessionEntries: [UsageEntry] {
        let start = Date().addingTimeInterval(-Double(ClaudePlan.sessionWindowHours) * 3600)
        return entries.filter { $0.timestamp >= start }
    }
    var currentSessionMessages: Int { currentSessionEntries.count }
    var currentSessionCost: Double { currentSessionEntries.reduce(0) { $0 + $1.costUSD } }
    var currentSessionModels: [String] { Array(Set(currentSessionEntries.map(\.model))).sorted() }
    var currentSessionIOCost: Double {
        currentSessionEntries.reduce(0) { $0 + CostCalculator.calculateCost(
            model: $1.model, inputTokens: $1.inputTokens, outputTokens: $1.outputTokens,
            cacheCreationTokens: 0, cacheReadTokens: 0) }
    }
    var sevenDayIOCost: Double {
        let start = Date().addingTimeInterval(-7 * 24 * 3600)
        return entries.filter { $0.timestamp >= start }.reduce(0) { $0 + CostCalculator.calculateCost(
            model: $1.model, inputTokens: $1.inputTokens, outputTokens: $1.outputTokens,
            cacheCreationTokens: 0, cacheReadTokens: 0) }
    }

    var todayCost: Double { dailyUsage.last(where: { Calendar.current.isDateInToday($0.date) })?.totalCost ?? 0 }
    var todayTokens: Int { dailyUsage.last(where: { Calendar.current.isDateInToday($0.date) })?.totalTokens ?? 0 }

    var statusText: String {
        if isLoading && lastUpdated == nil && lastAPIUpdate == nil { return "..." }
        if lastAPIUpdate != nil || isEstimated {
            return (isEstimated ? "~" : "") + "\(Int(effective5hPercent))%"
        }
        return "—"
    }

    var dataSourceLabel: String {
        if let t = lastAPIUpdate {
            if is5hExpired { return isEstimated ? "est. (reset)" : "API expired" }
            let s = Int(Date().timeIntervalSince(t))
            return "API \(s < 60 ? "\(s)s" : "\(s/60)m") ago"
        }
        if isEstimated { return "est." }
        return "no data"
    }

    // MARK: - Lifecycle

    func startAutoRefresh() {
        refreshAPI()
        startFullScan()

        localTimer?.invalidate()
        localTimer = Timer.scheduledTimer(
            withTimeInterval: Double(settings.refreshIntervalSeconds), repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIncremental() }
        }
    }

    func stopAutoRefresh() {
        localTimer?.invalidate()
        localTimer = nil
    }

    func refresh() {
        refreshAPI()
        refreshIncremental()
    }

    // MARK: - API

    private func refreshAPI() {
        Task {
            if let usage = await UsageAPI.fetchUsage() {
                let pct5 = usage.fiveHour?.utilization ?? 0
                fiveHourPercent = pct5
                fiveHourResetsAt = usage.fiveHour?.resetsAt
                let pct7 = usage.sevenDay?.utilization ?? 0
                sevenDayPercent = pct7
                sevenDayResetsAt = usage.sevenDay?.resetsAt
                extraUsage = usage.extraUsage
                lastAPIUpdate = Date()
                apiError = nil
                isEstimated = false

                if let r5 = usage.fiveHour?.resetsAt { savedResetAt5h = r5 }
                if let r7 = usage.sevenDay?.resetsAt { savedResetAt7d = r7 }

                // Calibrate
                let io5 = currentSessionIOCost
                if pct5 > 1 && io5 > 0.01 { costPerPercent5h = io5 / pct5 }
                let io7 = sevenDayIOCost
                if pct7 > 1 && io7 > 0.01 { costPerPercent7d = io7 / pct7 }

                // API percentages logged only at debug level
            } else {
                apiError = "API unavailable"
                if is5hExpired, let s = savedResetAt5h { fiveHourResetsAt = Self.projectReset(from: s, period: Self.window5h) }
                if is7dExpired, let s = savedResetAt7d { sevenDayResetsAt = Self.projectReset(from: s, period: Self.window7d) }
                estimateFromLocal()
            }
        }
    }

    private func estimateFromLocal() {
        if is5hExpired, let s = savedResetAt5h { fiveHourResetsAt = Self.projectReset(from: s, period: Self.window5h) }
        if is7dExpired, let s = savedResetAt7d { sevenDayResetsAt = Self.projectReset(from: s, period: Self.window7d) }
        if costPerPercent5h > 0 { fiveHourPercent = min(currentSessionIOCost / costPerPercent5h, 200) }
        if costPerPercent7d > 0 { sevenDayPercent = min(sevenDayIOCost / costPerPercent7d, 200) }
        isEstimated = true
    }

    // MARK: - Full scan (once at startup, populates cache)

    private func startFullScan() {
        isLoadingHistory = true
        loadingPercent = 0

        Task.detached(priority: .background) { [cache = self.cache] in
            // Progress callback
            await cache.setProgress { [weak self] done, total in
                let pct = total > 0 ? Double(done) / Double(total) : 0
                Task { @MainActor in
                    self?.loadingPercent = pct
                    self?.loadingProgress = "\(done)/\(total)"
                }
            }

            // Data callback — called progressively as batches are processed
            await cache.setDataCallback { [weak self] entries, daily, hourly, monthly in
                Task { @MainActor in
                    guard let self else { return }
                    self.entries = entries
                    self.dailyUsage = daily
                    self.hourlyUsage = hourly
                    self.monthlyUsage = monthly
                    self.lastUpdated = Date()

                    if self.isEstimated || self.lastAPIUpdate == nil {
                        self.estimateFromLocal()
                    }
                }
            }

            await cache.fullScan()

            await MainActor.run { [weak self] in
                self?.isLoadingHistory = false
                self?.loadingProgress = ""
                self?.loadingPercent = 0
                NSLog("[ClaudeBar] Cache ready: \(self?.dailyUsage.count ?? 0) days")
            }
        }
    }

    // MARK: - Incremental refresh (every 30s, only today changes)

    private func refreshIncremental() {
        guard !isLoading else { return }
        isLoading = true

        Task.detached(priority: .background) { [cache = self.cache] in
            // Only re-scans files modified in last 6h
            await cache.refreshRecent()

            let entries = await cache.getEntries(hoursBack: 168)
            let daily = await cache.getDailyUsage()
            let hourly = await cache.getHourlyUsage(hoursBack: 24)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = entries
                self.dailyUsage = daily
                self.hourlyUsage = hourly
                self.lastUpdated = Date()
                self.isLoading = false

                if self.isEstimated || self.lastAPIUpdate == nil || self.is5hExpired {
                    self.estimateFromLocal()
                }
            }
        }
    }

    // MARK: - History (no-op if cache ready, otherwise triggers scan)

    func loadHistory() {
        Task {
            let done = await cache.isFullScanDone
            if done {
                // Cache already has everything, just refresh views
                let daily = await cache.getDailyUsage()
                let monthly = await cache.getMonthlyUsage()
                let hourly = await cache.getHourlyUsage(hoursBack: 24)
                self.dailyUsage = daily
                self.monthlyUsage = monthly
                self.hourlyUsage = hourly
            } else if !isLoadingHistory {
                startFullScan()
            }
        }
    }
}
