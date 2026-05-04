# Pre-Warm Pill Spawn Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the cinematic 3.6s spawn animation that plays on the first hotkey press after each app launch (and after every model switch), per [the design spec](../specs/2026-05-04-prewarm-pill-spawn-animation-design.md).

**Architecture:**
- Pure-data **`SpawnTimeline`** struct maps a normalized `0…1` progress value to a fully-resolved `SpawnState` (figure positions, opacities, scales, pill width, bar opacities, rim opacity). Renders are stateless functions of progress; the math is unit-testable in isolation.
- **`PillViewModel.playSpawn(duration:)`** drives the timeline at ~60fps via a cancellable `Task`, publishing `.spawning(progress: t)` cases to the existing `@Published phase`. **`cancelSpawn()`** aborts cleanly when the user releases the hotkey mid-spawn.
- **`PillWindowController`** flips a `spawnPending` flag on init and on `Notification.Name.activeModelDidChange`. `show()` plays the spawn when pending, falls through to instant-armed otherwise. **`PreferencesStore`** posts the notification when `activeModelID` changes.
- **`AppCoordinator`** gains an `AppState.spawning` case. Hotkey-press now succeeds during `.idle` AND during `.loadingModel` (currently only `.idle`). Audio capture starts immediately on press; samples accumulate in a local `spawnBuffer` while spawning; when both spawn-complete AND whisper-warm conditions are met, the buffer drains into `whisper.append(...)` and state advances to `.streaming`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine. macOS 14+. Existing test runner: XCTest under `CyphrWhisprTests/`.

---

## File Structure

**New files:**

| Path                                                | Responsibility                                                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `CyphrWhispr/PillWindow/SpawnTimeline.swift`        | Pure data type. `SpawnTimeline.state(at: Double) -> SpawnState`. No SwiftUI imports. Used by `PillView`, tested directly. |
| `CyphrWhisprTests/SpawnTimelineTests.swift`         | XCTest cases that pin the timeline math at every phase boundary.                                                     |

**Modified files:**

| Path                                                  | What changes                                                                                                                                                                |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CyphrWhispr/PillWindow/PillView.swift`               | Add `.spawning(progress: Double)` to `PillPhase`. Add `playSpawn(duration:)`/`cancelSpawn()` to `PillViewModel`. Render the new phase in `body` using `SpawnTimeline`.       |
| `CyphrWhispr/PillWindow/PillWindowController.swift`   | Add `spawnPending: Bool = true`. Observe `Notification.Name.activeModelDidChange` in `init()`. Route `show()` through `playSpawn` when pending, instant `.armed` otherwise.  |
| `CyphrWhispr/Settings/PreferencesStore.swift`         | Define `Notification.Name.activeModelDidChange`. Post it from the `activeModelID` `didSet` after the dedup check.                                                            |
| `CyphrWhispr/App/AppCoordinator.swift`                | Add `.spawning` to `AppState`. Loosen the `handleHotkeyPress` guard. Add `spawnBuffer: [Float]`, `spawnAnimationDone`, `whisperWarmDone`, and `whisperWarmAwaiter`. Drain when both readiness flags are true. Wire `pill.onSpawnComplete` callback in `start()`. |
| `CyphrWhisprTests/CyphrWhisprTests.swift`             | (Existing — no changes; new tests live in `SpawnTimelineTests.swift`.)                                                                                                      |

---

## Production-scale geometry constants

The v5 mockup runs at 2× scale (340 × 96). Production pill is 170 × 48. **All values below are at production scale.** The `SpawnTimeline` will use these directly; the mockup file is purely a design reference.

| Constant                             | Value         |
| ------------------------------------ | ------------- |
| `pillWidth.seed`                     | `45`          |
| `pillWidth.anticipation`             | `42`          |
| `pillWidth.full`                     | `170`         |
| `triangleX.spawn`                    | `3.5`         |
| `triangleX.anticipation`             | `5`           |
| `triangleX.pushEnd`                  | `12`          |
| `dotX.spawn`                         | `25`          |
| `dotX.anticipation`                  | `23.5`        |
| `dotX.pushHold` *(far right)*        | `135`         |
| `dotX.traverseEnd` *(next to triangle)* | `46`        |
| `figureScale.spawnStart`             | `0.5`         |
| `figureScale.full`                   | `1.0`         |
| `figureScale.anticipationDip`        | `0.97`        |

Phase boundaries on the normalized `0…1` timeline (with corresponding wall-clock time at the default 3.6s duration):

| Phase            | Time          | t (normalized)           |
| ---------------- | ------------- | ------------------------ |
| Spawn            | 0 → 0.6s      | `0.000 → 0.167`          |
| Anticipation     | 0.6 → 0.85s   | `0.167 → 0.236`          |
| Push             | 0.85 → 1.7s   | `0.236 → 0.472`          |
| Hold             | 1.7 → 2.0s    | `0.472 → 0.556`          |
| Traverse         | 2.0 → 3.0s    | `0.556 → 0.833`          |
| Ignite           | 3.05 → 3.6s   | `0.847 → 1.000`          |

---

## Task 1: SpawnTimeline data + tests

**Files:**
- Create: `CyphrWhispr/PillWindow/SpawnTimeline.swift`
- Create: `CyphrWhisprTests/SpawnTimelineTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `CyphrWhisprTests/SpawnTimelineTests.swift`:

