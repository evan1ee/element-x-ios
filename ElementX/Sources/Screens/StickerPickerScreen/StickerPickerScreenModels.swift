//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import PhotosUI
import SwiftUI

enum StickerPickerScreenViewModelAction {
    case dismiss
}

struct StickerPickerScreenViewState: BindableState {
    var userStickers: [Sticker] = []
    var builtInStickers: [Sticker] = []
    var sendingStickerID: String?
    var isAddingSticker = false
    
    var bindings = StickerPickerScreenViewStateBindings()
    
    var isSending: Bool {
        sendingStickerID != nil
    }
    
    var isBusy: Bool {
        isSending || isAddingSticker
    }
}

struct StickerPickerScreenViewStateBindings {
    var photosPickerItems: [PhotosPickerItem] = []
}

enum StickerPickerScreenViewAction {
    case send(Sticker)
    case addSelectedPhotos
    case removeSticker(Sticker)
    case cancel
}
