import Foundation
import CoreGraphics

/// Fully-resolved visual state for the pill at a single point in the install
/// **intro** animation. Pure data — no SwiftUI types — so it stays
/// unit-testable.
///
/// All position/size values are in **production-scale points** (170 × 48 pill).
struct InstallIntroState: Equatable {
    /// Opacity of triangle + circle (both rise together during spawn phase).
    var figureOpacity: Double
    /// Scale applied to triangle + circle. Goes 0.5 → 1 during spawn,
    /// dips to 0.97 during anticipation, returns to 1 during push.
    var figureScale: Double
    /// Capsule width in points. Production: 63 (seed) → 60 (anticipation) → 170 (full).
    var pillWidth: CGFloat
    /// Triangle's left position relative to the pill's left edge.
    /// Pinned at `triPinnedX` (12) throughout the intro.
    var triangleX: CGFloat
    /// Circle's left position relative to the pill's left edge.
    /// Right-pinned: `pillWidth - 29` throughout the intro.
    var dotX: CGFloat
    /// "Installing model" label opacity. 0 during phases 1-3, fades in during hold.
    var labelOpacity: Double
    /// Vertical offset for the label. 4pt below at start of hold, 0 at end.
    var labelOffsetY: CGFloat
}

/// Fully-resolved visual state for the pill at a single point in the install
/// **outro** animation.
struct InstallOutroState: Equatable {
    /// Triangle's left position relative to the pill's left edge.
    /// Slides 12 → 22 over the circle-traverse window.
    var triangleX: CGFloat
    /// Circle's left position relative to the pill's left edge.
    /// Slides 141 → 47 over the circle-traverse window.
    var dotX: CGFloat
    /// Compile-pulse rim opacity. 1 → 0 over the rim-fade window.
    var rimOpacity: Double
    /// "Installing model" label opacity. 1 → 0 over the label-fade window.
    var labelOpacity: Double
    /// Vertical offset for the label. 0 → 4 over the label-fade window.
    var labelOffsetY: CGFloat
    /// Seven waveform-bar opacities in left-to-right order.
    /// Right-to-left cascade: rightmost (index 6) appears first.
    var barOpacities: [Double]
    /// Per-bar vertical offsets matching the cascade timing. 3pt below → 0pt.
    var barOffsetsY: [CGFloat]
    /// Comet ignite opacity. 0 → 1 starting at the comet-ignite point.
    var cometOpacity: Double
    /// Comet brightness multiplier. Default 1.0; gaussian flash to ~1.6 mid-ignite.
    var cometBrightness: Double
    /// Steady-state rim opacity (the idle pill's comet rim). 0 → 1 starting at ignite.
    var staticRimOpacity: Double
}

/// Pure timeline math for the install animation. Two normalized timelines —
/// one for the intro, one for the outro — each mapping `t ∈ [0, 1]` to a
/// fully-resolved state struct.
///
/// Mirrors the `SpawnTimeline` style: all geometry is in production-scale
/// points (170 × 48 pill), helpers are file-private, and the API is a single
/// `state(at:)`-style entry point per timeline.
///
/// ## Intro phases (production duration 2.0s)
/// - **Spawn**         0.000 → 0.300  figures fade in + scale up at seed pill
/// - **Anticipation**  0.300 → 0.425  pill compresses to 60pt, scale 0.97
/// - **Push**          0.425 → 0.850  pill expands to 170pt, figures at extremes
/// - **Hold + label**  0.850 → 1.000  label fades in from 4pt below
///
/// ## Outro phases (production duration 1.3s)
/// - **Label fade**    0.000 → 0.308  label fades out, drops 4pt
/// - **Rim fade**      0.000 → 0.462  compile-pulse rim fades out
/// - **Bar cascade**   0.115 → ~0.77  right-to-left bar reveal (120ms stagger)
/// - **Circle slide**  0.000 → 0.769  circle 141 → 47, triangle 12 → 22
/// - **Comet ignite**  0.654 → 1.000  comet rim ignites; steady-state rim fades in
enum InstallTimeline {