```swift
import XCTest
@testable import CyphrWhispr

final class SpawnTimelineTests: XCTestCase {

    // MARK: - Spawn phase (0 → 0.167)

    func test_atTimeZero_figuresAreInvisibleAtSeedScale() {
        let s = SpawnTimeline.state(at: 0)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.figureScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.001)
        XCTAssertEqual(s.triangleX, 3.5, accuracy: 0.001)
        XCTAssertEqual(s.dotX, 25, accuracy: 0.001)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.001)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 })
    }

    func test_atSpawnEnd_figuresAreFullySizedAtSeedPosition() {
        let s = SpawnTimeline.state(at: 0.167)
        XCTAssertEqual(s.figureOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.5)  // still seed
        XCTAssertEqual(s.triangleX, 3.5, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 25, accuracy: 0.5)
    }

    // MARK: - Anticipation (0.167 → 0.236)

    func test_atAnticipationEnd_pillCompresses_figuresLeanInward() {
        let s = SpawnTimeline.state(at: 0.236)
        XCTAssertEqual(s.figureScale, 0.97, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 42, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, 5, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 23.5, accuracy: 0.5)
    }

    // MARK: - Push (0.236 → 0.472)

    func test_atPushEnd_pillIsFullWidth_figuresAtExtremes() {
        let s = SpawnTimeline.state(at: 0.472)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 170, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, 12, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 }, "no bars during push")
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.01)
    }

    // MARK: - Hold (0.472 → 0.556)

    func test_duringHold_circleStaysAtFarRight_noBarsYet() {
        let s = SpawnTimeline.state(at: 0.51)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 })
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.01)
    }

    // MARK: - Traverse (0.556 → 0.833)

    func test_atTraverseStart_circleBeginsLeftward_noBarsRevealedYet() {
        let s = SpawnTimeline.state(at: 0.556)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertEqual(s.barOpacities[4], 0, accuracy: 0.01)
    }

    func test_atTraverseEnd_circleAtFinalPosition_allBarsVisible() {
        let s = SpawnTimeline.state(at: 0.833)
        XCTAssertEqual(s.dotX, 46, accuracy: 0.5)
        // Bars cascade right-to-left during traverse — bar 5 (rightmost) reveals
        // first, bar 1 (leftmost) reveals last. By traverse end all should be
        // fully visible.
        for (i, opacity) in s.barOpacities.enumerated() {
            XCTAssertEqual(opacity, 1, accuracy: 0.05, "bar \(i) should be visible at traverse end")
        }
    }

    func test_barsRevealRightToLeft_duringTraverse() {
        // Mid-traverse: rightmost bars should be more visible than leftmost.
        let s = SpawnTimeline.state(at: 0.7)
        XCTAssertGreaterThan(s.barOpacities[4], s.barOpacities[0],
                             "rightmost bar should reveal earlier than leftmost during the right-to-left cascade")
    }

    // MARK: - Ignite (0.847 → 1.0)

    func test_atIgniteStart_rimBeginsToFadeIn() {
        let s = SpawnTimeline.state(at: 0.847)
        XCTAssertGreaterThan(s.rimOpacity, 0)
        XCTAssertLessThan(s.rimOpacity, 0.5)
    }

    func test_atTimeOne_rimFullyVisible_allBarsVisible() {
        let s = SpawnTimeline.state(at: 1.0)
        XCTAssertEqual(s.rimOpacity, 1, accuracy: 0.01)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 >= 0.99 })
    }

    // MARK: - Boundary safety

    func test_progressAboveOne_clampsToFinalState() {
        let s = SpawnTimeline.state(at: 1.5)
        XCTAssertEqual(s.rimOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.dotX, 46, accuracy: 0.5)
    }

    func test_negativeProgress_clampsToInitialState() {
        let s = SpawnTimeline.state(at: -0.2)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the test file to verify it fails to compile**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAIL" | head
```
Expected: errors about missing `SpawnTimeline` and `SpawnState` symbols.

- [ ] **Step 3: Implement SpawnTimeline + SpawnState**

Create `CyphrWhispr/PillWindow/SpawnTimeline.swift`:

```swift
import Foundation
import CoreGraphics

/// Fully-resolved visual state for the pill at a single point in the spawn
/// animation timeline. Pure data — no SwiftUI types — so it stays unit-testable.
///
/// All position/size values are in **production-scale points** (170 × 48 pill).
/// SwiftUI denormalises into rendering primitives by reading these fields
/// directly into the `body` builder.
struct SpawnState: Equatable {
    /// Opacity of triangle + circle (both rise together during spawn phase).
    var figureOpacity: Double
    /// Scale applied to triangle + circle. Goes 0.5 → 1 during spawn,
    /// dips to 0.97 during anticipation, returns to 1 during push.
    var figureScale: Double
    /// Capsule width in points. Production: 45 (seed) → 42 (anticipation) → 170 (full).
    var pillWidth: CGFloat
    /// Triangle's left position relative to the pill's left edge.
    var triangleX: CGFloat
    /// Circle's left position relative to the pill's left edge.
    var dotX: CGFloat
    /// Five waveform-bar opacities in left-to-right order. Reveal cascades
    /// right-to-left during the traverse phase (rightmost first).
    var barOpacities: [Double]
    /// Comet-rim opacity. Stays 0 until the ignite phase begins (~0.847).
    var rimOpacity: Double
}

/// Pure timeline math for the spawn animation. Maps a normalised `t ∈ [0, 1]`
/// to a fully-resolved `SpawnState`. The wall-clock duration is set by the
/// caller (`PillViewModel.playSpawn(duration:)`); this struct is duration-
/// agnostic.
///
/// Phase boundaries (normalized t, with wall-clock time at the default 3.6s):
/// - **Spawn**        0.000 → 0.167  (0 → 0.6s)   figures fade in + scale up
/// - **Anticipation** 0.167 → 0.236  (0.6 → 0.85s) inward lean
/// - **Push**         0.236 → 0.472  (0.85 → 1.7s) figures shove apart
/// - **Hold**         0.472 → 0.556  (1.7 → 2.0s) brand-mark money shot
/// - **Traverse**     0.556 → 0.833  (2.0 → 3.0s) circle returns left,
///                                                bars cascade in behind it
/// - **Ignite**       0.847 → 1.000  (3.05 → 3.6s) comet rim fades in
enum SpawnTimeline {

    // MARK: - Phase boundaries (normalized)

    private static let pSpawnEnd:        Double = 0.167
    private static let pAnticipationEnd: Double = 0.236
    private static let pPushEnd:         Double = 0.472
    private static let pHoldEnd:         Double = 0.556
    private static let pTraverseEnd:     Double = 0.833
    private static let pIgniteStart:     Double = 0.847

    // MARK: - Geometry constants (production scale)

    private static let pillSeedW:         CGFloat = 45
    private static let pillAnticipationW: CGFloat = 42
    private static let pillFullW:         CGFloat = 170

    private static let triSpawnX:         CGFloat = 3.5
    private static let triAnticipationX:  CGFloat = 5
    private static let triPushEndX:       CGFloat = 12

    private static let dotSpawnX:         CGFloat = 25
    private static let dotAnticipationX:  CGFloat = 23.5
    private static let dotPushHoldX:      CGFloat = 135
    private static let dotTraverseEndX:   CGFloat = 46

    /// Each bar's reveal window. The traverse phase spans 0.556 → 0.833
    /// (Δ ≈ 0.277). Bars cascade right-to-left with ~0.05 stagger each;
    /// each bar's individual fade takes ~0.05 of normalised time.
    private static let barRevealStarts: [Double] = [
        0.760,  // bar 1 (leftmost) — last to reveal
        0.710,  // bar 2
        0.660,  // bar 3 (centre)
        0.610,  // bar 4
        0.560,  // bar 5 (rightmost) — first to reveal
    ]
    private static let barRevealDuration: Double = 0.045

    // MARK: - Public API

    /// Resolve the visual state at the given normalized progress.
    /// `t` is clamped to `[0, 1]` so out-of-range callers degrade gracefully.
    static func state(at t: Double) -> SpawnState {
        let t = clamp(t, 0, 1)

        return SpawnState(
            figureOpacity: figureOpacity(at: t),
            figureScale:   figureScale(at: t),
            pillWidth:     pillWidth(at: t),
            triangleX:     triangleX(at: t),
            dotX:          dotX(at: t),
            barOpacities:  barOpacities(at: t),
            rimOpacity:    rimOpacity(at: t)
        )
    }

    // MARK: - Per-field math

    private static func figureOpacity(at t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= pSpawnEnd { return 1 }
        return easeOut(t / pSpawnEnd)
    }

    private static func figureScale(at t: Double) -> Double {
        if t <= 0 { return 0.5 }
        if t < pSpawnEnd { return lerp(0.5, 1.0, easeOut(t / pSpawnEnd)) }
        if t < pAnticipationEnd {
            let local = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            return lerp(1.0, 0.97, easeInOut(local))
        }
        if t < pPushEnd {
            // Settle back to 1.0 over the first ~10% of the push, then hold.
            let pushSettle = (pPushEnd - pAnticipationEnd) * 0.10
            let local = min(1, (t - pAnticipationEnd) / pushSettle)
            return lerp(0.97, 1.0, easeOut(local))
        }
        return 1.0
    }

    private static func pillWidth(at t: Double) -> CGFloat {
        if t < pSpawnEnd { return pillSeedW }
        if t < pAnticipationEnd {
            let local = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            return CGFloat(lerp(Double(pillSeedW), Double(pillAnticipationW), easeInOut(local)))
        }
        if t < pPushEnd {
            let local = (t - pAnticipationEnd) / (pPushEnd - pAnticipationEnd)
            return CGFloat(lerp(Double(pillAnticipationW), Double(pillFullW), easeOutQuint(local)))
        }
        return pillFullW
    }

    private static func triangleX(at t: Double) -> CGFloat {
        if t < pSpawnEnd { return triSpawnX }
        if t < pAnticipationEnd {
            let local = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            return CGFloat(lerp(Double(triSpawnX), Double(triAnticipationX), easeInOut(local)))
        }
        if t < pPushEnd {
            let local = (t - pAnticipationEnd) / (pPushEnd - pAnticipationEnd)
            return CGFloat(lerp(Double(triAnticipationX), Double(triPushEndX), easeOutQuint(local)))
        }
        return triPushEndX
    }

    private static func dotX(at t: Double) -> CGFloat {
        if t < pSpawnEnd { return dotSpawnX }
        if t < pAnticipationEnd {
            let local = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            return CGFloat(lerp(Double(dotSpawnX), Double(dotAnticipationX), easeInOut(local)))
        }
        if t < pPushEnd {
            let local = (t - pAnticipationEnd) / (pPushEnd - pAnticipationEnd)
            return CGFloat(lerp(Double(dotAnticipationX), Double(dotPushHoldX), easeOutQuint(local)))
        }
        if t < pHoldEnd {
            return dotPushHoldX
        }
        if t < pTraverseEnd {
            let local = (t - pHoldEnd) / (pTraverseEnd - pHoldEnd)
            return CGFloat(lerp(Double(dotPushHoldX), Double(dotTraverseEndX), easeOutQuint(local)))
        }
        return dotTraverseEndX
    }

    private static func barOpacities(at t: Double) -> [Double] {
        barRevealStarts.map { start in
            if t < start { return 0 }
            if t > start + barRevealDuration { return 1 }
            return easeOut((t - start) / barRevealDuration)
        }
    }

    private static func rimOpacity(at t: Double) -> Double {
        if t < pIgniteStart { return 0 }
        let local = (t - pIgniteStart) / (1 - pIgniteStart)
        return easeOut(min(1, local))
    }

    // MARK: - Easings + utilities

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - clamp(t, 0, 1), 2)
    }

    private static func easeOutQuint(_ t: Double) -> Double {
        1 - pow(1 - clamp(t, 0, 1), 5)
    }

    private static func easeInOut(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project so the new files are picked up**

Run:
```bash
xcodegen generate
```
Expected: project regenerates with `SpawnTimeline.swift` and `SpawnTimelineTests.swift` included.

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: `Test Suite 'SpawnTimelineTests' passed.` All 11 tests green.

- [ ] **Step 6: Commit**

```bash
git add CyphrWhispr/PillWindow/SpawnTimeline.swift CyphrWhisprTests/SpawnTimelineTests.swift
git commit -m "$(cat <<'EOF'
Add SpawnTimeline pure-math timeline driver

