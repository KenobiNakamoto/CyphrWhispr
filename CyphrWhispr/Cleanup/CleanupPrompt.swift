import Foundation

/// Owns the canonical cleanup prompt that drives the on-device language model
/// when Polish is enabled. The text deliberately reads like a developer-friendly
/// rulebook rather than a chatty system message — clarity beats charm here,
/// because Apple's small Foundation Model follows tightly-scoped instructions
/// far better than open-ended ones.
///
/// Two pieces of vocabulary used throughout:
///
/// - **Default prompt** — the constant `defaultPrompt` below. Shown read-only
///   in the Polish tab when the user hasn't customised. This is what we ship
///   with and what we know is well-tuned.
///
/// - **Effective prompt** — whichever prompt is currently in force, default OR
///   the user's edited version. `PreferencesStore.effectivePolishPrompt`
///   returns this; the cleaner always reads from there, never from the raw
///   default constant.
enum CleanupPrompt {
    /// The baseline cleanup prompt. Constant — does NOT change when the user
    /// customises (their edits live on `PreferencesStore.polishCustomPrompt`).
    /// Versioned in spirit; if we ever materially change the default we should
    /// migrate users still on the old default forward.
    ///
    /// Design notes baked into the wording:
    ///   • "Return ONLY the cleaned transcript" — the small model loves to
    ///     prefix replies with "Here is your text:". Spelling that out kills
    ///     the preamble cleanly.
    ///   • "Never insert names or phrases the speaker did not say" — Whisper
    ///     can revise itself mid-stream, so the LM sees text that's already
    ///     been scrubbed once. A creative LM can't be allowed to "improve"
    ///     by adding content.
    ///   • Empty-input contract returns "EMPTY" verbatim — gives us a cheap
    ///     sentinel to skip the type+paste round when the user releases the
    ///     hotkey on silence.
    ///   • "Preserve the speaker's intent, tone, and meaning" — covers the
    ///     vibe most casual users will worry about ("don't make me sound
    ///     formal").
    static let defaultPrompt: String = """
    You are a dictation post-processor. You receive raw speech-to-text output \
    and return clean text that is ready to be typed into an application.

    Your job:
    - Remove filler words (um, uh, you know, like) unless they carry meaning.
    - Fix spelling, grammar, and punctuation errors.
    - Restore proper capitalization at the start of sentences and for proper nouns.
    - Preserve the speaker's intent, tone, and meaning exactly.

    Output rules:
    - Return ONLY the cleaned transcript text — no preamble, no commentary.
    - If the input is empty, return exactly: EMPTY
    - Never insert names, phrases, or content the speaker did not say.
    - Do not change the meaning of what was said.
    """

    /// Compose the system message that's actually handed to the language model.
    /// Right now this is a passthrough — the prompt text is the system message.
    /// Lives behind a function so we can later prepend boilerplate (model
    /// guard rails, timestamp, custom-vocabulary section) without touching
    /// every call site.
    ///
    /// - Parameter effective: the result of `PreferencesStore.effectivePolishPrompt`.
    /// - Returns: the string to pass as the LM's system instructions.
    static func systemMessage(effective: String) -> String {
        effective
    }

    /// Sentinel returned by the model when the input is empty. Defined here
    /// (rather than a magic string at the call site) so the prompt and the
    /// parser stay in lockstep.
    static let emptySentinel: String = "EMPTY"
}
