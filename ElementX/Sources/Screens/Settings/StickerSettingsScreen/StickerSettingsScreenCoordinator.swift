//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct StickerSettingsScreenCoordinatorParameters {
    let appSettings: AppSettings
}

final class StickerSettingsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: StickerSettingsScreenViewModelProtocol
    
    init(parameters: StickerSettingsScreenCoordinatorParameters) {
        viewModel = StickerSettingsScreenViewModel(stickerSettings: parameters.appSettings)
    }
    
    func toPresentable() -> AnyView {
        AnyView(StickerSettingsScreen(context: viewModel.context))
    }
}
