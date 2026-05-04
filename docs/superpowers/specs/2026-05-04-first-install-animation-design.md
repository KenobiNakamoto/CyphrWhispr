# First-Install Animation — Design

**Date:** 2026-05-04
**Status:** Draft, pending user review
**Scope:** UX for the one-time Core ML compile that happens when WhisperKit first encounters a model on a given Mac

## Goal

When the user first installs CyphrWhispr (or downloads a new Whisper model), Core ML must compile the `.mlmodelc` bundles for the user's specific Apple Silicon variant. This is a 30–90 second one-time cost per model. We need an animation that:

1. Appears at the same physical pill position as the regular floating widget (170 × 48). Not a separate onboarding card.
2. Reuses the user-approved cinematic spawn intro (figures fade in at centre, anticipation, push outward) — but with the circle pinned to the right wall during the push so it visually shoves the wall open.
3. Replaces the waveform area with a single word — **"compiling"** — that breathes softly.
4. Uses the pill's rim as a determinate progress indicator. The leading edge of the rim sweeps clockwise around the pill perimeter starting from top centre; the trailing edge stays anchored at top centre. Full coverage = compile done.
5. Hands off cleanly into the normal pill via the same end-of-spawn outro the user already approved (circle traverses leftward, bars cascade in behind it, comet rim ignites).

## Why this matters

The first-install Core ML compile is the single most jarring "the app is frozen" moment in the entire experience. Without explicit feedback the user assumes:

- The app is broken
- They installed it wrong
- Their Mac is too slow

A bare progress bar would do the job, but feels like installer chrome. Reusing the pill (the visual signature of the app) and treating the compile as **the pill being born** turns a frustrating wait into a small moment of theatre — the user's first impression of the app's personality.

## Scope and non-goals

**In scope:**

- The pill's intro animation (synced spawn + push, with the circle visibly shoving the right wall open)
- The "compiling" centre label and its fade-in / breath / fade-out timing
- The progress rim (clockwise sweep from top centre, leading edge maps to compile fraction, fallback cadence)
- The "still working" fallback when compile exceeds the fallback cadence with no real-progress callback available
- The outro back into the normal pill state (traverse + bar cascade + comet ignite)
- Where the pill lives during this — same floating-pill window, not a separate onboarding scene
- Integration with `WhisperKitBackend` to receive compile-progress callbacks if available

**Out of scope:**

