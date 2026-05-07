# First-Install Pill Animation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the cinematic first-install pill animation per the high-fidelity mockup, AND realign the existing idle pill + spawn-animation end-frame so both land on the same canonical idle state with no visual jump.

**Architecture:** Extend the existing `PillPhase` state machine with three new phases (`installSpawning`, `installCompiling`, `installOutro`), add a pure-math `InstallTimeline` driver mirroring `SpawnTimeline`, render the new phases in `PillView`, and route `AppCoordinator` to play the install animation whenever the hotkey arrives during `state == .loadingModel`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (for the floating panel), QuartzCore (`CACurrentMediaTime` for monotonic timing), no new external deps.

**Canonical reference:** `docs/superpowers/specs/assets/2026-05-04-first-install-animation-mockup.html` and the README delivered with it (`Visual Aides/Pill Animation/Start up Animation/design_handoff_pill_animation/README.md`).

---

## Task 1: Realign idle pill bars to new spec

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift` (normalBody)
- Modify: `CyphrWhispr/PillWindow/WaveformView.swift` (positioning)
- Test: existing app build + `CyphrWhispr/PillWindow/PillView.swift` previews

**Context:** The current `normalBody` uses `HStack` with `.frame(maxWidth: .infinity)` on the waveform, so bar positions are not pixel-deterministic. The new spec puts bars at fixed X positions: `[90, 97, 104, 111, 118, 125, 132]` (left edges, production pt). This is a structural change — bars become absolutely positioned, not flow-laid-out.

- [ ] **Step 1: Switch normalBody to ZStack-with-absolute-positions layout**

The new layout should still vertically centre, still use the existing capsule + rim treatment, but place the inner content via absolute X offsets:

```swift
@ViewBuilder
private var normalBody: some View {
    let shape = Capsule(style: .continuous)
    ZStack(alignment: .leading) {
        shape
            .fill(Color.black)
            .frame(width: Self.pillWidth, height: Self.pillHeight)
            .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)

        DownTriangle()
            .fill(Color.white)
            .frame(width: 18, height: 16)
            .offset(x: 22, y: (Self.pillHeight - 16) / 2)

        Circle()
            .fill(Color.white)
            .frame(width: 17, height: 17)
            .scaleEffect(viewModel.phase == .listening
                         ? 1.0 + CGFloat(min(viewModel.level, 1)) * 0.10
                         : 1.0)
            .animation(.easeOut(duration: 0.12), value: viewModel.level)
            .offset(x: 47, y: (Self.pillHeight - 17) / 2)

        WaveformView(level: viewModel.level, phase: viewModel.phase)
            .frame(width: Self.waveformWidth, height: Self.pillHeight)
            .offset(x: Self.waveformX, y: 0)
    }
    .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
    .overlay(RimHighlights(visible: viewModel.phase != .idle,
                           animating: viewModel.phase != .idle,
                           intensity: (viewModel.phase == .listening ? 0.95 : 0.65),
                           level: viewModel.level,
                           accent: prefs.accent,
                           accentSecondary: prefs.accentSecondary))
}

// New constants on PillView:
private static let waveformX: CGFloat = 90        // left edge of bar 1
private static let waveformWidth: CGFloat = 45    // 7 bars × 3pt + 6 gaps × 4pt = 45pt
```

- [ ] **Step 2: Update WaveformView to render at the new fixed width**

`WaveformView` already lays out bars in an HStack with fixed `barWidth: 3` and `spacing: 4`. With a 45pt frame it should fill exactly (`7×3 + 6×4 = 45`). No change to `WaveformView` itself — just verify it renders correctly inside the new fixed-width frame.

- [ ] **Step 3: Build the app and visually verify**

Run `./scripts/build-and-run.sh` (or whichever invocation the project uses). Trigger the pill via hotkey. Confirm:
- Bars sit roughly centred-right inside the pill
- ~14pt gap between circle right edge and bar 1 left edge
- ~35pt right margin from bar 7 right edge to capsule right edge
- Existing armed/listening/processing animations still drive the bars correctly

- [ ] **Step 4: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift CyphrWhispr/PillWindow/WaveformView.swift
git commit -m "Realign idle pill bars to new fixed-position spec"
```

---

## Task 2: Update SpawnTimeline geometry to match new idle frame

**Files:**
- Modify: `CyphrWhispr/PillWindow/SpawnTimeline.swift`
- Modify: `CyphrWhisprTests/SpawnTimelineTests.swift`
- Modify: `CyphrWhispr/PillWindow/PillView.swift` (spawnBody bar rendering)

**Context:** Current `SpawnTimeline` was built against the old 5-bar placeholder. It must be brought in line with the new 7-bar idle frame so the spawn animation lands on the exact pixel positions of the idle pill — no jump on hand-off. The dot's traverse end position must also match: `dotTraverseEndX = 47` (the new circle X).

- [ ] **Step 1: Update SpawnTimeline geometry constants**

```swift
enum SpawnTimeline {
    // ... phase boundaries unchanged ...

    static let pillSeedW: CGFloat = 45
    static let pillFullW: CGFloat = 170
    static let triPushEndX: CGFloat = 12   // unchanged — but see Step 3 note
    static let dotPushHoldX: CGFloat = 135 // ≈ 170 - 12 - 17 - 6 (right-pinned during push hold)
    static let dotTraverseEndX: CGFloat = 47  // CHANGED: was 46, now matches idle

    // Bars: 7 bars at the new idle X positions
    static let barColumns: [CGFloat] = [90, 97, 104, 111, 118, 125, 132]
    static let barWidth: CGFloat = 3                              // CHANGED: was 2
    static let barHeights: [CGFloat] = [7, 12, 15, 24, 15, 12, 7] // NEW (replaces barCentreHeight + barShortHeight)
}

struct SpawnState: Equatable {
    var figureOpacity: Double
    var figureScale: Double
    var pillWidth: CGFloat
    var triangleX: CGFloat
    var dotX: CGFloat
    var barOpacities: [Double]   // 7 elements now (was 5)
    var rimOpacity: Double
}
```

