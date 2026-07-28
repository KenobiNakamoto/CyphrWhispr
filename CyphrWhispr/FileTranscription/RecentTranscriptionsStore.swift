import Foundation

/// Persistent list of the last ~10 ad-hoc file transcriptions.
///
/// The recents *list* lives in `UserDefaults` (JSON-encoded) and carries
/// metadata only — filename, source URL, timestamp, outcome summary. The
/// transcript text itself is kept out of UserDefaults (a long podcast
/// transcript is large) and stored alongside, one JSON per entry, in the
/// `TranscriptArchive` folder keyed by the entry's UUID. This store owns that
/// archive's lifecycle: it writes an archive when recording a successful entry
/// and deletes the file whenever the entry is dropped, so the two never drift.
///
/// Reopening a `.done` entry loads its archived transcript instantly (no
/// re-run of the audio). A `.failed` entry — or a legacy entry recorded before
/// archiving shipped — has no archive, so reopening it falls back to
/// re-transcribing from the source URL on disk; if the file moved or was
/// deleted, the result window surfaces a normal "no audio decoded" error.
///
/// Successful transcripts ALSO mirror into the encrypted History vault when
/// History is enabled — that wiring lives in the result-window controller, not
/// here, because the vault is opt-in and best-effort.
///
/// Bound by the Transcribe Settings tab.
@MainActor
final class RecentTranscriptionsStore: ObservableObject {
    static let shared = RecentTranscriptionsStore()

    /// Summary of how a transcription ended. Lossy by design — we only keep
    /// what the Transcribe tab actually renders, not the whole transcript.
    enum Outcome: Codable, Equatable {
        case done(wordCount: Int, durationSeconds: TimeInterval)
        case failed(message: String)
    }

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let sourceURL: URL
        let filename: String
        let timestamp: Date
        let outcome: Outcome
    }

    @Published private(set) var entries: [Entry] = []

    /// Hard cap so the recents list stays scannable and the UserDefaults
    /// payload stays tiny. Older entries are dropped on insert.
    private static let maxEntries = 10
    private static let key = "cw.recents.fileTranscriptions"
    private let defaults: UserDefaults

    /// `init(defaults:)` is exposed for tests; production code goes through
    /// `.shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record a successful transcription. Word count + duration are
    /// captured so the recents card can render `5 min ago · 428 words ·
    /// 21:34` without re-deriving anything.
    func record(_ transcript: FileTranscript) {
        let words = transcript.plainText
            .split(whereSeparator: { $0.isWhitespace })
            .count
        let entry = Entry(
            id: UUID(),
            sourceURL: transcript.sourceURL,
            filename: transcript.sourceFilename,
            timestamp: Date(),
            outcome: .done(wordCount: words,
                           durationSeconds: transcript.durationSeconds)
        )
        // Archive the full transcript under the entry's id BEFORE prepending,
        // so by the time the recents list (and its observers) see the new entry
        // its "Reopen" archive already exists on disk.
        TranscriptArchive.save(transcript, id: entry.id)
        prepend(entry)
    }

    /// The saved transcript for a `.done` entry, or `nil` for a failed/legacy
    /// entry that has no archive. The Transcribe tab's "Reopen" uses this to
    /// show the saved transcript instantly, falling back to re-transcribing the
    /// source file only when it returns `nil`.
    func archivedTranscript(for entry: Entry) -> FileTranscript? {
        TranscriptArchive.load(id: entry.id)
    }

    /// Record a failure for a file we couldn't transcribe. Same surface
    /// area as `record(_:)` from the UI's POV.
    func recordFailure(url: URL, message: String) {
        // Don't let a transient failure evict an already-saved transcript of
        // the same file. If the most recent entry is a SUCCESSFUL transcript of
        // this URL (e.g. the user reopened it, then a language re-transcribe
        // failed to decode), keep it and its archive — the error is already
        // shown in the result window; the saved transcript must survive.
        if let first = entries.first, first.sourceURL == url, case .done = first.outcome {
            return
        }
        let entry = Entry(
            id: UUID(),
            sourceURL: url,
            filename: url.lastPathComponent,
            timestamp: Date(),
            outcome: .failed(message: message)
        )
        prepend(entry)
    }

    func clearAll() {
        // Drop every archived transcript along with the list — a cleared
        // recents list should leave nothing behind on disk.
        for entry in entries {
            TranscriptArchive.delete(id: entry.id)
        }
        entries.removeAll()
        save()
    }

    /// Remove a single entry — for swipe-to-delete-style trim on the
    /// recents card if we add that gesture later.
    func remove(_ entry: Entry) {
        TranscriptArchive.delete(id: entry.id)
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Persistence

    private func prepend(_ entry: Entry) {
        // De-dupe: if the most recent entry is the same file, replace it
        // rather than stacking. Helps when a user re-transcribes the same
        // file a few times in a row to compare results. The replaced entry's
        // archive is now orphaned — delete it so we don't leak JSON files.
        if let first = entries.first, first.sourceURL == entry.sourceURL {
            if first.id != entry.id { TranscriptArchive.delete(id: first.id) }
            entries[0] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        if entries.count > Self.maxEntries {
            // Delete the archives of entries falling off the end of the cap.
            for dropped in entries.dropFirst(Self.maxEntries) {
                TranscriptArchive.delete(id: dropped.id)
            }
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
