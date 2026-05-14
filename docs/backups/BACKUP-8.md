# Backup 8 — Phrase-level code-switching (experimental)

**Date:** 2026-05-11
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-8`
**Previous backup:** [`backup-7`](./BACKUP-7.md)

## What's new since Backup 7

Polyglot users who code-switch between languages at natural pauses now
have a working option: **Auto-detect — per phrase**. The language is
re-detected at every commit boundary (every 4-6 s of dictation),
enabling sentences like:

> "Hola, ¿qué tal? [pause] How are you doing? [pause] Auf Deutsch, sehr gut."

…to be transcribed in their respective languages.

**What this doesn't do** (and we say so plainly in the UI hint):
Whisper picks ONE language token per decode pass — it cannot switch
mid-decode. So word-level mid-utterance switching (`"¿qué tal, my
friend?"` spoken in one breath) will pick whichever language won the
LID for that segment. This is a Whisper architecture constraint, not a
bug. No Whisper-class model handles it today; it would require a
different architecture (e.g. NVIDIA Parakeet's per-frame LID, or
Meta's MMS).

## Commits introduced

```
788c190  Add per-phrase language re-detection for code-switching dictation
```

## What's in the running app right now

### New picker entry

`Settings → Models → Dictation language` now offers **two** auto-detect
modes at the top of the menu, above the alphabetical language list:

1. **Auto-detect — lock per session** (existing, still the default)
   Whisper LID runs on the first 1.5 s of audio, then **locks** for the
   rest of the dictation. Lowest cost, highest accuracy when you're
   speaking one language per session.
2. **Auto-detect — per phrase (experimental)** (NEW)
   LID re-runs after every commit boundary (~every 4-6 s, anchored to
   natural pauses in your speech). Allows phrase-level code-switching
   between languages.

Plus the 59 specific languages pinned individually for users who know
which language a session will be.

### Engine wiring

`WhisperKitBackend.emitPartial()` now resets `sessionLockedLanguage = nil`
after every successful commit when `requestedLanguageCode ==
TranscriptionLanguageMode.autoPerPhraseCode`. Centralised
`isAutoMode(_:)` helper checks for both auto sentinels so the
"should we run LID?" path can never miss the new code.

### Data model additions

`TranscriptionLanguageMode` enum gained:
  - `.autoDetectPerPhrase` case
  - `autoPerPhraseCode = "auto-per-phrase"` sentinel
  - `isAutoDetect` flag — true for both auto variants
  - `resetsLockOnCommit` flag — true only for per-phrase

`from(persistedCode:)` and `persistedCode` handle the new sentinel.
Unknown values still fall back to `autoDetectLocked` (safer default).

### UI updates

- Two new menu entries at the top of the picker, divider, then the
  59 specific languages alphabetically.
- The selected entry's display in the picker label adapts:
  - `auto` → "Auto-detect"
  - `auto-per-phrase` → "Auto — per phrase"
  - specific codes → the language's English name
- Hint text under the picker now reflects the chosen mode:
  - Locked: "Whisper detects the language from the first second of
    audio, then locks it for the rest of the session."
  - Per phrase: "Re-detects language after each natural pause.
    Code-switching between phrases works; switching within a single
    uninterrupted phrase will pick one language."
  - Pinned: "Pinned to <Name>. Highest accuracy — no detection penalty."

## How to try it

1. CyphrWhispr is running. Click menu-bar icon → Settings → Models.
2. Switch to a multilingual model if not already (Small Multilingual
   or Large v3 Turbo).
3. **Dictation language** picker → top of menu, pick "Auto-detect — per phrase (experimental)".
4. Close Settings. Hold the hotkey. Speak with deliberate pauses
   between language switches:
   - "Hola, ¿qué tal?" — pause ~1 second —
   - "How are you doing?" — pause ~1 second —
   - "Auf Deutsch, ich bin gut."
5. Release. Each phrase should be in its own language.

## Tests

- **28/28** new `TranscriptionLanguageTests` pass (up from 23 in backup-7)
- 9 new tests added covering the per-phrase mode specifically:
  - `testModeFromAutoPerPhraseSentinel`
  - `testModeFromNilOrEmptyDefaultsToAutoLocked` (renamed)
  - `testPersistedCodeRoundTrip` (now covers both auto codes)
  - `testIsAutoDetectFlag`
  - `testResetsLockOnCommitOnlyForPerPhrase`
  - `testAutoPerPhraseCodeIsValid`
  - `testBothAutoCodesResolveToSameDisplayEntry`
  - plus the existing ones updated to use the renamed `.autoDetectLocked` case

## Verified

Hash match between freshly-built binary and `/Applications/CyphrWhispr.app`
binary: `02252bfeace3477982c385d77de9c6c35b0ceaf255f031f739d759e7c087885f`.
The running app is the freshly-shipped code.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `788c190` | this baseline |

## Restoring to this state

```bash
git checkout backup-8
# or
git reset --hard backup-8     # destructive!
```

## Honest limitations

- **Within-phrase word-level switching doesn't work.** "¿Cómo estás
  my friend?" in one breath picks one language for the whole utterance.
  Whisper's architecture decides language ONCE at decode start.
- **Per-phrase mode pays a LID penalty on every commit.** Roughly a few
  hundred ms per commit (every 4-6 s of dictation). Locked mode pays
  this once at session start.
- **Mid-decode language changes might still leak through.** If the
  user starts in Spanish but their first commit window contains 5 s of
  Spanish then 1 s of English, the commit decodes everything as
  Spanish, and only the NEXT commit gets the chance to re-detect
  English. Pauses help; rapid switches do not.
- **The "natural pause" the engine relies on is implicit** — it's
  whatever Whisper's segmentation considers segment boundaries old
  enough to commit. Today that's ~2 s past the live tail in a buffer
  that's at least 6 s long. We don't have an explicit VAD-based pause
  detector. A future improvement could anchor re-detection to actual
  silence boundaries.

## Suggested next moves

In order of impact:

1. **Real-world test the per-phrase mode.** This is genuinely
   experimental — the architecture is right but the UX feel needs
   actual polyglot dictation to validate. Report any flapping,
   stuck-on-wrong-language, or lost-text behaviour.
2. **Apple `SpeechTranscriber` engine for macOS 26+** — 42 locales,
   native streaming with volatile/finalized partials, free, no model
   download UX. Biggest single quality win still available per the
   engine-research brief. ~3-5 days.
3. **FluidAudio Parakeet** as a third engine for power users in the
   25 European-language set. Apache-2.0, CoreML, native ANE.
4. **Phase 4: encrypted history** — the remaining big v1 feature
   from the original plan.
