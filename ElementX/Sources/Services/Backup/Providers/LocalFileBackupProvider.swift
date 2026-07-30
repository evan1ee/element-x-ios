//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Keeps packages in the app's own Documents directory, where the Files app can
/// reach them for copying to a drive, sharing, or AirDrop.
///
/// It exists as much to keep the abstraction honest as to be useful: it was written
/// after the engine, and adding it required no change to `BackupManager`,
/// `BackupArchive`, or any model. A WebDAV or AirDrop provider slots in the same way.
final nonisolated class LocalFileBackupProvider: BackupProviderProtocol {
    private let directory: URL
    
    /// `FileManager` isn't `Sendable`, so it's reached for where it's used rather
    /// than stored. Tests point the provider at a temporary directory instead.
    private var fileManager: FileManager {
        .default
    }
    
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.documentsDirectory.appending(component: "Backups", directoryHint: .isDirectory)
    }
    
    let id: BackupProviderID = .localFile
    var name: String {
        UntranslatedL10n.screenBackupProviderLocalFile
    }
    
    /// Always usable — it's the device's own disk. Space is checked when writing
    /// rather than here, since a true/false answer can't express "nearly full".
    func isAvailable() async -> Bool {
        true
    }
    
    func authenticate() async -> Result<Void, BackupError> {
        .success(())
    }
    
    func upload(packageURL: URL,
                manifest: BackupManifest,
                progress: @escaping @Sendable (Double) -> Void) async -> Result<BackupDescriptor, BackupError> {
        let filename = "HaloXBackup-\(Self.timestamp(manifest.createdAt)).\(BackupArchive.fileExtension)"
        let destination = directory.appending(component: filename)
        
        do {
            try fileManager.createDirectoryIfNeeded(at: directory)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: packageURL, to: destination)
        } catch {
            return .failure(Self.mapError(error))
        }
        
        progress(1)
        
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
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
        let source = directory.appending(component: id)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            return .failure(.corruptedPackage)
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
    
    func listBackups() async -> Result<[BackupDescriptor], BackupError> {
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
        do {
            try fileManager.removeItem(at: directory.appending(component: id))
            return .success(())
        } catch CocoaError.fileNoSuchFile {
            return .success(())
        } catch {
            return .failure(Self.mapError(error))
        }
    }
    
    func storageInfo() async -> Result<BackupStorageInfo, BackupError> {
        switch await listBackups() {
        case .success(let descriptors):
            let available = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            return .success(BackupStorageInfo(usedBytes: descriptors.reduce(0) { $0 + $1.size },
                                              availableBytes: available,
                                              backupCount: descriptors.count))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    // MARK: - Private
    
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private static func mapError(_ error: Error) -> BackupError {
        switch error {
        case CocoaError.fileWriteOutOfSpace: .storageFull
        case CocoaError.fileWriteNoPermission, CocoaError.fileReadNoPermission: .permissionDenied
        case CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile: .corruptedPackage
        default: .providerFailure(String(describing: error))
        }
    }
}
