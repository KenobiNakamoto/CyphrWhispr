import Foundation

// FoundationModels was new in macOS 26 (Tahoe, fall 2025). Anyone building
// CyphrWhispr against an older Xcode SDK won't have the framework available
// at compile time — `canImport` gates the import, and at runtime we further
// gate behind `#available(macOS 26.0, *)` so the same binary works back to
// our deployment floor of macOS 14.
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public surface

/// Why polish couldn't (or didn't) run on a given call. Surfaced to the user
/// via the Polish tab's status hint and read by `AppCoordinator` to decide
/// between running the cleaner or skipping straight to paste.
enum PolishAvailability: Equatable, Sendable {
    /// Apple Foundation Models is reachable; we can call it.
    case available
    /// Running on macOS earlier than 26.0 — framework absent at runtime.
    case requiresMacOS26
    /// User has Apple Intelligence turned off in System Settings.
    case appleIntelligenceDisabled
    /// Model is still downloading (typically the first hour after enabling AI).
    case modelDownloading
    /// Device doesn't support Apple Intelligence (Intel, base M1 with 8GB RAM, etc.).
    case deviceIneligible
    /// Polish toggle is off in CyphrWhispr's own settings.
    case disabledInSettings

    /// One-line user-facing copy for the Polish tab status hint. Kept short so
    /// it fits in a single line under the toggle.
    var explainer: String {
        switch self {
        case .available:
            return "Active — your transcripts will be polished on-device."
        case .requiresMacOS26:
            return "Requires macOS 26 (Tahoe) or later."
        case .appleIntelligenceDisabled:
            return "Enable Apple Intelligence in System Settings → Apple Intelligence."
        case .modelDownloading:
            return "Apple Intelligence is still downloading. Try again shortly."
        case .deviceIneligible:
            return "This Mac doesn't support Apple Intelligence."
        case .disabledInSettings:
            return "Turn on the toggle above to polish transcripts."
        }
    }
}

/// Outcome of a single cleanup pass. Drives downstream behaviour in the
/// coordinator: `.cleaned` → type the cleaned text; `.empty` → don't paste
/// at all; `.skipped` / `.rejected` → fall through to pasting the raw text.
enum PolishOutcome: Equatable, Sendable {
    /// Polished text from the language model. Always trimmed.
    case cleaned(String)
    /// LM (or our pre-check) decided the input was empty silence. Skip paste.
    case empty
    /// Couldn't run polish — caller should paste the raw transcript instead.
    /// `reason` is for telemetry / debug logs, not user-facing text.
    case skipped(reason: PolishAvailability)
    /// Polish ran but the result was untrustworthy (timeout, hallucination,
    /// wildly different length than the raw). Caller should paste raw.
    case rejected(reason: String)
}

/// Behind a protocol so unit tests can swap in a deterministic cleaner.
/// All methods are async — even `availability()` — because the production
/// implementation reads system state that the framework wraps in async.
protocol TranscriptionCleaner: Sendable {
    func availability() async -> PolishAvailability
    func clean(_ raw: String, prompt: String, timeout: TimeInterval) async -> PolishOutcome
}

// MARK: - Production implementation

/// Production cleaner backed by `LanguageModelSession` from Apple's
/// FoundationModels framework. No stored state — all the per-call session
/// setup happens inside `clean(...)` so we never accidentally reuse a session
/// across user sessions (each polish gets a fresh, instructions-only context).
///
/// Sendable because the class has no stored mutable state. Methods are not
/// actor-isolated so the timeout race in `clean(...)` actually runs the LM
/// call and the sleep on different cooperative threads.
final class FoundationModelsCleaner: TranscriptionCleaner, Sendable {
    init() {}

