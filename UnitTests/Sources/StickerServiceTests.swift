//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
@testable import ElementX
import Testing
import UIKit

@MainActor
struct StickerServiceTests {
    var clientProxy: ClientProxyMock!
    var timelineController: TimelineControllerMock!
    var userDefaults: UserDefaults!
    var service: StickerService!
    
    @Test
    mutating func loadsBuiltInStickersFromManifest() throws {
        try setup()
        
        #expect(service.builtInStickers.count == 2)
        
        let sticker = try #require(service.builtInStickers.first)
        #expect(sticker.id == "one")
        #expect(sticker.body == "Sticker one")
        #expect(sticker.width == 2)
        #expect(sticker.height == 2)
        #expect(sticker.mimeType == "image/png")
    }
    
    @Test
    mutating func loadsUserStickersFromAccountData() async throws {
        try setup()
        clientProxy.accountDataEventTypeReturnValue = .success("""
        {
            "pack": { "display_name": "My pack" },
            "images": {
                "party": { "url": "mxc://example.com/party", "body": "Party", "usage": ["sticker"] },
                "emote_only": { "url": "mxc://example.com/emote", "usage": ["emoticon"] },
                "no_usage": { "url": "mxc://example.com/any" }
            }
        }
        """)
        
        let collection = await service.loadStickers()
        
        #expect(collection.builtInStickers.count == 2)
        #expect(collection.userStickers.map(\.id) == ["no_usage", "party"])
        #expect(collection.userStickers.last?.source == .media(url: "mxc://example.com/party"))
    }
    
    @Test
    mutating func sendingBuiltInStickerUploadsOnceAndCachesTheURI() async throws {
        try setup()
        let sticker = try #require(service.builtInStickers.first)
        
        _ = await service.send(sticker, in: timelineController)
        _ = await service.send(sticker, in: timelineController)
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        #expect(timelineController.sendStickerBodyUrlImageInfoCallsCount == 2)
        
        let arguments = try #require(timelineController.sendStickerBodyUrlImageInfoReceivedArguments)
        #expect(arguments.body == "Sticker one")
        #expect(arguments.url == "mxc://example.com/abc123")
        #expect(arguments.imageInfo.mimetype == "image/png")
    }
    
    @Test
    mutating func sendingUserStickerDoesNotUpload() async throws {
        try setup()
        let sticker = Sticker(id: "party",
                              body: "Party",
                              source: .media(url: "mxc://example.com/party"),
                              width: 512,
                              height: 512,
                              fileSize: 1000,
                              mimeType: "image/png")
        
        let result = await service.send(sticker, in: timelineController)
        
        guard case .success = result else {
            Issue.record("Sending should succeed")
            return
        }
        #expect(!clientProxy.uploadMediaCalled)
        #expect(timelineController.sendStickerBodyUrlImageInfoReceivedArguments?.url == "mxc://example.com/party")
    }
    
    @Test
    mutating func uploadFailureIsSurfacedAndNothingIsSent() async throws {
        try setup()
        clientProxy.uploadMediaReturnValue = .failure(.invalidMedia)
        let sticker = try #require(service.builtInStickers.first)
        
        let result = await service.send(sticker, in: timelineController)
        
        guard case .failure(.uploadFailed) = result else {
            Issue.record("Sending should fail with an upload error")
            return
        }
        #expect(!timelineController.sendStickerBodyUrlImageInfoCalled)
        
        // A subsequent send shouldn't use a cached URI from the failed attempt.
        clientProxy.uploadMediaReturnValue = .success("mxc://example.com/abc123")
        _ = await service.send(sticker, in: timelineController)
        #expect(clientProxy.uploadMediaCallsCount == 2)
    }
    
