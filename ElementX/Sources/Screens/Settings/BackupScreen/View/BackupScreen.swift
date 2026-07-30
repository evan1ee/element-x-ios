//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

struct BackupScreen: View {
    @Bindable var context: BackupScreenViewModelType.Context
    
    var body: some View {
        Form {
            destinationSection
            statusSection
            if context.viewState.isEnabled {
                actionsSection
                backupsSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenBackupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { context.send(viewAction: .appeared) }
        .alert(item: $context.alertInfo)
        .sheet(isPresented: $context.isPresentingEnableSheet) { enableSheet }
        .sheet(isPresented: $context.isPresentingRestoreSheet) { restoreSheet }
        .confirmationDialog(UntranslatedL10n.screenBackupConfirmDisableTitle,
                            isPresented: $context.isPresentingDisableConfirmation,
                            titleVisibility: .visible) {
            // Never destroys what's stored without being told to.
            Button(UntranslatedL10n.screenBackupConfirmDisableKeep) {
                context.send(viewAction: .confirmDisable(.keepExistingBackups))
            }
            Button(UntranslatedL10n.screenBackupConfirmDisableDelete, role: .destructive) {
                context.send(viewAction: .confirmDisable(.deleteExistingBackups))
            }
            Button(L10n.actionCancel, role: .cancel) { }
        } message: {
            Text(UntranslatedL10n.screenBackupConfirmDisableMessage)
        }
    }
    
    // MARK: - Sections
    
    /// Only destinations usable on this device appear, so somewhere without iCloud
    /// isn't offered a choice that can't work.
    private var destinationSection: some View {
        Section {
            ForEach(context.viewState.availableProviders) { provider in
                ListRow(label: .plain(title: provider.name),
                        kind: .selection(isSelected: provider.id == context.viewState.selectedProviderID) {
                            context.send(viewAction: .selectProvider(provider.id))
                        })
                        .disabled(context.viewState.isEnabled || context.viewState.isBusy)
            }
        } header: {
            Text(UntranslatedL10n.screenBackupDestination)
                .compoundListSectionHeader()
        }
    }
    
    private var statusSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenBackupEnable),
                    kind: .toggle(enableBinding))
                .disabled(context.viewState.isBusy)
            
            if context.viewState.isEnabled || context.viewState.backup.phase != .idle {
                ListRow(label: .plain(title: UntranslatedL10n.screenBackupLastBackup,
                                      description: context.viewState.backup.lastError.map(\.localizedTitle)),
                        details: .title(context.viewState.statusTitle),
                        kind: .label)
                
                if context.viewState.isBusy {
                    ListRow(kind: .custom { progressRow })
                }
                
                ListRow(label: .plain(title: UntranslatedL10n.screenBackupLastBackup),
                        details: .title(context.viewState.lastBackupDescription),
                        kind: .label)
                
                if let storage = context.viewState.storage {
                    ListRow(label: .plain(title: UntranslatedL10n.screenBackupSize),
                            details: .title(storage.usedBytes.formatted(.byteCount(style: .file))),
                            kind: .label)
                }
            }
        } footer: {
            Text(UntranslatedL10n.screenBackupEnableFooter)
                .compoundListSectionFooter()
        }
    }
    
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: context.viewState.backup.phase.isRunning
                ? context.viewState.backup.fractionComplete
                : context.viewState.restore.fractionComplete)
                .tint(.compound.iconAccentTertiary)
            
            Text(context.viewState.backup.phase.isRunning
                ? context.viewState.statusTitle
                : (context.viewState.restoreStatusTitle ?? ""))
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var actionsSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenBackupUpNow, icon: \.exportArchive),
                    kind: .button { context.send(viewAction: .backUpNow) })
                .disabled(context.viewState.isBusy)
        }
    }
    
    private var backupsSection: some View {
        Section {
            if context.viewState.backups.isEmpty {
                ListRow(label: .plain(title: UntranslatedL10n.screenBackupNoBackups), kind: .label)
            } else {
                ForEach(context.viewState.backups) { descriptor in
                    ListRow(label: .plain(title: descriptor.deviceName.isEmpty ? descriptor.id : descriptor.deviceName,
                                          description: descriptor.createdAt.formatted(date: .abbreviated, time: .shortened)),
                            details: .title(descriptor.size.formatted(.byteCount(style: .file))),
                            kind: .button { context.send(viewAction: .startRestoring(descriptor)) })
                        .disabled(context.viewState.isBusy)
                }
            }
        } header: {
            Text(UntranslatedL10n.screenBackupRestore)
                .compoundListSectionHeader()
        }
    }
    
    // MARK: - Sheets
    
    /// Explains what leaves the device before asking for a passphrase, so enabling is
    /// an informed choice rather than a switch with consequences discovered later.
    private var enableSheet: some View {
        ElementNavigationStack {
            Form {
                Section {
                    Text(UntranslatedL10n.screenBackupContentsMessage)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .listRowInsets(ListRowPadding.insets)
                        .listRowBackground(Color.clear)
                } header: {
                    Text(UntranslatedL10n.screenBackupContentsTitle)
                        .compoundListSectionHeader()
                }
                
                Section {
                    ListRow(label: .plain(title: UntranslatedL10n.screenBackupPassphrasePlaceholder),
                            kind: .secureField(text: $context.passphrase))
                } header: {
                    Text(UntranslatedL10n.screenBackupPassphraseTitle)
                        .compoundListSectionHeader()
                } footer: {
                    Text(UntranslatedL10n.screenBackupPassphraseFooter)
                        .compoundListSectionFooter()
                }
            }
            .compoundList()
            .navigationTitle(UntranslatedL10n.screenBackupEnable)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { context.send(viewAction: .cancelEnabling) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionContinue) { context.send(viewAction: .confirmEnable) }
                        .disabled(context.passphrase.isEmpty)
                }
            }
        }
    }
    
    private var restoreSheet: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ListRow(label: .plain(title: UntranslatedL10n.screenBackupPassphrasePlaceholder),
                            kind: .secureField(text: $context.restorePassphrase))
                } footer: {
                    Text(UntranslatedL10n.screenBackupPassphraseFooter)
                        .compoundListSectionFooter()
                }
            }
            .compoundList()
            .navigationTitle(UntranslatedL10n.screenBackupRestore)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { context.send(viewAction: .cancelRestoring) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionContinue) { context.send(viewAction: .confirmRestore) }
                        .disabled(context.restorePassphrase.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Private
    
    /// The toggle can't own the setting: switching on opens a sheet that can be
    /// cancelled, and switching off asks what to do with what's stored. Both outcomes
    /// are decided elsewhere, so this only routes the intent.
    private var enableBinding: Binding<Bool> {
        Binding(get: { context.viewState.isEnabled },
                set: { isOn in
                    context.send(viewAction: isOn ? .startEnabling : .startDisabling)
                })
    }
}

