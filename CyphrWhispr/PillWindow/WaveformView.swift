import SwiftUI

/// 7-bar waveform whose behaviour switches based on the pill's phase:
/// - `.armed`: bars gently breathe between 0.88× and 1.08× their resting height
/// - `.listening`: bars react to live audio RMS (clamped, smoothed)
/// - `.processing`: bars play a left-to-right travelling wave
/// - `.idle`: bars sit at resting height
///
/// Resting heights match the spec exactly (28, 48, 58, 96, 58, 48, 28 px at 2x
/// — i.e. 14, 24, 29, 48, 29, 24, 14 pt at 1x).
struct WaveformView: View {
    var level: Float
    var phase: PillPhase

    /// Bar heights at rest. Half of the spec's mid-pill scale to match the
    /// half-sized 170×48 pill the user asked for.
    private static let restingHeights: [CGFloat] = [7, 12, 15, 24, 15, 12, 7]
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 4

    var body: some View {
        // Bumped from 30Hz → 60Hz so the per-bar erratic motion in `.listening`
        // actually reads as twitchy frequency-response rather than a slow wobble.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: phase == .idle)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            // Pure bars on solid black — no bloom behind them. All highlight
            // work happens on the rim per the user's direction.
            HStack(alignment: .center, spacing: Self.spacing) {
                ForEach(0..<Self.restingHeights.count, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(barGradient)
                        .frame(width: Self.barWidth,
                               height: animatedHeight(at: i, time: t))
                }
            }
        }
    }

    /// White-to-silver vertical gradient (spec: top #FFF, mid #DADAE2, bot #898A94).
    private var barGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white,                                              location: 0.0),
                .init(color: Color(red: 0.855, green: 0.855, blue: 0.886),        location: 0.5),
                .init(color: Color(red: 0.537, green: 0.541, blue: 0.580),        location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Hard ceiling so even the loudest spike can't overflow the pill.
    /// Pill is 48pt tall; we leave a tiny margin so capsule bars don't touch
    /// the rim at peak.
    private static let maxBarHeight: CGFloat = 38

    /// Compute current bar height based on phase + time.
    private func animatedHeight(at index: Int, time: TimeInterval) -> CGFloat {
        let resting = Self.restingHeights[index]
        let raw = rawHeight(at: index, time: time, resting: resting)
        return min(raw, Self.maxBarHeight)
    }

    private func rawHeight(at index: Int, time: TimeInterval, resting: CGFloat) -> CGFloat {

        switch phase {
        case .idle:
            return resting

        case .armed:
            // Gentle breathing: scaleY ∈ [0.88, 1.08], 1.4s cycle, 80ms stagger.
            let phaseOffset = Double(index) * 0.080
            let phaseT = (time + phaseOffset) * (.pi / 0.7) // ω so period = 1.4s
            let s = (sin(phaseT) + 1) / 2 // 0..1
            let scale = 0.88 + 0.20 * s   // 0.88..1.08
            return resting * CGFloat(scale)

        case .listening:
            // Goal: looks like a real frequency-response meter — vertical jumps
            // when the user speaks, with each bar twitching independently as if
            // it were tuned to a different band. Achieved by combining:
            //   1. A boosted level envelope (0.30 floor, ~2.4 ceiling) with a
            //      slight curve so quiet speech still moves bars but loud speech
            //      really spikes them.
            //   2. Per-bar pseudo-random jitter built from three offset sines at
            //      different frequencies — gives "erratic" motion that isn't
            //      synchronised across bars and doesn't loop visibly.
            //   3. A bell-shaped weight that gives the centre bars the biggest
            //      swing (mirroring a real spectrum where the mid-range bins
            //      dominate normal speech), so the centre punches more than the
            //      edges instead of all bars marching in lockstep.
            let lvl = CGFloat(min(max(level, 0), 1))
            // Curve: lvl^0.7 — boosts quiet input, keeps loud input near 1.
            let curved = pow(lvl, 0.7)
            let envelope = 0.30 + curved * (2.40 - 0.30)

            // Per-bar erratic jitter. Three incommensurable frequencies prevent
            // a visible repeating pattern.
            let i = Double(index)
            let j1 = sin((time + i * 0.31) * 11.0)
            let j2 = sin((time + i * 0.73) * 17.0)
            let j3 = sin((time + i * 1.19) *  5.0)
            // Combine then map to 0..1. Sum range = -3..3, so /6 + 0.5 → 0..1.
            let jitter = CGFloat((j1 + j2 + j3) / 6.0 + 0.5)

            // Centre bars get more swing; edges stay more contained.
            let centreDist = abs(i - Double(Self.restingHeights.count - 1) / 2.0)
            let centreWeight = CGFloat(1.0 - (centreDist / 4.0)) // ~1.0 at centre, ~0.25 at edges

            // Active jitter share scales with level — quiet = mostly steady,
            // loud = bars genuinely flailing around the envelope.
            let jitterShare: CGFloat = 0.20 + 0.70 * curved
            let scale = envelope * ((1 - jitterShare) + jitterShare * jitter * centreWeight * 1.4)
            return resting * max(0.25, scale)

        case .processing:
            // Travelling wave left → right. 900ms loop. Each bar reaches its
            // peak in sequence so it reads as a "thinking" pulse moving across.
            let loop: Double = 0.9
            let phaseT = (time.truncatingRemainder(dividingBy: loop)) / loop // 0..1
            let barCentre = Double(index) / Double(Self.restingHeights.count - 1) // 0..1
            // Distance from this bar's centre to the wave's current position.
            let dist = min(abs(phaseT - barCentre), 1 - abs(phaseT - barCentre))
            let bell = exp(-pow(dist * 4, 2)) // gaussian, narrow band
            let scale = 0.85 + 0.45 * bell    // 0.85..1.30
            return resting * CGFloat(scale)
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach([PillPhase.armed, .listening, .processing], id: \.self) { p in
            VStack {
                Text(String(describing: p)).font(.caption).foregroundStyle(.white)
                WaveformView(level: 0.6, phase: p)
                    .frame(width: 90, height: 70)
            }
        }
    }
    .padding(20)
    .background(Color.black)
}
