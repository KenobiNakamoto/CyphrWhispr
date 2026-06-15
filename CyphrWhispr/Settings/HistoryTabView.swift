import SwiftUI
import AppKit

/// Settings → History. The user-facing surface for the encrypted
/// transcription vault — Phase 4 of the v1 plan.
///
/// Binds directly to `HistoryService.shared`. Everything here is live: the
/// master toggle runs the BIP-39 enable/disable lifecycle, the search field
/// drives FTS5 queries against the SQLCipher store, and the entry cards show
/// real recorded dictations grouped by day.
///
/// Layout:
///   1. **Vault** — master toggle + (when on) a reveal-recovery-phrase row.
///   2. *(when on)* an error banner if the last vault op failed, a search
///      field, the day-grouped entry cards (or an empty state), the
///      retention policy card, and a footer with Finder / clear actions.
///
/// On the very first enable the freshly generated 12-word recovery phrase is
/// shown once in a backup sheet — that is the only moment the user is handed
/// the key, so the sheet pushes them to write it down.
struct HistoryTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @ObservedObject private var history = HistoryService.shared

    /// Live full-text search query. Every change re-runs `HistoryService.search`.
    @State private var query = ""

    /// Drives the destructive "clear all" confirmation dialog.
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "History",
                    subtitle: "Every finished dictation is appended to an encrypted vault on "
                        + "this Mac, unlocked by a 12-word recovery phrase. Searchable — and "
                        + "it never leaves your device."
                )

                vaultCard

                if prefs.historyEnabled {
                    if let error = history.lastError {
                        errorBanner(error)
                    }
                    if history.totalCount > 0 {
                        searchField
                    }
                    entriesSection
                    retentionCard
                    footerActions
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.cwMain, value: prefs.historyEnabled)
        }
        // Defensive: if Settings somehow opened before AppCoordinator's
        // launch-time bootstrap ran, open the vault now. `bootstrap()`
        // re-checks its own guards, so this is a no-op in the normal path.
        .onAppear {
            if prefs.historyEnabled && !history.isReady {
                history.bootstrap()
            }
        }
        .confirmationDialog("Delete all transcription history?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Delete all history", role: .destructive) {
                history.clearHistory()
                query = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases every saved transcription from the encrypted "
                 + "vault. Your recovery phrase is kept, so new dictations will still be "
                 + "recorded. This cannot be undone.")
        }
    }

    // MARK: - Vault card

    /// The master switch + recovery-phrase access. Always visible — this is
    /// the opt-in gate for the whole feature.
    private var vaultCard: some View {
        Card3(title: "Vault", meta: vaultMeta) {
            Row3(label: "Save dictation history",
                 sub: "Append every finished dictation to an AES-256 encrypted database. "
                    + "Off by default — recording is strictly opt-in.",
                 isLast: !prefs.historyEnabled) {
                Toggle3(isOn: enableBinding)
            }

            if prefs.historyEnabled {
                Row3(label: "Recovery phrase",
                     sub: "The 12 words that decrypt this vault. Anyone with them can read "
                        + "your history; without them it cannot be recovered — not even by "
                        + "CyphrWhispr.",
                     isLast: true) {
                    CWButton(title: "Reveal", variant: .ghost, indicator: .glyph("↗")) {
                        guard let phrase = history.recoveryPhrase else {
                            // Defensive — history is enabled but the
                            // Keychain access returned nil. Usually a
                            // re-signing / ACL mismatch; surface to the
                            // log so the user can grab it with Console.
                            NSLog("[CyphrWhispr] Reveal: Keychain returned no recovery phrase")
                            return
                        }
                        RecoveryPhraseSheetPresenter.present(
                            phrase: phrase,
                            isFirstTime: false,
                            prefs: prefs
                        )
                    }
                }
            }
        }
    }

    /// Card-header summary: off / encrypted-and-empty / count.
    private var vaultMeta: String {
        guard prefs.historyEnabled else { return "off" }
        if history.totalCount > 0 {
            return "\(history.totalCount) saved · encrypted"
        }
        return "AES-256 · on-device"
    }

    /// Toggle binding that runs the enable/disable lifecycle instead of just
    /// flipping a stored bool. The first enable hands back a fresh recovery
    /// phrase, which we surface in the one-time backup sheet.
    private var enableBinding: Binding<Bool> {
        Binding(
            get: { prefs.historyEnabled },
            set: { wantOn in
                if wantOn {
                    if let freshPhrase = history.enableHistory() {
                        RecoveryPhraseSheetPresenter.present(
                            phrase: freshPhrase,
                            isFirstTime: true,
                            prefs: prefs
                        )
                    }
                } else {
                    history.disableHistory()
                    query = ""
                }
            }
        )
    }

    // MARK: - Error banner

    /// Surfaces `HistoryService.lastError` — a crypto / SQLite failure the
    /// user needs to know about (e.g. a Keychain phrase that no longer
    /// matches the vault).
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!")
                .font(CWFont.mono(size: CWFont.s12, weight: .bold))
                .foregroundColor(.cwDanger)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.cwDanger.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.cwDanger.opacity(0.45), lineWidth: 1))
                )
            Text(message)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
                .fill(Color.cwDanger.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
                        .stroke(Color.cwDanger.opacity(0.30), lineWidth: 1)
                )
        )
        .padding(.bottom, CWSpace.s4)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.cwFg3)
            TextField("Search transcriptions", text: $query)
                .textFieldStyle(.plain)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg1)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.cwFg3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
                        .stroke(Color.cwBorder, lineWidth: 1)
                )
        )
        .padding(.bottom, CWSpace.s4)
        .onChange(of: query) { _, newValue in
            history.search(newValue)
        }
    }

    // MARK: - Entries

    /// Day-grouped entry cards, or an empty state when there is nothing to
    /// show (fresh vault, or a search with no matches).
    @ViewBuilder private var entriesSection: some View {
        if history.entries.isEmpty {
            emptyState
        } else {
            ForEach(dayGroups) { group in
                Card3(title: group.title,
                      meta: "\(group.records.count) "
                        + (group.records.count == 1 ? "entry" : "entries")) {
                    ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                        HistoryRow(record: record,
                                   isLast: index == group.records.count - 1)
                    }
                }
            }
        }
    }

    /// `HistoryService.entries` bucketed by calendar day, newest day first
    /// and newest entry first within each day.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: history.entries) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return buckets.keys.sorted(by: >).map { day in
            let records = buckets[day]!.sorted { $0.createdAt > $1.createdAt }
            return DayGroup(id: day, title: Self.dayTitle(day), records: records)
        }
    }

    private var emptyState: some View {
        let searching = !query.isEmpty
        return Card3 {
            VStack(spacing: 10) {
                Image(systemName: searching ? "magnifyingglass" : "tray")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.cwFg3)
                Text(searching ? "No matches" : "No transcriptions yet")
                    .font(CWFont.mono(size: CWFont.s13, weight: .medium))
                    .foregroundColor(.cwFg1)
                Text(searching
                     ? "No saved transcription contains “\(query)”."
                     : "Finished dictations will appear here — encrypted, and only on this Mac.")
                    .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                    .foregroundColor(.cwFg3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Retention card

    /// Pruning policy for the vault. Three policies — keep everything, cap by
    /// age, or cap by count. The control writes straight to `PreferencesStore`;
    /// `HistoryService` translates it into a `RetentionPolicy` the store
    /// enforces. Changing any value re-prunes immediately via
    /// `applyRetentionNow()` so the effect is visible right away.
    private var retentionCard: some View {
        Card3(title: "Retention", meta: retentionSummary) {
            Row3(label: "Keep transcriptions",
                 sub: "How long dictation history is kept before older entries are pruned.",
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
        .onChange(of: prefs.historyRetention) { _, _ in history.applyRetentionNow() }
        .onChange(of: prefs.historyRetentionDays) { _, _ in history.applyRetentionNow() }
        .onChange(of: prefs.historyRetentionEntryLimit) { _, _ in history.applyRetentionNow() }
    }

    /// Card-header summary of the active policy.
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

    // MARK: - Footer actions

    private var footerActions: some View {
        HStack(spacing: 10) {
            CWButton(title: "Reveal vault in Finder",
                     variant: .ghost,
                     indicator: .glyph("↗")) {
                history.revealVaultInFinder()
            }
            Spacer()
            if history.totalCount > 0 {
                CWButton(title: "Clear history",
                         variant: .danger,
                         indicator: .glyph("⌫")) {
                    showClearConfirm = true
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Day formatting

    /// "Today" / "Yesterday" / a locale-formatted date for a day bucket.
    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return (sameYear ? thisYearDayFormatter : pastYearDayFormatter).string(from: day)
    }

    private static let thisYearDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter
    }()

    private static let pastYearDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }()
}

// MARK: - Recovery-phrase sheet presenter
//
// We present the recovery-phrase sheet via AppKit's `NSWindow.beginSheet`
// rather than SwiftUI's `.sheet(item:)` because the latter has historically
// misbehaved when attached to views hosted in `NSHostingController`: in
// multi-display setups (or with `.fullSizeContentView` + transparent
// titlebar parent windows, as the Settings window has) the sheet can end up
// rendered as a free-floating panel positioned outside the parent — visible
// in single-display test runs but easy to lose track of when the user has
// a non-trivial monitor arrangement. AppKit's `beginSheet` guarantees a
// real, title-bar-attached sheet modal to the parent window.

@MainActor
enum RecoveryPhraseSheetPresenter {
    /// Open the BIP-39 recovery-phrase sheet as a real macOS sheet on top
    /// of the Settings window. Idempotent — if another sheet is already up
    /// on the same parent, this no-ops (macOS won't stack two sheets).
    static func present(phrase: String,
                        isFirstTime: Bool,
                        prefs: PreferencesStore) {
        guard let parent = settingsHostWindow() else {
            NSLog("[CyphrWhispr] Recovery phrase sheet: no host window to attach to")
            return
        }
        guard parent.attachedSheet == nil else {
            // A sheet is already up — defer to it instead of stacking. The
            // user re-fires by closing the existing sheet first.
            return
        }

        // Pre-construct the sheet window so the SwiftUI dismiss closure can
        // close it directly. `weak` on the capture so the closure doesn't
        // outlive the window if AppKit tears it down for any other reason.
        //
        // Borderless style mask: a real attached sheet has no title bar of
        // its own — AppKit slides it down from the parent window's title
        // bar. With `.titled` here the sheet would render its own redundant
        // title bar AND fail to attach properly; without it, `beginSheet`
        // does the right thing.
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 380),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        sheetWindow.appearance = NSAppearance(named: .darkAqua)
        sheetWindow.backgroundColor = NSColor(SettingsDesign.pageBackground)
        sheetWindow.isOpaque = true

        let dismiss: () -> Void = { [weak parent, weak sheetWindow] in
            guard let parent, let sheetWindow else { return }
            parent.endSheet(sheetWindow)
        }
        let host = NSHostingController(
            rootView: RecoveryPhraseSheet(phrase: phrase,
                                          isFirstTime: isFirstTime,
                                          onDismiss: dismiss)
                .environmentObject(prefs)
        )
        sheetWindow.contentViewController = host

        // Esc-to-dismiss. Native AppKit sheets respond to Esc; ours is a
        // SwiftUI view hosted inside a borderless NSWindow, which does not
        // get the same treatment for free. A local NSEvent monitor scoped
        // to this sheet's lifetime catches keyDown 53 (Esc) on the sheet
        // window and routes it through the same `dismiss` closure the Done
        // button calls. Removed in the beginSheet completion handler so the
        // monitor doesn't outlive the sheet.
        //
        // Filtering on `event.keyCode == 53` (rather than the
        // `charactersIgnoringModifiers` check) dodges IME edge cases where
        // an active input method swallows the character mapping but the
        // raw keyCode still fires.
        var escapeMonitor: Any?
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak sheetWindow] event in
            guard event.keyCode == 53,
                  let sw = sheetWindow,
                  event.window === sw else {
                return event
            }
            dismiss()
            return nil  // consume the Esc so the sheet's content doesn't also see it
        }

        parent.beginSheet(sheetWindow) { _ in
            if let token = escapeMonitor {
                NSEvent.removeMonitor(token)
                escapeMonitor = nil
            }
        }
    }

    /// Walk every visible NSWindow and find the one hosting the Settings UI.
    /// The Settings window is the only one carrying the
    /// `CyphrWhispr — Settings` title, so a title-prefix match is reliable.
    private static func settingsHostWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.title.hasPrefix("CyphrWhispr — Settings")
        }
    }
}

