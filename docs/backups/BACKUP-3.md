# Backup 3 — Install path wired end-to-end

**Date:** 2026-05-07
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-3`
**Previous backup:** [`backup-2`](./BACKUP-2.md)

## What's new since Backup 2

The first-install animation now runs end-to-end at runtime. From the user's perspective: hold the hotkey on a fresh launch (or right after a model switch) and you'll see the spawn-figures appear inside a 63 pt seed pill, push outward to the full 170 pt, the "compiling" label fade in, the determinate rim sweep around the perimeter as the model warms, and the outro hand-off into the canonical idle pill — all without anything looking frozen.

### IA7 — `PillWindowController` routes install vs spawn

Split `show()` and `showInstall()` rather than overloading `show()` with a mode parameter. The two paths have different audio-capture semantics, so keeping them separate at the API boundary keeps the call sites honest.

New surface on `PillWindowController`:
- **`showInstall()`** — present panel + play install intro, fires `onInstallIntroComplete` when done.
- **`setInstallProgress(_ p:)`** — proxy to the view model.
- **`playInstallOutro()`** — async drive of outro → `.armed`, fires `onInstallOutroComplete` on done.
- **`onInstallIntroComplete` / `onInstallOutroComplete`** callbacks.

`show()` and `hide()` both gain defensive `cancelInstall()` calls so a fresh press during a previous in-flight install doesn't leave a stale animation task running.

### IA8 — `AppCoordinator` drives the install path

- Detects `state == .loadingModel` at hotkey press → routes through `showInstall()` instead of `show()`.
- New `installPathActive` flag freezes the choice for the session.
- New `startInstallRimSweep()` drives a 30 s linear rim progress timer once the install intro completes. Cancelled and replaced by a snap to 1.0 the moment `whisper.warmUp()` resolves; if the timer reaches the end first, the rim holds at 1.0 visually.
- `whisperWarmAwaiter` now branches on `installPathActive` — install path snaps the rim and plays the outro; cinematic path falls back to the existing dual-flag gate.
- New `installOutroDone` flag is the sole streaming-start signal for the install path.
- `maybeBeginStreaming()` updated to use the right gate per path.
- Cleanup paths (early hotkey release, model switch mid-session) cancel the install rim task and reset the install-only flags.

### Pill phase progression for an install-path session

```
.installSpawning(progress: 0…1)
        ↓
.installCompiling(progress: 0…1)
        ↓
.installOutro(progress: 0…1)
        ↓
.armed
```

`AppCoordinator.state` stays at `.spawning` throughout (audio buffers locally), then flips to `.streaming` when the outro callback fires.

## Commits introduced

```
9ce509a  IA7: PillWindowController routes install vs spawn via showInstall
e73f18b  IA8: AppCoordinator drives install rim progress + outro on warm-up
```

## What's still missing

- **IA9** — manual smoke test of the full install animation flow on a fresh install with a known cold model. The implementation is complete and unit-tested; we just haven't watched it run on a real first launch yet.
- **Polish on the rim sweep** — the leading-edge gradient is approximate (linear gradient across the bounding box rather than a proper path-aware stroke). Visible only on close inspection; deferred to a v1.1 polish pass.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `e73f18b` | this baseline |
| `feature/polish-cleanup` | `6960438` | shipped, independent |

## Restoring to this state

```bash
git checkout backup-3
# or
git reset --hard backup-3     # destructive!
```