- The wider onboarding flow (mic permission, accessibility permission, hotkey picker, BIP-39 phrase generation). Those are separate Phase-4 work.
- The decision of WHEN to trigger the first-install animation — that's gated by `AppCoordinator` detecting a not-yet-compiled model on launch, which is a separate small piece of logic specced inline below but not the main story here.
- Failure handling (compile fails, model file corrupt, disk full). Will be specced separately when we tackle pre-warm failure UX.
- Bringing the user into the app post-compile — once the outro completes, the user is in the normal idle state. They still need to be told the app is ready (toast, menu-bar pulse, or just trust they'll notice the pill is gone). Decide separately.

## Reference

Final approved mockup: [`assets/2026-05-04-first-install-animation-mockup.html`](assets/2026-05-04-first-install-animation-mockup.html)

The mockup runs the full cycle in 11 seconds (intro + accelerated 8s rim + outro) so the choreography can be reviewed in a reasonable time. Production cadence for the rim sweep is 45 seconds (or driven by actual compile fraction when available).

## Animation choreography

All values at the production pill scale (170 × 48). Mockup is at 2× scale (340 × 96) — halve every pixel value to translate.

### Phase timeline

| Phase                | Time            | What happens                                                                                                                                                                     |
| -------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Spawn**            | 0 → 0.6s        | Triangle and circle fade in (opacity 0→1) and scale up (0.5→1) simultaneously. Both already at their respective wall positions inside a 63pt-wide seed pill (triangle at left=12 with 12 left padding; circle at left=34 with 12 right padding; 8pt gap between them). Circle trails triangle by 60ms. |
| **Anticipation**     | 0.6 → 0.85s     | Pill compresses from 63pt → 60pt wide. Both figures stay glued to their walls (triangle slides 1pt right with the wall; circle slides 1pt left with the wall). Both scale down to 0.97×. |
| **Push (synced)**    | 0.85 → 1.7s     | Pill expands from 60pt → 170pt wide. Triangle's relative position stays at left=12 (constant — wall padding never changes). Circle's relative position follows `pill_width − 29` (constant — same right padding). Both animate with `cubic-bezier(0.16, 0.84, 0.30, 1)` so the circle and right wall move at identical velocities. The whole pill does a 1.02× breathe at the apex. |
| **Hold + label-in**  | 1.7 → 2.0s      | Pill at full 170pt width. Figures at extremes. "compiling" fades in at centre with a small upward translate (0 → 4pt easing in). Subtext omitted — single word feels stronger.   |
| **Rim sweep**        | 1.7s → ~46.7s   | The rim ring's leading edge sweeps clockwise from top centre. Trailing edge stays anchored at top centre. Driven by either real compile-progress callback OR a 45s linear fallback. "compiling" breathes (opacity 0.85 ↔ 1.0, 3s cycle). |
| **Outro**            | ~46.7s → 47.7s  | Once the rim is full: slow rim fades out (0.6s), "compiling" fades out (0.4s), circle glides leftward from `left=141` to `left=46` (next-to-triangle position) over 1.0s with the same easing curve, bars cascade in right-to-left behind the moving circle (same stagger as the spawn-animation outro: ~0.18s between each bar starting from rightmost), comet rim fades in and starts its normal 4.4s rotation. |

### Geometry — why the push feels synced

The mismatch in the previous iteration was that the circle moved at a different speed than the right wall during the push. Now the circle's position is held at a constant offset from the right wall throughout the entire animation:

```
circle_relative_left(t) = pill_width(t) − 29   // production scale
                        = pill_width(t) − 58   // mockup 2× scale
```

Both `pill_width` and `circle_relative_left` use the same easing curve (`cubic-bezier(0.16, 0.84, 0.30, 1)`), so the relationship holds at every intermediate frame, not just at keyframes. The circle visually pins to the right wall.

The same trick on the left side: triangle's relative position is constant at `left = 12` (production) or `left = 24` (mockup). As the pill expands, the left wall moves leftward in stage coords and the triangle moves leftward with it, glued to the wall.

### Rim ring math

The pill is a horizontal capsule: `170 × 48` with corner radius `24` (= H/2). Its perimeter:

```
P = 2(W − 2R) + 2πR
  = 2(170 − 48) + 2π(24)
  = 244 + 48π
  ≈ 394.8 pt   // production
  ≈ 789.6 pt   // mockup at 2×
```

The rim is a single SVG path starting at top centre `(W/2, 0)` and going clockwise around the capsule. Two strokes are layered:

- A 5pt-wide blurred halo (`#7C4DFF` at 35% opacity, `blur(3px)`) that bleeds outside the pill
- A 2.5pt-wide crisp core with a `linearGradient` from `rgba(255,255,255,0.85)` → violet → blue

Both share `stroke-dasharray: P P` and a `stroke-dashoffset` that animates from `P` (nothing visible) to `0` (full coverage).

When real compile progress is available, the dashoffset is set imperatively to `P × (1 − fraction)` so the leading edge always reflects the actual percentage. When unavailable, a 45-second linear `keyframes` animation drives it.

### Color: respects the user's accent

Both the rim and the comet ignite use the user's chosen accent colour from `PreferencesStore.accent`. Default is the violet (#7C4DFF). The mockup hard-codes the default; production reads `prefs.accent` live so a colour change in Settings → About retints the rim immediately.

## Architecture

### `PillPhase` (in `PillView.swift`) — additional cases

```swift
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    case spawning(progress: Double)
    case armed
    case listening
    case processing
    // NEW for first-install:
    case installSpawning(progress: Double)   // 0 → 1 over the 2.5s intro
    case installCompiling(rimFraction: Double)  // 0 → 1; rim leading edge position
    case installOutro(progress: Double)      // 0 → 1 over the 1s outro
}
```

The `installSpawning` phase is structurally identical to `spawning` from the pre-warm spec but with the circle ending at the far-right "hold" position (left = 141 production, 282 mockup) instead of traversing back. We could share the spawn keyframes as a helper, but I'd prototype both as standalone phases first and refactor for shared keyframes only if the duplication grows painful.

### `PillViewModel` — new driver methods

```swift
@MainActor
final class PillViewModel: ObservableObject {
    @Published var phase: PillPhase = .idle
    // …existing fields

    private var installSpawnTask: Task<Void, Never>?
    private var installOutroTask: Task<Void, Never>?

    /// Run the install intro: spawn + push + label-in. After this completes,
    /// the caller transitions to .installCompiling(rimFraction: 0).
    func playInstallSpawn(duration: TimeInterval = 2.5) async {
        installSpawnTask?.cancel()
        installSpawnTask = Task { @MainActor in
            await runProgressTimeline(duration: duration) { t in
                phase = .installSpawning(progress: t)
            }
        }
        await installSpawnTask?.value
    }

    /// Set the rim's leading-edge position. Called by the coordinator
    /// either from a WhisperKit progress callback (real fraction) or from
    /// a fallback DispatchSourceTimer driving a 45s linear fill.
    func setInstallCompileFraction(_ f: Double) {
        phase = .installCompiling(rimFraction: min(max(f, 0), 1))
    }

    /// Run the outro: rim fades, label fades, circle traverses, bars
    /// cascade, comet ignites. After this completes, the caller transitions
    /// to .idle (the pill window hides) or .armed (if user is holding hotkey).
    func playInstallOutro(duration: TimeInterval = 1.0) async {
        installOutroTask?.cancel()
        installOutroTask = Task { @MainActor in
            await runProgressTimeline(duration: duration) { t in
                phase = .installOutro(progress: t)
            }
        }
        await installOutroTask?.value
    }
}
```

(The `runProgressTimeline` helper is a small util that polls at ~60Hz and yields normalized progress 0→1. Already useful for the pre-warm spawn; we extract it from there.)

### `AppCoordinator` — first-install detection and orchestration

On `applicationDidFinishLaunching`, the coordinator checks whether the active model has been compiled:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
        let needsInstall = !WhisperKitBackend.isModelCompiled(prefs.activeModelID)
        if needsInstall {
            await runFirstInstallSequence()
        } else {
            // Normal pre-warm path (separate spec)
            startPreWarm()
        }
    }
}

