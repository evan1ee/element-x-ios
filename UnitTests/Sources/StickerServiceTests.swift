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
    var roomProxy: JoinedRoomProxyMock!
    var userDefaults: UserDefaults!
    var service: StickerService!
    
    @Test
    mutating func loadsStickersFromManifest() throws {
        try setup()
        
        #expect(service.stickers.count == 2)
        
        let sticker = try #require(service.stickers.first)
        #expect(sticker.id == "one")
        #expect(sticker.body == "Sticker one")
        #expect(sticker.width == 2)
        #expect(sticker.height == 2)
        #expect(sticker.fileSize > 0)
    }
    
    @Test
    mutating func sendBuildsExpectedContent() async throws {
        try setup()
        let sticker = try #require(service.stickers.first)
        
        let result = await service.send(sticker, in: roomProxy, threadRootEventID: nil)
        
        guard case .success = result else {
            Issue.record("Sending should succeed")
            return
        }
        
        let arguments = try #require(roomProxy.sendRawEventTypeContentReceivedArguments)
        #expect(arguments.eventType == "m.sticker")
        
        let content = try #require(try JSONSerialization.jsonObject(with: Data(arguments.content.utf8)) as? [String: Any])
        #expect(content["body"] as? String == "Sticker one")
        #expect(content["url"] as? String == "mxc://example.com/abc123")
        #expect(content["m.relates_to"] == nil)
        
        let info = try #require(content["info"] as? [String: Any])
        #expect(info["w"] as? UInt64 == 2)
        #expect(info["h"] as? UInt64 == 2)
        #expect(info["mimetype"] as? String == "image/png")
    }
    
    @Test
    mutating func sendInThreadIncludesRelation() async throws {
        try setup()
        let sticker = try #require(service.stickers.first)
        
        _ = await service.send(sticker, in: roomProxy, threadRootEventID: "$thread-root")
        
        let arguments = try #require(roomProxy.sendRawEventTypeContentReceivedArguments)
        let content = try #require(try JSONSerialization.jsonObject(with: Data(arguments.content.utf8)) as? [String: Any])
        let relation = try #require(content["m.relates_to"] as? [String: Any])
        #expect(relation["rel_type"] as? String == "m.thread")
        #expect(relation["event_id"] as? String == "$thread-root")
    }
    
    @Test
    mutating func sendUploadsOnceAndCachesTheURI() async throws {
        try setup()
        let sticker = try #require(service.stickers.first)
        
        _ = await service.send(sticker, in: roomProxy, threadRootEventID: nil)
        _ = await service.send(sticker, in: roomProxy, threadRootEventID: nil)
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        #expect(roomProxy.sendRawEventTypeContentCallsCount == 2)
    }
    
    @Test
    mutating func uploadFailureIsSurfacedAndNothingIsSent() async throws {
        try setup()
        clientProxy.uploadMediaReturnValue = .failure(.invalidMedia)
        let sticker = try #require(service.stickers.first)
        
        let result = await service.send(sticker, in: roomProxy, threadRootEventID: nil)
        
        guard case .failure(.uploadFailed) = result else {
            Issue.record("Sending should fail with an upload error")
            return
        }
        #expect(!roomProxy.sendRawEventTypeContentCalled)
        
        // A subsequent send shouldn't use a cached URI from the failed attempt.
        clientProxy.uploadMediaReturnValue = .success("mxc://example.com/abc123")
        _ = await service.send(sticker, in: roomProxy, threadRootEventID: nil)
        #expect(clientProxy.uploadMediaCallsCount == 2)
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
        
        roomProxy = JoinedRoomProxyMock(.init())
        
        userDefaults = try #require(UserDefaults(suiteName: bundleDirectory.lastPathComponent))
        userDefaults.removePersistentDomain(forName: bundleDirectory.lastPathComponent)
        
        let bundle = try #require(Bundle(path: bundleDirectory.path(percentEncoded: false)))
        service = StickerService(clientProxy: clientProxy, bundle: bundle, userDefaults: userDefaults)
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
