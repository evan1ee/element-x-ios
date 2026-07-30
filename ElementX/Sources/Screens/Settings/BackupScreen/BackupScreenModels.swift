//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum BackupScreenViewModelAction {
    case dismiss
}

enum BackupScreenViewAction {
    case appeared
    case selectProvider(BackupProviderID)
    /// Opens the sheet explaining what gets backed up and asking for a passphrase.
    case startEnabling
    case cancelEnabling
    /// The user has read the explanation and entered a passphrase.
    case confirmEnable
    case startDisabling
    case confirmDisable(BackupDisposal)
    case backUpNow
    case startRestoring(BackupDescriptor)
    case cancelRestoring
    case confirmRestore
    case deleteBackup(String)
}

/// A destination as the picker needs it. The screen never holds a provider itself —
/// it shows what it is told and sends back an id.
struct BackupProviderOption: Identifiable, Equatable {
    let id: BackupProviderID
    let name: String
}

struct BackupScreenViewState: BindableState {
    /// Only destinations usable on this device. Somewhere without an iCloud account
    /// shouldn't be offered iCloud.
    var availableProviders: [BackupProviderOption] = []
    var selectedProviderID: BackupProviderID = .iCloud
    var isEnabled = false
    var backup = BackupProgress()
    var restore = RestoreProgress()
    var storage: BackupStorageInfo?
    var backups: [BackupDescriptor] = []
    var bindings = BackupScreenViewStateBindings()
    
    var isBusy: Bool {
        backup.phase.isRunning || restore.phase.isRunning
    }
    
    /// One line for the status row, which is the only part most people read.
    var statusTitle: String {
        switch backup.phase {
        case .idle: UntranslatedL10n.screenBackupStatusIdle
        case .preparing: UntranslatedL10n.screenBackupPhasePreparing
        case .exporting: UntranslatedL10n.screenBackupPhaseExporting
        case .compressing: UntranslatedL10n.screenBackupPhaseCompressing
        case .encrypting: UntranslatedL10n.screenBackupPhaseEncrypting
        case .uploading: UntranslatedL10n.screenBackupPhaseUploading
        case .completed: UntranslatedL10n.screenBackupStatusCompleted
        case .failed: UntranslatedL10n.screenBackupStatusFailed
        }
    }
    
    var restoreStatusTitle: String? {
        switch restore.phase {
        case .idle: nil
        case .findingBackup: UntranslatedL10n.screenBackupRestorePhaseFinding
        case .downloading: UntranslatedL10n.screenBackupRestorePhaseDownloading
        case .validating: UntranslatedL10n.screenBackupRestorePhaseValidating
        case .decrypting: UntranslatedL10n.screenBackupPhaseEncrypting
        case .restoring: UntranslatedL10n.screenBackupRestorePhaseRestoring
        case .completed: UntranslatedL10n.screenBackupStatusCompleted
        case .failed: UntranslatedL10n.screenBackupStatusFailed
        }
    }
    
    var lastBackupDescription: String {
        guard let date = backup.lastBackupDate else { return UntranslatedL10n.screenBackupNever }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct BackupScreenViewStateBindings {
    /// Drives the enable sheet. Enabling is a multi-step decision, so the toggle
    /// itself doesn't own the setting — the sheet's confirmation does.
    var isPresentingEnableSheet = false
    var isPresentingRestoreSheet = false
    var isPresentingDisableConfirmation = false
    
    var passphrase = ""
    var restorePassphrase = ""
    /// Which backup the restore sheet is about.
    var restoreTarget: BackupDescriptor?
    
    var alertInfo: AlertInfo<BackupScreenAlertType>?
}

enum BackupScreenAlertType: Hashable {
    case error
}

/// Turns an error into something worth reading. Kept next to the screen because it's
/// presentation: the same case says different things to a log and to a person.
extension BackupError {
    var localizedTitle: String {
        switch self {
        case .providerUnavailable: UntranslatedL10n.screenBackupErrorProviderUnavailable
        case .notAuthenticated: UntranslatedL10n.screenBackupErrorNotAuthenticated
        case .storageFull: UntranslatedL10n.screenBackupErrorStorageFull
        case .network: UntranslatedL10n.screenBackupErrorNetwork
        case .corruptedPackage: UntranslatedL10n.screenBackupErrorCorrupted
        case .decryptionFailed: UntranslatedL10n.screenBackupErrorDecryption
        case .encryptionFailed: UntranslatedL10n.screenBackupErrorEncryption
        case .versionMismatch: UntranslatedL10n.screenBackupErrorVersion
        case .permissionDenied: UntranslatedL10n.screenBackupErrorPermission
        case .payloadTooLarge: UntranslatedL10n.screenBackupErrorTooLarge
        case .accountMismatch: UntranslatedL10n.screenBackupErrorAccountMismatch
        case .cancelled, .providerFailure: L10n.commonSomethingWentWrong
        }
    }
}
