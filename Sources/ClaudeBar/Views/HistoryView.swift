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
            // Toolbar area: centered segmented picker with progress text
            toolbar

            // Thin progress bar (Safari-style) or divider
            progressIndicator

            // Main content area
            content
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 400, idealHeight: 550)
        // Data is loaded at startup; loadHistory is a no-op if cache is ready
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

    // MARK: - Progress Indicator

    @ViewBuilder
    private var progressIndicator: some View {
        if store.isLoadingHistory {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.08))

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

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 0) {
            // Shimmer rows to suggest table structure
            shimmerHeader

            ForEach(0..<12, id: \.self) { index in
                shimmerRow(index: index)
            }

            Spacer()
        }
    }

    // MARK: - Shimmer Skeleton

    private var shimmerHeader: some View {
        HStack(spacing: 0) {
            ForEach(columnLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: label == columnLabels.first ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var columnLabels: [String] {
        switch selectedTab {
        case .hours:  return ["Hour", "Msgs", "Input", "Output", "Cost"]
        case .days:   return ["Date", "Msgs", "Input", "Output", "Cache", "Cost"]
        case .months: return ["Month", "Days", "Msgs", "Input", "Output", "Cost"]
        }
    }

    private func shimmerRow(index: Int) -> some View {
        HStack(spacing: 12) {
            // Mimic column widths with placeholder rectangles
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.04))
                .frame(width: 70, height: 10)

            Spacer()

            ForEach(0..<(selectedTab == .hours ? 3 : 4), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: CGFloat.random(in: 30...50), height: 10)
            }

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.05))
                .frame(width: 45, height: 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.015))
    }

    // MARK: - Helpers

    private func hasData(for tab: HistoryTab) -> Bool {
        switch tab {
        case .hours:  return !store.hourlyUsage.isEmpty
        case .days:   return store.dailyUsage.count > 1
        case .months: return !store.monthlyUsage.isEmpty
        }
    }

    private var estimatedTimeRemaining: String {
        // Very rough estimate based on linear progress
        guard store.loadingPercent > 0.05 else { return "" }
        // We don't track elapsed time, so just show a qualitative hint
        let remaining = 1.0 - store.loadingPercent
        if remaining < 0.1 { return "Almost done..." }
        if remaining < 0.3 { return "Finishing up..." }
        return ""
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
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
                TableColumn("Hour") { h in
                    Text(fmtHour(h.hour))
                        .monospacedDigit()
                }
                .width(min: 90, ideal: 110)

                TableColumn("Msgs") { h in
                    Text("\(h.messageCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 45, ideal: 55)

                TableColumn("Input") { h in
                    Text(fmtTok(h.inputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Output") { h in
                    Text(fmtTok(h.outputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Cost") { h in
                    costCell(h.totalCost)
                }
                .width(min: 60, ideal: 75)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            summaryBar(
                label: "\(data.count) hours",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtHour(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.amSymbol = "am"
        f.pmSymbol = "pm"
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
                TableColumn("Date") { d in
                    Text(fmtDay(d.date))
                        .monospacedDigit()
                }
                .width(min: 95, ideal: 110)

                TableColumn("Msgs") { d in
                    Text("\(d.messageCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 45, ideal: 55)

                TableColumn("Input") { d in
                    Text(fmtTok(d.inputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Output") { d in
                    Text(fmtTok(d.outputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Cache") { d in
                    Text(fmtTok(d.cacheTokens))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Cost") { d in
                    costCell(d.totalCost)
                }
                .width(min: 60, ideal: 75)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            summaryBar(
                label: "\(data.count) days",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d (EEE)"
        return f.string(from: d)
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
                TableColumn("Month") { m in
                    Text(fmtMonth(m.month))
                        .monospacedDigit()
                }
                .width(min: 85, ideal: 100)

                TableColumn("Days") { m in
                    Text("\(m.dayCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 40, ideal: 45)

                TableColumn("Msgs") { m in
                    Text("\(m.messageCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 60)

                TableColumn("Input") { m in
                    Text(fmtTok(m.inputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Output") { m in
                    Text(fmtTok(m.outputTokens))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Cost") { m in
                    costCell(m.totalCost)
                }
                .width(min: 60, ideal: 75)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            summaryBar(
                label: "\(data.count) months",
                msgs: data.reduce(0) { $0 + $1.messageCount },
                input: data.reduce(0) { $0 + $1.inputTokens },
                output: data.reduce(0) { $0 + $1.outputTokens },
                cost: data.reduce(0) { $0 + $1.totalCost }
            )
        }
    }

    private func fmtMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Shared Helpers

private func costCell(_ cost: Double) -> some View {
    Text(fmtCost(cost))
        .monospacedDigit()
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .trailing)
}

private func summaryBar(label: String, msgs: Int, input: Int, output: Int, cost: Double) -> some View {
    HStack(spacing: 12) {
        Text(label)
            .fontWeight(.semibold)
        Spacer()
        Text("\(msgs) msgs")
            .foregroundStyle(.secondary)
        Text("In: \(fmtTok(input))")
            .foregroundStyle(.secondary)
        Text("Out: \(fmtTok(output))")
            .foregroundStyle(.secondary)
        Text(fmtCost(cost))
            .fontWeight(.semibold)
    }
    .font(.system(size: 12).monospacedDigit())
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
}

private func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

private func fmtCost(_ c: Double) -> String {
    String(format: "$%.2f", c)
}
