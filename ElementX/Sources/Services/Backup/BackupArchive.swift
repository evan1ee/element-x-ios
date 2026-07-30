//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
import Foundation

/// Reads and writes the `.hxb` container.
///
/// Layout, in order:
///
///     "HXB2"                 4 bytes, magic
///     manifest length        4 bytes, big endian
///     manifest JSON          plaintext
///     chunk records          one after another, in the manifest's entry order
///
/// and each chunk record is:
///
///     sealed length          4 bytes, big endian
///     sealed bytes           AES-GCM over the compressed chunk
///
/// The manifest is deliberately outside the encryption. Listing backups, showing how
/// old they are and refusing an unsupported version all happen before anyone is asked
/// for a passphrase, so that metadata has to be readable on its own. Everything with
/// user content in it is inside a sealed box.
///
/// Chunked rather than one box because a backup is as large as the account is: sealing
/// in one piece means holding the whole thing in memory, which is a limit that gets
/// hit by exactly the people who most need a backup. Each chunk is compressed and
/// sealed on its own, so peak memory is a chunk rather than a database.
nonisolated enum BackupArchive {
    static let fileExtension = "hxb"
    
    private static let magic = Data("HXB2".utf8)
    /// Version 1 sealed the whole payload at once. Still readable so backups taken
    /// before the streaming writer aren't stranded.
    private static let legacyMagic = Data("HXB1".utf8)
    private static let lengthSize = 4
    
    /// A manifest is a few hundred bytes plus one entry each. The cap stops a corrupt
    /// length field from making us allocate against a hostile number.
    private static let maximumManifestSize = 1 << 20
    /// Plaintext bytes per chunk. Large enough that per-chunk overhead and compression
    /// loss stay negligible, small enough that peak memory is a few megabytes.
    static let chunkSize = 1 << 20
    /// A compressed chunk should never exceed its plaintext by more than zlib's
    /// worst case; anything beyond this is a corrupt length rather than a real chunk.
    private static let maximumSealedChunkSize = (1 << 20) * 2
    
    // MARK: - Writing
    
    /// Seals the files at `entryURLs` into a package at `destinationURL`.
    ///
    /// Takes URLs rather than bytes so nothing larger than a chunk is ever resident.
    ///
    /// - Parameter entryURLs: package-relative name to the file holding its contents.
    static func write(entryURLs: [String: URL],
                      to destinationURL: URL,
                      passphrase: String,
                      appVersion: String,
                      databaseSchemaVersion: Int,
                      searchIndexSchemaVersion: Int,
                      providerID: BackupProviderID,
                      deviceName: String) throws -> BackupManifest {
        let salt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let noncePrefix = Data((0..<7).map { _ in UInt8.random(in: .min ... .max) })
        let key = deriveKey(passphrase: passphrase, salt: salt)
        
        // Chunks go to a scratch file first: the manifest carries the checksums, and
        // those aren't known until everything has been read. Writing the payload once
        // and copying it beats reading every source file twice — and a second read
        // could see a different database, since SQLite is still being written to.
        let payloadURL = FileManager.default.temporaryDirectory
            .appending(component: "hxb-payload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: payloadURL.path(percentEncoded: false), contents: nil)
        defer { try? FileManager.default.removeItem(at: payloadURL) }
        
        guard let payloadHandle = FileHandle(forWritingAtPath: payloadURL.path(percentEncoded: false)) else {
            throw BackupError.encryptionFailed
        }
        
        var entries: [BackupEntry] = []
        var totalHasher = SHA256()
        var counter: UInt32 = 0
        let names = entryURLs.keys.sorted()
        
        do {
            for name in names {
                guard let url = entryURLs[name],
                      let reader = FileHandle(forReadingAtPath: url.path(percentEncoded: false)) else {
                    continue
                }
                defer { try? reader.close() }
                
                var entryHasher = SHA256()
                var entrySize: Int64 = 0
                
                while true {
                    let plain = try reader.read(upToCount: chunkSize) ?? Data()
                    guard !plain.isEmpty else { break }
                    
                    entryHasher.update(data: plain)
                    totalHasher.update(data: plain)
                    entrySize += Int64(plain.count)
                    
                    let sealed = try seal(plain, key: key, noncePrefix: noncePrefix, counter: counter)
                    counter += 1
                    
                    try payloadHandle.write(contentsOf: bigEndian(sealed.count))
                    try payloadHandle.write(contentsOf: sealed)
                }
                
                entries.append(BackupEntry(name: name, size: entrySize, checksum: digest(entryHasher)))
            }
            try payloadHandle.close()
        } catch {
            try? payloadHandle.close()
            throw BackupError.encryptionFailed
        }
        
        let manifest = BackupManifest(formatVersion: BackupManifest.currentFormatVersion,
                                      appVersion: appVersion,
                                      databaseSchemaVersion: databaseSchemaVersion,
                                      searchIndexSchemaVersion: searchIndexSchemaVersion,
                                      createdAt: .now,
                                      payloadSize: entries.reduce(0) { $0 + $1.size },
                                      checksum: digest(totalHasher),
                                      entries: entries,
                                      providerID: providerID,
                                      deviceName: deviceName,
                                      keySalt: salt,
                                      noncePrefix: noncePrefix,
                                      chunkSize: chunkSize)
        
        try assemble(manifest: manifest, payloadURL: payloadURL, into: destinationURL)
        return manifest
    }
    
    /// Writes the header then appends the payload a chunk at a time, so assembling
    /// the package doesn't undo the streaming that produced it.
    private static func assemble(manifest: BackupManifest, payloadURL: URL, into destinationURL: URL) throws {
        let manifestData = try JSONEncoder().encode(manifest)
        
        var header = Data()
        header.append(magic)
        header.append(bigEndian(manifestData.count))
        header.append(manifestData)
        try header.write(to: destinationURL, options: .atomic)
        
        guard let output = FileHandle(forWritingAtPath: destinationURL.path(percentEncoded: false)),
              let input = FileHandle(forReadingAtPath: payloadURL.path(percentEncoded: false)) else {
            throw BackupError.encryptionFailed
        }
        defer {
            try? output.close()
            try? input.close()
        }
        
        try output.seekToEnd()
        while let block = try input.read(upToCount: chunkSize), !block.isEmpty {
            try output.write(contentsOf: block)
        }
    }
    
    // MARK: - Reading
    
    /// Parses just the header. Cheap enough to run over every file when listing, and
    /// needs no passphrase.
    static func readManifest(from url: URL) throws -> BackupManifest {
        guard let handle = FileHandle(forReadingAtPath: url.path(percentEncoded: false)) else {
            throw BackupError.corruptedPackage
        }
        defer { try? handle.close() }
        
        guard let header = try handle.read(upToCount: magic.count + lengthSize),
              header.count == magic.count + lengthSize else {
            throw BackupError.corruptedPackage
        }
        
        let foundMagic = header.prefix(magic.count)
        guard foundMagic == magic || foundMagic == legacyMagic else {
            throw BackupError.corruptedPackage
        }
        
        let length = Int(bigEndianValue(header.suffix(lengthSize)))
        guard length > 0, length <= maximumManifestSize,
              let manifestData = try handle.read(upToCount: length), manifestData.count == length else {
            throw BackupError.corruptedPackage
        }
        
        do {
            return try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.corruptedPackage
        }
    }
    
    /// Opens a package, writing each entry out to `directory` as it is decrypted.
    ///
    /// Returns where each entry landed rather than its bytes, for the same reason the
    /// writer takes URLs: the caller shouldn't have to hold a database in memory.
    /// Validates the version before decrypting anything and every checksum before
    /// returning, so a caller can't act on a payload that only partly arrived.
    static func read(from url: URL,
                     passphrase: String,
                     into directory: URL) throws -> (manifest: BackupManifest, entryURLs: [String: URL]) {
        let manifest = try readManifest(from: url)
        
        guard manifest.isSupported else {
            throw BackupError.versionMismatch(found: manifest.formatVersion,
                                              supported: BackupManifest.currentFormatVersion)
        }
        
        try FileManager.default.createDirectoryIfNeeded(at: directory)
        
        guard manifest.formatVersion >= 2 else {
            return try (manifest, readLegacy(from: url, manifest: manifest, passphrase: passphrase, into: directory))
        }
        
        guard let handle = FileHandle(forReadingAtPath: url.path(percentEncoded: false)) else {
            throw BackupError.corruptedPackage
        }
        defer { try? handle.close() }
        
        // Skip to the payload using the stored manifest length, not a re-encoded one:
        // JSON key order isn't guaranteed to round-trip byte for byte.
        try handle.seek(toOffset: UInt64(magic.count))
        guard let storedLength = try handle.read(upToCount: lengthSize), storedLength.count == lengthSize else {
            throw BackupError.corruptedPackage
        }
        try handle.seek(toOffset: UInt64(magic.count + lengthSize + Int(bigEndianValue(storedLength))))
        
        let key = deriveKey(passphrase: passphrase, salt: manifest.keySalt)
        let chunkSize = manifest.chunkSize ?? Self.chunkSize
        guard chunkSize > 0 else { throw BackupError.corruptedPackage }
        
        var entryURLs: [String: URL] = [:]
        var totalHasher = SHA256()
        var counter: UInt32 = 0
        
        for entry in manifest.entries {
            let destination = directory.appending(component: encodedName(entry.name))
            FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
            guard let writer = FileHandle(forWritingAtPath: destination.path(percentEncoded: false)) else {
                throw BackupError.corruptedPackage
            }
            
            var entryHasher = SHA256()
            var remaining = entry.size
            
            do {
                while remaining > 0 {
                    guard let lengthBytes = try handle.read(upToCount: lengthSize), lengthBytes.count == lengthSize else {
                        throw BackupError.corruptedPackage
                    }
                    let sealedLength = Int(bigEndianValue(lengthBytes))
                    guard sealedLength > 0, sealedLength <= maximumSealedChunkSize,
                          let sealed = try handle.read(upToCount: sealedLength), sealed.count == sealedLength else {
                        throw BackupError.corruptedPackage
                    }
                    
                    let plain = try open(sealed, key: key, noncePrefix: manifest.noncePrefix ?? Data(), counter: counter)
                    counter += 1
                    
                    entryHasher.update(data: plain)
                    totalHasher.update(data: plain)
                    remaining -= Int64(plain.count)
                    try writer.write(contentsOf: plain)
                }
                try writer.close()
            } catch {
                try? writer.close()
                throw error
            }
            
            guard remaining == 0, digest(entryHasher) == entry.checksum else {
                throw BackupError.corruptedPackage
            }
            entryURLs[entry.name] = destination
        }
        
        guard digest(totalHasher) == manifest.checksum else {
            throw BackupError.corruptedPackage
        }
        
        return (manifest, entryURLs)
    }
    
    /// Version 1: a single sealed box over the whole compressed payload. Read whole
    /// because that's the shape it was written in — the reason the format changed.
    private static func readLegacy(from url: URL,
                                   manifest: BackupManifest,
                                   passphrase: String,
                                   into directory: URL) throws -> [String: URL] {
        let file = try Data(contentsOf: url)
        let lengthRange = legacyMagic.count..<(legacyMagic.count + lengthSize)
        guard file.count > lengthRange.upperBound else { throw BackupError.corruptedPackage }
        let payloadStart = legacyMagic.count + lengthSize + Int(bigEndianValue(file[lengthRange]))
        guard file.count > payloadStart else { throw BackupError.corruptedPackage }
        
        let key = deriveKey(passphrase: passphrase, salt: manifest.keySalt)
        let compressed: Data
        do {
            compressed = try AES.GCM.open(AES.GCM.SealedBox(combined: file[payloadStart...]), using: key)
        } catch {
            throw BackupError.decryptionFailed
        }
        
        guard let payload = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
            throw BackupError.corruptedPackage
        }
        
        var entryURLs: [String: URL] = [:]
        var cursor = Data(payload).startIndex
        let data = Data(payload)
        
        while cursor < data.endIndex {
            guard let nameLength = readLength(data, at: &cursor),
                  let nameData = readSlice(data, length: nameLength, at: &cursor),
                  let name = String(data: nameData, encoding: .utf8),
                  let bodyLength = readLength(data, at: &cursor),
                  let body = readSlice(data, length: bodyLength, at: &cursor) else {
                throw BackupError.corruptedPackage
            }
            
            let destination = directory.appending(component: encodedName(name))
            try body.write(to: destination, options: .atomic)
            entryURLs[name] = destination
        }
        
        return entryURLs
    }
    
    // MARK: - Chunks
    
    /// Compresses then seals. The nonce is derived rather than stored: a random
    /// prefix fixed per package plus the chunk's position, so every chunk gets a
    /// distinct nonce and reordering or dropping one fails the tag check.
    private static func seal(_ plain: Data, key: SymmetricKey, noncePrefix: Data, counter: UInt32) throws -> Data {
        guard let compressed = try? (plain as NSData).compressed(using: .zlib) as Data else {
            throw BackupError.encryptionFailed
        }
        
        do {
            let box = try AES.GCM.seal(compressed, using: key, nonce: nonce(prefix: noncePrefix, counter: counter))
            return box.ciphertext + box.tag
        } catch {
            throw BackupError.encryptionFailed
        }
    }
    
    private static func open(_ sealed: Data, key: SymmetricKey, noncePrefix: Data, counter: UInt32) throws -> Data {
        let tagSize = 16
        guard sealed.count > tagSize else { throw BackupError.corruptedPackage }
        
        let compressed: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce(prefix: noncePrefix, counter: counter),
                                            ciphertext: sealed.dropLast(tagSize),
                                            tag: sealed.suffix(tagSize))
            compressed = try AES.GCM.open(box, using: key)
        } catch {
            // GCM can't tell a wrong key from altered bytes — both fail the tag check.
            // Reported as a bad passphrase because that's overwhelmingly the cause,
            // and the checksums catch corruption that somehow decrypts.
            throw BackupError.decryptionFailed
        }
        
        guard let plain = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
            throw BackupError.corruptedPackage
        }
        return plain
    }
    
    private static func nonce(prefix: Data, counter: UInt32) -> AES.GCM.Nonce {
        var bytes = Data(prefix.prefix(7))
        // A short or missing prefix would silently shrink the nonce; pad so the
        // counter always lands in the same place.
        while bytes.count < 7 {
            bytes.append(0)
        }
        bytes.append(contentsOf: withUnsafeBytes(of: counter.bigEndian) { Data($0) })
        bytes.append(0)
        // 12 bytes by construction, so this can't fail.
        return try! AES.GCM.Nonce(data: bytes) // swiftlint:disable:this force_try
    }
    
    // MARK: - Keys
    
    /// HKDF over the passphrase. The salt is per-backup, so the same passphrase
    /// produces a different key for every package.
    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
                               salt: salt,
                               info: Data("halo-x.backup.v1".utf8),
                               outputByteCount: 32)
    }
    
    // MARK: - Bytes
    
    /// Entry names carry '/', which can't be a filename on the way out.
    private static func encodedName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "__")
    }
    
    private static func digest(_ hasher: SHA256) -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    
    private static func bigEndian(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }
    
    private static func bigEndianValue(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    
    private static func readLength(_ data: Data, at cursor: inout Data.Index) -> Int? {
        guard let slice = readSlice(data, length: lengthSize, at: &cursor) else { return nil }
        return Int(bigEndianValue(slice))
    }
    
    private static func readSlice(_ data: Data, length: Int, at cursor: inout Data.Index) -> Data? {
        guard length >= 0, data.distance(from: cursor, to: data.endIndex) >= length else { return nil }
        let end = data.index(cursor, offsetBy: length)
        defer { cursor = end }
        return Data(data[cursor..<end])
    }
}
