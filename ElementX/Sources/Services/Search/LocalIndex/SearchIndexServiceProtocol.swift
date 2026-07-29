//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SearchIndexError: Error {
    /// The database couldn't be opened or the schema couldn't be created.
    case unavailable(String)
    /// A statement failed. Carries SQLite's own message, which names the column or constraint.
    case query(String)
}

/// What kind of event a row describes. Drives the search filters and is stored
/// verbatim, so don't renumber the raw values without migrating the index.
enum SearchIndexEventKind: String, Codable, CaseIterable, Sendable {
    case message
    case media
    case file
    case link
}

/// An event flattened into the fields worth searching. Deliberately free of any
/// `MatrixRustSDK` type so the index doesn't depend on the SDK's shape.
struct SearchIndexEntry: Equatable, Sendable {
    let eventID: String
    let roomID: String
    let senderID: String
    let senderDisplayName: String?
    let timestamp: Date
    let kind: SearchIndexEventKind
    /// The message text, or a caption where the event carries one.
    let body: String?
    let filename: String?
    let mimeType: String?
    /// Any URL found in the body, so links stay searchable by host.
    let url: String?
    let threadRootID: String?
}

/// Narrows a query. `.all` matches every kind.
enum SearchIndexFilter: Equatable, Sendable {
    case all
    case kind(SearchIndexEventKind)
    /// Restricts results to a single room. Combines with `kind` via `SearchIndexQuery`.
    case room(String)
}

struct SearchIndexQuery: Equatable, Sendable {
    let text: String
    var roomID: String?
    var kind: SearchIndexEventKind?
    var limit = 100
    var offset = 0
}

/// A hit, with the ranges the query matched so the UI can highlight them without
/// re-running the match itself.
struct SearchIndexResult: Equatable, Sendable {
    let entry: SearchIndexEntry
    /// Ranges within `entry.body` that matched. Empty when the hit came from a
    /// filename or URL rather than the body.
    let bodyMatches: [Range<String.Index>]
    /// Lower is better, straight from FTS5's bm25().
    let rank: Double
}

// sourcery: AutoMockable
protocol SearchIndexServiceProtocol: Sendable {
    /// Adds or replaces entries. Existing rows with the same event ID are overwritten,
    /// which is what makes re-indexing an edited event safe to call repeatedly.
    func index(_ entries: [SearchIndexEntry]) async throws
    
    /// Drops entries by event ID, for redactions.
    func remove(eventIDs: [String]) async throws
    
    /// Drops everything belonging to a room, for leaves and forgets.
    func removeAll(inRoom roomID: String) async throws
    
    func search(_ query: SearchIndexQuery) async throws -> [SearchIndexResult]
    
    /// Number of indexed events, for diagnostics and tests.
    func count() async throws -> Int
    
    /// Empties the index without deleting the file.
    func clear() async throws
}
