//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
@preconcurrency import KeychainAccess

// sourcery: AutoMockable
/// Holds the passphrase that backups are encrypted with.
///
/// Kept so automatic backups can run without asking every time. It deliberately does
/// not sync: a restore onto a new device asks the user for the passphrase, which is
/// the point — the destination holds nothing that can decrypt what it stores.
nonisolated protocol BackupPassphraseStoreProtocol: AnyObject, Sendable {
    var passphrase: String? { get }
    func setPassphrase(_ passphrase: String)
    func removePassphrase()
}

final nonisolated class BackupPassphraseStore: BackupPassphraseStoreProtocol {
    private let keychain: Keychain
    private static let key = "backupPassphrase"
    
    init(service: String, accessGroup: String) {
        keychain = Keychain(service: service, accessGroup: accessGroup)
            // Backups run when the app is backgrounded, so the passphrase has to be
            // readable then — but only on this device, and only once it's been
            // unlocked at least once since boot.
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }
    
    var passphrase: String? {
        try? keychain.getString(Self.key)
    }
    
    func setPassphrase(_ passphrase: String) {
        do {
            try keychain.set(passphrase, key: Self.key)
        } catch {
            MXLog.error("Failed storing the backup passphrase: \(error)")
        }
    }
    
    func removePassphrase() {
        do {
            try keychain.remove(Self.key)
        } catch {
            MXLog.error("Failed removing the backup passphrase: \(error)")
        }
    }
}