private func runFirstInstallSequence() async {
    // Show the pill in install-spawn mode, regardless of hotkey state.
    pillController.show(initialPhase: .installSpawning(progress: 0))
    await pillVM.playInstallSpawn()

    // Kick off WhisperKit's compile in the background. If WhisperKit's
    // ModelCompileProgress callback is available, route it to the pill.
    let compileTask = Task.detached {
        await whisperKit.compileModel(prefs.activeModelID) { fraction in
            await self.pillVM.setInstallCompileFraction(fraction)
        }
    }

    // Fallback: if we don't get a progress callback within 1.5s of compile
    // start, drive a 45s linear fill.
    startFallbackProgressIfNeeded()

    await compileTask.value
    await pillVM.playInstallOutro()
    pillController.hide()
}
```

The "fallback ring" is just a 45s `Timer.publish` that increments `rimFraction` linearly until either real progress kicks in (in which case the timer cancels) or the rim hits 1.0 (in which case it stops at 1.0 and the rim pulses — see "Failure modes" below).

### `WhisperKitBackend` — `isModelCompiled(_:)` + `compileModel(_:onProgress:)`

The backend exposes two new methods:

```swift
extension WhisperKitBackend {
    /// Whether the given model has its Core ML caches built for this device.
    /// Checks for the presence of compiled artifacts in WhisperKit's cache dir.
    static func isModelCompiled(_ modelID: String) -> Bool { /* fs check */ }

