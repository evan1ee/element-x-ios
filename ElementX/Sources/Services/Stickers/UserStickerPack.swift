//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The user's own image pack, stored in the `im.ponies.user_emotes` global
/// account data event as described by
/// [MSC2545](https://github.com/matrix-org/matrix-spec-proposals/pull/2545).
struct UserStickerPack: Codable, Equatable {
    static let eventType = "im.ponies.user_emotes"
    static let stickerUsage = "sticker"
    
    struct Image: Codable, Equatable {
        struct Info: Codable, Equatable {
            var w: UInt64?
            var h: UInt64?
            var size: UInt64?
            var mimetype: String?
        }
        
        var url: String
        var body: String?
        var info: Info?
        var usage: [String]?
        /// SHA-256 of the originally uploaded file, used to avoid duplicate uploads.
        var sha256: String?
        /// When the sticker was added, in milliseconds since the epoch, so the picker can show the
        /// most recent first. The pack is a dictionary and MSC2545 defines no ordering, so without
        /// this there's nothing to sort on. Absent on entries added before it was recorded, and on
        /// packs written by other clients.
        var addedAt: UInt64?
        
        enum CodingKeys: String, CodingKey {
            case url, body, info, usage
            case sha256 = "user.sticker.sha256"
            case addedAt = "user.sticker.added_at"
        }
        
        /// Where these two fields lived before they moved out of Element's namespace, which
        /// isn't ours to write in. Read so an existing pack keeps its dedup and its ordering;
        /// never written, so the first save after this drops them from the account data.
        enum LegacyCodingKeys: String, CodingKey {
            case sha256 = "io.element.sha256"
            case addedAt = "io.element.added_at"
        }
        
        /// The value to stamp on a sticker being added right now.
        static var currentTimestamp: UInt64 {
            UInt64(Date().timeIntervalSince1970 * 1000)
        }
        
        var isUsableAsSticker: Bool {
            guard let usage, !usage.isEmpty else { return true }
            return usage.contains(UserStickerPack.stickerUsage)
        }
    }
    
    struct Pack: Codable, Equatable {
        var displayName: String?
        var usage: [String]?
        
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case usage
        }
    }
    
    var pack: Pack?
    var images: [String: Image]
    
    init(pack: Pack? = nil, images: [String: Image] = [:]) {
        self.pack = pack
        self.images = images
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pack = try container.decodeIfPresent(Pack.self, forKey: .pack)
        images = try container.decodeIfPresent([String: Image].self, forKey: .images) ?? [:]
    }
    
    /// The pack's stickers, most recently added first.
    var stickers: [Sticker] {
        images
            .filter(\.value.isUsableAsSticker)
            .sorted { lhs, rhs in
                switch (lhs.value.addedAt, rhs.value.addedAt) {
                case let (lhsAddedAt?, rhsAddedAt?):
                    lhsAddedAt > rhsAddedAt
                case (.some, nil):
                    // Anything undated predates the first sticker that recorded a timestamp.
                    true
                case (nil, .some):
                    false
                case (nil, nil):
                    lhs.key < rhs.key
                }
            }
            .map { shortcode, image in
                Sticker(id: shortcode,
                        body: image.body ?? shortcode,
                        source: .media(url: image.url),
                        width: image.info?.w,
                        height: image.info?.h,
                        fileSize: image.info?.size,
                        mimeType: image.info?.mimetype)
            }
            .sorted { $0.id < $1.id }
    }
}

extension UserStickerPack.Image {
    /// Reads the two custom fields from their current keys, falling back to the ones they used
    /// while they lived in Element's namespace. Encoding stays synthesised, so a pack read in the
    /// old format is written back in the new one — account data is replaced wholesale, which
    /// means the first save after this drops the old keys for good.
    ///
    /// Declared in an extension so the memberwise initialiser survives.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        
        url = try container.decode(String.self, forKey: .url)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        info = try container.decodeIfPresent(Info.self, forKey: .info)
        usage = try container.decodeIfPresent([String].self, forKey: .usage)
        
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .sha256)
        addedAt = try container.decodeIfPresent(UInt64.self, forKey: .addedAt)
            ?? legacyContainer.decodeIfPresent(UInt64.self, forKey: .addedAt)
    }
}
