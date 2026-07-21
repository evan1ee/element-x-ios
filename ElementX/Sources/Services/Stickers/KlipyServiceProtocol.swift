//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// A sticker discovered through the Klipy API.
struct KlipySticker: Identifiable, Equatable {
    let id: String
    let title: String
    /// A small animated variant used for the discovery grid.
    let previewURL: URL
    /// The full variant that gets uploaded when the sticker is sent or collected.
    let fileURL: URL
    let width: UInt64
    let height: UInt64
    let size: UInt64
    let mimeType: String
}

struct KlipySearchResults: Equatable {
    var stickers: [KlipySticker] = []
    var hasNextPage = false
    var nextPage = 1
}

enum KlipyServiceError: Error {
    case invalidAPIKey
    case requestFailed
    case decodingFailed
    case downloadFailed
}

// sourcery: AutoMockable
protocol KlipyServiceProtocol {
    /// Searches for stickers matching `query`, or fetches the trending stickers when the query is empty.
    func search(query: String, page: Int) async -> Result<KlipySearchResults, KlipyServiceError>
    
    /// Downloads the raw bytes of a sticker variant so it can be uploaded to the homeserver.
    func downloadImage(from url: URL) async -> Result<Data, KlipyServiceError>
}
