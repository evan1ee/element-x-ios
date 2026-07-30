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
    private let indexService: SearchIndexServiceProtocol
    
    /// The activity each room had when it was last indexed. A room the list
    /// republishes with a newer message needs another look; one that hasn't changed
    /// doesn't. Nil marks a room seen but with nothing in it yet.
    private var indexedActivity: [String: Date?] = [:]
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
        self.indexService = indexService
        indexer = SearchIndexer(indexService: indexService)
    }
    
    deinit {
        backfillTask?.cancel()
    }
    
    /// Starts following the room list, indexing rooms as they appear and again
    /// whenever one of them receives something new.
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
        // A room qualifies if it has never been indexed, or if its latest message is
        // newer than the one it had when we last looked. That second case is what
        // makes sent and received messages searchable without waiting for a relaunch.
        let pending = summaries.filter { summary in
            guard let previous = indexedActivity[summary.id] else { return true }
            guard let latest = summary.lastMessageDate else { return false }
            return previous.map { latest > $0 } ?? true
        }
        guard !pending.isEmpty else { return }
        
        for summary in pending {
            indexedActivity[summary.id] = summary.lastMessageDate
        }
        let pendingIDs = pending.map(\.id)
        
        // One task at a time. A new room arriving mid-run shouldn't start a second
        // pass competing for the same database.
        let previous = backfillTask
        backfillTask = Task(priority: .background) { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await backfill(roomIDs: pendingIDs)
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
    
    /// Whether a revisit should look at this item again.
    ///
    /// Newer than the watermark is the common case — a message that has arrived since.
    /// Edits and redactions keep the original event's timestamp, so they sit below the
    /// watermark forever and would never be reconsidered; both change what should be
    /// in the index, so they're always let through.
    // Internal so the watermark's edge cases can be tested without a live timeline.
    static func isWorthReindexing(_ item: RoomTimelineItemProtocol, after watermark: Date) -> Bool {
        // A redaction has to reach the indexer so the row is deleted.
        if item is RedactedRoomTimelineItem {
            return true
        }
        
        // Anything without a timestamp isn't indexable anyway; the indexer drops it,
        // and deciding that twice invites the two judgements to drift apart.
        guard let item = item as? EventBasedMessageTimelineItemProtocol else { return true }
        
        return item.timestamp > watermark || item.properties.isEdited
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
        var items = room.timeline.timelineItemProvider.itemProxies.compactMap { proxy -> RoomTimelineItemProtocol? in
            guard case .event(let eventProxy) = proxy else { return nil }
            return timelineItemFactory.buildTimelineItem(for: eventProxy, isDM: isDM)
        }
        
        // On a revisit, only what arrived since last time. Without this a room with a
        // full history downloaded would rewrite thousands of rows for every message.
        // Indexing is an upsert, so the cost is the only thing at stake — but on a
        // busy room that cost lands on every incoming event.
        if let watermark = try? await indexService.latestTimestamp(inRoom: roomID) {
            items = items.filter { Self.isWorthReindexing($0, after: watermark) }
        }
        
        guard !items.isEmpty else { return }
        await indexer.process(items, inRoom: roomID)
    }
}
