//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct SyncStorageScreenCoordinatorParameters {
    let historyDownloadManager: HistoryDownloadManagerProtocol
    let appSettings: AppSettings
}

final class SyncStorageScreenCoordinator: CoordinatorProtocol {
    private let viewModel: SyncStorageScreenViewModelProtocol
    
    init(parameters: SyncStorageScreenCoordinatorParameters) {
        viewModel = SyncStorageScreenViewModel(historyDownloadManager: parameters.historyDownloadManager,
                                               appSettings: parameters.appSettings)
    }
    
    func toPresentable() -> AnyView {
        AnyView(SyncStorageScreen(context: viewModel.context))
    }
}
