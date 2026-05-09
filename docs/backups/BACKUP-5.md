# Backup 5 — Polish merged + sanitiser + install-animation arc complete

**Date:** 2026-05-09
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-5`
**Previous backup:** [`backup-4`](./BACKUP-4.md)

## What this backup represents

The state where:
- Both feature branches (`feature/prewarm-pill-spawn-animation` and `feature/polish-cleanup`) are unified onto a single tip.
- The install animation is the canonical first-press choreography on every fresh launch — no ".idle pill flash" before it begins.
- Whisper noise tokens never leak into the user's pasted text.
- The dev workflow is fully Xcode-free; one script command rebuilds and replaces `/Applications/CyphrWhispr.app` in place.
- Strategic groundwork (Superwhisper takeaways) is documented for future planning.

## Commits introduced since Backup 4

```
33bff9d  Eliminate first-frame .idle flash before install animation starts
a2659e2  Add Superwhisper takeaways — what's worth stealing, what isn't
1b1cbc0  Pin xcodebuild output to repo-local DerivedData
0bc8c2d  Fix banker's-rounding surprise in cleanup timeout formatter
cc5d492  Merge branch 'feature/polish-cleanup' into feature/prewarm-pill-spawn-animation
ecce680  Make install animation play on every session's first hotkey press
7bdd4dc  Add build-and-install script — kill Xcode dependency for daily dev
72e56be  Strip Whisper special tokens + parenthesised noise labels
6960438  Add Polish — Apple Foundation Models cleanup pass  (from polish-cleanup branch)
```

## What's in the running app right now

### Install animation arc
- Fires on every first hotkey press of a session (regardless of warm-up state)
- Adaptive rim sweep duration: **1 s** when model already warm (cached), **30 s** when genuinely cold-compiling
- Race fix: outro can't fire mid-intro even when warm-up resolves during the intro
- First frame is the install intro at progress 0 (seed pill, figures invisible) — no idle-pill flash
- Pill alignment fix: triangle/circle/bars vertically centred (no longer bottom-pinned by doubled offsets)
- Resets `hasPlayedSessionFirstPress` on model switch so a new model gets its install animation again

**Code locations:**
- `CyphrWhispr/App/AppCoordinator.swift` — gate logic, race fix, rim driver
- `CyphrWhispr/PillWindow/PillWindowController.swift:92-155` — phase pre-set + show/showInstall
- `CyphrWhispr/PillWindow/PillView.swift:175-243` — render bodies (alignment fix in normalBody + 4 install bodies)
- `CyphrWhispr/PillWindow/InstallTimeline.swift` — pure-math driver

### Apple Foundation Models polish pass
- Settings → Polish tab with master toggle + customisable cleanup prompt
- Availability hint reflecting macOS 26 / Apple Intelligence / model status
- 3 s hard timeout with raw-transcript fallback
- Length-ratio sanity check rejects hallucinated output
- Banker's-rounding fix in timeout formatter

**Code locations:**
- `CyphrWhispr/Cleanup/CleanupPrompt.swift`
- `CyphrWhispr/Cleanup/TranscriptionCleaner.swift`
- `CyphrWhispr/Settings/PolishTabView.swift`
- `CyphrWhispr/Settings/PreferencesStore.swift` — polish state
- `CyphrWhispr/App/AppCoordinator.swift` — polish() integration

### Transcript sanitiser
- Strips three artifact classes: special tokens (`<|...|>`), all-caps bracket labels (now including hyphens), parenthesised noise labels (allowlisted)
- 19 tests including the user's exact leaked output as a regression fixture
- Negative cases prove `(see page 12)` and `[appendix]` pass through unchanged

**Code locations:**
- `CyphrWhispr/Transcription/TranscriptSanitizer.swift`
- `CyphrWhisprTests/TranscriptSanitizerTests.swift`

### Xcode-free dev workflow
- `./scripts/build-and-install.sh` does everything: kill running → xcodegen → xcodebuild → copy to /Applications → launch
- Outputs to repo-local `build/derived/` (gitignored), kills the stale-binary roulette where `ls -td` was picking the wrong DerivedData folder
- Flags: `release` for Release config, `--no-launch` to skip auto-open

**Code locations:**
- `scripts/build-and-install.sh`

### Strategic docs
- `docs/strategy/2026-05-09-superwhisper-takeaways.md` — phase-by-phase amendment to v1 plan with ranked priorities (modes / URL scheme / agent integration / vocabulary / etc.)
- `docs/backups/BACKUP-1.md` through `BACKUP-5.md`

## Polish backlog — things worth revisiting later

Stuff that works but has rough edges, or that we shipped quickly knowing we'd revisit. Listed so the next polish pass can attack each precisely.

### Animation polish
- **Rim sweep duration** — Currently a static 30 s for cold compile, 1 s for warm. Could be smarter: query WhisperKit for actual estimated warm-up time, drive the rim from real progress callbacks instead of a wall-clock guess.
- **Outro hand-off** — The transition from `.installOutro` → `.armed` is functional but the comet-rim ignite is a hard cut from the determinate progress rim. Could cross-fade more deliberately.
- **Cinematic spawn on second-press** — Now that install plays first-press, the cinematic spawn animation is slightly redundant. Consider replacing it with a simpler "pill appears, ready" treatment (or removing it entirely so second-press is instant).
- **Compile label breathing** — 3 s sine cycle is fine; some users might prefer dot-progress text ("compiling.", "compiling..", "compiling...") for variety.
- **Seed pill width 63 pt** — Was the original spec; could be tuned smaller (e.g. 48 pt = pill height) for a more "pill grows from a coin" feel.
- **Install intro duration 2 s** — Slightly long for warm-model case where the user already pressed the hotkey expecting to dictate. Could drop to 1.4-1.6 s when warm-up is fast.

### Pill / window
- **Single-instance enforcement** — Two menu-bar icons appear briefly during Xcode `⌘R` cycles. Real users would never see this, but if a user double-clicks the .app while it's running, a new instance spawns. Use NSRunningApplication / LSUIElement detection to bring the existing instance forward instead.
- **Sendable closure warnings in `PillWindowController.hide()`** — Two yellow warnings about `panel` and `level` mutated from a Sendable closure. Pre-existing, harmless, but should be fixed for a clean compile.
- **Pill drag-to-move** — Implemented but the snap thresholds are guesstimates; could use a proper user test.

### Build / dev
- **Codesign race retry** — Sometimes the first `build-and-install.sh` after a code change hits `CodeSign … failed` because the running app holds files open. The `pkill -x` + `sleep 1` we have helps but isn't bulletproof. Add a retry loop.
- **Don't relaunch if the user explicitly killed** — Right now the script auto-launches after install. If the user just wanted to copy a binary into /Applications/ without reopening, `--no-launch` works but isn't intuitive.
- **AudioRingBuffer overflow bug** — Pre-existing test failure (`testRingBufferOverflowDropsOldest` expects last 4 of `[1..6]` but gets count 1). Already flagged as side-task chip; would be cleanly fixable.

### Polish / cleanup tab
- **Modes system supersedes Polish tab** — Per the Superwhisper takeaways doc, modes (named per-use-case configurations of model + prompt + audio settings) should replace the single global Polish prompt. The Polish tab will become legacy.
- **Polish prompt customisation UI** — The "Customise prompt" sheet works but lacks a "preview what cleaned output looks like for [example transcript]" step. Would help users tune.

### Transcription
- **Multilingual model** — Default is English-only (`small.en`). Switching to multilingual currently requires manually downloading via Settings → Models. The Whisper noise tokens (`(speaking in foreign language)`) the sanitiser strips ARE the symptom of an English-only model hearing non-English audio. Real fix: prompt the user to switch to multilingual on first non-English detection, or detect language at the audio stage.
- **Vocabulary editor** — Per takeaways doc; not built. Custom proper-noun list fed as `initial_prompt`.
- **Streaming partials cancellation** — When the user releases the hotkey mid-stream, partials in-flight may briefly type extra text before the final commit settles. Edge case; rarely visible.

### History (Phase 4 — not yet built)
- BIP-39 + encrypted store + history browser entirely pending. Per the original plan.

### Settings UX
- **Settings tabs ordering** — General, Models, Polish, Shortcut, About. Modes (when added) should slot between Models and Polish. About could move down or merge into a "?" button.
- **No "About" content yet** beyond the accent picker — needs version, license, GitHub link, credits.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged (this work has never been merged to main) |
| `feature/prewarm-pill-spawn-animation` | `33bff9d` | this baseline (now also contains the polish-cleanup work via merge `cc5d492`) |
| `feature/polish-cleanup` | `6960438` | merged into prewarm; safe to delete after backup-5 |

## Restoring to this state

```bash
git checkout backup-5
# or
git reset --hard backup-5     # destructive!
```

## Suggested next moves

Three forward paths from here, in order of recommended attack (per the takeaways doc):

1. **URL scheme** (`cyphrwhispr://record` etc.) — half-day, unlocks Raycast/Alfred/Shortcuts and lays groundwork for modes.
2. **Modes system** — ~1 week, replaces the single Polish prompt with named per-use-case configurations.
3. **Phase 4: Encrypted history + BIP-39** — the remaining v1 feature from the original plan.

Or — what the user has just asked for — **research multi-language strategies + NVIDIA Parakeet + Apple Silicon-tuned model options** before deciding which engine improvements to prioritise. That work is happening on a parallel research track, output landing in `docs/strategy/`.
