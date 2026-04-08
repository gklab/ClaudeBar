import Foundation

/// Pure data aggregation — no I/O, can be called from any thread.
enum UsageAggregator {
    static func buildDailyUsage(from entries: [UsageEntry]) -> [DailyUsage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return grouped.map { (date, entries) in
            DailyUsage(id: fmt.string(from: date), date: date,
                       entries: entries.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.date < $1.date }
    }

    static func buildHourlyUsage(from entries: [UsageEntry]) -> [HourlyUsage] {
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

    static func buildMonthlyUsage(from entries: [UsageEntry]) -> [MonthlyUsage] {
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
}
