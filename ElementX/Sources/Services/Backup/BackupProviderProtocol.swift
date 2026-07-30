//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// sourcery: AutoMockable
/// A place a backup can be kept.
///
/// The whole interface is in terms of an already-sealed file on disk: the core hands
/// over a package and asks for one back. A provider never sees the contents, the
/// passphrase, or anything about what the app stores, which is what lets a new
/// destination be added without touching the backup engine.
///
/// Nonisolated because every implementation does file or network work that has no
/// business on the main actor.
nonisolated protocol BackupProviderProtocol: AnyObject, Sendable {
    var id: BackupProviderID { get }
    /// Shown in the destination picker. Localised by the provider, since only it
    /// knows what to call itself.
    var name: String { get }
    
    /// Whether this destination can be used on this device right now — the account is
    /// signed in, the container resolves, the server answers. Called to decide
    /// whether to offer the provider at all, so it must not prompt.
    func isAvailable() async -> Bool
    
    /// Obtains whatever permission the destination needs. A no-op where the platform
    /// grants access implicitly, which is why the core always calls it and never
    /// reasons about whether it is needed.
    func authenticate() async -> Result<Void, BackupError>
    
    /// Stores a sealed package. `progress` reports 0...1 and may be called from any
    /// thread; it isn't guaranteed to reach 1 before the call returns.
    func upload(packageURL: URL,
                manifest: BackupManifest,
                progress: @escaping @Sendable (Double) -> Void) async -> Result<BackupDescriptor, BackupError>
    
    /// Fetches a package to `destinationURL`, returning where it actually landed.
    func download(id: String,
                  to destinationURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async -> Result<URL, BackupError>
    
    /// Newest first. Entries whose header won't parse are still returned with a nil
    /// manifest, so a damaged file can be seen and removed rather than being invisible.
    func listBackups() async -> Result<[BackupDescriptor], BackupError>
    
    func deleteBackup(id: String) async -> Result<Void, BackupError>
    
    func storageInfo() async -> Result<BackupStorageInfo, BackupError>
}
