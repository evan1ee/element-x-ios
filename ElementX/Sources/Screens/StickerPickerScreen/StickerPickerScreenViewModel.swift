//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias StickerPickerScreenViewModelType = StateStoreViewModelV2<StickerPickerScreenViewState, StickerPickerScreenViewAction>

class StickerPickerScreenViewModel: StickerPickerScreenViewModelType, StickerPickerScreenViewModelProtocol {
    private let stickerService: StickerServiceProtocol
    private let roomProxy: JoinedRoomProxyProtocol
    private let threadRootEventID: String?
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<StickerPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<StickerPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(stickerService: StickerServiceProtocol,
         roomProxy: JoinedRoomProxyProtocol,
         threadRootEventID: String?,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.stickerService = stickerService
        self.roomProxy = roomProxy
        self.threadRootEventID = threadRootEventID
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: StickerPickerScreenViewState(stickers: stickerService.stickers))
    }
    
    // MARK: - Public
    
    override func process(viewAction: StickerPickerScreenViewAction) {
        switch viewAction {
        case .send(let sticker):
            send(sticker)
        case .cancel:
            actionsSubject.send(.dismiss)
        }
    }
    
    // MARK: - Private
    
    private func send(_ sticker: BuiltInSticker) {
        guard !state.isSending else {
            return
        }
        
        state.sendingStickerID = sticker.id
        
        Task {
            switch await stickerService.send(sticker, in: roomProxy, threadRootEventID: threadRootEventID) {
            case .success:
                actionsSubject.send(.dismiss)
            case .failure:
                state.sendingStickerID = nil
                userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorUnknown, icon: \.close))
            }
        }
    }
}
