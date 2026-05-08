# Backup 4 — Install animation arc complete + pill alignment fix

**Date:** 2026-05-08
**Branch:** `feature/prewarm-pill-spawn-animation`
**Tag:** `backup-4`
**Previous backup:** [`backup-3`](./BACKUP-3.md)

## What's new since Backup 3

### IA9 — install path runs at runtime

Build succeeds, app launches, the pill renders correctly. The full install path (`showInstall()` → intro → 30 s rim sweep → outro → `.armed`) is wired and ships. Manual fresh-install smoke-test deferred to organic test on the next real cold-model state — the implementation is end-to-end and the alignment bug below was masking any visual sanity-check.

### Pill alignment fix — figures no longer pinned to bottom edge

`ZStack(alignment: .leading)` is `Alignment(horizontal: .leading, vertical: .center)` — children are **already vertically centred** by default. Five render bodies (`normalBody`, `spawnBody`, `installSpawnBody`, `installCompileBody`, `installOutroBody`) were applying an additional `.offset(y: (pillHeight - elementHeight) / 2)` on top of that, doubling the displacement and pinning the triangle, circle, and per-frame bars to the bottom of the capsule.

**Why it took this long to notice:** SwiftUI Previews use a 260×120 surrounding container that masked the misalignment. The bug only became obvious at runtime in the actual panel size. Bug present since `4c9e9c8` (HStack → ZStack rewrite, May 5) — predates the IA work.

**Fix:** dropped the redundant y-offset everywhere ZStack already centres. The waveform bars in `normalBody` were untouched because `WaveformView` is framed at full pill height and handles its own internal positioning.

## Commits introduced

```
f8feabe  Fix doubled y-offset that pinned pill figures to the bottom edge
```

(plus this backup commit)

## How to launch the app from now on

Skip Xcode. Build the `.app` once via `xcodebuild`, then double-click it like a normal user. From the repo root:

```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr \
  -configuration Debug -destination 'platform=macOS' build

# The built .app lives in DerivedData. Find and open it:
open ~/Library/Developer/Xcode/DerivedData/CyphrWhispr-*/Build/Products/Debug/CyphrWhispr.app
```

When you change source, re-run `xcodebuild` and re-launch. No need to keep Xcode open.

## Branch state at backup time

| Branch | Tip SHA | Notes |
|---|---|---|
| `main` | `f7902ed` | unchanged |
| `feature/prewarm-pill-spawn-animation` | `f8feabe` | this baseline (alignment fix on top of IA8) |
| `feature/polish-cleanup` | `6960438` | shipped, independent |

## Restoring to this state

```bash
git checkout backup-4
# or
git reset --hard backup-4     # destructive!
```
