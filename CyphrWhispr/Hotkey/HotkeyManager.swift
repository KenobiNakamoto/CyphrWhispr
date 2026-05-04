import Foundation
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

@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    func install() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.onPress?()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            self?.onRelease?()
        }
    }
}
