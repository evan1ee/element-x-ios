//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

/// One row or grid cell in the media library.
struct MediaLibraryAsset: Identifiable, Equatable {
    /// Unique per tile rather than per event: a gallery contributes one tile per attachment,
    /// all of which share ``eventID``.
    let id: String
    /// The event to open when the tile is tapped.
    let eventID: String
    let roomID: String
    let roomName: String
    let category: MediaCategory
    let senderID: String
    let senderName: String
    let timestamp: Date
    let filename: String?
    let body: String?
    let fileSize: UInt?
    let width: Int?
    let height: Int?
    let duration: TimeInterval?
    /// Thumbnail first, falling back to the full media when the sender sent no thumbnail.
    let thumbnailSource: MediaSourceProxy?
    /// The original, for the full screen viewer.
    let mediaSource: MediaSourceProxy?
    
    init?(_ entry: SearchIndexEntry, roomSummary: RoomSummary?) {
        guard let category = MediaCategory(kind: entry.kind,
                                           mimeType: entry.mimeType,
                                           isVoiceMessage: entry.isVoiceMessage) else {
            return nil
        }
        
        id = "\(entry.eventID)-\(entry.mediaIndex)"
        eventID = entry.eventID
        roomID = entry.roomID
        roomName = roomSummary?.name ?? entry.roomID
        self.category = category
        senderID = entry.senderID
        senderName = entry.senderDisplayName ?? entry.senderID
        timestamp = entry.timestamp
        filename = entry.filename
        body = entry.body
        fileSize = entry.fileSize
        width = entry.width
        height = entry.height
        duration = entry.duration
        
        // Serialised rather than a bare URL: media in an encrypted room needs the keys that
        // come with the source, and an mxc:// URI on its own would only fetch bytes we
        // couldn't decrypt.
        // The MIME type is only carried when falling back to the original. A thumbnail of a
        // GIF is a still image, and claiming otherwise sends the loader down its animated
        // path looking for frames that aren't there.
        let hasThumbnail = entry.thumbnailSource != nil
        let source = entry.thumbnailSource ?? entry.mediaSource
        thumbnailSource = source
            .flatMap { try? MediaSource.fromJson(json: $0) }
            .map { MediaSourceProxy(source: $0, mimeType: hasThumbnail ? nil : entry.mimeType) }
        mediaSource = entry.mediaSource
            .flatMap { try? MediaSource.fromJson(json: $0) }
            .map { MediaSourceProxy(source: $0, mimeType: entry.mimeType) }
    }
    
    /// What the row calls this. Links show their host, which is how people remember them.
    var title: String {
        switch category {
        case .link:
            body.flatMap(URL.init(string:))?.host() ?? body ?? filename ?? ""
        case .voice:
            L10n.commonVoiceMessage
        default:
            filename ?? body ?? ""
        }
    }
    
    /// Sender, room and whatever measurement suits the kind of asset.
    var subtitle: String {
        var parts = [senderName, roomName]
        if let duration, category == .video || category == .voice {
            parts.append(Self.durationFormatter.string(from: duration) ?? "")
        } else if let fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    
    /// Overlaid on a grid cell, for the kinds where it says something.
    var badge: String? {
        switch category {
        case .video:
            duration.flatMap { Self.durationFormatter.string(from: $0) }
        case .gif:
            "GIF"
        default:
            nil
        }
    }
    
    private static let durationFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}