    // MARK: - Intro phase boundaries (normalized)

    static let pSpawnEnd:        Double = 0.300
    static let pAnticipationEnd: Double = 0.425
    static let pPushEnd:         Double = 0.850

    // MARK: - Outro phase boundaries (normalized)

    static let pCircleTraverseEnd: Double = 0.769  // 1.0s of 1.3s
    static let pRimFadeEnd:        Double = 0.462  // 0.6s of 1.3s
    static let pLabelFadeEnd:      Double = 0.308  // 0.4s of 1.3s
    static let pCometIgniteStart:  Double = 0.654  // ~0.85s of 1.3s

    /// Bar cascade window (right-to-left). Rightmost bar starts at
    /// `barCascadeStartT`; each subsequent bar starts `barCascadeStaggerT`
    /// later; each bar fades over `barCascadeFadeT`.
    static let barCascadeStartT:   Double = 0.115  // 150ms / 1300ms
    static let barCascadeStaggerT: Double = 0.092  // 120ms / 1300ms
    static let barCascadeFadeT:    Double = 0.169  // 220ms / 1300ms

    // MARK: - Geometry constants (production scale)

    static let pillSeedW: CGFloat = 63
    static let pillAntiW: CGFloat = 60
    static let pillFullW: CGFloat = 170

    /// Triangle's pinned X during the install (12pt left padding).
    static let triPinnedX: CGFloat = 12
    /// Triangle's idle X (matches the post-spawn idle layout).
    static let triIdleX:   CGFloat = 22

    /// Circle's X at the end of the intro push: `pillFullW - 29 = 141`.
    /// (29 = 12pt right padding + 17pt circle width.)
    static let dotPushEndX: CGFloat = 141
    /// Circle's idle X (matches `SpawnTimeline.dotTraverseEndX`).
    static let dotIdleX:    CGFloat = 47

    // MARK: - Bar geometry (idle / end-of-outro frame)

    /// Seven bar columns at the same pixel-exact positions as the idle pill
    /// and `SpawnTimeline.barColumns`. Cross-checked in tests.
    static let barIdleColumns: [CGFloat] = [90, 97, 104, 111, 118, 125, 132]

    /// Per-bar resting heights. Matches `SpawnTimeline.barHeights`.
    static let barIdleHeights: [CGFloat] = [7, 12, 15, 24, 15, 12, 7]

    /// Width of each bar. Matches the idle waveform.
    static let barWidth: CGFloat = 3

    // MARK: - Public API: Intro

    /// Resolve the install-intro visual state at the given normalized progress.
    /// `t` is clamped to `[0, 1]` so out-of-range callers degrade gracefully.
    static func introState(at t: Double) -> InstallIntroState {
        let t = clamp(t, 0, 1)

        let figureOpacity: Double
        let figureScale: Double
        let pillWidth: CGFloat
        let dotX: CGFloat

        if t < pSpawnEnd {
            let p = t / pSpawnEnd
            figureOpacity = easeInOut(p)
            figureScale = lerp(0.5, 1.0, easeInOut(p))
            pillWidth = pillSeedW
            dotX = pillSeedW - 29
        } else if t < pAnticipationEnd {
            let p = (t - pSpawnEnd) / (pAnticipationEnd - pSpawnEnd)
            figureOpacity = 1.0
            figureScale = lerp(1.0, 0.97, easeInOut(p))
            pillWidth = lerpCG(pillSeedW, pillAntiW, easeInOut(p))
            dotX = pillWidth - 29
        } else if t < pPushEnd {
            let p = (t - pAnticipationEnd) / (pPushEnd - pAnticipationEnd)
            // Mimic CSS cubic-bezier(0.16, 0.84, 0.30, 1) — a fast-out cubic.
            let eased = easeOutCubic(p)
            figureOpacity = 1.0
            figureScale = lerp(0.97, 1.0, eased)
            pillWidth = lerpCG(pillAntiW, pillFullW, eased)
            dotX = pillWidth - 29
        } else {
            figureOpacity = 1.0
            figureScale = 1.0
            pillWidth = pillFullW
            dotX = pillFullW - 29
        }

        let labelOpacity: Double
        let labelOffsetY: CGFloat
        if t < pPushEnd {
            labelOpacity = 0
            labelOffsetY = 4
        } else {
            let p = (t - pPushEnd) / (1.0 - pPushEnd)
            labelOpacity = easeInOut(p)
            labelOffsetY = lerpCG(4, 0, easeInOut(p))
        }

        return InstallIntroState(
            figureOpacity: figureOpacity,
            figureScale: figureScale,
            pillWidth: pillWidth,
            triangleX: triPinnedX,
            dotX: dotX,
            labelOpacity: labelOpacity,
            labelOffsetY: labelOffsetY
        )
    }

