import Foundation

/// A model that CyphrWhispr knows how to load. Names match WhisperKit's
/// HuggingFace repo (`argmaxinc/whisperkit-coreml`) so we can pass them
/// straight through to `WhisperKitConfig(model:)`.
struct WhisperModel: Identifiable, Hashable, Sendable {
    enum Tier: String, CaseIterable, Sendable {
        case tiny, small, medium, largeTurbo, large
    }

    /// The string WhisperKit accepts (e.g. `"openai_whisper-small.en"`).
    let id: String
    let displayName: String
    let approxSizeMB: Int
    let tier: Tier
    /// Multilingual or English-only. We default to .en variants because they
    /// hallucinate less and are faster, but the user can switch.
    let isMultilingual: Bool
    /// One-line "what to expect" string for the picker.
    let speedHint: String
}

/// The set of models we ship pickers for. WhisperKit can technically download
/// any model in the `argmaxinc/whisperkit-coreml` repo, but listing every
/// variant overwhelms the picker. We curate the useful ones.
///
/// English-only (`.en`) variants are smaller, faster, and hallucinate less
/// for English input — they're the right default for English speakers.
/// Multilingual variants are larger but cover ~99 languages; required for
/// any non-English dictation. The Settings UI surfaces both groups so the
/// user can switch when their dictation language changes.
enum ModelCatalog {
    static let all: [WhisperModel] = [
        // MARK: English-only (smaller, faster, less hallucination)
        WhisperModel(
            id: "openai_whisper-tiny.en",
            displayName: "Tiny (English)",
            approxSizeMB: 75,
            tier: .tiny,
            isMultilingual: false,
            speedHint: "Fastest. Use on Intel or low-RAM Macs."
        ),
        WhisperModel(
            id: "openai_whisper-base.en",
            displayName: "Base (English)",
            approxSizeMB: 145,
            tier: .tiny,
            isMultilingual: false,
            speedHint: "Slightly better than Tiny, still cheap."
        ),
        WhisperModel(
            id: "openai_whisper-small.en",
            displayName: "Small (English)",
            approxSizeMB: 466,
            tier: .small,
            isMultilingual: false,
            speedHint: "Good baseline for daily dictation on M1/M2."
        ),
        WhisperModel(
            id: "openai_whisper-medium.en",
            displayName: "Medium (English)",
            approxSizeMB: 1_500,
            tier: .medium,
            isMultilingual: false,
            speedHint: "Higher accuracy. Comfortable on 16 GB+ Apple Silicon."
        ),

        // MARK: Multilingual (~99 languages — required for non-English)
        // Same architecture as the .en variants above, just trained on the
        // full multilingual mix. Smallest viable for daily-driver
        // multilingual dictation per Argmax/HuggingFace evals: `small`.
        WhisperModel(
            id: "openai_whisper-small",
            displayName: "Small (Multilingual)",
            approxSizeMB: 466,
            tier: .small,
            isMultilingual: true,
            speedHint: "Smallest viable for non-English daily dictation. ~99 languages."
        ),
        WhisperModel(
            id: "openai_whisper-medium",
            displayName: "Medium (Multilingual)",
            approxSizeMB: 1_500,
            tier: .medium,
            isMultilingual: true,
            speedHint: "Higher multilingual accuracy. Comfortable on 16 GB+ Apple Silicon."
        ),
        WhisperModel(
            id: "openai_whisper-large-v3-v20240930_turbo",
            displayName: "Large v3 Turbo",
            approxSizeMB: 1_600,
            tier: .largeTurbo,
            isMultilingual: true,
            speedHint: "Near-large quality, ~1.5× realtime on M3 Pro+. Sweet spot for power users."
        ),
        WhisperModel(
            id: "openai_whisper-large-v3",
            displayName: "Large v3 (Multilingual)",
            approxSizeMB: 3_000,
            tier: .large,
            isMultilingual: true,
            speedHint: "Best quality. Heavy. Use on M-Ultra / 64 GB+."
        ),
    ]

    static func model(id: String) -> WhisperModel? {
        all.first { $0.id == id }
    }
}
