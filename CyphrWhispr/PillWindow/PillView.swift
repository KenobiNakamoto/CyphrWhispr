import SwiftUI
import QuartzCore

/// High-level animation phase the pill is in. Maps loosely from `AppState` —
/// the coordinator pushes state changes into PillViewModel.
enum PillPhase: Equatable, Hashable, Sendable {
    case idle
    /// First-of-session (or post-model-switch) cinematic appearance.
    /// `progress` is the normalised 0…1 timeline driven by `PillViewModel.playSpawn(duration:)`.
    /// `PillView.body` reads `SpawnTimeline.state(at: progress)` to render the staged motion.
    case spawning(progress: Double)
    /// Install intro animation (figure spawn + push + label-in). Driven by
    /// `PillViewModel.playInstallSpawn(duration:)`. Progress is 0…1.
    case installSpawning(progress: Double)
    /// Compile-progress display. The pill is static; only the rim sweeps.
    /// `progress` is the rim's leading-edge fraction 0…1, driven by
    /// `PillViewModel.setInstallProgress(_:)`.
    case installCompiling(progress: Double)
    /// Install outro animation (rim fade + label fade + circle traverse +
    /// bar cascade + comet ignite). Driven by `PillViewModel.playInstallOutro(duration:)`.
    case installOutro(progress: Double)
    case armed
    case listening
    case processing
}

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
            let start = CACurrentMediaTime()
            phase = .spawning(progress: 0)
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
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

    private var spawnTask: Task<Bool, Never>?
    private var installSpawnTask: Task<Bool, Never>?
    private var installOutroTask: Task<Bool, Never>?

    /// Drives the install intro from `progress = 0` to `progress = 1` over
    /// `duration` seconds, then sets `phase = .installCompiling(progress: 0)`.
    /// Polls at ~60Hz. Returns `true` if it ran to completion, `false` if cancelled.
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

    /// Updates the rim sweep progress while in `.installCompiling`. Clamps to [0, 1].
    /// Caller must already be in the `.installCompiling` phase; calling this from
    /// any other phase is a no-op (defensive — avoids accidentally yanking the
    /// pill out of an idle/spawning state).
    func setInstallProgress(_ p: Double) {
        let clamped = min(max(p, 0), 1)
        if case .installCompiling = phase {
            phase = .installCompiling(progress: clamped)
        }
    }

    /// Drives the install outro from `progress = 0` to `progress = 1` over
    /// `duration` seconds, then sets `phase = .armed`. Returns `true` on
    /// completion, `false` if cancelled.
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

    /// Cancels both install intro and outro in-flight tasks. Phase is left at
    /// whatever value the latest tick published; caller decides next phase.
    func cancelInstall() {
        installSpawnTask?.cancel(); installSpawnTask = nil
        installOutroTask?.cancel(); installOutroTask = nil
    }
}

/// The black pill that floats at the bottom of the screen.
///
/// Design choices (per the latest user direction):
///   • Body is **fully solid black** — no gradient, no inset glass effect.
///   • All visual interest is in the **rim**: a static hairline + an animated
///     conic-gradient "comet" that orbits the capsule + an outer blurred halo
///     that gives the rim a high-quality glow without bleeding through the body.
///   • Content (triangle, circle, waveform) is positioned absolutely inside
///     a leading-anchored ZStack so bar X positions are pixel-deterministic
///     and align with the design spec's geometry. Vertical centring is done
///     per-element via `(pillHeight - elementHeight) / 2`.
struct PillView: View {
    @ObservedObject var viewModel: PillViewModel
    /// Owns the user's chosen accent — fed into the comet gradient below so
    /// the rim halo retints the moment the user picks a new color in
    /// Settings → About → Accent. Passed in explicitly (rather than via
    /// EnvironmentObject) because the pill window is hosted outside the
    /// Settings scene's environment.
    @ObservedObject var prefs: PreferencesStore = .shared

    // Visible pill geometry — half of the previous spec size.
    private static let pillWidth: CGFloat = 170
    private static let pillHeight: CGFloat = 48

