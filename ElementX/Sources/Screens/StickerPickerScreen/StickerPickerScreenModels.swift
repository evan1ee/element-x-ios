//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum StickerPickerScreenViewModelAction {
    case dismiss
}

struct StickerPickerScreenViewState: BindableState {
    var stickers: [BuiltInSticker]
    var sendingStickerID: String?
    
    var isSending: Bool {
        sendingStickerID != nil
    }
}

enum StickerPickerScreenViewAction {
    case send(BuiltInSticker)
    case cancel
}
