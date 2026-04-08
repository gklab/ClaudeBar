import AppKit
import Foundation

/// Renders the menu bar icon with usage meter bars.
///
/// The icon is 18×18 pt (matching macOS system menu bar size).
/// - Top bar (thick): current session usage percentage
/// - Bottom bar (thin): daily usage indication
enum IconRenderer {
    /// Icon dimensions matching macOS menu bar.
    private static let iconSize = NSSize(width: 18, height: 18)

    /// Create a menu bar icon showing usage levels.
    /// - Parameters:
    ///   - sessionPercent: Current session usage (0.0 - 1.0)
    ///   - dailyPercent: Daily usage indication (0.0 - 1.0)
    ///   - stale: Whether data is stale (dims the icon)
    static func makeIcon(
        sessionPercent: Double,
        dailyPercent: Double = 0,
        stale: Bool = false
    ) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            let alpha: CGFloat = stale ? 0.4 : 1.0

            // Background rounded rect
            let bgRect = rect.insetBy(dx: 1, dy: 2)
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3)
            NSColor.labelColor.withAlphaComponent(0.12 * alpha).setFill()
            bgPath.fill()

            // Session bar (top, thick) - 4pt height
            let sessionBarY: CGFloat = 9
            let sessionBarHeight: CGFloat = 4
            let barInset: CGFloat = 3
            let barWidth = rect.width - barInset * 2
            let sessionFillWidth = barWidth * CGFloat(min(max(sessionPercent, 0), 1))

            let sessionBg = NSRect(x: barInset, y: sessionBarY, width: barWidth, height: sessionBarHeight)
            let sessionBgPath = NSBezierPath(roundedRect: sessionBg, xRadius: 1.5, yRadius: 1.5)
            NSColor.labelColor.withAlphaComponent(0.15 * alpha).setFill()
            sessionBgPath.fill()

            if sessionFillWidth > 0 {
                let sessionFill = NSRect(x: barInset, y: sessionBarY, width: sessionFillWidth, height: sessionBarHeight)
                let sessionFillPath = NSBezierPath(roundedRect: sessionFill, xRadius: 1.5, yRadius: 1.5)
                colorForPercent(sessionPercent).withAlphaComponent(alpha).setFill()
                sessionFillPath.fill()
            }

            // Daily bar (bottom, thin) - 2pt height
            let dailyBarY: CGFloat = 5
            let dailyBarHeight: CGFloat = 2
            let dailyFillWidth = barWidth * CGFloat(min(max(dailyPercent, 0), 1))

            let dailyBg = NSRect(x: barInset, y: dailyBarY, width: barWidth, height: dailyBarHeight)
            let dailyBgPath = NSBezierPath(roundedRect: dailyBg, xRadius: 1, yRadius: 1)
            NSColor.labelColor.withAlphaComponent(0.15 * alpha).setFill()
            dailyBgPath.fill()

            if dailyFillWidth > 0 {
                let dailyFill = NSRect(x: barInset, y: dailyBarY, width: dailyFillWidth, height: dailyBarHeight)
                let dailyFillPath = NSBezierPath(roundedRect: dailyFill, xRadius: 1, yRadius: 1)
                colorForPercent(dailyPercent).withAlphaComponent(alpha * 0.7).setFill()
                dailyFillPath.fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    /// Color based on usage percentage: green -> yellow -> orange -> red.
    private static func colorForPercent(_ percent: Double) -> NSColor {
        switch percent {
        case ..<0.5:
            return NSColor.systemGreen
        case ..<0.75:
            return NSColor.systemYellow
        case ..<0.9:
            return NSColor.systemOrange
        default:
            return NSColor.systemRed
        }
    }
}