    // Idle-pill bar group geometry (from the high-fidelity mockup).
    // First bar's left edge sits at x=90; 7 bars × 3pt + 6 gaps × 4pt = 45pt total.
    private static let waveformX: CGFloat = 90
    private static let waveformWidth: CGFloat = 45  // 7×3 + 6×4

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
        ZStack(alignment: .leading) {
            // Capsule body — pure black with the existing two-shadow stack.
            shape
                .fill(Color.black)
                .frame(width: Self.pillWidth, height: Self.pillHeight)
                .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 8)
                .shadow(color: .black.opacity(0.20), radius: 3, x: 0, y: 1)

            // Triangle — left edge at x=22, vertically centred.
            DownTriangle()
                .fill(Color.white)
                .overlay(
                    DownTriangle()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 18, height: 16)
                .offset(x: 22, y: (Self.pillHeight - 16) / 2)

            // Circle — left edge at x=47, vertically centred. Preserves the
            // .listening level-bump scale effect from the previous layout.
            Circle()
                .fill(Color.white)
                .frame(width: 17, height: 17)
                .scaleEffect(viewModel.phase == .listening
                             ? 1.0 + CGFloat(min(viewModel.level, 1)) * 0.10
                             : 1.0)
                .animation(.easeOut(duration: 0.12), value: viewModel.level)
                .offset(x: 47, y: (Self.pillHeight - 17) / 2)

            // Waveform — first bar's left edge at x=90, group is exactly 45pt
            // wide (7 bars × 3pt + 6 gaps × 4pt). Pinning the frame to that
            // width makes the bar X positions pixel-deterministic instead of
            // depending on HStack flow.
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

    /// Renders the pill mid-spawn: figures positioned by absolute offsets
    /// inside a width-animated capsule, bars individually positioned (so
    /// their reveal cascade is independent of the HStack flow), and the
    /// comet rim faded in via the rimOpacity multiplier.
    @ViewBuilder
    private func spawnBody(progress: Double) -> some View {
        let s = SpawnTimeline.state(at: progress)
        let shape = Capsule(style: .continuous)

        ZStack(alignment: .leading) {
            // Capsule body — pure black, animated width. Shadows attached HERE
            // (not on the outer ZStack frame) so they track the visible capsule
            // size during seed/anticipation phases instead of leaking ahead at
            // the full 170pt outer frame.
            shape
                .fill(Color.black)
                .frame(width: s.pillWidth, height: Self.pillHeight)
                .shadow(color: .black.opacity(0.50 * s.figureOpacity), radius: 16, x: 0, y: 8)
                .shadow(color: .black.opacity(0.20 * s.figureOpacity), radius: 3, x: 0, y: 1)

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

            // Bars — seven individual capsules at the pixel-exact columns
            // used by the idle waveform. Matching the idle geometry here
            // means the spawn end-frame is pixel-identical to the idle
            // frame, so there is no reflow when the view flips to
            // `normalBody`. Plain white during reveal — the silver gradient
            // takes over once the pill transitions to `.armed`.
            ForEach(0..<7, id: \.self) { i in
                let barHeight = SpawnTimeline.barHeights[i]
                Capsule()
                    .fill(Color.white)
                    .frame(width: SpawnTimeline.barWidth, height: barHeight)
                    .opacity(s.barOpacities[i])
                    .offset(x: SpawnTimeline.barColumns[i],
                            y: (Self.pillHeight - barHeight) / 2)
            }
        }
        .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
        // Rim halo only after ignite — opacity ramps 0 → 1 in the ignite phase
        .overlay(
            RimHighlights(visible: true,
                          animating: true,
                          intensity: 0.85,
                          level: 0.0,
                          accent: prefs.accent,
                          accentSecondary: prefs.accentSecondary)
                .opacity(s.rimOpacity)
        )
    }
}

// MARK: - Rim highlights