    // MARK: - Public API: Outro

    /// Resolve the install-outro visual state at the given normalized progress.
    /// `t` is clamped to `[0, 1]` so out-of-range callers degrade gracefully.
    static func outroState(at t: Double) -> InstallOutroState {
        let t = clamp(t, 0, 1)

        // Triangle slides 12 → 22 over the circle-traverse window.
        // Circle slides 141 → 47 over the same window.
        let triangleX: CGFloat
        let dotX: CGFloat
        if t < pCircleTraverseEnd {
            let p = t / pCircleTraverseEnd
            let eased = easeOutCubic(p)
            triangleX = lerpCG(triPinnedX, triIdleX, eased)
            dotX = lerpCG(dotPushEndX, dotIdleX, eased)
        } else {
            triangleX = triIdleX
            dotX = dotIdleX
        }

        // Compile-pulse rim fade-out.
        let rimOpacity: Double = (t < pRimFadeEnd)
            ? 1.0 - easeInOut(t / pRimFadeEnd)
            : 0

        // Label fade-out + 4pt drop.
        let labelOpacity: Double
        let labelOffsetY: CGFloat
        if t < pLabelFadeEnd {
            let p = t / pLabelFadeEnd
            labelOpacity = 1.0 - easeInOut(p)
            labelOffsetY = lerpCG(0, 4, easeInOut(p))
        } else {
            labelOpacity = 0
            labelOffsetY = 4
        }

        // Bars: right-to-left cascade across 7 stops.
        var barOpacities = [Double](repeating: 0, count: 7)
        var barOffsetsY = [CGFloat](repeating: 3, count: 7)
        for i in 0..<7 {
            let reverseIndex = Double(6 - i)  // 6, 5, 4, …, 0 — rightmost first
            let startT = barCascadeStartT + reverseIndex * barCascadeStaggerT
            let progress = clamp((t - startT) / barCascadeFadeT, 0, 1)
            let eased = easeOutQuint(progress)
            barOpacities[i] = eased
            barOffsetsY[i] = lerpCG(3, 0, eased)
        }

        // Comet ignite + steady-state rim crossfade.
        let cometOpacity: Double
        let cometBrightness: Double
        let staticRimOpacity: Double
        if t < pCometIgniteStart {
            cometOpacity = 0
            cometBrightness = 1.0
            staticRimOpacity = 0
        } else {
            let p = (t - pCometIgniteStart) / (1.0 - pCometIgniteStart)
            // Fast fade-in, clamped at 1.
            cometOpacity = min(easeOut(p * 2.5), 1.0)
            // Gaussian flash peaking at p ≈ 0.4 (1.0 → ~1.6 → 1.0).
            cometBrightness = 1.0 + 0.6 * exp(-pow((p - 0.4) * 6, 2))
            staticRimOpacity = easeInOut(p)
        }

        return InstallOutroState(
            triangleX: triangleX,
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

    // MARK: - Easings + utilities (mirrors SpawnTimeline)

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// CGFloat-typed `lerp` for geometry interpolation.
    private static func lerpCG(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        CGFloat(lerp(Double(a), Double(b), t))
    }

    private static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - clamp(t, 0, 1), 2)
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - clamp(t, 0, 1), 3)
    }

    private static func easeOutQuint(_ t: Double) -> Double {
        1 - pow(1 - clamp(t, 0, 1), 5)
    }

    private static func easeInOut(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}
