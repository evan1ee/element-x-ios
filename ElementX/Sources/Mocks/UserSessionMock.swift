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
    var contentScannerService: ContentScannerServiceProtocol?
}

@MainActor extension UserSessionMock {
    convenience init(_ configuration: UserSessionMockConfiguration) {
        self.init()
        
        clientProxy = configuration.clientProxy
        mediaProvider = MediaProviderMock(.init())
        voiceMessageMediaManager = VoiceMessageMediaManagerMock()
        contentScannerService = configuration.contentScannerService
        
        sessionSecurityStatePublisher = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .enabled)).asCurrentValuePublisher()
        
        liveLocationManager = LiveLocationManagerMock(.init())
        
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
    }
}
