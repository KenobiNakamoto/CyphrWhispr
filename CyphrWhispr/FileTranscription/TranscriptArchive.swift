import Foundation

/// On-disk archive of completed file transcripts, one JSON file per recents
/// entry under `AppSupportPaths.transcriptsRoot`, named `<entry-uuid>.json`.
///
/// This is what makes "Reopen" instant: a finished transcript is written here
/// the moment it lands, so reopening it later loads the saved text rather than
/// decoding and re-running the whole audio through Whisper. `RecentTranscriptionsStore`
/// owns the lifecycle — it writes an archive when it records a `.done` entry
/// and deletes the matching file whenever that entry is dropped (overflow past
/// the 10-entry cap, single remove, or Clear all), so the archive folder never
/// drifts out of sync with the recents list.
///
/// Every operation is best-effort (`try?`): a transcript failing to archive
/// must never break the transcription itself or the recents UI. A missing
/// archive on load simply falls back to re-transcribing from the source URL.
enum TranscriptArchive {
    private static func url(for id: UUID) -> URL {
        AppSupportPaths.transcriptsRoot.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    /// Persist `transcript` under `id`. Overwrites any existing file for the
    /// same id (e.g. a re-transcribe of the same recents slot at a new language).
    static func save(_ transcript: FileTranscript, id: UUID) {
        guard let data = try? JSONEncoder().encode(transcript) else { return }
        try? data.write(to: url(for: id), options: .atomic)
    }

    /// Load the saved transcript for `id`, or `nil` if none exists (legacy
    /// entry recorded before archiving shipped, a failed transcription, or a
    /// file the user pruned).
    static func load(id: UUID) -> FileTranscript? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONDecoder().decode(FileTranscript.self, from: data)
    }

    /// Remove the archive for `id`. No-op if it doesn't exist.
    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