Maps normalised 0..1 progress to a SpawnState that fully resolves
the spawn animation's per-field values: figure opacity/scale, pill
width, triangle/circle positions, bar opacities (right-to-left
cascade), rim opacity. No SwiftUI types — pure data, easily testable.

Eleven test cases pin every phase boundary plus boundary clamping.
EOF
)"
```

---

## Task 2: PreferencesStore posts `activeModelDidChange` notification

**Files:**
- Modify: `CyphrWhispr/Settings/PreferencesStore.swift`

- [ ] **Step 1: Add a failing test for the notification**

Append to `CyphrWhisprTests/CyphrWhisprTests.swift`:

```swift
    @MainActor
    func testActiveModelChange_postsNotification() async {
        let store = PreferencesStore.shared
        let initial = store.activeModelID
        let other = (initial == "openai_whisper-small.en")
            ? "openai_whisper-tiny.en"
            : "openai_whisper-small.en"

        let exp = expectation(forNotification: .activeModelDidChange,
                              object: store,
                              handler: nil)

        store.activeModelID = other
        await fulfillment(of: [exp], timeout: 1.0)

        // Restore so we don't pollute test ordering.
        store.activeModelID = initial
    }
```

- [ ] **Step 2: Run the test to confirm it fails (no notification name yet)**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head
```
Expected: error about `activeModelDidChange` member missing on `Notification.Name`.

- [ ] **Step 3: Add the notification name + post it**

In `CyphrWhispr/Settings/PreferencesStore.swift`, **add at the very bottom of the file** (after the `extension PreferencesStore` block):

```swift
extension Notification.Name {
    /// Posted by `PreferencesStore` whenever the user picks a different
    /// Whisper model. Listeners (e.g. `PillWindowController`) use this to
    /// reset session-scoped state that should re-trigger after a model
    /// switch — like replaying the cinematic spawn animation on the next
    /// hotkey press.
    static let activeModelDidChange = Notification.Name("CyphrWhispr.activeModelDidChange")
}
```

In the same file, find this `didSet` block (currently lines ~33-37):

```swift
    @Published var activeModelID: String {
        didSet {
            guard activeModelID != oldValue else { return }
            UserDefaults.standard.set(activeModelID, forKey: Key.activeModelID)
        }
    }
```

Replace with:

```swift
    @Published var activeModelID: String {
        didSet {
            guard activeModelID != oldValue else { return }
            UserDefaults.standard.set(activeModelID, forKey: Key.activeModelID)
            // Broadcast so cross-cutting listeners (PillWindowController
            // for the spawn animation reset) can react without a tight
            // Combine binding back into the prefs store.
            NotificationCenter.default.post(name: .activeModelDidChange, object: self)
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "Test Case|FAIL|passed"
```
Expected: `testActiveModelChange_postsNotification` passes.

- [ ] **Step 5: Commit**

