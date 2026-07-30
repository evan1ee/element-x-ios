//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// Turns local data into a sealed package and hands it to whichever provider is
/// selected, then does the reverse on restore.
///
/// The engine: it knows about snapshots, compression, encryption and validation, and
/// nothing about destinations. Every mention of storage goes through
/// `BackupProviderProtocol`, which is what makes a new destination additive.
class BackupManager: BackupManagerProtocol {
    private let providersByID: [BackupProviderID: BackupProviderProtocol]
    private let dataSource: BackupDataSourceProtocol
    private let passphraseStore: BackupPassphraseStoreProtocol
    private let appSettings: AppSettings
    private let userID: String
    private let deviceName: String
    private let appVersion: String
    
    /// How stale a backup has to be before backgrounding takes another one.
    private static let automaticBackupInterval: TimeInterval = 24 * 60 * 60
    
    private let progressSubject = CurrentValueSubject<BackupProgress, Never>(.init())
    var progressPublisher: CurrentValuePublisher<BackupProgress, Never> {
        progressSubject.asCurrentValuePublisher()
    }
    
    private let restoreProgressSubject = CurrentValueSubject<RestoreProgress, Never>(.init())
    var restoreProgressPublisher: CurrentValuePublisher<RestoreProgress, Never> {
        restoreProgressSubject.asCurrentValuePublisher()
    }
    
    private var backupTask: Task<Result<Void, BackupError>, Never>?
    
    let providers: [BackupProviderProtocol]
    
    init(providers: [BackupProviderProtocol],
         dataSource: BackupDataSourceProtocol,
         passphraseStore: BackupPassphraseStoreProtocol,
         appSettings: AppSettings,
         userID: String,
         deviceName: String,
         appVersion: String) {
        self.providers = providers
        providersByID = Dictionary(providers.map { ($0.id, $0) }) { first, _ in first }
        self.dataSource = dataSource
        self.passphraseStore = passphraseStore
        self.appSettings = appSettings
        self.userID = userID
        self.deviceName = deviceName
        self.appVersion = appVersion
        
        progressSubject.send(.init(phase: .idle, lastBackupDate: appSettings.lastBackupDate))
    }
    
    // MARK: - Providers
    
    func availableProviders() async -> [BackupProviderProtocol] {
        var available: [BackupProviderProtocol] = []
        for provider in providers where await provider.isAvailable() {
            available.append(provider)
        }
        return available
    }
    
    var selectedProviderID: BackupProviderID {
        appSettings.backupProviderID
    }
    
    func selectProvider(_ id: BackupProviderID) {
        appSettings.backupProviderID = id
    }
    
    private var selectedProvider: BackupProviderProtocol? {
        providersByID[appSettings.backupProviderID]
    }
    
    // MARK: - Enabling
    
    var isEnabled: Bool {
        appSettings.backupEnabled
    }
    
    func enable(passphrase: String) async -> Result<Void, BackupError> {
        guard let provider = selectedProvider else { return .failure(.providerUnavailable) }
        
        if case .failure(let error) = await provider.authenticate() {
            return .failure(error)
        }
        
        passphraseStore.setPassphrase(passphrase)
        appSettings.backupEnabled = true
        
        let result = await performBackup()
        if case .failure = result {
            // Leave it off rather than claiming a backup exists when the first one
            // couldn't be made.
            appSettings.backupEnabled = false
            passphraseStore.removePassphrase()
        }
        return result
    }
    
    func disable(disposal: BackupDisposal) async -> Result<Void, BackupError> {
        backupTask?.cancel()
        backupTask = nil
        appSettings.backupEnabled = false
        
        guard disposal == .deleteExistingBackups else {
            // The passphrase stays: the backups it opens are still out there.
            progressSubject.send(.init(phase: .idle, lastBackupDate: appSettings.lastBackupDate))
            return .success(())
        }
        
        guard let provider = selectedProvider else { return .failure(.providerUnavailable) }
        
        switch await provider.listBackups() {
        case .success(let descriptors):
            for descriptor in descriptors {
                if case .failure(let error) = await provider.deleteBackup(id: descriptor.id) {
                    return .failure(error)
                }
            }
        case .failure(let error):
            return .failure(error)
        }
        
        passphraseStore.removePassphrase()
        appSettings.lastBackupDate = nil
        progressSubject.send(.init())
        return .success(())
    }
    
