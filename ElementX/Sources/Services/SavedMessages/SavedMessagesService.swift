//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// Resolves the room backing Saved Messages, creating it on first use.
///
/// The room is an ordinary private encrypted room with the user as its only member,
/// so timelines, search, sync and offline support all come for free. The only thing
/// that makes it special is the pointer we keep in account data, which is what lets
/// a second device find the same room rather than making its own.
class SavedMessagesService: SavedMessagesServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    
    private let roomIDSubject = CurrentValueSubject<String?, Never>(nil)
    var roomIDPublisher: CurrentValuePublisher<String?, Never> {
        roomIDSubject.asCurrentValuePublisher()
    }
    
    /// Set when we have a room but failed to record it in account data. Until this clears,
    /// another device signing in would create a second room, so we retry on every `setUp`.
    private var infoPendingStore: SavedMessagesRoomInfo?
    
    private var setUpTask: Task<Result<String, SavedMessagesServiceError>, Never>?
    
    init(clientProxy: ClientProxyProtocol) {
        self.clientProxy = clientProxy
    }
    
    @discardableResult
    func setUp() async -> Result<String, SavedMessagesServiceError> {
        if let roomID = roomIDSubject.value {
            if let infoPendingStore {
                _ = await store(infoPendingStore)
            }
            return .success(roomID)
        }
        
        if let setUpTask {
            return await setUpTask.value
        }
        
        let task = Task { await resolveOrCreateRoom() }
        setUpTask = task
        let result = await task.value
        setUpTask = nil
        return result
    }
    
    /// Resolves the room in the background once the session has synced.
    func start() {
        Task { await setUp() }
    }
    
    func isSavedMessagesRoom(_ roomID: String) -> Bool {
        roomIDSubject.value == roomID
    }
    
    // MARK: - Private
    
    private func resolveOrCreateRoom() async -> Result<String, SavedMessagesServiceError> {
        // Account data is read from the local store, so asking before the first sync has
        // landed would report no room and have us create a second one. Waiting costs a
        // moment on a cold launch and saves the user a duplicate room forever.
        await waitForInitialSync()
        
        if let roomID = await recordedRoomID() {
            roomIDSubject.send(roomID)
            return .success(roomID)
        }
        
        return await createRoom()
    }
    
    private func waitForInitialSync() async {
        guard !clientProxy.roomSummaryProvider.statePublisher.value.isLoaded else { return }
        
        for await state in clientProxy.roomSummaryProvider.statePublisher.values where state.isLoaded {
            return
        }
    }
    
    /// The room named in account data, but only while we're still joined to it. Anything
    /// else — no account data yet, or a room left from another client — means we need a new one.
    private func recordedRoomID() async -> String? {
        guard case let .success(content) = await clientProxy.accountData(eventType: SavedMessagesRoomInfo.eventType),
              let content,
              let info = try? JSONDecoder().decode(SavedMessagesRoomInfo.self, from: Data(content.utf8)) else {
            return nil
        }
        
        guard case .joined = await clientProxy.roomForIdentifier(info.roomID) else {
            MXLog.info("No longer joined to the recorded Saved Messages room, creating a replacement")
            return nil
        }
        
        return info.roomID
    }
    
    private func createRoom() async -> Result<String, SavedMessagesServiceError> {
        // `.private` already means encrypted, invite-only and unlisted, which is the whole
        // requirement. The name is only ever seen by other Matrix clients — we render our
        // own localised title — so it's a best-effort fallback rather than the source of truth.
        let result = await clientProxy.createRoom(name: UntranslatedL10n.commonSavedMessages,
                                                  topic: nil,
                                                  accessType: .private,
                                                  isSpace: false,
                                                  userIDs: [],
                                                  avatarURL: nil,
                                                  aliasLocalPart: nil)
        
        guard case let .success(roomID) = result else {
            MXLog.error("Failed creating the Saved Messages room")
            return .failure(.roomCreationFailed)
        }
        
        let info = SavedMessagesRoomInfo(roomID: roomID)
        let storeResult = await store(info)
        
        // The room works either way, so publish it and let the user get on with it. A failed
        // write is retried by `setUp`; if it never lands, another device will create its own room.
        roomIDSubject.send(roomID)
        
        switch storeResult {
        case .success:
            return .success(roomID)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    private func store(_ info: SavedMessagesRoomInfo) async -> Result<Void, SavedMessagesServiceError> {
        guard let content = try? String(data: JSONEncoder().encode(info), encoding: .utf8) else {
            return .failure(.accountDataUpdateFailed)
        }
        
        switch await clientProxy.setAccountData(eventType: SavedMessagesRoomInfo.eventType, content: content) {
        case .success:
            infoPendingStore = nil
            return .success(())
        case .failure(let error):
            MXLog.error("Failed recording the Saved Messages room with error: \(error)")
            infoPendingStore = info
            return .failure(.accountDataUpdateFailed)
        }
    }
}
