import Foundation
import SwiftUI
import Combine

/// User-tunable settings, persisted to UserDefaults. Single shared instance
/// passed via @ObservedObject / @EnvironmentObject so the Settings UI and the
/// AppCoordinator both observe the same source of truth.
///
/// Owns the **accent color**, too — the violet hex the user picked in
/// About → Appearance. Every view that draws an accent (Settings tabs, the
/// pill's comet rim, the menu-bar selection state) reads it from here so a
/// single picker change lights up the whole app.
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private enum Key {
        static let activeModelID = "Whisper.activeModelID"
        static let didCompleteFirstRun = "App.didCompleteFirstRun"
        static let accentHex = "App.accentColorHex"
    }

    /// The original brand violet — what the app ships with and what the
    /// "Reset" button restores to. Color literal keeps tests + previews from
    /// having to load the bundle.
    static let defaultAccentHex = "#7C4DFF"
    static let defaultAccent = Color(red: 0.486, green: 0.302, blue: 1.000)

    /// Currently selected Whisper model (a string ID matching `WhisperModel.id`).
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

    /// True after the recommender has been run once and a default model picked.
    /// Lets us avoid re-prompting on every launch.
    @Published var didCompleteFirstRun: Bool {
        didSet {
            UserDefaults.standard.set(didCompleteFirstRun, forKey: Key.didCompleteFirstRun)
        }
    }

    /// The user-chosen accent, persisted as a hex string. Treated as the source
    /// of truth — every other accent helper below derives from this.
    @Published var accentHex: String {
        didSet {
            guard accentHex != oldValue else { return }
            UserDefaults.standard.set(accentHex, forKey: Key.accentHex)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedModel = defaults.string(forKey: Key.activeModelID)
        let storedDidRun = defaults.bool(forKey: Key.didCompleteFirstRun)
        let storedHex = defaults.string(forKey: Key.accentHex)

        if let storedModel, ModelCatalog.model(id: storedModel) != nil {
            self.activeModelID = storedModel
            self.didCompleteFirstRun = storedDidRun
        } else {
            // First launch (or stored model has been removed from the catalog):
            // ask the recommender.
            let recommended = ModelRecommender.recommend(for: HardwareProfiler.profile())
            self.activeModelID = recommended.id
            self.didCompleteFirstRun = false
            defaults.set(recommended.id, forKey: Key.activeModelID)
        }

        // Accent is always present (defaulted) so the app paints sensibly on a
        // fresh install before the user has visited the picker.
        self.accentHex = storedHex ?? Self.defaultAccentHex
    }

    /// Mark first-run as done; called once the user has accepted (or changed
    /// from) the recommended model.
    func markFirstRunComplete() {
        if !didCompleteFirstRun { didCompleteFirstRun = true }
    }

    /// Replace the accent. Defensive against nonsense hex (falls back silently
    /// to the default rather than persisting garbage).
    func setAccent(_ color: Color) {
        let hex = color.hexString
        if Color(hex: hex) == nil {
            accentHex = Self.defaultAccentHex
        } else {
            accentHex = hex
        }
    }

    /// Restore the brand violet.
    func resetAccent() {
        accentHex = Self.defaultAccentHex
    }
}

// MARK: - Derived accent palette

/// Read-only computed properties built on top of `accentHex`. Putting them on
/// PreferencesStore (rather than a parallel Theme object) means views observe
/// a single ObservableObject — one `@EnvironmentObject` and the whole accent
/// system updates atomically.
extension PreferencesStore {
    /// The picked accent as a SwiftUI Color, with fallback to the default
    /// brand violet if the stored hex is somehow malformed.
    var accent: Color {
        Color(hex: accentHex) ?? Self.defaultAccent
    }

    /// Cooler counterpart to `accent` — shifted ~−28° in hue. The pill's comet
    /// gradient and the shortcut field's glow stroke fade INTO this so they
    /// have somewhere to go and don't read as flat single-color halos.
    var accentSecondary: Color {
        accent.huedShift(by: -28, saturationDelta: -0.05)
    }

    /// 12% wash used behind icon badges + the recommendation banner.
    var accentWash: Color { accent.opacity(0.12) }
    /// 20% fill used for hover/selected chips.
    var accentSelected: Color { accent.opacity(0.20) }

    /// Active-tab pill fill — soft accent → near-transparent so it reads as a
    /// glow rather than a hard chip.
    var activeTabFill: LinearGradient {
        LinearGradient(
            colors: [accentSelected, accent.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Border around the focused shortcut input — diagonal accent → secondary
    /// fade.
    var accentGlowStroke: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Notification.Name {
    /// Posted by `PreferencesStore` whenever the user picks a different
    /// Whisper model. Listeners (e.g. `PillWindowController`) use this to
    /// reset session-scoped state that should re-trigger after a model
    /// switch — like replaying the cinematic spawn animation on the next
    /// hotkey press.
    static let activeModelDidChange = Notification.Name("CyphrWhispr.activeModelDidChange")
}