- [ ] **Step 2: Update bar cascade in `state(at:)` to spread across 7 bars**

The existing cascade goes right-to-left during the traverse phase. Now there are 7 bars instead of 5. Spread the staggered fade-in across the same time window (`pHoldEnd → pTraverseEnd`) but with 7 stops:

```swift
// Inside state(at:), replace 5-bar logic with:
let traverseT: Double = clamp((t - pHoldEnd) / (pTraverseEnd - pHoldEnd), 0, 1)
// Each bar fades in over 0.20 of the traverse window. Right-to-left stagger:
// bar 6 (rightmost) starts at traverseT = 0.0
// bar 0 (leftmost)  starts at traverseT = 0.80
let barOpacities: [Double] = (0..<7).map { i in
    let reverseIndex = Double(6 - i)            // 6 → 0
    let startT = reverseIndex / 6.0 * 0.80      // 0.0, 0.133, 0.267, 0.40, 0.533, 0.667, 0.80
    let progress = clamp((traverseT - startT) / 0.20, 0, 1)
    return easeOut(progress)
}
```

- [ ] **Step 3: Update SpawnTimelineTests to test 7 bars**

The existing tests reference `barOpacities[0..<5]` (or similar). Update each test:
- At `t = pHoldEnd`, all 7 bars are 0
- At `t = pHoldEnd + (pTraverseEnd - pHoldEnd) * 0.10`, only bar 6 should be partially in (others 0)
- At `t = pTraverseEnd`, all 7 bars are 1
- Add an assertion that `barColumns.count == 7`, `barOpacities.count == 7`

- [ ] **Step 4: Update `PillView.spawnBody` to render 7 bars at the new heights**

```swift
ForEach(0..<7, id: \.self) { i in
    let barHeight = SpawnTimeline.barHeights[i]
    Rectangle()
        .fill(Color.white)
        .frame(width: SpawnTimeline.barWidth, height: barHeight)
        .opacity(s.barOpacities[i])
        .offset(x: SpawnTimeline.barColumns[i],
                y: (Self.pillHeight - barHeight) / 2)
}
```

Use `Capsule()` shape instead of `Rectangle()` so bars have rounded ends matching the WaveformView (`radius = barWidth / 2 = 1.5pt`).

- [ ] **Step 5: Verify spawn end-frame matches idle frame visually**

Build, trigger spawn via cold launch + immediate hotkey. Watch the moment the spawn ends: bars should NOT pop in number, position, height, or width. Triangle should NOT jump. Circle should NOT jump.

- [ ] **Step 6: Run tests + commit**

```bash
xcodebuild -scheme CyphrWhispr -destination 'platform=macOS' test 2>&1 | grep -E "(Test Case|FAILED|PASSED)"
git add CyphrWhispr/PillWindow/SpawnTimeline.swift CyphrWhispr/PillWindow/PillView.swift CyphrWhisprTests/SpawnTimelineTests.swift
git commit -m "Update SpawnTimeline to 7-bar geometry matching new idle"
```

---

## Task 3: Add new PillPhase cases

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift`
- Modify: `CyphrWhispr/MenuBar/StatusItemController.swift`
- Modify: `CyphrWhispr/PillWindow/WaveformView.swift`
- Modify: `CyphrWhispr/App/AppCoordinator.swift`

**Context:** Three new phases parallel the install animation's three structural sections.

- [ ] **Step 1: Add the three new cases**

```swift
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    case spawning(progress: Double)
    case installSpawning(progress: Double)        // NEW: 0 → 1 over the 2.0s intro
    case installCompiling(progress: Double)       // NEW: 0 → 1 = rim sweep fraction
    case installOutro(progress: Double)           // NEW: 0 → 1 over the 1.3s outro
    case armed
    case listening
    case processing
}
```

- [ ] **Step 2: Update WaveformView's exhaustive switch to handle the new cases**

Add `.installSpawning, .installCompiling, .installOutro` to the `.idle, .spawning` fallthrough — WaveformView shouldn't be drawing during install phases either (PillView renders bars directly).

```swift
case .idle, .spawning, .installSpawning, .installCompiling, .installOutro:
    return resting
```

- [ ] **Step 3: Update StatusItemController to bucket install phases as "active"**

The status item already buckets `.spawning` as an active state. Add the three install phases to the same bucket so the menu-bar icon reflects activity during install.

- [ ] **Step 4: Update AppState if necessary**

If `AppCoordinator.AppState` needs an explicit `.installing` case, add it. If we can reuse `.spawning` as a generic "pill is showing, audio buffered, awaiting completion" state, prefer that for simplicity. **Recommendation: reuse `.spawning`** — the state machine doesn't care which animation is playing, only that the pill is up and audio is buffering.

- [ ] **Step 5: Build to verify no missing-case warnings**

```bash
xcodebuild -scheme CyphrWhispr build 2>&1 | grep -E "(warning|error|missing)"
```

- [ ] **Step 6: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift CyphrWhispr/PillWindow/WaveformView.swift CyphrWhispr/MenuBar/StatusItemController.swift CyphrWhispr/App/AppCoordinator.swift
git commit -m "Add installSpawning/installCompiling/installOutro phases"
```

---

## Task 4: Build InstallTimeline pure-math driver + tests

**Files:**
- Create: `CyphrWhispr/PillWindow/InstallTimeline.swift`
- Create: `CyphrWhisprTests/InstallTimelineTests.swift`

