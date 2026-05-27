import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// In-memory store of the most recent committed transcription text.
///
/// Surfaces to the menu-bar dropdown so the user can quickly copy the last
/// thing they dictated without rummaging through the encrypted History
/// vault (which is opt-in anyway). The coordinator's `commitFinalText`
/// records into this store at the same moment it pastes into the focused
/// app, and the menu reads from `lastTranscript` at click time.
///
/// **Not persisted across launches by design.** The privacy contract
/// ("no transcription content lives beyond the session") forbids us from
/// writing plaintext transcripts to UserDefaults. When the user opts in
/// to the encrypted History vault, the vault is the authoritative source
/// of past transcripts and this store is just a RAM mirror for the latest
/// one; without history, the only place last-transcript exists is in this
/// process's memory and it disappears at quit.
///
/// Single-writer (the coordinator) + single-reader (the menu builder) on
/// the main actor — no locking needed.
@MainActor
final class LastTranscriptStore: ObservableObject {
    static let shared = LastTranscriptStore()

    @Published private(set) var lastTranscript: String?

    private init() {}

    /// Record a freshly committed transcript. Whitespace-only commits are
    /// rejected so the cleanup-erases-silence path doesn't blank out an
    /// actually-useful prior transcript with empty string. The text is
    /// stored verbatim; UI surfaces (menu preview, etc.) handle truncation
    /// and ellipsisation themselves.
    func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastTranscript = trimmed
    }

    /// Convenience for the "Copy" menu item — write the last transcript
    /// to the general pasteboard. No-op when there's nothing to copy.
    /// Returns true if something was written, false otherwise (so the
    /// caller can decide whether to surface a confirmation).
    @discardableResult
    func copyToPasteboard() -> Bool {
        guard let text = lastTranscript else { return false }
        // Late import-by-default — keep this file free of AppKit in case we
        // want to test it on platforms without NSPasteboard. NSPasteboard
        // is the standard system clipboard; clearContents() before setString
        // ensures stale UTI types from previous pasteboard owners don't
        // bleed through (e.g. a hidden RTF representation of older text).
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
        #else
        return false
        #endif
    }
}
