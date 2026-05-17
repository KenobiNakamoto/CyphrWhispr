import SwiftUI

/// Settings → History. Encrypted transcription history. Phase 4 of the v1
/// plan brings the SQLCipher-backed store + BIP-39 unlock; until that lands
/// this tab shows demo entries (clearly labelled in the page subtitle) so
/// the user knows what the feature will look like — and so the visual
/// structure is in place to drop the real store into.
///
/// v2 glass redesign — a `Card3` titled "Today" with four demo entries, a
/// "Retention" card with the pruning policy, then two action buttons in a
/// footer row. The retention *preference* is real and persists today; the
/// encrypted vault, the clear-history wipe, and the actual pruning are
/// stubs that ship with the real store in v0.5.
struct HistoryTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Drives the destructive "clear all" confirmation dialog.
    @State private var showClearConfirm = false

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

                retentionCard

                HStack(spacing: 10) {
                    CWButton(title: "Reveal vault in Finder",
                             variant: .ghost,
                             indicator: .glyph("↗")) {
                        // Stub — encrypted vault ships in v0.5.
                    }
                    CWButton(title: "Clear history",
                             variant: .danger,
                             indicator: .glyph("⌫")) {
                        showClearConfirm = true
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Delete all transcription history?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Delete all history", role: .destructive) {
                // TODO(v0.5): wipe the encrypted HistoryStore here. The
                // confirmation UX is wired now so only the store call is
                // left to add.
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved transcription. It cannot be undone.")
        }
    }

    // MARK: - Retention card

    /// Pruning policy for the transcription history. Three policies — keep
    /// everything, cap by age, or cap by count — mirroring the spec in
    /// `docs/strategy`. The control writes straight to `PreferencesStore`;
    /// the encrypted store reads these values to prune once it ships.
    private var retentionCard: some View {
        Card3(title: "Retention", meta: retentionSummary) {
            Row3(label: "Keep transcriptions",
                 sub: "How long dictation history is kept. Takes effect when the encrypted store ships in v0.5.",
                 isLast: prefs.historyRetention == .forever) {
                Segmented3(
                    value: $prefs.historyRetention,
                    options: PreferencesStore.HistoryRetention.allCases.map {
                        ($0, $0.label)
                    }
                )
            }

            switch prefs.historyRetention {
            case .forever:
                EmptyView()
            case .days:
                Row3(label: "Delete after",
                     sub: "Entries older than this are removed automatically.",
                     isLast: true) {
                    numberMenu(value: $prefs.historyRetentionDays,
                               options: PreferencesStore.historyRetentionDayChoices) {
                        "\($0) days"
                    }
                }
            case .entries:
                Row3(label: "Keep most recent",
                     sub: "Older entries drop off as new dictations arrive.",
                     isLast: true) {
                    numberMenu(value: $prefs.historyRetentionEntryLimit,
                               options: PreferencesStore.historyRetentionEntryChoices) {
                        "\($0) entries"
                    }
                }
            }
        }
        .animation(.cwMain, value: prefs.historyRetention)
    }

    /// Card-header summary of the active policy, e.g. "30-DAY LIMIT".
    private var retentionSummary: String {
        switch prefs.historyRetention {
        case .forever: return "keep forever"
        case .days:    return "\(prefs.historyRetentionDays)-day limit"
        case .entries: return "last \(prefs.historyRetentionEntryLimit)"
        }
    }

    /// Styled dropdown for a fixed set of integer choices — same visual
    /// language as the dictation-language menu on the General tab.
    private func numberMenu(value: Binding<Int>,
                            options: [Int],
                            format: @escaping (Int) -> String) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    value.wrappedValue = opt
                } label: {
                    HStack {
                        Text(format(opt))
                        if value.wrappedValue == opt {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(format(value.wrappedValue))
                    .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                    .foregroundColor(.cwFg1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.cwFg2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.cwBorder, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
