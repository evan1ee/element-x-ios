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
    
    var stickers: [Sticker] {
        images
            .filter(\.value.isUsableAsSticker)
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
