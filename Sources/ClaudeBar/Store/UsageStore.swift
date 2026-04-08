import Foundation
import Observation

/// Central observable state container.
/// API for authoritative percentages (low frequency), local JSONL for token details (high frequency).
/// When API is unavailable, estimates percentage from local tokens using a calibration factor.
@MainActor
@Observable
final class UsageStore {
    // API data (authoritative, refreshed every 2 min)
    private(set) var fiveHourPercent: Double = 0
    private(set) var fiveHourResetsAt: Date?
    private(set) var sevenDayPercent: Double = 0
    private(set) var sevenDayResetsAt: Date?
    private(set) var extraUsage: UsageAPI.ExtraUsage?
    private(set) var apiError: String?
    private(set) var lastAPIUpdate: Date?

    // Local JSONL data (for token breakdown, refreshed every 30s)
    private(set) var entries: [UsageEntry] = []
    private(set) var dailyUsage: [DailyUsage] = []
    private(set) var hourlyUsage: [HourlyUsage] = []
    private(set) var monthlyUsage: [MonthlyUsage] = []
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var isLoadingHistory = false

    /// Whether the current 5h percentage is estimated (not from API).
    private(set) var isEstimated = false

    private let reader: UsageReader
    private let settings: SettingsStore
    private var localTimer: Timer?
    private var apiTimer: Timer?

    /// Base API interval: 5 minutes. Doubles on each 429, up to 30 min.
    private static let apiBaseInterval: TimeInterval = 300
    private var apiCurrentInterval: TimeInterval = 300
    private static let calibrationKey = "claudebar_cost_per_percent"

    /// Calibration: how much cost (USD) = 1% of the 5h limit.
    /// Cost naturally weights input/output/model correctly.
    /// Persisted to UserDefaults so it survives restarts.
    private var costPerPercent: Double {
        get { UserDefaults.standard.double(forKey: Self.calibrationKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.calibrationKey) }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        let path = NSString(string: settings.dataPath).expandingTildeInPath
        self.reader = UsageReader(dataPath: URL(fileURLWithPath: path))
    }

    // MARK: - Computed

    var sessionUsagePercent: Double { fiveHourPercent / 100.0 }
    var weeklyUsagePercent: Double { sevenDayPercent / 100.0 }

