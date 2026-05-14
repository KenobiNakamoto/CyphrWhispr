# Backup 1 — Pre-IA6 Baseline

**Date:** 2026-05-07
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-1`
**Commit at tag time:** `8518a6a` — *Settings UI: switch typography to Monaspace Krypton*

## Why this backup

This is our last known-good state before resuming the **first-install pill animation** work (IA6 → IA9 from `docs/superpowers/plans/2026-05-05-first-install-pill-animation.md`). IA6 touches `PillView` significantly — adding new render paths for the install intro / compile / outro phases — and a regression here would be visible the moment the user holds the hotkey. Worth a snapshot before we change rendering.

## What's in this state

### Working features
- **Cinematic spawn animation** when the hotkey is pressed for the first time in a session (or after a model switch). Pill fades in at seed-pill geometry, breathes, expands to full width, comet rim ignites.
- **Live streaming transcription** with chunked commits — partials revise within a bounded ~2 s tail window, no runaway re-transcribe on long sessions.
- **Paste/clipboard race fix** — final commit goes through `typeUnicode(_:)` (Unicode keystroke events carry text in the payload, no clipboard read needed) so the receiving app can't paste the just-restored old clipboard on top of the transcription.
- **Settings UI in Monaspace Krypton** across all four weights (Regular / Medium / SemiBold / Bold), bundled via `Resources/Fonts/` and registered at app launch via `ATSApplicationFontsPath` in Info.plist.
- **Three Settings tabs** — Shortcut, Models, About — each fully functional and on-brand.
- **All 47 existing tests pass**, including `SpawnTimelineTests` and `InstallTimelineTests`.

### Foundation in place for IA6 (not yet rendered)
- `InstallTimeline.swift` — pure-math driver for the install intro + outro phases. Geometry constants, phase boundaries, easing curves all defined and unit-tested.
- `PillPhase` enum has `.installSpawning(progress:)`, `.installCompiling(progress:)`, `.installOutro(progress:)` cases.
- `PillViewModel` has `playInstallSpawn(duration:)`, `setInstallProgress(_:)`, `playInstallOutro(duration:)` async methods that drive a 60 Hz progress timer.
- `WaveformView` treats install phases as `.idle` (resting heights, no animation) — defensive default until PillView renders the install path explicitly.

### What's missing (the IA6→IA9 work to come)
- **IA6** — `PillView` doesn't render the install phases yet. Holding the hotkey during `.loadingModel` falls through to `normalBody`, which means the user sees the regular pill instead of the install-specific intro/compile/outro choreography.
- **IA7** — `PillWindowController.show()` doesn't yet branch between the cinematic spawn and the install animation. Today it always plays spawn.
- **IA8** — `AppCoordinator` doesn't detect `state == .loadingModel` at hotkey press to drive a 30 s linear rim progress timer + snap to 1.0 + outro on warm-up complete.
- **IA9** — no manual smoke test of the full install animation flow on a fresh install.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `8518a6a` | this baseline |
| `feature/polish-cleanup` | `6960438` | shipped; lives independently from this work |

## Restoring to this state

```bash
git checkout backup-1               # detach HEAD on the tag
# or
git reset --hard backup-1           # nuke local changes back to here (destructive!)
```

To branch off this state without disturbing current work:

```bash
git checkout -b experiment-from-backup-1 backup-1
```