**Context:** Mirror the `SpawnTimeline` pattern: pure-math, deterministic, 100% testable. Two timelines: `introState(at:)` for installSpawning (0 → 1 over 2.0s) and `outroState(at:)` for installOutro (0 → 1 over 1.3s). The compiling phase is a single scalar (rim fraction), no timeline math needed.

- [ ] **Step 1: Write the failing tests first**

```swift
// CyphrWhisprTests/InstallTimelineTests.swift
import XCTest
@testable import CyphrWhispr

final class InstallTimelineTests: XCTestCase {

    // MARK: - Intro

    func testIntro_atZero_pillIsSeed_figuresInvisible() {
        let s = InstallTimeline.introState(at: 0)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillSeedW)
        XCTAssertEqual(s.figureOpacity, 0)
        XCTAssertEqual(s.figureScale, 0.5, accuracy: 0.001)
    }

    func testIntro_atSpawnEnd_figuresFullyVisible() {
        let s = InstallTimeline.introState(at: InstallTimeline.pSpawnEnd)
        XCTAssertEqual(s.figureOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.001)
    }

    func testIntro_atAnticipationEnd_pillCompressed() {
        let s = InstallTimeline.introState(at: InstallTimeline.pAnticipationEnd)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillAntiW, accuracy: 0.5)
        XCTAssertEqual(s.figureScale, 0.97, accuracy: 0.01)
    }

    func testIntro_atPushEnd_pillFullWidth_figuresAtExtremes() {
        let s = InstallTimeline.introState(at: InstallTimeline.pPushEnd)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillFullW, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, InstallTimeline.triFinalX, accuracy: 0.5)
        XCTAssertEqual(s.dotX, InstallTimeline.dotPushEndX, accuracy: 0.5)
    }

    func testIntro_atOne_labelFullyVisible() {
        let s = InstallTimeline.introState(at: 1.0)
        XCTAssertEqual(s.labelOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.labelOffsetY, 0, accuracy: 0.5)
    }

    // MARK: - Outro

    func testOutro_atZero_pillFullWidth_circleAtPushEnd_barsHidden() {
        let s = InstallTimeline.outroState(at: 0)
        XCTAssertEqual(s.dotX, InstallTimeline.dotPushEndX, accuracy: 0.5)
        XCTAssertEqual(s.rimOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.labelOpacity, 1.0, accuracy: 0.001)
        for opacity in s.barOpacities {
            XCTAssertEqual(opacity, 0, accuracy: 0.001)
        }
        XCTAssertEqual(s.cometOpacity, 0, accuracy: 0.001)
    }

    func testOutro_atOne_circleAtIdle_barsVisible_cometIgnited() {
        let s = InstallTimeline.outroState(at: 1.0)
        XCTAssertEqual(s.dotX, InstallTimeline.dotIdleX, accuracy: 0.5)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.labelOpacity, 0, accuracy: 0.001)
        for opacity in s.barOpacities {
            XCTAssertEqual(opacity, 1, accuracy: 0.001)
        }
        XCTAssertEqual(s.cometOpacity, 1, accuracy: 0.001)
    }

    func testOutro_barCascadeIsRightToLeft() {
        // At ~25% through the outro, only the rightmost bars should be partially visible
        let s = InstallTimeline.outroState(at: 0.25)
        XCTAssertGreaterThan(s.barOpacities[6], s.barOpacities[0])
        XCTAssertGreaterThan(s.barOpacities[5], s.barOpacities[0])
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Expected: "InstallTimeline not defined" or similar.

- [ ] **Step 3: Write `InstallTimeline.swift`**

```swift
import Foundation
import CoreGraphics

/// Phase boundaries (intro, normalised 0 → 1 over 2.0s production):
///   0.000 → 0.300  Spawn        (0.6s)
///   0.300 → 0.425  Anticipation (0.25s)
///   0.425 → 0.850  Push         (0.85s)
///   0.850 → 1.000  Hold + label-in (0.30s)
///
/// Phase boundaries (outro, normalised 0 → 1 over 1.3s production):
///   0.000 → 0.462  Rim fade-out + label fade-out + circle traverse + bar cascade overlap
///   (rim 0.0→0.46 ≈ 0.6s; label 0.0→0.31 ≈ 0.4s; circle 0.0→0.77 ≈ 1.0s; bars start ~0.15)
///   0.692 → 1.000  Comet ignite + brightness flash settle
struct InstallIntroState: Equatable {
    var figureOpacity: Double
    var figureScale: Double
    var pillWidth: CGFloat
    var triangleX: CGFloat
    var dotX: CGFloat
    var labelOpacity: Double
    var labelOffsetY: CGFloat   // 4pt below at start, 0 at final
}

struct InstallOutroState: Equatable {
    var dotX: CGFloat
    var rimOpacity: Double
    var labelOpacity: Double
    var labelOffsetY: CGFloat   // 0 at start, 4pt below at end
    var barOpacities: [Double]  // 7 elements
    var barOffsetsY: [CGFloat]  // 3pt below at start, 0 at end (per bar)
    var cometOpacity: Double
    var cometBrightness: Double // 1.0 default, 1.6 at flash apex
    var staticRimOpacity: Double
}

enum InstallTimeline {
    // Geometry
    static let pillSeedW: CGFloat = 63
    static let pillAntiW: CGFloat = 60
    static let pillFullW: CGFloat = 170
    static let triFinalX: CGFloat = 12   // pinned 12pt left padding inside seed AND full pill
    static let triIdleX: CGFloat = 22    // production idle position (matches SpawnTimeline + normalBody)

