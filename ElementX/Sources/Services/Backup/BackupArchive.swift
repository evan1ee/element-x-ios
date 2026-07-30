//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compression
import CryptoKit
import Foundation

/// Reads and writes the `.hxb` container.
///
/// Layout, in order:
///
///     "HXB1"                 4 bytes, magic
///     manifest length        4 bytes, big endian
///     manifest JSON          plaintext
///     sealed payload         AES-GCM over the compressed entries
///
/// The manifest is deliberately outside the encryption. Listing backups, showing how
/// old they are and refusing an unsupported version all happen before anyone is asked
/// for a passphrase, so that metadata has to be readable on its own. Everything with
/// user content in it is inside the sealed box.
nonisolated enum BackupArchive {
    static let fileExtension = "hxb"
    private static let magic = Data("HXB1".utf8)
    private static let manifestLengthSize = 4
    /// A manifest is a few hundred bytes. The cap stops a corrupt length field from
    /// making us allocate against a hostile number before anything is validated.
    private static let maximumManifestSize = 1 << 20
    
    // MARK: - Writing
    
    /// Packs `entries` into a sealed package at `destinationURL`.
    ///
    /// - Parameter entries: name to contents. Names are paths within the package.
    static func write(entries: [String: Data],
                      to destinationURL: URL,
                      passphrase: String,
                      appVersion: String,
                      databaseSchemaVersion: Int,
                      searchIndexSchemaVersion: Int,
                      providerID: BackupProviderID,
                      deviceName: String) throws -> BackupManifest {
        let payload = try pack(entries)
        let compressed = try compress(payload)
        
        let salt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let key = deriveKey(passphrase: passphrase, salt: salt)
        
        let sealed: Data
        do {
            sealed = try AES.GCM.seal(compressed, using: key).combined ?? { throw BackupError.encryptionFailed }()
        } catch {
            throw BackupError.encryptionFailed
        }
        
        let manifest = BackupManifest(formatVersion: BackupManifest.currentFormatVersion,
                                      appVersion: appVersion,
                                      databaseSchemaVersion: databaseSchemaVersion,
                                      searchIndexSchemaVersion: searchIndexSchemaVersion,
                                      createdAt: .now,
                                      payloadSize: Int64(payload.count),
                                      checksum: sha256(compressed),
                                      entries: entries
                                          .map { BackupEntry(name: $0.key, size: Int64($0.value.count), checksum: sha256($0.value)) }
                                          .sorted { $0.name < $1.name },
                                      providerID: providerID,
                                      deviceName: deviceName,
                                      keySalt: salt)
        
        let manifestData = try JSONEncoder().encode(manifest)
        
        var file = Data()
        file.append(magic)
        file.append(bigEndianLength(manifestData.count))
        file.append(manifestData)
        file.append(sealed)
        
        try file.write(to: destinationURL, options: .atomic)
        return manifest
    }
    
    // MARK: - Reading
    
    /// Parses just the header. Cheap enough to run over every file when listing, and
    /// needs no passphrase.
    static func readManifest(from url: URL) throws -> BackupManifest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        guard let header = try handle.read(upToCount: magic.count + manifestLengthSize),
              header.count == magic.count + manifestLengthSize,
              header.prefix(magic.count) == magic else {
            throw BackupError.corruptedPackage
        }
        
        let length = Int(bigEndianValue(header.suffix(manifestLengthSize)))
        guard length > 0, length <= maximumManifestSize else {
            throw BackupError.corruptedPackage
        }
        
        guard let manifestData = try handle.read(upToCount: length), manifestData.count == length else {
            throw BackupError.corruptedPackage
        }
        
        do {
            return try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.corruptedPackage
        }
    }
    
    /// Opens a package. Validates the version and the checksum before returning
    /// anything, so a caller can't act on a payload that only partly arrived.
    static func read(from url: URL, passphrase: String) throws -> (manifest: BackupManifest, entries: [String: Data]) {
        let manifest = try readManifest(from: url)
        
        guard manifest.isSupported else {
            throw BackupError.versionMismatch(found: manifest.formatVersion,
                                              supported: BackupManifest.currentFormatVersion)
        }
        
        let file = try Data(contentsOf: url)
        // The payload offset comes from the stored length, not from re-encoding the
        // manifest: JSON key order isn't guaranteed to round-trip byte for byte.
        let lengthRange = magic.count..<(magic.count + manifestLengthSize)
        guard file.count > lengthRange.upperBound else { throw BackupError.corruptedPackage }
        let length = Int(bigEndianValue(file[lengthRange]))
        let payloadStart = magic.count + manifestLengthSize + length
        guard file.count > payloadStart else { throw BackupError.corruptedPackage }
        
        let sealed = file[payloadStart...]
        
        let key = deriveKey(passphrase: passphrase, salt: manifest.keySalt)
        let compressed: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            compressed = try AES.GCM.open(box, using: key)
        } catch {
            // GCM can't tell a wrong key from altered bytes — both fail the tag check.
            // Reported as a bad passphrase because that's overwhelmingly the cause,
            // and the checksum below catches genuine corruption that decrypts.
            throw BackupError.decryptionFailed
        }
        
        guard sha256(compressed) == manifest.checksum else {
            throw BackupError.corruptedPackage
        }
        
        let payload = try decompress(compressed, expectedSize: Int(manifest.payloadSize))
        let entries = try unpack(payload)
        
        for entry in manifest.entries {
            guard let data = entries[entry.name], sha256(data) == entry.checksum else {
                throw BackupError.corruptedPackage
            }
        }
        
        return (manifest, entries)
    }
    
    // MARK: - Entry packing
    
    /// Length-prefixed records: name length, name, data length, data. A tar or zip
    /// would work too, but this needs no dependency and the format is only ever read
    /// by the code that wrote it.
    private static func pack(_ entries: [String: Data]) throws -> Data {
        var out = Data()
        for name in entries.keys.sorted() {
            guard let data = entries[name] else { continue }
            let nameData = Data(name.utf8)
            out.append(bigEndianLength(nameData.count))
            out.append(nameData)
            out.append(bigEndianLength(data.count))
            out.append(data)
        }
        return out
    }
    
    private static func unpack(_ payload: Data) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        var cursor = payload.startIndex
        
        while cursor < payload.endIndex {
            guard let nameLength = readLength(payload, at: &cursor),
                  let name = readSlice(payload, length: nameLength, at: &cursor).flatMap({ String(data: $0, encoding: .utf8) }),
                  let dataLength = readLength(payload, at: &cursor),
                  let data = readSlice(payload, length: dataLength, at: &cursor) else {
                throw BackupError.corruptedPackage
            }
            entries[name] = data
        }
        
        return entries
    }
    
    private static func readLength(_ data: Data, at cursor: inout Data.Index) -> Int? {
        guard let slice = readSlice(data, length: manifestLengthSize, at: &cursor) else { return nil }
        return Int(bigEndianValue(slice))
    }
    
    private static func readSlice(_ data: Data, length: Int, at cursor: inout Data.Index) -> Data? {
        guard length >= 0, data.distance(from: cursor, to: data.endIndex) >= length else { return nil }
        let end = data.index(cursor, offsetBy: length)
        defer { cursor = end }
        return Data(data[cursor..<end])
    }
    
    // MARK: - Compression
    
    private static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data else {
            throw BackupError.encryptionFailed
        }
        return compressed
    }
    
    private static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data else {
            throw BackupError.corruptedPackage
        }
        guard decompressed.count == expectedSize else {
            throw BackupError.corruptedPackage
        }
        return decompressed
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
    
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    private static func bigEndianLength(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }
    
    private static func bigEndianValue(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
