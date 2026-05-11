import SwiftUI

/// Settings → History. Encrypted transcription history. Phase 4 of the v1
/// plan introduces the real SQLCipher-backed store + BIP-39 unlock; for now
/// this tab is a "coming soon" placeholder that shows the visual structure
/// (rows of past dictations with timestamp + source app) so the user
/// understands what the feature will look like once it's wired up.
///
/// The placeholder examples are clearly fictional — the timestamps reference
/// a release date and the contents read like a developer's reminder list.
/// We don't store any real history yet.
struct HistoryTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        SettingsTabContainer(
            title: "History",
            subtitle: "Encrypted with your BIP-39 passphrase. Searchable, never logged off-device."
        ) {
            // Coming-soon banner — important up front so we don't pretend
            // the placeholder rows are real history.
            comingSoonBanner

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
            .opacity(0.85) // softens the placeholder; reads as inactive
        }
    }

    private var comingSoonBanner: some View {
        HStack(spacing: 12) {
            TerminalBadge(label: "PHASE 4", glyph: "▴", tint: prefs.accent)
            Text("Encrypted history lands in v0.5 — BIP-39 passphrase, FTS5 search, SQLCipher store.")
                .font(SettingsDesign.krCaption(size: 12))
                .foregroundStyle(SettingsDesign.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(prefs.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(prefs.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// Stand-in entries shown before the real store is wired. Picked to
    /// look like a developer's actual dictation output — mixed apps, mixed
    /// content types. Matches the mockup exactly.
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
                .fixedSize(horizontal: false, vertical: true)
            // Metadata: date · time · app, joined by middle-dots.
            Text("\(entry.date) · \(entry.time) · \(entry.app)")
                .font(SettingsDesign.krCaption(size: 11))
                .foregroundStyle(SettingsDesign.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
