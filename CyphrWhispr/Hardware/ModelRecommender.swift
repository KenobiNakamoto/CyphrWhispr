import Foundation

/// Picks a sensible default Whisper model from a `HardwareProfile`.
///
/// The matrix mirrors the table in the implementation plan. It's intentionally
/// coarse — we'd rather under-promise than ship a default that thermal-throttles
/// the user's laptop on first dictation.
enum ModelRecommender {
    static func recommend(for profile: HardwareProfile) -> WhisperModel {
        // Intel Macs: anything bigger than tiny gets miserable. WhisperKit
        // technically supports them but we don't want first-launch to feel slow.
        guard profile.isAppleSilicon else {
            return ModelCatalog.model(id: "openai_whisper-tiny.en")!
        }

        // M-Ultra with serious RAM headroom can handle full Large v3.
        if profile.variant == .ultra && profile.ramGB >= 64 {
            return ModelCatalog.model(id: "openai_whisper-large-v3")!
        }

        // Pro/Max on M3+ → Turbo. Quality close to Large, speed close to Medium.
        if (profile.variant == .pro || profile.variant == .max)
            && (profile.family == .m3 || profile.family == .m4)
            && profile.ramGB >= 16 {
            return ModelCatalog.model(id: "openai_whisper-large-v3-v20240930_turbo")!
        }

        // 16 GB+ on any M-series → Medium.
        if profile.ramGB >= 16 {
            return ModelCatalog.model(id: "openai_whisper-medium.en")!
        }

        // 8 GB Apple Silicon → Small.
        if profile.ramGB >= 8 {
            return ModelCatalog.model(id: "openai_whisper-small.en")!
        }

        // Anything else: be conservative.
        return ModelCatalog.model(id: "openai_whisper-tiny.en")!
    }

    /// Build a one-line user-facing recommendation explanation.
    /// Example: "Detected M3 Pro, 18 GB. Recommended: Large v3 Turbo."
    static func explanation(for profile: HardwareProfile, model: WhisperModel) -> String {
        "Detected \(profile.displayName), \(profile.ramGB) GB. Recommended: \(model.displayName)."
    }
}
