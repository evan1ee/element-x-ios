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
        let read = try read(url)
        
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
        
        #expect(try read(url).entries == entries)
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
        
        #expect(try read(url).entries == entries)
    }
    
    // MARK: - Chunking
    
    /// The reason the format changed: an entry larger than a chunk has to round-trip
    /// across chunk boundaries, and every test above sits comfortably inside one.
    @Test
    func roundTripsAnEntrySpanningManyChunks() throws {
        // Pseudo-random so it can't be compressed down into a single chunk, which
        // would make this test silently stop covering what it claims to.
        var generator = SystemRandomNumberGenerator()
        let large = Data((0..<(BackupArchive.chunkSize * 3 + 1234)).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        let manifest = try write(["big.bin": large], to: url)
        #expect(manifest.entries.first?.size == Int64(large.count))
        
        #expect(try read(url).entries["big.bin"] == large)
    }
    
    /// Several multi-chunk entries in one package: each entry's chunks have to be
    /// read back against the right entry, not run together.
    @Test
    func keepsMultiChunkEntriesSeparate() throws {
        let entries = ["first.bin": Data(repeating: 0xA1, count: BackupArchive.chunkSize + 100),
                       "second.bin": Data(repeating: 0xB2, count: BackupArchive.chunkSize * 2 + 7),
                       "third.txt": Data("small".utf8)]
        
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(entries, to: url)
        
        #expect(try read(url).entries == entries)
    }
    
    /// Each chunk is sealed with a nonce derived from its position, so swapping two
    /// chunks has to fail rather than quietly producing scrambled output.
    @Test
    func rejectsReorderedChunks() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        
        _ = try write(["big.bin": Data(repeating: 0xC3, count: BackupArchive.chunkSize * 2)], to: url)
        
        // Chunks are uniform here, so the two sealed records are the same length:
        // swapping them keeps the file well-formed and only the nonce catches it.
        var raw = try Data(contentsOf: url)
        let manifest = try BackupArchive.readManifest(from: url)
        let headerSize = try 4 + 4 + (JSONEncoder().encode(manifest).count)
        let recordSize = (raw.count - headerSize) / 2
        let first = raw[headerSize..<(headerSize + recordSize)]
        let second = raw[(headerSize + recordSize)...]
        raw.replaceSubrange(headerSize..., with: Data(second) + Data(first))
        try raw.write(to: url)
        
        #expect(throws: (any Error).self) {
            try read(url)
        }
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
            try read(url, passphrase: "not the passphrase")
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
            try read(url)
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
            try read(url)
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
                           keySalt: manifest.keySalt,
                           noncePrefix: manifest.noncePrefix,
                           chunkSize: manifest.chunkSize)
        }
        
        #expect(throws: BackupError.versionMismatch(found: BackupManifest.currentFormatVersion + 1,
                                                    supported: BackupManifest.currentFormatVersion)) {
            try read(url)
        }
    }
    
    // MARK: - Helpers
    
    private static var sampleEntries: [String: Data] {
        ["database/matrix-sdk-state.sqlite3": Data(repeating: 0xAB, count: 4096),
         "search.sqlite": Data(repeating: 0xCD, count: 2048),
         "preferences.json": Data(#"{"theme":"dark"}"#.utf8),
         "metadata.json": Data(#"{"userID":"@alice:example.com"}"#.utf8)]
    }
    
    /// Writes each entry to its own file first, since the archive now takes URLs.
    private func write(_ entries: [String: Data], to url: URL) throws -> BackupManifest {
        let scratch = Self.temporaryDirectory()
        try FileManager.default.createDirectoryIfNeeded(at: scratch)
        
        var entryURLs: [String: URL] = [:]
        for (name, data) in entries {
            let fileURL = scratch.appending(component: name.replacingOccurrences(of: "/", with: "__"))
            try data.write(to: fileURL, options: .atomic)
            entryURLs[name] = fileURL
        }
        
        return try BackupArchive.write(entryURLs: entryURLs,
                                       to: url,
                                       passphrase: passphrase,
                                       appVersion: "1.2.3",
                                       databaseSchemaVersion: 1,
                                       searchIndexSchemaVersion: 2,
                                       providerID: .localFile,
                                       deviceName: "Test Device")
    }
    
    /// Reads a package back as bytes, so the round-trip assertions stay readable.
    private func read(_ url: URL, passphrase: String? = nil) throws -> (manifest: BackupManifest, entries: [String: Data]) {
        let directory = Self.temporaryDirectory()
        let result = try BackupArchive.read(from: url, passphrase: passphrase ?? self.passphrase, into: directory)
        let entries = try result.entryURLs.mapValues { try Data(contentsOf: $0) }
        return (result.manifest, entries)
    }
    
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
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
