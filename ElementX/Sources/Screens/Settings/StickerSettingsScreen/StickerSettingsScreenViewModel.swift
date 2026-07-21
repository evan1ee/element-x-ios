//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

typealias StickerSettingsScreenViewModelType = StateStoreViewModelV2<StickerSettingsScreenViewState, StickerSettingsScreenViewAction>

class StickerSettingsScreenViewModel: StickerSettingsScreenViewModelType, StickerSettingsScreenViewModelProtocol {
    init(stickerSettings: StickerSettingsProtocol) {
        super.init(initialViewState: StickerSettingsScreenViewState(bindings: .init(stickerSettings: stickerSettings)))
    }
    
    override func process(viewAction: StickerSettingsScreenViewAction) {
        switch viewAction {
        case .reset:
            state.bindings.klipyAPIKey = AppSettings.defaultKlipyAPIKey
        }
    }
}
