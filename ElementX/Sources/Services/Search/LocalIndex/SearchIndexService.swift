//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SQLite3

/// SQLite tells us whether it may keep the pointer we bind or must copy it. Swift
/// doesn't import these macros, so they're restated here.
private nonisolated let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A local full text index over timeline events, backed by SQLite's FTS5.
///
/// An actor rather than a queue because every entry point touches the same
/// connection, and SQLite wants its statements serialised.
actor SearchIndexService: SearchIndexServiceProtocol {
    private let databaseURL: URL
    private var database: OpaquePointer?
    
    /// Bumped whenever the schema changes so a stale index is discarded rather
    /// than queried with the wrong columns. The index is derived data, so
    /// throwing it away costs only the re-indexing.
    private nonisolated static let schemaVersion = 1
    
    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }
    
    /// Isolated so it can reach the connection: the handle isn't `Sendable`, so a
    /// nonisolated deinit isn't allowed to touch it.
    isolated deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }
    
    // MARK: - SearchIndexServiceProtocol
    
    func index(_ entries: [SearchIndexEntry]) async throws {
        guard !entries.isEmpty else { return }
        let database = try connection()
        
        try execute("BEGIN IMMEDIATE", on: database)
        do {
            // ON CONFLICT keeps re-indexing an edited event idempotent, and fires the
            // update trigger so the FTS side stays in step.
            let sql = """
            INSERT INTO events
                (event_id, room_id, sender_id, sender_display_name, timestamp, kind,
                 message_body, filename, mime_type, url, thread_root_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
                sender_display_name = excluded.sender_display_name,
                timestamp = excluded.timestamp,
                kind = excluded.kind,
                message_body = excluded.message_body,
                filename = excluded.filename,
                mime_type = excluded.mime_type,
                url = excluded.url,
                thread_root_id = excluded.thread_root_id
            """
            let statement = try prepare(sql, on: database)
            defer { sqlite3_finalize(statement) }
            
            for entry in entries {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(entry.eventID, to: statement, at: 1)
                bind(entry.roomID, to: statement, at: 2)
                bind(entry.senderID, to: statement, at: 3)
                bind(entry.senderDisplayName, to: statement, at: 4)
                sqlite3_bind_int64(statement, 5, Int64(entry.timestamp.timeIntervalSince1970 * 1000))
                bind(entry.kind.rawValue, to: statement, at: 6)
                bind(entry.body, to: statement, at: 7)
                bind(entry.filename, to: statement, at: 8)
                bind(entry.mimeType, to: statement, at: 9)
                bind(entry.url, to: statement, at: 10)
                bind(entry.threadRootID, to: statement, at: 11)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SearchIndexError.query(lastErrorMessage(database))
                }
            }
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
        try execute("COMMIT", on: database)
    }
    
    func remove(eventIDs: [String]) async throws {
        guard !eventIDs.isEmpty else { return }
        let database = try connection()
        
        let statement = try prepare("DELETE FROM events WHERE event_id = ?", on: database)
        defer { sqlite3_finalize(statement) }
        
        try execute("BEGIN IMMEDIATE", on: database)
        for eventID in eventIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(eventID, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                try? execute("ROLLBACK", on: database)
                throw SearchIndexError.query(lastErrorMessage(database))
            }
        }
        try execute("COMMIT", on: database)
    }
    
    func removeAll(inRoom roomID: String) async throws {
        let database = try connection()
        let statement = try prepare("DELETE FROM events WHERE room_id = ?", on: database)
        defer { sqlite3_finalize(statement) }
        
        bind(roomID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
    }
    
    func search(_ query: SearchIndexQuery) async throws -> [SearchIndexResult] {
        let terms = Self.terms(in: query.text)
        guard !terms.isEmpty else { return [] }
        
        let database = try connection()
        
        var sql = """
        SELECT e.event_id, e.room_id, e.sender_id, e.sender_display_name, e.timestamp, e.kind,
               e.message_body, e.filename, e.mime_type, e.url, e.thread_root_id,
               bm25(events_fts) AS rank
        FROM events_fts
        JOIN events e ON e.rowid = events_fts.rowid
        WHERE events_fts MATCH ?
        """
        if query.roomID != nil {
            sql += " AND e.room_id = ?"
        }
        if query.kind != nil {
            sql += " AND e.kind = ?"
        }
        // bm25 is negative and more negative is better, so plain ascending order is
        // best first. Ties fall back to newest.
        sql += " ORDER BY rank ASC, e.timestamp DESC LIMIT ? OFFSET ?"
        
        let statement = try prepare(sql, on: database)
        defer { sqlite3_finalize(statement) }
        
        var position: Int32 = 1
        bind(Self.matchExpression(for: terms), to: statement, at: position)
        position += 1
        if let roomID = query.roomID {
            bind(roomID, to: statement, at: position)
            position += 1
        }
        if let kind = query.kind {
            bind(kind.rawValue, to: statement, at: position)
            position += 1
        }
        sqlite3_bind_int(statement, position, Int32(query.limit))
        sqlite3_bind_int(statement, position + 1, Int32(query.offset))
        
        var results: [SearchIndexResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let eventID = string(from: statement, at: 0),
                  let roomID = string(from: statement, at: 1),
                  let senderID = string(from: statement, at: 2),
                  let kind = string(from: statement, at: 5).flatMap(SearchIndexEventKind.init(rawValue:)) else {
                continue
            }
            
            let body = string(from: statement, at: 6)
            let entry = SearchIndexEntry(eventID: eventID,
                                         roomID: roomID,
                                         senderID: senderID,
                                         senderDisplayName: string(from: statement, at: 3),
                                         timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1000),
                                         kind: kind,
                                         body: body,
                                         filename: string(from: statement, at: 7),
                                         mimeType: string(from: statement, at: 8),
                                         url: string(from: statement, at: 9),
                                         threadRootID: string(from: statement, at: 10))
            
            results.append(SearchIndexResult(entry: entry,
                                             bodyMatches: Self.matchRanges(of: terms, in: body),
                                             rank: sqlite3_column_double(statement, 11)))
        }
        return results
    }
    
    func count() async throws -> Int {
        let database = try connection()
        let statement = try prepare("SELECT COUNT(*) FROM events", on: database)
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    func clear() async throws {
        let database = try connection()
        try execute("DELETE FROM events", on: database)
    }
    
    // MARK: - Query parsing
    
    /// Splits user input into terms, dropping punctuation that would otherwise be
    /// read as FTS5 syntax.
    nonisolated static func terms(in text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.union(.punctuationCharacters).inverted) }
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
    }
    
    /// Builds the MATCH expression. Every term is quoted so the user can't inject
    /// FTS5 operators, and given a prefix wildcard so results arrive while typing.
    nonisolated static func matchExpression(for terms: [String]) -> String {
        terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }
    
    /// Locates each term in the body so the UI can highlight without matching again.
    nonisolated static func matchRanges(of terms: [String], in body: String?) -> [Range<String.Index>] {
        guard let body, !body.isEmpty else { return [] }
        
        var ranges: [Range<String.Index>] = []
        for term in terms {
            var searchStart = body.startIndex
            while searchStart < body.endIndex,
                  let found = body.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<body.endIndex) {
                ranges.append(found)
                searchStart = found.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
    
    // MARK: - Database
    
    private func connection() throws -> OpaquePointer {
        if let database {
            return database
        }
        
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path(percentEncoded: false), &handle, flags, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map(lastErrorMessage) ?? "unknown"
            sqlite3_close_v2(handle)
            throw SearchIndexError.unavailable(message)
        }
        
        do {
            try configure(handle)
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }
        
        database = handle
        return handle
    }
    
    private func configure(_ database: OpaquePointer) throws {
        // WAL keeps readers from blocking the indexer. NORMAL is the usual pairing:
        // a crash can lose the last transactions, which for derived data is fine.
        try execute("PRAGMA journal_mode = WAL", on: database)
        try execute("PRAGMA synchronous = NORMAL", on: database)
        
        if try version(of: database) != Self.schemaVersion {
            try dropSchema(on: database)
        }
        try createSchema(on: database)
        try execute("PRAGMA user_version = \(Self.schemaVersion)", on: database)
    }
    
    private func version(of database: OpaquePointer) throws -> Int {
        let statement = try prepare("PRAGMA user_version", on: database)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    private func dropSchema(on database: OpaquePointer) throws {
        for statement in ["DROP TRIGGER IF EXISTS events_after_insert",
                          "DROP TRIGGER IF EXISTS events_after_delete",
                          "DROP TRIGGER IF EXISTS events_after_update",
                          "DROP TABLE IF EXISTS events_fts",
                          "DROP TABLE IF EXISTS events"] {
            try execute(statement, on: database)
        }
    }
    
    private func createSchema(on database: OpaquePointer) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS events (
            rowid INTEGER PRIMARY KEY,
            event_id TEXT NOT NULL UNIQUE,
            room_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            sender_display_name TEXT,
            timestamp INTEGER NOT NULL,
            kind TEXT NOT NULL,
            message_body TEXT,
            filename TEXT,
            mime_type TEXT,
            url TEXT,
            thread_root_id TEXT
        )
        """, on: database)
        
        try execute("CREATE INDEX IF NOT EXISTS events_room_idx ON events(room_id)", on: database)
        try execute("CREATE INDEX IF NOT EXISTS events_timestamp_idx ON events(timestamp DESC)", on: database)
        
        // External content: the FTS table stores only the terms and points back at
        // `events` by rowid, so metadata isn't duplicated and deleting an event by
        // ID stays an indexed lookup rather than a scan of the FTS table.
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
            message_body,
            filename,
            url,
            sender_display_name,
            content = 'events',
            content_rowid = 'rowid',
            tokenize = 'unicode61 remove_diacritics 2'
        )
        """, on: database)
        
        // External content tables aren't kept in step automatically.
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_insert AFTER INSERT ON events BEGIN
            INSERT INTO events_fts(rowid, message_body, filename, url, sender_display_name)
            VALUES (new.rowid, new.message_body, new.filename, new.url, new.sender_display_name);
        END
        """, on: database)
        
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_delete AFTER DELETE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, message_body, filename, url, sender_display_name)
            VALUES ('delete', old.rowid, old.message_body, old.filename, old.url, old.sender_display_name);
        END
        """, on: database)
        
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_update AFTER UPDATE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, message_body, filename, url, sender_display_name)
            VALUES ('delete', old.rowid, old.message_body, old.filename, old.url, old.sender_display_name);
            INSERT INTO events_fts(rowid, message_body, filename, url, sender_display_name)
            VALUES (new.rowid, new.message_body, new.filename, new.url, new.sender_display_name);
        END
        """, on: database)
    }
    
    // MARK: - SQLite helpers
    
    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
    }
    
    private func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
        return statement
    }
    
    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        if let value {
            // Transient: SQLite copies the bytes, so the Swift string needn't outlive the call.
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
    
    private func string(from statement: OpaquePointer?, at column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
    
    private func lastErrorMessage(_ database: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(database) else { return "unknown" }
        return String(cString: message)
    }
}
