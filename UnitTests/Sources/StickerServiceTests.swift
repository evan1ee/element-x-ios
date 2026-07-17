//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

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
    mutating func addingAStickerUploadsAndUpdatesThePack() async throws {
        try setup()
        let imageURL = try makeTestImageFile(named: "Fancy Cat")
        
        let result = await service.addUserSticker(fromMediaAt: imageURL)
        
        guard case .success = result else {
            Issue.record("Adding should succeed")
            return
        }
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        
        let arguments = try #require(clientProxy.setAccountDataEventTypeContentReceivedArguments)
        #expect(arguments.eventType == "im.ponies.user_emotes")
        
        let pack = try JSONDecoder().decode(UserStickerPack.self, from: Data(arguments.content.utf8))
        let image = try #require(pack.images["fancy_cat"])
        #expect(image.url == "mxc://example.com/abc123")
        #expect(image.body == "Fancy Cat")
        #expect(image.usage == ["sticker"])
        #expect(image.info?.mimetype != nil)
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
    
    private func makeTestImageFile(named name: String) throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "StickerServiceTests-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "\(name).png")
        try makeTestImage().pngData()?.write(to: fileURL)
        return fileURL
    }
    
    private func makeTestImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}
