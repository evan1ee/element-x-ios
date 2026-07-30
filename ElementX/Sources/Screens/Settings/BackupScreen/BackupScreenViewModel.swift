//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias BackupScreenViewModelType = StateStoreViewModelV2<BackupScreenViewState, BackupScreenViewAction>

class BackupScreenViewModel: BackupScreenViewModelType, BackupScreenViewModelProtocol {
    private let backupManager: BackupManagerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private var refreshTask: Task<Void, Never>?
    
    private let actionsSubject: PassthroughSubject<BackupScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<BackupScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(backupManager: BackupManagerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.backupManager = backupManager
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: BackupScreenViewState(selectedProviderID: backupManager.selectedProviderID,
                                                           isEnabled: backupManager.isEnabled))
        
        backupManager.progressPublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.backup, on: self)
            .store(in: &cancellables)
        
        backupManager.restoreProgressPublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.restore, on: self)
            .store(in: &cancellables)
    }
    
    override func process(viewAction: BackupScreenViewAction) {
        switch viewAction {
        case .appeared:
            refresh()
        case .selectProvider(let id):
            backupManager.selectProvider(id)
            state.selectedProviderID = id
            // Each destination holds its own backups, so everything listed is now stale.
            state.backups = []
            state.storage = nil
            refresh()
        case .startEnabling:
            state.bindings.passphrase = ""
            state.bindings.isPresentingEnableSheet = true
        case .cancelEnabling:
            state.bindings.isPresentingEnableSheet = false
            state.bindings.passphrase = ""
        case .confirmEnable:
            enable()
        case .startDisabling:
            state.bindings.isPresentingDisableConfirmation = true
        case .confirmDisable(let disposal):
            disable(disposal)
        case .backUpNow:
            backUpNow()
        case .startRestoring(let descriptor):
            state.bindings.restorePassphrase = ""
            state.bindings.restoreTarget = descriptor
            state.bindings.isPresentingRestoreSheet = true
        case .cancelRestoring:
            state.bindings.isPresentingRestoreSheet = false
            state.bindings.restoreTarget = nil
            state.bindings.restorePassphrase = ""
        case .confirmRestore:
            restore()
        case .deleteBackup(let id):
            deleteBackup(id)
        }
    }
    
    // MARK: - Private
    
    private func enable() {
        let passphrase = state.bindings.passphrase
        guard !passphrase.isEmpty else { return }
        
        state.bindings.isPresentingEnableSheet = false
        state.bindings.passphrase = ""
        
        Task {
            switch await backupManager.enable(passphrase: passphrase) {
            case .success:
                state.isEnabled = true
                refresh()
            case .failure(let error):
                // The manager leaves the setting off when the first backup fails, so
                // the toggle has to follow it back rather than showing a lie.
                state.isEnabled = false
                show(error)
            }
        }
    }
    
    private func disable(_ disposal: BackupDisposal) {
        state.bindings.isPresentingDisableConfirmation = false
        
        Task {
            switch await backupManager.disable(disposal: disposal) {
            case .success:
                state.isEnabled = false
                refresh()
            case .failure(let error):
                show(error)
                // Turning it off succeeded even when clearing up didn't, so don't
                // put the toggle back on.
                state.isEnabled = backupManager.isEnabled
            }
        }
    }
    
    private func backUpNow() {
        Task {
            if case .failure(let error) = await backupManager.backUpNow() {
                show(error)
            }
            refresh()
        }
    }
    
    private func restore() {
        guard let descriptor = state.bindings.restoreTarget else { return }
        let passphrase = state.bindings.restorePassphrase
        
        state.bindings.isPresentingRestoreSheet = false
        state.bindings.restorePassphrase = ""
        
        Task {
            switch await backupManager.restore(descriptor: descriptor, passphrase: passphrase) {
            case .success:
                userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenBackupStatusCompleted))
            case .failure(let error):
                show(error)
            }
            state.bindings.restoreTarget = nil
        }
    }
    
    private func deleteBackup(_ id: String) {
        Task {
            if case .failure(let error) = await backupManager.deleteBackup(id: id) {
                show(error)
            }
            refresh()
        }
    }
    
    /// Re-reads everything the destination can tell us. Cancels any in-flight refresh
    /// so switching providers quickly can't have the slower answer land last.
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            
            let providers = await backupManager.availableProviders()
            guard !Task.isCancelled else { return }
            state.availableProviders = providers.map { .init(id: $0.id, name: $0.name) }
            
            // The default is iCloud, which isn't available everywhere. Left alone, the
            // picker would show no selection at all and enabling would fail against a
            // destination the user was never shown, so fall back to one that works.
            if !providers.contains(where: { $0.id == backupManager.selectedProviderID }),
               let fallback = providers.first {
                backupManager.selectProvider(fallback.id)
            }
            state.selectedProviderID = backupManager.selectedProviderID
            
            // Only ask the destination for its contents once backups are switched on;
            // before that there is nothing to show and iCloud would be woken for nothing.
            guard backupManager.isEnabled else {
                state.backups = []
                state.storage = nil
                return
            }
            
            if case .success(let backups) = await backupManager.listBackups(), !Task.isCancelled {
                state.backups = backups
            }
            if case .success(let storage) = await backupManager.storageInfo(), !Task.isCancelled {
                state.storage = storage
            }
        }
    }
    
    private func show(_ error: BackupError) {
        state.bindings.alertInfo = AlertInfo(id: .error,
                                             title: error.localizedTitle,
                                             message: nil)
    }
}
