//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// sourcery: AutoMockable
/// Supplies the bytes a backup is made of, and puts them back on restore.
///
/// Separate from the manager so the engine deals only in named blobs: it compresses,
/// encrypts and hands them to a provider without knowing that one of them is a Rust
/// state store and another is an FTS index.
nonisolated protocol BackupDataSourceProtocol: AnyObject, Sendable {
    /// Written into the manifest and compared on restore, so a package from a newer
    /// schema is refused rather than half-applied.
    var databaseSchemaVersion: Int { get }
    var searchIndexSchemaVersion: Int { get }
    
    /// Package-relative name to the file holding its contents. URLs rather than bytes
    /// so a backup never has to fit in memory; `scratchDirectory` is where synthesised
    /// entries are written and is the caller's to clean up.
    func exportEntryURLs(scratchDirectory: URL) async throws -> [String: URL]
    func importEntryURLs(_ entryURLs: [String: URL]) async throws
}

/// The real one: the session's databases, the search index, and preferences.
final nonisolated class SessionBackupDataSource: BackupDataSourceProtocol {
    /// Nil when the session's directories can't be resolved. The index and
    /// preferences are still worth backing up on their own, so that isn't fatal —
    /// the package simply carries no database entries.
    private let sessionDirectories: SessionDirectories?
    private let searchIndexURL: URL
    private let userID: String
    
    /// `UserDefaults` isn't `Sendable`, so the suite is named here and opened where
    /// it's used. Opening a suite is cheap and the instance is a shared singleton.
    private let preferencesSuiteName: String?
    private var userDefaults: UserDefaults? {
        preferencesSuiteName.flatMap(UserDefaults.init(suiteName:))
    }
    
    /// Prefixes worth keeping. The crypto store is deliberately absent — device keys
    /// belong to the device, and Matrix has its own key backup for them. The media
    /// cache is absent too: it re-downloads, and it's the bulk of the bytes.
    private static let databasePrefixes = ["matrix-sdk-state", "matrix-sdk-event-cache"]
    
    /// Preference keys that describe this install rather than the user's choices.
    /// Restoring them onto another device would be wrong.
    private static let excludedPreferenceKeys: Set = [
        "lastLoginDate", "deviceID", "pusherProfileTag", "sessionDirectories"
    ]
    
    static let databaseDirectory = "database"
    static let searchEntryName = "search.sqlite"
    static let preferencesEntryName = "preferences.json"
    static let metadataEntryName = "metadata.json"
    
    init(sessionDirectories: SessionDirectories?,
         searchIndexURL: URL,
         preferencesSuiteName: String?,
         userID: String) {
        self.sessionDirectories = sessionDirectories
        self.searchIndexURL = searchIndexURL
        self.preferencesSuiteName = preferencesSuiteName
        self.userID = userID
    }
    
    var databaseSchemaVersion: Int {
        1
    }
    
    var searchIndexSchemaVersion: Int {
        SearchIndexService.schemaVersion
    }
    
    func exportEntryURLs(scratchDirectory: URL) async throws -> [String: URL] {
        var entries: [String: URL] = [:]
        
        // The databases are already files, so they're referenced where they lie rather
        // than read. Only the two synthesised entries need writing out.
        for directory in [sessionDirectories?.dataDirectory, sessionDirectories?.cacheDirectory].compactMap(\.self) {
            let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                         includingPropertiesForKeys: nil)) ?? []
            for url in contents where Self.databasePrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
                entries["\(Self.databaseDirectory)/\(url.lastPathComponent)"] = url
            }
        }
        
        // The -wal and -shm siblings come along with the loop above, so the index is
        // captured as SQLite left it rather than needing a checkpoint we can't force
        // from outside the actor that owns the connection.
        for url in searchIndexSiblings() {
            let suffix = url.lastPathComponent.dropFirst(searchIndexURL.lastPathComponent.count)
            entries[Self.searchEntryName + suffix] = url
        }
        
        try FileManager.default.createDirectoryIfNeeded(at: scratchDirectory)
        
        let preferencesURL = scratchDirectory.appending(component: Self.preferencesEntryName)
        try JSONSerialization.data(withJSONObject: exportedPreferences()).write(to: preferencesURL, options: .atomic)
        entries[Self.preferencesEntryName] = preferencesURL
        
        let metadataURL = scratchDirectory.appending(component: Self.metadataEntryName)
        try JSONEncoder().encode(BackupMetadata(userID: userID, createdAt: .now)).write(to: metadataURL, options: .atomic)
        entries[Self.metadataEntryName] = metadataURL
        
        return entries
    }
    
    /// Stages rather than writes. The databases are open right now, so putting the
    /// files in place has to wait for the next launch — see `BackupRestoreStaging`.
    func importEntryURLs(_ entryURLs: [String: URL]) async throws {
        try BackupRestoreStaging.stage(entryURLs: entryURLs)
    }
    
    /// Puts a restore in place. Only safe before anything opens these databases,
    /// which is why it's separate from `importEntryURLs` and called during startup.
    func write(entryURLs: [String: URL]) throws {
        for (name, source) in entryURLs where name.hasPrefix("\(Self.databaseDirectory)/") {
            guard let sessionDirectories else { continue }
            let filename = String(name.dropFirst(Self.databaseDirectory.count + 1))
            // The event cache belongs in caches and the state store in data. Writing
            // both to one place would leave the SDK unable to find half of them.
            let directory = filename.hasPrefix("matrix-sdk-event-cache")
                ? sessionDirectories.cacheDirectory
                : sessionDirectories.dataDirectory
            try FileManager.default.createDirectoryIfNeeded(at: directory)
            try Self.replaceItem(at: directory.appending(component: filename), with: source)
        }
        
        for (name, source) in entryURLs where name.hasPrefix(Self.searchEntryName) {
            let suffix = name.dropFirst(Self.searchEntryName.count)
            let destination = searchIndexURL.deletingLastPathComponent()
                .appending(component: searchIndexURL.lastPathComponent + suffix)
            try FileManager.default.createDirectoryIfNeeded(at: destination.deletingLastPathComponent())
            try Self.replaceItem(at: destination, with: source)
        }
        
        // Small enough to read whole, unlike the databases above.
        if let url = entryURLs[Self.preferencesEntryName],
           let data = try? Data(contentsOf: url),
           let preferences = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in preferences where !Self.excludedPreferenceKeys.contains(key) {
                userDefaults?.set(value, forKey: key)
            }
        }
    }
    
    // MARK: - Private
    
    /// Moves rather than copies: the source is a decrypted staging file that is being
    /// consumed, and copying a database twice over is a pointless second write.
    private static func replaceItem(at destination: URL, with source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
    
    private func searchIndexSiblings() -> [URL] {
        let directory = searchIndexURL.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(searchIndexURL.lastPathComponent) }
    }
    
    /// Only property-list types survive a round trip through JSON and UserDefaults,
    /// so anything else is dropped rather than corrupting the file.
    private func exportedPreferences() -> [String: Any] {
        guard let userDefaults else { return [:] }
        
        return userDefaults.dictionaryRepresentation().filter { key, value in
            guard !Self.excludedPreferenceKeys.contains(key) else { return false }
            return JSONSerialization.isValidJSONObject([value])
        }
    }
}

/// Identifies who the backup belongs to, so a restore can refuse a package from
/// another account rather than merging two people's history.
nonisolated struct BackupMetadata: Codable, Equatable, Sendable {
    let userID: String
    let createdAt: Date
}
