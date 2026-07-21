//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct StickerDiscoveryScreenCoordinatorParameters {
    let klipyService: KlipyServiceProtocol
    let stickerService: StickerServiceProtocol
    let timelineController: TimelineControllerProtocol
    let mediaProvider: MediaProviderProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum StickerDiscoveryScreenCoordinatorAction {
    case dismiss
    case sent
}

final class StickerDiscoveryScreenCoordinator: CoordinatorProtocol {
    private let viewModel: StickerDiscoveryScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<StickerDiscoveryScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<StickerDiscoveryScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: StickerDiscoveryScreenCoordinatorParameters) {
        viewModel = StickerDiscoveryScreenViewModel(klipyService: parameters.klipyService,
                                                    stickerService: parameters.stickerService,
                                                    timelineController: parameters.timelineController,
                                                    mediaProvider: parameters.mediaProvider,
                                                    userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                actionsSubject.send(.dismiss)
            case .sent:
                actionsSubject.send(.sent)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(StickerDiscoveryScreen(context: viewModel.context))
    }
}
