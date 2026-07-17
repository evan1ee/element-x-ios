//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct StickerPickerScreenCoordinatorParameters {
    let stickerService: StickerServiceProtocol
    let roomProxy: JoinedRoomProxyProtocol
    let threadRootEventID: String?
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum StickerPickerScreenCoordinatorAction {
    case dismiss
}

final class StickerPickerScreenCoordinator: CoordinatorProtocol {
    private let viewModel: StickerPickerScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<StickerPickerScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<StickerPickerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: StickerPickerScreenCoordinatorParameters) {
        viewModel = StickerPickerScreenViewModel(stickerService: parameters.stickerService,
                                                 roomProxy: parameters.roomProxy,
                                                 threadRootEventID: parameters.threadRootEventID,
                                                 userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(StickerPickerScreen(context: viewModel.context))
    }
}
