//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AsyncAlgorithms
import Combine
import SwiftUI

typealias SearchScreenViewModelType = StateStoreViewModelV2<SearchScreenViewState, SearchScreenViewAction>

class SearchScreenViewModel: SearchScreenViewModelType, SearchScreenViewModelProtocol {
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private let searchService: SearchServiceProxyProtocol
    /// Attachments and links. The SDK's search covers message bodies but takes text
    /// messages alone, so filenames and URLs would otherwise be unreachable.
    private let searchIndexService: SearchIndexServiceProtocol
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private var localSearchTask: Task<Void, Never>?
    private var searchQueryObservationTask: Task<Void, Never>?
    private var searchModeObservationTask: Task<Void, Never>?
    private var loadingObservationTask: Task<Void, Never>?
    private var setQueryTask: Task<Void, Never>?
    /// The query each tab last searched, so switching tabs only re-searches when the query changed.
    private var searchedQueries: [SearchScreenMode: String] = [:]
    
    private let actionsSubject: PassthroughSubject<SearchScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<SearchScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(roomSummaryProvider: RoomSummaryProviderProtocol,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         searchIndexService: SearchIndexServiceProtocol,
         historyDownloadManager: HistoryDownloadManagerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         initialSearchQuery: String = "",
         initialSearchMode: SearchScreenMode = .messages) {
        self.roomSummaryProvider = roomSummaryProvider
        self.searchIndexService = searchIndexService
        self.clientProxy = clientProxy
        searchService = clientProxy.searchService
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: SearchScreenViewState(bindings: .init(searchQuery: initialSearchQuery, searchMode: initialSearchMode)),
                   mediaProvider: mediaProvider)
        
        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.updateRooms(with: summaries)
            }
            .store(in: &cancellables)
        
        historyDownloadManager.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                switch progress.status {
                case .preparing, .downloading:
                    self?.state.isHistoryIncomplete = true
                default:
                    self?.state.isHistoryIncomplete = false
                }
            }
            .store(in: &cancellables)
        
        searchService.resultsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                guard let self else { return }
                // A previous query's fetch can complete after the field was cleared; drop its late results.
                guard !state.bindings.searchQuery.isEmpty else {
                    state.messages = []
                    return
                }
                remoteMessages = results.map { result in
                    SearchScreenMessage(result,
                                        roomSummary: clientProxy.roomSummaryForIdentifier(result.roomID),
                                        isOutgoing: result.sender.id == clientProxy.userID)
                }
                mergeMessages()
            }
            .store(in: &cancellables)
        
        searchService.paginationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paginationState in
                self?.state.isLoadingMessages = paginationState == .loading
            }
            .store(in: &cancellables)
        
        // Room search is fast so it reacts to every keystroke; message search debounces inside updateFilter.
        let searchQueryStream = context.observe(\.viewState.bindings.searchQuery).removeDuplicates()
        searchQueryObservationTask = Task { [weak self] in
            for await searchQuery in searchQueryStream {
                self?.updateFilter(for: searchQuery)
            }
        }
        
        // Re-run the search when switching tabs so the newly active tab reflects the current query.
        let searchModeStream = context.observe(\.viewState.bindings.searchMode).removeDuplicates()
        searchModeObservationTask = Task { [weak self] in
            for await _ in searchModeStream {
                guard let self else { return }
                updateFilter(for: state.bindings.searchQuery)
            }
        }
        
        // Flip the loading indicator on the moment the user starts typing, ahead of the debounced
        // message query above, so the empty state doesn't flash while the first search is still pending.
        let loadingQueryStream = context.observe(\.viewState.bindings.searchQuery).removeDuplicates()
        loadingObservationTask = Task { [weak self] in
            for await searchQuery in loadingQueryStream {
                self?.setActiveTabLoading(!searchQuery.isEmpty)
            }
        }
        
        updateRooms(with: roomSummaryProvider.roomListPublisher.value)
    }
    
    isolated deinit {
        searchQueryObservationTask?.cancel()
        searchModeObservationTask?.cancel()
        loadingObservationTask?.cancel()
        setQueryTask?.cancel()
    }
    
    // MARK: - Public
    
    override func process(viewAction: SearchScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .appeared:
            // The provider is shared, so other consumers may have changed its filter while we were off-screen.
            // Re-apply ours on every appearance to keep the displayed results in sync with the query.
            updateFilter(for: state.bindings.searchQuery, forced: true)
            loadMedia(reset: true)
        case .selectRoom(let roomID):
            actionsSubject.send(.presentRoom(roomID: roomID, eventID: nil))
        case .selectMessage(let roomID, let eventID):
            actionsSubject.send(.presentRoom(roomID: roomID, eventID: eventID))
        case .reachedTop:
            break // Only the room list paged upwards, and it no longer has a tab.
        case .reachedBottom:
            switch state.bindings.searchMode {
            case .messages:
                Task { await searchService.paginate() }
            case .media:
                break // The grid drives its own paging through `reachedMediaBottom`.
            }
        case .cancel:
            actionsSubject.send(.cancel)
        case .selectAsset(let asset):
            actionsSubject.send(.presentRoom(roomID: asset.roomID, eventID: asset.eventID))
        case .reachedMediaBottom:
            loadMedia(reset: false)
        case .mediaFiltersChanged:
            loadMedia(reset: true)
        }
    }
    
    // MARK: - Media library
    
    private var mediaLoadTask: Task<Void, Never>?
    /// Stops the grid asking for another page once the index has run out.
    private var hasLoadedAllMedia = false
    
    private static let mediaPageSize = 60
    
    private func loadMedia(reset: Bool) {
        if reset {
            mediaLoadTask?.cancel()
            hasLoadedAllMedia = false
        } else if hasLoadedAllMedia || state.isLoadingMedia {
            return
        }
        
        let offset = reset ? 0 : state.media.count
        state.isLoadingMedia = true
        
        mediaLoadTask = Task { [weak self] in
            guard let self else { return }
            
            var query = SearchIndexBrowseQuery(limit: Self.mediaPageSize, offset: offset)
            if let category = state.bindings.mediaCategory {
                query.categories = [category]
            }
            query.senderID = state.bindings.mediaSenderID
            query.after = state.bindings.mediaDateRange.after
            
            let entries = await (try? searchIndexService.browse(query)) ?? []
            
            guard !Task.isCancelled else { return }
            
            let assets = entries.compactMap {
                MediaLibraryAsset($0, roomSummary: clientProxy.roomSummaryForIdentifier($0.roomID))
            }
            
            // Short of a full page means the index has nothing more to give, so stop asking.
            hasLoadedAllMedia = entries.count < Self.mediaPageSize
            state.media = reset ? assets : state.media + assets
            state.isLoadingMedia = false
            
            if reset {
                updateMediaSenders()
            }
        }
    }
    
    /// Names for the sender filter, taken from what's on screen. Cheap, and it can only
    /// offer someone who has actually shared something.
    private func updateMediaSenders() {
        var seen = Set<String>()
        var senders: [SearchScreenMediaSender] = []
        for asset in state.media where seen.insert(asset.senderID).inserted {
            senders.append(SearchScreenMediaSender(id: asset.senderID, name: asset.senderName))
        }
        state.mediaSenders = senders.sorted { $0.name < $1.name }
    }
    
    // MARK: - Private
    
    /// Hits from the SDK's index, and from ours. Kept apart so a late reply from one
    /// source can't wipe out the other's results.
    private var remoteMessages: [SearchScreenMessage] = []
    private var localMessages: [SearchScreenMessage] = []
    
    private func searchLocalIndex(for searchQuery: String) {
        localSearchTask?.cancel()
        localSearchTask = Task { [weak self] in
            guard let self else { return }
            
            let results = await (try? searchIndexService.search(.init(text: searchQuery))) ?? []
            
            // The field may have moved on while we were querying.
            guard !Task.isCancelled, searchQuery == state.bindings.searchQuery else { return }
            
            localMessages = results.map { SearchScreenMessage($0, roomSummary: clientProxy.roomSummaryForIdentifier($0.entry.roomID)) }
            mergeMessages()
        }
    }
    
    /// Newest first across both sources, dropping anything indexed twice.
    private func mergeMessages() {
        var seen = Set<String>()
        state.messages = (remoteMessages + localMessages)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    private func updateFilter(for searchQuery: String, forced: Bool = false) {
        guard !searchQuery.isEmpty else {
            // Supersede any in-flight query so its results can't land after a newer one's.
            setQueryTask?.cancel()
            searchedQueries.removeAll()
            roomSummaryProvider.setFilter(.excludeAll)
            localSearchTask?.cancel()
            remoteMessages = []
            localMessages = []
            state.messages = []
            return
        }
        
        // The media tab browses its own filters rather than the query, so only the messages
        // tab has anything to re-run here.
        let mode = state.bindings.searchMode
        guard mode == .messages else { return }
        // Skip a tab that already ran this query (e.g. switching back and forth) unless forced.
        guard forced || searchedQueries[mode] != searchQuery else { return }
        
        setQueryTask?.cancel()
        setActiveTabLoading(true)
        roomSummaryProvider.setFilter(.search(query: searchQuery))
        setQueryTask = Task { [weak self] in
            // Debounce message queries; superseded keystrokes cancel this before it commits.
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            searchedQueries[mode] = searchQuery
            if case .failure = await searchService.setQuery(searchQuery), !Task.isCancelled {
                userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
            }
        }
        searchLocalIndex(for: searchQuery)
    }
    
    private func setActiveTabLoading(_ isLoading: Bool) {
        switch state.bindings.searchMode {
        case .messages:
            state.isLoadingMessages = isLoading
        case .media:
            break // The media tab loads from its filters, not the search query.
        }
    }
    
    private func updateRooms(with summaries: [RoomSummary]) {
        // The list has caught up with the current filter, so we're no longer waiting on results.
        state.isLoadingRooms = false
        state.rooms = summaries.map { summary in
            let identifier = if summary.isDirect {
                summary.heroes.first?.id ?? summary.canonicalAlias
            } else {
                summary.canonicalAlias
            }
            
            return SearchScreenRoom(id: summary.id,
                                    title: summary.name,
                                    description: identifier ?? "",
                                    avatar: summary.avatar)
        }
    }
    
    /// The actual range values don't matter as long as they contain the lower
    /// or upper bounds. updateVisibleRange is a hybrid API that powers both
    /// sliding sync visible range update and list paginations.
    /// For lists other than the home screen one we don't care about visible ranges,
    /// we just need the respective bounds to be there to trigger a next page load or
    /// a reset to just one page.
    private func updateVisibleRange(edge: UIRectEdge) {
        switch edge {
        case .top:
            roomSummaryProvider.updateVisibleRange(0..<0)
        case .bottom:
            let roomCount = roomSummaryProvider.roomListPublisher.value.count
            roomSummaryProvider.updateVisibleRange(roomCount..<roomCount)
        default:
            break
        }
    }
}
