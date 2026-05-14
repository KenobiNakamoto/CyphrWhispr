import SwiftUI

/// Settings → Customization. v2 glass redesign — the user-controlled
/// surface for the accent picker. Tweaks here ripple through every
/// accent-using view via `PreferencesStore.accent`.
///
/// Two cards:
///   1. A pill-preview stage hosting the **real** production `PillView`
///      driven by a local `PillViewModel` pinned to `.listening`. That
///      means visual changes to the pill (rim, waveform, glyph layout,
///      shadows) only need to happen in `PillView.swift` — they
///      automatically show up here too. The viewmodel reads
///      `PreferencesStore.shared` (same singleton injected as the
///      Settings environment object), so picking a new accent retints
///      the comet rim in real time.
///   2. An accent-picker card with the six curated presets + a custom
///      hex picker (macOS-only).
struct CustomizationTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Production pill viewmodel held by the customization preview.
    /// `@StateObject` so it survives view re-evaluations during accent
    /// changes (without this the comet rim's TimelineView phase would
    /// reset on every preference write). Pinned to `.listening` with a
    /// static-ish level so the waveform reads as alive — WaveformView's
    /// `.listening` branch drives per-bar jitter from `TimelineView`
    /// regardless of the level value, so the bars twitch even without
    /// real audio input.
    @StateObject private var previewPill = PillViewModel()

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
                // Production pill — same code path as the live menu-bar
                // pill, just driven by a local viewmodel. PillView applies
                // its own 36/36/48/36 padding for shadow bleed; the stage
                // is already minHeight=200 so it fits comfortably.
                PillView(viewModel: previewPill)
                    .onAppear {
                        previewPill.phase = .listening
                        previewPill.level = 0.55
                    }

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

// The pill preview is rendered by the production `PillView`
// (CyphrWhispr/PillWindow/PillView.swift) — no separate stand-in lives
// here any more. Visual changes only need to happen in `PillView` and
// they automatically propagate to this preview.