    // MARK: - Backing up
    
    func backUpNow() async -> Result<Void, BackupError> {
        await performBackup()
    }
    
    func applicationDidEnterBackground() {
        guard appSettings.backupEnabled, !progressSubject.value.phase.isRunning else { return }
        
        if let last = appSettings.lastBackupDate,
           Date.now.timeIntervalSince(last) < Self.automaticBackupInterval {
            return
        }
        
        backupTask = Task { [weak self] in
            guard let self else { return .failure(.cancelled) }
            return await performBackup()
        }
    }
    
    private func performBackup() async -> Result<Void, BackupError> {
        guard let provider = selectedProvider else {
            return fail(.providerUnavailable)
        }
        guard let passphrase = passphraseStore.passphrase else {
            // Enabling stores one, so its absence means the keychain entry is gone —
            // a restore onto a device that never enabled backups, typically.
            return fail(.notAuthenticated)
        }
        
        update { $0.phase = .preparing; $0.fractionComplete = 0; $0.lastError = nil }
        
        guard await provider.isAvailable() else {
            return fail(.providerUnavailable)
        }
        
        update { $0.phase = .exporting }
        
        // Scratch holds the two synthesised entries; the databases are referenced
        // where they already sit, so nothing is copied to get here.
        let scratchURL = FileManager.default.temporaryDirectory
            .appending(component: "hxb-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        
        let entryURLs: [String: URL]
        do {
            entryURLs = try await dataSource.exportEntryURLs(scratchDirectory: scratchURL)
        } catch {
            MXLog.error("Backup export failed: \(error)")
            return fail(.providerFailure("export"))
        }
        
        guard !Task.isCancelled else { return fail(.cancelled) }
        
        let packageURL = FileManager.default.temporaryDirectory
            .appending(component: "HaloXBackup-\(UUID().uuidString).\(BackupArchive.fileExtension)")
        defer { try? FileManager.default.removeItem(at: packageURL) }
        
        update { $0.phase = .compressing }
        
        let manifest: BackupManifest
        do {
            // Compression and sealing happen together inside the archive writer, so
            // the encrypting phase is reported around the same call.
            update { $0.phase = .encrypting }
            manifest = try BackupArchive.write(entryURLs: entryURLs,
                                               to: packageURL,
                                               passphrase: passphrase,
                                               appVersion: appVersion,
                                               databaseSchemaVersion: dataSource.databaseSchemaVersion,
                                               searchIndexSchemaVersion: dataSource.searchIndexSchemaVersion,
                                               providerID: provider.id,
                                               deviceName: deviceName)
        } catch let error as BackupError {
            return fail(error)
        } catch {
            MXLog.error("Backup packaging failed: \(error)")
            return fail(.encryptionFailed)
        }
        
        guard !Task.isCancelled else { return fail(.cancelled) }
        
        update { $0.phase = .uploading; $0.fractionComplete = 0 }
        
        let uploadResult = await provider.upload(packageURL: packageURL, manifest: manifest) { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.update { $0.fractionComplete = fraction }
            }
        }
        
        switch uploadResult {
        case .success(let descriptor):
            appSettings.lastBackupDate = descriptor.createdAt
            update {
                $0.phase = .completed
                $0.fractionComplete = 1
                $0.lastBackupDate = descriptor.createdAt
                $0.backupSize = descriptor.size
                $0.lastError = nil
            }
            return .success(())
        case .failure(let error):
            return fail(error)
        }
    }
    
    // MARK: - Listing
    
    func listBackups() async -> Result<[BackupDescriptor], BackupError> {
        guard let provider = selectedProvider else { return .failure(.providerUnavailable) }
        return await provider.listBackups()
    }
    
    func deleteBackup(id: String) async -> Result<Void, BackupError> {
        guard let provider = selectedProvider else { return .failure(.providerUnavailable) }
        return await provider.deleteBackup(id: id)
    }
    
    func storageInfo() async -> Result<BackupStorageInfo, BackupError> {
        guard let provider = selectedProvider else { return .failure(.providerUnavailable) }
        return await provider.storageInfo()
    }
    
    // MARK: - Restoring
    
