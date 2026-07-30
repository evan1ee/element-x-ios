//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct BackupArchiveTests {
    private let passphrase = "correct horse battery staple"
    
    // MARK: - Round trip
    
    @Test
    func roundTripsEveryEntry() throws {
        let entries = Self.sampleEntries
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        let written = try write(entries, to: url)
        let read = try BackupArchive.read(from: url, passphrase: passphrase)
        
        #expect(read.entries == entries)
        #expect(read.manifest.formatVersion == BackupManifest.currentFormatVersion)
        #expect(read.manifest.entries.count == entries.count)
        #expect(written.checksum == read.manifest.checksum)
    }
    
    @Test
    func roundTripsAnEmptyEntry() throws {
        let entries = ["empty.bin": Data(), "one.bin": Data([0x01])]
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(entries, to: url)
        
        #expect(try BackupArchive.read(from: url, passphrase: passphrase).entries == entries)
    }
    
    /// Names go through a length-prefixed record rather than a path, so anything that
    /// would trip a naive separator-based format has to survive.
    @Test
    func roundTripsAwkwardEntryNames() throws {
        let entries = ["database/matrix-sdk-state.sqlite3": Data([0x01]),
                       "with space.json": Data([0x02]),
                       "ünïcode-🗄.bin": Data([0x03])]
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(entries, to: url)
        
        #expect(try BackupArchive.read(from: url, passphrase: passphrase).entries == entries)
    }
    
    // MARK: - Confidentiality
    
    /// The whole point of the feature: nothing readable should reach the destination.
    @Test
    func doesNotLeaveContentsInTheClear() throws {
        let secret = "the treasure is buried under the third oak"
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(["notes.txt": Data(secret.utf8)], to: url)
        
        let raw = try Data(contentsOf: url)
        #expect(raw.range(of: Data(secret.utf8)) == nil)
    }
    
    /// The header has to stay readable so backups can be listed and version-checked
    /// before anyone is asked for a passphrase.
    @Test
    func exposesTheManifestWithoutThePassphrase() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        let written = try write(Self.sampleEntries, to: url)
        let manifest = try BackupArchive.readManifest(from: url)
        
        #expect(manifest.deviceName == written.deviceName)
        #expect(manifest.appVersion == written.appVersion)
        #expect(manifest.providerID == .localFile)
    }
    
    @Test
    func rejectsTheWrongPassphrase() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(Self.sampleEntries, to: url)
        
        #expect(throws: BackupError.decryptionFailed) {
            try BackupArchive.read(from: url, passphrase: "not the passphrase")
        }
    }
    
    /// A fresh salt per backup means the same passphrase and contents never produce
    /// the same bytes twice.
    @Test
    func usesAFreshSaltEachTime() throws {
        let first = Self.temporaryURL()
        let second = Self.temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        
        let a = try write(Self.sampleEntries, to: first)
        let b = try write(Self.sampleEntries, to: second)
        
        #expect(a.keySalt != b.keySalt)
        #expect(try Data(contentsOf: first) != Data(contentsOf: second))
    }
    
    // MARK: - Integrity
    
    @Test
    func rejectsATruncatedPackage() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(Self.sampleEntries, to: url)
        let full = try Data(contentsOf: url)
        try full.prefix(full.count / 2).write(to: url)
        
        #expect(throws: (any Error).self) {
            try BackupArchive.read(from: url, passphrase: passphrase)
        }
    }
    
    /// Flipping a byte in the sealed payload must be caught, not decrypted into
    /// nonsense and written over a working database.
    @Test
    func rejectsATamperedPayload() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(Self.sampleEntries, to: url)
        var raw = try Data(contentsOf: url)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: url)
        
        #expect(throws: BackupError.decryptionFailed) {
            try BackupArchive.read(from: url, passphrase: passphrase)
        }
    }
    
    @Test
    func rejectsAFileThatIsNotABackup() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        try Data("this is just a text file, honest".utf8).write(to: url)
        
        #expect(throws: BackupError.corruptedPackage) {
            try BackupArchive.readManifest(from: url)
        }
    }
    
    @Test
    func rejectsAnEmptyFile() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        try Data().write(to: url)
        
        #expect(throws: BackupError.corruptedPackage) {
            try BackupArchive.readManifest(from: url)
        }
    }
    
    /// A corrupt length field shouldn't make the reader allocate against whatever
    /// number happens to be there.
    @Test
    func rejectsAnAbsurdManifestLength() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        var raw = Data("HXB1".utf8)
        raw.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        raw.append(Data(repeating: 0, count: 64))
        try raw.write(to: url)
        
        #expect(throws: BackupError.corruptedPackage) {
            try BackupArchive.readManifest(from: url)
        }
    }
    
    // MARK: - Versioning
    
    @Test
    func refusesAPackageFromANewerFormat() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(Self.sampleEntries, to: url)
        try Self.rewriteManifest(at: url) { manifest in
            BackupManifest(formatVersion: manifest.formatVersion + 1,
                           appVersion: manifest.appVersion,
                           databaseSchemaVersion: manifest.databaseSchemaVersion,
                           searchIndexSchemaVersion: manifest.searchIndexSchemaVersion,
                           createdAt: manifest.createdAt,
                           payloadSize: manifest.payloadSize,
                           checksum: manifest.checksum,
                           entries: manifest.entries,
                           providerID: manifest.providerID,
                           deviceName: manifest.deviceName,
                           keySalt: manifest.keySalt)
        }
        
        #expect(throws: BackupError.versionMismatch(found: BackupManifest.currentFormatVersion + 1,
                                                    supported: BackupManifest.currentFormatVersion)) {
            try BackupArchive.read(from: url, passphrase: passphrase)
        }
    }
    
    // MARK: - Helpers
    
    private static var sampleEntries: [String: Data] {
        ["database/matrix-sdk-state.sqlite3": Data(repeating: 0xAB, count: 4096),
         "search.sqlite": Data(repeating: 0xCD, count: 2048),
         "preferences.json": Data(#"{"theme":"dark"}"#.utf8),
         "metadata.json": Data(#"{"userID":"@alice:example.com"}"#.utf8)]
    }
    
    private func write(_ entries: [String: Data], to url: URL) throws -> BackupManifest {
        try BackupArchive.write(entries: entries,
                                to: url,
                                passphrase: passphrase,
                                appVersion: "1.2.3",
                                databaseSchemaVersion: 1,
                                searchIndexSchemaVersion: 2,
                                providerID: .localFile,
                                deviceName: "Test Device")
    }
    
    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: "\(UUID().uuidString).\(BackupArchive.fileExtension)")
    }
    
    /// Swaps the plaintext header, leaving the sealed payload untouched, so version
    /// handling can be exercised without a second implementation of the writer.
    private static func rewriteManifest(at url: URL, _ transform: (BackupManifest) -> BackupManifest) throws {
        let raw = try Data(contentsOf: url)
        let magicCount = 4
        let lengthCount = 4
        let length = raw[magicCount..<(magicCount + lengthCount)].reduce(Int(0)) { ($0 << 8) | Int($1) }
        let payload = raw[(magicCount + lengthCount + length)...]
        
        let original = try BackupArchive.readManifest(from: url)
        let replacement = try JSONEncoder().encode(transform(original))
        
        var out = Data("HXB1".utf8)
        out.append(withUnsafeBytes(of: UInt32(replacement.count).bigEndian) { Data($0) })
        out.append(replacement)
        out.append(payload)
        try out.write(to: url)
    }
}
