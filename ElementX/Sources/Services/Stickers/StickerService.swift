//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import ImageIO
import MatrixRustSDK

/// Sends stickers and manages the user's own MSC2545 sticker pack.
///
/// Bundled stickers are uploaded to the homeserver the first time they're sent
/// and the resulting `mxc://` URI is reused for subsequent sends. User stickers
/// live in the `im.ponies.user_emotes` account data and are uploaded when added.
class StickerService: StickerServiceProtocol {
    private static let bundledMimeType = "image/png"
    
    private let clientProxy: ClientProxyProtocol
    private let mediaUploadingPreprocessor: MediaUploadingPreprocessor
    private let userDefaults: UserDefaults
    
    let builtInStickers: [Sticker]
    
    private var uploadCacheKey: String {
        "stickerMediaURIs-\(clientProxy.userID)"
    }
    
    init(clientProxy: ClientProxyProtocol,
         mediaUploadingPreprocessor: MediaUploadingPreprocessor,
         bundle: Bundle = Bundle(for: StickerService.self),
         userDefaults: UserDefaults = .standard) {
        self.clientProxy = clientProxy
        self.mediaUploadingPreprocessor = mediaUploadingPreprocessor
        self.userDefaults = userDefaults
        builtInStickers = Self.loadBuiltInStickers(from: bundle)
    }
    
    func loadStickers() async -> StickerCollection {
        await StickerCollection(userStickers: loadUserPack().stickers,
                                builtInStickers: builtInStickers)
    }
    
    func send(_ sticker: Sticker,
              in timelineController: TimelineControllerProtocol) async -> Result<Void, StickerServiceError> {
        let mediaURI: String
        switch sticker.source {
        case .media(let url):
            mediaURI = url
        case .bundle(let fileURL):
            switch await resolveBundledMediaURI(for: sticker, fileURL: fileURL) {
            case .success(let uri):
                mediaURI = uri
            case .failure(let error):
                return .failure(error)
            }
        }
        
        let imageInfo = ImageInfo(height: sticker.height,
                                  width: sticker.width,
                                  mimetype: sticker.mimeType,
                                  size: sticker.fileSize,
                                  thumbnailInfo: nil,
                                  thumbnailSource: nil,
                                  blurhash: nil,
                                  isAnimated: false)
        
        switch await timelineController.sendSticker(body: sticker.body, url: mediaURI, imageInfo: imageInfo) {
        case .success:
            return .success(())
        case .failure(let error):
            MXLog.error("Failed sending sticker \(sticker.id) with error: \(error)")
            return .failure(.sendFailed)
        }
    }
    
    func addUserSticker(fromMediaAt url: URL) async -> Result<Void, StickerServiceError> {
        guard case let .success(maxUploadSize) = await clientProxy.maxMediaUploadSize else {
            return .failure(.processingFailed)
        }
        
        guard case let .success(mediaInfo) = await mediaUploadingPreprocessor.processMedia(at: url, maxUploadSize: maxUploadSize),
              case let .image(imageURL, _, imageInfo) = mediaInfo else {
            MXLog.error("Failed processing the image to add as a sticker.")
            return .failure(.processingFailed)
        }
        
        guard case let .success(mediaURI) = await clientProxy.uploadMedia(.image(imageURL: imageURL,
                                                                                 thumbnailURL: imageURL,
                                                                                 imageInfo: imageInfo)) else {
            return .failure(.uploadFailed)
        }
        
        var pack = await loadUserPack()
        
        let body = url.deletingPathExtension().lastPathComponent
        let shortcode = uniqueShortcode(for: body, in: pack)
        pack.images[shortcode] = .init(url: mediaURI,
                                       body: body,
                                       info: .init(w: imageInfo.width,
                                                   h: imageInfo.height,
                                                   size: imageInfo.size,
                                                   mimetype: imageInfo.mimetype),
                                       usage: [UserStickerPack.stickerUsage])
        
        return await save(pack)
    }
    
    func removeUserSticker(id: String) async -> Result<Void, StickerServiceError> {
        var pack = await loadUserPack()
        
        guard pack.images.removeValue(forKey: id) != nil else {
            return .success(())
        }
        
        return await save(pack)
    }
    
    // MARK: - User pack
    
    private func loadUserPack() async -> UserStickerPack {
        guard case let .success(content) = await clientProxy.accountData(eventType: UserStickerPack.eventType),
              let content,
              let pack = try? JSONDecoder().decode(UserStickerPack.self, from: Data(content.utf8)) else {
            return UserStickerPack()
        }
        return pack
    }
    
    private func save(_ pack: UserStickerPack) async -> Result<Void, StickerServiceError> {
        guard let content = try? String(data: JSONEncoder().encode(pack), encoding: .utf8) else {
            return .failure(.packUpdateFailed)
        }
        
        switch await clientProxy.setAccountData(eventType: UserStickerPack.eventType, content: content) {
        case .success:
            return .success(())
        case .failure(let error):
            MXLog.error("Failed updating the user sticker pack with error: \(error)")
            return .failure(.packUpdateFailed)
        }
    }
    
    private func uniqueShortcode(for body: String, in pack: UserStickerPack) -> String {
        let base = body.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let shortcode = base.isEmpty ? "sticker" : base
        
        guard pack.images[shortcode] != nil else {
            return shortcode
        }
        
        return "\(shortcode)_\(UUID().uuidString.prefix(8).lowercased())"
    }
    
    // MARK: - Bundled stickers
    
    private func resolveBundledMediaURI(for sticker: Sticker, fileURL: URL) async -> Result<String, StickerServiceError> {
        var cachedURIs = userDefaults.dictionary(forKey: uploadCacheKey) as? [String: String] ?? [:]
        
        if let cachedURI = cachedURIs[sticker.id] {
            return .success(cachedURI)
        }
        
        let imageInfo = ImageInfo(height: sticker.height,
                                  width: sticker.width,
                                  mimetype: sticker.mimeType,
                                  size: sticker.fileSize,
                                  thumbnailInfo: nil,
                                  thumbnailSource: nil,
                                  blurhash: nil,
                                  isAnimated: false)
        
        switch await clientProxy.uploadMedia(.image(imageURL: fileURL, thumbnailURL: fileURL, imageInfo: imageInfo)) {
        case .success(let mediaURI):
            cachedURIs[sticker.id] = mediaURI
            userDefaults.set(cachedURIs, forKey: uploadCacheKey)
            return .success(mediaURI)
        case .failure(let error):
            MXLog.error("Failed uploading sticker \(sticker.id) with error: \(error)")
            return .failure(.uploadFailed)
        }
    }
    
    private static func loadBuiltInStickers(from bundle: Bundle) -> [Sticker] {
        guard let manifestURL = bundle.url(forResource: "sticker_manifest", withExtension: "json"),
              let manifestData = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: manifestData) else {
            MXLog.error("Failed loading the sticker manifest.")
            return []
        }
        
        return entries.compactMap { entry -> Sticker? in
            let filename = entry.file as NSString
            guard let fileURL = bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension),
                  let properties = imageProperties(of: fileURL),
                  let width = properties[kCGImagePropertyPixelWidth] as? UInt64,
                  let height = properties[kCGImagePropertyPixelHeight] as? UInt64,
                  let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                MXLog.error("Failed loading bundled sticker: \(entry.id)")
                return nil
            }
            
            return Sticker(id: entry.id,
                           body: entry.body,
                           source: .bundle(fileURL),
                           width: width,
                           height: height,
                           fileSize: UInt64(fileSize),
                           mimeType: Self.bundledMimeType)
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
