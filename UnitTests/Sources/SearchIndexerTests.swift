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
        
        let entry = try #require(SearchIndexer.entries(from: item, roomID: roomID).first)
        
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
        
        #expect(SearchIndexer.entries(from: image, roomID: roomID).first?.kind == .media)
    }
    
    // MARK: - Galleries
    
    @Test
    func galleriesAreIndexedOneEntryPerAttachment() {
        let item = makeGallery(caption: "the weekend",
                               items: [.mockImage(index: 0, filename: "one.jpg"),
                                       .mockVideo(index: 1, filename: "two.mp4"),
                                       .mockFile(index: 2, filename: "three.pdf")])
        
        let entries = SearchIndexer.entries(from: item, roomID: roomID)
        
        #expect(entries.count == 3)
        #expect(entries.map(\.mediaIndex) == [0, 1, 2])
        #expect(entries.map(\.filename) == ["one.jpg", "two.mp4", "three.pdf"])
        #expect(entries.map(\.kind) == [.media, .media, .file])
        // One event, so every row shares its ID and the caption that makes it findable.
        #expect(Set(entries.map(\.eventID)).count == 1)
        #expect(entries.allSatisfy { $0.body == "the weekend" })
    }
    
    @Test
    func galleryItemsOfUnknownTypeFallBackToIndexingTheCaption() throws {
        let item = makeGallery(caption: "no previewable items",
                               items: [.other(id: .mock(0), filename: "mystery.bin")])
        
        let entry = try #require(SearchIndexer.entries(from: item, roomID: roomID).first)
        
        #expect(entry.kind == .message)
        #expect(entry.mediaIndex == 0)
        #expect(entry.body == "no previewable items")
    }
    
    // MARK: - Links
    
    @Test
    func textCarryingALinkIsIndexedAsALink() throws {
        let item = makeText("have a look at https://github.com/element-hq/element-x-ios")
        
        let entry = try #require(SearchIndexer.entries(from: item, roomID: roomID).first)
        
        #expect(entry.kind == .link)
        #expect(entry.url?.contains("github.com") == true)
        #expect(entry.body?.isEmpty == false)
    }
    
    @Test
    func plainTextIsIndexedSoBodiesAreSearchable() throws {
        let entry = try #require(SearchIndexer.entries(from: makeText("just a normal message"), roomID: roomID).first)
        
        #expect(entry.kind == .message)
        #expect(entry.body == "just a normal message")
    }
    
    @Test
    func textWithNoBodyAndNoAttachmentIsSkipped() {
        // Nothing to match against, so the row would only take up space.
        #expect(SearchIndexer.entries(from: makeText(""), roomID: roomID).isEmpty)
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
        
        #expect(SearchIndexer.entries(from: item, roomID: roomID).isEmpty)
    }
    
    @Test
    func mappingAWholeTimelineClassifiesEachItem() {
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
        
        #expect(entries.count == 3)
        #expect(entries.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.file, .link, .message])
    }
    
    // MARK: - Helpers
    
    private func makeGallery(caption: String, items: [GalleryItem]) -> GalleryRoomTimelineItem {
        GalleryRoomTimelineItem(id: .randomEvent,
                                timestamp: .mock,
                                isOutgoing: false,
                                isEditable: false,
                                canBeRepliedTo: true,
                                sender: .init(id: "@john:example.com", displayName: "John"),
                                content: .init(body: caption, caption: caption, items: items))
    }
    
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
