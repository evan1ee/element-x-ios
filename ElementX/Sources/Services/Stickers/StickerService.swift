//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import ImageIO
import MatrixRustSDK

/// Sends stickers from the pack of images bundled with the app.
///
/// Stickers are uploaded to the homeserver the first time they're sent and the
/// resulting `mxc://` URI is reused for subsequent sends.
class StickerService: StickerServiceProtocol {
    private static let mimeType = "image/png"
    
    private let clientProxy: ClientProxyProtocol
    private let userDefaults: UserDefaults
    
    let stickers: [BuiltInSticker]
    
    private var cacheKey: String {
        "stickerMediaURIs-\(clientProxy.userID)"
    }
    
    init(clientProxy: ClientProxyProtocol,
         bundle: Bundle = Bundle(for: StickerService.self),
         userDefaults: UserDefaults = .standard) {
        self.clientProxy = clientProxy
        self.userDefaults = userDefaults
        stickers = Self.loadStickers(from: bundle)
    }
    
    func send(_ sticker: BuiltInSticker,
              in roomProxy: JoinedRoomProxyProtocol,
              threadRootEventID: String?) async -> Result<Void, StickerServiceError> {
        let mediaURI: String
        switch await resolveMediaURI(for: sticker) {
        case .success(let uri):
            mediaURI = uri
        case .failure(let error):
            return .failure(error)
        }
        
        let content = StickerContent(body: sticker.body,
                                     url: mediaURI,
                                     info: .init(w: sticker.width,
                                                 h: sticker.height,
                                                 size: sticker.fileSize,
                                                 mimetype: Self.mimeType),
                                     relatesTo: threadRootEventID.map { .init(relType: "m.thread", eventID: $0) })
        
        guard let json = try? String(data: JSONEncoder().encode(content), encoding: .utf8) else {
            return .failure(.encodingFailure)
        }
        
        switch await roomProxy.sendRaw(eventType: "m.sticker", content: json) {
        case .success:
            return .success(())
        case .failure(let error):
            MXLog.error("Failed sending sticker \(sticker.id) with error: \(error)")
            return .failure(.sendFailed)
        }
    }
    
    // MARK: - Private
    
    private func resolveMediaURI(for sticker: BuiltInSticker) async -> Result<String, StickerServiceError> {
        var cachedURIs = userDefaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        
        if let cachedURI = cachedURIs[sticker.id] {
            return .success(cachedURI)
        }
        
        let imageInfo = ImageInfo(height: sticker.height,
                                  width: sticker.width,
                                  mimetype: Self.mimeType,
                                  size: sticker.fileSize,
                                  thumbnailInfo: nil,
                                  thumbnailSource: nil,
                                  blurhash: nil,
                                  isAnimated: false)
        
        switch await clientProxy.uploadMedia(.image(imageURL: sticker.fileURL, thumbnailURL: sticker.fileURL, imageInfo: imageInfo)) {
        case .success(let mediaURI):
            cachedURIs[sticker.id] = mediaURI
            userDefaults.set(cachedURIs, forKey: cacheKey)
            return .success(mediaURI)
        case .failure(let error):
            MXLog.error("Failed uploading sticker \(sticker.id) with error: \(error)")
            return .failure(.uploadFailed)
        }
    }
    
    private static func loadStickers(from bundle: Bundle) -> [BuiltInSticker] {
        guard let manifestURL = bundle.url(forResource: "sticker_manifest", withExtension: "json"),
              let manifestData = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: manifestData) else {
            MXLog.error("Failed loading the sticker manifest.")
            return []
        }
        
        return entries.compactMap { entry -> BuiltInSticker? in
            let filename = entry.file as NSString
            guard let fileURL = bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension),
                  let properties = imageProperties(of: fileURL),
                  let width = properties[kCGImagePropertyPixelWidth] as? UInt64,
                  let height = properties[kCGImagePropertyPixelHeight] as? UInt64,
                  let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                MXLog.error("Failed loading bundled sticker: \(entry.id)")
                return nil
            }
            
            return BuiltInSticker(id: entry.id,
                                  body: entry.body,
                                  fileURL: fileURL,
                                  width: width,
                                  height: height,
                                  fileSize: UInt64(fileSize))
        }
    }
    
    private static func imageProperties(of url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }
}

private struct ManifestEntry: Decodable {
    let id: String
    let body: String
    let file: String
}

/// https://spec.matrix.org/latest/client-server-api/#msticker
private struct StickerContent: Encodable {
    struct Info: Encodable {
        let w: UInt64
        let h: UInt64
        let size: UInt64
        let mimetype: String
    }
    
    struct Relation: Encodable {
        let relType: String
        let eventID: String
        
        enum CodingKeys: String, CodingKey {
            case relType = "rel_type"
            case eventID = "event_id"
        }
    }
    
    let body: String
    let url: String
    let info: Info
    let relatesTo: Relation?
    
    enum CodingKeys: String, CodingKey {
        case body
        case url
        case info
        case relatesTo = "m.relates_to"
    }
}
