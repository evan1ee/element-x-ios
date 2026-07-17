//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct StickerPickerScreenViewModelTests {
    var stickerService: StickerServiceMock!
    var roomProxy: JoinedRoomProxyMock!
    var userIndicatorController: UserIndicatorControllerMock!
    
    var viewModel: StickerPickerScreenViewModel!
    var context: StickerPickerScreenViewModel.Context {
        viewModel.context
    }
    
    let sticker = BuiltInSticker(id: "smile",
                                 body: "Smiling face",
                                 fileURL: URL(filePath: "/dev/null"),
                                 width: 512,
                                 height: 512,
                                 fileSize: 1024)
    
    @Test
    mutating func sendingSuccessDismisses() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        context.send(viewAction: .send(sticker))
        try await deferred.fulfill()
        
        let arguments = try #require(stickerService.sendInThreadRootEventIDReceivedArguments)
        #expect(arguments.sticker == sticker)
        #expect(arguments.threadRootEventID == "$thread-root")
    }
    
    @Test
    mutating func sendingFailureShowsIndicatorAndResets() async throws {
        setupViewModel(sendResult: .failure(.uploadFailed))
        
        let deferred = deferFulfillment(context.observe(\.viewState.sendingStickerID)) { $0 == nil }
        context.send(viewAction: .send(sticker))
        #expect(context.viewState.sendingStickerID == sticker.id)
        try await deferred.fulfill()
        
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
    }
    
    @Test
    mutating func sendingIsIgnoredWhileAlreadySending() async {
        setupViewModel()
        stickerService.sendInThreadRootEventIDClosure = { _, _, _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        
        context.send(viewAction: .send(sticker))
        #expect(context.viewState.sendingStickerID == sticker.id)
        context.send(viewAction: .send(sticker))
        
        while !stickerService.sendInThreadRootEventIDCalled {
            await Task.yield()
        }
        #expect(stickerService.sendInThreadRootEventIDCallsCount == 1)
    }
    
    @Test
    mutating func cancelDismisses() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        context.send(viewAction: .cancel)
        try await deferred.fulfill()
    }
    
    // MARK: - Private
    
    private mutating func setupViewModel(sendResult: Result<Void, StickerServiceError> = .success(())) {
        stickerService = StickerServiceMock()
        stickerService.stickers = [sticker]
        stickerService.sendInThreadRootEventIDReturnValue = sendResult
        
        roomProxy = JoinedRoomProxyMock(.init())
        userIndicatorController = UserIndicatorControllerMock()
        
        viewModel = StickerPickerScreenViewModel(stickerService: stickerService,
                                                 roomProxy: roomProxy,
                                                 threadRootEventID: "$thread-root",
                                                 userIndicatorController: userIndicatorController)
    }
}
