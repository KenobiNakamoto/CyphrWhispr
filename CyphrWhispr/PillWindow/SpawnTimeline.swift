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

    // MARK: - Bar geometry (public — read by PillView's spawnBody)

    /// Five evenly-spaced waveform bar columns, in points relative to the
    /// pill's left edge. Production scale (170pt-wide pill).
    static let barColumns: [CGFloat] = [70, 92, 113, 135, 156]

    /// Width of each bar (pt).
    static let barWidth: CGFloat = 2

    /// Height of the centre (3rd) bar at rest. Tallest of the five.
    static let barCentreHeight: CGFloat = 14

    /// Height of the four non-centre bars at rest.
    static let barShortHeight: CGFloat = 6

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
