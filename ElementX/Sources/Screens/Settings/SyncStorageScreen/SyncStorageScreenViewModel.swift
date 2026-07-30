//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias SyncStorageScreenViewModelType = StateStoreViewModelV2<SyncStorageScreenViewState, SyncStorageScreenViewAction>

class SyncStorageScreenViewModel: SyncStorageScreenViewModelType, SyncStorageScreenViewModelProtocol {
    private let historyDownloadManager: HistoryDownloadManagerProtocol
    private let appSettings: AppSettings
    
    /// Storage is measured by walking directories, which is too slow to do on every
    /// progress update, so it's sampled on a timer instead.
    private var storageTask: Task<Void, Never>?
    private var settingsObservationTask: Task<Void, Never>?
    private var backgroundObservationTask: Task<Void, Never>?
    private var enabledObservationTask: Task<Void, Never>?
    
    private let actionsSubject: PassthroughSubject<SyncStorageScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<SyncStorageScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(historyDownloadManager: HistoryDownloadManagerProtocol, appSettings: AppSettings) {
        self.historyDownloadManager = historyDownloadManager
        self.appSettings = appSettings
        
        super.init(initialViewState: SyncStorageScreenViewState(bindings: .init(historyDownloadEnabled: appSettings.historyDownloadEnabled,
                                                                                historyDownloadOnWiFiOnly: appSettings.historyDownloadOnWiFiOnly,
                                                                                historyDownloadInBackground: appSettings.historyDownloadInBackground)))
        
        // resume() and pause() own the setting, so the switch calls them rather than
        // writing it itself — otherwise the two could disagree.
        enabledObservationTask = Task { [weak self] in
            guard let self else { return }
            for await isEnabled in context.observe(\.viewState.bindings.historyDownloadEnabled).removeDuplicates() {
                guard isEnabled != appSettings.historyDownloadEnabled else { continue }
                if isEnabled {
                    historyDownloadManager.resume()
                } else {
                    historyDownloadManager.pause()
                }
            }
        }
        
        // Push the toggles back into settings. The download checks these between
        // batches, so switching Wi-Fi only on mid-download stops it shortly after.
        settingsObservationTask = Task { [weak self] in
            guard let self else { return }
            for await value in context.observe(\.viewState.bindings.historyDownloadOnWiFiOnly).removeDuplicates() {
                appSettings.historyDownloadOnWiFiOnly = value
            }
        }
        
        backgroundObservationTask = Task { [weak self] in
            guard let self else { return }
            for await value in context.observe(\.viewState.bindings.historyDownloadInBackground).removeDuplicates() {
                appSettings.historyDownloadInBackground = value
            }
        }
        
        historyDownloadManager.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                
                // Note when a pass begins so the estimate has something to measure from.
                if state.progress.status == .notStarted || state.startedAt == nil,
                   case .downloading = progress.status {
                    state.startedAt = .now
                }
                state.progress = progress
            }
            .store(in: &cancellables)
    }
    
    override func process(viewAction: SyncStorageScreenViewAction) {
        switch viewAction {
        case .appeared:
            refreshStorage()
        case .pause:
            historyDownloadManager.pause()
        case .resume:
            historyDownloadManager.resume()
        case .retry:
            historyDownloadManager.retryFailed()
        case .rebuildIndex:
            Task {
                await historyDownloadManager.rebuildSearchIndex()
                refreshStorage()
            }
        case .clearHistory:
            Task {
                await historyDownloadManager.clearOfflineHistory()
                refreshStorage()
            }
        case .toggleAdvanced:
            withElementAnimation {
                state.isAdvancedExpanded.toggle()
            }
        }
    }
    
    // MARK: - Private
    
    private func refreshStorage() {
        storageTask?.cancel()
        storageTask = Task { [weak self] in
            guard let self else { return }
            let usage = await historyDownloadManager.storageUsage()
            guard !Task.isCancelled else { return }
            state.storage = usage
        }
    }
}
