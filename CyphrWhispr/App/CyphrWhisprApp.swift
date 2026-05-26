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

        // First-run welcome window. Auto-opens once; closing it flips
        // `prefs.onboardingCompleted` so the next launch is quiet. Re-open
        // from About → "Show onboarding again".
        if !PreferencesStore.shared.onboardingCompleted {
            OnboardingWindowController.shared.show()
        }

        // Register the cyphr-whispr:// URL handler so `open cyphr-whispr://...`
        // can drive the app remotely (scripting, deep-links). We use the
        // legacy NSAppleEventManager API rather than `.onOpenURL` because
        // this app has no SwiftUI WindowGroup scene to attach it to.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }

    /// Routes `cyphr-whispr://...` URLs to the right runtime action. Currently
    /// supports only `open-settings` but the switch is set up to grow.
    @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        switch url.host {
        case "open-settings":
            SettingsWindowController.shared.show()
        case "open-onboarding":
            OnboardingWindowController.shared.show()
        default:
            break
        }
    }
}
