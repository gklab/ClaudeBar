import SwiftUI

enum HistoryTab: String, CaseIterable {
    case hours = "24 Hours"
    case days = "Daily"
    case months = "Monthly"
}

struct HistoryView: View {
    let store: UsageStore
    @State private var selectedTab: HistoryTab = .days

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(HistoryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                if store.isLoadingHistory {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Button {
                    store.loadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingHistory)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Content
            switch selectedTab {
            case .hours:
                HourlyTab(data: store.hourlyUsage)
            case .days:
                DailyTab(data: store.dailyUsage)
            case .months:
                MonthlyTab(data: store.monthlyUsage)
            }
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 400, idealHeight: 550)
        .onAppear {
            if store.dailyUsage.count <= 1 {
                store.loadHistory()
            }
        }
    }
}

// MARK: - 24 Hours Tab

private struct HourlyTab: View {
    let data: [HourlyUsage]

    var body: some View {
        if data.isEmpty {
            emptyView("No data in last 24 hours")
        } else {
            VStack(spacing: 0) {
                List {
                    headerRow(columns: hourColumns)
                        .listRowSeparator(.hidden)
                    ForEach(data.reversed()) { h in
                        row(columns: [
                            (fmtHour(h.hour), 80, .leading),
                            ("\(h.messageCount)", 45, .trailing),
                            (fmtTok(h.inputTokens), 55, .trailing),
                            (fmtTok(h.outputTokens), 60, .trailing),
                            (fmtTok(h.cacheTokens), 60, .trailing),
                            (fmtCost(h.totalCost), 65, .trailing),
                        ], cost: h.totalCost, maxCost: maxCost)
                    }
                }
                .listStyle(.plain)
                Divider()
                totalFooter(label: "\(data.count)h", msgs: totalMsgs, inp: totalInp, out: totalOut, cache: totalCache, cost: totalCost)
            }
        }
    }

    private var hourColumns: [(String, CGFloat, Alignment)] {
        [("Hour", 80, .leading), ("Msgs", 45, .trailing), ("Input", 55, .trailing),
         ("Output", 60, .trailing), ("Cache", 60, .trailing), ("Cost", 65, .trailing)]
    }

    private var maxCost: Double { data.map(\.totalCost).max() ?? 1 }
    private var totalMsgs: Int { data.reduce(0) { $0 + $1.messageCount } }
    private var totalInp: Int { data.reduce(0) { $0 + $1.inputTokens } }
    private var totalOut: Int { data.reduce(0) { $0 + $1.outputTokens } }
    private var totalCache: Int { data.reduce(0) { $0 + $1.cacheTokens } }
    private var totalCost: Double { data.reduce(0) { $0 + $1.totalCost } }

    private func fmtHour(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "ha"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        let today = Calendar.current.isDateInToday(d)
        let prefix = today ? "Today " : {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "MMM d "
            return df.string(from: d)
        }()
        return "\(prefix)\(f.string(from: d))"
    }
}

// MARK: - Daily Tab

private struct DailyTab: View {
    let data: [DailyUsage]

    var body: some View {
        if data.isEmpty {
            emptyView("No daily data")
        } else {
            VStack(spacing: 0) {
                List {
                    headerRow(columns: dayColumns)
                        .listRowSeparator(.hidden)
                    ForEach(data.reversed()) { d in
                        row(columns: [
                            (fmtDay(d.date), 95, .leading),
                            ("\(d.messageCount)", 45, .trailing),
                            (fmtTok(d.inputTokens), 55, .trailing),
                            (fmtTok(d.outputTokens), 60, .trailing),
                            (fmtTok(d.cacheTokens), 60, .trailing),
                            (fmtCost(d.totalCost), 65, .trailing),
                        ], cost: d.totalCost, maxCost: maxCost)
                    }
                }
                .listStyle(.plain)
                Divider()
                totalFooter(label: "\(data.count) days", msgs: totalMsgs, inp: totalInp, out: totalOut, cache: totalCache, cost: totalCost)
            }
        }
    }

    private var dayColumns: [(String, CGFloat, Alignment)] {
        [("Date", 95, .leading), ("Msgs", 45, .trailing), ("Input", 55, .trailing),
         ("Output", 60, .trailing), ("Cache", 60, .trailing), ("Cost", 65, .trailing)]
    }

    private var maxCost: Double { data.map(\.totalCost).max() ?? 1 }
    private var totalMsgs: Int { data.reduce(0) { $0 + $1.messageCount } }
    private var totalInp: Int { data.reduce(0) { $0 + $1.inputTokens } }
    private var totalOut: Int { data.reduce(0) { $0 + $1.outputTokens } }
    private var totalCache: Int { data.reduce(0) { $0 + $1.cacheTokens } }
    private var totalCost: Double { data.reduce(0) { $0 + $1.totalCost } }

    private func fmtDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d (EEE)"
        return f.string(from: d)
    }
}

