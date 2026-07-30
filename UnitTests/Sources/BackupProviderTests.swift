//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

/// Exercises a provider through nothing but `BackupProviderProtocol`.
///
/// Written against the interface on purpose: if a future WebDAV or AirDrop provider
/// passes these, it will work with the engine, and if adding one required changing
/// this file the abstraction would have leaked.
struct BackupProviderTests {
    @Test
    func storesListsAndRetrievesAPackage() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider: any BackupProviderProtocol = LocalFileBackupProvider(directory: directory)
        
        #expect(await provider.isAvailable())
        #expect(await provider.authenticate().isSuccess)
        
        let package = Self.temporaryDirectory().appending(component: "package.hxb")
        try FileManager.default.createDirectoryIfNeeded(at: package.deletingLastPathComponent())
        let manifest = try BackupArchive.write(entries: ["a.bin": Data(repeating: 0x11, count: 512)],
                                               to: package,
                                               passphrase: "pass",
                                               appVersion: "1.0.0",
                                               databaseSchemaVersion: 1,
                                               searchIndexSchemaVersion: 2,
                                               providerID: .localFile,
                                               deviceName: "Device")
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        
        let uploaded = try #require(await provider.upload(packageURL: package, manifest: manifest) { _ in }.successValue)
        #expect(uploaded.size > 0)
        #expect(uploaded.deviceName == "Device")
        
        let listed = try #require(await provider.listBackups().successValue)
        #expect(listed.count == 1)
        #expect(listed.first?.id == uploaded.id)
        // Listing parses the header, so it can describe a backup it hasn't decrypted.
        #expect(listed.first?.manifest?.appVersion == "1.0.0")
        
        // Outside the provider's own directory, as the manager does — downloading into
        // it would make the fetched copy look like a second backup.
        let fetchDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fetchDirectory) }
        try FileManager.default.createDirectoryIfNeeded(at: fetchDirectory)
        let destination = fetchDirectory.appending(component: "fetched.hxb")
        _ = try #require(await provider.download(id: uploaded.id, to: destination) { _ in }.successValue)
        #expect(try BackupArchive.read(from: destination, passphrase: "pass").entries["a.bin"]?.count == 512)
        
        let info = try #require(await provider.storageInfo().successValue)
        #expect(info.backupCount == 1)
        #expect(info.usedBytes > 0)
        
        #expect(await provider.deleteBackup(id: uploaded.id).isSuccess)
        #expect(await provider.listBackups().successValue?.isEmpty == true)
    }
    
    @Test
    func reportsAnEmptyListBeforeAnythingIsStored() async {
        let directory = Self.temporaryDirectory().appending(component: "never-created")
        let provider = LocalFileBackupProvider(directory: directory)
        
        #expect(await provider.listBackups().successValue?.isEmpty == true)
        #expect(await provider.storageInfo().successValue?.backupCount == 0)
    }
    
    @Test
    func reportsAMissingPackageRatherThanCrashing() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = LocalFileBackupProvider(directory: directory)
        
        let result = await provider.download(id: "absent.hxb",
                                             to: directory.appending(component: "out.hxb")) { _ in }
        #expect(result.failureValue == .corruptedPackage)
    }
    
    /// Deleting something already gone is the state the caller asked for.
    @Test
    func treatsDeletingAnAbsentBackupAsSuccess() async {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        
        #expect(await LocalFileBackupProvider(directory: directory).deleteBackup(id: "absent.hxb").isSuccess)
    }
    
    /// A foreign file still has to be listed, otherwise it can never be cleaned up.
    @Test
    func listsAnUnreadablePackageWithoutAManifest() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectoryIfNeeded(at: directory)
        try Data("not a backup".utf8).write(to: directory.appending(component: "junk.hxb"))
        
        let listed = try #require(await LocalFileBackupProvider(directory: directory).listBackups().successValue)
        #expect(listed.count == 1)
        #expect(listed.first?.manifest == nil)
    }
    
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }
    
    var successValue: Success? {
        if case .success(let value) = self {
            value
        } else {
            nil
        }
    }
    
    var failureValue: Failure? {
        if case .failure(let error) = self {
            error
        } else {
            nil
        }
    }
}