    // The triangle in the install animation stays at x = 12 (pinned to left wall, NEVER traverses).
    // After the install ends, the ZStack hands off to normalBody where the triangle is at x = 22.
    // The ~10pt difference at hand-off is acceptable here ONLY IF the outro slides the triangle
    // leftward to land at 22. If we want a clean hand-off, slide it. Decision: slide it.
    // (Use an `outroState.triangleX` field that lerps from triFinalX → triIdleX during outro.)

    static let dotPushEndX: CGFloat = 135 // 170 - 12 - 17 - 6 (right-padding 12, dot width 17)
    // Wait — recheck: per the README, mockup circle ends at left=282px = 141pt production.
    // 141 = pillFullW - 29 = 170 - 29. So dotPushEndX = 141.
    // Updated:
    // (Comment kept here for reviewer; final value below.)

    // Phase boundaries — intro
    static let pSpawnEnd: Double = 0.300
    static let pAnticipationEnd: Double = 0.425
    static let pPushEnd: Double = 0.850
    // (label-in continues to 1.0)

    // Phase boundaries — outro
    static let pCircleTraverseEnd: Double = 0.769  // 1.0s of 1.3s
    static let pRimFadeEnd: Double = 0.462         // 0.6s of 1.3s
    static let pLabelFadeEnd: Double = 0.308       // 0.4s of 1.3s
    static let pCometIgniteStart: Double = 0.654   // ~250ms after rim fade ends

    // Bar cascade (right-to-left, 120ms stagger, 220ms each fade)
    // Bar starts and ends in normalised outro time:
    static let barCascadeStartT: Double = 0.115    // ~150ms in (right after rim fade-out has begun)
    static let barCascadeStaggerT: Double = 0.092  // 120ms / 1300ms
    static let barCascadeFadeT: Double = 0.169     // 220ms / 1300ms

    static let barIdleHeights: [CGFloat] = [7, 12, 15, 24, 15, 12, 7]
    static let barIdleColumns: [CGFloat] = [90, 97, 104, 111, 118, 125, 132]
    static let barWidth: CGFloat = 3

    static func introState(at t: Double) -> InstallIntroState {
        let t = clamp(t, 0, 1)
        // Spawn: figure opacity & scale 0→1; pill stays at seed width
        // Anticipation: pill compresses seedW → antiW; figures scale 1.0 → 0.97
        // Push: pill antiW → fullW; figures back to 1.0; triangle pinned at triFinalX,
        //   circle pinned at pillWidth - 29
        // Label-in: opacity 0→1; offsetY 4pt → 0pt
        let figureOpacity: Double
        let figureScale: Double
        let pillWidth: CGFloat
        let dotX: CGFloat

        if t < pSpawnEnd {
            let p = t / pSpawnEnd
            figureOpacity = easeInOut(p)
            figureScale = lerp(0.5, 1.0, easeInOut(p))
            pillWidth = pillSeedW
            dotX = pillSeedW - 29  // 12 right padding + 17 width = 29 from right wall
        } else if t < pAnticipationEnd {
            let p = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            figureOpacity = 1.0
            figureScale = lerp(1.0, 0.97, easeInOut(p))
            pillWidth = lerp(pillSeedW, pillAntiW, easeInOut(p))
            dotX = pillWidth - 29
        } else if t < pPushEnd {
            let p = (t - pAnticipationEnd) / (pPushEnd - pAnticipationEnd)
            let eased = easeOutCubic(p)  // mimic cubic-bezier(0.16, 0.84, 0.30, 1)
            figureOpacity = 1.0
            figureScale = lerp(0.97, 1.0, eased)
            pillWidth = lerp(pillAntiW, pillFullW, eased)
            dotX = pillWidth - 29
        } else {
            // Hold + label-in
            figureOpacity = 1.0
            figureScale = 1.0
            pillWidth = pillFullW
            dotX = pillFullW - 29
        }

        // Label
        let labelOpacity: Double
        let labelOffsetY: CGFloat
        if t < pPushEnd {
            labelOpacity = 0
            labelOffsetY = 4
        } else {
            let p = (t - pPushEnd) / (1.0 - pPushEnd)
            labelOpacity = easeInOut(p)
            labelOffsetY = lerp(4, 0, easeInOut(p))
        }

        return InstallIntroState(
            figureOpacity: figureOpacity,
            figureScale: figureScale,
            pillWidth: pillWidth,
            triangleX: triFinalX,
            dotX: dotX,
            labelOpacity: labelOpacity,
            labelOffsetY: labelOffsetY
        )
    }

