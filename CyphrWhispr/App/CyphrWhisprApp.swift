import SwiftUI
import AppKit

@main
struct CyphrWhisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // We have no SwiftUI scenes — the app lives entirely in the menu bar
        // and the Settings window we manage in SettingsWindowController.
        // SwiftUI requires *some* scene to satisfy the App protocol; we use
        // a Settings scene with EmptyView so it never appears in any menu but
        // also doesn't cost us a real window.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Touch the launch-at-login service so its init reconciles
        // SMAppService.mainApp.status with our prefs, and subscribes to
        // pref-change notifications for the rest of the session.
        _ = LaunchAtLoginService.shared
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
