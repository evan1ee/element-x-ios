//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias StickerDiscoveryScreenViewModelType = StateStoreViewModelV2<StickerDiscoveryScreenViewState, StickerDiscoveryScreenViewAction>

class StickerDiscoveryScreenViewModel: StickerDiscoveryScreenViewModelType, StickerDiscoveryScreenViewModelProtocol {
    private let klipyService: KlipyServiceProtocol
    private let stickerService: StickerServiceProtocol
    private let timelineController: TimelineControllerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<StickerDiscoveryScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<StickerDiscoveryScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var currentPage = 1
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    
    init(klipyService: KlipyServiceProtocol,
         stickerService: StickerServiceProtocol,
         timelineController: TimelineControllerProtocol,
         mediaProvider: MediaProviderProtocol?,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.klipyService = klipyService
        self.stickerService = stickerService
        self.timelineController = timelineController
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: StickerDiscoveryScreenViewState(), mediaProvider: mediaProvider)
        
        performSearch(reset: true)
    }
    
    // MARK: - Public
    
    override func process(viewAction: StickerDiscoveryScreenViewAction) {
        switch viewAction {
        case .search:
            debounceSearch()
        case .retry:
            performSearch(reset: true)
        case .loadMore:
            guard state.hasNextPage, !state.isLoading, !state.isLoadingMore else { return }
            performSearch(reset: false)
        case .send(let sticker):
            send(sticker)
        case .add(let sticker):
            add(sticker)
        case .cancel:
            actionsSubject.send(.dismiss)
        }
    }
    
    // MARK: - Private
    
    private func debounceSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.performSearch(reset: true)
        }
    }
    
    private func performSearch(reset: Bool) {
        let query = state.bindings.searchQuery
        let page = reset ? 1 : currentPage + 1
        
        if reset {
            state.isLoading = true
            state.hasFailed = false
        } else {
            state.isLoadingMore = true
        }
        
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            let result = await klipyService.search(query: query, page: page)
            
            guard !Task.isCancelled, query == state.bindings.searchQuery else { return }
            
            switch result {
            case .success(let results):
                currentPage = page
                if reset {
                    withAnimation { state.results = results.stickers }
                } else {
                    let existingIDs = Set(state.results.map(\.id))
                    let newStickers = results.stickers.filter { !existingIDs.contains($0.id) }
                    withAnimation { state.results.append(contentsOf: newStickers) }
                }
                state.hasNextPage = results.hasNextPage
                state.hasFailed = false
            case .failure:
                if reset {
                    state.results = []
                    state.hasFailed = true
                }
            }
            
            state.isLoading = false
            state.isLoadingMore = false
        }
    }
    
    private func send(_ sticker: KlipySticker) {
        guard state.sendingStickerID == nil else { return }
        
        state.sendingStickerID = sticker.id
        
        Task {
            defer { state.sendingStickerID = nil }
            
            guard case let .success(data) = await klipyService.downloadImage(from: sticker.fileURL) else {
                showFailureIndicator()
                return
            }
            
            switch await stickerService.sendExternalSticker(imageData: data,
                                                            body: body(for: sticker),
                                                            width: sticker.width,
                                                            height: sticker.height,
                                                            mimeType: sticker.mimeType,
                                                            in: timelineController) {
            case .success:
                actionsSubject.send(.sent)
            case .failure:
                showFailureIndicator()
            }
        }
    }
    
    private func add(_ sticker: KlipySticker) {
        guard !state.addingStickerIDs.contains(sticker.id) else { return }
        
        withAnimation { _ = state.addingStickerIDs.insert(sticker.id) }
        
        Task {
            defer { withAnimation { state.addingStickerIDs.remove(sticker.id) } }
            
            guard case let .success(data) = await klipyService.downloadImage(from: sticker.fileURL) else {
                showFailureIndicator()
                return
            }
            
            let summary = await stickerService.addExternalSticker(imageData: data,
                                                                  body: body(for: sticker),
                                                                  width: sticker.width,
                                                                  height: sticker.height,
                                                                  mimeType: sticker.mimeType)
            showSummaryIndicator(summary)
        }
    }
    
    private func body(for sticker: KlipySticker) -> String {
        sticker.title.isEmpty ? "sticker" : sticker.title
    }
    
    private func showFailureIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorUnknown, icon: \.close))
    }
    
    private func showSummaryIndicator(_ summary: StickerBatchSummary) {
        if summary.added > 0 {
            userIndicatorController.submitIndicator(UserIndicator(title: UntranslatedL10n.screenStickerPickerAddedCount(summary.added), icon: \.check))
        } else if summary.duplicates > 0 {
            userIndicatorController.submitIndicator(UserIndicator(title: UntranslatedL10n.screenStickerPickerDuplicateCount(summary.duplicates), icon: \.info))
        } else {
            userIndicatorController.submitIndicator(UserIndicator(title: UntranslatedL10n.screenStickerPickerFailedCount(max(summary.failed, 1)), icon: \.close))
        }
    }
}