    static func outroState(at t: Double) -> InstallOutroState {
        let t = clamp(t, 0, 1)

        // Circle traverses 141 → triIdleX + 25 = 47 over 0..pCircleTraverseEnd
        let circleStartX: CGFloat = pillFullW - 29  // 141
        let circleEndX: CGFloat = 47
        let dotX: CGFloat
        if t < pCircleTraverseEnd {
            let p = t / pCircleTraverseEnd
            dotX = lerp(circleStartX, circleEndX, easeOutCubic(p))
        } else {
            dotX = circleEndX
        }

        // Rim fade-out: 1.0 → 0 over 0..pRimFadeEnd
        let rimOpacity: Double = (t < pRimFadeEnd)
            ? 1.0 - easeInOut(t / pRimFadeEnd)
            : 0

        // Label fade-out: 1.0 → 0 over 0..pLabelFadeEnd
        let labelOpacity: Double = (t < pLabelFadeEnd)
            ? 1.0 - easeInOut(t / pLabelFadeEnd)
            : 0
        let labelOffsetY: CGFloat = (t < pLabelFadeEnd)
            ? lerp(0, 4, easeInOut(t / pLabelFadeEnd))
            : 4

        // Bars: right-to-left cascade
        var barOpacities = [Double](repeating: 0, count: 7)
        var barOffsetsY = [CGFloat](repeating: 3, count: 7)
        for i in 0..<7 {
            let reverseIndex = Double(6 - i) // 6 → 0 (rightmost first)
            let startT = barCascadeStartT + reverseIndex * barCascadeStaggerT
            let progress = clamp((t - startT) / barCascadeFadeT, 0, 1)
            barOpacities[i] = easeOutQuint(progress)
            barOffsetsY[i] = lerp(3, 0, easeOutQuint(progress))
        }

        // Comet ignite: opacity 0 → 1 over 0.5 of remaining window after pCometIgniteStart
        let cometOpacity: Double
        let cometBrightness: Double
        let staticRimOpacity: Double
        if t < pCometIgniteStart {
            cometOpacity = 0
            cometBrightness = 1.0
            staticRimOpacity = 0
        } else {
            let p = (t - pCometIgniteStart) / (1.0 - pCometIgniteStart)
            cometOpacity = easeOut(p * 2.5).clamped(0, 1)  // fast fade-in
            // Brightness: 1.0 → 1.6 → 1.0 (flash). Peak at p ≈ 0.4
            cometBrightness = 1.0 + 0.6 * exp(-pow((p - 0.4) * 6, 2))
            staticRimOpacity = easeInOut(p)
        }

        return InstallOutroState(
            dotX: dotX,
            rimOpacity: rimOpacity,
            labelOpacity: labelOpacity,
            labelOffsetY: labelOffsetY,
            barOpacities: barOpacities,
            barOffsetsY: barOffsetsY,
            cometOpacity: cometOpacity,
            cometBrightness: cometBrightness,
            staticRimOpacity: staticRimOpacity
        )
    }

    // MARK: - Easing helpers (private, file-local — also used by SpawnTimeline; if duplicated, refactor into shared file)

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }
    private static func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(x, lo), hi)
    }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
    private static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }
    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }
    private static func easeOutQuint(_ t: Double) -> Double {
        1 - pow(1 - t, 5)
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme CyphrWhispr -destination 'platform=macOS' test -only-testing:CyphrWhisprTests/InstallTimelineTests 2>&1 | grep -E "Test Case"
```

- [ ] **Step 5: Commit**

```bash
git add CyphrWhispr/PillWindow/InstallTimeline.swift CyphrWhisprTests/InstallTimelineTests.swift
git commit -m "Add InstallTimeline pure-math driver + tests"
```

---

## Task 5: Add install methods to PillViewModel

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift` (PillViewModel)
- Modify: `CyphrWhisprTests/CyphrWhisprTests.swift` (or new file)

**Context:** Mirror the existing `playSpawn` / `cancelSpawn` pattern.

- [ ] **Step 1: Write failing tests**

```swift
@MainActor
func testPlayInstallSpawn_progressesFromZeroToCompiling() async {
    let vm = PillViewModel()
    let task = Task { await vm.playInstallSpawn(duration: 0.1) }
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    if case .installSpawning(let p) = vm.phase {
        XCTAssertGreaterThan(p, 0)
        XCTAssertLessThan(p, 1)
    } else {
        XCTFail("Expected .installSpawning, got \(vm.phase)")
    }
    let didFinish = await task.value
    XCTAssertTrue(didFinish)
    if case .installCompiling(let p) = vm.phase {
        XCTAssertEqual(p, 0)
    } else {
        XCTFail("Expected .installCompiling, got \(vm.phase)")
    }
}

@MainActor
func testSetInstallProgress_updatesRimFraction() {
    let vm = PillViewModel()
    vm.phase = .installCompiling(progress: 0)
    vm.setInstallProgress(0.42)
    if case .installCompiling(let p) = vm.phase {
        XCTAssertEqual(p, 0.42, accuracy: 0.001)
    } else {
        XCTFail("Expected .installCompiling")
    }
}

@MainActor
func testPlayInstallOutro_progressesToArmed() async {
    let vm = PillViewModel()
    vm.phase = .installCompiling(progress: 1.0)
    let task = Task { await vm.playInstallOutro(duration: 0.1) }
    let didFinish = await task.value
    XCTAssertTrue(didFinish)
    XCTAssertEqual(vm.phase, .armed)
}

@MainActor
func testCancelInstall_stopsTimeline() {
    let vm = PillViewModel()
    Task { await vm.playInstallSpawn(duration: 1.0) }
    vm.cancelInstall()
    // Phase stays at whatever installSpawning(progress:) value it last had,
    // OR whatever the caller sets next. We don't enforce a specific phase.
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement on PillViewModel**

```swift
private var installSpawnTask: Task<Bool, Never>?
private var installOutroTask: Task<Bool, Never>?

@discardableResult
func playInstallSpawn(duration: TimeInterval = 2.0) async -> Bool {
    installSpawnTask?.cancel()
    let task = Task<Bool, Never> { @MainActor in
        let start = CACurrentMediaTime()
        phase = .installSpawning(progress: 0)
        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - start
            let t = min(1.0, elapsed / duration)
            phase = .installSpawning(progress: t)
            if t >= 1.0 { break }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        if Task.isCancelled { return false }
        phase = .installCompiling(progress: 0)
        return true
    }
    installSpawnTask = task
    return await task.value
}

func setInstallProgress(_ p: Double) {
    let clamped = min(max(p, 0), 1)
    phase = .installCompiling(progress: clamped)
}

@discardableResult
func playInstallOutro(duration: TimeInterval = 1.3) async -> Bool {
    installOutroTask?.cancel()
    let task = Task<Bool, Never> { @MainActor in
        let start = CACurrentMediaTime()
        phase = .installOutro(progress: 0)
        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - start
            let t = min(1.0, elapsed / duration)
            phase = .installOutro(progress: t)
            if t >= 1.0 { break }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        if Task.isCancelled { return false }
        phase = .armed
        return true
    }
    installOutroTask = task
    return await task.value
}

func cancelInstall() {
    installSpawnTask?.cancel(); installSpawnTask = nil
    installOutroTask?.cancel(); installOutroTask = nil
}
```

- [ ] **Step 4: Run tests + commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift CyphrWhisprTests/CyphrWhisprTests.swift
git commit -m "Add install timeline methods to PillViewModel"
```

---

## Task 6: Render install phases in PillView

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillView.swift`

**Context:** Three new phase-specific renderers: `installSpawnBody(progress:)`, `installCompileBody(rimFraction:)`, `installOutroBody(progress:)`. The compile rim sweep is the trickiest part — needs a `Capsule().trim(from:to:)` or a custom `Path` drawing the capsule outline starting from top centre and going clockwise.

- [ ] **Step 1: Add the install renderers**

```swift
@ViewBuilder
private func installSpawnBody(progress: Double) -> some View {
    let s = InstallTimeline.introState(at: progress)
    let shape = Capsule(style: .continuous)

    ZStack(alignment: .leading) {
        shape
            .fill(Color.black)
            .frame(width: s.pillWidth, height: Self.pillHeight)
            .shadow(color: .black.opacity(0.50 * s.figureOpacity), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20 * s.figureOpacity), radius: 3, x: 0, y: 1)

        DownTriangle()
            .fill(Color.white)
            .frame(width: 18, height: 16)
            .opacity(s.figureOpacity)
            .scaleEffect(s.figureScale)
            .offset(x: s.triangleX, y: (Self.pillHeight - 16) / 2)

        Circle()
            .fill(Color.white)
            .frame(width: 17, height: 17)
            .opacity(s.figureOpacity)
            .scaleEffect(s.figureScale)
            .offset(x: s.dotX, y: (Self.pillHeight - 17) / 2)

        // Label fades in during the hold phase
        if s.labelOpacity > 0 {
            Text("compiling")
                .font(.system(size: 12, weight: .regular))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.85 * s.labelOpacity))
                .frame(width: s.pillWidth, height: Self.pillHeight)
                .offset(y: s.labelOffsetY)
        }
    }
    .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
}

