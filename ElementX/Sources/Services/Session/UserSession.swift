//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

class UserSession: UserSessionProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    private var authErrorCancellable: AnyCancellable?
    
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    
    let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    let liveLocationManager: LiveLocationManagerProtocol
    
    /// Scans media content, `nil` when no content scanner is configured for the server.
    let contentScannerService: ContentScannerServiceProtocol?
    
    /// The local index of attachments and links. Message bodies come from the SDK's
    /// own index instead, which the client builder configures.
    let searchIndexService: SearchIndexServiceProtocol
    private let searchIndexBackfillService: SearchIndexBackfillService
    
    let callbacks = PassthroughSubject<UserSessionCallback, Never>()
    
    let sessionSecurityStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
    var sessionSecurityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never> {
        sessionSecurityStateSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol, mediaProvider: MediaProviderProtocol, voiceMessageMediaManager: VoiceMessageMediaManagerProtocol, liveLocationManager: LiveLocationManagerProtocol) {
        self.clientProxy = clientProxy
        self.mediaProvider = mediaProvider
        self.voiceMessageMediaManager = voiceMessageMediaManager
        self.liveLocationManager = liveLocationManager
        contentScannerService = clientProxy.contentScanner.map(ContentScannerService.init)
        
        let searchIndexService = SearchIndexService(databaseURL: .searchIndexURL(for: clientProxy.userID))
        self.searchIndexService = searchIndexService
        searchIndexBackfillService = SearchIndexBackfillService(clientProxy: clientProxy,
                                                                roomSummaryProvider: clientProxy.roomSummaryProvider,
                                                                timelineItemFactory: RoomTimelineItemFactory(userID: clientProxy.userID,
                                                                                                             attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                                                                             stateEventStringBuilder: RoomStateEventStringBuilder(userID: clientProxy.userID)),
                                                                indexService: searchIndexService)
        searchIndexBackfillService.start()
        
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
