//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

enum SearchScreenViewModelAction {
    case presentRoom(roomID: String, eventID: String?)
    case cancel
}

enum SearchScreenMode: CaseIterable, Identifiable {
    case rooms
    case messages
    case media
    
    var id: Self {
        self
    }
    
    var title: String {
        switch self {
        case .rooms: UntranslatedL10n.screenSearchTabRooms
        case .messages: UntranslatedL10n.screenSearchTabMessages
        case .media: UntranslatedL10n.screenSearchTabMedia
        }
    }
}

struct SearchScreenViewState: BindableState {
    var rooms = [SearchScreenRoom]()
    var messages = [SearchScreenMessage]()
    var media = [SearchScreenMediaAsset]()
    var isLoadingRooms = false
    var isLoadingMessages = false
    var isLoadingMedia = false
    /// Senders who have actually shared something, so the filter only offers names
    /// that can return a result.
    var mediaSenders = [SearchScreenMediaSender]()
    /// Set while history is still downloading, so results can say they're partial
    /// rather than letting an empty result read as "nothing was ever said".
    var isHistoryIncomplete = false
    var bindings: SearchScreenViewStateBindings
    
    var isSearching: Bool {
        !bindings.searchQuery.isEmpty
    }
}

struct SearchScreenViewStateBindings {
    var searchQuery = ""
    var searchMode: SearchScreenMode = .rooms
    
    /// Empty means every category, which is what the library opens on.
    var mediaCategory: MediaCategory?
    var mediaSenderID: String?
    var mediaDateRange: SearchScreenMediaDateRange = .anyTime
}

/// Coarse ranges rather than a date picker: browsing is usually "recently" or "a while ago",
/// and a picker is a lot of chrome for a filter bar.
enum SearchScreenMediaDateRange: CaseIterable, Identifiable {
    case anyTime
    case today
    case thisWeek
    case thisMonth
    
    var id: Self {
        self
    }
    
    var title: String {
        switch self {
        case .anyTime: UntranslatedL10n.screenSearchMediaDateAnyTime
        case .today: UntranslatedL10n.screenSearchMediaDateToday
        case .thisWeek: UntranslatedL10n.screenSearchMediaDateThisWeek
        case .thisMonth: UntranslatedL10n.screenSearchMediaDateThisMonth
        }
    }
    
    /// The lower bound to filter on, or nil for no bound at all.
    var after: Date? {
        let calendar = Calendar.current
        return switch self {
        case .anyTime: nil
        case .today: calendar.startOfDay(for: .now)
        case .thisWeek: calendar.dateInterval(of: .weekOfYear, for: .now)?.start
        case .thisMonth: calendar.dateInterval(of: .month, for: .now)?.start
        }
    }
}

struct SearchScreenMediaSender: Identifiable, Equatable {
    let id: String
    let name: String
}

/// One row or grid cell in the media library.
struct SearchScreenMediaAsset: Identifiable, Equatable {
    let id: String
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
    
    init?(_ entry: SearchIndexEntry, roomSummary: RoomSummary?) {
        guard let category = MediaCategory(kind: entry.kind,
                                           mimeType: entry.mimeType,
                                           isVoiceMessage: entry.isVoiceMessage) else {
            return nil
        }
        
        id = entry.eventID
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
        let source = entry.thumbnailSource ?? entry.mediaSource
        thumbnailSource = source
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

enum SearchScreenViewAction {
    case appeared
    case selectRoom(roomID: String)
    case selectMessage(roomID: String, eventID: String)
    case reachedTop
    case reachedBottom
    case cancel
    case selectAsset(SearchScreenMediaAsset)
    case reachedMediaBottom
    case mediaFiltersChanged
}

struct SearchScreenRoom: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let avatar: RoomAvatar
}

struct SearchScreenMessage: Identifiable, Equatable {
    let id: String
    let roomID: String
    let roomName: String
    let roomAvatar: RoomAvatar
    let senderName: String
    let content: TimelineEventContent
    let timestamp: Date
    
