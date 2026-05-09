# Backup 6 — Multilingual transcription shipped

**Date:** 2026-05-09
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-6`
**Previous backup:** [`backup-5`](./BACKUP-5.md)

## What's new since Backup 5

The single biggest user-facing addition since the install-animation arc:
**multilingual dictation works**.

A non-English speaker can now switch to a multilingual model in
Settings → Models, leave the language picker on Auto-detect (or pin
to their language), and dictate naturally. No more `[NON-ENGLISH SPEECH]`
or `(speaking in foreign language)` artifacts being silently stripped
because the English-only model couldn't decode the audio.

Pattern adapted from VoiceInk's `LibWhisper.swift` (GPL — pattern, not
code) and the WhisperKit DecodingOptions API surface. Verdict on engine
research: see `docs/strategy/2026-05-09-stt-engine-research.md` for
the full multilingual / NVIDIA Parakeet / Apple SpeechTranscriber
write-up.

## Commits introduced

```
4258198  Settings: language picker in Models tab + AppCoordinator wiring
91fbd1f  Add multilingual transcription: language picker + auto-detect lock
1da2cb9  Add STT engine research — multilingual / Parakeet / Apple Silicon
```

## What's in the running app right now

### New: language preference + auto-detect lock

- `Settings → Models` shows a new **Dictation language** card between the
  recommendation banner and the model list.
- When a multilingual model is active (any non-`.en` variant), the picker
  is enabled with **Auto-detect** + **33 curated languages** (English first,
  then alphabetical, with native-script subtitles).
- When an English-only `.en` model is active, the picker is greyed out
  with a hint: "Switch to a multilingual model below to enable language
  selection."
- Auto-detect runs Whisper's own LID head on the first ~1.5 s of audio,
  then **locks** the detected language for the rest of the session. The
  detection penalty hits exactly one transcribe per session.
- Forced-language mode skips LID entirely and prefills the language
  token — fastest path, highest accuracy.
- The user's preference is effective on the **next** hotkey press; never
  on an in-flight session (engine reads at `startStream()`).

### New: multilingual model variants

`ModelCatalog` now ships:

| Variant | Size | Tier | Multilingual? | Use case |
|---|---|---|---|---|
| `openai_whisper-tiny.en` | 75 MB | tiny | English-only | Fastest, low-RAM |
| `openai_whisper-base.en` | 145 MB | tiny | English-only | Slightly better than tiny |
| `openai_whisper-small.en` | 466 MB | small | English-only | **Default for English** |
| `openai_whisper-medium.en` | 1.5 GB | medium | English-only | Higher EN accuracy |
| **`openai_whisper-small`** | **466 MB** | **small** | **Multilingual** | **Smallest viable for non-English** |
| **`openai_whisper-medium`** | **1.5 GB** | **medium** | **Multilingual** | **Higher multilingual accuracy** |
| `openai_whisper-large-v3-v20240930_turbo` | 1.6 GB | largeTurbo | Multilingual | Sweet spot for power users |
| `openai_whisper-large-v3` | 3.0 GB | large | Multilingual | Best, heavy |

### Code locations

- `CyphrWhispr/Transcription/TranscriptionLanguage.swift` — language data
  model: `TranscriptionLanguageMode` enum + `TranscriptionLanguageCatalog`
  with 33 curated languages
- `CyphrWhispr/Transcription/WhisperEngine.swift` — protocol gains
  `setLanguageCode(_:)`
- `CyphrWhispr/Transcription/WhisperKitBackend.swift` — `DecodingOptions`
  construction with three modes (forced / auto-first-pass /
  auto-locked); `lockSessionLanguage(from:)` after every transcribe
- `CyphrWhispr/Transcription/ModelCatalog.swift` — multilingual variants
- `CyphrWhispr/Settings/PreferencesStore.swift` — `selectedLanguageCode`,
  derived `effectiveLanguageCode` and `activeModelSupportsLanguageChoice`
- `CyphrWhispr/Settings/ModelsTabView.swift` — language card +
  `LanguagePickerMenu` private view
- `CyphrWhispr/App/AppCoordinator.swift` — backend init takes
  `effectiveLanguageCode`; Combine subscription propagates changes to the
  actor
- `CyphrWhisprTests/TranscriptionLanguageTests.swift` — 19 tests covering
  catalog, mode round-trip, native-name presence, English-only clamping

### New strategic doc (carried over from earlier this session)

- `docs/strategy/2026-05-09-stt-engine-research.md` — full STT engine
  research brief (multilingual / NVIDIA Parakeet / Apple SpeechTranscriber).
  Recommends multilingual first (this commit), then Apple's macOS 26
  SpeechTranscriber as a second engine, then FluidAudio Parakeet as a
  third option.

## How it works at runtime

```
                user picks language in Settings
                            │
                            ▼
              PreferencesStore.selectedLanguageCode
                            │
                            ▼
            PreferencesStore.effectiveLanguageCode
                  (clamps to "en" on .en model)
                            │
                            ▼
                AppCoordinator Combine sink
                            │
                            ▼
             whisper.setLanguageCode(code) [actor]
                            │
                            ▼
              WhisperKitBackend.requestedLanguageCode
                            │
                            ▼
        startStream() resets sessionLockedLanguage = nil
                            │
                            ▼
   First emitPartial / finishStream uses currentDecodeOptions():
     • forced code? language=code, prefill on
     • auto + locked? language=lockedCode, prefill on
     • auto + not locked? language=nil, detectLanguage=true
                            │
                            ▼
       lockSessionLanguage(from: results) captures detected
                            │
                            ▼
        every subsequent partial reuses the locked code
```

## Tests

- 19/19 new `TranscriptionLanguageTests` pass
- 105/106 total tests pass (1 unrelated pre-existing failure:
  `testRingBufferOverflowDropsOldest` — already chipped as side-task)
- Build clean; only pre-existing warnings remain

## Verified

- Hash match between freshly-built binary and `/Applications/CyphrWhispr.app`
  binary (`1b639aad...`). The running app IS the freshly-shipped code.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `4258198` | this baseline |

## Restoring to this state

```bash
git checkout backup-6
# or
git reset --hard backup-6     # destructive!
```

## Known limitations

- The picker offers a curated 33-language list. Whisper supports ~99
  languages; if a user wants Hawaiian (`haw`) or Yoruba (`yo`), they
  can't pick it from the menu yet. We could add a "More…" option that
  exposes the full list, or a manual code entry field. Defer until
  someone actually asks.
- Auto-detect locks the language for the rest of the session. If a
  user dictates English then immediately switches to French in the
  same hotkey press without releasing, French audio gets transcribed
  through the English language token — quality will suffer. Code-
  switching mid-utterance is a known unsolved problem; no Whisper-
  class model handles it well. The session-scoped lock is the
  industry-standard compromise.
- The "few hundred ms" detection penalty in auto mode hits the first
  transcribe of a session. Argmax's docs cite "few hundred ms"; we
  haven't measured on M1/M2/M3 ourselves. Open question in the
  engine-research brief.

## Suggested next moves

Per the engine research brief, in order:

1. **Apple `SpeechTranscriber` engine** for macOS 26+ — native
   AsyncStream of partials, 42 locales, no model download UX. Biggest
   single quality win available right now. ~3-5 days.
2. **FluidAudio Parakeet** as a third engine for power users in the
   25 European languages. Apache-2.0, CoreML, runs on Neural Engine.
   ~3 days.
3. Or pivot to original-plan items: URL scheme + modes (per the
   Superwhisper takeaways doc), or Phase 4 encrypted history.
