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

private nonisolated extension Character {
    /// Scripts written without spaces between words, where the tokeniser can't find
    /// word boundaries on its own.
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || // CJK Unified Ideographs
            (0x3400...0x4DBF).contains(scalar.value) || // Extension A
            (0xF900...0xFAFF).contains(scalar.value) || // Compatibility Ideographs
            (0x3040...0x30FF).contains(scalar.value) || // Hiragana and Katakana
            (0xAC00...0xD7AF).contains(scalar.value) // Hangul syllables
    }
}

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
    /// Internal rather than private so a backup can record which schema its copy of
    /// the index was written with, and refuse to restore a newer one.
    nonisolated static let schemaVersion = 4
    
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
                 message_body, filename, mime_type, url, thread_root_id,
                 file_size, width, height, duration, is_voice_message,
                 media_source, thumbnail_source,
                 message_body_segmented, filename_segmented, sender_display_name_segmented)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
                sender_display_name = excluded.sender_display_name,
                timestamp = excluded.timestamp,
                kind = excluded.kind,
                message_body = excluded.message_body,
                filename = excluded.filename,
                mime_type = excluded.mime_type,
                url = excluded.url,
                thread_root_id = excluded.thread_root_id,
                file_size = excluded.file_size,
                width = excluded.width,
                height = excluded.height,
                duration = excluded.duration,
                is_voice_message = excluded.is_voice_message,
                media_source = excluded.media_source,
                thumbnail_source = excluded.thumbnail_source,
                message_body_segmented = excluded.message_body_segmented,
                filename_segmented = excluded.filename_segmented,
                sender_display_name_segmented = excluded.sender_display_name_segmented
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
                bind(entry.fileSize.map(Int64.init), to: statement, at: 12)
                bind(entry.width.map(Int64.init), to: statement, at: 13)
                bind(entry.height.map(Int64.init), to: statement, at: 14)
                bind(entry.duration.map { Int64($0 * 1000) }, to: statement, at: 15)
                sqlite3_bind_int64(statement, 16, entry.isVoiceMessage ? 1 : 0)
                bind(entry.mediaSource, to: statement, at: 17)
                bind(entry.thumbnailSource, to: statement, at: 18)
                // The searchable copies. Segmenting on write means the query only has
                // to segment itself the same way to line up.
                bind(entry.body.map(Self.segmented), to: statement, at: 19)
                bind(entry.filename.map(Self.segmented), to: statement, at: 20)
                bind(entry.senderDisplayName.map(Self.segmented), to: statement, at: 21)
                
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
    
    /// The newest event indexed for a room, used as a watermark so live updates only
    /// write what's actually new rather than re-indexing the whole loaded timeline.
    func latestTimestamp(inRoom roomID: String) async throws -> Date? {
        let database = try connection()
        let statement = try prepare("SELECT MAX(timestamp) FROM events WHERE room_id = ?", on: database)
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, roomID, -1, sqliteTransient)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
        // NULL for a room with nothing indexed, which reads as 0 here.
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) / 1000)
    }
    
    func browse(_ query: SearchIndexBrowseQuery) async throws -> [SearchIndexEntry] {
        let database = try connection()
        
        // Kinds rather than categories, because kind is what's stored and indexed. Photos,
        // videos and GIFs all live under `media`, so they're separated afterwards in Swift
        // using the same rule the rest of the app derives categories with.
        let kinds = query.categories.reduce(into: Set<SearchIndexEventKind>()) { kinds, category in
            kinds.formUnion(Self.kinds(for: category))
        }
        
        var sql = """
        SELECT event_id, room_id, sender_id, sender_display_name, timestamp, kind,
               message_body, filename, mime_type, url, thread_root_id,
               file_size, width, height, duration, is_voice_message,
               media_source, thumbnail_source
        FROM events
        WHERE kind != 'message'
        """
        if !kinds.isEmpty {
            sql += " AND kind IN (\(kinds.map { "'\($0.rawValue)'" }.sorted().joined(separator: ", ")))"
        }
        if query.senderID != nil {
            sql += " AND sender_id = ?"
        }
        if query.after != nil {
            sql += " AND timestamp >= ?"
        }
        if query.before != nil {
            sql += " AND timestamp < ?"
        }
        sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
        
        let statement = try prepare(sql, on: database)
        defer { sqlite3_finalize(statement) }
        
        var position: Int32 = 1
        if let senderID = query.senderID {
            bind(senderID, to: statement, at: position)
            position += 1
        }
        for date in [query.after, query.before].compacted() {
            bind(Int64(date.timeIntervalSince1970 * 1000), to: statement, at: position)
            position += 1
        }
        sqlite3_bind_int(statement, position, Int32(query.limit))
        sqlite3_bind_int(statement, position + 1, Int32(query.offset))
        
        var entries: [SearchIndexEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = entry(from: statement) else { continue }
            
            // The category filter is finished here rather than in SQL, since telling a photo
            // from a video from a GIF means reading the MIME type.
            if !query.categories.isEmpty {
                guard let category = MediaCategory(kind: entry.kind,
                                                   mimeType: entry.mimeType,
                                                   isVoiceMessage: entry.isVoiceMessage),
                    query.categories.contains(category) else {
                    continue
                }
            }
            
            entries.append(entry)
        }
        
        return entries
    }
    
    /// The stored kinds a category can come from. Deliberately a superset: this only narrows
    /// what SQL reads, and the exact category is decided afterwards from the MIME type.
    ///
    /// `.file` spans both stored kinds. An audio file or an attachment we couldn't type is
    /// stored as `.media` but belongs under files, so restricting to `kind = 'file'` here
    /// would hide it before the category check ever ran.
    private nonisolated static func kinds(for category: MediaCategory) -> Set<SearchIndexEventKind> {
        switch category {
        case .photo, .video, .gif, .voice: [.media]
        case .file: [.file, .media]
        case .link: [.link]
        }
    }
    
    private func entry(from statement: OpaquePointer?) -> SearchIndexEntry? {
        guard let eventID = string(from: statement, at: 0),
              let roomID = string(from: statement, at: 1),
              let senderID = string(from: statement, at: 2),
              let kind = string(from: statement, at: 5).flatMap(SearchIndexEventKind.init(rawValue:)) else {
            return nil
        }
        
        return SearchIndexEntry(eventID: eventID,
                                roomID: roomID,
                                senderID: senderID,
                                senderDisplayName: string(from: statement, at: 3),
                                timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1000),
                                kind: kind,
                                body: string(from: statement, at: 6),
                                filename: string(from: statement, at: 7),
                                mimeType: string(from: statement, at: 8),
                                url: string(from: statement, at: 9),
                                threadRootID: string(from: statement, at: 10),
                                fileSize: integer(from: statement, at: 11).map(UInt.init),
                                width: integer(from: statement, at: 12).map(Int.init),
                                height: integer(from: statement, at: 13).map(Int.init),
                                duration: integer(from: statement, at: 14).map { Double($0) / 1000 },
                                isVoiceMessage: sqlite3_column_int64(statement, 15) == 1,
                                mediaSource: string(from: statement, at: 16),
                                thumbnailSource: string(from: statement, at: 17))
    }
    
    func clear() async throws {
        let database = try connection()
        try execute("DELETE FROM events", on: database)
        try execute("DELETE FROM room_history_state", on: database)
    }
    
    // MARK: - History download progress
    
    func roomHistoryStates() async throws -> [String: RoomHistoryState] {
        let database = try connection()
        let statement = try prepare("""
        SELECT room_id, status, messages_indexed, estimated_total, last_updated
        FROM room_history_state
        """, on: database)
        defer { sqlite3_finalize(statement) }
        
        var states: [String: RoomHistoryState] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let roomID = string(from: statement, at: 0),
                  let status = string(from: statement, at: 1).flatMap(RoomHistoryState.Status.init(rawValue:)) else {
                continue
            }
            
            states[roomID] = RoomHistoryState(roomID: roomID,
                                              status: status,
                                              messagesIndexed: Int(sqlite3_column_int64(statement, 2)),
                                              estimatedTotal: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 3)),
                                              lastUpdated: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1000))
        }
        return states
    }
    
    func setRoomHistoryState(_ state: RoomHistoryState) async throws {
        let database = try connection()
        let statement = try prepare("""
        INSERT INTO room_history_state (room_id, status, messages_indexed, estimated_total, last_updated)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(room_id) DO UPDATE SET
            status = excluded.status,
            messages_indexed = excluded.messages_indexed,
            estimated_total = excluded.estimated_total,
            last_updated = excluded.last_updated
        """, on: database)
        defer { sqlite3_finalize(statement) }
        
        bind(state.roomID, to: statement, at: 1)
        bind(state.status.rawValue, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, Int64(state.messagesIndexed))
        if let total = state.estimatedTotal {
            sqlite3_bind_int64(statement, 4, Int64(total))
        } else {
            sqlite3_bind_null(statement, 4)
        }
        if let updated = state.lastUpdated {
            sqlite3_bind_int64(statement, 5, Int64(updated.timeIntervalSince1970 * 1000))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchIndexError.query(lastErrorMessage(database))
        }
    }
    
    func databaseSize() async -> Int64 {
        // The write-ahead log can hold a meaningful share of the data, so counting the
        // main file alone would understate what's actually on disk.
        [databaseURL,
         databaseURL.appendingPathExtension("wal"),
         databaseURL.appendingPathExtension("shm")]
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0.path(percentEncoded: false))[.size] as? Int64 }
            .reduce(0, +)
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
    ///
    /// Terms are segmented the same way the indexed text was, so a term buried in a
    /// run of CJK still lines up with the tokens actually stored.
    nonisolated static func matchExpression(for terms: [String]) -> String {
        terms
            .map { term in
                segmented(term)
                    .split(separator: " ")
                    .map { "\"\($0)\"*" }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    /// Pads every CJK character with spaces so `unicode61` treats each as its own token.
    ///
    /// Without this the tokeniser sees a whole unspaced run as a single term: an entire
    /// Chinese sentence with an English word inside it becomes one token, and neither
    /// the English word nor any Chinese word within it can be matched. Splitting per
    /// character also beats the `trigram` tokeniser here, which can't match the
    /// two-character words that make up much of written Chinese.
    nonisolated static func segmented(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count * 2)
        
        for character in text {
            if character.isCJK {
                result.append(" ")
                result.append(character)
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
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
                          "DROP TABLE IF EXISTS events",
                          "DROP TABLE IF EXISTS room_history_state"] {
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
            thread_root_id TEXT,
            -- Attachment metadata, so a library row renders without fetching the media.
            file_size INTEGER,
            width INTEGER,
            height INTEGER,
            duration INTEGER,
            is_voice_message INTEGER NOT NULL DEFAULT 0,
            media_source TEXT,
            thumbnail_source TEXT,
            -- Indexed copies, CJK split per character. Kept apart from the columns
            -- above so what's searched and what's shown can differ.
            message_body_segmented TEXT,
            filename_segmented TEXT,
            sender_display_name_segmented TEXT
        )
        """, on: database)
        
        try execute("""
        CREATE TABLE IF NOT EXISTS room_history_state (
            room_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            messages_indexed INTEGER NOT NULL DEFAULT 0,
            estimated_total INTEGER,
            last_updated INTEGER
        )
        """, on: database)
        
        try execute("CREATE INDEX IF NOT EXISTS events_room_idx ON events(room_id)", on: database)
        try execute("CREATE INDEX IF NOT EXISTS events_timestamp_idx ON events(timestamp DESC)", on: database)
        // Browsing filters on kind and orders by time, so the two together earn an index.
        try execute("CREATE INDEX IF NOT EXISTS events_kind_timestamp_idx ON events(kind, timestamp DESC)", on: database)
        
        // External content: the FTS table stores only the terms and points back at
        // `events` by rowid, so metadata isn't duplicated and deleting an event by
        // ID stays an indexed lookup rather than a scan of the FTS table.
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
            message_body_segmented,
            filename_segmented,
            url,
            sender_display_name_segmented,
            content = 'events',
            content_rowid = 'rowid',
            tokenize = 'unicode61 remove_diacritics 2'
        )
        """, on: database)
        
        // External content tables aren't kept in step automatically.
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_insert AFTER INSERT ON events BEGIN
            INSERT INTO events_fts(rowid, message_body_segmented, filename_segmented, url, sender_display_name_segmented)
            VALUES (new.rowid, new.message_body_segmented, new.filename_segmented, new.url, new.sender_display_name_segmented);
        END
        """, on: database)
        
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_delete AFTER DELETE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, message_body_segmented, filename_segmented, url, sender_display_name_segmented)
            VALUES ('delete', old.rowid, old.message_body_segmented, old.filename_segmented, old.url, old.sender_display_name_segmented);
        END
        """, on: database)
        
        try execute("""
        CREATE TRIGGER IF NOT EXISTS events_after_update AFTER UPDATE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, message_body_segmented, filename_segmented, url, sender_display_name_segmented)
            VALUES ('delete', old.rowid, old.message_body_segmented, old.filename_segmented, old.url, old.sender_display_name_segmented);
            INSERT INTO events_fts(rowid, message_body_segmented, filename_segmented, url, sender_display_name_segmented)
            VALUES (new.rowid, new.message_body_segmented, new.filename_segmented, new.url, new.sender_display_name_segmented);
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
    
    private func bind(_ value: Int64?, to statement: OpaquePointer?, at index: Int32) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
    
    /// Nil rather than zero when the column was never written, so "no duration recorded"
    /// stays distinguishable from "zero seconds long".
    private func integer(from statement: OpaquePointer?, at column: Int32) -> Int64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, column)
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
