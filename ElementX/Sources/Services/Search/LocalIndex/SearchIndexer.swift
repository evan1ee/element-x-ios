//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Turns timeline items into index entries and hands them to the index.
///
/// Message bodies are indexed here rather than left to the SDK. Its index tokenises
/// on spaces, so it can't reach a word inside a run of Chinese, Japanese or Korean —
/// and it only accepts text messages, so filenames and links never reach it at all.
/// Holding everything locally means one index, one tokeniser, one set of rules.
///
/// The cost is that message bodies now sit in the app group container. They arrive
/// decrypted, so the file deserves the same care as the event cache beside it.
nonisolated struct SearchIndexer: Sendable {
    private let indexService: SearchIndexServiceProtocol
    
    init(indexService: SearchIndexServiceProtocol) {
        self.indexService = indexService
    }
    
    /// Indexes what's worth indexing from a timeline, and drops anything redacted
    /// since it was last seen.
    func process(_ items: [RoomTimelineItemProtocol], inRoom roomID: String) async {
        let entries = Self.entries(from: items, roomID: roomID)
        let redacted = items.compactMap { ($0 as? RedactedRoomTimelineItem)?.id.eventID }
        
        do {
            if !entries.isEmpty {
                try await indexService.index(entries)
            }
            if !redacted.isEmpty {
                try await indexService.remove(eventIDs: redacted)
            }
        } catch {
            // The index is derived data. Losing a write costs a missing result, not
            // correctness, so don't propagate into the timeline.
            MXLog.error("Failed updating the search index: \(error)")
        }
    }
    
    // MARK: - Mapping
    
    static func entries(from items: [RoomTimelineItemProtocol], roomID: String) -> [SearchIndexEntry] {
        items.flatMap { entries(from: $0, roomID: roomID) }
    }
    
    /// Usually one entry, but a gallery yields one per attachment so each stays separately
    /// findable and gets its own tile in the library.
    static func entries(from item: RoomTimelineItemProtocol, roomID: String) -> [SearchIndexEntry] {
        // Local echoes have no event ID yet; they'll be indexed once the timeline
        // replaces them with the remote item.
        guard let eventID = item.id.eventID,
              let item = item as? EventBasedMessageTimelineItemProtocol else {
            return []
        }
        
        let links = Self.links(in: item.body)
        
        if case .gallery(let content) = item.contentType {
            // The caption rides along on every row so searching it finds the gallery
            // whichever attachment ranks first.
            let entries = content.items.enumerated().compactMap { mediaIndex, galleryItem in
                Self.contentType(of: galleryItem)
                    .flatMap(Self.attachment(in:))
                    .map { entry(eventID: eventID, mediaIndex: mediaIndex, attachment: $0, links: links, item: item, roomID: roomID) }
            }
            // A gallery of nothing but unknown types still has its caption worth indexing.
            guard entries.isEmpty else { return entries }
        }
        
        let attachment = Self.attachment(in: item.contentType)
        
        // Nothing to match against: no filename, no text.
        guard attachment != nil || !item.body.isEmpty else { return [] }
        
        return [entry(eventID: eventID, mediaIndex: 0, attachment: attachment, links: links, item: item, roomID: roomID)]
    }
    
    private static func entry(eventID: String,
                              mediaIndex: Int,
                              attachment: Attachment?,
                              links: [String],
                              item: EventBasedMessageTimelineItemProtocol,
                              roomID: String) -> SearchIndexEntry {
        // A message carrying a link files under links so the filter can find it;
        // the body is still indexed either way.
        let kind: SearchIndexEventKind = attachment?.kind ?? (links.isEmpty ? .message : .link)
        
        return SearchIndexEntry(eventID: eventID,
                                mediaIndex: mediaIndex,
                                roomID: roomID,
                                senderID: item.sender.id,
                                senderDisplayName: item.sender.displayName,
                                timestamp: item.timestamp,
                                kind: kind,
                                body: item.body.isEmpty ? nil : item.body,
                                filename: attachment?.filename,
                                mimeType: attachment?.mimeType,
                                url: links.first,
                                // The timeline item knows it's threaded but not which root it
                                // hangs off, so the column stays empty until thread-only search
                                // needs it.
                                threadRootID: nil,
                                fileSize: attachment?.fileSize,
                                width: attachment?.width,
                                height: attachment?.height,
                                duration: attachment?.duration,
                                isVoiceMessage: attachment?.isVoiceMessage ?? false,
                                mediaSource: attachment?.mediaSource,
                                thumbnailSource: attachment?.thumbnailSource)
    }
    
    /// A gallery's attachments reuse the standalone message content types, so they map
    /// straight back onto them and share the attachment mapping below.
    private static func contentType(of item: GalleryItem) -> EventBasedMessageTimelineItemContentType? {
        switch item {
        case .image(_, let content): .image(content)
        case .video(_, let content): .video(content)
        case .audio(_, let content): .audio(content)
        case .file(_, let content): .file(content)
        case .other: nil
        }
    }
    
    private struct Attachment {
        let kind: SearchIndexEventKind
        let filename: String
        let mimeType: String?
        var fileSize: UInt?
        var width: Int?
        var height: Int?
        var duration: TimeInterval?
        /// A recorded voice note. Audio files share its MIME type, so nothing else tells them apart.
        var isVoiceMessage = false
        var mediaSource: String?
        var thumbnailSource: String?
    }
    
    private static func attachment(in contentType: EventBasedMessageTimelineItemContentType) -> Attachment? {
        switch contentType {
        case .file(let content):
            Attachment(kind: .file,
                       filename: content.filename,
                       mimeType: content.contentType?.preferredMIMEType,
                       fileSize: content.fileSize)
        case .image(let content):
            Attachment(kind: .media,
                       filename: content.filename,
                       mimeType: content.contentType?.preferredMIMEType,
                       fileSize: content.imageInfo.fileSize,
                       width: content.imageInfo.size.map { Int($0.width) },
                       height: content.imageInfo.size.map { Int($0.height) },
                       mediaSource: content.imageInfo.source.underlyingSource.toJson(),
                       thumbnailSource: content.thumbnailInfo?.source.underlyingSource.toJson())
        case .video(let content):
            Attachment(kind: .media,
                       filename: content.filename,
                       mimeType: content.contentType?.preferredMIMEType,
                       fileSize: content.videoInfo.fileSize,
                       width: content.videoInfo.size.map { Int($0.width) },
                       height: content.videoInfo.size.map { Int($0.height) },
                       duration: content.videoInfo.duration,
                       mediaSource: content.videoInfo.source.underlyingSource.toJson(),
                       thumbnailSource: content.thumbnailInfo?.source.underlyingSource.toJson())
        case .audio(let content):
            Attachment(kind: .media,
                       filename: content.filename,
                       mimeType: content.contentType?.preferredMIMEType,
                       fileSize: content.fileSize,
                       duration: content.duration)
        case .voice(let content):
            Attachment(kind: .media,
                       filename: content.filename,
                       mimeType: content.contentType?.preferredMIMEType,
                       fileSize: content.fileSize,
                       duration: content.duration,
                       isVoiceMessage: true)
        // A gallery is unpacked into one entry per attachment before reaching here.
        case .text, .notice, .emote, .location, .gallery:
            nil
        }
    }
    
    /// Pulls URLs out of a body so links stay findable by host, which is how people
    /// tend to remember them — "that github link" rather than the full path.
    static func links(in text: String) -> [String] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
    }
}
