//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Searches and downloads stickers from the [Klipy](https://docs.klipy.com) API.
///
/// The API key is read lazily on each request so that changes made in the sticker
/// settings take effect without rebuilding the service.
final nonisolated class KlipyService: KlipyServiceProtocol, Sendable {
    private static let baseURL: URL = "https://api.klipy.com/api/v1"
    
    private let session: URLSession
    private let apiKey: @Sendable () -> String
    private let customerID: String
    private let mediaType: String
    private let perPage: Int
    private let locale: String
    private let contentFilter: String
    
    init(session: URLSession = .shared,
         apiKey: @escaping @Sendable () -> String,
         customerID: String,
         mediaType: String = "stickers",
         perPage: Int = 24,
         locale: String = Locale.current.language.languageCode?.identifier ?? "en",
         contentFilter: String = "medium") {
        self.session = session
        self.apiKey = apiKey
        self.customerID = customerID
        self.mediaType = mediaType
        self.perPage = perPage
        self.locale = locale
        self.contentFilter = contentFilter
    }
    
    func search(query: String, page: Int) async -> Result<KlipySearchResults, KlipyServiceError> {
        let key = apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .failure(.invalidAPIKey)
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = trimmedQuery.isEmpty ? "trending" : "search"
        
        guard var components = URLComponents(url: Self.baseURL.appending(path: "\(key)/\(mediaType)/\(endpoint)"),
                                             resolvingAgainstBaseURL: false) else {
            return .failure(.requestFailed)
        }
        
        var queryItems = [URLQueryItem(name: "customer_id", value: customerID),
                          URLQueryItem(name: "page", value: String(page)),
                          URLQueryItem(name: "per_page", value: String(perPage)),
                          URLQueryItem(name: "locale", value: locale),
                          URLQueryItem(name: "content_filter", value: contentFilter)]
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmedQuery))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else {
            return .failure(.requestFailed)
        }
        
        do {
            let (data, response) = try await session.dataWithRetry(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return .failure(.requestFailed)
            }
            let decoded = try JSONDecoder().decode(KlipyResponse.self, from: data)
            return .success(decoded.searchResults(requestedPage: page))
        } catch is DecodingError {
            MXLog.error("Failed decoding the Klipy response.")
            return .failure(.decodingFailed)
        } catch {
            MXLog.error("Failed fetching stickers from Klipy: \(error)")
            return .failure(.requestFailed)
        }
    }
    
    func downloadImage(from url: URL) async -> Result<Data, KlipyServiceError> {
        do {
            let (data, response) = try await session.dataWithRetry(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return .failure(.downloadFailed)
            }
            return .success(data)
        } catch {
            MXLog.error("Failed downloading sticker from Klipy: \(error)")
            return .failure(.downloadFailed)
        }
    }
}

// MARK: - Response decoding

private struct KlipyResponse: Decodable {
    let data: DataBlock
    
    func searchResults(requestedPage: Int) -> KlipySearchResults {
        let stickers = data.data.compactMap(\.sticker)
        let nextPage = (data.currentPage ?? requestedPage) + 1
        return KlipySearchResults(stickers: stickers, hasNextPage: data.hasNext ?? false, nextPage: nextPage)
    }
    
    struct DataBlock: Decodable {
        let data: [Item]
        let hasNext: Bool?
        let currentPage: Int?
        
        enum CodingKeys: String, CodingKey {
            case data
            case hasNext = "has_next"
            case currentPage = "current_page"
        }
    }
    
    struct Item: Decodable {
        let id: String
        let slug: String?
        let title: String?
        let file: FileVariants
        
        enum CodingKeys: String, CodingKey {
            case id, slug, title, file
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Klipy returns numeric IDs that don't always fit an Int, so accept either form.
            if let intID = try? container.decode(Int64.self, forKey: .id) {
                id = String(intID)
            } else {
                id = try container.decode(String.self, forKey: .id)
            }
            slug = try container.decodeIfPresent(String.self, forKey: .slug)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            file = try container.decode(FileVariants.self, forKey: .file)
        }
        
        /// Maps the entry to an app sticker, preferring an animated variant, or `nil` when no usable variant exists.
        var sticker: KlipySticker? {
            guard let upload = file.uploadVariant, let preview = file.previewVariant else {
                return nil
            }
            return KlipySticker(id: slug ?? id,
                                title: title ?? "",
                                previewURL: preview.url,
                                fileURL: upload.url,
                                width: upload.width,
                                height: upload.height,
                                size: upload.size,
                                mimeType: upload.mimeType)
        }
    }
    
    struct FileVariants: Decodable {
        let hd: SizeVariants?
        let md: SizeVariants?
        let sm: SizeVariants?
        let xs: SizeVariants?
        
        /// The animated GIF uploaded as the sticker, at a reasonable size.
        var uploadVariant: TypedVariant? {
            md?.gifVariant ?? hd?.gifVariant ?? sm?.gifVariant ?? xs?.gifVariant
        }
        
        /// A small animated GIF for the discovery grid preview.
        var previewVariant: TypedVariant? {
            sm?.gifVariant ?? md?.gifVariant ?? xs?.gifVariant ?? hd?.gifVariant
        }
    }
    
    struct SizeVariants: Decodable {
        let gif: Variant?
        
        /// Only animated GIFs are used, so the sticker animates both in the discovery
        /// grid (Kingfisher) and once sent (Element renders animated GIFs, not WebP).
        var gifVariant: TypedVariant? {
            gif.map { TypedVariant(variant: $0, mimeType: "image/gif") }
        }
    }
    
    struct Variant: Decodable {
        let url: URL
        let width: UInt64
        let height: UInt64
        let size: UInt64
    }
    
    struct TypedVariant {
        let variant: Variant
        let mimeType: String
        
        var url: URL {
            variant.url
        }
        
        var width: UInt64 {
            variant.width
        }
        
        var height: UInt64 {
            variant.height
        }
        
        var size: UInt64 {
            variant.size
        }
    }
}