    /// Compile the model. WhisperKit may or may not surface a progress callback;
    /// when it does, we forward the fraction. When it doesn't, the closure is
    /// called once with 1.0 at completion and the fallback timer drives the UI.
    /// The exact WhisperKit API surface we wrap is determined during the
    /// implementation phase (likely `WhisperKit.loadModels(...)` plus an
    /// `Observable` wrapping its internal compile-progress signal — but
    /// confirming this is implementation work, not spec work).
    func compileModel(_ modelID: String,
                      onProgress: @escaping (Double) async -> Void) async throws
}
```

### `PillView` — rendering the new phases

The `body` switches on `viewModel.phase`. For `.installSpawning(progress: t)` and `.installOutro(progress: t)` we compute the staged visual state from `t` (same approach as the pre-warm spawn). For `.installCompiling(rimFraction: f)`, we render a static pill (figures at extremes, "compiling" label) with the rim's `stroke-dashoffset` set to `P × (1 − f)`.

```swift
@ViewBuilder
private var body_phaseSwitch: some View {
    switch viewModel.phase {
    case .installSpawning(let t):
        installSpawnLayer(progress: t)
    case .installCompiling(let f):
        installCompilingLayer(rimFraction: f)
    case .installOutro(let t):
        installOutroLayer(progress: t)
    case .idle, .spawning, .armed, .listening, .processing:
        existingPhaseRendering
    }
}
```

### `PillWindowController`

`show(initialPhase:)` is a new overload that lets `AppCoordinator` show the pill directly into a non-armed state (specifically `.installSpawning`) without going through the hotkey path.

## Failure modes

| Scenario                                                                               | Behavior                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WhisperKit gives us no `onProgress` callbacks                                          | Fallback timer drives the rim at 45s linear fill. If compile is still running when the rim is full, the rim pulses (subtle 1.0× → 1.1× brightness breath, 2s cycle) until real completion arrives. Then play the outro.                                   |
| WhisperKit's progress callback fires inconsistently                                    | Each callback updates `rimFraction` directly. The rim "jumps" to the new value with a 0.3s ease-out interpolation (so a sudden jump from 0.2 → 0.8 isn't jarring). No fallback timer interferes once any real callback has fired.                          |
| Compile takes >>45s but produces real progress                                         | Rim fills as slow as needed. No pulse. No fallback. The rim is the truth.                                                                                                                                                                                  |
| Compile fails with an error                                                            | Out of scope for this spec — handled by separate failure-handling design. Placeholder behavior: cancel the install sequence, hide the pill, surface the error via menu-bar icon + tooltip.                                                                |
| User attempts to interact with the pill during the install sequence                    | The install pill is non-interactive. Hotkey presses are queued (NOT lost — the coordinator buffers them). On install-outro completion, if the hotkey is still held, the pill transitions directly into `.armed` and starts capturing audio.               |
| User quits the app during compile                                                      | Compile task cancels (detached, so it cleans up). Next launch detects "not compiled" and replays the entire install sequence from scratch. Acceptable — compile resume across launches is a WhisperKit concern, out of scope here.                       |
| User triggers a model switch during compile                                            | The current install sequence cancels. The pill plays a 0.4s fade-out, then the install sequence restarts with the new model. (Same architectural path as launching — `runFirstInstallSequence()` is just called again.)                                  |
| User on multi-monitor setup; pill appears on wrong screen                              | Out of scope — same pill-positioning logic as the regular floating widget. Whatever rules apply to the pre-warm spawn apply here.                                                                                                                          |

## Test plan

1. **Fresh install on a Mac that has never compiled this model.** Quit, delete the WhisperKit cache directory, relaunch. Pill should appear with the install-spawn intro, "compiling" label fades in, rim sweeps clockwise from top centre as compile progresses. On compile completion, outro plays and the pill disappears (or transitions to armed if hotkey is held).
2. **Subsequent launches.** After test #1, the model is compiled. Relaunch. Install sequence should NOT play. Pre-warm path (separate spec) takes over.
3. **Model switch in Settings → Models triggers a fresh install.** Switch to a model that hasn't been compiled on this device. Install sequence plays for the new model.
4. **Real progress callback drives the rim.** Verify by adding a test hook that logs `rimFraction` updates and visually confirming the rim's leading edge matches.
5. **Fallback timer engages when no callback fires.** Mock WhisperKit to suppress progress callbacks. Rim should fill in 45s (visually verifiable via a ↻Replay button in dev mode).
6. **Compile longer than fallback.** Mock a 120s compile with no callbacks. Rim fills in 45s, then pulses for 75s, then outro plays at compile completion.
7. **User holds hotkey during install.** Confirm the hotkey is queued and the pill transitions cleanly to `.armed` (with audio capture started) the moment the outro completes.
8. **Cancellation.** User quits during compile — no crash, no orphaned pill, no leaked tasks.

Performance budget: the install pill should hold 60fps throughout. The compile work itself runs on the Neural Engine / GPU, so the CPU has headroom for the animation.

## Approval

User signs off here before we move to writing-plans:

- [x] Choreography matches the v4 mockup
- [x] Push is synced (circle pinned to right wall throughout)
- [x] Real progress mapping with 45s fallback cadence
- [x] Pulse the full ring as "still working" indicator if compile exceeds fallback
- [x] Word: "compiling"
- [x] Outro = end-of-spawn-v5 (traverse + bar cascade + comet ignite)
