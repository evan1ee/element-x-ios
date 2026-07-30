//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// Builds the local search cache in the background so results exist before the user
/// has opened anything.
///
/// Indexing only what's on screen leaves the cache empty on a fresh install and
/// fills it in room by room as the user browses, which isn't a cache so much as a
/// side effect of reading. This walks the room list instead.
///
/// It reaches as far back as the SDK's event cache holds, not to the start of a
/// room's history — going further would mean paginating every room on the server.
final class SearchIndexBackfillService {
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private let timelineItemFactory: RoomTimelineItemFactoryProtocol
    private let indexer: SearchIndexer
    
    /// Rooms already covered this launch. The index itself is the durable record;
    /// this only stops us revisiting a room each time the list republishes.
    private var visitedRoomIDs: Set<String> = []
    private var backfillTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    /// Rooms are handled one at a time with a pause between them. Backfill competes
    /// with sync and with whatever the user is doing, and finishing sooner isn't
    /// worth making the app stutter.
    private let delayBetweenRooms = Duration.milliseconds(250)
    
    /// How many 200ms turns to give a room's timeline before moving on. A room can be
    /// legitimately empty, so this can't wait indefinitely.
    private static let timelineLoadAttempts = 10
    
    init(clientProxy: ClientProxyProtocol,
         roomSummaryProvider: RoomSummaryProviderProtocol,
         timelineItemFactory: RoomTimelineItemFactoryProtocol,
         indexService: SearchIndexServiceProtocol) {
        self.clientProxy = clientProxy
        self.roomSummaryProvider = roomSummaryProvider
        self.timelineItemFactory = timelineItemFactory
        indexer = SearchIndexer(indexService: indexService)
    }
    
    deinit {
        backfillTask?.cancel()
    }
    
    /// Starts following the room list, indexing rooms as they appear.
    func start() {
        roomSummaryProvider.roomListPublisher
            .sink { [weak self] summaries in
                self?.scheduleBackfill(for: summaries)
            }
            .store(in: &cancellables)
    }
    
    func stop() {
        backfillTask?.cancel()
        backfillTask = nil
        cancellables.removeAll()
    }
    
    // MARK: - Private
    
    private func scheduleBackfill(for summaries: [RoomSummary]) {
        let pending = summaries.map(\.id).filter { !visitedRoomIDs.contains($0) }
        guard !pending.isEmpty else { return }
        
        visitedRoomIDs.formUnion(pending)
        
        // One task at a time. A new room arriving mid-run shouldn't start a second
        // pass competing for the same database.
        let previous = backfillTask
        backfillTask = Task(priority: .background) { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await backfill(roomIDs: pending)
        }
    }
    
    private func backfill(roomIDs: [String]) async {
        MXLog.info("Backfilling the search index for \(roomIDs.count) room(s)")
        
        for roomID in roomIDs {
            guard !Task.isCancelled else { return }
            
            await index(roomID: roomID)
            
            // Yield between rooms so sync and the UI keep their turn.
            try? await Task.sleep(for: delayBetweenRooms)
        }
    }
    
    private func index(roomID: String) async {
        guard case .joined(let room) = await clientProxy.roomForIdentifier(roomID) else {
            return
        }
        
        // `timelineItemProvider` is implicitly unwrapped and only exists once the room
        // has been subscribed, so reading it on an unopened room traps. Subscribing is
        // idempotent, and a no-op for rooms the user already has open.
        await room.subscribeForUpdates()
        
        // Subscribing only creates the provider — the items follow on the SDK's diff
        // stream. Reading straight away finds an empty timeline and indexes nothing,
        // so give it a bounded chance to fill.
        for _ in 0..<Self.timelineLoadAttempts where room.timeline.timelineItemProvider.itemProxies.isEmpty {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        
        let isDM = room.infoPublisher.value.isDirect
        let items = room.timeline.timelineItemProvider.itemProxies.compactMap { proxy -> RoomTimelineItemProtocol? in
            guard case .event(let eventProxy) = proxy else { return nil }
            return timelineItemFactory.buildTimelineItem(for: eventProxy, isDM: isDM)
        }
        
        guard !items.isEmpty else { return }
        await indexer.process(items, inRoom: roomID)
    }
}
