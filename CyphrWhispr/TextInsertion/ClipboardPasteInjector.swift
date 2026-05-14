import AppKit
import ApplicationServices

enum PasteInjectionError: Error, LocalizedError {
    case accessibilityNotTrusted
    case keyEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "CyphrWhispr needs Accessibility permission to type at the cursor. Open System Settings → Privacy & Security → Accessibility and enable CyphrWhispr."
        case .keyEventCreationFailed:
            return "Could not synthesize keyboard events."
        }
    }
}

/// Inserts transcribed text at the user's current cursor position by writing
/// to the pasteboard and synthesizing ⌘V. Supports two modes:
///
/// - One-shot `paste(_:)` — captures and restores the clipboard around a
///   single paste. Use when you only need to commit a final transcript.
///
/// - Live-typing via `pasteWithoutRestore(_:)` + `sendBackspaces(_:)` —
///   designed to be called repeatedly while the user is speaking. The caller
///   captures the clipboard once at the start of a session via
///   `PasteboardSnapshot.capture()`, lets the injector mutate the clipboard
///   freely during streaming (always tagged transient + concealed so clipboard
///   managers ignore it), then restores the snapshot once the session ends.
struct ClipboardPasteInjector {
    /// Delay between pressing each key in the ⌘V chord. Electron-class apps
    /// (Slack, VS Code, Notion) drop the V if Cmd's keyDown hasn't been
    /// processed yet.
    var interKeyDelay: useconds_t = 8_000      // 8 ms

    /// Delay after a one-shot paste, before we restore the clipboard. The
    /// receiving app needs time to actually read the pasteboard.
    var postPasteDelay: useconds_t = 120_000   // 120 ms

    /// Delay between consecutive backspaces during live typing. Too fast and
    /// some apps drop events; too slow and live typing feels laggy.
    var interBackspaceDelay: useconds_t = 1_500 // 1.5 ms

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Returns true once Accessibility is trusted, prompting the user if not.
    @discardableResult
    static func ensureAccessibilityTrusted(prompt: Bool = true) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - One-shot

    /// Paste `text` at the cursor and restore the previous clipboard content.
    func paste(_ text: String) throws {
        guard Self.ensureAccessibilityTrusted(prompt: false) else {
            throw PasteInjectionError.accessibilityNotTrusted
        }
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        PasteboardSnapshot.writeTranscription(text, to: pasteboard)
        try simulateCmdV()
        usleep(postPasteDelay)
        snapshot.restore(to: pasteboard)
    }

    // MARK: - Live typing (no clipboard restore — caller handles it)

    /// Paste `text` at the cursor without restoring the clipboard. Caller is
    /// expected to have snapshotted the clipboard before the streaming session
    /// began and will restore it when the session ends.
    func pasteWithoutRestore(_ text: String) throws {
        guard Self.ensureAccessibilityTrusted(prompt: false) else {
            throw PasteInjectionError.accessibilityNotTrusted
        }
        guard !text.isEmpty else { return }
        PasteboardSnapshot.writeTranscription(text, to: pasteboard)
        try simulateCmdV()
        // Brief gap so the receiving app's runloop catches the paste before
        // we send another paste or backspace burst.
        usleep(20_000)
    }

    /// Type `text` directly via synthetic Unicode keystrokes — does NOT touch
    /// the clipboard. Each Unicode scalar becomes a single keyDown/keyUp pair
    /// carrying the scalar as its `keyboardSetUnicodeString` payload, so the
    /// receiving app gets the literal text and there's no race between a
    /// posted ⌘V and a clipboard restore.
    ///
    /// Use this for the FINAL commit at session end, where the cost of an
    /// async-paste race (wrong text pasted) is highest. Live partials still
    /// use `pasteWithoutRestore` because clipboard ⌘V is faster for long
    /// suffixes during streaming, and a partial that lands in the wrong order
    /// gets superseded by the next partial anyway — but the final commit has
    /// no follow-up, so it must be ironclad.
    ///
    /// Surrogate pairs (non-BMP characters like emoji) are kept inside one
    /// event by iterating per-scalar and posting each scalar's full UTF-16
    /// representation (1 or 2 UInt16 units) as one event payload.
    ///
    /// As with `sendBackspaces`, we force `event.flags = []` so the user
    /// holding a modifier-bearing hotkey (e.g. ⌃⌘Space) doesn't poison the
    /// synthesized characters with stray modifiers.
    func typeUnicode(_ text: String) throws {
        guard !text.isEmpty else { return }
        guard Self.ensureAccessibilityTrusted(prompt: false) else {
            throw PasteInjectionError.accessibilityNotTrusted
        }
        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            // Each scalar maps to 1 or 2 UTF-16 code units. Send both inside
            // a single keyDown/keyUp pair so surrogate pairs aren't split.
            let utf16: [UniChar] = Array(String(scalar).utf16)

            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw PasteInjectionError.keyEventCreationFailed
            }
            down.flags = []
            up.flags = []
            utf16.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            }
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(interKeyDelay)
        }
    }

    /// Send `count` delete-back keystrokes to remove text we previously typed.
    /// Used during live typing to revise prior partial transcripts in place.
    ///
    /// CRITICAL: we explicitly clear `event.flags` to `[]`. If the user is
    /// holding the dictation hotkey (e.g. ⌥Space), the system's modifier state
    /// has the Option key down. CGEvent.post otherwise inherits that, so each
    /// synthesized ⌫ would arrive at the focused app as ⌥⌫ — which means
    /// "delete previous WORD." That manifests as the dictation app eating
    /// chunks of the user's existing text the first time a partial gets
    /// revised. Forcing flags = [] makes the event carry no modifiers,
    /// regardless of what the user is physically holding.
    func sendBackspaces(_ count: Int) throws {
        guard count > 0 else { return }
        guard Self.ensureAccessibilityTrusted(prompt: false) else {
            throw PasteInjectionError.accessibilityNotTrusted
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let deleteKey: CGKeyCode = 0x33  // kVK_Delete

        for _ in 0..<count {
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)
            else {
                throw PasteInjectionError.keyEventCreationFailed
            }
            down.flags = []
            up.flags = []
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(interBackspaceDelay)
        }
    }

    // MARK: - Internals

    /// Synthesize ⌘V at the focused app.
    ///
    /// We set `event.flags` on every event so the receiving app sees ONLY ⌘
    /// (not ⌘⌥V or ⌘⌃V) — important because the user may be holding the
    /// hotkey modifiers when this fires. ⌘⌥V is "Paste and Match Style" in
    /// many apps, which would lose formatting; in others it's a no-op and the
    /// paste silently fails.
    private func simulateCmdV() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09     // kVK_ANSI_V
        let cmdKey: CGKeyCode = 0x37   // kVK_Command

        guard
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        else {
            throw PasteInjectionError.keyEventCreationFailed
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand
        cmdUp.flags   = []

        cmdDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(interKeyDelay)
        vDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(interKeyDelay)
        vUp.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