    @Test
    mutating func addingStickersUploadsAllAndSavesThePackOnce() async throws {
        try setup()
        let catURL = try makeTestImageFile(named: "Fancy Cat", color: .red)
        let dogURL = try makeTestImageFile(named: "Happy Dog", color: .blue)
        
        let summary = await service.addUserStickers(fromMediaAt: [catURL, dogURL])
        
        #expect(summary == StickerBatchSummary(added: 2, duplicates: 0, failed: 0))
        #expect(clientProxy.uploadMediaCallsCount == 2)
        #expect(clientProxy.setAccountDataEventTypeContentCallsCount == 1)
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        #expect(arguments.eventType == "im.ponies.user_emotes")
        #expect(arguments.content.contains("io.element.sha256"))
        
        let pack = try JSONDecoder().decode(UserStickerPack.self, from: Data(arguments.content.utf8))
        let image = try #require(pack.images["fancy_cat"])
        #expect(image.url == "mxc://example.com/abc123")
        #expect(image.body == "Fancy Cat")
        #expect(image.usage == ["sticker"])
        #expect(image.info?.mimetype != nil)
        #expect(image.sha256?.count == 64)
        #expect(pack.images["happy_dog"]?.sha256 != image.sha256)
    }
    
    @Test
    mutating func duplicateWithinABatchIsSkipped() async throws {
        try setup()
        let firstURL = try makeTestImageFile(named: "First", color: .red)
        let secondURL = try makeTestImageFile(named: "Second", color: .red)
        
        let summary = await service.addUserStickers(fromMediaAt: [firstURL, secondURL])
        
        #expect(summary == StickerBatchSummary(added: 1, duplicates: 1, failed: 0))
        #expect(clientProxy.uploadMediaCallsCount == 1)
    }
    
    @Test
    mutating func duplicateAgainstTheExistingPackIsSkipped() async throws {
        try setup()
        let imageURL = try makeTestImageFile(named: "Fancy Cat", color: .red)
        let hash = try sha256Hex(ofFileAt: imageURL)
        clientProxy.accountDataEventTypeReturnValue = .success("""
        { "images": { "cat": { "url": "mxc://example.com/cat", "io.element.sha256": "\(hash)" } } }
        """)
        
        let summary = await service.addUserStickers(fromMediaAt: [imageURL])
        
        #expect(summary == StickerBatchSummary(added: 0, duplicates: 1, failed: 0))
        #expect(!clientProxy.uploadMediaCalled)
        #expect(!clientProxy.setAccountDataEventTypeContentCalled)
    }
    
    @Test
    mutating func existingEntryWithoutAHashDoesNotMatch() async throws {
        try setup()
        clientProxy.accountDataEventTypeReturnValue = .success("""
        { "images": { "cat": { "url": "mxc://example.com/cat" } } }
        """)
        let imageURL = try makeTestImageFile(named: "Fancy Cat", color: .red)
        
        let summary = await service.addUserStickers(fromMediaAt: [imageURL])
        
        #expect(summary == StickerBatchSummary(added: 1, duplicates: 0, failed: 0))
        #expect(clientProxy.uploadMediaCallsCount == 1)
    }
    
    @Test
    mutating func perFileUploadFailureDoesNotAbortTheBatch() async throws {
        try setup()
        // The mock increments its calls count before invoking the closure.
        let proxy = try #require(clientProxy)
        clientProxy.uploadMediaClosure = { _ in
            proxy.uploadMediaCallsCount == 1 ? .failure(.invalidMedia) : .success("mxc://example.com/abc123")
        }
        let catURL = try makeTestImageFile(named: "Fancy Cat", color: .red)
        let dogURL = try makeTestImageFile(named: "Happy Dog", color: .blue)
        
        let summary = await service.addUserStickers(fromMediaAt: [catURL, dogURL])
        
        #expect(summary == StickerBatchSummary(added: 1, duplicates: 0, failed: 1))
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        let pack = try JSONDecoder().decode(UserStickerPack.self, from: Data(arguments.content.utf8))
        #expect(pack.images.count == 1)
    }
    
    @Test
    mutating func packSaveFailureCountsAllAddedAsFailed() async throws {
        try setup()
        clientProxy.setAccountDataEventTypeContentReturnValue = .failure(.invalidResponse)
        let imageURL = try makeTestImageFile(named: "Fancy Cat", color: .red)
        
        let summary = await service.addUserStickers(fromMediaAt: [imageURL])
        
        #expect(summary == StickerBatchSummary(added: 0, duplicates: 0, failed: 1))
    }
    
