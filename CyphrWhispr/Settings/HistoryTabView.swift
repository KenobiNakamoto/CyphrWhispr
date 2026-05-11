import SwiftUI

/// Settings → History. Encrypted transcription history. Phase 4 of the v1
/// plan brings the SQLCipher-backed store + BIP-39 unlock; until that lands
/// this tab shows demo entries (clearly labelled in the page subtitle) so
/// the user knows what the feature will look like — and so the visual
/// structure is in place to drop the real store into.
///
/// Two design decisions:
///   • No loud "PHASE 4 / coming soon" banner — the page subtitle quietly
///     calls out that the entries are demo data and the rows are styled to
///     read at full opacity. Saves vertical real estate and avoids
///     screaming "incomplete" at the user.
///   • Real rows render at full opacity in the eventual implementation;
///     for now we soften them by ~10% so they don't claim to be authentic
///     history.
struct HistoryTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        SettingsTabContainer(
            title: "History",
            subtitle: "Encrypted with your BIP-39 passphrase. Searchable, never logged off-device. — Demo entries; encrypted store ships in v0.5."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.placeholderEntries.enumerated()), id: \.offset) { index, entry in
                        HistoryEntryRow(entry: entry)
                        if index < Self.placeholderEntries.count - 1 {
                            CardRowDivider()
                        }
                    }
                }
            }
            .opacity(0.92)
        }
    }

    /// Stand-in entries shown before the real store is wired. Picked to
    /// look like a developer's actual dictation output — mixed apps, mixed
    /// content types. Mirrors the mockup exactly.
    private static let placeholderEntries: [HistoryEntry] = [
        HistoryEntry(
            text: "Hey, can you push the latest changes to the feature branch and tag the release as v0.4.0-alpha tonight?",
            date: "2026-05-07",
            time: "10:41",
            app: "TextEdit"
        ),
        HistoryEntry(
            text: "Reminder to self: review the install animation outro one more time before merging — bar cascade should land at idle position with zero pop.",
            date: "2026-05-07",
            time: "09:58",
            app: "Apple Notes"
        ),
        HistoryEntry(
            text: "The model switch flow drops the in-flight transcription cleanly now — confirmed end-to-end in scenario 4.",
            date: "2026-05-07",
            time: "09:14",
            app: "Slack"
        ),
        HistoryEntry(
            text: "Numbers / punctuation test: 0123456789 — i I l 1 — 0 O — and emoji ✓ should round-trip through the keystroke path.",
            date: "2026-05-07",
            time: "08:32",
            app: "iMessage"
        ),
    ]
}

/// One placeholder entry. Real entries will come from `HistoryStore` in
/// Phase 4 — same shape (text + timestamp + source app), backed by the
/// encrypted SQLite store instead of a hard-coded array.
private struct HistoryEntry {
    let text: String
    let date: String
    let time: String
    let app: String
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(SettingsDesign.krBody(size: 13))
                .foregroundStyle(SettingsDesign.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // Metadata: date · time · app, joined by middle-dots. Tertiary
            // colour so it recedes visually behind the transcript text.
            Text("\(entry.date) · \(entry.time) · \(entry.app)")
                .font(SettingsDesign.krCaption(size: 11))
                .foregroundStyle(SettingsDesign.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsDesign.rowPaddingHorizontal)
        .padding(.vertical, SettingsDesign.rowPaddingVertical)
    }
}
