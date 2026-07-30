//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

/// Covers the watermark that decides what a revisit re-indexes.
///
/// The service re-reads a room whenever the room list reports newer activity, so this
/// filter runs on every incoming message in every room. Letting too much through is a
/// performance problem; letting too little through silently loses search results.
struct SearchIndexBackfillServiceTests {
    private let watermark = Date(timeIntervalSince1970: 1_000_000)
    
    @Test
    func indexesAMessageNewerThanTheWatermark() {
        let item = Self.message(at: watermark.addingTimeInterval(60))
        #expect(SearchIndexBackfillService.isWorthReindexing(item, after: watermark))
    }
    
    /// The common case on a busy room: almost everything loaded is already indexed.
    @Test
    func skipsAMessageOlderThanTheWatermark() {
        let item = Self.message(at: watermark.addingTimeInterval(-60))
        #expect(!SearchIndexBackfillService.isWorthReindexing(item, after: watermark))
    }
    
    /// Equal, not newer — re-indexing it would rewrite the row the watermark came from.
    @Test
    func skipsAMessageExactlyAtTheWatermark() {
        #expect(!SearchIndexBackfillService.isWorthReindexing(Self.message(at: watermark), after: watermark))
    }
    
    /// An edit keeps the original event's timestamp, so it sits below the watermark
    /// forever. Without this the index would keep serving the text before the edit.
    @Test
    func indexesAnEditedMessageFromBeforeTheWatermark() {
        var item = Self.message(at: watermark.addingTimeInterval(-3600))
        item.properties.isEdited = true
        
        #expect(SearchIndexBackfillService.isWorthReindexing(item, after: watermark))
    }
    
    /// Same problem, worse consequence: a redaction below the watermark would leave
    /// deleted content searchable.
    @Test
    func indexesARedactionFromBeforeTheWatermark() {
        let item = RedactedRoomTimelineItem(id: .randomEvent,
                                            body: "Message deleted",
                                            timestamp: watermark.addingTimeInterval(-3600),
                                            isOutgoing: false,
                                            isEditable: false,
                                            canBeRepliedTo: false,
                                            sender: .init(id: "@alice:example.com"))
        
        #expect(SearchIndexBackfillService.isWorthReindexing(item, after: watermark))
    }
    
    /// Items the indexer can't map are passed on rather than filtered here, so the
    /// decision about what's indexable lives in one place.
    @Test
    func defersNonMessageItemsToTheIndexer() {
        let item = SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("separator")), timestamp: watermark)
        #expect(SearchIndexBackfillService.isWorthReindexing(item, after: watermark))
    }
    
    // MARK: - Helpers
    
    private static func message(at timestamp: Date) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .randomEvent,
                             timestamp: timestamp,
                             isOutgoing: false,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: "@alice:example.com"),
                             content: .init(body: "A message"))
    }
}