    @Test
    mutating func collectingAReceivedStickerAddsItToThePackWithoutUploading() async throws {
        try setup()
        
        let result = await service.collectSticker(body: "Party",
                                                  url: "mxc://example.com/party",
                                                  width: 512,
                                                  height: 512,
                                                  fileSize: 1000,
                                                  mimeType: "image/png")
        
        guard case .success = result else {
            Issue.record("Collecting should succeed")
            return
        }
        
        #expect(!clientProxy.uploadMediaCalled)
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        #expect(arguments.eventType == "im.ponies.user_emotes")
        
        let pack = try JSONDecoder().decode(UserStickerPack.self, from: Data(arguments.content.utf8))
        let image = try #require(pack.images["party"])
        #expect(image.url == "mxc://example.com/party")
        #expect(image.body == "Party")
        #expect(image.info?.w == 512)
        #expect(image.usage == ["sticker"])
    }
    
    @Test
    mutating func collectingAnAlreadyCollectedStickerDoesNotWriteAccountData() async throws {
        try setup()
        clientProxy.accountDataEventTypeReturnValue = .success("""
        { "images": { "party": { "url": "mxc://example.com/party" } } }
        """)
        
        let result = await service.collectSticker(body: "Party again",
                                                  url: "mxc://example.com/party",
                                                  width: nil,
                                                  height: nil,
                                                  fileSize: nil,
                                                  mimeType: nil)
        
        guard case .success = result else {
            Issue.record("Collecting a duplicate should be a no-op success")
            return
        }
        #expect(!clientProxy.setAccountDataEventTypeContentCalled)
    }
    
    @Test
    mutating func removingAStickerUpdatesThePack() async throws {
        try setup()
        clientProxy.accountDataEventTypeReturnValue = .success("""
        { "images": { "party": { "url": "mxc://example.com/party" } } }
        """)
        
        let result = await service.removeUserSticker(id: "party")
        
        guard case .success = result else {
            Issue.record("Removing should succeed")
            return
        }
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        let pack = try JSONDecoder().decode(UserStickerPack.self, from: Data(arguments.content.utf8))
        #expect(pack.images.isEmpty)
    }
    
    @Test
    mutating func removingAnUnknownStickerDoesNotWriteAccountData() async throws {
        try setup()
        
        let result = await service.removeUserSticker(id: "missing")
        
        guard case .success = result else {
            Issue.record("Removing a missing sticker should be a no-op success")
            return
        }
        #expect(!clientProxy.setAccountDataEventTypeContentCalled)
    }
    
    // MARK: - Private
    
    private mutating func setup() throws {
        let bundleDirectory = URL(filePath: NSTemporaryDirectory()).appending(path: "StickerServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        
        let pngData = try #require(makeTestImage().pngData())
        try pngData.write(to: bundleDirectory.appending(path: "sticker_one.png"))
        try pngData.write(to: bundleDirectory.appending(path: "sticker_two.png"))
        
        let manifest = """
        [
            { "id": "one", "body": "Sticker one", "file": "sticker_one.png" },
            { "id": "two", "body": "Sticker two", "file": "sticker_two.png" }
        ]
        """
        try Data(manifest.utf8).write(to: bundleDirectory.appending(path: "sticker_manifest.json"))
        
        clientProxy = ClientProxyMock(.init(userID: "@alice:example.com"))
        clientProxy.uploadMediaReturnValue = .success("mxc://example.com/abc123")
        clientProxy.underlyingMaxMediaUploadSize = .success(100 * 1024 * 1024)
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        clientProxy.setAccountDataEventTypeContentReturnValue = .success(())
        
        timelineController = TimelineControllerMock(.init())
        timelineController.sendStickerBodyUrlImageInfoReturnValue = .success(())
        
        userDefaults = try #require(UserDefaults(suiteName: bundleDirectory.lastPathComponent))
        userDefaults.removePersistentDomain(forName: bundleDirectory.lastPathComponent)
        
        let bundle = try #require(Bundle(path: bundleDirectory.path(percentEncoded: false)))
        service = StickerService(clientProxy: clientProxy,
                                 mediaUploadingPreprocessor: MediaUploadingPreprocessor(appSettings: AppSettings.volatile()),
                                 bundle: bundle,
                                 userDefaults: userDefaults)
    }
    
    private func makeTestImageFile(named name: String, color: UIColor = .red) throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "StickerServiceTests-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "\(name).png")
        try makeTestImage(color: color).pngData()?.write(to: fileURL)
        return fileURL
    }
    
    private func makeTestImage(color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
    
    private func sha256Hex(ofFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
