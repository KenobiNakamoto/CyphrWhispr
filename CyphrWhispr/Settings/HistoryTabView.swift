import SwiftUI

/// Settings → History. Encrypted transcription history. Phase 4 of the v1
/// plan brings the SQLCipher-backed store + BIP-39 unlock; until that lands
/// this tab shows demo entries (clearly labelled in the page subtitle) so
/// the user knows what the feature will look like — and so the visual
/// structure is in place to drop the real store into.
///
/// v2 glass redesign — single `Card3` titled "Today" with four demo
/// entries, two action buttons in a footer row below. The encrypted vault
/// + clear-history actions are stubs; they ship with the real store in
/// v0.5.
struct HistoryTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "History",
                    subtitle: "Encrypted with your BIP-39 passphrase. Searchable, never logged off-device. — Demo entries; encrypted store ships in v0.5."
                )

                Card3(title: "Today",
                      meta: "\(Self.placeholderEntries.count) entries · AES-256-GCM placeholder") {
                    ForEach(Array(Self.placeholderEntries.enumerated()), id: \.offset) { index, entry in
                        HistoryEntryRow(
                            entry: entry,
                            isLast: index == Self.placeholderEntries.count - 1
                        )
                    }
                }

                HStack(spacing: 10) {
                    CWButton(title: "Reveal vault in Finder",
                             variant: .ghost,
                             indicator: .glyph("↗")) {
                        // Stub — encrypted vault ships in v0.5.
                    }
                    CWButton(title: "Clear history",
                             variant: .danger,
                             indicator: .glyph("⌫")) {
                        // Stub — confirmation sheet + wipe land alongside the store.
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Stand-in entries shown before the real store is wired. Picked to
    /// look like a developer's actual dictation output — mixed apps, mixed
    /// content types. Mirrors the mockup exactly.
    private static let placeholderEntries: [HistoryEntry] = [
        HistoryEntry(
            text: "Hey, can you push the latest changes to the feature branch and tag the release as v0.4.0-alpha tonight?",
            timestamp: "2026-05-07 · 10:41",
            context: "TextEdit"
        ),
        HistoryEntry(
            text: "Reminder to self: review the install animation outro one more time before merging — bar cascade should land at idle position with zero pop.",
            timestamp: "2026-05-07 · 09:58",
            context: "Apple Notes"
        ),
        HistoryEntry(
            text: "The model switch flow drops the in-flight transcription cleanly now — confirmed end-to-end in scenario 4.",
            timestamp: "2026-05-07 · 09:14",
            context: "Slack"
        ),
        HistoryEntry(
            text: "Numbers / punctuation test: 0123456789 — i I l 1 — 0 O — and emoji ✓ should round-trip through the keystroke path.",
            timestamp: "2026-05-07 · 08:32",
            context: "iMessage"
        ),
    ]
}

/// One placeholder entry. Real entries will come from `HistoryStore` in
/// Phase 4 — same shape (text + timestamp + source app), backed by the
/// encrypted SQLite store instead of a hard-coded array.
private struct HistoryEntry {
    let text: String
    let timestamp: String
    let context: String
}

/// One history row inside the "Today" card. Three-line transcript at top
/// in `cwFg1`, then a metadata row with the timestamp (`cwFg3`) and a
/// small badge-style context chip. Hairline below unless `isLast`.
private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                .foregroundColor(.cwFg1)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(entry.timestamp)
                    .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                    .foregroundColor(.cwFg3)
                Text(entry.context)
                    .font(CWFont.mono(size: CWFont.s10, weight: .medium))
                    .tracking(0.4)
                    .foregroundColor(.cwFg2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.cwBorder, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(hovering ? Color.white.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.cwBorder).frame(height: 1)
            }
        }
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}
