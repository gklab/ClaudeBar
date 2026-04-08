import AppKit
import SwiftUI

/// Pure AppKit entry point — avoids SwiftUI App lifecycle issues with menu bar apps.
@main
enum ClaudeBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private var store: UsageStore!
    private var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = UsageStore(settings: settings)
        statusController = StatusItemController(store: store, settings: settings)
        store.startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopAutoRefresh()
    }
}
