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
                           url: String? = nil,
                           senderID: String = "@john:example.com",
                           timestamp: Date = .init(timeIntervalSince1970: 1_700_000_000),
                           mimeType: String? = nil,
                           fileSize: UInt? = nil,
                           width: Int? = nil,
                           height: Int? = nil,
                           duration: TimeInterval? = nil,
                           isVoiceMessage: Bool = false) -> SearchIndexEntry {
        SearchIndexEntry(eventID: eventID,
                         roomID: roomID,
                         senderID: senderID,
                         senderDisplayName: "John",
                         timestamp: timestamp,
                         kind: kind,
                         body: body,
                         filename: filename,
                         mimeType: mimeType,
                         url: url,
                         threadRootID: nil,
                         fileSize: fileSize,
                         width: width,
                         height: height,
                         duration: duration,
                         isVoiceMessage: isVoiceMessage)
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
    
    // MARK: - Scripts without spaces between words
    
    @Test
    func termsBuriedInChineseAreStillFound() async throws {
        let service = makeService()
        // Real message from a mixed-language room. Nothing separates "app" from the
        // characters either side of it.
        try await service.index([makeEntry(body: "可以发表情的app还要改一下代码才行。")])
        
        #expect(try await service.search(.init(text: "app")).count == 1)
    }
    
    @Test
    func chineseWordsAreFoundAtAnyLength() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "刚刚把卸载的官方element x 装上，官方的可以收到通知。")])
        
        // Two characters is the common case in written Chinese, and the length the
        // trigram tokeniser can't reach.
        #expect(try await service.search(.init(text: "通知")).count == 1)
        #expect(try await service.search(.init(text: "收到通知")).count == 1)
        #expect(try await service.search(.init(text: "element")).count == 1)
    }
    
    @Test
    func chineseThatIsntPresentStillMisses() async throws {
        let service = makeService()
        try await service.index([makeEntry(body: "可以发表情的app还要改一下代码才行。")])
        
        // Per-character segmentation must not turn every query into a match.
        #expect(try await service.search(.init(text: "不存在")).isEmpty)
    }
    
    @Test
    func japaneseAndKoreanSegmentToo() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$jp", body: "会議は明日ですか"),
                                 makeEntry(eventID: "$kr", body: "내일 회의 있어요")])
        
        #expect(try await service.search(.init(text: "明日")).count == 1)
        #expect(try await service.search(.init(text: "회의")).count == 1)
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
    
    // MARK: - Browsing
    
    @Test
    func browsingReturnsAttachmentsNewestFirstAndSkipsPlainMessages() async throws {
        let service = makeService()
        try await service.index([
            makeEntry(eventID: "$chat", kind: .message, body: "just talking"),
            makeEntry(eventID: "$old", kind: .media, filename: "old.jpg",
                      timestamp: .init(timeIntervalSince1970: 1000), mimeType: "image/jpeg"),
            makeEntry(eventID: "$new", kind: .media, filename: "new.jpg",
                      timestamp: .init(timeIntervalSince1970: 2000), mimeType: "image/jpeg")
        ])
        
        let entries = try await service.browse(.init())
        
        // The plain message has nothing to show in a library, so it stays out.
        #expect(entries.map(\.eventID) == ["$new", "$old"])
    }
    
    @Test
    func browsingWithNoQueryTextWorksWhereSearchingDoesNot() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$photo", kind: .media,
                                           filename: "cat.jpg", mimeType: "image/jpeg")])
        
        // The whole reason browse exists: FTS has nothing to match on.
        #expect(try await service.search(.init(text: "")).isEmpty)
        #expect(try await service.browse(.init()).count == 1)
    }
    
    @Test
    func browsingSeparatesPhotosVideosAndGIFsByMIMEType() async throws {
        let service = makeService()
        try await service.index([
            makeEntry(eventID: "$photo", kind: .media, filename: "a.jpg", mimeType: "image/jpeg"),
            makeEntry(eventID: "$gif", kind: .media, filename: "b.gif", mimeType: "image/gif"),
            makeEntry(eventID: "$video", kind: .media, filename: "c.mp4", mimeType: "video/mp4")
        ])
        
        // All three are stored as `.media`; only the MIME type tells them apart.
        #expect(try await service.browse(.init(categories: [.photo])).map(\.eventID) == ["$photo"])
        #expect(try await service.browse(.init(categories: [.gif])).map(\.eventID) == ["$gif"])
        #expect(try await service.browse(.init(categories: [.video])).map(\.eventID) == ["$video"])
    }
    
    @Test
    func browsingSeparatesVoiceNotesFromAudioFiles() async throws {
        let service = makeService()
        try await service.index([
            makeEntry(eventID: "$voice", kind: .media, filename: "voice.ogg",
                      mimeType: "audio/ogg", duration: 12, isVoiceMessage: true),
            makeEntry(eventID: "$audio", kind: .media, filename: "song.ogg", mimeType: "audio/ogg")
        ])
        
        // Same MIME type, so the flag is the only thing separating them.
        #expect(try await service.browse(.init(categories: [.voice])).map(\.eventID) == ["$voice"])
        
        let audio = try await service.browse(.init(categories: [.file]))
        #expect(audio.map(\.eventID) == ["$audio"])
    }
    
    @Test
    func browsingFiltersBySenderAndDate() async throws {
        let service = makeService()
        try await service.index([
            makeEntry(eventID: "$alice", kind: .media, filename: "a.jpg",
                      senderID: "@alice:example.com",
                      timestamp: .init(timeIntervalSince1970: 2000), mimeType: "image/jpeg"),
            makeEntry(eventID: "$bob", kind: .media, filename: "b.jpg",
                      senderID: "@bob:example.com",
                      timestamp: .init(timeIntervalSince1970: 3000), mimeType: "image/jpeg"),
            makeEntry(eventID: "$aliceOld", kind: .media, filename: "c.jpg",
                      senderID: "@alice:example.com",
                      timestamp: .init(timeIntervalSince1970: 500), mimeType: "image/jpeg")
        ])
        
        let bySender = try await service.browse(.init(senderID: "@alice:example.com"))
        #expect(bySender.map(\.eventID) == ["$alice", "$aliceOld"])
        
        let byDate = try await service.browse(.init(after: .init(timeIntervalSince1970: 1000),
                                                    before: .init(timeIntervalSince1970: 2500)))
        #expect(byDate.map(\.eventID) == ["$alice"])
    }
    
    @Test
    func browsingRoundTripsTheAttachmentMetadata() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$video", kind: .media, filename: "clip.mp4",
                                           mimeType: "video/mp4", fileSize: 2048,
                                           width: 1920, height: 1080, duration: 23.5)])
        
        let entry = try #require(try await service.browse(.init()).first)
        #expect(entry.fileSize == 2048)
        #expect(entry.width == 1920)
        #expect(entry.height == 1080)
        // Stored as milliseconds, so this also covers the conversion back.
        #expect(entry.duration == 23.5)
    }
    
    @Test
    func browsingPaginates() async throws {
        let service = makeService()
        try await service.index((0..<5).map { index in
            makeEntry(eventID: "$\(index)", kind: .media, filename: "\(index).jpg",
                      timestamp: .init(timeIntervalSince1970: Double(index) * 1000),
                      mimeType: "image/jpeg")
        })
        
        let firstPage = try await service.browse(.init(limit: 2))
        let secondPage = try await service.browse(.init(limit: 2, offset: 2))
        
        #expect(firstPage.map(\.eventID) == ["$4", "$3"])
        #expect(secondPage.map(\.eventID) == ["$2", "$1"])
    }
    
    @Test
    func anUntypedAttachmentStaysReachableUnderFiles() async throws {
        let service = makeService()
        try await service.index([makeEntry(eventID: "$unknown", kind: .media,
                                           filename: "mystery", mimeType: nil)])
        
        // Better to file it somewhere wrong than drop it out of the library entirely.
        #expect(try await service.browse(.init(categories: [.file])).map(\.eventID) == ["$unknown"])
    }
    
    @Test
    func aFilteredPageIsFullLengthSoPaginationKnowsToContinue() async throws {
        let service = makeService()
        // Photos and videos interleaved, so a page read without filtering in SQL would come
        // back half empty and be mistaken for the end of the results.
        try await service.index((0..<40).map { index in
            makeEntry(eventID: "$\(index)",
                      kind: .media,
                      filename: "\(index)",
                      timestamp: .init(timeIntervalSince1970: Double(index) * 1000),
                      mimeType: index.isMultiple(of: 2) ? "image/jpeg" : "video/mp4")
        })
        
        let firstPage = try await service.browse(.init(categories: [.photo], limit: 10))
        #expect(firstPage.count == 10)
        
        let secondPage = try await service.browse(.init(categories: [.photo], limit: 10, offset: 10))
        #expect(secondPage.count == 10)
        
        // The offset counts matching rows, so the two pages mustn't overlap.
        #expect(Set(firstPage.map(\.eventID)).isDisjoint(with: secondPage.map(\.eventID)))
        
        // Twenty photos in total, so asking beyond them returns nothing.
        #expect(try await service.browse(.init(categories: [.photo], limit: 10, offset: 20)).isEmpty)
    }
}
