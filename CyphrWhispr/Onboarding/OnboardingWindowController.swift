import AppKit
import SwiftUI

/// Hosts the first-run onboarding window — a single fixed-size pane that
/// walks the user through the two required permissions plus the recommended
/// Whisper model + hotkey.
///
/// Mirrors `SettingsWindowController` architecturally: a manual `NSWindow` +
/// `NSHostingController`, kept around between opens so the view's permission
/// poller doesn't restart every time. `AppDelegate` opens it automatically
/// on first launch (when `!prefs.onboardingCompleted`); the About tab's
/// "Show onboarding again" row reopens it on demand.
///
/// Closing the window marks `prefs.onboardingCompleted = true` so the auto-
/// open path doesn't re-fire next launch.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var willCloseObserver: NSObjectProtocol?

    private init() {}

    /// Show (or bring to front) the onboarding window.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(
            rootView: OnboardingView()
                .environmentObject(PreferencesStore.shared)
        )
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to CyphrWhispr"
        // `.fullSizeContentView` lets the SwiftUI backdrop reach the top edge
        // under the transparent title bar — same trick as the Settings window.
        // No `.resizable` / `.miniaturizable`: onboarding is a one-page pane
        // sized for its content; only the close button is active.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsDesign.pageBackground)
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 520, height: 640))
        window.center()

        // Mark onboarding complete on close so the auto-open path doesn't
        // re-trigger next launch. Re-discovery lives in About → "Show
        // onboarding again", which re-opens this window; the flag is set
        // again on the next close. No harm flipping a true value to true.
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PreferencesStore.shared.onboardingCompleted = true
            }
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Programmatic close — used by the "Done" / "Close" button in
    /// `OnboardingView`. Triggers the same `willCloseNotification` as the
    /// title-bar X, so the completion flag is set the same way.
    func close() {
        window?.close()
    }
}
