//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SyncStorageScreenViewModelAction {
    case dismiss
}

enum SyncStorageScreenViewAction {
    case appeared
    case pause
    case resume
    case retry
    case rebuildIndex
    case clearHistory
    case toggleAdvanced
}

/// Which destructive action the confirmation sheet is about to perform.
enum SyncStorageConfirmation: Identifiable {
    case rebuildIndex
    case clearHistory
    
    var id: Self {
        self
    }
    
    var title: String {
        switch self {
        case .rebuildIndex: UntranslatedL10n.screenSyncStorageRebuildIndex
        case .clearHistory: UntranslatedL10n.screenSyncStorageClearHistory
        }
    }
    
    var message: String {
        switch self {
        case .rebuildIndex: UntranslatedL10n.screenSyncStorageRebuildIndexConfirmation
        case .clearHistory: UntranslatedL10n.screenSyncStorageClearHistoryConfirmation
        }
    }
}

struct SyncStorageScreenViewState: BindableState {
    var progress = HistoryDownloadProgress()
    var storage = HistoryStorageUsage()
    var isAdvancedExpanded = false
    var bindings = SyncStorageScreenViewStateBindings()
    
    /// One line saying where things stand, which is the only part most people read.
    var statusTitle: String {
        switch progress.status {
        case .notStarted: UntranslatedL10n.screenSyncStorageStatusNotStarted
        case .preparing: UntranslatedL10n.screenSyncStorageStatusPreparing
        case .downloading: UntranslatedL10n.screenSyncStorageStatusDownloading
        case .paused: UntranslatedL10n.screenSyncStorageStatusPaused
        case .completed: UntranslatedL10n.screenSyncStorageStatusCompleted
        case .error: UntranslatedL10n.screenSyncStorageStatusError
        }
    }
    
    /// Why it stopped, when that isn't the user's own doing.
    var statusDetail: String? {
        switch progress.status {
        case .paused(.waitingForWiFi): UntranslatedL10n.screenSyncStorageWaitingForWifi
        case .paused(.offline): UntranslatedL10n.screenSyncStorageOffline
        case .completed: UntranslatedL10n.screenSyncStorageCompletedDescription
        default: nil
        }
    }
    
    var isRunning: Bool {
        switch progress.status {
        case .preparing, .downloading: true
        default: false
        }
    }
    
    var canRetry: Bool {
        progress.lastError?.isRetryable == true
    }
    
    /// Extrapolated from the rooms already done. Nil until one has finished, because
    /// before that there's nothing to extrapolate from — Matrix doesn't say how many
    /// messages a room holds, so there's no denominator to work back from.
    var estimatedTimeRemaining: String? {
        guard isRunning,
              progress.roomsCompleted > 0,
              progress.roomsCompleted < progress.roomsTotal,
              let started = startedAt else {
            return nil
        }
        
        let elapsed = Date.now.timeIntervalSince(started)
        let perRoom = elapsed / Double(progress.roomsCompleted)
        let remaining = perRoom * Double(progress.roomsTotal - progress.roomsCompleted)
        
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = remaining < 60 ? [.second] : [.hour, .minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: remaining)
    }
    
    /// When the current pass began, for the estimate above.
    var startedAt: Date?
}

struct SyncStorageScreenViewStateBindings {
    var confirmation: SyncStorageConfirmation?
    /// Mirrored from AppSettings so the toggles bind directly; the view model writes
    /// changes back and the scheduler picks them up on its next check.
    var historyDownloadOnWiFiOnly = true
    var historyDownloadInBackground = true
}
