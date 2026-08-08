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
    /// Which attachment of the event this row describes. A gallery sends several under one
    /// event ID, so the index keys on this alongside it; everything else stays at zero.
    var mediaIndex = 0
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
    
    /// Attachment metadata, for showing a library row without fetching the media. All nil on
    /// events that carry no attachment, and on rows indexed before these were recorded.
    var fileSize: UInt?
    var width: Int?
    var height: Int?
    var duration: TimeInterval?
    /// A recorded voice note rather than an audio file that happens to be attached. The two
    /// share a MIME type, so this is the only thing that separates them.
    var isVoiceMessage = false
    /// `mxc://` URI of the attachment, and of its thumbnail where the sender provided one.
    /// Stored so the library can render a grid without asking the server what these events were.
    var mediaSource: String?
    var thumbnailSource: String?
}

/// What the library shows a row as. Derived rather than stored: `kind` and `mimeType` already
/// carry enough to tell these apart, and deriving means a wrong rule is fixed by shipping code
/// instead of reindexing every row.
nonisolated enum MediaCategory: String, CaseIterable, Sendable {
    case photo
    case video
    case gif
    case file
    case link
    case voice
    
    init?(kind: SearchIndexEventKind, mimeType: String?, isVoiceMessage: Bool) {
        switch kind {
        case .message:
            return nil
        case .link:
            self = .link
        case .file:
            self = .file
        case .media:
            guard let mimeType else {
                // An attachment we couldn't type. Filing it under files keeps it reachable
                // rather than dropping it out of the library entirely.
                self = .file
                return
            }
            
            if isVoiceMessage {
                self = .voice
            } else if mimeType == "image/gif" {
                self = .gif
            } else if mimeType.hasPrefix("image/") {
                self = .photo
            } else if mimeType.hasPrefix("video/") {
                self = .video
            } else if mimeType.hasPrefix("audio/") {
                self = .file
            } else {
                self = .file
            }
        }
    }
    
    /// Categories laid out in a grid rather than a list.
    var isVisual: Bool {
        switch self {
        case .photo, .video, .gif: true
        case .file, .link, .voice: false
        }
    }
}

/// Browsing rather than searching: no text, ordered newest first. The library needs this
/// because `search` goes through FTS and returns nothing for an empty query.
struct SearchIndexBrowseQuery: Equatable, Sendable {
    var categories: Set<MediaCategory> = []
    var roomID: String?
    var senderID: String?
    /// Inclusive lower bound, for the date filter.
    var after: Date?
    /// Exclusive upper bound.
    var before: Date?
    var limit = 100
    var offset = 0
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
    
    /// Newest-first browse over attachments, for the media library. Unlike `search` this
    /// doesn't touch FTS, so it works with no query text at all.
    func browse(_ query: SearchIndexBrowseQuery) async throws -> [SearchIndexEntry]
    
    /// Every room holding something in these categories. Asked of the index rather than
    /// worked out from a page of results, which only knows about what's been scrolled to.
    func rooms(withMediaIn categories: Set<MediaCategory>) async throws -> [String]
    
    /// Number of indexed events, for diagnostics and tests.
    func count() async throws -> Int
    
    /// Empties the index without deleting the file.
    /// The newest indexed event's timestamp for a room, or nil when it has none.
    func latestTimestamp(inRoom roomID: String) async throws -> Date?
    
    func clear() async throws
    
    // MARK: - History download progress
    
    /// Per-room download progress. Stored alongside the index because it describes
    /// how complete the index is, and the two must be discarded together.
    func roomHistoryStates() async throws -> [String: RoomHistoryState]
    
    func setRoomHistoryState(_ state: RoomHistoryState) async throws
    
    /// Bytes the index occupies on disk, including its write-ahead log.
    func databaseSize() async -> Int64
}
