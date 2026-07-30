//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Keeps packages in the app's iCloud Drive container.
///
/// Everything iCloud-shaped lives here: ubiquity containers, the fact that a
/// "download" is really a request for the system to materialise a placeholder, and
/// the mapping from `NSFileProvider`/`CKError`-flavoured failures onto `BackupError`.
/// Nothing above this file knows iCloud exists.
final nonisolated class ICloudBackupProvider: BackupProviderProtocol {
    private let containerIdentifier: String?
    
    /// `FileManager` isn't `Sendable`, so it's reached for where it's used rather
    /// than stored. `.default` is safe to call from any thread.
    private var fileManager: FileManager {
        .default
    }
    
    /// Subdirectory inside Documents so backups appear as a tidy folder in the Files
    /// app rather than loose files the user might take for junk.
    private static let directoryName = "Backups"
    /// How long to wait for iCloud to materialise a placeholder before giving up.
    private static let downloadTimeout: TimeInterval = 300
    private static let pollInterval = Duration.milliseconds(500)
    
    init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }
    
    let id: BackupProviderID = .iCloud
    var name: String {
        UntranslatedL10n.screenBackupProviderIcloud
    }
    
    // MARK: - Availability
    
    /// Resolving the container touches the disk and can block, so it's kept off the
    /// caller's thread. A nil token means no iCloud account, or the user has turned
    /// iCloud Drive off for the app.
    func isAvailable() async -> Bool {
        await Task.detached(priority: .utility) { [fileManager, containerIdentifier] in
            fileManager.ubiquityIdentityToken != nil
                && fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) != nil
        }.value
    }
    
    func authenticate() async -> Result<Void, BackupError> {
        // iCloud is granted by the system: there's nothing to prompt for, so this
        // only reports whether the container is usable.
        await isAvailable() ? .success(()) : .failure(.providerUnavailable)
    }
    
    // MARK: - Transfer
    
    func upload(packageURL: URL,
                manifest: BackupManifest,
                progress: @escaping @Sendable (Double) -> Void) async -> Result<BackupDescriptor, BackupError> {
        guard let directory = await backupsDirectory() else { return .failure(.providerUnavailable) }
        
        let filename = "HaloXBackup-\(Self.timestamp(manifest.createdAt)).\(BackupArchive.fileExtension)"
        let destination = directory.appending(component: filename)
        
        do {
            try fileManager.createDirectoryIfNeeded(at: directory)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            // Copying into the ubiquity container hands the file to the iCloud
            // daemon; the actual upload continues after this returns.
            try fileManager.copyItem(at: packageURL, to: destination)
        } catch {
            return .failure(Self.mapError(error))
        }
        
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        
        // Report completion of the local hand-off. The daemon's own progress isn't
        // observable without a metadata query per file, and claiming a percentage
        // we aren't measuring would be worse than a single step.
        progress(1)
        
        return .success(BackupDescriptor(id: filename,
                                         createdAt: manifest.createdAt,
                                         size: size,
                                         deviceName: manifest.deviceName,
                                         appVersion: manifest.appVersion,
                                         manifest: manifest))
    }
    
    func download(id: String,
                  to destinationURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async -> Result<URL, BackupError> {
        guard let directory = await backupsDirectory() else { return .failure(.providerUnavailable) }
        
        let source = directory.appending(component: id)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false))
            || (try? source.checkResourceIsReachable()) == true else {
            return .failure(.corruptedPackage)
        }
        
        // A file in the container may be a placeholder. Ask for it, then wait for it
        // to actually land before reading a single byte.
        do {
            try fileManager.startDownloadingUbiquitousItem(at: source)
        } catch {
            return .failure(Self.mapError(error))
        }
        
        // iOS exposes no percentage on the URL — that needs an NSMetadataQuery — so
        // this waits on the status and leaves the fraction alone. An invented
        // percentage would be worse than an indeterminate bar.
        let deadline = Date.now.addingTimeInterval(Self.downloadTimeout)
        while Date.now < deadline {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            if (try? source.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                .ubiquitousItemDownloadingStatus == .current {
                break
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
        
        guard (try? source.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus == .current else {
            return .failure(.network)
        }
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: source, to: destinationURL)
        } catch {
            return .failure(Self.mapError(error))
        }
        
        progress(1)
        return .success(destinationURL)
    }
    
    // MARK: - Enumeration
    
    func listBackups() async -> Result<[BackupDescriptor], BackupError> {
        guard let directory = await backupsDirectory() else { return .failure(.providerUnavailable) }
        
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return .success([])
        } catch {
            return .failure(Self.mapError(error))
        }
        
        let descriptors = contents
            .filter { $0.pathExtension == BackupArchive.fileExtension }
            .map { url -> BackupDescriptor in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                // Reading the header can fail on a placeholder that hasn't downloaded,
                // or on a file that isn't ours. Either way it's still listed, so the
                // user can see it and delete it.
                let manifest = try? BackupArchive.readManifest(from: url)
                return BackupDescriptor(id: url.lastPathComponent,
                                        createdAt: manifest?.createdAt ?? values?.contentModificationDate ?? .distantPast,
                                        size: values?.fileSize.map(Int64.init) ?? 0,
                                        deviceName: manifest?.deviceName ?? "",
                                        appVersion: manifest?.appVersion ?? "",
                                        manifest: manifest)
            }
            .sorted { $0.createdAt > $1.createdAt }
        
        return .success(descriptors)
    }
    
    func deleteBackup(id: String) async -> Result<Void, BackupError> {
        guard let directory = await backupsDirectory() else { return .failure(.providerUnavailable) }
        
        do {
            try fileManager.removeItem(at: directory.appending(component: id))
            return .success(())
        } catch CocoaError.fileNoSuchFile {
            // Already gone is the outcome the caller wanted.
            return .success(())
        } catch {
            return .failure(Self.mapError(error))
        }
    }
    
    func storageInfo() async -> Result<BackupStorageInfo, BackupError> {
        switch await listBackups() {
        case .success(let descriptors):
            let available = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            return .success(BackupStorageInfo(usedBytes: descriptors.reduce(0) { $0 + $1.size },
                                              availableBytes: available,
                                              backupCount: descriptors.count))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    // MARK: - Private
    
    private func backupsDirectory() async -> URL? {
        await Task.detached(priority: .utility) { [fileManager, containerIdentifier] in
            // Documents rather than the container root: only Documents is surfaced
            // in the Files app, which is where a user would go looking.
            fileManager.url(forUbiquityContainerIdentifier: containerIdentifier)?
                .appending(component: "Documents", directoryHint: .isDirectory)
                .appending(component: Self.directoryName, directoryHint: .isDirectory)
        }.value
    }
    
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    /// Collapses Cocoa's file errors onto the shared vocabulary, so callers never
    /// have to reason about iCloud's own codes.
    private static func mapError(_ error: Error) -> BackupError {
        switch error {
        case CocoaError.fileWriteOutOfSpace:
            .storageFull
        case CocoaError.fileWriteNoPermission, CocoaError.fileReadNoPermission:
            .permissionDenied
        case CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile:
            .corruptedPackage
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            .network
        default:
            .providerFailure(String(describing: error))
        }
    }
}