```bash
git add CyphrWhispr/Settings/PreferencesStore.swift CyphrWhisprTests/CyphrWhisprTests.swift
git commit -m "$(cat <<'EOF'
Post activeModelDidChange notification on model switch

PreferencesStore posts Notification.Name.activeModelDidChange whenever
activeModelID changes (after the dedup check). PillWindowController
will observe this in a follow-up commit to re-arm the spawn animation
on the next hotkey press following a model switch.
EOF
)"
```

---

## Task 3: Add `.spawning(progress:)` case to `PillPhase`

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift:5-10`

- [ ] **Step 1: Add the new case**

In `CyphrWhispr/PillWindow/PillView.swift`, replace the `PillPhase` enum (currently at lines 5-10):

```swift
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    case armed
    case listening
    case processing
}
```

with:

```swift
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    /// First-of-session (or post-model-switch) cinematic appearance.
    /// `progress` is the normalised 0…1 timeline driven by `PillViewModel.playSpawn(duration:)`.
    /// `PillView.body` reads `SpawnTimeline.state(at: progress)` to render the staged motion.
    case spawning(progress: Double)
    case armed
    case listening
    case processing
}
```

- [ ] **Step 2: Verify the project still compiles (the `body` switch is non-exhaustive, but Swift's `switch` over enums needs handling — defer that to Task 5)**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' build 2>&1 | tail -10
```
Expected: compiles cleanly. (No code currently switches exhaustively on `PillPhase`; Equatable/Hashable conformance is auto-synthesised.)

- [ ] **Step 3: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift
git commit -m "$(cat <<'EOF'
Add .spawning(progress:) case to PillPhase

Tracks the cinematic spawn animation's normalised 0..1 timeline.
PillView and PillViewModel pick up the new case in subsequent commits.
EOF
)"
```

---

## Task 4: Add `playSpawn` and `cancelSpawn` to `PillViewModel`

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift:12-18` (the `PillViewModel` class)
- Test: `CyphrWhisprTests/CyphrWhisprTests.swift`

- [ ] **Step 1: Add a failing test for `playSpawn` ramp + completion**

Append to `CyphrWhisprTests/CyphrWhisprTests.swift`:

```swift
    @MainActor
    func testPlaySpawn_progressesFromZeroToArmed() async {
        let vm = PillViewModel()
        XCTAssertEqual(vm.phase, .idle)

        // Use a short duration so the test runs quickly. The implementation
        // is duration-agnostic — same logic, faster wall-clock.
        await vm.playSpawn(duration: 0.20)

        XCTAssertEqual(vm.phase, .armed,
                       "spawn should complete by setting phase to .armed")
    }

    @MainActor
    func testCancelSpawn_stopsTimeline_keepsLastPhase() async {
        let vm = PillViewModel()
        let task = Task { await vm.playSpawn(duration: 1.0) }

        // Let the spawn run for a slice, then cancel.
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        vm.cancelSpawn()
        await task.value

        // Phase should still be .spawning(...) — cancel does NOT advance to .armed.
        if case .spawning = vm.phase {
            // pass
        } else {
            XCTFail("after cancellation, phase should still be .spawning, got \(vm.phase)")
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAIL" | head
```
Expected: errors about missing `playSpawn` and `cancelSpawn` methods.

- [ ] **Step 3: Implement `playSpawn` and `cancelSpawn`**

In `CyphrWhispr/PillWindow/PillView.swift`, replace the `PillViewModel` class (currently at lines 12-18):

```swift
@MainActor
final class PillViewModel: ObservableObject {
    @Published var phase: PillPhase = .idle
    @Published var level: Float = 0

    var isRecording: Bool { phase == .armed || phase == .listening }
}
```

with:

```swift
@MainActor
final class PillViewModel: ObservableObject {
    @Published var phase: PillPhase = .idle
    @Published var level: Float = 0

    var isRecording: Bool { phase == .armed || phase == .listening }

    /// Drives the spawn animation from `progress = 0` to `progress = 1` over
    /// `duration` seconds, then sets `phase = .armed`. Polls at ~60Hz, which
    /// is plenty for SwiftUI's diff-based body re-evaluation.
    ///
    /// Calling this while another spawn is in flight cancels the previous
    /// one (last-write-wins). Returns `true` if the animation ran to
    /// completion, `false` if it was cancelled. The boolean lets the
    /// caller distinguish "phase == .armed because spawn finished" from
    /// "phase happened to be .armed because something else moved it" — the
    /// race exists because audio-level updates can promote `.armed` to
    /// `.listening` the instant the spawn ends.
    @discardableResult
    func playSpawn(duration: TimeInterval = 3.6) async -> Bool {
        spawnTask?.cancel()
        let task = Task<Bool, Never> { @MainActor in
            let start = Date()
            phase = .spawning(progress: 0)
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let t = min(1.0, elapsed / duration)
                phase = .spawning(progress: t)
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)  // ~60fps
            }
            if Task.isCancelled { return false }
            phase = .armed
            return true
        }
        spawnTask = task
        return await task.value
    }

    /// Aborts an in-flight spawn animation. Phase stays at whatever
    /// `.spawning(progress:)` value the timeline last published — the
    /// caller is responsible for the next phase transition (typically
    /// `.idle` via `PillWindowController.hide()`).
    func cancelSpawn() {
        spawnTask?.cancel()
        spawnTask = nil
    }

    private var spawnTask: Task<Void, Never>?
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "Test Case 'CyphrWhisprTests.test(Play|Cancel)Spawn|passed|FAIL" | head
```
Expected: both `testPlaySpawn_progressesFromZeroToArmed` and `testCancelSpawn_stopsTimeline_keepsLastPhase` pass.

- [ ] **Step 5: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift CyphrWhisprTests/CyphrWhisprTests.swift
git commit -m "$(cat <<'EOF'
Add playSpawn / cancelSpawn to PillViewModel

playSpawn(duration:) drives the spawn timeline at ~60fps, publishing
.spawning(progress:) phases until completion, then transitioning to
.armed. cancelSpawn aborts cleanly without advancing the phase, so the
caller (PillWindowController.hide on hotkey-release-mid-spawn) is
free to drive its own fade-out.
EOF
)"
```

---

## Task 5: Render `.spawning` phase in `PillView`

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift` (the `body` and `RimHighlights` sections)

- [ ] **Step 1: Replace the `body` so it switches on the phase**

In `CyphrWhispr/PillWindow/PillView.swift`, find the existing `body` definition (currently at lines 43-94 — the `var body: some View { let shape = ...` block).

Replace the entire body with:

