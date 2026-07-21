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
struct StickerDiscoveryScreenViewModelTests {
    var klipyService: KlipyServiceMock!
    var stickerService: StickerServiceMock!
    var timelineController: TimelineControllerMock!
    var userIndicatorController: UserIndicatorControllerMock!
    
    var viewModel: StickerDiscoveryScreenViewModel!
    var context: StickerDiscoveryScreenViewModel.Context {
        viewModel.context
    }
    
    func makeSticker(id: String) -> KlipySticker {
        KlipySticker(id: id,
                     title: "Title \(id)",
                     previewURL: url("\(id)-sm"),
                     fileURL: url("\(id)-md"),
                     width: 480,
                     height: 480,
                     size: 80000,
                     mimeType: "image/gif")
    }
    
    private func url(_ name: String) -> URL {
        URL(string: "https://static.klipy.com/\(name).gif") ?? URL(filePath: "/")
    }
    
    @Test
    mutating func loadsTrendingOnInit() async throws {
        setupViewModel(stickers: [makeSticker(id: "a"), makeSticker(id: "b")])
        
        let deferred = deferFulfillment(context.observe(\.viewState.results)) { !$0.isEmpty }
        try await deferred.fulfill()
        
        #expect(context.viewState.results.map(\.id) == ["a", "b"])
        #expect(klipyService.searchQueryPageReceivedArguments?.query == "")
    }
    
    @Test
    mutating func sendingASuccessfulStickerEmitsSent() async throws {
        setupViewModel(stickers: [makeSticker(id: "a")])
        let loaded = deferFulfillment(context.observe(\.viewState.results)) { !$0.isEmpty }
        try await loaded.fulfill()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .sent }
        context.send(viewAction: .send(makeSticker(id: "a")))
        try await deferred.fulfill()
        
        #expect(klipyService.downloadImageFromCalled)
        let arguments = try #require(stickerService.sendExternalStickerImageDataBodyWidthHeightMimeTypeInReceivedArguments)
        #expect(arguments.mimeType == "image/gif")
        #expect(arguments.body == "Title a")
    }
    
    @Test
    mutating func sendingAFailedDownloadShowsIndicator() async throws {
        setupViewModel(stickers: [makeSticker(id: "a")])
        klipyService.downloadImageFromReturnValue = .failure(.downloadFailed)
        
        let deferred = deferFulfillment(context.observe(\.viewState.sendingStickerID)) { $0 == nil }
        context.send(viewAction: .send(makeSticker(id: "a")))
        #expect(context.viewState.sendingStickerID == "a")
        try await deferred.fulfill()
        
        #expect(!stickerService.sendExternalStickerImageDataBodyWidthHeightMimeTypeInCalled)
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
    }
    
    @Test
    mutating func addingAStickerShowsASummaryIndicator() async throws {
        setupViewModel(stickers: [makeSticker(id: "a")])
        stickerService.addExternalStickerImageDataBodyWidthHeightMimeTypeReturnValue = StickerBatchSummary(added: 1)
        
        let deferred = deferFulfillment(context.observe(\.viewState.addingStickerIDs)) { $0.isEmpty == false }
        context.send(viewAction: .add(makeSticker(id: "a")))
        try await deferred.fulfill()
        
        // Wait for the add to finish.
        while !stickerService.addExternalStickerImageDataBodyWidthHeightMimeTypeCalled {
            await Task.yield()
        }
        while userIndicatorController.submitIndicatorDelayCallsCount == 0 {
            await Task.yield()
        }
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
    }
    
    @Test
    mutating func loadMoreAppendsTheNextPage() async throws {
        setupViewModel(stickers: [makeSticker(id: "a")], hasNextPage: true)
        let loaded = deferFulfillment(context.observe(\.viewState.results)) { !$0.isEmpty }
        try await loaded.fulfill()
        
        klipyService.searchQueryPageReturnValue = .success(.init(stickers: [makeSticker(id: "b")], hasNextPage: false, nextPage: 3))
        
        let deferred = deferFulfillment(context.observe(\.viewState.results)) { $0.count == 2 }
        context.send(viewAction: .loadMore)
        try await deferred.fulfill()
        
        #expect(context.viewState.results.map(\.id) == ["a", "b"])
        #expect(context.viewState.hasNextPage == false)
    }
    
    @Test
    mutating func aFailedSearchSurfacesTheErrorState() async throws {
        setupViewModel(stickers: [])
        klipyService.searchQueryPageReturnValue = .failure(.requestFailed)
        
        let deferred = deferFulfillment(context.observe(\.viewState.hasFailed)) { $0 }
        context.send(viewAction: .retry)
        try await deferred.fulfill()
        
        #expect(context.viewState.hasFailed)
    }
    
    // MARK: - Private
    
    private mutating func setupViewModel(stickers: [KlipySticker], hasNextPage: Bool = false) {
        klipyService = KlipyServiceMock()
        klipyService.searchQueryPageReturnValue = .success(.init(stickers: stickers, hasNextPage: hasNextPage, nextPage: 2))
        klipyService.downloadImageFromReturnValue = .success(Data("bytes".utf8))
        
        stickerService = StickerServiceMock()
        stickerService.sendExternalStickerImageDataBodyWidthHeightMimeTypeInReturnValue = .success(())
        stickerService.addExternalStickerImageDataBodyWidthHeightMimeTypeReturnValue = StickerBatchSummary(added: 1)
        
        timelineController = TimelineControllerMock(.init())
        userIndicatorController = UserIndicatorControllerMock()
        
        viewModel = StickerDiscoveryScreenViewModel(klipyService: klipyService,
                                                    stickerService: stickerService,
                                                    timelineController: timelineController,
                                                    mediaProvider: MediaProviderMock(.init()),
                                                    userIndicatorController: userIndicatorController)
    }
}
