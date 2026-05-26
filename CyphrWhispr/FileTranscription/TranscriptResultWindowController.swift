import AppKit
import SwiftUI
import Combine

/// Manages floating result windows produced by ad-hoc file transcription.
///
/// Unlike `OnboardingWindowController` / `SettingsWindowController`, this is
/// *not* a singleton-window controller — each dropped file gets its own
/// window so the user can stack several transcripts at once. Windows are
/// retained in a dictionary keyed by a per-window UUID and removed when
/// they close, so we don't leak NSWindows or services.
///
/// Each window owns its own `FileTranscriptionService` (and therefore its
/// own `FileTranscriber` actor). The services run their pipelines
/// concurrently in their decode phase; the actual WhisperKit transcribe
/// call serialises because Core ML's GPU-context access is single-instance
/// per Mac — second drop's transcribe phase will queue behind the first.
@MainActor
final class TranscriptResultWindowController {
    static let shared = TranscriptResultWindowController()

    private struct Entry {
        let window: NSWindow
        let service: FileTranscriptionService
        var willCloseObserver: NSObjectProtocol?
        var statusObserver: AnyCancellable?
    }
    private var entries: [UUID: Entry] = [:]

    /// Origin of the most recently opened window — used to cascade the next
    /// drop so a burst of files stacks legibly. Dictionaries don't preserve
    /// insertion order, so we track this independently of `entries`.
    private var lastWindowOrigin: NSPoint?

    private init() {}

    /// Open a fresh result window for the file at `url`. Pulls the active
    /// model and effective language code out of `PreferencesStore` so the
    /// file path uses whatever the user picked for live dictation. Phase C
    /// will add a per-file override surface in the Settings tab.
    func showNewWindow(for url: URL) {
        let prefs = PreferencesStore.shared
        let service = FileTranscriptionService(
            sourceURL: url,
            modelName: prefs.activeModelID,
            languageCode: prefs.effectiveLanguageCode
        )

        let id = UUID()
        let host = NSHostingController(
            rootView: TranscriptResultView(service: service)
                .environmentObject(prefs)
        )

        let window = NSWindow(contentViewController: host)
        window.title = url.lastPathComponent
        // `.fullSizeContentView` lets the SwiftUI backdrop reach the top edge
        // under the transparent title bar — same trick the Settings and
        // Onboarding windows use. Resizable so long transcripts have room.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsDesign.pageBackground)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 460, height: 360)
        window.setContentSize(NSSize(width: 620, height: 680))
        // Cascade: each new window opens slightly offset from the last so a
        // burst of drops stacks legibly instead of stacking on top of itself.
        if let lastOrigin = lastWindowOrigin {
            window.setFrameOrigin(NSPoint(x: lastOrigin.x + 22, y: lastOrigin.y - 22))
        } else {
            window.center()
        }
        lastWindowOrigin = window.frame.origin

        // Drop the entry when the window closes so we don't retain dead
        // controllers + their loaded WhisperKit pipelines.
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.entries.removeValue(forKey: id)
            }
        }

        // Record into the recents store the moment the service flips to its
        // terminal state. Subscribed here, not on the view, because views
        // come and go (the user might close the result window before the
        // .done/.failed lands) and we want recents to capture the outcome
        // either way.
        let statusObserver = service.$status
            .receive(on: RunLoop.main)
            .sink { status in
                switch status {
                case .done(let transcript):
                    RecentTranscriptionsStore.shared.record(transcript)
                case .failed(let message):
                    RecentTranscriptionsStore.shared.recordFailure(url: url,
                                                                   message: message)
                case .idle, .decoding, .transcribing:
                    break
                }
            }

        entries[id] = Entry(window: window,
                            service: service,
                            willCloseObserver: observer,
                            statusObserver: statusObserver)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
