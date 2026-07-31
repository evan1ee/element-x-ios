//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDKMocks
import Testing

@MainActor
struct SavedMessagesServiceTests {
    let existingRoomID = "!saved:example.com"
    
    @Test
    func reusesTheRoomRecordedInAccountData() async throws {
        let clientProxy = makeClientProxy(rooms: [.mock(id: existingRoomID, name: "Saved Messages")])
        clientProxy.accountDataEventTypeReturnValue = .success(accountDataContent(roomID: existingRoomID))
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        let result = await service.setUp()
        
        #expect(try result.get() == existingRoomID)
        #expect(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartCallsCount == 0)
        #expect(service.isSavedMessagesRoom(existingRoomID))
    }
    
    @Test
    func createsAnEncryptedSoloRoomWhenAccountDataIsEmpty() async throws {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        let result = await service.setUp()
        
        #expect(try result.get() == existingRoomID)
        
        let arguments = try #require(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReceivedArguments)
        // `.private` is what makes the room encrypted, invite-only and unlisted.
        #expect(arguments.accessType == .private)
        #expect(arguments.userIDs.isEmpty)
        #expect(!arguments.isSpace)
    }
    
    @Test
    func recordsTheNewRoomInAccountData() async throws {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        _ = await service.setUp()
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        #expect(arguments.eventType == SavedMessagesRoomInfo.eventType)
        
        let info = try JSONDecoder().decode(SavedMessagesRoomInfo.self, from: Data(arguments.content.utf8))
        #expect(info.roomID == existingRoomID)
        #expect(info.version == SavedMessagesRoomInfo.currentVersion)
    }
    
    @Test
    func replacesARoomTheUserIsNoLongerJoinedTo() async throws {
        // Account data points at a room the summary provider doesn't know about, which is
        // what leaving from another client looks like.
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(accountDataContent(roomID: "!left:example.com"))
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        let result = await service.setUp()
        
        #expect(try result.get() == existingRoomID)
        #expect(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartCallsCount == 1)
    }
    
    @Test
    func resolvesOnlyOnceAcrossRepeatedCalls() async {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        _ = await service.setUp()
        _ = await service.setUp()
        
        #expect(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartCallsCount == 1)
    }
    
    @Test
    func retriesTheAccountDataWriteAfterItFails() async throws {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        // The room still works, it just isn't durable yet.
        let result = await service.setUp()
        #expect(throws: SavedMessagesServiceError.self) { try result.get() }
        #expect(service.roomIDPublisher.value == existingRoomID)
        
        // A later call retries the write rather than creating a second room.
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        _ = await service.setUp()
        
        #expect(clientProxy.setAccountDataEventTypeContentCallsCount == 2)
        #expect(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartCallsCount == 1)
    }
    
    @Test
    func reportsARoomItHasNotResolvedAsNotSavedMessages() {
        let service = SavedMessagesService(clientProxy: makeClientProxy())
        
        #expect(!service.isSavedMessagesRoom(existingRoomID))
        #expect(service.roomIDPublisher.value == nil)
    }
    
    @Test
    func savingSendsTheContentIntoTheResolvedRoom() async throws {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(accountDataContent(roomID: existingRoomID))
        
        // Pinned so the send can be asserted on; the default closure builds a fresh proxy per call.
        let roomProxy = JoinedRoomProxyMock(.init(id: existingRoomID, name: "Saved Messages"))
        let timeline = TimelineProxyMock(.init())
        roomProxy.timeline = timeline
        clientProxy.roomForIdentifierClosure = { $0 == existingRoomID ? .joined(roomProxy) : nil }
        
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        let result = await service.save(RoomMessageEventContentWithoutRelationSDKMock())
        
        #expect(throws: Never.self) { try result.get() }
        #expect(timeline.sendMessageEventContentCallsCount == 1)
    }
    
    @Test
    func savingCreatesTheRoomWhenItHasNotBeenSetUpYet() async {
        // Nothing has called `setUp`, so saving has to resolve the room on the spot.
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .success(existingRoomID)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        _ = await service.save(RoomMessageEventContentWithoutRelationSDKMock())
        
        #expect(clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartCallsCount == 1)
    }
    
    @Test
    func savingFailsWhenTheRoomCannotBeRetrieved() async {
        let clientProxy = makeClientProxy()
        clientProxy.accountDataEventTypeReturnValue = .success(accountDataContent(roomID: existingRoomID))
        clientProxy.createRoomNameTopicAccessTypeIsSpaceUserIDsAvatarURLAliasLocalPartReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        let service = SavedMessagesService(clientProxy: clientProxy)
        
        let result = await service.save(RoomMessageEventContentWithoutRelationSDKMock())
        
        #expect(throws: SavedMessagesServiceError.self) { try result.get() }
    }
    
    // MARK: - Helpers
    
    /// A client whose summary provider has already loaded, so `setUp` doesn't wait for a sync.
    private func makeClientProxy(rooms: [RoomSummary] = []) -> ClientProxyMock {
        ClientProxyMock(.init(roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms)))))
    }
    
    private func accountDataContent(roomID: String) -> String {
        """
        { "room_id": "\(roomID)", "created_at": 1700000000000, "version": 1 }
        """
    }
}
