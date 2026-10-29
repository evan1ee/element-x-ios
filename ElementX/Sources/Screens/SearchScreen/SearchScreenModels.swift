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
    case messages
    case media
    
    var id: Self {
        self
    }
    
    var title: String {
        switch self {
        case .messages: L10n.screenSearchTabMessages
        case .media: UntranslatedL10n.screenSearchTabMedia
        }
    }
}

struct SearchScreenViewState: BindableState {
    var rooms = [SearchScreenRoom]()
    var messages = [SearchScreenMessage]()
    var media = [MediaLibraryAsset]()
    var breadcrumbs = [SearchScreenBreadcrumb]()
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
    var searchMode: SearchScreenMode = .messages
    
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

enum SearchScreenViewAction: CustomStringConvertible {
    case appeared
    case submitQuery
    case selectRoom(roomID: String)
    case selectMessage(roomID: String, eventID: String)
    case removeBreadcrumb(SearchScreenBreadcrumb)
    case clearBreadcrumbs
    case reachedTop
    case reachedBottom
    case cancel
    case selectAsset(MediaLibraryAsset)
    case reachedMediaBottom
    case mediaFiltersChanged
    
    var description: String {
        switch self {
        case .appeared: "appeared"
        case .submitQuery: "submitQuery"
        case .selectRoom(let roomID): "selectRoom(\(roomID))"
        case .selectMessage(let roomID, let eventID): "selectMessage(\(roomID), \(eventID))"
        case .removeBreadcrumb: "removeBreadcrumb"
        case .clearBreadcrumbs: "clearBreadcrumbs"
        case .reachedTop: "reachedTop"
        case .reachedBottom: "reachedBottom"
        case .cancel: "cancel"
        case .selectAsset(let asset): "selectAsset(\(asset.id))"
        case .reachedMediaBottom: "reachedMediaBottom"
        case .mediaFiltersChanged: "mediaFiltersChanged"
        }
    }
}

struct SearchScreenRoom: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let avatar: RoomAvatar
    
    init(_ summary: RoomSummary) {
        let identifier = if summary.isDirect {
            summary.heroes.first?.id ?? summary.canonicalAlias
        } else {
            summary.canonicalAlias
        }
        
        id = summary.id
        title = summary.name
        description = identifier ?? ""
        avatar = summary.avatar
    }
}

/// An entry in the search history shown before the user has typed a query.
enum SearchScreenBreadcrumb: Identifiable, Equatable {
    case query(String)
    case room(SearchScreenRoom)
    
    var id: String {
        switch self {
        case .query(let query): "query-\(query)"
        case .room(let room): "room-\(room.id)"
        }
    }
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
    
    var preview: String? {
        guard let messageBody else { return nil }
        return "\(senderName): \(messageBody)"
    }
    
    private var messageBody: String? {
        switch content {
        case .message(let content):
            switch content {
            case .text(let content):
                content.body
            case .notice(let content):
                content.body
            case .emote(let content):
                content.body
            case .audio, .file, .image, .video, .gallery:
                nil
            case .voice:
                L10n.commonVoiceMessage
            case .location:
                L10n.commonSharedLocation
            }
        case .poll(let question):
            question
        case .liveLocation:
            L10n.commonSharedLiveLocation
        case .redacted:
            L10n.commonMessageRemoved
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
        case .text, .notice, .emote, .voice, .location, .gallery:
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
