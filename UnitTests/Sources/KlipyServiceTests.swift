//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Synchronization
import Testing

struct KlipyServiceTests {
    init() {
        KlipyMockURLProtocol.reset()
    }
    
    @Test
    func searchDecodesStickersAndSkipsUnusableEntries() async throws {
        let service = makeService()
        
        let result = await service.search(query: "cat", page: 1)
        
        let results = try result.get()
        // Entries without a GIF variant (webp-only, empty) are dropped.
        #expect(results.stickers.count == 1)
        
        let sticker = try #require(results.stickers.first)
        #expect(sticker.id == "happy-cat")
        #expect(sticker.title == "Happy Cat")
        #expect(sticker.fileURL.absoluteString == "https://static.klipy.com/cat-md.gif")
        #expect(sticker.mimeType == "image/gif")
        #expect(sticker.width == 115)
        #expect(sticker.height == 115)
        #expect(sticker.previewURL.absoluteString == "https://static.klipy.com/cat-sm.gif")
        #expect(results.hasNextPage == true)
        #expect(results.nextPage == 2)
    }
    
    @Test
    func emptyQueryHitsTheTrendingEndpoint() async throws {
        let service = makeService()
        
        _ = await service.search(query: "  ", page: 1)
        
        let url = try #require(KlipyMockURLProtocol.lastRequestURL)
        #expect(url.path().contains("/stickers/trending"))
        let query = url.query() ?? ""
        #expect(query.contains("customer_id=@alice:example.com") || query.contains("customer_id=%40alice"))
        #expect(query.contains("page=1"))
        #expect(query.contains("per_page="))
        #expect(query.contains("locale="))
        #expect(query.contains("content_filter="))
        #expect(!query.contains("q="))
    }
    
    @Test
    func nonEmptyQueryHitsTheSearchEndpoint() async throws {
        let service = makeService()
        
        _ = await service.search(query: "dog", page: 3)
        
        let url = try #require(KlipyMockURLProtocol.lastRequestURL)
        #expect(url.path().contains("/stickers/search"))
        #expect((url.query() ?? "").contains("q=dog"))
        #expect((url.query() ?? "").contains("page=3"))
    }
    
    @Test
    func theAPIKeyIsPartOfThePath() async throws {
        let service = makeService()
        
        _ = await service.search(query: "cat", page: 1)
        
        let url = try #require(KlipyMockURLProtocol.lastRequestURL)
        #expect(url.path().contains("/api/v1/testkey/stickers/"))
    }
    
    @Test
    func anEmptyAPIKeyFailsWithoutARequest() async {
        let service = makeService(apiKey: "   ")
        
        let result = await service.search(query: "cat", page: 1)
        
        guard case .failure(.invalidAPIKey) = result else {
            Issue.record("An empty API key should fail with .invalidAPIKey")
            return
        }
        #expect(KlipyMockURLProtocol.lastRequestURL == nil)
    }
    
    @Test
    func aServerErrorIsSurfacedAsRequestFailed() async {
        KlipyMockURLProtocol.statusCode = 500
        let service = makeService()
        
        let result = await service.search(query: "cat", page: 1)
        
        guard case .failure(.requestFailed) = result else {
            Issue.record("A 500 should surface as .requestFailed")
            return
        }
    }
    
    @Test
    func downloadImageReturnsTheRawBytes() async throws {
        let service = makeService()
        
        let result = await service.downloadImage(from: "https://static.klipy.com/download.webp")
        
        let data = try result.get()
        #expect(data == KlipyMockURLProtocol.imageData)
    }
    
    // MARK: - Private
    
    private func makeService(apiKey: String = "testkey") -> KlipyService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KlipyMockURLProtocol.self]
        return KlipyService(session: URLSession(configuration: configuration),
                            apiKey: { apiKey },
                            customerID: "@alice:example.com")
    }
}

// MARK: - MockURLProtocol

private nonisolated class KlipyMockURLProtocol: URLProtocol {
    static let imageData = Data("sticker-bytes".utf8)
    
    private static let _lastRequestURL: Mutex<URL?> = .init(nil)
    static var lastRequestURL: URL? {
        _lastRequestURL.withLock { $0 }
    }
    
    private static let _statusCode: Mutex<Int> = .init(200)
    static var statusCode: Int {
        get { _statusCode.withLock { $0 } }
        set { _statusCode.withLock { $0 = newValue } }
    }
    
    static func reset() {
        _lastRequestURL.withLock { $0 = nil }
        _statusCode.withLock { $0 = 200 }
    }
    
    private static let trendingJSON = """
    {"result":true,"data":{"data":[
        {"id":123,"slug":"trending-1","title":"Trending One","file":{
            "md":{"gif":{"url":"https://static.klipy.com/tr-md.gif","width":480,"height":480,"size":200000}},
            "sm":{"gif":{"url":"https://static.klipy.com/tr-sm.gif","width":200,"height":200,"size":60000}}
        }}
    ],"current_page":1,"per_page":24,"has_next":true}}
    """
    
    private static let searchJSON = """
    {"result":true,"data":{"data":[
        {"id":456,"slug":"happy-cat","title":"Happy Cat","file":{
            "md":{"gif":{"url":"https://static.klipy.com/cat-md.gif","width":115,"height":115,"size":12000}},
            "sm":{"gif":{"url":"https://static.klipy.com/cat-sm.gif","width":115,"height":115,"size":9000}}
        }},
        {"id":700,"slug":"webp-only","title":"WebP Only","file":{
            "md":{"webp":{"url":"https://static.klipy.com/wo-md.webp","width":115,"height":115,"size":1600}}
        }},
        {"id":789,"slug":"broken","title":"Broken","file":{"md":{},"sm":{}}}
    ],"current_page":1,"per_page":24,"has_next":true}}
    """
    
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        KlipyMockURLProtocol._lastRequestURL.withLock { $0 = url }
        
        let path = url.path()
        let data: Data = if path.contains("/stickers/trending") {
            Data(Self.trendingJSON.utf8)
        } else if path.contains("/stickers/search") {
            Data(Self.searchJSON.utf8)
        } else {
            Self.imageData
        }
        
        guard let response = HTTPURLResponse(url: url, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() { }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
}
