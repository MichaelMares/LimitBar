import SwiftUI

struct LimitBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — the app lives entirely in the menu bar (see AppDelegate).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var store: UsageStore?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        let settings = AppSettings()
        let store = UsageStore(settings: settings, liveMonitor: LiveTokenMonitor())
        self.settings = settings
        self.store = store
        controller = StatusItemController(store: store)
    }
}
