//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum PhotosScreenViewModelAction {
    /// Opens the room the asset was shared in, focussed on the message that carried it.
    case presentRoom(roomID: String, eventID: String)
}

/// A room offered in the filter, named as the chat list names it.
struct PhotosScreenRoom: Identifiable, Equatable {
    let id: String
    let name: String
}

struct PhotosScreenViewState: BindableState {
    var assets = [MediaLibraryAsset]()
    var rooms = [PhotosScreenRoom]()
    var isLoading = false
    
    /// The room the grid is narrowed to, or nil for everything.
    var roomID: String?
    
    var roomFilterTitle: String {
        rooms.first { $0.id == roomID }?.name ?? UntranslatedL10n.screenPhotosAllChats
    }
    
    /// Set while the history download hasn't finished, so a thin library reads as
    /// "still arriving" rather than "this is all there is".
    var isHistoryIncomplete = false
    
    var isEmpty: Bool {
        assets.isEmpty && !isLoading
    }
    
    var bindings = PhotosScreenViewStateBindings()
}

struct PhotosScreenViewStateBindings {
    /// The asset the full screen viewer opened on, if it's open.
    var previewedAsset: MediaLibraryAsset?
}

enum PhotosScreenViewAction {
    case appeared
    case selectAsset(MediaLibraryAsset)
    case openInChat(MediaLibraryAsset)
    case selectRoom(String?)
    case reachedBottom
}
