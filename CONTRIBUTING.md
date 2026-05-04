# Contributing to CyphrWhispr

Thanks for your interest. CyphrWhispr is a small, opinionated codebase — a few rules keep it that way.

## Before you start

- For **bug reports**, open an issue with: macOS version, chip + RAM, the model you're using, exact reproduction steps, and (if a paste/clipboard issue) which app you were pasting into.
- For **small fixes** (typos, obvious bugs, comment improvements), feel free to open a PR directly.
- For **anything bigger** (new tab, new feature, model changes, crypto changes, UI redesigns), open an issue first so we can agree on the shape before you spend time on it.

## Setup

```sh
brew install xcodegen
git clone https://github.com/<your-fork>/CyphrWhispr.git
cd CyphrWhispr
xcodegen generate
open CyphrWhispr.xcodeproj
```

Code-signing setup is in the [README](README.md#code-signing-for-local-development).

## House style

- **Swift 5.9+, SwiftUI first.** Drop to AppKit when SwiftUI can't reach the API (NSPanel, NSStatusItem, NSEvent, NSHostingView).
- **Comment the why, not the what.** The codebase reads like a colleague explaining tricky design decisions. Doc comments that just restate the function name are noise; a 3-line comment explaining why a magic constant is what it is is gold. Read `PillView.swift` or `ClipboardPasteInjector.swift` for the voice.
- **Single-source-of-truth state.** `PreferencesStore` owns persisted user settings, `AppCoordinator` owns the runtime state machine. Don't add another singleton.
- **No new dependencies without discussion.** Each one is a long-term commitment.
- **Keep the menu-bar/Dockless contract.** `LSUIElement = true` stays true. Nothing should ever bring up a Dock icon or app-switcher entry except by explicit user action.

## Project layout

See [README → How it works](README.md#how-it-works) for the module map. New code should land in one of the existing folders (App / MenuBar / PillWindow / Hotkey / Audio / Transcription / TextInsertion / Hardware / Settings) or, if you're genuinely adding a new concern, in a new sibling folder with a one-paragraph comment in its first file explaining why it exists.

## Running tests

A `CyphrWhisprTests` target exists but is currently sparse. New code that has a sensible unit boundary (BIP-39, model recommender, transcript sanitizer, pasteboard snapshot) should come with tests. UI code generally doesn't.

```sh
xcodebuild -project CyphrWhispr.xcodeproj -scheme CyphrWhispr test
```

## Pull request checklist

- [ ] `xcodegen generate` ran clean
- [ ] Project builds with no new warnings
- [ ] Existing tests pass; new code has tests where it makes sense
- [ ] UI changes include a before/after screenshot in the PR description
- [ ] Commit messages explain the *why*, not just the *what*

## License

By contributing, you agree your contributions will be licensed under the [MIT License](LICENSE).