```swift
    var body: some View {
        Group {
            if case .spawning(let progress) = viewModel.phase {
                spawnBody(progress: progress)
            } else {
                normalBody
            }
        }
        .padding(EdgeInsets(top: 36, leading: 36, bottom: 48, trailing: 36))
    }

    /// The existing pill content — used in every phase except `.spawning`.
    /// Logic identical to the pre-spawn version of `body`; just lifted into
    /// its own computed property so we can swap whole layouts cleanly.
    @ViewBuilder
    private var normalBody: some View {
        let shape = Capsule(style: .continuous)
        HStack(alignment: .center, spacing: 7) {
            Color.clear.frame(width: 8, height: 1)

            DownTriangle()
                .fill(Color.white)
                .overlay(
                    DownTriangle()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 18, height: 16)

            Circle()
                .fill(Color.white)
                .frame(width: 17, height: 17)
                .scaleEffect(viewModel.phase == .listening
                             ? 1.0 + CGFloat(min(viewModel.level, 1)) * 0.10
                             : 1.0)
                .animation(.easeOut(duration: 0.12), value: viewModel.level)

            WaveformView(level: viewModel.level, phase: viewModel.phase)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .padding(.horizontal, 14)
        .frame(width: Self.pillWidth, height: Self.pillHeight)
        .background(shape.fill(Color.black))
        .overlay(RimHighlights(phase: viewModel.phase,
                               level: viewModel.level,
                               accent: prefs.accent,
                               accentSecondary: prefs.accentSecondary))
        .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)
    }

    /// Renders the pill mid-spawn: figures positioned by absolute offsets
    /// inside a width-animated capsule, bars individually positioned (so
    /// their reveal cascade is independent of the HStack flow), and the
    /// comet rim faded in via the rimOpacity multiplier.
    @ViewBuilder
    private func spawnBody(progress: Double) -> some View {
        let s = SpawnTimeline.state(at: progress)
        let shape = Capsule(style: .continuous)

        ZStack(alignment: .leading) {
            // Capsule body — pure black, animated width.
            shape
                .fill(Color.black)
                .frame(width: s.pillWidth, height: Self.pillHeight)

            // Triangle — absolute positioning by SpawnTimeline.triangleX
            DownTriangle()
                .fill(Color.white)
                .frame(width: 18, height: 16)
                .opacity(s.figureOpacity)
                .scaleEffect(s.figureScale)
                .offset(x: s.triangleX,
                        y: (Self.pillHeight - 16) / 2)

            // Circle — absolute positioning by SpawnTimeline.dotX
            Circle()
                .fill(Color.white)
                .frame(width: 17, height: 17)
                .opacity(s.figureOpacity)
                .scaleEffect(s.figureScale)
                .offset(x: s.dotX,
                        y: (Self.pillHeight - 17) / 2)

            // Bars — five individual rectangles at fixed columns to the
            // right of the circle's final position. Bar columns are derived
            // by spreading evenly across the waveform area
            // (left = 70 → right = 156, production scale).
            ForEach(0..<5, id: \.self) { i in
                let column: CGFloat = 70 + CGFloat(i) * (86 / 4)  // 70, 91.5, 113, 134.5, 156
                let barHeight: CGFloat = (i == 2) ? 14 : 6  // centre bar taller
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: barHeight)
                    .opacity(s.barOpacities[i])
                    .offset(x: column,
                            y: (Self.pillHeight - barHeight) / 2)
            }
        }
        .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
        // Rim halo only after ignite — opacity ramps 0 → 1 in the ignite phase
        .overlay(
            RimHighlights(phase: .listening,  // pretend listening so the comet runs
                          level: 0.0,
                          accent: prefs.accent,
                          accentSecondary: prefs.accentSecondary)
                .opacity(s.rimOpacity)
        )
        .shadow(color: .black.opacity(0.50 * s.figureOpacity), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20 * s.figureOpacity), radius: 3, x: 0, y: 1)
    }
```

- [ ] **Step 2: Add a `#Preview` for the spawning state so the SwiftUI canvas can render it**

In `CyphrWhispr/PillWindow/PillView.swift`, append after the existing `#Preview`:

```swift
#Preview("Spawning - mid push") {
    let vm = PillViewModel()
    vm.phase = .spawning(progress: 0.40)
    return PillView(viewModel: vm)
        .frame(width: 260, height: 120)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
}

#Preview("Spawning - traverse") {
    let vm = PillViewModel()
    vm.phase = .spawning(progress: 0.70)
    return PillView(viewModel: vm)
        .frame(width: 260, height: 120)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
}
```

- [ ] **Step 3: Build and verify the previews render without errors**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' build 2>&1 | tail -15
```
Expected: clean build, no warnings about `PillPhase` exhaustiveness or shape mismatches.

Then open `CyphrWhispr/PillWindow/PillView.swift` in Xcode and verify the new previews render (should show pill mid-push and mid-traverse).

- [ ] **Step 4: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift
git commit -m "$(cat <<'EOF'
Render PillPhase.spawning via SpawnTimeline

Splits PillView.body so the spawning phase uses absolute positioning
(driven by SpawnTimeline.state) while every other phase keeps the
existing HStack flow. Adds two SwiftUI previews (mid-push, mid-traverse)
so the canvas can verify the shape without launching the app.
EOF
)"
```

---

## Task 6: PillWindowController gates `show()` on `spawnPending`

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillWindowController.swift:6-44`
- Test: `CyphrWhisprTests/CyphrWhisprTests.swift`

- [ ] **Step 1: Add a failing test for the spawnPending lifecycle**

Append to `CyphrWhisprTests/CyphrWhisprTests.swift`:

```swift
    @MainActor
    func testPillController_spawnsOnFirstShow_thenInstantOnSecond() async {
        let controller = PillWindowController()

        // First show — should set phase to .spawning(progress: 0).
        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)  // give playSpawn one tick

        if case .spawning = controller.viewModelForTesting.phase {
            // pass
        } else {
            XCTFail("first show() must trigger .spawning phase, got \(controller.viewModelForTesting.phase)")
        }

        // Cancel + hide
        controller.hide()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Second show — should be instant .armed.
        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.viewModelForTesting.phase, .armed,
                       "second show() in same session must skip the spawn")

        controller.hide()
    }

    @MainActor
    func testPillController_replaysSpawnAfterModelChange() async {
        let controller = PillWindowController()

        controller.show()  // burns the first spawn
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.hide()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Simulate the user changing the active model in Settings.
        NotificationCenter.default.post(name: .activeModelDidChange, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)  // let observer fire

        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .spawning = controller.viewModelForTesting.phase {
            // pass — spawnPending was reset by the notification
        } else {
            XCTFail("show() after activeModelDidChange must replay spawn, got \(controller.viewModelForTesting.phase)")
        }
        controller.hide()
    }
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAIL" | head
```
Expected: errors about missing `viewModelForTesting` accessor (and the spawn behaviour itself).

- [ ] **Step 3: Update PillWindowController**

In `CyphrWhispr/PillWindow/PillWindowController.swift`, replace the class declaration through the `show()` and `hide()` methods (currently lines 5-60):

```swift
@MainActor
final class PillWindowController {
    /// True when the next `show()` should play the cinematic spawn instead of
    /// the instant fade-in. Set to `true` on init (so the first press of every
    /// session is cinematic) and again whenever the user picks a different
    /// Whisper model in Settings (because that triggers a fresh pre-warm and
    /// the same "first press" feel applies). Set to `false` after each spawn.
    private var spawnPending = true

