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
            toolbar
            progressIndicator
            content
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 400, idealHeight: 550)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(HistoryTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Spacer()

            if store.isLoadingHistory {
                loadingLabel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var loadingLabel: some View {
        let parts = store.loadingProgress.split(separator: "/")
        let done = parts.first.flatMap { Int($0) }
        let total = parts.last.flatMap { Int($0) }

        if let done, let total, total > 0 {
            Text("Loading \(done) of \(formatNumber(total)) files...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text("Scanning files...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if store.isLoadingHistory {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.accentColor.opacity(0.08))
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: geo.size.width * store.loadingPercent)
                        .animation(.linear(duration: 0.3), value: store.loadingPercent)
                }
            }
            .frame(height: 2)
        } else {
            Divider()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoadingHistory && !hasData(for: selectedTab) {
            loadingPlaceholder
        } else {
            switch selectedTab {
            case .hours:  HourlyTableView(data: store.hourlyUsage)
            case .days:   DailyTableView(data: store.dailyUsage)
            case .months: MonthlyTableView(data: store.monthlyUsage)
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 0) {
            shimmerHeader
            ForEach(0..<12, id: \.self) { i in shimmerRow(index: i) }
            Spacer()
        }
    }

    private var shimmerHeader: some View {
        HStack(spacing: 0) {
            ForEach(columnLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: label == columnLabels.first ? .leading : .center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var columnLabels: [String] {
        switch selectedTab {
        case .hours:  return ["Hour", "Msgs", "Input", "Output", "Cache R", "Total", "Cost"]
        case .days:   return ["Date", "Msgs", "Input", "Output", "Cache R", "Total", "Cost"]
        case .months: return ["Month", "Days", "Msgs", "Input", "Output", "Total", "Cost"]
        }
    }

    private func shimmerRow(index: Int) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04)).frame(width: 70, height: 10)
            Spacer()
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.03)).frame(width: CGFloat.random(in: 30...50), height: 10)
            }
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.05)).frame(width: 45, height: 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.015))
    }

    private func hasData(for tab: HistoryTab) -> Bool {
        switch tab {
        case .hours:  return !store.hourlyUsage.isEmpty
        case .days:   return store.dailyUsage.count > 1
        case .months: return !store.monthlyUsage.isEmpty
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Hourly Table

private struct HourlyTableView: View {
    let data: [HourlyUsage]

    var body: some View {
        if data.isEmpty {
            ContentUnavailableView("No data in last 24 hours", systemImage: "clock")
        } else {
            Table(data.reversed()) {
                TableColumn("Hour") { h in Text(fmtHour(h.hour)).monospacedDigit() }
                    .width(min: 85, ideal: 100)
                TableColumn("Msgs") { h in cell("\(h.messageCount)") }
                    .width(min: 40, ideal: 50)
                TableColumn("Input") { h in cell(fmtTok(h.inputTokens), .secondary) }
                    .width(min: 45, ideal: 55)
                TableColumn("Output") { h in cell(fmtTok(h.outputTokens), .secondary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Cache R") { h in cell(fmtTok(h.cacheTokens), .tertiary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Total") { h in cell(fmtTok(h.totalTokens)) }
                    .width(min: 50, ideal: 60)
                TableColumn("Cost") { h in costCell(h.totalCost) }
                    .width(min: 55, ideal: 65)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            summaryBar(
                label: "\(data.count) hours",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cache: data.reduce(0) { $0 + $1.cacheTokens },
                total: data.reduce(0) { $0 + $1.totalTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtHour(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.amSymbol = "am"; f.pmSymbol = "pm"
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'Today' ha" : "MMM d ha"
        return f.string(from: d)
    }
}

// MARK: - Daily Table

private struct DailyTableView: View {
    let data: [DailyUsage]

    var body: some View {
        if data.isEmpty {
            ContentUnavailableView("No daily data", systemImage: "calendar")
        } else {
            Table(data.reversed()) {
                TableColumn("Date") { d in Text(fmtDay(d.date)).monospacedDigit() }
                    .width(min: 85, ideal: 100)
                TableColumn("Msgs") { d in cell("\(d.messageCount)") }
                    .width(min: 40, ideal: 50)
                TableColumn("Input") { d in cell(fmtTok(d.inputTokens), .secondary) }
                    .width(min: 45, ideal: 55)
                TableColumn("Output") { d in cell(fmtTok(d.outputTokens), .secondary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Cache R") { d in cell(fmtTok(d.cacheTokens), .tertiary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Total") { d in cell(fmtTok(d.totalTokens)) }
                    .width(min: 50, ideal: 60)
                TableColumn("Cost") { d in costCell(d.totalCost) }
                    .width(min: 55, ideal: 65)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            summaryBar(
                label: "\(data.count) days",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cache: data.reduce(0) { $0 + $1.cacheTokens },
                total: data.reduce(0) { $0 + $1.totalTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtDay(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d (EEE)"; return f.string(from: d)
    }
}

// MARK: - Monthly Table

private struct MonthlyTableView: View {
    let data: [MonthlyUsage]

    var body: some View {
        if data.isEmpty {
            ContentUnavailableView("No monthly data", systemImage: "calendar.badge.clock")
        } else {
            Table(data.reversed()) {
                TableColumn("Month") { m in Text(fmtMonth(m.month)).monospacedDigit() }
                    .width(min: 75, ideal: 85)
                TableColumn("Days") { m in cell("\(m.dayCount)") }
                    .width(min: 35, ideal: 40)
                TableColumn("Msgs") { m in cell("\(m.messageCount)") }
                    .width(min: 45, ideal: 55)
                TableColumn("Input") { m in cell(fmtTok(m.inputTokens), .secondary) }
                    .width(min: 45, ideal: 55)
                TableColumn("Output") { m in cell(fmtTok(m.outputTokens), .secondary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Total") { m in cell(fmtTok(m.totalTokens)) }
                    .width(min: 50, ideal: 60)
                TableColumn("Cost") { m in costCell(m.totalCost) }
                    .width(min: 55, ideal: 65)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            summaryBar(
                label: "\(data.count) months",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cache: 0,
                total: data.reduce(0) { $0 + $1.totalTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM yyyy"; return f.string(from: d)
    }
}

// MARK: - Shared Helpers

private func cell(_ text: String, _ style: HierarchicalShapeStyle = .primary) -> some View {
    Text(text)
        .monospacedDigit()
        .foregroundStyle(style)
        .frame(maxWidth: .infinity, alignment: .center)
}

private func costCell(_ cost: Double) -> some View {
    Text(fmtCost(cost))
        .monospacedDigit()
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .center)
}

private func summaryBar(label: String, msgs: Int, input: Int, output: Int, cache: Int, total: Int, cost: Double) -> some View {
    HStack(spacing: 10) {
        Text(label).fontWeight(.semibold)
        Spacer()
        Text("\(msgs) msgs").foregroundStyle(.secondary)
        Text("In: \(fmtTok(input))").foregroundStyle(.secondary)
        Text("Out: \(fmtTok(output))").foregroundStyle(.secondary)
        if cache > 0 {
            Text("Cache: \(fmtTok(cache))").foregroundStyle(.tertiary)
        }
        Text("Total: \(fmtTok(total))")
        Text(fmtCost(cost)).fontWeight(.semibold)
    }
    .font(.system(size: 11).monospacedDigit())
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
}

private func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

private func fmtCost(_ c: Double) -> String {
    if c >= 1000 { return String(format: "$%.0f", c) }
    return String(format: "$%.2f", c)
}
