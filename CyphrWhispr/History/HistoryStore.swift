import Foundation
import SQLCipher

/// Retention policy the store enforces when pruning. Mirrors
/// `PreferencesStore.HistoryRetention`, but is redeclared here so the store
/// has no dependency on the preferences layer — `HistoryService` translates.
enum RetentionPolicy: Equatable, Sendable {
    case keepForever
    case maxAge(days: Int)
    case maxEntries(Int)
}

/// One stored transcription.
struct HistoryRecord: Identifiable, Equatable, Sendable {
    let id: Int64
    let text: String
    let createdAt: Date
    /// Localized name of the app that was frontmost when dictation finished.
    /// Nil for entries captured before the focused app could be resolved.
    let sourceApp: String?
    let charCount: Int
}

enum HistoryStoreError: Error, Equatable {
    case openFailed(String)
    /// The mnemonic-derived key did not decrypt the vault — either the wrong
    /// recovery phrase, or a corrupt file.
    case wrongKey
    case sql(String)
}

/// The encrypted transcription-history vault.
///
/// An `actor` wrapping a single SQLCipher (AES-256) database connection. Every
/// call is serialized through the actor, so the connection needs no extra
/// locking of its own.
///
/// The file at `vaultURL` is encrypted at rest: without the BIP-39-derived key
/// it is indistinguishable from random bytes. The key is applied once, at
/// init, via `PRAGMA key`; this type never writes the key or the mnemonic to
/// disk — that is `HistoryKeychain`'s job.
actor HistoryStore {

    private var db: OpaquePointer?
    private let vaultURL: URL

    /// SQLite wants to know whether it may keep a borrowed string pointer.
    /// `TRANSIENT` tells it to copy immediately, so Swift `String` bridging
    /// (valid only for the call) is safe.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Open (creating if absent) and unlock the vault at `vaultURL` with the
    /// key derived from `mnemonic`. Throws `.wrongKey` if an existing vault
    /// won't decrypt with this phrase.
    init(vaultURL: URL, mnemonic: String) throws {
        self.vaultURL = vaultURL

        var handle: OpaquePointer?
        guard sqlite3_open_v2(vaultURL.path, &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open"
            sqlite3_close(handle)
            throw HistoryStoreError.openFailed(message)
        }
        self.db = handle

        // Apply the encryption key. This must be the first statement on the
        // connection — before any read or write touches the database pages.
        let keyValue = HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonic)
        try exec("PRAGMA key = \"\(keyValue)\";")

        // Confirm the key actually decrypts the file. On a brand-new vault
        // this query trivially succeeds; on an existing vault opened with the
        // wrong key, SQLCipher reports the pages as "not a database".
        if sqlite3_exec(db, "SELECT count(*) FROM sqlite_master;", nil, nil, nil) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
            throw HistoryStoreError.wrongKey
        }

        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    /// Idempotent schema creation. `entries` holds the rows; `entries_fts` is
    /// an external-content FTS5 index kept in sync by triggers, so full-text
    /// search never duplicates the (encrypted) transcript text.
    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS entries (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                text        TEXT    NOT NULL,
                created_at  REAL    NOT NULL,
                source_app  TEXT,
                char_count  INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_entries_created_at
                ON entries (created_at DESC);

            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5 (
                text,
                content='entries',
                content_rowid='id'
            );

            CREATE TRIGGER IF NOT EXISTS entries_after_insert
            AFTER INSERT ON entries BEGIN
                INSERT INTO entries_fts (rowid, text) VALUES (new.id, new.text);
            END;

            CREATE TRIGGER IF NOT EXISTS entries_after_delete
            AFTER DELETE ON entries BEGIN
                INSERT INTO entries_fts (entries_fts, rowid, text)
                    VALUES ('delete', old.id, old.text);
            END;
            """)
    }

    // MARK: - Writes

    /// Append a finalized transcription. `sourceApp` is the frontmost app's
    /// localized name, captured by `AppCoordinator` at hotkey-press.
    @discardableResult
    func insert(text: String, sourceApp: String?) throws -> HistoryRecord {
        let createdAt = Date()
        let sql = "INSERT INTO entries (text, created_at, source_app, char_count) VALUES (?, ?, ?, ?);"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, text, -1, Self.transient)
        sqlite3_bind_double(statement, 2, createdAt.timeIntervalSince1970)
        if let sourceApp {
            sqlite3_bind_text(statement, 3, sourceApp, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_int(statement, 4, Int32(text.count))

        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        return HistoryRecord(id: sqlite3_last_insert_rowid(db),
                             text: text,
                             createdAt: createdAt,
                             sourceApp: sourceApp,
                             charCount: text.count)
    }

    /// Delete every entry. The FTS index is cleared by the delete triggers.
    func clearAll() throws {
        try exec("DELETE FROM entries;")
    }

    /// Apply a retention policy, deleting whatever falls outside it. Returns
    /// the number of rows removed. `keepForever` is a no-op.
    @discardableResult
    func prune(policy: RetentionPolicy) throws -> Int {
        switch policy {
        case .keepForever:
            return 0

        case .maxAge(let days):
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let statement = try prepare("DELETE FROM entries WHERE created_at < ?;")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }

        case .maxEntries(let limit):
            // Keep the newest `limit` rows; delete the rest.
            let statement = try prepare("""
                DELETE FROM entries WHERE id NOT IN (
                    SELECT id FROM entries ORDER BY created_at DESC LIMIT ?
                );
                """)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
        return Int(sqlite3_changes(db))
    }

    // MARK: - Reads

    /// The most recent `limit` entries, newest first.
    func recent(limit: Int = 200) throws -> [HistoryRecord] {
        let statement = try prepare("""
            SELECT id, text, created_at, source_app, char_count
            FROM entries ORDER BY created_at DESC LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        return try readAll(statement)
    }

    /// Full-text search, newest match first. An empty/whitespace query falls
    /// back to `recent(limit:)`.
    func search(_ query: String, limit: Int = 200) throws -> [HistoryRecord] {
        guard let match = Self.ftsQuery(for: query) else {
            return try recent(limit: limit)
        }
        let statement = try prepare("""
            SELECT e.id, e.text, e.created_at, e.source_app, e.char_count
            FROM entries e
            JOIN entries_fts f ON f.rowid = e.id
            WHERE entries_fts MATCH ?
            ORDER BY e.created_at DESC LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, match, -1, Self.transient)
        sqlite3_bind_int(statement, 2, Int32(limit))
        return try readAll(statement)
    }

    /// Total entry count.
    func count() throws -> Int {
        let statement = try prepare("SELECT count(*) FROM entries;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: - FTS query building

    /// Turn raw user input into a safe FTS5 `MATCH` expression. Each token is
    /// double-quoted (so punctuation can't break FTS5's query grammar) and
    /// given a `*` suffix for search-as-you-type prefix matching; tokens are
    /// ANDed. Returns nil for an empty query.
    private static func ftsQuery(for raw: String) -> String? {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: - SQLite plumbing

    /// Run a statement (or several) that returns no rows.
    private func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw HistoryStoreError.sql(message)
        }
    }

    /// Compile a single SQL statement, ready for binding + stepping.
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw lastError()
        }
        return statement
    }

    /// Step a SELECT to completion, decoding each row into a `HistoryRecord`.
    /// Column order must match the `SELECT` lists above.
    private func readAll(_ statement: OpaquePointer) throws -> [HistoryRecord] {
        var records: [HistoryRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let id = sqlite3_column_int64(statement, 0)
                let text = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                let sourceApp = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let charCount = Int(sqlite3_column_int(statement, 4))
                records.append(HistoryRecord(id: id, text: text, createdAt: createdAt,
                                             sourceApp: sourceApp, charCount: charCount))
            case SQLITE_DONE:
                return records
            default:
                throw lastError()
            }
        }
    }

    /// The connection's last error, wrapped.
    private func lastError() -> HistoryStoreError {
        .sql(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }
}
