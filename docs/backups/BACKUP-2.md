# Backup 2 — IA6 complete

**Date:** 2026-05-07
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-2`
**Previous backup:** [`backup-1`](./BACKUP-1.md)

## What's new since Backup 1

### IA6 — install phases now render in `PillView`

Three new render paths gate behind their matching `PillPhase` cases. All motion math is sourced from the existing `InstallTimeline` driver — these views are pure declarative renderers with no animation logic of their own.

- **`installSpawnBody(progress:)`** — figure spawn at seed-pill (63 × 48), compress to 60 during anticipation, symmetric expand to 170 with figures pinned to walls, "compiling" label fades in during the post-push hold.
- **`installCompileBody(rimFraction:)`** — static pill with figures at the install-hold extremes (triangle x=12, circle x=141), breathing "compiling" label on a 3 s sine cycle, determinate rim sweep starting at 12 o'clock and going clockwise.
- **`installOutroBody(progress:)`** — rim fades, label drops 4 pt and fades, triangle slides 12 → 22, circle traverses 141 → 47, seven bars cascade right-to-left with a 3 pt y-translate, comet rim ignites with a gaussian brightness flash. End-frame pixel-identical to idle.

### `ProgressRim` view

Capsule outline drawn as a SwiftUI `Path` starting at top-centre clockwise, trimmed to `fraction` of the perimeter. Two stacked strokes (5 pt blurred halo + 2.5 pt crisp core with leading-edge gradient) — the same two-stroke recipe the comet rim uses, but determinate. Rendered inside a `Canvas` so we control the exact path geometry, since SwiftUI's built-in `Capsule().trim` doesn't guarantee where the trim starts.

### SwiftUI Previews

Five static frames across the install timeline at instructive progress points:
- Intro push (mid)
- Intro hold (label fading in)
- Compiling 67 %
- Outro mid (bars cascading)
- Outro late (comet igniting)

Plus one self-driving live demo (`Install - full sequence (Live)`) that loops the full intro → compile → outro choreography using the same `PillViewModel` API the production `AppCoordinator` will use. Click the canvas play button to watch it animate.

### Browser-friendly verification

A self-contained HTML preview lives at `Visual Aides/Design System Export/Pill Reference/install-animation-live.html` — JS translation of `InstallTimeline.swift`'s exact math, with play/pause/scrub controls and a phase timeline. Useful when SwiftUI's preview canvas is misbehaving or when you want to inspect a specific frame at slow speed.

## Commits introduced

```
30f3717  IA6: render installSpawning / installCompiling / installOutro in PillView
1ad44b4  IA6 verification: add self-driving install-sequence preview
```

## What's still missing (the IA7 → IA9 work to come)

- **IA7** — `PillWindowController.show()` doesn't yet branch between cinematic spawn and install animation. Today it always plays spawn even when the model is mid-warm-up. Need a separate `showInstall(onIntroComplete:)` entry point.
- **IA8** — `AppCoordinator` doesn't detect `state == .loadingModel` at hotkey press to choose the install path, drive the 30 s linear rim progress timer, and snap to 1.0 + play outro on warm-up complete.
- **IA9** — no manual smoke test of the full install animation flow on a fresh install.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `1ad44b4` | this baseline |
| `feature/polish-cleanup` | `6960438` | shipped, independent of this work |

## Restoring to this state

```bash
git checkout backup-2
# or
git reset --hard backup-2     # destructive!
```
