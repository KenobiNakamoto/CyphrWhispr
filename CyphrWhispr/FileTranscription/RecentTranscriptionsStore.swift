import Foundation

/// Persistent list of the last ~10 ad-hoc file transcriptions.
///
/// Lives in `UserDefaults` (JSON-encoded) rather than the SQLCipher History
/// vault on purpose — file transcripts are not session dictations, and we
/// don't want filenames the user transcribed to surface in History's
/// encrypted-vault UX. The store carries metadata only (filename, source
/// URL, timestamp, outcome summary); the transcript text itself is never
/// persisted here.
///
/// Bound by the Transcribe Settings tab. The result-window controller
/// records into this store when each service transitions to `.done` or
/// `.failed`. Re-opening a previous entry resolves the URL on disk; if the
/// file moved or was deleted, the result window surfaces a normal "no
/// audio decoded" error.
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
        prepend(entry)
    }

    /// Record a failure for a file we couldn't transcribe. Same surface
    /// area as `record(_:)` from the UI's POV.
    func recordFailure(url: URL, message: String) {
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
        entries.removeAll()
        save()
    }

    /// Remove a single entry — for swipe-to-delete-style trim on the
    /// recents card if we add that gesture later.
    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Persistence

    private func prepend(_ entry: Entry) {
        // De-dupe: if the most recent entry is the same file, replace it
        // rather than stacking. Helps when a user re-transcribes the same
        // file a few times in a row to compare results.
        if let first = entries.first, first.sourceURL == entry.sourceURL {
            entries[0] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        if entries.count > Self.maxEntries {
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
