//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import UIKit

class UserSession: UserSessionProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    private var authErrorCancellable: AnyCancellable?
    
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    
    let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    let liveLocationManager: LiveLocationManagerProtocol
    
    /// Scans media content, `nil` when no content scanner is configured for the server.
    let contentScannerService: ContentScannerServiceProtocol?
    
    /// The local search index and the two things that fill it: a light pass over what
    /// the event cache already holds, and the optional full history download.
    let searchIndexService: SearchIndexServiceProtocol
    let historyDownloadManager: HistoryDownloadManagerProtocol
    private let searchIndexBackfillService: SearchIndexBackfillService
    
    /// Optional encrypted backup of everything above, plus preferences. Idle unless
    /// the user turns it on.
    let backupManager: BackupManagerProtocol
    
    let callbacks = PassthroughSubject<UserSessionCallback, Never>()
    
    let sessionSecurityStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
    var sessionSecurityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never> {
        sessionSecurityStateSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         voiceMessageMediaManager: VoiceMessageMediaManagerProtocol,
         liveLocationManager: LiveLocationManagerProtocol,
         sessionDirectories: SessionDirectories?,
         appSettings: AppSettings) {
        self.clientProxy = clientProxy
        self.mediaProvider = mediaProvider
        self.voiceMessageMediaManager = voiceMessageMediaManager
        self.liveLocationManager = liveLocationManager
        contentScannerService = clientProxy.contentScanner.map(ContentScannerService.init)
        
        let searchIndexService = SearchIndexService(databaseURL: .searchIndexURL(for: clientProxy.userID))
        self.searchIndexService = searchIndexService
        
        let timelineItemFactory = RoomTimelineItemFactory(userID: clientProxy.userID,
                                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                          stateEventStringBuilder: RoomStateEventStringBuilder(userID: clientProxy.userID))
        
        searchIndexBackfillService = SearchIndexBackfillService(clientProxy: clientProxy,
                                                                roomSummaryProvider: clientProxy.roomSummaryProvider,
                                                                timelineItemFactory: timelineItemFactory,
                                                                indexService: searchIndexService)
        searchIndexBackfillService.start()
        
        // Only runs if the user asked for it; otherwise it sits idle reporting not started.
        let historyDownloadManager = HistoryDownloadManager(clientProxy: clientProxy,
                                                            roomSummaryProvider: clientProxy.roomSummaryProvider,
                                                            timelineItemFactory: timelineItemFactory,
                                                            indexService: searchIndexService,
                                                            appSettings: appSettings)
        self.historyDownloadManager = historyDownloadManager
        historyDownloadManager.start()
        
        // Providers are listed in the order the picker shows them. Adding one here is
        // the whole cost of a new destination — nothing in the engine changes.
        backupManager = BackupManager(providers: [ICloudBackupProvider(),
                                                  LocalFileBackupProvider()],
                                      dataSource: SessionBackupDataSource(sessionDirectories: sessionDirectories,
                                                                          searchIndexURL: .searchIndexURL(for: clientProxy.userID),
                                                                          preferencesSuiteName: AppSettings.suiteName,
                                                                          userID: clientProxy.userID),
                                      passphraseStore: BackupPassphraseStore(service: InfoPlistReader.main.baseBundleIdentifier + ".backup",
                                                                             accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier),
                                      appSettings: appSettings,
                                      userID: clientProxy.userID,
                                      deviceName: UIDevice.current.name,
                                      appVersion: InfoPlistReader.main.bundleShortVersionString)
        
        authErrorCancellable = clientProxy.actionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                switch callback {
                case .receivedAuthError(let isSoftLogout):
                    callbacks.send(.didReceiveAuthError(isSoftLogout: isSoftLogout))
                    authErrorCancellable = nil
                default:
                    break
                }
            }
        
        Publishers.CombineLatest(clientProxy.verificationStatePublisher, clientProxy.secureBackupController.recoveryState)
            .map {
                MXLog.info("Session security state changed, verificationState: \($0), recoveryState: \($1)")
                return SessionSecurityState(verificationState: $0, recoveryState: $1)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sessionSecurityStateSubject.send(value)
            }
            .store(in: &cancellables)
    }
}
