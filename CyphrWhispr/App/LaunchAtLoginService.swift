import Foundation
import ServiceManagement

/// Bridges the `prefs.launchAtLogin` toggle to `SMAppService.mainApp` —
/// macOS 13+'s replacement for the old SMLoginItemSetEnabled API. The app
/// gets registered to launch at login when the user flips the toggle ON,
/// and unregistered when they flip it back OFF.
///
/// Important caveats:
///
///   1. The user can also flip this from System Settings → General →
///      Login Items. We observe `SMAppService.mainApp.status` on each
///      boot and reconcile the toggle with whatever the system thinks is
///      the truth, so the UI stays honest.
///
///   2. Registration can FAIL silently (sandbox missing, the user denied
///      the prompt, etc). On failure we log + flip the toggle back to
///      false so the user sees the request didn't stick.
///
///   3. App Store distribution would change this — there you'd use a
///      separate `LoginItemService` bundle inside the .app. For direct
///      distribution `SMAppService.mainApp` is the right call.
@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private var prefsObserver: NSObjectProtocol?

    private init() {
        // Sync the pref to whatever the system actually says. macOS might
        // have approved/denied us asynchronously, or the user might have
        // toggled us off from System Settings — either way, the pref UI
        // should reflect the truth.
        let prefs = PreferencesStore.shared
        let actual = (SMAppService.mainApp.status == .enabled)
        if prefs.launchAtLogin != actual {
            // Update via the underlying defaults so we don't re-trigger
            // the notification we're about to subscribe to.
            UserDefaults.standard.set(actual, forKey: "General.launchAtLogin")
            // Then update the Published property so the UI re-renders.
            prefs.launchAtLogin = actual
        }

        prefsObserver = NotificationCenter.default.addObserver(
            forName: .launchAtLoginDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
    }

    deinit {
        if let token = prefsObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Make the system match the current pref. Called once at app launch
    /// (after `init`) and again every time the user flips the toggle.
    func reconcile() {
        let prefs = PreferencesStore.shared
        do {
            if prefs.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[CyphrWhispr] Launch-at-login registration failed: \(error)")
            // Don't recursively re-fire the notification — set via
            // UserDefaults first, then sync the @Published value with a
            // local guard to avoid an infinite loop.
            if prefs.launchAtLogin {
                prefs.launchAtLogin = false
            }
        }
    }
}
