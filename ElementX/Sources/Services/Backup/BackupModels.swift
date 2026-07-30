//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// What went wrong, in terms the UI can act on. Providers map their own failures onto
/// these so a WebDAV timeout and an iCloud timeout reach the user as the same thing.
nonisolated enum BackupError: Error, Equatable, Sendable {
    /// The destination isn't usable right now — signed out, disabled, or absent.
    case providerUnavailable
    case notAuthenticated
    case storageFull
    case network
    /// The package isn't a backup, or has been truncated or altered.
    case corruptedPackage
    /// The package is intact but the key is wrong, which in practice means the passphrase.
    case decryptionFailed
    case encryptionFailed
    /// Written by a newer app than this one, so its contents can't be trusted.
    case versionMismatch(found: Int, supported: Int)
    case permissionDenied
    case cancelled
    /// The package belongs to a different account.
    case accountMismatch
    /// Anything a provider can't express as one of the above. The string is for logs
    /// and the error screen's detail line, never for branching on.
    case providerFailure(String)
    
    /// Whether trying the same thing again could plausibly work, which decides
    /// whether the UI offers a retry.
    var isRetryable: Bool {
        switch self {
        case .network, .providerUnavailable, .providerFailure: true
        case .notAuthenticated, .storageFull, .corruptedPackage, .decryptionFailed,
             .encryptionFailed, .versionMismatch, .permissionDenied, .cancelled,
             .accountMismatch: false
        }
    }
}

/// One file inside the package. Listed in the manifest so a restore can tell what it
/// is about to write before it decrypts anything.
nonisolated struct BackupEntry: Codable, Equatable, Sendable {
    /// Path within the package, e.g. `database.sqlite`.
    let name: String
    let size: Int64
    /// SHA256 of this entry's bytes, so a partial write is caught per file rather
    /// than only at the package level.
    let checksum: String
}

/// The plaintext header of a package.
///
/// Deliberately readable without the key: listing backups, showing their age and size,
/// and refusing an incompatible version all have to work before anyone is asked for a
/// passphrase. It therefore holds no message content and no user identifiers beyond
/// the device name the user chose themselves.
nonisolated struct BackupManifest: Codable, Equatable, Sendable {
    /// Bumped when the container layout changes in a way older readers can't handle.
    /// 2 introduced chunked sealing so a backup never has to fit in memory.
    static let currentFormatVersion = 2
    
    let formatVersion: Int
    let appVersion: String
    /// Schema versions of the payload databases. A restore compares these before
    /// writing anything, since a newer schema would not be readable.
    let databaseSchemaVersion: Int
    let searchIndexSchemaVersion: Int
    let createdAt: Date
    /// Uncompressed size of the payload, for the progress bar and the storage row.
    let payloadSize: Int64
    /// SHA256 over the compressed, still-unencrypted payload.
    let checksum: String
    let entries: [BackupEntry]
    let providerID: BackupProviderID
    /// Shown when choosing which backup to restore.
    let deviceName: String
    /// Random per-backup salt for deriving the key from the passphrase. Public by
    /// design — a salt defends against precomputation, not against being read.
    let keySalt: Data
    /// Random per-backup nonce prefix. Each chunk's nonce is this plus its position,
    /// so nonces are unique without storing one per chunk. Absent in version 1.
    let noncePrefix: Data?
    /// Plaintext bytes per chunk, recorded so a future writer can change it without
    /// stranding older packages. Absent in version 1.
    let chunkSize: Int?
    
    var isSupported: Bool {
        formatVersion <= Self.currentFormatVersion
    }
}

/// A backup as the provider sees it, without opening the payload.
nonisolated struct BackupDescriptor: Identifiable, Equatable, Sendable {
    /// Provider-scoped identifier — a filename for iCloud and local files, a URL
    /// path for WebDAV. Opaque to the backup core.
    let id: String
    let createdAt: Date
    /// Size on the destination, so it can differ from the manifest's payload size.
    let size: Int64
    let deviceName: String
    let appVersion: String
    /// Nil when the header couldn't be parsed, which is how a corrupted or foreign
    /// file still gets listed and can therefore be deleted.
    let manifest: BackupManifest?
}

/// What the destination reports about itself.
nonisolated struct BackupStorageInfo: Equatable, Sendable {
    /// Space taken by this app's backups, not the whole destination.
    let usedBytes: Int64
    /// Nil where the provider can't say — WebDAV servers often won't.
    let availableBytes: Int64?
    let backupCount: Int
}

/// Where a backup has got to. Ordered as the work happens so the UI can show a
/// sensible label without knowing the internals.
nonisolated enum BackupPhase: Equatable, Sendable {
    case idle
    case preparing
    case exporting
    case compressing
    case encrypting
    case uploading
    case completed
    case failed(BackupError)
    
    var isRunning: Bool {
        switch self {
        case .preparing, .exporting, .compressing, .encrypting, .uploading: true
        case .idle, .completed, .failed: false
        }
    }
}

/// Where a restore has got to.
nonisolated enum RestorePhase: Equatable, Sendable {
    case idle
    case findingBackup
    case downloading
    case validating
    case decrypting
    case restoring
    case completed
    case failed(BackupError)
    
    var isRunning: Bool {
        switch self {
        case .findingBackup, .downloading, .validating, .decrypting, .restoring: true
        case .idle, .completed, .failed: false
        }
    }
}

/// A snapshot of an in-flight backup for the UI to render.
nonisolated struct BackupProgress: Equatable, Sendable {
    var phase: BackupPhase = .idle
    /// 0...1 within the current phase, not across the whole run — only the upload
    /// reports real byte counts, so a single overall number would be invented.
    var fractionComplete: Double = 0
    var lastBackupDate: Date?
    var lastError: BackupError?
    var backupSize: Int64 = 0
}

/// A snapshot of an in-flight restore.
nonisolated struct RestoreProgress: Equatable, Sendable {
    var phase: RestorePhase = .idle
    var fractionComplete: Double = 0
    var lastError: BackupError?
}
