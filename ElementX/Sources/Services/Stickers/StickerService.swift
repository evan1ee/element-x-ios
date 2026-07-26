//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
import Foundation
import ImageIO
import MatrixRustSDK

/// The last known pack per user, held outside `StickerService` because a session builds one of
/// those per screen — the timeline, the composer's panel, the picker and the discovery screen —
/// and a sticker added on any of them has to be visible to the rest straight away.
///
/// Passed in rather than reached for so that tests get an empty one; `.shared` is what the app
/// itself uses.
final class StickerPackCache {
    static let shared = StickerPackCache()
    
    private var packs: [String: UserStickerPack] = [:]
    
    subscript(userID: String) -> UserStickerPack? {
        get { packs[userID] }
        set { packs[userID] = newValue }
    }
}

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
    private let packCache: StickerPackCache
    
    let builtInStickers: [Sticker]
    
    // v2: builds prior to disabling Xcode's PNG optimisation uploaded broken media.
    private var uploadCacheKey: String {
        "stickerMediaURIs-v2-\(clientProxy.userID)"
    }
    
    init(clientProxy: ClientProxyProtocol,
         mediaUploadingPreprocessor: MediaUploadingPreprocessor,
         bundle: Bundle = Bundle(for: StickerService.self),
         userDefaults: UserDefaults = .standard,
         packCache: StickerPackCache = .shared) {
        self.clientProxy = clientProxy
        self.mediaUploadingPreprocessor = mediaUploadingPreprocessor
        self.userDefaults = userDefaults
        self.packCache = packCache
        builtInStickers = Self.loadBuiltInStickers(from: bundle)
    }
    
    func loadStickers() async -> StickerCollection {
        await StickerCollection(userStickers: loadUserPack().stickers,
                                builtInStickers: builtInStickers)
    }
    
    func send(_ sticker: Sticker,
              in timelineController: StickerSending) async -> Result<Void, StickerServiceError> {
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
    
    func addUserStickers(fromMediaAt urls: [URL]) async -> StickerBatchSummary {
        guard case let .success(maxUploadSize) = await clientProxy.maxMediaUploadSize else {
            return StickerBatchSummary(failed: urls.count)
        }
        
        var summary = StickerBatchSummary()
        var pack = await loadUserPack()
        var knownHashes = Set(pack.images.values.compactMap(\.sha256))
        
        for url in urls {
            guard let data = try? Data(contentsOf: url) else {
                summary.failed += 1
                continue
            }
            
            let hash = Self.sha256Hex(data)
            
            guard !knownHashes.contains(hash) else {
                summary.duplicates += 1
                continue
            }
            
            guard case let .success((mediaURI, imageInfo)) = await uploadSticker(at: url, maxUploadSize: maxUploadSize) else {
                summary.failed += 1
                continue
            }
            
            let body = url.deletingPathExtension().lastPathComponent
            pack.images[uniqueShortcode(for: body, in: pack)] = .init(url: mediaURI,
                                                                      body: body,
                                                                      info: .init(w: imageInfo.width,
                                                                                  h: imageInfo.height,
                                                                                  size: imageInfo.size,
                                                                                  mimetype: imageInfo.mimetype),
                                                                      usage: [UserStickerPack.stickerUsage],
                                                                      sha256: hash,
                                                                      addedAt: UserStickerPack.Image.currentTimestamp)
            knownHashes.insert(hash)
            summary.added += 1
        }
        
        if summary.added > 0, case .failure = await save(pack) {
            summary.failed += summary.added
            summary.added = 0
        }
        
        return summary
    }
    
    func sendExternalSticker(imageData: Data,
                             body: String,
                             width: UInt64,
                             height: UInt64,
                             mimeType: String,
                             in timelineController: StickerSending) async -> Result<Void, StickerServiceError> {
        switch await uploadRawImage(data: imageData, mimeType: mimeType, width: width, height: height) {
        case .failure(let error):
            return .failure(error)
        case .success(let (mediaURI, imageInfo)):
            switch await timelineController.sendSticker(body: body, url: mediaURI, imageInfo: imageInfo) {
            case .success:
                return .success(())
            case .failure(let error):
                MXLog.error("Failed sending external sticker with error: \(error)")
                return .failure(.sendFailed)
            }
        }
    }
    
    func sendImage(data: Data,
                   filename: String,
                   in timelineController: StickerSending) async -> Result<Void, StickerServiceError> {
        guard case let .success(maxUploadSize) = await clientProxy.maxMediaUploadSize else {
            return .failure(.uploadFailed)
        }
        
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "media-send-\(UUID().uuidString)")
        let fileURL = directory.appending(path: filename)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              (try? data.write(to: fileURL)) != nil else {
            return .failure(.processingFailed)
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        
        // The preprocessor leaves GIFs alone (it only re-encodes still images), so animation
        // survives and the thumbnail and image info come out the same as for a picked attachment.
        guard case let .success(mediaInfo) = await mediaUploadingPreprocessor.processMedia(at: fileURL, maxUploadSize: maxUploadSize),
              case let .image(imageURL, thumbnailURL, imageInfo) = mediaInfo else {
            MXLog.error("Failed processing \(filename) for sending.")
            return .failure(.processingFailed)
        }
        
        // Nothing here holds on to the join handle: cancelling and retrying a GIF is the
        // timeline's job now, the same as for any other attachment. Bound to a local first
        // because a trailing closure in a `switch` subject reads as the statement's own body.
        let result = await timelineController.sendImage(url: imageURL,
                                                        thumbnailURL: thumbnailURL,
                                                        imageInfo: imageInfo,
                                                        caption: nil) { _ in }
        
        switch result {
        case .success:
            return .success(())
        case .failure(let error):
            MXLog.error("Failed sending image with error: \(error)")
            return .failure(.sendFailed)
        }
    }
    
    func addExternalSticker(imageData: Data,
                            body: String,
                            width: UInt64,
                            height: UInt64,
                            mimeType: String) async -> StickerBatchSummary {
        let hash = Self.sha256Hex(imageData)
        var pack = await loadUserPack()
        
        guard !pack.images.values.contains(where: { $0.sha256 == hash }) else {
            return StickerBatchSummary(duplicates: 1)
        }
        
        switch await uploadRawImage(data: imageData, mimeType: mimeType, width: width, height: height) {
        case .failure:
            return StickerBatchSummary(failed: 1)
        case .success(let (mediaURI, imageInfo)):
            pack.images[uniqueShortcode(for: body, in: pack)] = .init(url: mediaURI,
                                                                      body: body,
                                                                      info: .init(w: imageInfo.width,
                                                                                  h: imageInfo.height,
                                                                                  size: imageInfo.size,
                                                                                  mimetype: imageInfo.mimetype),
                                                                      usage: [UserStickerPack.stickerUsage],
                                                                      sha256: hash,
                                                                      addedAt: UserStickerPack.Image.currentTimestamp)
            
            if case .failure = await save(pack) {
                return StickerBatchSummary(failed: 1)
            }
            return StickerBatchSummary(added: 1)
        }
    }
    
    /// Writes the bytes to a temporary file and uploads them without re-encoding so animation is preserved.
    private func uploadRawImage(data: Data,
                                mimeType: String,
                                width: UInt64,
                                height: UInt64) async -> Result<(String, ImageInfo), StickerServiceError> {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "sticker-external-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return .failure(.processingFailed)
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        
        let fileURL = directory.appending(path: "sticker.\(Self.fileExtension(for: mimeType))")
        guard (try? data.write(to: fileURL)) != nil else {
            return .failure(.processingFailed)
        }
        
        let imageInfo = ImageInfo(height: height,
                                  width: width,
                                  mimetype: mimeType,
                                  size: UInt64(data.count),
                                  thumbnailInfo: nil,
                                  thumbnailSource: nil,
                                  blurhash: nil,
                                  isAnimated: true)
        
        guard case let .success(mediaURI) = await clientProxy.uploadMedia(.image(imageURL: fileURL,
                                                                                 thumbnailURL: fileURL,
                                                                                 imageInfo: imageInfo)) else {
            return .failure(.uploadFailed)
        }
        
        return .success((mediaURI, imageInfo))
    }
    
    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/webp": "webp"
        case "image/gif": "gif"
        case "image/png": "png"
        case "image/jpeg": "jpg"
        default: "img"
        }
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    private func uploadSticker(at url: URL, maxUploadSize: UInt) async -> Result<(String, ImageInfo), StickerServiceError> {
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
        
        return .success((mediaURI, imageInfo))
    }
    
    func collectSticker(body: String,
                        url: String,
                        width: UInt64?,
                        height: UInt64?,
                        fileSize: UInt64?,
                        mimeType: String?) async -> Result<Void, StickerServiceError> {
        var pack = await loadUserPack()
        
        guard !pack.images.values.contains(where: { $0.url == url }) else {
            return .success(())
        }
        
        let shortcode = uniqueShortcode(for: body, in: pack)
        pack.images[shortcode] = .init(url: url,
                                       body: body,
                                       info: .init(w: width, h: height, size: fileSize, mimetype: mimeType),
                                       usage: [UserStickerPack.stickerUsage],
                                       addedAt: UserStickerPack.Image.currentTimestamp)
        
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
    
    /// The last pack we loaded or saved. Account data reads lag writes (the change
    /// only lands locally once it syncs back), so within a session we trust this
    /// rather than re-reading a stale value straight after a mutation.
    ///
    /// Held in `StickerPackCache` rather than here so that every screen's service agrees on it.
    private var cachedPack: UserStickerPack? {
        get { packCache[clientProxy.userID] }
        set { packCache[clientProxy.userID] = newValue }
    }
    
    private func loadUserPack() async -> UserStickerPack {
        if let cachedPack {
            return cachedPack
        }
        
        guard case let .success(content) = await clientProxy.accountData(eventType: UserStickerPack.eventType),
              let content,
              let pack = try? JSONDecoder().decode(UserStickerPack.self, from: Data(content.utf8)) else {
            let pack = UserStickerPack()
            cachedPack = pack
            return pack
        }
        
        cachedPack = pack
        return pack
    }
    
    private func save(_ pack: UserStickerPack) async -> Result<Void, StickerServiceError> {
        guard let content = try? String(data: JSONEncoder().encode(pack), encoding: .utf8) else {
            return .failure(.packUpdateFailed)
        }
        
        switch await clientProxy.setAccountData(eventType: UserStickerPack.eventType, content: content) {
        case .success:
            cachedPack = pack
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