    init(_ result: SearchServiceResult, roomSummary: RoomSummary?, isOutgoing: Bool) {
        id = result.eventID
        roomID = result.roomID
        roomName = roomSummary?.name ?? result.roomID
        roomAvatar = roomSummary?.avatar ?? .room(id: result.roomID, name: roomSummary?.name, avatarURL: nil)
        senderName = isOutgoing ? L10n.commonYou : result.sender.disambiguatedDisplayName ?? result.sender.id
        content = result.content
        timestamp = result.timestamp
    }
    
    /// A hit from the local index, which holds attachments and links.
    init(_ result: SearchIndexResult, roomSummary: RoomSummary?) {
        let entry = result.entry
        id = entry.eventID
        roomID = entry.roomID
        roomName = roomSummary?.name ?? entry.roomID
        roomAvatar = roomSummary?.avatar ?? .room(id: entry.roomID, name: roomSummary?.name, avatarURL: nil)
        senderName = entry.senderDisplayName ?? entry.senderID
        timestamp = entry.timestamp
        // Show the filename for an attachment and the text for a link, so the row says
        // what was actually matched.
        content = .message(.text(.init(body: entry.filename ?? entry.body ?? "")))
    }
    
    var preview: AttributedString? {
        guard let messageBody else { return nil }
        return AttributedString("\(senderName): ") + messageBody
    }
    
    private var messageBody: AttributedString? {
        switch content {
        case .message(let content):
            switch content {
            case .text(let content):
                content.formattedBody ?? AttributedString(content.body)
            case .notice(let content):
                content.formattedBody ?? AttributedString(content.body)
            case .emote(let content):
                content.formattedBody ?? AttributedString(content.body)
            case .audio, .file, .image, .video:
                nil
            case .voice:
                AttributedString(L10n.commonVoiceMessage)
            case .location:
                AttributedString(L10n.commonSharedLocation)
            }
        case .poll(let question):
            AttributedString(question)
        case .liveLocation:
            AttributedString(L10n.commonSharedLiveLocation)
        case .redacted:
            AttributedString(L10n.commonMessageRemoved)
        }
    }
    
    var mediaPreview: SearchScreenMediaPreview? {
        guard case .message(let content) = content else { return nil }
        switch content {
        case .file(let content):
            return .init(title: content.caption ?? content.filename,
                         details: mediaDetails(filename: content.filename, fileSize: content.fileSize),
                         kind: .file)
        case .audio(let content):
            return .init(title: content.caption ?? content.filename,
                         details: mediaDetails(filename: content.filename, fileSize: content.fileSize),
                         kind: .audio)
        case .image(let content):
            return .init(title: content.caption ?? content.filename,
                         details: mediaDetails(filename: content.filename, fileSize: content.imageInfo.fileSize),
                         kind: .image(thumbnail: content.thumbnailInfo ?? content.imageInfo, blurhash: content.blurhash))
        case .video(let content):
            return .init(title: content.caption ?? content.filename,
                         details: mediaDetails(filename: content.filename, fileSize: content.videoInfo.fileSize),
                         kind: .video(thumbnail: content.thumbnailInfo, blurhash: content.blurhash))
        case .text, .notice, .emote, .voice, .location:
            return nil
        }
    }
    
    private func mediaDetails(filename: String, fileSize: UInt?) -> String {
        var details = filename.validatedFileExtension.uppercased()
        if let fileSize {
            details += " (\(fileSize.formatted(.byteCount(style: .file))))"
        }
        return details
    }
}

struct SearchScreenMediaPreview: Equatable {
    enum Kind: Equatable {
        case file
        case audio
        case image(thumbnail: ImageInfoProxy?, blurhash: String?)
        case video(thumbnail: ImageInfoProxy?, blurhash: String?)
    }
    
    let title: String
    let details: String
    let kind: Kind
}