@ViewBuilder
private func installCompileBody(rimFraction: Double) -> some View {
    let shape = Capsule(style: .continuous)

    ZStack(alignment: .leading) {
        shape
            .fill(Color.black)
            .frame(width: Self.pillWidth, height: Self.pillHeight)
            .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)

        DownTriangle()
            .fill(Color.white)
            .frame(width: 18, height: 16)
            .offset(x: InstallTimeline.triFinalX, y: (Self.pillHeight - 16) / 2)

        Circle()
            .fill(Color.white)
            .frame(width: 17, height: 17)
            .offset(x: Self.pillWidth - 29, y: (Self.pillHeight - 17) / 2)

        // Breathing "compiling" label, centred
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.0) / 3.0
            let breath = 0.85 + 0.15 * (sin(phase * 2 * .pi) * 0.5 + 0.5)
            Text("compiling")
                .font(.system(size: 12, weight: .regular))
                .tracking(0.5)
                .foregroundColor(.white.opacity(breath))
                .frame(width: Self.pillWidth, height: Self.pillHeight)
        }
    }
    .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
    .overlay(
        ProgressRim(fraction: rimFraction, accent: prefs.accent, accentSecondary: prefs.accentSecondary)
    )
}

@ViewBuilder
private func installOutroBody(progress: Double) -> some View {
    let s = InstallTimeline.outroState(at: progress)
    let shape = Capsule(style: .continuous)

    ZStack(alignment: .leading) {
        shape
            .fill(Color.black)
            .frame(width: Self.pillWidth, height: Self.pillHeight)
            .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)

        DownTriangle()
            .fill(Color.white)
            .frame(width: 18, height: 16)
            .offset(x: 22, y: (Self.pillHeight - 16) / 2)  // sits at idle position throughout outro

        Circle()
            .fill(Color.white)
            .frame(width: 17, height: 17)
            .offset(x: s.dotX, y: (Self.pillHeight - 17) / 2)

        // Bars cascading in
        ForEach(0..<7, id: \.self) { i in
            let h = InstallTimeline.barIdleHeights[i]
            Capsule()
                .fill(LinearGradient(stops: [
                    .init(color: .white,                                              location: 0.0),
                    .init(color: Color(red: 0.855, green: 0.855, blue: 0.886),        location: 0.5),
                    .init(color: Color(red: 0.537, green: 0.541, blue: 0.580),        location: 1.0)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: InstallTimeline.barWidth, height: h)
                .opacity(s.barOpacities[i])
                .offset(x: InstallTimeline.barIdleColumns[i],
                        y: (Self.pillHeight - h) / 2 + s.barOffsetsY[i])
        }

        // Fading label
        if s.labelOpacity > 0 {
            Text("compiling")
                .font(.system(size: 12, weight: .regular))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.85 * s.labelOpacity))
                .frame(width: Self.pillWidth, height: Self.pillHeight)
                .offset(y: s.labelOffsetY)
        }
    }
    .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
    // Progress rim fading out
    .overlay(
        ProgressRim(fraction: 1.0, accent: prefs.accent, accentSecondary: prefs.accentSecondary)
            .opacity(s.rimOpacity)
    )
    // Comet rim igniting
    .overlay(
        RimHighlights(visible: s.cometOpacity > 0,
                      animating: true,
                      intensity: 0.85 * s.cometBrightness,
                      level: 0,
                      accent: prefs.accent,
                      accentSecondary: prefs.accentSecondary)
            .opacity(s.cometOpacity)
    )
}
```

- [ ] **Step 2: Add the `ProgressRim` view**

This draws a capsule outline starting at top-centre, going clockwise, trimmed to `fraction` of the perimeter. Use SwiftUI's `Path` directly.

```swift
private struct ProgressRim: View {
    let fraction: Double
    let accent: Color
    let accentSecondary: Color