    func restore(descriptor: BackupDescriptor, passphrase: String) async -> Result<Void, BackupError> {
        guard let provider = selectedProvider else { return failRestore(.providerUnavailable) }
        
        updateRestore { $0.phase = .findingBackup; $0.fractionComplete = 0; $0.lastError = nil }
        
        guard await provider.isAvailable() else { return failRestore(.providerUnavailable) }
        
        let destination = FileManager.default.temporaryDirectory
            .appending(component: "HaloXRestore-\(UUID().uuidString).\(BackupArchive.fileExtension)")
        defer { try? FileManager.default.removeItem(at: destination) }
        
        updateRestore { $0.phase = .downloading }
        
        let packageURL: URL
        // Parenthesised rather than trailing: a trailing closure here reads as the
        // switch body to both the compiler and the eye.
        // swiftlint:disable:next trailing_closure
        switch await provider.download(id: descriptor.id, to: destination, progress: { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.updateRestore { $0.fractionComplete = fraction }
            }
        }) {
        case .success(let url):
            packageURL = url
        case .failure(let error):
            return failRestore(error)
        }
        
        updateRestore { $0.phase = .validating; $0.fractionComplete = 0 }
        
        // Version is checked before decrypting: a package from a newer app shouldn't
        // have its contents opened at all, let alone written over a working database.
        do {
            let manifest = try BackupArchive.readManifest(from: packageURL)
            guard manifest.isSupported else {
                return failRestore(.versionMismatch(found: manifest.formatVersion,
                                                    supported: BackupManifest.currentFormatVersion))
            }
            guard manifest.searchIndexSchemaVersion <= dataSource.searchIndexSchemaVersion,
                  manifest.databaseSchemaVersion <= dataSource.databaseSchemaVersion else {
                return failRestore(.versionMismatch(found: manifest.databaseSchemaVersion,
                                                    supported: dataSource.databaseSchemaVersion))
            }
        } catch let error as BackupError {
            return failRestore(error)
        } catch {
            return failRestore(.corruptedPackage)
        }
        
        updateRestore { $0.phase = .decrypting }
        
        // Decrypted entries are written out as files rather than returned as bytes,
        // so restoring a large account costs disk rather than memory.
        let unsealedURL = FileManager.default.temporaryDirectory
            .appending(component: "hxb-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: unsealedURL) }
        
        let entryURLs: [String: URL]
        do {
            entryURLs = try BackupArchive.read(from: packageURL, passphrase: passphrase, into: unsealedURL).entryURLs
        } catch let error as BackupError {
            return failRestore(error)
        } catch {
            return failRestore(.corruptedPackage)
        }
        
        // Refuse another account's package before writing anything: merging two
        // users' stores would corrupt both.
        if let url = entryURLs[SessionBackupDataSource.metadataEntryName],
           let data = try? Data(contentsOf: url),
           let metadata = try? JSONDecoder().decode(BackupMetadata.self, from: data),
           metadata.userID != userID {
            return failRestore(.accountMismatch)
        }
        
        updateRestore { $0.phase = .restoring }
        
        do {
            try await dataSource.importEntryURLs(entryURLs)
        } catch {
            MXLog.error("Backup import failed: \(error)")
            return failRestore(.providerFailure("import"))
        }
        
        updateRestore { $0.phase = .completed; $0.fractionComplete = 1 }
        return .success(())
    }
    
    // MARK: - Private
    
    private func update(_ mutate: (inout BackupProgress) -> Void) {
        var value = progressSubject.value
        mutate(&value)
        progressSubject.send(value)
    }
    
    private func updateRestore(_ mutate: (inout RestoreProgress) -> Void) {
        var value = restoreProgressSubject.value
        mutate(&value)
        restoreProgressSubject.send(value)
    }
    
    private func fail(_ error: BackupError) -> Result<Void, BackupError> {
        MXLog.error("Backup failed: \(error)")
        update { $0.phase = .failed(error); $0.lastError = error }
        return .failure(error)
    }
    
    private func failRestore(_ error: BackupError) -> Result<Void, BackupError> {
        MXLog.error("Restore failed: \(error)")
        updateRestore { $0.phase = .failed(error); $0.lastError = error }
        return .failure(error)
    }
}