    var sessionResetIn: TimeInterval? {
        guard let resetsAt = fiveHourResetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    var weeklyResetIn: TimeInterval? {
        guard let resetsAt = sevenDayResetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    var currentSessionEntries: [UsageEntry] {
        let windowStart = Date().addingTimeInterval(-Double(ClaudePlan.sessionWindowHours) * 3600)
        return entries.filter { $0.timestamp >= windowStart }
    }

    var currentSessionBillableTokens: Int {
        currentSessionEntries.reduce(0) { $0 + $1.billableTokens }
    }
    var currentSessionMessages: Int { currentSessionEntries.count }
    var currentSessionCost: Double { currentSessionEntries.reduce(0) { $0 + $1.costUSD } }

    /// Cost of only input+output tokens (no cache) — used for calibration.
    var currentSessionIOCost: Double {
        currentSessionEntries.reduce(0) { total, entry in
            total + CostCalculator.calculateCost(
                model: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
        }
    }
    var currentSessionModels: [String] {
        Array(Set(currentSessionEntries.map(\.model))).sorted()
    }

    var todayCost: Double { dailyUsage.last?.totalCost ?? 0 }
    var todayTokens: Int { dailyUsage.last?.totalTokens ?? 0 }

    var statusText: String {
        if isLoading && lastUpdated == nil && lastAPIUpdate == nil { return "..." }
        let pct = Int(fiveHourPercent)
        if lastAPIUpdate != nil || isEstimated {
            let prefix = isEstimated ? "~" : ""
            return "\(prefix)\(pct)%"
        }
        return "—"
    }

    var activeSession: SessionBlock? { nil }

    // MARK: - Lifecycle

    func startAutoRefresh() {
        refreshAPI()
        refreshLocal()

        scheduleAPITimer()

        localTimer?.invalidate()
        localTimer = Timer.scheduledTimer(
            withTimeInterval: Double(settings.refreshIntervalSeconds), repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLocal() }
        }
    }

    func stopAutoRefresh() {
        apiTimer?.invalidate()
        apiTimer = nil
        localTimer?.invalidate()
        localTimer = nil
    }

    func refresh() {
        refreshAPI()
        refreshLocal()
    }

    // MARK: - API Refresh

    private func scheduleAPITimer() {
        apiTimer?.invalidate()
        apiTimer = Timer.scheduledTimer(withTimeInterval: apiCurrentInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAPI()
                self?.scheduleAPITimer()
            }
        }
    }

    private func refreshAPI() {
        Task {
            if let usage = await UsageAPI.fetchUsage() {
                let apiPct = usage.fiveHour?.utilization ?? 0
                self.fiveHourPercent = apiPct
                self.fiveHourResetsAt = usage.fiveHour?.resetsAt
                self.sevenDayPercent = usage.sevenDay?.utilization ?? 0
                self.sevenDayResetsAt = usage.sevenDay?.resetsAt
                self.extraUsage = usage.extraUsage
                self.lastAPIUpdate = Date()
                self.apiError = nil
                self.isEstimated = false

                // Success: reset interval to base
                self.apiCurrentInterval = Self.apiBaseInterval

                // Calibrate
                let ioCost = self.currentSessionIOCost
                if apiPct > 1 && ioCost > 0.01 {
                    let newCPP = ioCost / apiPct
                    self.costPerPercent = newCPP
                    NSLog("[ClaudeBar] Calibrated: $\(String(format: "%.4f", newCPP))/percent")
                }

                NSLog("[ClaudeBar] API: 5h=\(apiPct)%, 7d=\(self.sevenDayPercent)%")
            } else {
                self.apiError = "API unavailable"
                // Backoff: double interval, max 30 min
                self.apiCurrentInterval = min(self.apiCurrentInterval * 2, 1800)
                NSLog("[ClaudeBar] API failed, next try in \(Int(self.apiCurrentInterval))s")
                estimateFromLocal()
            }
        }
    }

    /// Estimate 5h percentage from local IO cost using calibration factor.
    private func estimateFromLocal() {
        let cpp = costPerPercent
        guard cpp > 0 else { return }

        let ioCost = currentSessionIOCost
        let estimated = ioCost / cpp
        self.fiveHourPercent = min(estimated, 200) // allow >100% to show overuse
        self.isEstimated = true
    }

    // MARK: - Local JSONL Refresh

    private func refreshLocal() {
        guard !isLoading else { return }
        isLoading = true

        Task.detached(priority: .background) { [reader = self.reader] in
            let recent = await reader.loadEntries(hoursBack: 6)
            let daily = await reader.buildDailyUsage(from: recent)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = recent
                let historyDays = self.dailyUsage.filter { d in
                    !daily.contains(where: { $0.id == d.id })
                }
                self.dailyUsage = (historyDays + daily).sorted { $0.date < $1.date }
                self.lastUpdated = Date()
                self.isLoading = false

                // If API is stale, re-estimate
                if self.isEstimated || self.lastAPIUpdate == nil {
                    self.estimateFromLocal()
                }
            }
        }
    }

    // MARK: - History (on demand)

    func loadHistory() {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true

        Task.detached(priority: .background) { [reader = self.reader] in
            let all = await reader.loadAllEntries()
            let daily = await reader.buildDailyUsage(from: all)
            let monthly = await reader.buildMonthlyUsage(from: all)

            let last24h = all.filter { $0.timestamp > Date().addingTimeInterval(-86400) }
            let hourly = await reader.buildHourlyUsage(from: last24h)

            await MainActor.run { [weak self] in
                self?.dailyUsage = daily
                self?.monthlyUsage = monthly
                self?.hourlyUsage = hourly
                self?.isLoadingHistory = false
                NSLog("[ClaudeBar] History: \(daily.count) days, \(monthly.count) months, \(hourly.count) hours")
            }
        }
    }
}