// MARK: - Monthly Tab

private struct MonthlyTab: View {
    let data: [MonthlyUsage]

    var body: some View {
        if data.isEmpty {
            emptyView("No monthly data")
        } else {
            VStack(spacing: 0) {
                List {
                    headerRow(columns: monthColumns)
                        .listRowSeparator(.hidden)
                    ForEach(data.reversed()) { m in
                        row(columns: [
                            (fmtMonth(m.month), 85, .leading),
                            ("\(m.dayCount)d", 35, .trailing),
                            ("\(m.messageCount)", 50, .trailing),
                            (fmtTok(m.inputTokens), 55, .trailing),
                            (fmtTok(m.outputTokens), 60, .trailing),
                            (fmtCost(m.totalCost), 65, .trailing),
                        ], cost: m.totalCost, maxCost: maxCost)
                    }
                }
                .listStyle(.plain)
                Divider()
                HStack(spacing: 0) {
                    Text("Total")
                        .frame(width: 85, alignment: .leading).fontWeight(.semibold)
                    Text("\(totalDays)d").frame(width: 35, alignment: .trailing)
                    Text("\(totalMsgs)").frame(width: 50, alignment: .trailing)
                    Text(fmtTok(totalInp)).frame(width: 55, alignment: .trailing)
                    Text(fmtTok(totalOut)).frame(width: 60, alignment: .trailing)
                    Text(fmtCost(totalCost))
                        .frame(width: 65, alignment: .trailing).fontWeight(.semibold)
                    Spacer()
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private var monthColumns: [(String, CGFloat, Alignment)] {
        [("Month", 85, .leading), ("Days", 35, .trailing), ("Msgs", 50, .trailing),
         ("Input", 55, .trailing), ("Output", 60, .trailing), ("Cost", 65, .trailing)]
    }

    private var maxCost: Double { data.map(\.totalCost).max() ?? 1 }
    private var totalDays: Int { data.reduce(0) { $0 + $1.dayCount } }
    private var totalMsgs: Int { data.reduce(0) { $0 + $1.messageCount } }
    private var totalInp: Int { data.reduce(0) { $0 + $1.inputTokens } }
    private var totalOut: Int { data.reduce(0) { $0 + $1.outputTokens } }
    private var totalCost: Double { data.reduce(0) { $0 + $1.totalCost } }

    private func fmtMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Shared Helpers

private func emptyView(_ text: String) -> some View {
    VStack {
        Spacer()
        Text(text).foregroundStyle(.secondary)
        Spacer()
    }
}

private func headerRow(columns: [(String, CGFloat, Alignment)]) -> some View {
    HStack(spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
            Text(col.0).frame(width: col.1, alignment: col.2)
        }
        Spacer()
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
}

private func row(columns: [(String, CGFloat, Alignment)], cost: Double, maxCost: Double) -> some View {
    HStack(spacing: 0) {
        // First column (date/time) in primary color
        if let first = columns.first {
            Text(first.0).frame(width: first.1, alignment: first.2)
        }
        // Data columns in secondary color
        ForEach(Array(columns.dropFirst().dropLast().enumerated()), id: \.offset) { _, col in
            Text(col.0)
                .frame(width: col.1, alignment: col.2)
                .foregroundStyle(.secondary)
        }
        // Cost column with mini bar
        if let last = columns.last {
            HStack(spacing: 4) {
                let ratio = maxCost > 0 ? cost / maxCost : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(ratio))
                    .frame(width: CGFloat(ratio) * 40, height: 10)
                Spacer()
                Text(last.0)
            }
            .frame(width: last.1 + 50, alignment: .trailing)
        }
    }
    .font(.system(size: 12).monospacedDigit())
}

private func totalFooter(label: String, msgs: Int, inp: Int, out: Int, cache: Int, cost: Double) -> some View {
    HStack(spacing: 0) {
        Text(label).frame(width: 95, alignment: .leading).fontWeight(.semibold)
        Text("\(msgs)").frame(width: 45, alignment: .trailing)
        Text(fmtTok(inp)).frame(width: 55, alignment: .trailing)
        Text(fmtTok(out)).frame(width: 60, alignment: .trailing)
        Text(fmtTok(cache)).frame(width: 60, alignment: .trailing)
        Text(fmtCost(cost)).frame(width: 65, alignment: .trailing).fontWeight(.semibold)
        Spacer()
    }
    .font(.system(size: 12).monospacedDigit())
    .padding(.horizontal)
    .padding(.vertical, 8)
}

private func barColor(_ ratio: Double) -> Color {
    switch ratio {
    case ..<0.25: return .green.opacity(0.5)
    case ..<0.5: return .yellow.opacity(0.6)
    case ..<0.75: return .orange.opacity(0.6)
    default: return .red.opacity(0.6)
    }
}

private func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

private func fmtCost(_ c: Double) -> String { String(format: "$%.2f", c) }
