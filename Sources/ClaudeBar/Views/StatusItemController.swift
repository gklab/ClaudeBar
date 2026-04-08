import AppKit
import SwiftUI

/// Manages the NSStatusItem in the macOS menu bar.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private let settings: SettingsStore
    private var preferencesWindow: NSWindow?
    private var historyWindow: NSWindow?

    init(store: UsageStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupStatusItem()
        buildMenu()
        startObserving()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.imageScaling = .scaleNone
        updateIcon()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
        statusItem.menu = menu
    }

    // MARK: - Menu

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Header with API status on the right
        do {
            let item = NSMenuItem(title: "ClaudeBar", action: nil, keyEquivalent: "")
            item.isEnabled = false

            let header = NSMutableAttributedString()
            let name = store.displayName.isEmpty ? "ClaudeBar" : store.displayName
            header.append(NSAttributedString(string: "\(name) — \(settings.plan.rawValue)", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]))

            // Data source indicator
            let sourceColor: NSColor = store.apiError != nil ? .systemOrange : .tertiaryLabelColor
            header.append(NSAttributedString(string: "   \(store.dataSourceLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: sourceColor,
            ]))

            item.attributedTitle = header
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        // ── 5-Hour Window ──
        addSectionHeader(menu, title: "5-Hour Window")
        let pct5 = Int(store.effective5hPercent)
        let estMark = store.isEstimated ? " ~" : ""
        addBarItem(menu, label: "\(pct5)%\(estMark)", percent: store.sessionUsagePercent)
        if let resetsAt = store.fiveHourResetsAt {
            addDetailItem(menu, text: "Resets \(formatResetDate(resetsAt))")
        }

        // Token breakdown
        let se = store.currentSessionEntries
        if !se.isEmpty {
            let inp = se.reduce(0) { $0 + $1.inputTokens }
            let out = se.reduce(0) { $0 + $1.outputTokens }
            let cw = se.reduce(0) { $0 + $1.cacheCreationTokens }
            let cr = se.reduce(0) { $0 + $1.cacheReadTokens }
            addDetailItem(menu, text: "In: \(fmtTok(inp))  Out: \(fmtTok(out))  Cache: \(fmtTok(cw))/\(fmtTok(cr))")
            addDetailItem(menu, text: "\(store.currentSessionMessages) msgs  ~\(fmtCost(store.currentSessionCost)) est.")

            if !store.currentSessionModels.isEmpty {
                let models = store.currentSessionModels.map { shortModel($0) }.joined(separator: ", ")
                addDetailItem(menu, text: models)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // ── 7-Day Window ──
        addSectionHeader(menu, title: "7-Day Window")
        let pct7 = Int(store.effective7dPercent)
        let est7 = store.isEstimated ? " ~" : ""
        addBarItem(menu, label: "\(pct7)%\(est7)", percent: store.weeklyUsagePercent)
        if let resetsAt = store.sevenDayResetsAt {
            addDetailItem(menu, text: "Resets \(formatResetDate(resetsAt))")
        }

        // ── 7-Day Sonnet (if has usage) ──
        if store.sevenDaySonnetPercent > 0 {
            addSectionHeader(menu, title: "7-Day Sonnet")
            addBarItem(menu, label: "\(Int(store.sevenDaySonnetPercent))%", percent: store.sevenDaySonnetPercent / 100)
            if let resetsAt = store.sevenDaySonnetResetsAt {
                addDetailItem(menu, text: "Resets \(formatResetDate(resetsAt))")
            }
        }

        // ── Extra Usage ──
        if let extra = store.extraUsage, extra.isEnabled {
            menu.addItem(NSMenuItem.separator())
            addSectionHeader(menu, title: "Extra Usage")
            let spent = extra.usedCredits / 100
            let limit = Double(extra.monthlyLimit) / 100
            addBarItem(menu, label: "\(fmtCost(spent)) / \(fmtCost(limit))", percent: extra.utilization / 100)
        }

        // ── Actions ──
        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "Daily History...", action: #selector(historyAction), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(preferencesAction), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClaudeBar", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Helpers

    private func addSectionHeader(_ menu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        menu.addItem(item)
    }

    private func addDetailItem(_ menu: NSMenu, text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: "  \(text)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(item)
    }

    /// Compact progress bar with label on the same line.
    private func addBarItem(_ menu: NSMenu, label: String, percent: Double) {
        let barLen = 20
        let filled = Int(Double(barLen) * min(max(percent, 0), 1.0))
        let empty = barLen - filled
        let bar = String(repeating: "\u{2589}", count: filled) + String(repeating: "\u{2581}", count: empty)

        let color: NSColor
        switch percent {
        case ..<0.5: color = .systemGreen
        case ..<0.75: color = .systemYellow
        case ..<0.9: color = .systemOrange
        default: color = .systemRed
        }

        let attrStr = NSMutableAttributedString()
        attrStr.append(NSAttributedString(string: "  \(bar) ", attributes: [
            .font: NSFont.systemFont(ofSize: 9), .foregroundColor: color,
        ]))
        attrStr.append(NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]))

        let item = NSMenuItem(title: "\(bar) \(label)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = attrStr
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func refreshAction() { store.refresh() }

    @objc private func historyAction() {
        // Reuse existing window if it still exists
        if let existing = historyWindow {
            // Update content in case store changed
            existing.contentView = NSHostingView(rootView: HistoryView(store: store))
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "ClaudeBar — Daily History"
        window.contentView = NSHostingView(rootView: HistoryView(store: store))
        window.isReleasedWhenClosed = false  // Keep window object alive after close
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func preferencesAction() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PreferencesView(settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "ClaudeBar Preferences"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }

    @objc private func quitAction() { NSApp.terminate(nil) }

    // MARK: - Icon

    private func startObserving() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isStale = store.lastUpdated.map { Date().timeIntervalSince($0) > 120 } ?? true

        button.image = IconRenderer.makeIcon(
            sessionPercent: store.sessionUsagePercent,
            dailyPercent: store.weeklyUsagePercent,
            stale: isStale
        )
        button.title = " \(store.statusText)"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.toolTip = "ClaudeBar — 5h: \(Int(store.effective5hPercent))%  7d: \(Int(store.effective7dPercent))%"
    }

    // MARK: - Formatting

    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func fmtCost(_ c: Double) -> String { String(format: "$%.2f", c) }

    private func formatResetDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d 'at' ha"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        f.timeZone = .current
        return "\(f.string(from: date)) (\(TimeZone.current.identifier))"
    }

    private func shortModel(_ m: String) -> String {
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return m
    }
}

// MARK: - NSMenuDelegate

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
    }
}
