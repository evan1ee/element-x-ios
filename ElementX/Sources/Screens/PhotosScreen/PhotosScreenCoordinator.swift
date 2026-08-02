//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct PhotosScreenCoordinatorParameters {
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    let searchIndexService: SearchIndexServiceProtocol
    let historyDownloadManager: HistoryDownloadManagerProtocol
}

enum PhotosScreenCoordinatorAction {
    case presentRoom(roomID: String, eventID: String)
}

final class PhotosScreenCoordinator: CoordinatorProtocol {
    private let viewModel: PhotosScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<PhotosScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<PhotosScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: PhotosScreenCoordinatorParameters) {
        viewModel = PhotosScreenViewModel(clientProxy: parameters.clientProxy,
                                          mediaProvider: parameters.mediaProvider,
                                          searchIndexService: parameters.searchIndexService,
                                          historyDownloadManager: parameters.historyDownloadManager)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            switch action {
            case .presentRoom(let roomID, let eventID):
                self?.actionsSubject.send(.presentRoom(roomID: roomID, eventID: eventID))
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(PhotosScreen(context: viewModel.context))
    }
}
