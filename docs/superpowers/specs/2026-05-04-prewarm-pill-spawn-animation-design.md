# Pre-Warm Pill Spawn Animation — Design

**Date:** 2026-05-04
**Status:** Draft, pending user review
**Scope:** UX side of latency improvement #1 (first-press freeze)

## Goal

When the user fires the hotkey for the first time after an app launch, play a cinematic 3.6s "spawn" animation. This animation visually decouples the pill's appearance from Whisper engine readiness, makes the unavoidable pre-warm wait feel intentional, and ensures no spoken audio is lost during the warm-up window.

After this first appearance, every subsequent hotkey press in the same session uses the existing instant pill appearance — the animation is the launch ritual, not a per-press effect. The animation also replays once after the user switches the active Whisper model in Settings (since switching models triggers a fresh pre-warm of the new model and a brand-new "first press" feel).

## Why this matters

Today, when you quit and relaunch CyphrWhispr and immediately press the hotkey, two things go wrong:

1. **The pill may not appear at all** — the global hotkey hasn't been registered yet, the press goes to /dev/null. (Fixed separately as part of latency #1's "fast hotkey registration" item.)
2. **Even when the pill DOES appear, transcription doesn't start for 1–3s** — Whisper has to load the Core ML model into memory. The pill sits frozen, the user assumes the app is broken.

The spawn animation is the visible counterpart to the invisible pre-warm work happening in the background. It tells the user:

- "I heard you press the hotkey." (pill appears immediately)
- "I'm getting ready." (the spawn motion is purposeful, not a freeze)
- "I haven't dropped your speech." (audio is captured into the ring buffer from the moment you press)
- "Now I'm ready to transcribe." (the animation completes into the normal listening pill)

## Scope and non-goals

**In scope for this spec:**

- The SwiftUI implementation of the spawn animation in `PillView`
- The state-machine integration — adding a `.spawning` phase before `.armed`
- The "first-spawn-per-session OR after a model switch" gating logic in `PillWindowController`
- Audio queueing during the animation (capture into buffer, defer transcription until animation completes AND engine is ready)
- Behavior when pre-warm completes mid-animation (let it play out — see "Open questions")

