//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct DisplaySettingsScreenCoordinatorParameters {
    let appSettings: AppSettings
}

final class DisplaySettingsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: DisplaySettingsScreenViewModelProtocol
    
    init(parameters: DisplaySettingsScreenCoordinatorParameters) {
        viewModel = DisplaySettingsScreenViewModel(displaySettings: parameters.appSettings)
    }
    
    func toPresentable() -> AnyView {
        AnyView(DisplaySettingsScreen(context: viewModel.context))
    }
}
