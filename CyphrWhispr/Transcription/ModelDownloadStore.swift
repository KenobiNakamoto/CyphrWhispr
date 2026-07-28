import Foundation
import Combine

/// RAM-only progress register for the in-flight Whisper-model download (if
/// any). Two unrelated UI surfaces need to render the same `XX% Downloaded`
/// text — the dictation pill at the bottom of the screen AND the per-row
/// action button on the Settings → Models tab — without either one owning
/// the source of truth. The store sits between `AppCoordinator` (the only
/// writer; it watches the engine's progress callback) and the views (the
/// only readers).
///
/// Privacy contract intact: nothing here is persisted. The state evaporates
/// on app exit by design — this tracks "what's happening right now", not
/// history.
///
/// Single-download invariant: only one variant is ever being fetched at a
/// time. The engine serialises switches (`modelSwitchTask?.cancel()` on
/// every `switchModel(...)` call), and `WhisperKit.download(variant:)` is
/// the only callable; concurrent downloads of different variants don't
/// happen. So `currentModelID` is a single optional rather than a set.
@MainActor
final class ModelDownloadStore: ObservableObject {
    static let shared = ModelDownloadStore()

    /// The variant ID currently being downloaded, or nil when no download
    /// is in flight. Drives the row-level "is this me?" check in
    /// `ModelsTabView` so the matching row's action button swaps to a
    /// percent label.
    @Published private(set) var currentModelID: String?

    /// Latest fraction in `[0, 1]` reported by the engine. Meaningful only
    /// while `currentModelID != nil`. Defensively clamped on every set so a
    /// misbehaving callback can't push the UI out of range.
    @Published private(set) var fraction: Double = 0

    private init() {}

    /// Mark the start of a download for `modelID`. Resets `fraction` to 0
    /// so the matching row starts at "0% Downloaded" rather than
    /// inheriting the tail value of a previous download.
    func begin(modelID: String) {
        currentModelID = modelID
        fraction = 0
    }

    /// Push a new progress fraction from the engine. No-op when no
    /// download is registered: a late callback firing after `finish()`
    /// should not yank an already-idle UI back to mid-progress.
    func update(_ p: Double) {
        guard currentModelID != nil else { return }
        fraction = min(max(p, 0), 1)
    }

    /// Mark the end of a download — success OR failure. Clears the model
    /// ID so observing rows fall back to their normal action button, and
    /// resets `fraction` so the next download starts clean.
    func finish() {
        currentModelID = nil
        fraction = 0
    }
}
