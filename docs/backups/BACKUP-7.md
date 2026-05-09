# Backup 7 — Language coverage broadened to 59 + Whisper-validity guard

**Date:** 2026-05-09
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-7`
**Previous backup:** [`backup-6`](./BACKUP-6.md)

## What's new since Backup 6

Two improvements to the multilingual feature shipped in backup-6:

### 1. Expanded picker — 33 → 59 languages

All major European entries now present (no more "wait, where's Bulgarian /
Slovak / Croatian / Slovenian"), plus a wider Indian-subcontinent set
(Tamil, Telugu, Malayalam, Marathi, Punjabi, Urdu) and global picks
(Tagalog, Swahili, Afrikaans). Whisper itself supports 100 languages;
the long tail (Hawaiian, Tibetan, Yoruba, Hausa, etc.) lives in
`WhisperOfficialLanguages` and we'll surface it via a "More…" picker
affordance once someone asks.

### 2. Source-of-truth Whisper code set + auto-validation

New `WhisperOfficialLanguages.codes` enum holds the canonical 100-code
set sourced from `openai/whisper`'s `tokenizer.py`. A unit test
(`testEveryCuratedCodeIsAValidWhisperCode`) asserts every code in our
curated catalog is in that set — so a typo like `"ge"` instead of
`"de"` gets caught at test time instead of silently shipping and
breaking transcription only for users who happened to pick the bad code.

A second unit test (`testProductRequiredLanguagesAllPresent`) pins
the founding-user core (Spanish, German, Catalan, English) plus 33
other must-haves by **both code and display name** — failure means
the picker visibly dropped a language a real user would notice.

## Commits introduced

```
f5ffed2  Expand language catalog to 59 + lock with Whisper-validity test
```

## Languages now in the picker

**Founding-user core** (must always be present):
- English (en), Spanish (es), German (de), Catalan (ca)

**All major European**:
- Albanian (sq), Basque (eu), Belarusian (be), Bosnian (bs),
  Bulgarian (bg), Catalan (ca), Croatian (hr), Czech (cs),
  Danish (da), Dutch (nl), English (en), Estonian (et),
  Finnish (fi), French (fr), Galician (gl), German (de),
  Greek (el), Hungarian (hu), Icelandic (is), Italian (it),
  Latvian (lv), Lithuanian (lt), Macedonian (mk), Maltese (mt),
  Norwegian (no), Polish (pl), Portuguese (pt), Romanian (ro),
  Russian (ru), Serbian (sr), Slovak (sk), Slovenian (sl),
  Spanish (es), Swedish (sv), Turkish (tr), Ukrainian (uk),
  Welsh (cy)

**Major non-European**:
- Afrikaans (af), Arabic (ar), Bengali (bn), Cantonese (yue),
  Chinese (zh), Hebrew (he), Hindi (hi), Indonesian (id),
  Japanese (ja), Korean (ko), Malay (ms), Malayalam (ml),
  Marathi (mr), Persian (fa), Punjabi (pa), Swahili (sw),
  Tagalog (tl), Tamil (ta), Telugu (te), Thai (th), Urdu (ur),
  Vietnamese (vi)

Plus `auto` for "Auto-detect & lock per session" — the friendly default
for multilingual users.

## Tests

- 23/23 new `TranscriptionLanguageTests` pass
- 105/106 total tests pass (1 unrelated pre-existing AudioRingBuffer
  failure already chipped as side-task)

## Hash verified

Built binary and `/Applications/CyphrWhispr.app` binary both at
`822062464d68...`. The running app is the freshly-shipped code.

## How to confirm in the UI

1. CyphrWhispr is running — click its menu-bar icon, choose Settings.
2. Models tab → look for the new **Dictation language** card between
   the recommendation banner and the model list.
3. Switch to a multilingual model (Small Multilingual, Large v3 Turbo,
   etc.) — picker activates.
4. Click the picker. The list opens with **Auto-detect** at top,
   **English** next, then alphabetical: Afrikaans → Albanian → Arabic
   → Basque → Belarusian → Bengali → Bosnian → Bulgarian → Cantonese
   → Catalan → Chinese → Croatian → Czech → Danish → Dutch → Estonian
   → Finnish → French → Galician → German → Greek → Hebrew → Hindi
   → Hungarian → Icelandic → Indonesian → Italian → Japanese → Korean
   → Latvian → Lithuanian → Macedonian → Malay → Malayalam → Maltese
   → Marathi → Norwegian → Persian → Polish → Portuguese → Punjabi
   → Romanian → Russian → Serbian → Slovak → Slovenian → Spanish
   → Swahili → Swedish → Tagalog → Tamil → Telugu → Thai → Turkish
   → Ukrainian → Urdu → Vietnamese → Welsh.
5. Each entry shows the native-script name as a subtitle (e.g.
   "Spanish — Español", "Japanese — 日本語"). Languages where the
   English name and native form match (Afrikaans, Tagalog) skip
   the subtitle.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `f5ffed2` | this baseline |

## Restoring to this state

```bash
git checkout backup-7
# or
git reset --hard backup-7     # destructive!
```

## Known limitations carried over

Same as backup-6:
- Curated to 59; the remaining 41 long-tail Whisper languages need a
  "More…" affordance (deferred until requested).
- Auto-detect locks per session — no mid-utterance code-switching
  (no Whisper-class model handles this well).
- Detection penalty on first transcribe of an auto-mode session is
  Argmax's claimed "few hundred ms" — not measured locally yet.

## Suggested next moves

Either:

1. **Keep going on the engine layer** — Apple `SpeechTranscriber`
   (macOS 26+) as a second engine per the engine-research brief.
   Native AsyncStream of partials, 42 locales, no model download UX.
   ~3-5 days. Biggest single quality win available right now.

2. **Pivot to product polish** — URL scheme + modes per the
   Superwhisper takeaways doc. Cheaper, unblocks Raycast/Alfred/
   Shortcuts integration and lays groundwork for app-aware mode
   auto-switching.

3. **Phase 4: encrypted history** — the remaining big v1 feature
   from the original plan. BIP-39 + GRDB+SQLCipher.

Or — once the user has confirmed the picker actually works in real
non-English dictation — file any specific quality / UX issues that
come up so we attack the right thing.
