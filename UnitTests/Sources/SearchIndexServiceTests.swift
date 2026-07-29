//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct SearchIndexServiceTests {
    /// Each test gets its own file so they can't observe one another's rows.
    private func makeService() -> SearchIndexService {
        let url = URL.temporaryDirectory
            .appending(component: "search-index-tests", directoryHint: .isDirectory)
            .appending(component: "\(UUID().uuidString).sqlite3")
        return SearchIndexService(databaseURL: url)
    }
    
    private func makeEntry(eventID: String = "$event",
                           roomID: String = "!room:example.com",
                           kind: SearchIndexEventKind = .message,
                           body: String? = "Can we have the meeting tomorrow?",
                           filename: String? = nil,
                           url: String? = nil) -> SearchIndexEntry {
        SearchIndexEntry(eventID: eventID,
                         roomID: roomID,
                         senderID: "@john:example.com",
                         senderDisplayName: "John",
                         timestamp: .init(timeIntervalSince1970: 1_700_000_000),
                         kind: kind,
                         body: body,
                         filename: filename,
                         mimeType: nil,
                         url: url,
                         threadRootID: nil)
    }
    
    // MARK: - Indexing
    
    @Test
    func indexingAndSearchingAMessage() async throws {
        let service = makeService()
        try await service.index([makeEntry()])
        
        let results = try await service.search(.init(text: "meeting"))
        
        #expect(results.count == 1)
        #expect(results.first?.entry.eventID == "$event")
        #expect(try await service.count() == 1)
    }
    
    @Test
    func searchingMatchesPrefixesSoResultsArriveWhileTyping() async throws {
        let service = makeService()
        try await service.index([makeEntry()])
        
        // "meet" should already find "meeting" — otherwise nothing appears until the
        // user finishes the word.
        #expect(try await service.search(.init(text: "meet")).count == 1)
    }
    
    @Test
    func searchingIsCaseAndDiacriticInsensitive() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "Café closes at noon")])
        
        #expect(try await service.search(.init(text: "CAFE")).count == 1)
    }
    
    @Test
    func indexingTheSameEventTwiceUpdatesItRatherThanDuplicating() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "original wording")])
        try await service.index([makeEntry(body: "edited wording")])
        
        #expect(try await service.count() == 1)
        #expect(try await service.search(.init(text: "original")).isEmpty)
        #expect(try await service.search(.init(text: "edited")).count == 1)
    }
    
    @Test
    func allTermsMustMatch() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "lunch tomorrow")])
        
        #expect(try await service.search(.init(text: "lunch tomorrow")).count == 1)
        #expect(try await service.search(.init(text: "lunch yesterday")).isEmpty)
    }
    
    // MARK: - Filters
    
    @Test
    func filteringByKind() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$a", kind: .message, body: "budget review"),
                                 makeEntry(eventID: "$b", kind: .file, body: nil, filename: "budget.xlsx")])
        
        #expect(try await service.search(.init(text: "budget")).count == 2)
        #expect(try await service.search(.init(text: "budget", kind: .file)).count == 1)
        #expect(try await service.search(.init(text: "budget", kind: .file)).first?.entry.eventID == "$b")
    }
    
    @Test
    func filteringByRoom() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$a", roomID: "!one:example.com"),
                                 makeEntry(eventID: "$b", roomID: "!two:example.com")])
        
        let results = try await service.search(.init(text: "meeting", roomID: "!two:example.com"))
        #expect(results.count == 1)
        #expect(results.first?.entry.roomID == "!two:example.com")
    }
    
    @Test
    func searchingFilenamesAndLinks() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$a", kind: .file, body: nil, filename: "invoice-2026.pdf"),
                                 makeEntry(eventID: "$b", kind: .link, body: "have a look", url: "https://github.com/element-hq")])
        
        #expect(try await service.search(.init(text: "invoice")).count == 1)
        #expect(try await service.search(.init(text: "github")).count == 1)
    }
    
    // MARK: - Removal
    
    @Test
    func removingByEventID() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$a"), makeEntry(eventID: "$b")])
        
        try await service.remove(eventIDs: ["$a"])
        
        let results = try await service.search(.init(text: "meeting"))
        #expect(results.count == 1)
        #expect(results.first?.entry.eventID == "$b")
    }
    
    @Test
    func removingAnEntireRoom() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$a", roomID: "!one:example.com"),
                                 makeEntry(eventID: "$b", roomID: "!two:example.com")])
        
        try await service.removeAll(inRoom: "!one:example.com")
        
        #expect(try await service.count() == 1)
        #expect(try await service.search(.init(text: "meeting")).first?.entry.roomID == "!two:example.com")
    }
    
    @Test
    func clearingEmptiesTheIndex() async throws {
        let service = makeService()
        try await service.index([makeEntry()])
        
        try await service.clear()
        
        #expect(try await service.count() == 0)
        #expect(try await service.search(.init(text: "meeting")).isEmpty)
    }
    
    // MARK: - Query handling
    
    @Test
    func queryTextCannotInjectFTSSyntax() async throws {
        let service = makeService()
        try await service.index([makeEntry()])
        
        // These are all FTS5 operators. Unquoted they'd either throw or match
        // something the user didn't ask for.
        for text in ["meeting OR tomorrow", "\"meeting", "meeting NEAR/2 tomorrow", "meeting*(", "^meeting"] {
            _ = try await service.search(.init(text: text))
        }
    }
    
    @Test
    func emptyQueriesReturnNothingRatherThanEverything() async throws {
        let service = makeService()
        try await service.index([makeEntry()])
        
        #expect(try await service.search(.init(text: "")).isEmpty)
        #expect(try await service.search(.init(text: "   ")).isEmpty)
    }
    
    @Test
    func resultsCarryTheRangesToHighlight() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "Meeting now, meeting later")])
        
        let result = try #require(try await service.search(.init(text: "meeting")).first)
        let body = try #require(result.entry.body)
        
        #expect(result.bodyMatches.count == 2)
        #expect(result.bodyMatches.allSatisfy { body[$0].lowercased() == "meeting" })
    }
    
    // MARK: - Persistence
    
    @Test
    func theIndexSurvivesBeingReopened() async throws {
        let url = URL.temporaryDirectory
            .appending(component: "search-index-tests", directoryHint: .isDirectory)
            .appending(component: "\(UUID().uuidString).sqlite3")
        
        let first = SearchIndexService(databaseURL: url)
        try await first.index([makeEntry()])
        
        // The whole point of an on-disk index: a relaunch keeps the history searchable.
        let second = SearchIndexService(databaseURL: url)
        #expect(try await second.search(.init(text: "meeting")).count == 1)
    }
}
