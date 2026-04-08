import Foundation

/// Aggregated session block representing a 5-hour usage window (Claude Code session duration).
struct SessionBlock: Sendable, Identifiable {
    let id: String
    let startTime: Date
    let endTime: Date
    let entries: [UsageEntry]
    let isActive: Bool

    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheCreationTokens: Int { entries.reduce(0) { $0 + $1.cacheCreationTokens } }
    var cacheReadTokens: Int { entries.reduce(0) { $0 + $1.cacheReadTokens } }
    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.costUSD } }
    var messageCount: Int { entries.count }

    var durationMinutes: Double {
        max(endTime.timeIntervalSince(startTime) / 60, 1.0)
    }

    var tokensPerMinute: Double {
        guard durationMinutes > 0 else { return 0 }
        return Double(totalTokens) / durationMinutes
    }

    var costPerHour: Double {
        guard durationMinutes > 0 else { return 0 }
        return (totalCost / durationMinutes) * 60
    }

    /// Models used in this session, deduplicated.
    var models: [String] {
        Array(Set(entries.map(\.model))).sorted()
    }
}

/// Daily aggregated usage.
struct DailyUsage: Sendable, Identifiable {
    let id: String
    let date: Date
    let entries: [UsageEntry]

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheTokens: Int { entries.reduce(0) { $0 + $1.cacheCreationTokens + $1.cacheReadTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.costUSD } }
    var messageCount: Int { entries.count }
}

/// Hourly aggregated usage.
struct HourlyUsage: Sendable, Identifiable {
    let id: String // e.g. "2025-01-15 14"
    let hour: Date
    let entries: [UsageEntry]

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheTokens: Int { entries.reduce(0) { $0 + $1.cacheCreationTokens + $1.cacheReadTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.costUSD } }
    var messageCount: Int { entries.count }
}

/// Monthly aggregated usage.
struct MonthlyUsage: Sendable, Identifiable {
    let id: String // e.g. "2025-01"
    let month: Date
    let entries: [UsageEntry]

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheTokens: Int { entries.reduce(0) { $0 + $1.cacheCreationTokens + $1.cacheReadTokens } }
    var totalCost: Double { entries.reduce(0) { $0 + $1.costUSD } }
    var messageCount: Int { entries.count }
    var dayCount: Int {
        Set(entries.map { Calendar.current.startOfDay(for: $0.timestamp) }).count
    }
}
