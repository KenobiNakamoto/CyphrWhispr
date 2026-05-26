import SwiftUI
import AppKit

/// First-run welcome window content. Single-page checklist showing the four
/// items a new user benefits from setting up — microphone + accessibility
/// permissions, the recommended Whisper model, and the dictation hotkey.
///
/// Layout fits the fixed 520×640 window without needing to scroll on a normal
/// install; a `ScrollView` is in place so the page tolerates display scaling
/// without clipping. Backdrop ignores the safe area to reach under the
/// transparent title bar — same trick `SettingsView` uses — while the
/// content respects the native 28pt safe-area inset so nothing scrolls into
/// the traffic-light zone.
///
/// All four rows are live: the permission rows reflect the OS state via a
/// 1Hz `PermissionsProbe`, the model row checks `AppSupportPaths` on appear
/// and again after a download is kicked off, and the hotkey row links into
/// Settings → Shortcut.
struct OnboardingView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @StateObject private var permissions = PermissionsProbe()
    @StateObject private var inventory = ModelInventory()

    /// True while a "Download recommended model" action is in flight. Set by
    /// `downloadRecommended()`; cleared when the model lands on disk or the
    /// 5-minute poll timeout fires.
    @State private var isDownloadingRecommended = false

    /// Hardware profile is fixed per launch; capture once.
    private let profile = HardwareProfiler.profile()

    private var recommendedModel: WhisperModel {
        ModelRecommender.recommend(for: profile)
    }

    private var recommendedDownloaded: Bool {
        AppSupportPaths.isModelDownloaded(recommendedModel.id)
    }

    /// At least one model is on disk somewhere (recommended, custom, or the
    /// bundled `small.en` fallback). The bundled model means the app works
    /// out of the box; the recommended one is an upgrade.
    private var anyModelDownloaded: Bool {
        inventory.rows.contains { $0.isDownloaded }
    }

    /// Mic + Accessibility are the only true blockers for dictation; the
    /// bundled model means transcription works without an explicit download.
    private var readyToDictate: Bool {
        permissions.bothGranted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Card3(title: "Setup",
                      meta: readyToDictate ? "ready" : "in progress") {
                    microphoneRow
                    accessibilityRow
                    modelRow
                    hotkeyRow
                }

                if readyToDictate {
                    readyBanner
                }

                Spacer(minLength: 20)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { backdrop }
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.start()
            inventory.refresh()
        }
        .onDisappear { permissions.stop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to CyphrWhispr")
                .font(CWFont.mono(size: CWFont.s22, weight: .semibold))
                .foregroundColor(.cwFg1)
            Text("Privacy-first, on-device dictation. A few things to set up, then "
                + "press your hotkey and watch words land at your cursor.")
                .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 18)
    }

    // MARK: - Rows

    private var microphoneRow: some View {
        Row3(label: "Microphone access",
             sub: microphoneSub) {
            switch permissions.microphone {
            case .granted:
                CWToken(text: "granted",
                        variant: .downloaded,
                        indicator: .glyph("✓"))
            case .notDetermined:
                CWButton(title: "Request access", variant: .primary) {
                    permissions.requestMicrophone()
                }
            case .denied:
                CWButton(title: "Open Settings",
                         variant: .ghost,
                         indicator: .glyph("↗")) {
                    permissions.openMicrophoneSystemSettings()
                }
            }
        }
    }

    private var microphoneSub: String {
        switch permissions.microphone {
        case .granted:
            return "We can capture audio while you hold the hotkey."
        case .notDetermined:
            return "Required to hear what you say during dictation."
        case .denied:
            return "Re-enable Microphone for CyphrWhispr in System Settings → "
                + "Privacy & Security → Microphone."
        }
    }

    private var accessibilityRow: some View {
        Row3(label: "Accessibility access",
             sub: accessibilitySub) {
            switch permissions.accessibility {
            case .granted:
                CWToken(text: "granted",
                        variant: .downloaded,
                        indicator: .glyph("✓"))
            case .missing:
                CWButton(title: "Open Settings",
                         variant: .primary,
                         indicator: .glyph("↗")) {
                    permissions.openAccessibilitySystemSettings()
                }
            }
        }
    }

    private var accessibilitySub: String {
        switch permissions.accessibility {
        case .granted:
            return "We can paste the transcript at your cursor in any app."
        case .missing:
            return "Required so CyphrWhispr can synthesise ⌘V and drop text "
                + "where you're typing. Tick the CyphrWhispr checkbox in "
                + "Privacy & Security → Accessibility."
        }
    }

    private var modelRow: some View {
        Row3(label: "Whisper model",
             sub: modelSub) {
            if isDownloadingRecommended {
                CWToken(text: "downloading", variant: .info, indicator: .block)
            } else if recommendedDownloaded {
                CWToken(text: "ready",
                        variant: .downloaded,
                        indicator: .glyph("✓"))
            } else {
                CWButton(title: "Download",
                         variant: anyModelDownloaded ? .ghost : .primary,
                         indicator: .glyph("↓")) {
                    downloadRecommended()
                }
            }
        }
    }

    private var modelSub: String {
        let sizeStr = ByteCountFormatter.string(
            fromByteCount: Int64(recommendedModel.approxSizeMB) * 1_048_576,
            countStyle: .file
        )
        if isDownloadingRecommended {
            return "Fetching \(recommendedModel.displayName) (\(sizeStr)) — this "
                + "can take a minute on a fresh install."
        }
        if recommendedDownloaded {
            return "\(recommendedModel.displayName) — picked for your Mac (\(profile.displayName), "
                + "\(profile.ramGB) GB)."
        }
        if anyModelDownloaded {
            return "You're running on the bundled fallback. Optional upgrade: "
                + "\(recommendedModel.displayName) (\(sizeStr))."
        }
        return "Recommended for your Mac: \(recommendedModel.displayName) (\(sizeStr))."
    }

    private var hotkeyRow: some View {
        Row3(label: "Hotkey",
             sub: "Default: ⌥Space. Change it any time in Settings → Shortcut.",
             isLast: true) {
            CWButton(title: "Configure",
                     variant: .ghost,
                     indicator: .glyph("›")) {
                openShortcutTab()
            }
        }
    }

    // MARK: - Ready banner + footer

    private var readyBanner: some View {
        HStack(spacing: 10) {
            Text("✓")
                .font(CWFont.mono(size: CWFont.s17, weight: .semibold))
                .foregroundColor(.cwSuccess)
            Text("You're set. Press ⌥Space anywhere on your Mac to dictate.")
                .font(CWFont.mono(size: CWFont.s13, weight: .medium))
                .foregroundColor(.cwFg1)
            Spacer()
        }
        .padding(.top, 18)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Closing this window marks onboarding done. Re-open from "
                + "About → Show onboarding again.")
                .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                .foregroundColor(.cwFg3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            CWButton(title: readyToDictate ? "Done" : "Close",
                     variant: readyToDictate ? .primary : .ghost) {
                OnboardingWindowController.shared.close()
            }
        }
        .padding(.top, 14)
    }

    // MARK: - Backdrop

    @ViewBuilder private var backdrop: some View {
        ZStack {
            LinearGradient.cwBackdrop
            Circle().fill(prefs.accent.opacity(0.10))
                .frame(width: 500, height: 500).blur(radius: 120)
                .offset(x: 140, y: -160)
            Circle().fill(Color.cwAccentSecondary.opacity(0.06))
                .frame(width: 400, height: 400).blur(radius: 100)
                .offset(x: -160, y: 200)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - Actions

    /// Activate the recommended model — `AppCoordinator` observes
    /// `activeModelID` and asks WhisperKit to load it, which pulls the bundle
    /// from HuggingFace on a fresh install. Poll the filesystem on a 2s
    /// cadence so the row's badge flips to "ready" the moment the file lands.
    /// Caps at 5 minutes so a stuck download doesn't leave the spinner
    /// running forever.
    private func downloadRecommended() {
        prefs.activeModelID = recommendedModel.id
        isDownloadingRecommended = true
        let targetID = recommendedModel.id
        Task {
            let deadline = Date().addingTimeInterval(300)   // 5 min
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if AppSupportPaths.isModelDownloaded(targetID) {
                    await MainActor.run {
                        inventory.refresh()
                        isDownloadingRecommended = false
                    }
                    return
                }
            }
            await MainActor.run { isDownloadingRecommended = false }
        }
    }

    /// Pre-select the Shortcut tab in Settings, then open Settings. The
    /// Settings shell reads `cw.settings.tab` via `@AppStorage`, so writing
    /// the key first jumps straight to the right pane.
    private func openShortcutTab() {
        UserDefaults.standard.set(
            SettingsView.Tab.shortcut.rawValue,
            forKey: "cw.settings.tab"
        )
        SettingsWindowController.shared.show()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(PreferencesStore.shared)
        .frame(width: 520, height: 640)
        .preferredColorScheme(.dark)
}