    func availability() async -> PolishAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceDisabled
                case .modelNotReady:
                    return .modelDownloading
                case .deviceNotEligible:
                    return .deviceIneligible
                @unknown default:
                    // New unavailability reason in a future OS — degrade
                    // safely. The Polish tab will say "device ineligible"
                    // even if it's actually something subtler; the worst
                    // case is the user retries and gets the right answer.
                    return .deviceIneligible
                }
            @unknown default:
                return .deviceIneligible
            }
        } else {
            return .requiresMacOS26
        }
        #else
        return .requiresMacOS26
        #endif
    }

    func clean(_ raw: String, prompt: String, timeout: TimeInterval) async -> PolishOutcome {
        // Bail out before doing any work if we know the framework can't help.
        let avail = await self.availability()
        guard case .available = avail else {
            return .skipped(reason: avail)
        }

        // Empty-input shortcut. Avoids a wasted LM round-trip if the user
        // released the hotkey on silence.
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else { return .empty }

        // Race the LM call against a sleep. Whoever finishes first wins; the
        // other gets cancelled. We use a non-throwing TaskGroup so each branch
        // returns a fully-formed PolishOutcome — the timeout branch returns
        // `.rejected(reason:)`, the LM branch returns whatever it computes.
        return await withTaskGroup(of: PolishOutcome.self) { group in
            group.addTask {
                await Self.callLanguageModel(prompt: prompt, input: trimmedRaw)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .rejected(reason: "Cleanup timed out after \(Self.format(timeout: timeout))")
            }
            let first = await group.next() ?? .rejected(reason: "Cleanup yielded no result")
            group.cancelAll()
            return first
        }
    }

    /// Single LM round-trip. Static so it can be called from inside a TaskGroup
    /// without capturing `self` and dragging actor isolation along.
    private static func callLanguageModel(prompt: String, input: String) async -> PolishOutcome {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(
                    instructions: CleanupPrompt.systemMessage(effective: prompt)
                )
                let response = try await session.respond(to: input)
                return validate(raw: input, cleaned: response.content)
            } catch {
                return .rejected(reason: "LM error: \(error.localizedDescription)")
            }
        }
        #endif
        return .rejected(reason: "FoundationModels unavailable at runtime")
    }

    /// Sanity-check the LM's output. Catches the two failure modes that show
    /// up most often in practice:
    ///   • The model returns a preamble like "Sure, here's the cleaned text:"
    ///     despite the prompt forbidding it. Hard to detect without parsing,
    ///     so we lean on the length-ratio heuristic below.
    ///   • The model hallucinates and either drops most of the content or
    ///     adds invented detail. Both show up as a length ratio outside our
    ///     0.4× – 2.5× tolerance band.
    /// Borderline returns get the raw paste — we'd rather miss a polish than
    /// paste corrupt text.
    ///
    /// Internal (not private) so unit tests can exercise the heuristics without
    /// having to stand up an actual `LanguageModelSession`.
    static func validate(raw: String, cleaned: String) -> PolishOutcome {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == CleanupPrompt.emptySentinel { return .empty }
        if trimmed.isEmpty { return .rejected(reason: "Cleaner returned empty string") }

        let rawLen = max(raw.count, 1)
        let ratio = Double(trimmed.count) / Double(rawLen)
        if ratio < 0.4 || ratio > 2.5 {
            return .rejected(
                reason: "Cleaned length out of expected range (\(String(format: "%.2f", ratio))×)"
            )
        }
        return .cleaned(trimmed)
    }

    static func format(timeout: TimeInterval) -> String {
        // "3s" reads better than "3.0 seconds" in the rejected-reason logs.
        if timeout == floor(timeout) { return "\(Int(timeout))s" }
        // printf's %.1f uses banker's rounding (toNearestOrEven), which
        // surprises tests and users — e.g. 0.25 → "0.2" instead of "0.3".
        // Pre-round half-away-from-zero so it matches the conventional
        // "round up at .5" behaviour.
        let rounded = (timeout * 10).rounded(.toNearestOrAwayFromZero) / 10
        return String(format: "%.1fs", rounded)
    }
}
