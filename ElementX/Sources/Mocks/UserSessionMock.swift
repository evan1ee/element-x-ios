//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

struct UserSessionMockConfiguration {
    var clientProxy: ClientProxyProtocol = ClientProxyMock(.init())
    var userSettings: UserSettings = .mock()
    var userHooks = UserHooks()
    var contentScannerService: ContentScannerServiceProtocol?
    var liveLocationService: LiveLocationServiceProtocol = LiveLocationServiceMock(.init())
    var notificationService: NotificationServiceProtocol = NotificationServiceMock(.init())
}

@MainActor extension UserSessionMock {
    convenience init(_ configuration: UserSessionMockConfiguration) {
        self.init()
        
        clientProxy = configuration.clientProxy
        userSettings = configuration.userSettings
        userHooks = configuration.userHooks
        callbacks = .init()
        
        mediaProvider = MediaProviderMock(.init())
        voiceMessageMediaManager = VoiceMessageMediaManagerMock()
        contentScannerService = configuration.contentScannerService
        
        sessionSecurityStatePublisher = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .enabled)).asCurrentValuePublisher()
        
        liveLocationService = configuration.liveLocationService
        notificationService = configuration.notificationService
        
        // No per-room state, so screens reading it show nothing rather than trapping on
        // an un-configured mock. Tests wanting the download visible replace this.
        let historyDownloadManagerMock = HistoryDownloadManagerMock()
        historyDownloadManagerMock.underlyingProgressPublisher = CurrentValueSubject<HistoryDownloadProgress, Never>(.init()).asCurrentValuePublisher()
        historyDownloadManagerMock.underlyingRoomStatesPublisher = CurrentValueSubject<[String: RoomHistoryState], Never>([:]).asCurrentValuePublisher()
        historyDownloadManager = historyDownloadManagerMock
        
        // Idle and switched off, matching the default. Same reasoning as above: a
        // screen that reads it gets an answer instead of trapping.
        let backupManagerMock = BackupManagerMock()
        backupManagerMock.underlyingProgressPublisher = CurrentValueSubject<BackupProgress, Never>(.init()).asCurrentValuePublisher()
        backupManagerMock.underlyingRestoreProgressPublisher = CurrentValueSubject<RestoreProgress, Never>(.init()).asCurrentValuePublisher()
        backupManagerMock.availableProvidersReturnValue = []
        backupManagerMock.underlyingSelectedProviderID = .iCloud
        backupManagerMock.underlyingIsEnabled = false
        backupManager = backupManagerMock
        
        // An empty index. The Photos tab reads this as the session starts, so leaving it
        // un-configured traps before any test gets going.
        let searchIndexServiceMock = SearchIndexServiceMock()
        searchIndexServiceMock.searchReturnValue = []
        searchIndexServiceMock.browseReturnValue = []
        searchIndexServiceMock.roomsWithMediaInReturnValue = []
        searchIndexService = searchIndexServiceMock
        
        // Resolved to nothing, so screens asking whether a room is Saved Messages get a
        // plain no. Tests exercising the feature substitute a mock with a room ID.
        let savedMessagesServiceMock = SavedMessagesServiceMock()
        savedMessagesServiceMock.underlyingRoomIDPublisher = CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher()
        savedMessagesServiceMock.isSavedMessagesRoomReturnValue = false
        savedMessagesService = savedMessagesServiceMock
    }
}
