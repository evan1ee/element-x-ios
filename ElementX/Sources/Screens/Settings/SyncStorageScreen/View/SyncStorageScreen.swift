//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct SyncStorageScreen: View {
    @Bindable var context: SyncStorageScreenViewModelType.Context
    
    var body: some View {
        Form {
            statusSection
            statisticsSection
            storageSection
            downloadSection
            actionsSection
            advancedSection
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenSyncStorageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { context.send(viewAction: .appeared) }
        .alert(item: $context.confirmation) { confirmation in
            Alert(title: Text(confirmation.title),
                  message: Text(confirmation.message),
                  primaryButton: .destructive(Text(L10n.actionContinue)) {
                      switch confirmation {
                      case .rebuildIndex: context.send(viewAction: .rebuildIndex)
                      case .clearHistory: context.send(viewAction: .clearHistory)
                      }
                  },
                  secondaryButton: .cancel())
        }
    }
    
    // MARK: - Sections
    
    private var statusSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageHistoryDownload,
                                  description: context.viewState.statusDetail),
                    details: .title(context.viewState.statusTitle),
                    kind: .label)
            
            if context.viewState.isRunning || context.viewState.progress.roomsCompleted > 0 {
                ListRow(kind: .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: context.viewState.progress.fractionComplete)
                            .tint(.compound.iconAccentTertiary)
                        
                        HStack(spacing: 8) {
                            Text(context.viewState.progress.fractionComplete.formatted(.percent.precision(.fractionLength(0))))
                                .font(.compound.bodySMSemibold)
                                .foregroundStyle(.compound.textPrimary)
                            
                            Spacer()
                            
                            if context.viewState.isRunning {
                                // Says "Calculating…" rather than guessing: no room has
                                // finished yet, so there's nothing to extrapolate from.
                                Text(context.viewState.estimatedTimeRemaining.map(UntranslatedL10n.screenSyncStorageTimeRemaining)
                                    ?? UntranslatedL10n.screenSyncStorageCalculating)
                                    .font(.compound.bodySM)
                                    .foregroundStyle(.compound.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                })
            }
        } header: {
            Text(UntranslatedL10n.screenSyncStorageHistoryDownload)
                .compoundListSectionHeader()
        }
    }
    
    private var statisticsSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageRooms),
                    details: .title("\(context.viewState.progress.roomsCompleted) / \(context.viewState.progress.roomsTotal)"),
                    kind: .label)
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageMessages),
                    details: .title(context.viewState.progress.messagesIndexed.formatted()),
                    kind: .label)
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageSearchIndex),
                    details: .title(context.viewState.progress.messagesIndexed > 0
                        ? UntranslatedL10n.screenSyncStorageSearchIndexHealthy
                        : UntranslatedL10n.screenSyncStorageSearchIndexEmpty),
                    kind: .label)
        }
    }
    
    private var storageSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageDatabase),
                    details: .title(format(context.viewState.storage.databaseBytes)),
                    kind: .label)
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageMediaCache),
                    details: .title(format(context.viewState.storage.mediaCacheBytes)),
                    kind: .label)
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageTotal),
                    details: .title(format(context.viewState.storage.totalBytes)),
                    kind: .label)
        }
    }
    
    private var downloadSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageDownloadHistory),
                    kind: .toggle($context.historyDownloadEnabled))
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageWifiOnly),
                    kind: .toggle($context.historyDownloadOnWiFiOnly))
            
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageBackground,
                                  description: UntranslatedL10n.screenSyncStorageBackgroundDescription),
                    kind: .toggle($context.historyDownloadInBackground))
        } footer: {
            Text(UntranslatedL10n.screenSyncStorageDownloadHistoryDescription)
                .compoundListSectionFooter()
        }
    }
    
    private var actionsSection: some View {
        Section {
            if context.viewState.isRunning {
                ListRow(label: .action(title: UntranslatedL10n.screenSyncStoragePause, icon: \.pause),
                        kind: .button { context.send(viewAction: .pause) })
            } else {
                ListRow(label: .action(title: UntranslatedL10n.screenSyncStorageResume, icon: \.play),
                        kind: .button { context.send(viewAction: .resume) })
            }
            
            if context.viewState.canRetry {
                ListRow(label: .action(title: UntranslatedL10n.screenSyncStorageRetry, icon: \.restart),
                        kind: .button { context.send(viewAction: .retry) })
            }
            
            ListRow(label: .action(title: UntranslatedL10n.screenSyncStorageRebuildIndex, icon: \.search),
                    kind: .button { context.confirmation = .rebuildIndex })
            
            ListRow(label: .action(title: UntranslatedL10n.screenSyncStorageClearHistory,
                                   icon: \.delete,
                                   role: .destructive),
                    kind: .button { context.confirmation = .clearHistory })
        }
    }
    
    private var advancedSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageAdvanced),
                    kind: .button { context.send(viewAction: .toggleAdvanced) })
            
            if context.viewState.isAdvancedExpanded {
                if let room = context.viewState.progress.activeRoomName {
                    ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageActiveRoom),
                            details: .title(room),
                            kind: .label)
                }
                
                ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageQueueLength),
                        details: .title("\(context.viewState.progress.queueLength)"),
                        kind: .label)
                
                if let date = context.viewState.progress.lastSyncDate {
                    ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageLastSync),
                            details: .title(date.formatted(date: .abbreviated, time: .shortened)),
                            kind: .label)
                }
                
                if let error = context.viewState.progress.lastError {
                    ListRow(label: .plain(title: UntranslatedL10n.screenSyncStorageLastError),
                            details: .title(describe(error)),
                            kind: .label)
                }
            }
        }
    }
    
    // MARK: - Formatting
    
    private func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
    
    private func describe(_ error: HistoryDownloadError) -> String {
        switch error {
        case .network: UntranslatedL10n.screenSyncStorageErrorNetwork
        case .server: UntranslatedL10n.screenSyncStorageErrorServer
        case .storageFull: UntranslatedL10n.screenSyncStorageErrorStorageFull
        case .authenticationExpired: UntranslatedL10n.screenSyncStorageErrorAuthentication
        }
    }
}