// MARK: - Previews

struct BackupScreen_Previews: PreviewProvider, TestablePreview {
    static let disabledViewModel = makeViewModel()
    static let enabledViewModel = makeViewModel(isEnabled: true,
                                                progress: .init(phase: .completed,
                                                                lastBackupDate: .init(timeIntervalSince1970: 1_700_000_000),
                                                                backupSize: 482 * 1024 * 1024))
    static let runningViewModel = makeViewModel(isEnabled: true,
                                                progress: .init(phase: .uploading, fractionComplete: 0.8))
    static let failedViewModel = makeViewModel(isEnabled: true,
                                               progress: .init(phase: .failed(.storageFull), lastError: .storageFull))
    
    static var previews: some View {
        ElementNavigationStack {
            BackupScreen(context: disabledViewModel.context)
        }
        .previewDisplayName("Disabled")
        
        ElementNavigationStack {
            BackupScreen(context: enabledViewModel.context)
        }
        .previewDisplayName("Enabled")
        
        ElementNavigationStack {
            BackupScreen(context: runningViewModel.context)
        }
        .previewDisplayName("Uploading")
        
        ElementNavigationStack {
            BackupScreen(context: failedViewModel.context)
        }
        .previewDisplayName("Failed")
    }
    
    static func makeViewModel(isEnabled: Bool = false,
                              progress: BackupProgress = .init()) -> BackupScreenViewModel {
        let manager = BackupManagerManagerMock(isEnabled: isEnabled, progress: progress)
        return BackupScreenViewModel(backupManager: manager,
                                     userIndicatorController: UserIndicatorControllerMock())
    }
}

/// A stand-in for the previews. Hand-written rather than generated because the
/// generated mock traps on anything un-configured, and this screen calls most of the
/// protocol as soon as it appears.
private class BackupManagerManagerMock: BackupManagerProtocol {
    private let progressSubject: CurrentValueSubject<BackupProgress, Never>
    private let restoreSubject = CurrentValueSubject<RestoreProgress, Never>(.init())
    
    init(isEnabled: Bool, progress: BackupProgress) {
        self.isEnabled = isEnabled
        progressSubject = .init(progress)
    }
    
    var progressPublisher: CurrentValuePublisher<BackupProgress, Never> {
        progressSubject.asCurrentValuePublisher()
    }
    
    var restoreProgressPublisher: CurrentValuePublisher<RestoreProgress, Never> {
        restoreSubject.asCurrentValuePublisher()
    }
    
    var providers: [BackupProviderProtocol] {
        []
    }
    
    func availableProviders() async -> [BackupProviderProtocol] {
        []
    }
    
    var selectedProviderID: BackupProviderID = .iCloud
    func selectProvider(_ id: BackupProviderID) {
        selectedProviderID = id
    }
    
    var isEnabled: Bool
    func enable(passphrase: String) async -> Result<Void, BackupError> {
        .success(())
    }
    
    func disable(disposal: BackupDisposal) async -> Result<Void, BackupError> {
        .success(())
    }
    
    func backUpNow() async -> Result<Void, BackupError> {
        .success(())
    }
    
    func listBackups() async -> Result<[BackupDescriptor], BackupError> {
        .success([BackupDescriptor(id: "HaloXBackup-20260729-143200.hxb",
                                   createdAt: .init(timeIntervalSince1970: 1_700_000_000),
                                   size: 482 * 1024 * 1024,
                                   deviceName: "iPhone",
                                   appVersion: "1.0.0",
                                   manifest: nil)])
    }
    
    func deleteBackup(id: String) async -> Result<Void, BackupError> {
        .success(())
    }
    
    func storageInfo() async -> Result<BackupStorageInfo, BackupError> {
        .success(BackupStorageInfo(usedBytes: 482 * 1024 * 1024, availableBytes: nil, backupCount: 1))
    }
    
    func restore(descriptor: BackupDescriptor, passphrase: String) async -> Result<Void, BackupError> {
        .success(())
    }
    
    func applicationDidEnterBackground() { }
}