    /// Held strongly so the observer survives for the controller's lifetime.
    private var modelChangeObserver: NSObjectProtocol?

    /// Total panel size. Bigger than the visible pill (170×48) because PillView
    /// pads itself so the drop shadow + rim halo can fully fade to alpha 0
    /// before reaching the panel boundary. Bumped ~30% over the previous
    /// 226×112 after a faint silhouette of the panel was still showing at the
    /// shadow's fall-off.
    /// Padding: 36 left/right/top, 48 bottom (extra for the y-offset shadow).
    /// Panel = 170+72 × 48+84 = 242×132.
    private static let pillSize = NSSize(width: 242, height: 132)
    /// Distance of the *visible pill's* bottom edge from the bottom of the
    /// screen. The panel itself sits lower because PillView adds 36pt of
    /// bottom padding for shadow room; we subtract that when placing the
    /// panel so the visible pill lands here regardless of padding changes.
    private static let bottomMargin: CGFloat = 80
    /// Bottom inset inside PillView (panel origin → visible pill bottom).
    /// Must mirror the bottom padding in PillView.body.
    private static let pillBottomInset: CGFloat = 48
    /// Distance in points within which the pill softly snaps to a guide.
    /// Larger value = "stickier" snap. 28 makes the centre-line feel magnetic.
    private static let snapThreshold: CGFloat = 28
    /// Persists the user's last manual position per-display.
    private static let positionKey = "PillWindow.lastOriginByScreen"

    private var panel: PillPanel?
    private let viewModel = PillViewModel()

    init() {
        // Re-arm the spawn after every model switch. PreferencesStore posts
        // .activeModelDidChange in its activeModelID didSet (after dedup).
        modelChangeObserver = NotificationCenter.default.addObserver(
            forName: .activeModelDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.spawnPending = true
        }
    }

