//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import Network

/// Walks every room back to the beginning of its history, indexing as it goes, and
/// publishes how far it has got.
///
/// Sits between the SDK and the settings screen so the UI observes progress rather
/// than driving pagination itself.
///
/// A full pass is expensive — it downloads every message in every room — so it runs
/// at background priority, one room at a time, and stops the moment the user's
/// conditions stop being met. Progress is written to the database as it goes, so
/// being killed costs the current chunk rather than the whole run.
final class HistoryDownloadManager: HistoryDownloadManagerProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private let timelineItemFactory: RoomTimelineItemFactoryProtocol
    private let indexService: SearchIndexServiceProtocol
    private let indexer: SearchIndexer
    private let appSettings: AppSettings
    
    private let progressSubject = CurrentValueSubject<HistoryDownloadProgress, Never>(.init())
    var progressPublisher: CurrentValuePublisher<HistoryDownloadProgress, Never> {
        progressSubject.asCurrentValuePublisher()
    }
    
    private let roomStatesSubject = CurrentValueSubject<[String: RoomHistoryState], Never>([:])
    var roomStatesPublisher: CurrentValuePublisher<[String: RoomHistoryState], Never> {
        roomStatesSubject.asCurrentValuePublisher()
    }
    
    private var downloadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    /// Watches for cellular so "Wi-Fi only" can take effect the moment the network
    /// changes rather than at the next room boundary.
    private let pathMonitor = NWPathMonitor()
    private var isOnExpensiveNetwork = false
    
    /// Events per pagination request. Small enough that cancelling is responsive,
    /// large enough not to make a request per handful of messages.
    private static let paginationBatchSize: UInt16 = 100
    /// Ceiling per room per pass. A very long room shouldn't starve every room behind
    /// it — it gets picked up again on the next pass.
    private static let maximumBatchesPerRoom = 50
    private static let delayBetweenBatches = Duration.milliseconds(150)
    
    init(clientProxy: ClientProxyProtocol,
         roomSummaryProvider: RoomSummaryProviderProtocol,
         timelineItemFactory: RoomTimelineItemFactoryProtocol,
         indexService: SearchIndexServiceProtocol,
         appSettings: AppSettings) {
        self.clientProxy = clientProxy
        self.roomSummaryProvider = roomSummaryProvider
        self.timelineItemFactory = timelineItemFactory
        self.indexService = indexService
        self.appSettings = appSettings
        indexer = SearchIndexer(indexService: indexService)
        
        observeNetwork()
    }
    
    deinit {
        downloadTask?.cancel()
        pathMonitor.cancel()
    }
    
    // MARK: - HistoryDownloadManagerProtocol
    
    func start() {
        guard downloadTask == nil else { return }
        guard appSettings.historyDownloadEnabled else {
            update { $0.status = .notStarted }
            return
        }
        
        downloadTask = Task(priority: .background) { [weak self] in
            await self?.run()
            self?.downloadTask = nil
        }
    }
    
    func pause() {
        appSettings.historyDownloadEnabled = false
        downloadTask?.cancel()
        downloadTask = nil
        update { $0.status = .paused(.user) }
    }
    
    func resume() {
        appSettings.historyDownloadEnabled = true
        start()
    }
    
    func retryFailed() {
        Task { [weak self] in
            guard let self else { return }
            
            // Only the failures go back in the queue; finished rooms stay finished.
            var states = roomStatesSubject.value
            for (roomID, state) in states where state.status == .error {
                states[roomID]?.status = .waiting
                try? await indexService.setRoomHistoryState(states[roomID] ?? state)
            }
            roomStatesSubject.send(states)
            
            update { $0.lastError = nil }
            resume()
        }
    }
    
    func rebuildSearchIndex() async {
        downloadTask?.cancel()
        downloadTask = nil
        
        try? await indexService.clear()
        roomStatesSubject.send([:])
        update {
            $0 = HistoryDownloadProgress()
            $0.status = .notStarted
        }
        
        start()
    }
    
    func clearOfflineHistory() async {
        downloadTask?.cancel()
        downloadTask = nil
        
        try? await indexService.clear()
        roomStatesSubject.send([:])
        update { $0 = HistoryDownloadProgress() }
    }
    
    func storageUsage() async -> HistoryStorageUsage {
        await HistoryStorageUsage(databaseBytes: indexService.databaseSize(),
                                  mediaCacheBytes: Self.directorySize(at: .sessionCachesBaseDirectory))
    }
    
    // MARK: - The pass
    
    private func run() async {
        update { $0.status = .preparing }
        
        var states = await (try? indexService.roomHistoryStates()) ?? [:]
        let roomIDs = roomSummaryProvider.roomListPublisher.value.map(\.id)
        
        for roomID in roomIDs where states[roomID] == nil {
            states[roomID] = RoomHistoryState(roomID: roomID)
        }
        roomStatesSubject.send(states)
        
        let pending = roomIDs.filter { states[$0]?.status != .complete }
        
        update {
            $0.roomsTotal = roomIDs.count
            $0.roomsCompleted = roomIDs.count - pending.count
            $0.queueLength = pending.count
            $0.messagesIndexed = states.values.reduce(0) { $0 + $1.messagesIndexed }
        }
        
        guard !pending.isEmpty else {
            update { $0.status = .completed }
            return
        }
        
        update { $0.status = .downloading }
        
        for roomID in pending {
            guard !Task.isCancelled else { return }
            
            if let reason = pauseReason() {
                update { $0.status = .paused(reason) }
                return
            }
            
            await download(roomID: roomID)
            update { $0.queueLength = max($0.queueLength - 1, 0) }
        }
        
        guard !Task.isCancelled else { return }
        
        update {
            $0.activeRoomName = nil
            $0.lastSyncDate = .now
            $0.status = $0.isComplete ? .completed : .downloading
        }
    }
    
    private func download(roomID: String) async {
        guard case .joined(let room) = await clientProxy.roomForIdentifier(roomID) else {
            return
        }
        
        await room.subscribeForUpdates()
        
        let name = room.infoPublisher.value.displayName
        update { $0.activeRoomName = name }
        await setState(roomID: roomID) { $0.status = .downloading }
        
        let isDM = room.infoPublisher.value.isDirect
        var batches = 0
        
        while batches < Self.maximumBatchesPerRoom {
            guard !Task.isCancelled else { return }
            
            if pauseReason() != nil {
                await setState(roomID: roomID) { $0.status = .paused }
                return
            }
            
            // Already at the start of the room: nothing left to fetch.
            if room.timeline.timelineItemProvider.paginationState.backward == .endReached {
                break
            }
            
            switch await room.timeline.paginateBackwards(requestSize: Self.paginationBatchSize) {
            case .success:
                batches += 1
            case .failure:
                await setState(roomID: roomID) { $0.status = .error }
                update {
                    $0.lastError = .server
                    $0.status = .error(.server)
                }
                return
            }
            
            await indexLoadedItems(of: room, roomID: roomID, isDM: isDM)
            
            // Let sync and the UI have a turn between requests.
            try? await Task.sleep(for: Self.delayBetweenBatches)
        }
        
        let reachedStart = room.timeline.timelineItemProvider.paginationState.backward == .endReached
        await setState(roomID: roomID) { $0.status = reachedStart ? .complete : .waiting }
        
        if reachedStart {
            update { $0.roomsCompleted += 1 }
        }
    }
    
    private func indexLoadedItems(of room: JoinedRoomProxyProtocol, roomID: String, isDM: Bool) async {
        let items = room.timeline.timelineItemProvider.itemProxies.compactMap { proxy -> RoomTimelineItemProtocol? in
            guard case .event(let eventProxy) = proxy else { return nil }
            return timelineItemFactory.buildTimelineItem(for: eventProxy, isDM: isDM)
        }
        
        guard !items.isEmpty else { return }
        await indexer.process(items, inRoom: roomID)
        
        // The loaded window is the best count available without a second query, and
        // it only grows as we paginate.
        await setState(roomID: roomID) { $0.messagesIndexed = items.count }
        update { $0.messagesIndexed = roomStatesSubject.value.values.reduce(0) { $0 + $1.messagesIndexed } }
    }
    
    // MARK: - Conditions
    
    private func pauseReason() -> HistoryDownloadPauseReason? {
        if !appSettings.historyDownloadEnabled {
            return .user
        }
        if appSettings.historyDownloadOnWiFiOnly, isOnExpensiveNetwork {
            return .waitingForWiFi
        }
        return nil
    }
    
    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            // `isExpensive` covers cellular and personal hotspots, which is what the
            // Wi-Fi-only setting is really about.
            let isExpensive = path.isExpensive
            Task { @MainActor in
                self?.isOnExpensiveNetwork = isExpensive
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "io.element.elementx.history_download_network"))
    }
    
    // MARK: - State
    
    private func update(_ mutate: (inout HistoryDownloadProgress) -> Void) {
        var progress = progressSubject.value
        mutate(&progress)
        progressSubject.send(progress)
    }
    
    private func setState(roomID: String, _ mutate: (inout RoomHistoryState) -> Void) async {
        var states = roomStatesSubject.value
        var state = states[roomID] ?? RoomHistoryState(roomID: roomID)
        mutate(&state)
        state.lastUpdated = .now
        states[roomID] = state
        roomStatesSubject.send(states)
        
        // Written every time rather than at the end: being killed mid-run should cost
        // the current batch, not the whole pass.
        try? await indexService.setRoomHistoryState(state)
    }
    
    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: [.fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