**Out of scope (separate work items under latency #1):**

- The actual Whisper pre-warm logic on `applicationDidFinishLaunching` — kicking off the background model load. This is its own design.
- AVAudioEngine pre-warm.
- Reordering launch sequence so global hotkey registration is the first thing that happens.
- First-install Core ML compile progress UI (the 30–90s one-time onboarding screen). Separate brainstorm + spec.
- Pre-warm failure handling (model corrupt, disk full, etc.). Separate spec.
- The full first-install / first-time-model-download experience. That gets its own (different) animation — a longer, looping compile-progress sequence that lives inside the onboarding window, not on the floating pill. Designed in a separate spec.

## Animation choreography

Final reference: [`assets/2026-05-04-prewarm-pill-spawn-animation-mockup.html`](assets/2026-05-04-prewarm-pill-spawn-animation-mockup.html) — open in any browser to see the approved cinematic v5 choreography auto-loop.

Six phases over 3.6s:

| Phase            | Time          | What happens                                                                                                                                                   |
| ---------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Spawn**        | 0 → 0.6s      | Triangle and circle fade in (opacity 0→1) and scale up (0.5→1) simultaneously, side-by-side at the centre of a 90pt-wide seed pill. Circle trails triangle by 60ms.|
| **Anticipation** | 0.6 → 0.85s   | Tiny inward lean — figures shrink to 0.97×, pill compresses to ~84pt wide. Reads as "drawing breath."                                                          |
| **Push**         | 0.85 → 1.7s   | Symmetric outward shove. Triangle slides leftward to its final left position; circle slides rightward to the far right edge of the (now-expanded) 340pt pill. The pill widens between them. Whole-pill scales up 1.02× during this phase. |
| **Hold**         | 1.7 → 2.0s    | Brand-mark money shot — triangle at left edge, circle at far right edge, pill at full width, no waveform yet.                                                  |
| **Traverse**     | 2.0 → 3.0s    | Circle glides leftward from the far-right hold position to its final position next to the triangle. As it moves, the waveform bars cascade in behind it (right-to-left stagger, ~0.18s between each). |
| **Ignite**       | 3.05 → 3.6s   | Comet rim fades in with a 1.6× brightness flash, then settles into the normal cometSpin animation. Pill is now in normal `.listening` (or `.armed`) state.    |

### Easing

Single global curve for the layout-driving animations: `cubic-bezier(0.16, 0.84, 0.30, 1)` — slow start, accelerated middle, soft settle. SwiftUI equivalent: `.timingCurve(0.16, 0.84, 0.30, 1, duration: 3.6)`.

Bar fade-ins use `cubic-bezier(0.22, 1, 0.36, 1)` (snappier, since each bar is a small reveal). The comet ignite flash uses ease-out.

### Scale at production size

The mockup runs at 2× scale (340 × 96) for visibility. Production pill is 170 × 48. All pixel values in this doc refer to the **production scale** unless explicitly marked otherwise; halve the mockup's CSS pixel values to get production values.

## Architecture

### `PillPhase` (in `PillView.swift`)

Add a new case:

```swift
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    case spawning(progress: Double)  // NEW — 0.0 → 1.0 over 3.6s
    case armed
    case listening
    case processing
}
```

The `progress` parameter is a normalized 0–1 timeline that drives all the staged sub-animations. `PillView` reads it and computes the visual state for each phase boundary (see `phaseAt(_:)` below).

### `PillViewModel` (in `PillView.swift`)

Existing model already exposes `@Published var phase: PillPhase`. No structural changes — just extend it with a helper for driving the spawn timeline:

```swift
@MainActor
final class PillViewModel: ObservableObject {
    @Published var phase: PillPhase = .idle
    @Published var level: Float = 0

    /// Drives the spawn animation from 0 → 1 over `duration` seconds, then
    /// transitions to `.armed`. Cancellable so a hide() during spawn can
    /// abort the timeline cleanly.
    private var spawnTask: Task<Void, Never>?

    func playSpawn(duration: TimeInterval = 3.6) {
        spawnTask?.cancel()
        spawnTask = Task { @MainActor in
            let start = Date()
            phase = .spawning(progress: 0)
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let t = min(1.0, elapsed / duration)
                phase = .spawning(progress: t)
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)  // ~60fps
            }
            if !Task.isCancelled { phase = .armed }
        }
    }

    func cancelSpawn() { spawnTask?.cancel(); spawnTask = nil }
}
```

(Implementation detail: a `TimelineView(.animation)` driving SwiftUI animation is more elegant than a polling Task, but Task-with-progress is easier to cancel cleanly when the user lets go of the hotkey mid-spawn. We'll prototype both and pick the smoother one in the implementation phase.)

### `PillWindowController` (existing file)

Add a "needs to play spawn next time" flag, set on launch and on model switch:

```swift
@MainActor
final class PillWindowController {
    /// True when the next show() should play the cinematic spawn instead of
    /// the instant fade-in. Set on app launch and whenever the active model
    /// changes (because a model switch kicks off a fresh pre-warm — same
    /// "first press" feel as a cold launch).
    private var spawnPending = true

    init() {
        // Replay the spawn after a model switch. The PreferencesStore
        // publishes `activeModelID` changes; AppCoordinator already
        // observes this to swap WhisperKit backends. We piggyback to
        // reset spawnPending so the next pill appearance is cinematic.
        NotificationCenter.default.addObserver(forName: .activeModelDidChange,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.spawnPending = true
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(targetOrigin(for: panel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        if spawnPending {
            // Play the cinematic spawn. Pill becomes visible immediately
            // (alpha → 1) and the SwiftUI body handles all the internal
            // motion via PillPhase.spawning(progress:).
            spawnPending = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
            viewModel.playSpawn()
        } else {
            // Existing behavior — instant fade-in into .armed
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
            viewModel.phase = .armed
        }
    }

    func hide() {
        viewModel.cancelSpawn()  // NEW — abort if user releases hotkey mid-spawn
        // …existing fade-out
    }
}
```

(`Notification.Name.activeModelDidChange` is a small new notification posted by `PreferencesStore` when `activeModelID` changes. Trivial addition — alternative is wiring through Combine, but a one-line notification is lighter for this single observer.)

### `AppCoordinator` (existing file)

The state machine gains a new transient state:

```
idle → [hotkey down] → (first-of-session?) → spawning → armed → listening → processing → idle
                                            ↓ (subsequent presses)
                                            → armed → listening → ...
```

While `phase == .spawning`, the coordinator:

- **Captures audio** into the ring buffer as normal. AVAudioEngine is already running (it was pre-warmed at launch), so capture starts the moment the hotkey is pressed, with no delay.
- **Does NOT feed audio to Whisper yet.** The buffer fills silently in the background.
- When `phase` transitions out of `.spawning` (animation complete), the coordinator checks: is Whisper warm? If yes, drain the buffered audio into Whisper's stream and proceed to `.listening`. If no (rare — pre-warm taking longer than 3.6s), stay in `.armed` and start Whisper feed once the engine signals ready.

### `PillView.swift` rendering

`body` switches on `viewModel.phase`. For the new `.spawning(progress: t)` case, compute the staged visual state from `t`:

```swift
private func spawnState(at t: Double) -> SpawnState {
    // Phase boundaries in normalized timeline (0.0 → 1.0):
    let pSpawnEnd: Double      = 0.167   // 0.6s
    let pAnticipationEnd: Double = 0.236 // 0.85s
    let pPushEnd: Double       = 0.472   // 1.7s
    let pHoldEnd: Double       = 0.556   // 2.0s
    let pTraverseEnd: Double   = 0.833   // 3.0s
    // (Ignite runs 0.847 → 1.0; comet rim opacity + brightness)

    return SpawnState(
        figureOpacity: easeInOut(t / pSpawnEnd, clamped: true),
        figureScale: lerp(0.5, 1.0, t / pSpawnEnd, clamped: true),
        // …additional fields for triangleX, dotX, pillWidth, barOpacities[5], rimOpacity
    )
}
```

The full mapping is mechanical from the mockup keyframes — porting CSS keyframes to a SwiftUI lerp table.

### Audio + state-machine sequencing (sequence diagram)

```
User                Hotkey         Coordinator        AudioEngine       Whisper          PillVM
 |                    |                |                  |                |                |
 |─[press hotkey]────>|                |                  |                |                |
 |                    |─[onPress]─────>|                  |                |                |
 |                    |                |─[startCapture]──>| (ring buffer)  |                |
 |                    |                |─[show()]─────────────────────────────────────────> |
 |                    |                |                  |                |    (playSpawn) |
 |                    |                |                  |                |  phase=.spawning|
 |                    |                |                  |                |                |
 |─[start speaking]──>|                |                  | <buffer fills> |                |
 |                    |                |                  |                |                |
 |                                                                  3.6s elapses
 |                                                                  spawn animation done
 |                                                                  phase=.armed
 |                    |                |<─[spawn complete]───────────────────────────────── |
 |                    |                |─[isWhisperReady?]─────────────────>| (yes — pre-warm done) |
 |                    |                |─[drainBuffer→stream]──────────────>|                |
 |                    |                |                                    | partials        |
 |                    |                |<───────────────────[partialUpdate]─|                |
 |                    |                |─[phase=.listening]──────────────────────────────────>|
```

## Failure modes

| What happens                                              | Behavior                                                                                                                                                                                              |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| User releases hotkey during the spawn animation           | `PillWindowController.hide()` calls `viewModel.cancelSpawn()` and runs the existing fade-out. Pill disappears mid-animation. Audio captured during the brief spawn is discarded (we never started transcribing it). |
| User presses hotkey AGAIN during the spawn animation       | Ignored. Spawn is already playing, the pill is already up. (Coordinator already debounces double-presses.)                                                                                                      |
| Whisper pre-warm completes WELL BEFORE the spawn finishes | Animation plays out anyway. The waveform fades in on schedule (right-to-left cascade). When animation ends, buffered audio drains immediately into Whisper. Net cost: the user sees the animation feel "deliberate" rather than "rushed" — preferable to snapping out mid-spawn. |
| Whisper pre-warm STILL not done when spawn finishes       | Phase transitions to `.armed`, but audio remains buffered. As soon as Whisper signals ready, drain. The pill shows the normal armed/listening visual immediately.                                       |
| Whisper pre-warm FAILS                                    | Out of scope for this spec — handled by the separate failure-handling design.                                                                                                                          |

## Test plan

Manual smoke tests (the animation is hard to unit-test, so we lean on visual verification):

1. **Cold launch + immediate press** — quit, relaunch, press hotkey within 200ms of launch. Pill should spawn with full animation, no missed audio. Speak during the animation, release after 4s. Words should paste correctly.
2. **Cold launch + delayed press** — quit, relaunch, wait 5s, press hotkey. Pill should still spawn with full animation (first-of-session). Pre-warm has long completed, so audio drains immediately into Whisper at animation end.
3. **Second press in same session** — after #1 or #2, press hotkey again. Pill should appear instantly (existing behavior, no spawn animation).
4. **Release mid-spawn** — press hotkey, release within 1s. Pill should fade out cleanly, no orphaned animation, no crash.
5. **Spawn during pre-warm failure path** — manually corrupt the active model file, relaunch. Spawn should still play. (Failure UX itself is out of scope, but the animation shouldn't crash if Whisper never becomes ready.)
6. **5-minute idle + first press** — launch, leave the app idle for 5 minutes (Whisper is warm but unused). Press hotkey. Spawn animation should NOT replay (it's first-of-session, already happened at launch verification). Wait — actually this test confirms that "first press" = first press EVER per session, not first press after idle. See "Open questions" below.
7. **Animation framerate** — visually confirm the spawn runs at 60fps on M1 base. Watch the comet rim's brightness flash and the bar cascade — those are the most likely to drop frames.

Performance budget:
- Animation should hold 60fps on every supported hardware (M1 base is the floor).
- Total CPU time during spawn: ≤ 5% of one core (the spawn runs while Whisper pre-warm is using GPU/Neural Engine, so we have CPU headroom).

## Resolved decisions (formerly open questions)

1. **Replay after model switch?** **Yes.** Switching the active Whisper model in Settings posts an `activeModelDidChange` notification, `PillWindowController.spawnPending` flips back to `true`, and the next hotkey press plays the full cinematic spawn. Same "first press of a new chapter" feel.
2. **Always play even when Whisper is already warm?** **Yes.** Consistency wins. The animation is short enough (3.6s) that even a fully-warm engine isn't bottlenecked by it — the buffered audio just drains immediately at the end. The animation is the "launch ritual," not a stall.
3. **Audio queueing window.** Confirmed in scope. The existing ring buffer holds ~30s; spawn is 3.6s. No risk of overflow during normal use.

---

## Approval

User signs off here before we move to writing-plans:

- [x] Choreography matches the v5 mockup
- [x] Trigger logic: first press per session + after every model switch
- [x] Always play, even when warm
- [x] Audio queueing during spawn, drain when ready