    deinit {
        if let observer = modelChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Fired when the cinematic spawn animation finishes (i.e. when the pill
    /// has transitioned from `.spawning(...)` to `.armed`). AppCoordinator
    /// registers a closure here to drain its audio buffer + start streaming.
    /// On a non-spawn `show()` (subsequent presses in the same session), this
    /// fires synchronously inside `show()` so the same code path always works.
    var onSpawnComplete: (() -> Void)?

    /// **For tests only.** Production code should never read the view model
    /// directly — go through `setPhase`, `updateLevel`, etc.
    var viewModelForTesting: PillViewModel { viewModel }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(targetOrigin(for: panel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        if spawnPending {
            spawnPending = false
            Task { @MainActor [weak self] in
                guard let self else { return }
                let completed = await self.viewModel.playSpawn()
                if completed {
                    self.onSpawnComplete?()
                }
            }
        } else {
            viewModel.phase = .armed
            onSpawnComplete?()
        }
    }

    /// Spec calls for the pill to scale slightly down (1.0 → 0.97) and fade
    /// out on completion. We do that here on the panel's contentView via a
    /// CALayer transform in addition to fading alpha.
    func hide() {
        guard let panel else { return }
        viewModel.cancelSpawn()  // safe no-op if no spawn in flight
        viewModel.phase = .idle
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.viewModel.level = 0
        })
    }
```

(Leave the rest of the file — `updateLevel`, `setPhase`, `makePanel`, `makeContainer`, positioning helpers, `DraggablePillView`, `PanelDelegate` — untouched.)

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "Test Case 'CyphrWhisprTests.testPillController|passed|FAIL" | head
```
Expected: both `testPillController_spawnsOnFirstShow_thenInstantOnSecond` and `testPillController_replaysSpawnAfterModelChange` pass.

- [ ] **Step 5: Commit**

```bash
git add CyphrWhispr/PillWindow/PillWindowController.swift CyphrWhisprTests/CyphrWhisprTests.swift
git commit -m "$(cat <<'EOF'
Gate PillWindowController.show on spawnPending flag

First show() per session triggers the cinematic spawn animation;
subsequent shows go straight to .armed (existing behaviour). The
flag re-arms whenever PreferencesStore posts activeModelDidChange,
so a model switch in Settings makes the next press cinematic again.

hide() now cancels any in-flight spawn before the fade-out.
EOF
)"
```

---

## Task 7: AppCoordinator buffers audio during spawn, drains on completion

**Files:**
- Modify: `CyphrWhispr/App/AppCoordinator.swift`

- [ ] **Step 1: Extend AppState with `.spawning`**

In `CyphrWhispr/App/AppCoordinator.swift`, replace the `AppState` enum (currently lines 5-13):

```swift
enum AppState: Equatable {
    case idle
    case loadingModel
    case armed
    case streaming
    case finalizing
    case injecting
    case error(String)
}
```

with:

```swift
enum AppState: Equatable {
    case idle
    case loadingModel
    /// Hotkey pressed but pill is mid-spawn (and/or whisper still warming).
    /// Audio capture has started; samples accumulate in `spawnBuffer`
    /// until both the spawn animation completes AND `whisper.warmUp()`
    /// has resolved, at which point we drain into `whisper.append(...)`
    /// and advance to `.streaming`.
    case spawning
    case armed
    case streaming
    case finalizing
    case injecting
    case error(String)
}
```

- [ ] **Step 2: Add a `spawnBuffer` property and rework `handleHotkeyPress` / `feed`**

In the same file, find `handleHotkeyPress()` (currently around lines 140-181). Replace the entire method:

```swift
    private func handleHotkeyPress() {
        guard state == .idle else { return }

        // Pre-flight: if Accessibility isn't granted (or has gone stale after a
        // rebuild), bail with an actionable message instead of letting the user
        // dictate into a silent paste pipeline.
        guard ClipboardPasteInjector.ensureAccessibilityTrusted(prompt: true) else {
            state = .error("Accessibility permission required. Toggle CyphrWhispr OFF then ON in System Settings → Privacy & Security → Accessibility.")
            scheduleReturnToIdle()
            return
        }

        state = .armed
        pill.show()

        do {
            try audio.start()
        } catch {
            state = .error("Microphone unavailable: \(error.localizedDescription)")
            pill.hide()
            scheduleReturnToIdle()
            return
        }

        // Snapshot the user's clipboard so we can restore it when the session ends.
        typingQueue.async { [weak self] in
            guard let self else { return }
            self.sessionClipboard = PasteboardSnapshot.capture()
            self.typedSoFar = ""
        }

        // Start the streaming session and feed each partial through the live
        // typing pipeline.
        streamConsumer = Task { [weak self] in
            guard let self else { return }
            let stream = await self.whisper.startStream()
            for await update in stream {
                self.applyTranscriptUpdate(update.text)
            }
        }
        state = .streaming
    }
```

with:

```swift
    private func handleHotkeyPress() {
        // Accept presses during .idle AND during the brief .loadingModel
        // window after launch — the pre-warm is happening in the background
        // and we now have a "spawning" state + spawn buffer to bridge the gap.
        guard state == .idle || state == .loadingModel else { return }

        guard ClipboardPasteInjector.ensureAccessibilityTrusted(prompt: true) else {
            state = .error("Accessibility permission required. Toggle CyphrWhispr OFF then ON in System Settings → Privacy & Security → Accessibility.")
            scheduleReturnToIdle()
            return
        }

        // Enter spawning state — pill plays the cinematic appearance, audio
        // capture starts immediately, samples buffer locally instead of
        // streaming until both the animation completes and whisper is warm.
        state = .spawning
        spawnBuffer.removeAll(keepingCapacity: true)
        pill.show()

        do {
            try audio.start()
        } catch {
            state = .error("Microphone unavailable: \(error.localizedDescription)")
            pill.hide()
            scheduleReturnToIdle()
            return
        }

        typingQueue.async { [weak self] in
            guard let self else { return }
            self.sessionClipboard = PasteboardSnapshot.capture()
            self.typedSoFar = ""
        }

        // Reset both readiness flags. The pill controller's `onSpawnComplete`
        // callback (wired up in `start()`) flips `spawnAnimationDone`; the
        // warm-up Task below flips `whisperWarmDone`. The second one to fire
        // calls `maybeBeginStreaming()` which actually advances state.
        spawnAnimationDone = false
        whisperWarmDone = false

        whisperWarmAwaiter?.cancel()
        whisperWarmAwaiter = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.whisper.warmUp()
            } catch {
                await MainActor.run {
                    self.state = .error("Model load failed: \(error.localizedDescription)")
                    self.endSession(restoreClipboard: true)
                }
                return
            }
            await MainActor.run {
                self.whisperWarmDone = true
                self.maybeBeginStreaming()
            }
        }
    }

    /// Called from two places — both fire only after the precondition they
    /// represent has been met:
    ///   • `pill.onSpawnComplete` callback flips `spawnAnimationDone`
    ///   • the warm-up Task above flips `whisperWarmDone`
    /// Whichever arrives second satisfies the guard and advances state to
    /// `.streaming`. Idempotent — re-entering after `.streaming` is a no-op.
    private func maybeBeginStreaming() {
        guard state == .spawning else { return }
        guard spawnAnimationDone && whisperWarmDone else { return }
        beginStreaming()
    }

    /// Open a streaming session, drain any buffered audio, and transition to
    /// `.streaming`. Caller MUST be on the main actor and MUST have verified
    /// `state == .spawning` (i.e. the user hasn't released the hotkey yet).
    private func beginStreaming() {
        streamConsumer = Task { [weak self] in
            guard let self else { return }
            let stream = await self.whisper.startStream()
            for await update in stream {
                self.applyTranscriptUpdate(update.text)
            }
        }
        state = .streaming

        // Drain whatever audio piled up during the spawn window.
        let drained = spawnBuffer
        spawnBuffer.removeAll(keepingCapacity: true)
        if !drained.isEmpty {
            Task { [whisper] in
                await whisper.append(samples: drained)
            }
        }
    }
```

In the same file, find the existing `feed(samples:)` method (currently around lines 206-211):

```swift
    private func feed(samples: [Float]) {
        guard state == .streaming else { return }
        Task { [whisper] in
            await whisper.append(samples: samples)
        }
    }
```

Replace with:

```swift
    private func feed(samples: [Float]) {
        switch state {
        case .streaming:
            Task { [whisper] in
                await whisper.append(samples: samples)
            }
        case .spawning:
            // Buffer locally — we'll drain into whisper.append once the spawn
            // animation completes AND whisper.warmUp() resolves.
            spawnBuffer.append(contentsOf: samples)
        default:
            return
        }
    }
```

Find `handleHotkeyRelease()` (currently around lines 183-204) and replace its guard:

```swift
    private func handleHotkeyRelease() {
        guard state == .streaming else { return }
```

with:

```swift
    private func handleHotkeyRelease() {
        // Release during .spawning is valid — user gave up before whisper
        // was ready. Cancel cleanly: stop audio, hide the pill, drop the
        // buffer, restore clipboard.
        if state == .spawning {
            spawnAwaiter?.cancel()
            spawnAwaiter = nil
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            endSession(restoreClipboard: true)
            return
        }

        guard state == .streaming else { return }
```

Add the new properties near the top of the `AppCoordinator` class, alongside `streamConsumer` (currently around line 32). Find:

```swift
    private var cancellables = Set<AnyCancellable>()
    private var streamConsumer: Task<Void, Never>?
    /// In-flight model switch task; we cancel an earlier switch if the user
    /// rapid-fires through a few options in Settings.
    private var modelSwitchTask: Task<Void, Never>?
```

Replace with:

```swift
    private var cancellables = Set<AnyCancellable>()
    private var streamConsumer: Task<Void, Never>?
    /// In-flight model switch task; we cancel an earlier switch if the user
    /// rapid-fires through a few options in Settings.
    private var modelSwitchTask: Task<Void, Never>?
    /// In-flight whisper warm-up task during the spawn window. Cancelled
    /// when the user releases the hotkey mid-spawn (so we don't try to
    /// drain into a stream that never starts).
    private var whisperWarmAwaiter: Task<Void, Never>?
    /// Set when `pill.onSpawnComplete` fires for the current session.
    private var spawnAnimationDone: Bool = false
    /// Set when `whisper.warmUp()` resolves for the current session.
    private var whisperWarmDone: Bool = false
    /// Audio captured during the spawn window. Drained into
    /// `whisper.append(...)` the moment streaming begins.
    private var spawnBuffer: [Float] = []
```

Then find the `start()` method (currently around lines 57-103) and update the `audio.onSamples = ...` block plus add the new pill callback hookup. Change this section:

```swift
        audio.onLevel = { [weak self] level in
            self?.pill.updateLevel(level)
        }
        audio.onSamples = { [weak self] samples in
            self?.feed(samples: samples)
        }
```

to:

```swift
        audio.onLevel = { [weak self] level in
            self?.pill.updateLevel(level)
        }
        audio.onSamples = { [weak self] samples in
            self?.feed(samples: samples)
        }

        // The pill fires this when its cinematic spawn animation finishes
        // (or immediately on subsequent shows in the same session). It's
        // one half of the precondition for advancing to `.streaming`; the
        // other half is whisper.warmUp resolving.
        pill.onSpawnComplete = { [weak self] in
            guard let self else { return }
            self.spawnAnimationDone = true
            self.maybeBeginStreaming()
        }
```

Also update `handleHotkeyRelease()` to cancel the warm-up awaiter (in addition to the audio flow). Find:

```swift
        // Release during .spawning is valid — user gave up before whisper
        // was ready. Cancel cleanly: stop audio, hide the pill, drop the
        // buffer, restore clipboard.
        if state == .spawning {
            spawnAwaiter?.cancel()
            spawnAwaiter = nil
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            endSession(restoreClipboard: true)
            return
        }
```

Replace with:

```swift
        // Release during .spawning is valid — user gave up before whisper
        // was ready. Cancel cleanly: stop audio, drop the buffer, hide
        // the pill, restore clipboard.
        if state == .spawning {
            whisperWarmAwaiter?.cancel()
            whisperWarmAwaiter = nil
            spawnAnimationDone = false
            whisperWarmDone = false
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            endSession(restoreClipboard: true)
            return
        }
```

- [ ] **Step 3: Build to verify the new state machine compiles**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' build 2>&1 | tail -10
```
Expected: clean build. (If there are switch-exhaustiveness warnings about `.spawning`, fix them inline — they'd appear in `StatusItemController.update(for:)` if it switches on AppState. Add `.spawning` mapped to whatever idle/active glyph already exists.)

- [ ] **Step 4: Inspect `StatusItemController.update(for:)` — add `.spawning` case if needed**

Run:
```bash
grep -n "case " "/Users/agustinkrupka/Documents/03_Profesional/Claude Projects/CyphrWhispr/CyphrWhispr/MenuBar/StatusItemController.swift" | head
```

If a switch over `AppState` is missing `.spawning`, add it. The spawning state should reuse the same icon as `.armed` (the active "ready to record" glyph). Open the file and add:

```swift
case .spawning, .armed:
    // (existing .armed body — same icon for the spawn-into-armed transition)
```

- [ ] **Step 5: Run the full test suite to verify nothing regressed**

Run:
```bash
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite|FAIL" | tail -10
```
Expected: all suites pass (existing tests + the four new ones across Tasks 2/4/6).

- [ ] **Step 6: Commit**

```bash
git add CyphrWhispr/App/AppCoordinator.swift CyphrWhispr/MenuBar/StatusItemController.swift
git commit -m "$(cat <<'EOF'
Wire AppCoordinator to the spawn animation + audio buffering

Adds AppState.spawning. handleHotkeyPress now accepts presses during
.loadingModel (the brief launch window when whisper is still warming),
shows the pill (which plays the cinematic spawn for first-of-session),
starts audio capture immediately, and buffers samples in spawnBuffer
until both the animation completes AND whisper.warmUp() resolves.

The spawnAwaiter task awaits both conditions in parallel; on success
it drains the buffer into whisper.append(...) and transitions to
.streaming. handleHotkeyRelease handles the early-release-during-spawn
case cleanly (cancels awaiter, drops buffer, hides pill, restores
clipboard).

Audio captured during the spawn no longer disappears — it lands as
the first words of the transcript.
EOF
)"
```

---

## Task 8: Manual smoke test + push

**Files:**
- (None modified — this task is pure verification.)

- [ ] **Step 1: Build the app for normal launch**

Run from the project root:
```bash
xcodegen generate
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr -configuration Debug -derivedDataPath build build 2>&1 | tail -5
```

If you get the recurring xattr / iCloud Drive codesign issue, apply the workaround:
```bash
for i in 1 2 3 4 5; do
  xattr -cr build/Build/Products/Debug/CyphrWhispr.app 2>/dev/null
  codesign --force --deep --sign 941468D53343F05869E9ECA0537B15D039ABE326 \
    -o runtime \
    --entitlements build/Build/Intermediates.noindex/CyphrWhispr.build/Debug/CyphrWhispr.build/CyphrWhispr.app.xcent \
    --timestamp=none --generate-entitlement-der \
    build/Build/Products/Debug/CyphrWhispr.app 2>&1 | tail -2
  if codesign --verify --strict build/Build/Products/Debug/CyphrWhispr.app 2>&1; then
    echo "SIGN OK on attempt $i"
    break
  fi
  sleep 0.3
done
```

- [ ] **Step 2: Verify scenario 1 — cold launch + immediate press**

```bash
pkill -9 -f CyphrWhispr 2>/dev/null
open "/Users/agustinkrupka/Documents/03_Profesional/Claude Projects/CyphrWhispr/build/Build/Products/Debug/CyphrWhispr.app"
```

Within 200ms of seeing the menu-bar icon appear, press and hold the dictation hotkey (default ⌥Space). Expected:
- Pill appears with the cinematic spawn (figures fade in centred, push outward, circle traverses left, comet rim ignites).
- Speak something — words must appear in the focused text field after release, including whatever you said during the animation.

- [ ] **Step 3: Verify scenario 2 — second press in same session is instant**

Without quitting, press the hotkey a second time. Expected: pill appears INSTANTLY in the armed state (no spawn animation). This is the existing fast path.

- [ ] **Step 4: Verify scenario 3 — replay after model switch**

Open Settings → Models. Switch to a different model. Wait for the model to finish loading (the menu-bar icon will indicate when ready). Press the hotkey. Expected: pill plays the cinematic spawn again (because `activeModelDidChange` reset `spawnPending`).

- [ ] **Step 5: Verify scenario 4 — release mid-spawn**

Press the hotkey, then release within 1 second (well before the 3.6s spawn completes). Expected: pill fades out cleanly, no orphaned animation, no error toast, no leaked tasks. (Verify with Activity Monitor that CPU drops to idle.)

- [ ] **Step 6: Verify scenario 5 — long dictation following a spawn**

Press hotkey, watch the spawn play, then continue holding and dictating for 30+ seconds. Release. Expected: full transcript pastes correctly. The audio captured during the spawn animation should appear at the start of the transcript.

- [ ] **Step 7: If all scenarios pass, push the branch**

```bash
git push 2>&1 | tail -5
```

- [ ] **Step 8: If any scenario fails, file findings inline**

Add a short note at the bottom of `docs/superpowers/specs/2026-05-04-prewarm-pill-spawn-animation-design.md` under a new heading "## Implementation findings" describing what failed and what was changed (or what's still open). Commit + push.

---

## Self-review notes (engineer pre-flight)

- The plan adds a single new file (`SpawnTimeline.swift`) plus modifications to four existing files. No restructuring beyond what's needed.
- TDD discipline: every modification with non-trivial logic has tests written FIRST (timeline math, notification posting, viewModel spawn cycle, controller spawn gating). UI rendering and the coordinator state-machine wiring rely on manual smoke tests because animation behaviour and AVAudioEngine timing don't unit-test cleanly.
- Geometry constants in the timeline are at production scale (170 × 48). The mockup at 2× is a design reference only.
- The spawnPending flag re-arms on `activeModelDidChange` notification, satisfying the "replay after model switch" decision.
- The "always play even when warm" decision is satisfied implicitly: the spawn animation runs unconditionally on first show per session, and the audio buffer drains into `whisper.append(...)` whether warm-up was a no-op (already warm) or a real wait.
- The audio-queueing-during-spawn requirement is implemented via `spawnBuffer` — bounded at most by the wall-clock duration of the spawn (3.6s × 16kHz mono Float32 ≈ 230 KB), well within memory budget.
- The handle-hotkey-release-mid-spawn edge case is explicitly handled in `handleHotkeyRelease()`.
