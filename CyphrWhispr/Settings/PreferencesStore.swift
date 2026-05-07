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
        static let polishEnabled = "Polish.enabled"
        static let polishPromptIsCustomised = "Polish.promptIsCustomised"
        static let polishCustomPrompt = "Polish.customPrompt"
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

    // MARK: - Polish (Apple Foundation Models cleanup)
    //
    // Off by default in v1 — polishing is an opt-in. The user toggles it on in
    // Settings → Polish, where they can also see and edit the cleanup prompt.
    // Three pieces of state:
    //   • `polishEnabled`              — the master switch
    //   • `polishPromptIsCustomised`   — true once the user has clicked "Customise prompt"
    //   • `polishCustomPrompt`         — the user-edited prompt; only used when customised
    //
    // The "effective" prompt is computed below: returns the custom prompt if
    // the user has customised, otherwise the default from `CleanupPrompt`.

    /// Master switch: should we run a cleanup pass on the final transcription?
    /// Even when ON, the cleaner respects OS availability — see
    /// `TranscriptionCleaner.availability` for the actual feature gate.
    @Published var polishEnabled: Bool {
        didSet {
            guard polishEnabled != oldValue else { return }
            UserDefaults.standard.set(polishEnabled, forKey: Key.polishEnabled)
        }
    }

    /// True once the user has clicked "Customise prompt" and edited the
    /// cleanup instructions away from the default. While false, the default
    /// prompt is used and the prompt UI shows the read-only baseline.
    @Published var polishPromptIsCustomised: Bool {
        didSet {
            guard polishPromptIsCustomised != oldValue else { return }
            UserDefaults.standard.set(polishPromptIsCustomised, forKey: Key.polishPromptIsCustomised)
        }
    }

    /// User-edited cleanup prompt. Only consulted when
    /// `polishPromptIsCustomised == true`. Stored separately from the toggle
    /// so the user's edits survive flipping customised → default → customised.
    @Published var polishCustomPrompt: String {
        didSet {
            guard polishCustomPrompt != oldValue else { return }
            UserDefaults.standard.set(polishCustomPrompt, forKey: Key.polishCustomPrompt)
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

        // Polish defaults: off, prompt at baseline. The customPrompt slot is
        // pre-seeded with the default so the textarea has something sensible
        // to show the moment the user clicks "Customise prompt" — they edit
        // a copy, they don't start from a blank field.
        self.polishEnabled = defaults.bool(forKey: Key.polishEnabled)
        self.polishPromptIsCustomised = defaults.bool(forKey: Key.polishPromptIsCustomised)
        self.polishCustomPrompt = defaults.string(forKey: Key.polishCustomPrompt)
            ?? CleanupPrompt.defaultPrompt
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

    // MARK: - Polish derived helpers

    /// The cleanup prompt that will actually be sent to the language model.
    /// Customised → user's edit. Default → the canonical prompt from
    /// `CleanupPrompt`. Computed (not stored) so it always reflects the
    /// current customise toggle without needing a separate didSet sync.
    var effectivePolishPrompt: String {
        polishPromptIsCustomised ? polishCustomPrompt : CleanupPrompt.defaultPrompt
    }

    /// User clicks "Customise prompt": flip into customised mode. Seeds the
    /// editable text with whatever they were just looking at (the default)
    /// so they can edit-in-place rather than starting from blank.
    func enablePolishCustomPrompt() {
        if !polishPromptIsCustomised {
            polishCustomPrompt = CleanupPrompt.defaultPrompt
            polishPromptIsCustomised = true
        }
    }

    /// User clicks "Reset to default": flip out of customised mode. We DON'T
    /// wipe `polishCustomPrompt` — keeping the previous edits means clicking
    /// Customise again restores the user's last version rather than the
    /// pristine default. (If they want to start over, the editable textarea
    /// has a "Restore default text" affordance.)
    func resetPolishPrompt() {
        polishPromptIsCustomised = false
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
