//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Holds a decrypted backup until it can be safely put in place.
///
/// A restore can't write over the live databases. The Rust SDK and the search index
/// hold those SQLite files open, and replacing a file atomically swaps the inode:
/// the open handles keep writing to the old one, so the restore either has no effect
/// or, worse, a later checkpoint flushes a stale `-wal` over the restored `.sqlite3`
/// and corrupts it. Nothing about that failure is visible at the time.
///
/// So a restore writes here instead, and the files are moved into place on the next
/// launch, before any database is opened.
nonisolated enum BackupRestoreStaging {
    /// Sits beside the session directories rather than in caches — the system may
    /// evict caches under pressure, and losing half a staged restore would leave the
    /// databases in a mixed state.
    private static var directory: URL {
        .sessionsBaseDirectory.appending(component: "PendingRestore", directoryHint: .isDirectory)
    }
    
    /// Written last, and checked first. Its absence means a staging run was
    /// interrupted, in which case the partial files are discarded rather than
    /// half-applied.
    private static let markerName = ".complete"
    
    static var hasPendingRestore: Bool {
        FileManager.default.fileExists(atPath: directory.appending(component: markerName).path(percentEncoded: false))
    }
    
    /// Moves the decrypted entries aside, keyed by their package names.
    ///
    /// Moves rather than reads: the archive has already written them out as files, and
    /// loading them here would reintroduce the memory ceiling the streaming reader
    /// exists to remove.
    static func stage(entryURLs: [String: URL]) throws {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectoryIfNeeded(at: directory)
        
        for (name, source) in entryURLs {
            // Package names carry '/', which can't be a filename. Encoding rather than
            // creating subdirectories keeps applying it a flat, restartable loop.
            let destination = directory.appending(component: encode(name))
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        
        try Data().write(to: directory.appending(component: markerName), options: .atomic)
    }
    
    /// Moves a staged restore into place. Call before anything opens a database.
    ///
    /// Clears the staging directory whatever happens: a restore that can't be applied
    /// shouldn't be retried on every launch forever.
    static func applyPendingRestore(sessionDirectories: SessionDirectories?,
                                    searchIndexURL: URL,
                                    preferencesSuiteName: String?) {
        guard hasPendingRestore else { return }
        defer { try? FileManager.default.removeItem(at: directory) }
        
        MXLog.info("Applying a staged backup restore.")
        
        guard let names = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        
        var entryURLs: [String: URL] = [:]
        for url in names where url.lastPathComponent != markerName {
            entryURLs[decode(url.lastPathComponent)] = url
        }
        
        let dataSource = SessionBackupDataSource(sessionDirectories: sessionDirectories,
                                                 searchIndexURL: searchIndexURL,
                                                 preferencesSuiteName: preferencesSuiteName,
                                                 userID: "")
        do {
            try dataSource.write(entryURLs: entryURLs)
            MXLog.info("Restore applied: \(entryURLs.count) entries.")
        } catch {
            MXLog.error("Failed applying the staged restore: \(error)")
        }
    }
    
    // MARK: - Private
    
    private static func encode(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "__")
    }
    
    private static func decode(_ filename: String) -> String {
        filename.replacingOccurrences(of: "__", with: "/")
    }
}
