import SwiftUI
import AppKit

/// Settings → About. v2 glass redesign — centred hero (app icon + name +
/// version + tagline) over a soft accent wash, three info rows (source /
/// license / privacy), then a "Diagnostics" card with three read-only
/// rows.
///
/// The accent picker that used to live here has moved to the Customization
/// tab — accent state still lives on `PreferencesStore` so the move is
/// purely cosmetic.
struct AboutTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(title: "About")

                Card3 {
                    VStack(spacing: 0) {
                        hero
                        Row3(label: "Source",
                             sub: "github.com/KenobiNakamoto/CyphrWhispr") {
                            CWButton(title: "View on GitHub",
                                     variant: .ghost,
                                     indicator: .glyph("↗")) {
                                if let url = URL(string: "https://github.com/KenobiNakamoto/CyphrWhispr") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        Row3(label: "License") {
                            CWToken(text: "MIT", variant: .foss, indicator: .glyph("∗"))
                        }
                        Row3(label: "Privacy", isLast: true) {
                            HStack(spacing: 6) {
                                CWToken(text: "100% local",
                                        variant: .local,
                                        indicator: .glyph("●"))
                                CWToken(text: "encrypted",
                                        variant: .encrypted,
                                        indicator: .glyph("⌗"))
                            }
                        }
                    }
                }

                Card3(title: "Diagnostics", meta: "read-only") {
                    Row3(label: "Whisper.cpp",
                         sub: "ggml backend, Metal accelerated.") {
                        CWToken(text: "v1.7.2 · metal",
                                variant: .info,
                                indicator: .glyph("●"))
                    }
                    Row3(label: "Audio session",
                         sub: "AVAudioEngine input tap @ 16 kHz mono.") {
                        CWToken(text: "ok",
                                variant: .downloaded,
                                indicator: .glyph("●"))
                    }
                    Row3(label: "Accessibility permission",
                         sub: "Required for global hotkey + keystroke synthesis.",
                         isLast: true) {
                        CWToken(text: "granted",
                                variant: .downloaded,
                                indicator: .glyph("✓"))
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero block

    /// Centred hero — 80pt accent-tinted app icon, the wordmark, version
    /// line, and the one-sentence tagline. Sits over a top-down accent
    /// wash so the hero feels lit, with a hairline at the bottom dividing
    /// it from the rows below.
    private var hero: some View {
        VStack(spacing: 0) {
            heroIcon
                .frame(width: 80, height: 80)
                .padding(.bottom, 14)

            Text("CyphrWhispr")
                .font(CWFont.mono(size: CWFont.s26, weight: .semibold))
                .tracking(-0.52)
                .foregroundColor(.cwFg1)

            Text("v\(version) · build \(build)")
                .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                .tracking(1.5)
                .foregroundColor(.cwFg3)
                .textCase(.uppercase)
                .padding(.top, 6)

            Text("A native macOS dictation widget — local, encrypted, and intentionally minimal. Press a key, speak, watch words land at your cursor.")
                .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                .foregroundColor(.cwFg2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 460)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .background(
            LinearGradient(colors: [prefs.accent.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(Rectangle().fill(Color.cwBorder).frame(height: 1),
                 alignment: .bottom)
    }

    /// 80pt rounded app icon with an accent-tinted shadow and 1pt accent
    /// border. Falls back to `NSApp.applicationIconImage` if the bundled
    /// "AppIcon" asset isn't loadable (e.g. running from Xcode previews).
    @ViewBuilder private var heroIcon: some View {
        let image = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage()
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: prefs.accent.opacity(0.30), radius: 12, x: 0, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(prefs.accent.opacity(0.30), lineWidth: 1)
            )
    }
}
