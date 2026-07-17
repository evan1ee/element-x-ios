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
    var timelineController: TimelineControllerMock!
    var userIndicatorController: UserIndicatorControllerMock!
    
    var viewModel: StickerPickerScreenViewModel!
    var context: StickerPickerScreenViewModel.Context {
        viewModel.context
    }
    
    let builtInSticker = Sticker(id: "smile",
                                 body: "Smiling face",
                                 source: .bundle(URL(filePath: "/dev/null")),
                                 width: 512,
                                 height: 512,
                                 fileSize: 1024,
                                 mimeType: "image/png")
    
    let userSticker = Sticker(id: "party",
                              body: "Party",
                              source: .media(url: "mxc://example.com/party"),
                              width: 512,
                              height: 512,
                              fileSize: 1024,
                              mimeType: "image/png")
    
    @Test
    mutating func loadsUserStickersOnInit() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(context.observe(\.viewState.userStickers)) { !$0.isEmpty }
        try await deferred.fulfill()
        
        #expect(context.viewState.userStickers == [userSticker])
        #expect(context.viewState.builtInStickers == [builtInSticker])
    }
    
    @Test
    mutating func sendingSuccessDismisses() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss }
        context.send(viewAction: .send(builtInSticker))
        try await deferred.fulfill()
        
        let arguments = try #require(stickerService.sendInReceivedArguments)
        #expect(arguments.sticker == builtInSticker)
    }
    
    @Test
    mutating func sendingFailureShowsIndicatorAndResets() async throws {
        setupViewModel(sendResult: .failure(.uploadFailed))
        
        let deferred = deferFulfillment(context.observe(\.viewState.sendingStickerID)) { $0 == nil }
        context.send(viewAction: .send(builtInSticker))
        #expect(context.viewState.sendingStickerID == builtInSticker.id)
        try await deferred.fulfill()
        
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
    }
    
    @Test
    mutating func sendingIsIgnoredWhileAlreadySending() async {
        setupViewModel()
        stickerService.sendInClosure = { _, _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        
        context.send(viewAction: .send(builtInSticker))
        #expect(context.viewState.sendingStickerID == builtInSticker.id)
        context.send(viewAction: .send(builtInSticker))
        
        while !stickerService.sendInCalled {
            await Task.yield()
        }
        #expect(stickerService.sendInCallsCount == 1)
    }
    
    @Test
    mutating func removingAStickerReloads() async throws {
        setupViewModel()
        
        let loaded = deferFulfillment(context.observe(\.viewState.userStickers)) { !$0.isEmpty }
        try await loaded.fulfill()
        
        stickerService.loadStickersReturnValue = StickerCollection(userStickers: [],
                                                                   builtInStickers: [builtInSticker])
        
        let deferred = deferFulfillment(context.observe(\.viewState.userStickers)) { $0.isEmpty }
        context.send(viewAction: .removeSticker(userSticker))
        try await deferred.fulfill()
        
        #expect(stickerService.removeUserStickerIdReceivedId == userSticker.id)
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
        stickerService.builtInStickers = [builtInSticker]
        stickerService.loadStickersReturnValue = StickerCollection(userStickers: [userSticker],
                                                                   builtInStickers: [builtInSticker])
        stickerService.sendInReturnValue = sendResult
        stickerService.removeUserStickerIdReturnValue = .success(())
        
        timelineController = TimelineControllerMock(.init())
        userIndicatorController = UserIndicatorControllerMock()
        
        viewModel = StickerPickerScreenViewModel(stickerService: stickerService,
                                                 timelineController: timelineController,
                                                 mediaProvider: MediaProviderMock(.init()),
                                                 userIndicatorController: userIndicatorController)
    }
}
