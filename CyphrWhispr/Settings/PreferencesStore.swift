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
        static let selectedLanguageCode = "Whisper.selectedLanguageCode"
        static let didCompleteFirstRun = "App.didCompleteFirstRun"
        static let accentHex = "App.accentColorHex"
        static let polishEnabled = "Polish.enabled"
        static let polishPromptIsCustomised = "Polish.promptIsCustomised"
        static let polishCustomPrompt = "Polish.customPrompt"
        // General tab — new in the sidebar refactor.
        static let launchAtLogin = "General.launchAtLogin"
        static let hideMenuBarIcon = "General.hideMenuBarIcon"
        static let activationMode = "General.activationMode"
        static let inhibitWhileTyping = "Shortcut.inhibitWhileTyping"
        // History tab — opt-in switch + retention policy.
        static let historyEnabled = "History.enabled"
        static let historyRetention = "History.retention"
        static let historyRetentionDays = "History.retentionDays"
        static let historyRetentionEntryLimit = "History.retentionEntryLimit"
    }

    /// How the hotkey turns dictation on and off. **Push-to-talk** (default)
    /// keeps the user holding the chord; release ends the session. **Toggle**
    /// flips on a single press and off on the next press — easier for long
    /// dictation but slightly harder to recover from accidental triggers.
    /// Read by `HotkeyManager` at install time; changing this restarts the
    /// hotkey wiring so the new mode takes effect immediately.
    enum ActivationMode: String, CaseIterable, Identifiable, Codable {
        case pushToTalk = "push_to_talk"
        case toggle = "toggle"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .pushToTalk: return "Push to talk"
            case .toggle:     return "Toggle"
            }
        }
    }

    /// How long transcription history is kept. `.forever` keeps every
    /// entry; `.days` prunes anything older than `historyRetentionDays`;
    /// `.entries` keeps only the most recent `historyRetentionEntryLimit`.
    /// Persisted now and surfaced in Settings → History; the actual
    /// pruning runs once the Phase 4 encrypted `HistoryStore` ships.
    enum HistoryRetention: String, CaseIterable, Identifiable, Codable {
        case forever = "forever"
        case days    = "days"
        case entries = "entries"
        var id: String { rawValue }
        /// Short label for the segmented control in Settings → History.
        var label: String {
            switch self {
            case .forever: return "Forever"
            case .days:    return "By age"
            case .entries: return "By count"
            }
        }
    }

    /// Day-count choices offered when retention is `.days`.
    static let historyRetentionDayChoices = [7, 14, 30, 60, 90, 180]
    /// Entry-count choices offered when retention is `.entries`.
    static let historyRetentionEntryChoices = [50, 100, 250, 500, 1000]

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

    /// User's transcription language preference. Either a Whisper language
    /// code (`"en"`, `"es"`, `"ja"`, …) to pin a specific language, or
    /// `TranscriptionLanguageMode.autoCode` (`"auto"`) to auto-detect on
    /// the first audio chunk and lock for the rest of the session.
    ///
    /// Validity is enforced: an unknown code (e.g. corrupted UserDefaults
    /// value, or one removed from the catalog in a future release)
    /// silently falls back to `"auto"` rather than blowing up.
    ///
    /// Effective on the **next** hotkey press, never an in-flight session
    /// (the engine reads this once at `startStream` and locks it).
    /// English-only (`.en`) model variants ignore this setting — they can
    /// only decode English regardless. The Settings UI hides the picker
    /// in that case.
    @Published var selectedLanguageCode: String {
        didSet {
            guard selectedLanguageCode != oldValue else { return }
            UserDefaults.standard.set(selectedLanguageCode,
                                      forKey: Key.selectedLanguageCode)
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

    // MARK: - General tab
    //
    // Three switches and one mode-picker that live in Settings → General.
    // All wired to real behaviour: launch-at-login flips an `SMAppService`
    // registration, hide-menu-bar toggles the `NSStatusItem`, activation
    // mode rebinds the hotkey callbacks in `HotkeyManager`, and inhibit-
    // while-typing is read by `HotkeyManager` before invoking onPress.

    /// Register CyphrWhispr to start when the user signs in. Backed by
    /// `SMAppService.mainApp` — registration is reversible from System
    /// Settings → General → Login Items. Failures (sandbox missing,
    /// service not approved, etc.) are logged but don't crash; the toggle
    /// is set back to false so the user sees the request didn't stick.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            NotificationCenter.default.post(name: .launchAtLoginDidChange, object: self)
        }
    }

    /// Hide the menu-bar status item. The hotkey still works — the icon is
    /// just suppressed for users who prefer a fully-invisible menu bar
    /// (think: Bartender users who don't need yet another icon up there).
    /// `StatusItemController` observes this and adds/removes the
    /// `NSStatusItem` accordingly.
    @Published var hideMenuBarIcon: Bool {
        didSet {
            guard hideMenuBarIcon != oldValue else { return }
            UserDefaults.standard.set(hideMenuBarIcon, forKey: Key.hideMenuBarIcon)
            NotificationCenter.default.post(name: .hideMenuBarIconDidChange, object: self)
        }
    }

    /// Push-to-talk vs Toggle. `HotkeyManager` reads this when wiring up
    /// the global hotkey; flipping it posts a notification so the manager
    /// can re-install with the new behaviour mid-session.
    @Published var activationMode: ActivationMode {
        didSet {
            guard activationMode != oldValue else { return }
            UserDefaults.standard.set(activationMode.rawValue, forKey: Key.activationMode)
            NotificationCenter.default.post(name: .activationModeDidChange, object: self)
        }
    }

    /// Suppress the hotkey when a text-entry field already has focus and the
    /// user is actively typing. Prevents accidental triggers while writing
    /// code or filling forms. Default ON — read by `HotkeyManager` before
    /// invoking onPress; doesn't change the hotkey registration itself.
    @Published var inhibitWhileTyping: Bool {
        didSet {
            guard inhibitWhileTyping != oldValue else { return }
            UserDefaults.standard.set(inhibitWhileTyping, forKey: Key.inhibitWhileTyping)
        }
    }

    // MARK: - History
    //
    // `.forever` is the default retention — we never silently drop a user's
    // data without them choosing a pruning policy first. The day / entry
    // values are kept independently so switching policy back and forth
    // doesn't lose the other axis's setting.

    /// Master switch for the encrypted transcription history. Off by default
    /// — recording dictation is strictly opt-in. `HistoryService` owns the
    /// open/close flow; this flag is the persisted record of the user's
    /// choice and what the History tab's toggle reflects.
    @Published var historyEnabled: Bool {
        didSet {
            guard historyEnabled != oldValue else { return }
            UserDefaults.standard.set(historyEnabled, forKey: Key.historyEnabled)
        }
    }

    /// Active retention policy: keep forever, prune by age, or prune by count.
    @Published var historyRetention: HistoryRetention {
        didSet {
            guard historyRetention != oldValue else { return }
            UserDefaults.standard.set(historyRetention.rawValue, forKey: Key.historyRetention)
        }
    }

    /// Age cap (in days) used when `historyRetention == .days`.
    @Published var historyRetentionDays: Int {
        didSet {
            guard historyRetentionDays != oldValue else { return }
            UserDefaults.standard.set(historyRetentionDays, forKey: Key.historyRetentionDays)
        }
    }

    /// Entry cap used when `historyRetention == .entries`.
    @Published var historyRetentionEntryLimit: Int {
        didSet {
            guard historyRetentionEntryLimit != oldValue else { return }
            UserDefaults.standard.set(historyRetentionEntryLimit, forKey: Key.historyRetentionEntryLimit)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedModel = defaults.string(forKey: Key.activeModelID)
        let storedDidRun = defaults.bool(forKey: Key.didCompleteFirstRun)
        let storedHex = defaults.string(forKey: Key.accentHex)
        let storedLang = defaults.string(forKey: Key.selectedLanguageCode)

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

        // Language preference: validate against our curated list. An unknown
        // code (corrupted defaults, value removed from a future catalog) falls
        // back to "auto" rather than crashing or silently using something
        // unexpected. First-launch users get "auto" so they're not forced
        // into English even on a multilingual model.
        if let storedLang, TranscriptionLanguageCatalog.isValid(storedLang) {
            self.selectedLanguageCode = storedLang
        } else {
            self.selectedLanguageCode = TranscriptionLanguageMode.autoCode
            defaults.set(TranscriptionLanguageMode.autoCode,
                         forKey: Key.selectedLanguageCode)
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

        // General-tab defaults:
        //   • Launch at login OFF — opt-in (we don't auto-add ourselves on
        //     first launch; the user has to ask).
        //   • Hide menu bar OFF — icon visible by default so people can
        //     find Settings without keyboard navigation.
        //   • Activation mode push-to-talk — matches the v1 spec.
        //   • Inhibit while typing ON — safest default for daily use.
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.hideMenuBarIcon = defaults.bool(forKey: Key.hideMenuBarIcon)
        if let modeRaw = defaults.string(forKey: Key.activationMode),
           let mode = ActivationMode(rawValue: modeRaw) {
            self.activationMode = mode
        } else {
            self.activationMode = .pushToTalk
        }
        if defaults.object(forKey: Key.inhibitWhileTyping) == nil {
            self.inhibitWhileTyping = true
            defaults.set(true, forKey: Key.inhibitWhileTyping)
        } else {
            self.inhibitWhileTyping = defaults.bool(forKey: Key.inhibitWhileTyping)
        }

        // History defaults: recording OFF (opt-in), retention keep-everything.
        // The day / entry caps carry sensible mid-range defaults so the
        // dropdowns aren't empty the first time a policy is selected
        // (`integer(forKey:)` returns 0 when the key is absent).
        self.historyEnabled = defaults.bool(forKey: Key.historyEnabled)
        if let retentionRaw = defaults.string(forKey: Key.historyRetention),
           let retention = HistoryRetention(rawValue: retentionRaw) {
            self.historyRetention = retention
        } else {
            self.historyRetention = .forever
        }
        let storedDays = defaults.integer(forKey: Key.historyRetentionDays)
        self.historyRetentionDays = storedDays == 0 ? 30 : storedDays
        let storedLimit = defaults.integer(forKey: Key.historyRetentionEntryLimit)
        self.historyRetentionEntryLimit = storedLimit == 0 ? 100 : storedLimit
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

    // MARK: - Language derived helpers

    /// What we actually pass to the engine. If the active model is
    /// English-only (a `.en` variant), force `"en"` regardless of what's
    /// in `selectedLanguageCode` — those models can't decode anything else
    /// and passing `"auto"` or another locale would either error or
    /// silently produce nonsense. Otherwise pass through the user's pick.
    var effectiveLanguageCode: String {
        if let model = ModelCatalog.model(id: activeModelID), !model.isMultilingual {
            return "en"
        }
        return selectedLanguageCode
    }

    /// True when the active model variant is multilingual — i.e. the
    /// language picker should be enabled in Settings. Single source of
    /// truth so the UI logic stays one-line.
    var activeModelSupportsLanguageChoice: Bool {
        ModelCatalog.model(id: activeModelID)?.isMultilingual ?? false
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
    /// editable text with the default prompt so they edit-in-place rather
    /// than starting from a blank box. The Polish tab edits a draft copy of
    /// this and only writes it back through `savePolishPrompt(_:)`.
    func enablePolishCustomPrompt() {
        if !polishPromptIsCustomised {
            polishCustomPrompt = CleanupPrompt.defaultPrompt
            polishPromptIsCustomised = true
        }
    }

    /// User clicks "Default" in the prompt editor: stop using a custom prompt
    /// and fall back to the read-only default. We DON'T wipe
    /// `polishCustomPrompt`; it's harmless to keep, and re-entering customised
    /// mode reseeds it from the default anyway.
    func resetPolishPrompt() {
        polishPromptIsCustomised = false
    }

    /// User clicks "Save" in the prompt editor: commit the edited draft as
    /// the prompt dictation will use from now on.
    ///
    /// If the edited text is the default prompt verbatim (whitespace aside),
    /// drop back to read-only default mode instead of storing a "custom"
    /// prompt that merely duplicates the default — that keeps the Polish
    /// card's default/customised label honest.
    func savePolishPrompt(_ edited: String) {
        let normalise: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if normalise(edited) == normalise(CleanupPrompt.defaultPrompt) {
            polishPromptIsCustomised = false
        } else {
            polishCustomPrompt = edited
            polishPromptIsCustomised = true
        }
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

    /// Posted when the user flips the Launch-at-login switch. The launch-
    /// services helper observes this to register / unregister the
    /// `SMAppService.mainApp` entry.
    static let launchAtLoginDidChange = Notification.Name("CyphrWhispr.launchAtLoginDidChange")

    /// Posted when the user flips the Hide-menu-bar-icon switch.
    /// `StatusItemController` observes this and installs / removes the
    /// `NSStatusItem` so the change takes effect immediately.
    static let hideMenuBarIconDidChange = Notification.Name("CyphrWhispr.hideMenuBarIconDidChange")

    /// Posted when the user changes the activation mode (push-to-talk vs
    /// toggle). `HotkeyManager` observes this and re-wires its callbacks.
    static let activationModeDidChange = Notification.Name("CyphrWhispr.activationModeDidChange")
}
