import SwiftUI

/// Settings → Customization. v2 glass redesign — the user-controlled
/// surface for the accent picker. Tweaks here ripple through every
/// accent-using view via `PreferencesStore.accent`.
///
/// Two cards:
///   1. A pill-preview stage that lets the user see the comet rim and
///      waveform retint live as they pick. The preview is a stand-in for
///      the production `PillView` — the real one is wired to
///      AppCoordinator + a phase-driven view model, which would need to
///      be unspooled into something previewable. The visuals match the
///      live pill closely enough for accent-picking purposes.
///   2. An accent-picker card with the six curated presets + a custom
///      hex picker (macOS-only).
struct CustomizationTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Maps the current `prefs.accentHex` back to one of the curated
    /// preset names (case-insensitive). Falls back to "Custom" when the
    /// user has picked a non-preset hex via `HexPicker3`.
    private var accentName: String {
        AccentPreset.presets
            .first { $0.hex.caseInsensitiveCompare(prefs.accentHex) == .orderedSame }?
            .name
            ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "Customization",
                    subtitle: "Tweak the pill's accent and preview the change live above. The whole app — comet rim, focus glows, badges — retints to match."
                )

                Card3 {
                    pillPreviewStage
                }

                Card3(title: "Accent colour", meta: prefs.accentHex.uppercased()) {
                    Row3(label: "Preset",
                         sub: "The pill's comet rim, focus glows, badges, and selection states all read from a single accent token.") {
                        HStack(spacing: 10) {
                            ForEach(AccentPreset.presets) { p in
                                Swatch3(preset: p, accentHex: $prefs.accentHex)
                            }
                        }
                    }
                    #if os(macOS)
                    Row3(label: "Custom",
                         sub: "Pick any hex — the comet gradient and accent-secondary derive automatically.",
                         isLast: true) {
                        HexPicker3(hex: $prefs.accentHex)
                    }
                    #endif
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pill preview

    /// Stage that hosts the pill preview, a radial accent glow behind it,
    /// and a tracked-out caption row underneath.
    private var pillPreviewStage: some View {
        ZStack {
            // Floor + glow
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [prefs.accent.opacity(0.22), .clear],
                        center: .center, startRadius: 0, endRadius: 240
                    )
                )
            Rectangle()
                .fill(
                    LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom)
                )

            VStack(spacing: 18) {
                PillPreview()
                    .frame(width: 170, height: 48)

                HStack(spacing: 8) {
                    Text("THE PILL")
                    dot
                    Text("LISTENING").foregroundColor(prefs.accent)
                    dot
                    Text(accentName.uppercased())
                }
                .font(CWFont.mono(size: CWFont.s10, weight: .medium))
                .tracking(1.6)
                .foregroundColor(.cwFg3)
            }
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var dot: some View {
        Circle().fill(Color.cwFg3).frame(width: 3, height: 3)
    }
}

// MARK: - Pill stand-in (preview only)

/// Stand-in for the production `PillView`. The real one is wired to
/// `PillViewModel` + AppCoordinator + audio-level streaming, which
/// doesn't make sense to spin up just for a settings preview. This
/// preview reads `PreferencesStore.accent` directly so the comet rim
/// retints the moment the user picks a new colour.
private struct PillPreview: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            // Body
            Capsule().fill(Color.black)

            // Comet rim — angular gradient masked to an annulus.
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 4.4)) / 4.4 * 360.0
                Capsule()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear,             location: 0.00),
                                .init(color: .clear,             location: 0.30),
                                .init(color: .white.opacity(0.6),location: 0.50),
                                .init(color: prefs.accent,       location: 0.60),
                                .init(color: prefs.accentSecondary, location: 0.70),
                                .init(color: .clear,             location: 0.90),
                                .init(color: .clear,             location: 1.00),
                            ]),
                            center: .center,
                            angle: .degrees(phase)
                        ),
                        lineWidth: 1.4
                    )
            }

            // Static rim
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)

            // Inner glyphs (down-triangle + filled circle + waveform)
            HStack(spacing: 7) {
                Triangle()
                    .fill(.white)
                    .frame(width: 18, height: 14)
                Circle().fill(.white).frame(width: 14, height: 14)
                HStack(spacing: 3) {
                    ForEach(0..<5) { i in
                        Bar(delay: Double(i) * 0.08, peak: barEnvelope(i))
                    }
                }
                .frame(height: 32)
            }
            .padding(.horizontal, 14)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.50), radius: 16, x: 0, y: 16)
        .shadow(color: .black.opacity(0.20), radius: 3,  x: 0, y: 2)
    }

    private func barEnvelope(_ i: Int) -> CGFloat {
        let env: [CGFloat] = [0.42, 0.66, 0.92, 0.66, 0.42]
        return env[i]
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private struct Bar: View {
    let delay: Double
    let peak: CGFloat
    @State private var t: CGFloat = 0.45

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LinearGradient(colors: [.white, Color(white: 0.86), Color(white: 0.55)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 3, height: 32 * t)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delay)) {
                    t = peak
                }
            }
    }
}
