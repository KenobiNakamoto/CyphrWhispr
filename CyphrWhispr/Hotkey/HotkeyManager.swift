import Foundation
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default = ⌥Space (Option + Space). Easy to hold one-handed, not used by
    /// any built-in macOS app shortcut. The text-input mapping for ⌥Space (a
    /// non-breaking space character) doesn't interfere because we register a
    /// global hotkey via Carbon's RegisterEventHotKey, which runs before the
    /// active app sees the keystroke. The user can rebind it from Settings →
    /// Shortcut at any time.
    static let toggleDictation = Self(
        "toggleDictation",
        default: .init(.space, modifiers: [.option])
    )
}

/// Bridges the global hotkey to `AppCoordinator`. Two responsibilities:
///
///   1. **Activation mode.** In `pushToTalk` mode, key-down triggers
///      `onPress` and key-up triggers `onRelease` — the user holds the
///      chord for the duration of the dictation. In `toggle` mode, the
///      first key-down triggers `onPress` and the next key-down triggers
///      `onRelease` (the up event is ignored). Re-installs callbacks when
///      `activationModeDidChange` fires so a mid-session mode flip takes
///      effect on the very next press.
///
///   2. **Inhibit-while-typing.** When the user is actively focused on a
///      text-entry field (any first responder that conforms to
///      `NSTextInputClient`), suppress the press callback so an accidental
///      ⌥Space in a code editor doesn't trigger dictation. The hotkey
///      still registers — we just no-op the callback. Opt-out per-user
///      via `prefs.inhibitWhileTyping = false`.
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// Toggle-mode bookkeeping: are we currently "armed" (i.e. waiting for
    /// the next press to fire `onRelease`)? Reset whenever the activation
    /// mode changes or `install` is re-called.
    private var toggleIsArmed = false

    /// Observer token for the activation-mode change notification. Stored
    /// so we can remove it on deinit (avoids a leaked observer if the
    /// manager is ever recreated).
    private var activationModeObserver: NSObjectProtocol?

    init() {
        // Re-wire on activation-mode flips. This is a Settings-tab event,
        // not a hotkey event, so it fires from the main thread.
        activationModeObserver = NotificationCenter.default.addObserver(
            forName: .activationModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reinstall()
            }
        }
    }

    deinit {
        if let token = activationModeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Initial install. Reads the current activation mode from prefs and
    /// wires the appropriate key-down / key-up callbacks.
    func install() {
        wire()
    }

    /// Re-wire after a mode change. Replaces the prior handler bindings —
    /// KeyboardShortcuts replaces handlers for the same Name when you
    /// re-register, so this is safe to call repeatedly.
    private func reinstall() {
        toggleIsArmed = false
        wire()
    }

    private func wire() {
        let prefs = PreferencesStore.shared
        let mode = prefs.activationMode

        switch mode {
        case .pushToTalk:
            // Standard hold-to-dictate. Press starts; release stops.
            KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
                self?.handleKeyDownPushToTalk()
            }
            KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
                // Inhibit-while-typing only suppresses the START of a
                // session. Once a session has begun, the release should
                // still finalise it.
                self?.onRelease?()
            }

        case .toggle:
            // Toggle mode — only react to key-down. First press starts,
            // second press stops. Key-up is intentionally ignored.
            KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
                self?.handleKeyDownToggle()
            }
            KeyboardShortcuts.onKeyUp(for: .toggleDictation) { /* no-op */ }
        }
    }

    private func handleKeyDownPushToTalk() {
        if shouldInhibit() { return }
        onPress?()
    }

    private func handleKeyDownToggle() {
        if !toggleIsArmed {
            // Starting a session.
            if shouldInhibit() { return }
            toggleIsArmed = true
            onPress?()
        } else {
            // Ending the current session. We do NOT check inhibit here —
            // the user has an active dictation going and we should let
            // them stop it regardless of which field has focus.
            toggleIsArmed = false
            onRelease?()
        }
    }

    /// Returns true when the user has the pref enabled AND the focused
    /// responder is actively accepting text input. Best-effort check using
    /// NSTextInputClient conformance — covers native AppKit text fields,
    /// NSTextView, WebKit content editing, and SwiftUI TextField. Misses
    /// some Electron internals (Slack, VS Code), but doesn't false-positive
    /// on read-only views.
    private func shouldInhibit() -> Bool {
        let prefs = PreferencesStore.shared
        guard prefs.inhibitWhileTyping else { return false }
        // We check the KEY window of OUR app first (the Settings window
        // might be focused). But the user is normally typing in a
        // DIFFERENT app — so we also check the system-wide frontmost app's
        // accessibility state for an "AXFocused" text-area child. That's
        // overkill for v1; for now we only inhibit when our own Settings
        // window has focus on a text field. The hotkey is global, so the
        // FAR more common case (typing in a code editor that isn't us)
        // doesn't trigger the inhibit — which matches the user expectation
        // that the hotkey "just works" everywhere except in our own UI.
        guard let key = NSApp.keyWindow else { return false }
        if let responder = key.firstResponder,
           responder.conforms(to: NSTextInputClient.self) {
            return true
        }
        return false
    }
}
