# STT Engine Research — Multilingual, Parakeet, Apple Silicon

**Date:** 2026-05-09
**Author:** Research brief for CyphrWhispr engine planning
**Status:** Tactical recommendation, not a commitment

## TL;DR

1. **Multilingual** — ship a separate "multilingual" model slot (`large-v3-turbo` or the v3-distilled variant) and let the user pick "Auto-detect & lock for session" or a forced locale; do not try to hot-swap mid-utterance. WhisperKit supports this natively but the user must opt in by downloading a non-`.en` model.
2. **Parakeet** — feasible *today* on Apple Silicon via FluidAudio's CoreML port (Apache 2.0, ~50 production apps, streaming-capable), but only worth integrating as a second engine for users in the 25 supported European languages who want lower latency than `large-v3-turbo`; it is not a Whisper replacement.
3. **Apple Silicon models** — for macOS 26+ users, **Apple's `SpeechTranscriber` is the new default to beat** (42 locales, native streaming, free, no model download UX); add it as a third engine and treat WhisperKit as the macOS 14–25 fallback and the long-tail-language path.

---

## Q1 — Multi-language strategies

### What other projects do

| Project | Strategy |
|---|---|
| **MacWhisper** (closed) | Per-mode language pin; auto-detect available but per-session, not per-utterance. |
| **whisper.cpp** | `--language auto` flag detects on first 30s window; `whisper-stream` streams with a fixed locale. No per-utterance re-detect. ([source](https://github.com/ggml-org/whisper.cpp)) |
| **WhisperX / Faster-Whisper** | Run Whisper's built-in language ID on the first chunk, then lock; expose `language=None` for auto. |
| **MLX-Whisper / Lightning-Whisper-MLX** | Same — Whisper's own LID head, single-shot at start. |
| **Vosk / Coqui** | One model per language, hard pick — no LID. |
| **Superwhisper** | Per-mode language pin (modes are JSON, see [Superwhisper-Analysis 02](../../../../Superwhisper-Analysis/02-architecture.md)). Whisper variants for long tail, Parakeet V2/V3 for premium European-language users. |

**Consensus:** nobody does true mid-utterance code-switching well. Whisper's own LID runs once on the first ~30 s of audio, and re-detecting per chunk causes flapping. Even Whisper-native code-switching ("send this to José sobre el proyecto") frequently silently translates or sticks to whichever language won the LID coin-flip. ([discussion](https://github.com/openai/whisper/discussions/2009))

### WhisperKit specifics

- **All WhisperKit models are multilingual *unless* the variant name ends in `.en`.** Our current default `openai_whisper-small.en` is English-only by build; switching languages requires downloading a non-`.en` variant. There is no "one model, two modes" — separate downloads. ([WhisperKit repo](https://github.com/argmaxinc/WhisperKit))
- Auto-detect adds "a few hundred ms" to the first segment, then is free; subsequent decoding uses the locked language token. Argmax recommends `large-v3-v20240930_626MB` for max multilingual accuracy. (per their docs / recent search summary)
- **Live streaming with auto-detect works**, but the first ~1–2 s of partial output may be wrong before the LID head settles — UX must hide or de-emphasize the first partial.

### Recommended approach for CyphrWhispr

Add a **language picker in Settings** with three modes:
1. **English (current default)** — keep `small.en` / `large-v3-turbo.en`.
2. **Force locale** — user picks one of ~99 (`es`, `de`, `fr`, …); we pass it to `DecodingOptions.language`.
3. **Auto-detect, lock per session** — first push-to-talk press runs LID on the leading 1.5–2 s, then locks for the rest of the dictation; resets on next press. This matches every other live-dictation tool and avoids mid-utterance flapping.

Do **not** ship per-utterance re-detection or attempt code-switching as a feature. It does not work reliably with Whisper-class models today. If a user dictates `"send this to José sobre el proyecto"` they should be on a multilingual model with Spanish locked or auto-detected; Whisper will then handle the proper-noun switch within Spanish output.

**Smallest usable multilingual on M1/M2/M3 for daily-driver live dictation:** `openai_whisper-small` (~466 MB, multilingual). `tiny` and `base` are accuracy-floor for any non-English. For users who can spare the disk, `large-v3-turbo` (~1.6 GB, ~4× realtime on M1) is the sweet spot. ([model sizes](https://openwhispr.com/blog/whisper-model-sizes-explained))

---

## Q2 — NVIDIA Parakeet feasibility on Apple Silicon

### What is Parakeet

NVIDIA's RNN-T / TDT (Token-and-Duration Transducer) ASR family. The current daily-driver checkpoint is **`parakeet-tdt-0.6b-v3`**: 600 M params, multilingual across **25 European languages** (en, es, de, fr, it, pt, nl, pl, sv, da, fi, no, etc. + ru/uk), CC-BY-4.0 license, native streaming via the EOU 120 M companion model. Beats `whisper-large-v3-turbo` on European-language WER by a meaningful margin on NVIDIA's published benchmarks. ([HF model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3))

### Apple Silicon path

**It runs.** Two ports exist:

- **`parakeet-mlx`** (MLX, Python+Swift bindings): community port. The Swift wrapper [`swift-parakeet-mlx`](https://github.com/FluidInference/swift-parakeet-mlx) is **archived July 2025** and explicitly marked "not for production — too resource-intensive, ~2.5 GB model + ~100 MB / minute of audio."
- **FluidAudio** (CoreML, Apache 2.0, Swift Package): *the* viable path. Compiles Parakeet v2 (English) and v3 (25 lang) to CoreML, runs on the Neural Engine, ships [`SlidingWindowAsrManager`](https://github.com/FluidInference/FluidAudio) for live streaming with EOU detection, ~110× RTF on M4 Pro. Powers VoiceInk, Spokenly, Slipbox, BoltAI — i.e. our direct competitors. macOS 14+, iOS 17+. ([FluidAudio repo](https://github.com/FluidInference/FluidAudio))

### Quality vs Whisper

- **English:** roughly tied with `whisper-large-v3-turbo` (Parakeet ~2.5 % WER on FluidAudio internal benchmarks vs WhisperKit's distilled turbo at 2.2 %). ([source](https://www.arunbaby.com/speech-tech/0073-whisper-vs-parakeet-asr-decision/))
- **European multilingual:** Parakeet v3 wins on its 25-language set.
- **Long tail (Arabic, Japanese, Hindi, Mandarin, Korean, Vietnamese, …):** Parakeet doesn't cover them — Whisper-only.

### Verdict for CyphrWhispr

**Realistic and worth doing, as a *second* engine behind WhisperKit.** Drop in `FluidAudio` as a new `WhisperEngine` conformer (the protocol already abstracts the backend — see `Transcription/WhisperEngine.swift:13`). Selling point: lower latency than turbo on M1 + better European-language WER + native EOU streaming. Caveat: doesn't replace Whisper because it lacks 70+ languages. **Not a hot path** — implement after Apple `SpeechTranscriber` (Q3) since that's both higher-impact and lower-effort.

---

## Q3 — Apple Silicon-optimized models worth a look

### The actual landscape, ranked

1. **Apple `SpeechTranscriber` (macOS 26 / iOS 26)** — *the new entrant that changes the calculus.* 42 locales (en, es, de, fr, it, pt, nl, pl, sv, da, fi, no, ja, ko, zh, ar, he, ru, th, tr, vi, yue, ms, …), `AsyncStream` of results with `isFinal` volatile/finalized flag (i.e. exactly the partial-streaming model our floating pill needs), free, model auto-downloads, no UX cost. Argmax's own benchmark concedes Apple beats `WhisperKit-base` on WER (14.0 % vs 15.2 %), though still trails `small` (12.8 %) and turbo. ([Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax), [supportedLocales list](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide))
2. **WhisperKit `large-v3-turbo` (current)** — still the right default for macOS 14–25 and for the 50+ languages Apple doesn't cover. Argmax has a self-distilled "d750" turbo variant (smaller, faster) worth picking up when they ship the `.mlmodelc` publicly. ([WhisperKit paper](https://arxiv.org/html/2507.10860v1))
3. **Distil-Whisper** — **English-only as of May 2026.** Multilingual checkpoints have been "coming soon" for over a year. Skip until that ships. ([Distil-Whisper repo](https://github.com/huggingface/distil-whisper))
4. **MLX-Whisper / Lightning-Whisper-MLX** — Faster than CoreML for batch on M-series GPU, but **no Neural Engine path**, so it burns more battery and competes with the user's other GPU work. CoreML/ANE (what WhisperKit does) is the right backend for a menu-bar always-on app. Skip.
5. **Community fine-tunes** — none are demonstrably better than turbo for general dictation. Domain-specific (medical, legal) fine-tunes exist but are out of scope for v1.

---

## Recommended action plan

Ranked by impact ÷ effort.

1. **Multilingual support via Settings (Q1).** Add a language picker; expose `auto-detect-and-lock-per-session`, `force locale`, and `English-only` modes. Surface a multilingual model variant (`small` for default, `large-v3-turbo` for power users) in the model catalog. Effort: ~2–3 days. Unblocks the entire non-English audience.

2. **Apple `SpeechTranscriber` engine for macOS 26+ (Q3).** Add a second `WhisperEngine` conformer using `SpeechAnalyzer + SpeechTranscriber`. On macOS 26+, prefer it for the 42 supported locales; fall back to WhisperKit otherwise. This is the biggest latency + battery + UX win available and aligns with our "Polish via Foundation Models" trajectory. Effort: ~3–5 days, mostly streaming/AsyncStream plumbing. **Requires hardware testing** on macOS 26 to confirm partial-result cadence matches our 400 ms target.

3. **FluidAudio Parakeet engine as third option (Q2).** Add as opt-in for power users who want lower latency and live in the 25-language European set. Effort: ~3 days for SPM integration + protocol conformance + model-management wiring. Lower priority; ship after #1 and #2.

4. **Skip for now:** Distil-Whisper (English-only), MLX-Whisper (no ANE), community fine-tunes (no clear win).

### Open questions requiring on-device verification

- Apple `SpeechTranscriber` partial-result cadence on M1/M2/M3 — does it hit our 400 ms target, or is it slower than WhisperKit streaming?
- WhisperKit auto-detect first-segment penalty on a real M1 with our actual chunked-commit pipeline — published "few hundred ms" may be optimistic for our use case.
- FluidAudio `SlidingWindowAsrManager` behavior on push-to-talk style very-short utterances (<2 s) — its sliding-window assumes longer-form audio.

---

## Sources

- [WhisperKit (argmax-oss-swift) GitHub](https://github.com/argmaxinc/WhisperKit)
- [Argmax — Apple SpeechAnalyzer vs WhisperKit comparison](https://www.argmaxinc.com/blog/apple-and-argmax)
- [WhisperKit on-device ASR paper, arXiv 2507.10860](https://arxiv.org/html/2507.10860v1)
- [whisper.cpp GitHub](https://github.com/ggml-org/whisper.cpp)
- [Whisper code-switching discussion #2009](https://github.com/openai/whisper/discussions/2009)
- [NVIDIA Parakeet TDT 0.6B v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [FluidAudio Swift SDK](https://github.com/FluidInference/FluidAudio)
- [FluidInference Parakeet v3 CoreML weights](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [swift-parakeet-mlx (archived)](https://github.com/FluidInference/swift-parakeet-mlx)
- [Whisper vs Parakeet production decision — Arun Baby](https://www.arunbaby.com/speech-tech/0073-whisper-vs-parakeet-asr-decision/)
- [SpeechTranscriber supportedLocales list — Anton Gubarenko](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [Apple SpeechAnalyzer documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Distil-Whisper GitHub (multilingual still pending)](https://github.com/huggingface/distil-whisper)
- [Whisper model sizes — OpenWhispr](https://openwhispr.com/blog/whisper-model-sizes-explained)
- [Superwhisper Analysis 02-architecture.md](../../../../Superwhisper-Analysis/02-architecture.md) (internal)
