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
    /// model out of `PreferencesStore`, and seeds the language to the
    /// file-transcription default (auto-detect on a multilingual model rather
    /// than the live-dictation pin — see `fileTranscriptionDefaultLanguageCode`).
    /// The result window exposes a per-file language picker that calls
    /// `service.retranscribe(languageCode:)` to override this seed.
    func showNewWindow(for url: URL) {
        let prefs = PreferencesStore.shared
        let service = FileTranscriptionService(
            sourceURL: url,
            modelName: prefs.activeModelID,
            languageCode: prefs.fileTranscriptionDefaultLanguageCode
        )
        present(service: service, sourceURL: url)
    }

    /// Reopen a previously-saved transcript instantly — no decode, no Whisper
    /// run. The service is seeded `.done` with the archived transcript, so the
    /// window paints the saved text the moment it appears. The language picker
    /// still works: overriding it decodes the source file and re-runs (the only
    /// case that re-reads the audio).
    func showSavedWindow(transcript: FileTranscript) {
        let prefs = PreferencesStore.shared
        let service = FileTranscriptionService(
            preloaded: transcript,
            modelName: prefs.activeModelID,
            languageCode: prefs.fileTranscriptionDefaultLanguageCode
        )
        present(service: service, sourceURL: transcript.sourceURL)
    }

    /// Shared window construction for both fresh and reopened transcripts. The
    /// result view drives `service.start()` on appear; a preloaded (reopened)
    /// service no-ops it because its status is already `.done`.
    private func present(service: FileTranscriptionService, sourceURL url: URL) {
        let prefs = PreferencesStore.shared

        // Persist + mirror every genuine transcript the moment it lands:
        //   1. Archive it into recents so "Reopen" is instant next time.
        //   2. Mirror it into the encrypted History vault (no-op when History
        //      is disabled) so it shows in the History tab + full-text search.
        // Fires for the initial run and any language re-transcribe, but NOT for
        // a preloaded reopen (its transcript is already saved).
        service.onTranscribed = { transcript in
            RecentTranscriptionsStore.shared.record(transcript)
            HistoryService.shared.record(text: transcript.plainText,
                                         sourceApp: transcript.sourceFilename)
        }

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

        // Record FAILURES the moment the service flips to its terminal failed
        // state. Subscribed here, not on the view, because views come and go
        // (the user might close the result window before the outcome lands) and
        // we want recents to capture a failure either way. SUCCESS is recorded
        // via `service.onTranscribed` instead — that path also archives the
        // transcript and mirrors it into the History vault, and crucially does
        // NOT fire for a preloaded reopen (whose transcript is already saved).
        let statusObserver = service.$status
            .receive(on: RunLoop.main)
            .sink { status in
                switch status {
                case .failed(let message):
                    RecentTranscriptionsStore.shared.recordFailure(url: url,
                                                                   message: message)
                case .idle, .decoding, .transcribing, .done:
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