// MARK: - Day group

/// One calendar day's worth of entries, rendered as a single `Card3`.
private struct DayGroup: Identifiable {
    /// Start-of-day — both the dictionary key and the `ForEach` identity.
    let id: Date
    let title: String
    let records: [HistoryRecord]
}

// MARK: - Entry row

/// One transcription inside a day card. Up to four lines of transcript, then
/// a metadata line (time · source app · length). A copy button fades in on
/// hover and copies the *full* text — the visible transcript is truncated.
private struct HistoryRow: View {
    let record: HistoryRecord
    let isLast: Bool

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.text)
                .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                .foregroundColor(.cwFg1)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(Self.timeFormatter.string(from: record.createdAt))
                    .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                    .foregroundColor(.cwFg3)
                if let app = record.sourceApp, !app.isEmpty {
                    appChip(app)
                }
                Text("\(record.charCount) chars")
                    .font(CWFont.mono(size: CWFont.s10, weight: .regular))
                    .foregroundColor(.cwFg3)
                Spacer(minLength: 0)
                if hovering || copied {
                    copyButton
                }
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

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                copied = false
            }
        } label: {
            Text(copied ? "[ ✓ COPIED ]" : "[ COPY ]")
                .font(CWFont.mono(size: CWFont.s10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(copied ? .cwSuccess : .cwFg2)
        }
        .buttonStyle(.plain)
    }

    private func appChip(_ name: String) -> some View {
        Text(name)
            .font(CWFont.mono(size: CWFont.s10, weight: .medium))
            .tracking(0.4)
            .foregroundColor(.cwFg2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cwBorder, lineWidth: 1))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

// MARK: - Recovery-phrase sheet

/// The one-time BIP-39 backup sheet, also reused for later "show me my
/// phrase" reveals. Twelve numbered words in a 3-column grid, a warning, and
/// copy / dismiss controls. `isFirstTime` only changes the copy.
private struct RecoveryPhraseSheet: View {
    let phrase: String
    let isFirstTime: Bool
    let onDismiss: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var copied = false

    private var words: [String] {
        phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("⌗")
                    .font(CWFont.mono(size: CWFont.s17, weight: .semibold))
                    .foregroundColor(prefs.accent)
                Text(isFirstTime ? "Save your recovery phrase" : "Your recovery phrase")
                    .font(CWFont.mono(size: CWFont.s17, weight: .semibold))
                    .foregroundColor(.cwFg1)
            }

            Text(isFirstTime
                 ? "These 12 words are the only key to your encrypted history. Write them "
                    + "down and store them offline, somewhere safe."
                 : "These 12 words decrypt your history vault. Keep them offline and private.")
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            wordGrid
                .padding(.top, 18)

            warningRow
                .padding(.top, 16)

            HStack(spacing: 10) {
                CWButton(title: copied ? "Copied" : "Copy phrase",
                         variant: copied ? .downloaded : .ghost,
                         indicator: copied ? .glyph("✓") : .none) {
                    copyPhrase()
                }
                Spacer()
                CWButton(title: isFirstTime ? "I've saved it" : "Done",
                         variant: .primary,
                         indicator: .glyph("›")) {
                    onDismiss()
                }
            }
            .padding(.top, 22)
        }
        .padding(26)
        .frame(width: 468)
        .background(SettingsDesign.pageBackground)
        .preferredColorScheme(.dark)
    }

    private var wordGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 7) {
                    Text(String(format: "%02d", index + 1))
                        .font(CWFont.mono(size: CWFont.s10, weight: .medium))
                        .foregroundColor(.cwFg3)
                    Text(word)
                        .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                        .foregroundColor(.cwFg1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.cwBorder, lineWidth: 1))
                )
            }
        }
    }

    private var warningRow: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.cwWarning)
                .padding(.top, 1)
            Text(isFirstTime
                 ? "If this Mac is lost or erased, these words are the only way back into "
                    + "your history. CyphrWhispr keeps no copy and cannot reset them."
                 : "Never type these words into a website or share them. They are stored "
                    + "in your macOS Keychain.")
                .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CWRadius.sm, style: .continuous)
                .fill(Color.cwWarning.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: CWRadius.sm, style: .continuous)
                        .stroke(Color.cwWarning.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func copyPhrase() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phrase, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }
}

#Preview("History — off") {
    let prefs = PreferencesStore.shared
    prefs.historyEnabled = false
    return HistoryTabView()
        .environmentObject(prefs)
        .frame(width: 760, height: 720)
        .background(SettingsDesign.pageBackground)
        .preferredColorScheme(.dark)
}
