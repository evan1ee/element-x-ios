//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// What a disable should do with what's already stored. Asked rather than assumed —
/// turning a feature off shouldn't destroy data as a side effect.
enum BackupDisposal: Equatable, Sendable {
    case keepExistingBackups
    case deleteExistingBackups
}

// sourcery: AutoMockable
/// Drives backups and restores, and knows nothing about where they're kept.
///
/// Everything destination-shaped goes through `BackupProviderProtocol`, so adding a
/// provider means adding a conformance and registering it — nothing here changes.
protocol BackupManagerProtocol: AnyObject {
    var progressPublisher: CurrentValuePublisher<BackupProgress, Never> { get }
    var restoreProgressPublisher: CurrentValuePublisher<RestoreProgress, Never> { get }
    
    /// Every provider compiled into the app, in display order, available or not.
    var providers: [BackupProviderProtocol] { get }
    /// The subset that could be used right now. The picker shows only these.
    func availableProviders() async -> [BackupProviderProtocol]
    
    var selectedProviderID: BackupProviderID { get }
    func selectProvider(_ id: BackupProviderID)
    
    var isEnabled: Bool { get }
    /// Turns backups on and takes the first one. The passphrase is kept so later
    /// automatic runs don't have to ask.
    func enable(passphrase: String) async -> Result<Void, BackupError>
    /// Stops automatic backups. Only removes what's stored when asked to.
    func disable(disposal: BackupDisposal) async -> Result<Void, BackupError>
    
    /// Runs a backup now, regardless of the automatic triggers.
    func backUpNow() async -> Result<Void, BackupError>
    
    func listBackups() async -> Result<[BackupDescriptor], BackupError>
    func deleteBackup(id: String) async -> Result<Void, BackupError>
    func storageInfo() async -> Result<BackupStorageInfo, BackupError>
    
    /// Restores over the local databases. The passphrase is supplied by the user,
    /// since a new device has nothing stored.
    func restore(descriptor: BackupDescriptor, passphrase: String) async -> Result<Void, BackupError>
    
    /// Called when the app backgrounds so the triggers can be evaluated.
    func applicationDidEnterBackground()
}
