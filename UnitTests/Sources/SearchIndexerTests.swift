//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing
import UniformTypeIdentifiers

struct SearchIndexerTests {
    private let roomID = "!room:example.com"
    
    // MARK: - Attachments
    
    @Test
    func filesAreIndexedByFilename() throws {
        let item = FileRoomTimelineItem(id: .randomEvent,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@john:example.com", displayName: "John"),
                                        content: .init(filename: "budget.xlsx",
                                                       source: nil,
                                                       fileSize: nil,
                                                       thumbnailSource: nil,
                                                       contentType: .spreadsheet))
        
        let entry = try #require(SearchIndexer.entry(from: item, roomID: roomID))
        
        #expect(entry.kind == .file)
        #expect(entry.filename == "budget.xlsx")
        #expect(entry.roomID == roomID)
        #expect(entry.senderDisplayName == "John")
    }
    
    @Test
    func imagesAndVideosCountAsMediaRatherThanFiles() {
        let image = ImageRoomTimelineItem(id: .randomEvent,
                                          timestamp: .mock,
                                          isOutgoing: false,
                                          isEditable: false,
                                          canBeRepliedTo: true,
                                          sender: .init(id: "@john:example.com"),
                                          content: .init(filename: "holiday.jpg",
                                                         imageInfo: .mockImage,
                                                         thumbnailInfo: nil,
                                                         contentType: .jpeg))
        
        #expect(SearchIndexer.entry(from: image, roomID: roomID)?.kind == .media)
    }
    
    // MARK: - Links
    
    @Test
    func textCarryingALinkIsIndexedAsALink() throws {
        let item = makeText("have a look at https://github.com/element-hq/element-x-ios")
        
        let entry = try #require(SearchIndexer.entry(from: item, roomID: roomID))
        
        #expect(entry.kind == .link)
        #expect(entry.url?.contains("github.com") == true)
        #expect(entry.body?.isEmpty == false)
    }
    
    @Test
    func plainTextIsLeftToTheSDKsIndex() {
        // Indexing this too would duplicate the SDK's work and put a second copy of
        // every private message on disk.
        #expect(SearchIndexer.entry(from: makeText("just a normal message"), roomID: roomID) == nil)
    }
    
    @Test
    func linkDetectionFindsBareHosts() {
        #expect(SearchIndexer.links(in: "see matrix.org for details").count == 1)
        #expect(SearchIndexer.links(in: "https://a.com and https://b.com").count == 2)
        #expect(SearchIndexer.links(in: "no links here").isEmpty)
        #expect(SearchIndexer.links(in: "").isEmpty)
    }
    
    // MARK: - Skipping
    
    @Test
    func itemsWithoutAnEventIDAreSkipped() {
        // A local echo has no event ID yet. It gets indexed when the timeline swaps
        // in the remote item.
        let item = FileRoomTimelineItem(id: .event(uniqueID: .init("unique"),
                                                   eventOrTransactionID: .transactionID("transaction")),
                                        timestamp: .mock,
                                        isOutgoing: true,
                                        isEditable: false,
                                        canBeRepliedTo: false,
                                        sender: .init(id: "@me:example.com"),
                                        content: .init(filename: "pending.pdf",
                                                       source: nil,
                                                       fileSize: nil,
                                                       thumbnailSource: nil,
                                                       contentType: .pdf))
        
        #expect(SearchIndexer.entry(from: item, roomID: roomID) == nil)
    }
    
    @Test
    func mappingAWholeTimelineKeepsOnlyTheRelevantItems() {
        let items: [RoomTimelineItemProtocol] = [
            makeText("plain chatter"),
            makeText("look at https://matrix.org"),
            FileRoomTimelineItem(id: .randomEvent,
                                 timestamp: .mock,
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: "@john:example.com"),
                                 content: .init(filename: "notes.txt",
                                                source: nil,
                                                fileSize: nil,
                                                thumbnailSource: nil,
                                                contentType: .plainText))
        ]
        
        let entries = SearchIndexer.entries(from: items, roomID: roomID)
        
        #expect(entries.count == 2)
        #expect(entries.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.file, .link])
    }
    
    // MARK: - Helpers
    
    private func makeText(_ body: String) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .randomEvent,
                             timestamp: .mock,
                             isOutgoing: false,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: "@john:example.com", displayName: "John"),
                             content: .init(body: body))
    }
}