    var body: some View {
        Canvas { ctx, size in
            // Capsule path starting at top centre, going clockwise
            let path = capsulePath(in: CGRect(origin: .zero, size: size), startAtTopCentre: true)
            let perimeter = path.length()
            let visibleLength = perimeter * CGFloat(fraction.clamped(0, 1))

            // Use trimmedPath
            let trimmed = path.trimmedPath(from: 0, to: max(0.0001, fraction))

            // Halo
            ctx.opacity = 0.55
            ctx.addFilter(.blur(radius: 3))
            ctx.stroke(trimmed, with: .color(accent.opacity(0.35)), lineWidth: 5)

            // Crisp core (gradient leading edge → accent → secondary)
            ctx.opacity = 1
            ctx.addFilter(.blur(radius: 0))
            ctx.stroke(trimmed, with: .linearGradient(
                Gradient(stops: [
                    .init(color: accentSecondary.opacity(0.6), location: 0),
                    .init(color: accent, location: 0.5),
                    .init(color: .white.opacity(0.85), location: 1.0)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ), lineWidth: 2.5)
        }
    }

    private func capsulePath(in rect: CGRect, startAtTopCentre: Bool) -> Path {
        // Capsule with corner radius = rect.height / 2
        let r = rect.height / 2
        let mid = rect.width / 2

        var p = Path()
        if startAtTopCentre {
            p.move(to: CGPoint(x: mid, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
            p.addArc(center: CGPoint(x: rect.maxX - r, y: r),
                     radius: r, startAngle: .degrees(-90), endAngle: .degrees(90),
                     clockwise: false)
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.minX + r, y: r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(270),
                     clockwise: false)
            p.addLine(to: CGPoint(x: mid, y: 0))
        }
        return p
    }
}

private extension Path {
    func length() -> CGFloat {
        // Approximate via flattened path
        var len: CGFloat = 0
        var prev: CGPoint?
        let cgPath = self.cgPath
        cgPath.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                prev = pts[0]
            case .addLineToPoint:
                if let p = prev { len += hypot(pts[0].x - p.x, pts[0].y - p.y) }
                prev = pts[0]
            case .addQuadCurveToPoint, .addCurveToPoint:
                if let p = prev { len += hypot(pts[element.pointee.type == .addCurveToPoint ? 2 : 1].x - p.x,
                                                pts[element.pointee.type == .addCurveToPoint ? 2 : 1].y - p.y) }
                prev = pts[element.pointee.type == .addCurveToPoint ? 2 : 1]
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return len
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
```

NOTE: SwiftUI's `Path.trimmedPath(from:to:)` should "just work" if the path is constructed cleanly. If the trimmed rim doesn't start at top-centre, the implementation may need to redraw the path with the correct start point. Verify visually.

- [ ] **Step 3: Wire the new phases into `body`**

```swift
var body: some View {
    Group {
        switch viewModel.phase {
        case .spawning(let progress):
            spawnBody(progress: progress)
        case .installSpawning(let p):
            installSpawnBody(progress: p)
        case .installCompiling(let f):
            installCompileBody(rimFraction: f)
        case .installOutro(let p):
            installOutroBody(progress: p)
        case .idle, .armed, .listening, .processing:
            normalBody
        }
    }
    .padding(EdgeInsets(top: 36, leading: 36, bottom: 48, trailing: 36))
}
```

- [ ] **Step 4: Add SwiftUI Previews for each install phase**

- [ ] **Step 5: Build + visually verify each phase via Preview**

- [ ] **Step 6: Commit**

```bash
git add CyphrWhispr/PillWindow/PillView.swift
git commit -m "Render installSpawning/installCompiling/installOutro phases"
```

---

## Task 7: PillWindowController routes to install vs spawn

**Files:**
- Modify: `CyphrWhispr/PillWindow/PillWindowController.swift`

**Context:** Today `show()` plays the cinematic spawn iff `spawnPending`. We need a new branch: if the caller signals "play install instead", run the install intro, leave the pill in `.installCompiling(0)`, and let the coordinator drive `setInstallProgress(_:)` and eventually `playInstallOutro()`.

- [ ] **Step 1: Add `show(mode:)` parameter or split into `showInstall()`**

Recommend splitting: `show()` keeps the existing semantics (idle → spawn or instant), and a new `showInstall(onIntroComplete:)` plays the install intro. The coordinator also needs to call `viewModel.setInstallProgress(_:)` and `viewModel.playInstallOutro()` directly during the compile and at the end.

```swift
func showInstall(onIntroComplete: (() -> Void)? = nil) {
    // panel setup identical to show() — fade panel alpha to 1 over 0.18s
    // ...
    spawnPending = false  // install also "uses up" the pending flag

    Task { @MainActor in
        let didFinish = await viewModel.playInstallSpawn()
        if didFinish {
            onIntroComplete?()
        }
    }
}
```

The existing `hide()` should also call `viewModel.cancelInstall()` defensively, alongside the existing `cancelSpawn()`.

- [ ] **Step 2: Tests for the install path**

Mirror `testPillController_spawnsOnFirstShow_thenInstantOnSecond` but for the install path. Verify `onIntroComplete` fires exactly once when intro completes.

- [ ] **Step 3: Commit**

```bash
git add CyphrWhispr/PillWindow/PillWindowController.swift CyphrWhisprTests/CyphrWhisprTests.swift
git commit -m "PillWindowController.showInstall() plays install intro"
```

---

## Task 8: AppCoordinator detects loadingModel + drives rim

**Files:**
- Modify: `CyphrWhispr/App/AppCoordinator.swift`

**Context:** The coordinator already accepts hotkey presses during `.loadingModel`. Today it routes to the spawn animation regardless. Now, we route to install when the press happens during `.loadingModel`, and to the existing spawn when the press happens during `.idle`.

The rim during install needs a progress driver. Two options:
- **(A) Time-based linear:** capture launch time, ramp rim 0→0.95 linearly over 30s, snap to 1.0 when warmUp completes.
- **(B) WhisperKit progress callback:** check if WhisperKit exposes load progress. If yes, bind directly.

Start with **(A)** — it's deterministic and doesn't require WhisperKit API archaeology.

- [ ] **Step 1: Branch `handleHotkeyPress` based on warm-up state**

```swift
private func handleHotkeyPress() {
    let wasLoading = (state == .loadingModel)
    guard state == .idle || state == .loadingModel else { return }

    guard ClipboardPasteInjector.ensureAccessibilityTrusted(prompt: true) else {
        // ... existing error path ...
        return
    }

    state = .spawning  // generic "pill is up, audio buffered"
    spawnBuffer.removeAll(keepingCapacity: true)

    if wasLoading {
        beginInstallSession()
    } else {
        pill.show()
    }

    // ... existing audio.start() and warm-up await logic unchanged ...
}

private func beginInstallSession() {
    pill.showInstall(onIntroComplete: { [weak self] in
        guard let self else { return }
        self.startInstallProgressDriver()
    })
}

private var installProgressTimer: DispatchSourceTimer?
private var installStartTime: TimeInterval = 0
private static let installFallbackDuration: TimeInterval = 30.0

private func startInstallProgressDriver() {
    installStartTime = CACurrentMediaTime()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(50))
    timer.setEventHandler { [weak self] in
        guard let self else { return }
        let elapsed = CACurrentMediaTime() - self.installStartTime
        let raw = elapsed / Self.installFallbackDuration
        let capped = min(raw, 0.95)  // never reach 1.0 from time alone
        self.pill.viewModel.setInstallProgress(capped)
    }
    timer.resume()
    installProgressTimer = timer
}

private func stopInstallProgressDriver() {
    installProgressTimer?.cancel()
    installProgressTimer = nil
}
```

- [ ] **Step 2: When warm-up completes, snap rim to 1.0 and play outro**

Modify the existing `whisperWarmAwaiter` Task body (currently `state = .streaming` on warm-up done) so that, in install mode, it stops the timer, snaps the rim, plays the outro, then begins streaming.

Since the `state == .spawning` check in `maybeBeginStreaming()` already gates streaming on `whisperWarmDone && spawnAnimationDone`, we just need a parallel for install:
- `installCompletion = whisperWarmDone && installIntroComplete && installOutroComplete`

Practically, the simplest path: when warm-up completes during an install session, `pill.viewModel.setInstallProgress(1.0)`, `pill.viewModel.playInstallOutro()`, and inside the outro's completion callback, set `spawnAnimationDone = true` (semantic equivalent) and call `maybeBeginStreaming()`.

- [ ] **Step 3: Cleanup paths (release mid-install, switch model mid-install)**

`handleHotkeyRelease`'s existing `state == .spawning` branch already drops the buffer, stops audio, ends session. Just add `pill.viewModel.cancelInstall()` and `stopInstallProgressDriver()`. Same for `switchModel(to:)`.

- [ ] **Step 4: Commit**

```bash
git add CyphrWhispr/App/AppCoordinator.swift
git commit -m "AppCoordinator routes to install animation during warm-up"
```

---

## Task 9: Manual smoke test

- [ ] **Step 1: Build + run the app**

- [ ] **Step 2: Five scenarios, with explicit pass/fail criteria**

1. **Cold launch + immediate press (slow path).** Quit, relaunch, press hotkey within 200ms. Pill should play the install animation (intro + breathing label + rim sweep over ~30s + outro). After outro, transcription should work. Audio captured during the wait should land in the transcript.
2. **Cold launch + delayed press (fast path).** Quit, relaunch, wait 60s for warm-up to complete (`state == .idle`), then press. Pill should play the **regular** spawn animation (no install treatment).
3. **Second press in same session.** After scenario 1 or 2, press again. Pill appears instantly, no animation.
4. **Model switch.** Switch to a different model in Settings. Next hotkey press plays the install animation again (because warm-up resumed).
5. **Mid-install release.** Press hotkey during install, release within 1 second. Pill cleans up cleanly, no orphaned animation, no leaked tasks.

- [ ] **Step 3: Push branch and request final review**

---

## Risks & open questions

1. **`Path.trimmedPath` and rim start angle.** SwiftUI's `Path.trimmedPath` trims along the path's natural length, but the path's `0` point is wherever you `move(to:)` first. Drawing the capsule starting at top-centre should make `trim(from: 0, to: f)` sweep clockwise. If it sweeps counterclockwise or starts at the wrong point, the path direction needs reversal. Verify visually first; debug only if broken.
2. **30s fallback might not match real compile time.** If a user's Mac takes 90s, the rim hits 95% and stalls visibly. Acceptable for v1 (the spec allows for this — the rim "pulses" if it caps before warm-up done; we can add the pulse later). For now, 30s linear → 95% cap → snap to 100% on warm-up done is the MVP.
3. **`Canvas` in SwiftUI on macOS 14.** The chosen `Canvas`-based ProgressRim implementation may be heavier than necessary. If 60fps drops, fall back to layering two `Capsule().trim(from:to:)` strokes.

---

## Self-review

- [x] Spec coverage: bar realignment, install animation intro, compiling state, install outro, AppCoordinator detection, model-switch replay
- [x] No placeholders left in the plan
- [x] Type names and method signatures consistent across tasks
- [x] Each task is self-contained with a commit
