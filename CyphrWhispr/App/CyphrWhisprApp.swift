import SwiftUI
import AppKit
import UniformTypeIdentifiers  // UTType.audio / .movie filter in application(_:open:)

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

    /// Files handed to us via Voice Memos' "Open With" submenu, Finder's
    /// Open With submenu, system Share extensions, or `open -a CyphrWhispr
    /// <file>` from the terminal — every system-level "open this with
    /// CyphrWhispr" path lands here. Registered indirectly via the
    /// `CFBundleDocumentTypes` declaration in `project.yml`, which tells
    /// macOS we're a viewer for `public.audio` / `public.movie` /
    /// `public.audiovisual-content` (always with `LSHandlerRank: Alternate`
    /// so we never displace Music.app or QuickTime as the default).
    ///
    /// Routes each URL through the same `TranscriptResultWindowController`
    /// the menu-bar drop overlay, the Transcribe-tab drop zone, and the
    /// `cyphr-whispr://transcribe-file` URL scheme already use — one result
    /// window per file, cascade-offset for legibility on multi-file bursts.
    func application(_ application: NSApplication, open urls: [URL]) {
        // LSUIElement = true means we have no Dock icon, so the result
        // window can otherwise open behind whichever app the user clicked
        // "Open With" from (Voice Memos, Finder, etc.). Explicit activate
        // puts the window in front the moment it materialises.
        NSApp.activate(ignoringOtherApps: true)
        for url in urls where Self.isMediaFile(url) {
            TranscriptResultWindowController.shared.showNewWindow(for: url)
        }
    }

    /// UTType conformance check — mirrors the predicate the menu-bar drop
    /// overlay and the Transcribe-tab drop zone use, kept here so a stray
    /// non-media file passed via `open -a CyphrWhispr foo.txt` from the
    /// terminal doesn't open a useless empty result window.
    private static func isMediaFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }
        return type.conforms(to: .audio)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
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
        case "transcribe-file":
            // `cyphr-whispr://transcribe-file?path=/Users/.../podcast.mp3`
            // — extracted via URLComponents so percent-encoding decodes
            // properly. Phase A entry point; Phase B/C/D add menu-bar,
            // Settings-tab, and Finder-Sync paths that all funnel into the
            // same `TranscriptResultWindowController.showNewWindow(for:)`.
            guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                                .queryItems?
                                .first(where: { $0.name == "path" })?
                                .value,
                  !path.isEmpty else { return }
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                NSLog("[CyphrWhispr] transcribe-file URL: no file at \(fileURL.path)")
                return
            }
            TranscriptResultWindowController.shared.showNewWindow(for: fileURL)
        default:
            break
        }
    }
}
