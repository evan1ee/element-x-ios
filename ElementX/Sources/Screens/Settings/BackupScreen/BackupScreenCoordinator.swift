//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct BackupScreenCoordinatorParameters {
    let backupManager: BackupManagerProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

final class BackupScreenCoordinator: CoordinatorProtocol {
    private let viewModel: BackupScreenViewModelProtocol
    
    init(parameters: BackupScreenCoordinatorParameters) {
        viewModel = BackupScreenViewModel(backupManager: parameters.backupManager,
                                          userIndicatorController: parameters.userIndicatorController)
    }
    
    func toPresentable() -> AnyView {
        AnyView(BackupScreen(context: viewModel.context))
    }
}