/// All the rim treatment in one view, layered back-to-front:
///   1. **Outer halo**: a blurred stroke of the moving conic gradient. Sits
///      outside the capsule edge thanks to the blur — this is the "high-quality
///      glow" without colouring the body.
///   2. **Static rim**: subtle 1pt white border so the pill always has a
///      defined edge, even between comet sweeps.
///   3. **Comet highlight**: the bright conic-gradient sliver that orbits.
private struct RimHighlights: View {
    /// Whether the rim is visible at all. When false, the whole component
    /// renders nothing — used for the `.idle` state and during the early
    /// (pre-ignite) phases of the spawn animation. Visibility transitions
    /// fade gently via the .opacity animation.
    let visible: Bool
    /// Whether the comet animation should keep ticking. Pause it during
    /// `.idle` to save CPU; keep it running during all active phases AND
    /// during the spawn animation (the comet should already be orbiting
    /// when the rim fades in at ignite).
    let animating: Bool
    /// Brightness multiplier for the halo glow. ~0.65 for armed/processing,
    /// 0.95 for listening, 0.85 for the spawn ignite to feel "alive."
    let intensity: Double
    /// Audio level — adds a subtle bump to the halo when speaking.
    let level: Float
    /// User-chosen accent — drives the bright core of the comet sweep.
    let accent: Color
    /// Cooler counterpart (hue-shifted accent) — drives the trailing fade.
    let accentSecondary: Color

    /// One fixed loop duration regardless of phase. The earlier per-phase
    /// speed change caused the comet's angle to JUMP at the moment phase
    /// changed because the angle is `t / loopDuration` and we suddenly
    /// divided by a different number. Single constant keeps the orbit
    /// continuous; we react to phase via `intensity` and `visible` instead.
    private static let loopDuration: Double = 4.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t / Self.loopDuration * 360).truncatingRemainder(dividingBy: 360)
            let levelBump = 0.30 * Double(min(max(level, 0), 1))

            ZStack {
                // 1. Outer halo (blurred stroke of the comet — bleeds beyond the rim)
                Capsule(style: .continuous)
                    .stroke(cometGradient(angle: angle), lineWidth: 4)
                    .blur(radius: 5)
                    .opacity(0.55 * (intensity + levelBump))

                // 2. Static rim — 1pt subtle white edge always present while active
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)

                // 3. Comet highlight — crisp neon sliver that orbits the rim
                Capsule(style: .continuous)
                    .strokeBorder(cometGradient(angle: angle), lineWidth: 1.4)
            }
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: visible)
        }
    }

    /// The conic gradient: a band of icy white + the user's accent + the
    /// hue-shifted secondary, with very gentle alpha falloff on both ends so
    /// the leading and trailing edges feather into transparency instead of
    /// cutting off. Result: a soft "comet of light" rather than a hard moving
    /// stripe — and one that retints whenever the user picks a new accent.
    private func cometGradient(angle: Double) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .clear,                          location: 0.00),
                .init(color: .clear,                          location: 0.30),
                // Long, soft leading edge: clear → white over ~25% of perimeter
                .init(color: .white.opacity(0.05),            location: 0.36),
                .init(color: .white.opacity(0.18),            location: 0.44),
                .init(color: .white.opacity(0.45),            location: 0.52),
                .init(color: .white.opacity(0.78),            location: 0.58),
                // Core of the comet: white → accent → secondary
                .init(color: accent.opacity(0.85),            location: 0.66),
                .init(color: accentSecondary.opacity(0.65),   location: 0.72),
                // Long, soft trailing edge: secondary → clear over ~22%
                .init(color: accentSecondary.opacity(0.30),   location: 0.78),
                .init(color: accentSecondary.opacity(0.12),   location: 0.85),
                .init(color: .clear,                          location: 0.92),
                .init(color: .clear,                          location: 1.00),
            ]),
            center: .center,
            angle: .degrees(angle)
        )
    }
}

// MARK: - Down triangle shape

private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    let vm = PillViewModel()
    vm.phase = .listening
    vm.level = 0.55
    return PillView(viewModel: vm)
        .frame(width: 260, height: 120)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
}

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
