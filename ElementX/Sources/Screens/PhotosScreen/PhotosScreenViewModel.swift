//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias PhotosScreenViewModelType = StateStoreViewModel<PhotosScreenViewState, PhotosScreenViewAction>

class PhotosScreenViewModel: PhotosScreenViewModelType, PhotosScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let searchIndexService: SearchIndexServiceProtocol
    
    /// Everything the grid shows. GIFs are excluded along with files, links and voice notes:
    /// they're reactions passed around in conversation, not pictures you took.
    private static let categories: Set<MediaCategory> = [.photo, .video]
    private static let pageSize = 90
    
    private var assets: [MediaLibraryAsset] = []
    private var hasLoadedEverything = false
    private var loadTask: Task<Void, Never>?
    
    private let actionsSubject: PassthroughSubject<PhotosScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<PhotosScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         searchIndexService: SearchIndexServiceProtocol,
         historyDownloadManager: HistoryDownloadManagerProtocol) {
        self.clientProxy = clientProxy
        self.searchIndexService = searchIndexService
        
        super.init(initialViewState: PhotosScreenViewState(), mediaProvider: mediaProvider)
        
        // Only while it's actively working. A paused or failed download isn't "still
        // arriving", and saying so would be a banner that never goes away.
        historyDownloadManager.progressPublisher
            .map { progress in
                switch progress.status {
                case .preparing, .downloading: true
                default: false
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.isHistoryIncomplete, on: self)
            .store(in: &cancellables)
    }
    
    override func process(viewAction: PhotosScreenViewAction) {
        switch viewAction {
        case .appeared:
            // Reloaded on every appearance: the backfill keeps indexing while you're elsewhere,
            // so what's on screen goes stale rather than wrong.
            load(reset: true)
        case .selectAsset(let asset):
            state.bindings.previewedAsset = asset
        case .openInChat(let asset):
            // Closed first: it's a full screen cover, so it would otherwise stay sitting on
            // top of the room we've just navigated to.
            state.bindings.previewedAsset = nil
            actionsSubject.send(.presentRoom(roomID: asset.roomID, eventID: asset.eventID))
        case .selectRoom(let roomID):
            guard roomID != state.roomID else { return }
            state.roomID = roomID
            load(reset: true)
        case .reachedBottom:
            load(reset: false)
        }
    }
    
    // MARK: - Private
    
    private func load(reset: Bool) {
        if reset {
            loadTask?.cancel()
            hasLoadedEverything = false
        } else if hasLoadedEverything || state.isLoading {
            return
        }
        
        let offset = reset ? 0 : assets.count
        state.isLoading = true
        
        loadTask = Task { [weak self] in
            guard let self else { return }
            
            let query = SearchIndexBrowseQuery(categories: Self.categories,
                                               roomID: state.roomID,
                                               limit: Self.pageSize,
                                               offset: offset)
            let entries = await (try? searchIndexService.browse(query)) ?? []
            
            guard !Task.isCancelled else { return }
            
            let page = entries.compactMap {
                MediaLibraryAsset($0, roomSummary: clientProxy.roomSummaryForIdentifier($0.roomID))
            }
            
            hasLoadedEverything = entries.count < Self.pageSize
            // Deduplicated because the index keeps growing while you browse, so an offset
            // page can hand back rows an earlier one already had. Two cells with the same
            // identity make SwiftUI hand a tap to the wrong picture.
            assets = reset ? page : Self.appending(page, to: assets)
            state.assets = assets
            state.isLoading = false
            
            if reset {
                await updateRooms()
            }
        }
    }
    
    /// Asked of the whole index rather than of the pages loaded so far, which would only ever
    /// offer the rooms in the first screenful of pictures.
    private func updateRooms() async {
        let roomIDs = await (try? searchIndexService.rooms(withMediaIn: Self.categories)) ?? []
        
        state.rooms = roomIDs
            .map { PhotosScreenRoom(id: $0, name: clientProxy.roomSummaryForIdentifier($0)?.name ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private static func appending(_ page: [MediaLibraryAsset], to assets: [MediaLibraryAsset]) -> [MediaLibraryAsset] {
        var seen = Set(assets.map(\.id))
        return assets + page.filter { seen.insert($0.id).inserted }
    }
}
