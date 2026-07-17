//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct Sticker: Identifiable, Equatable {
    enum Source: Equatable {
        /// An image file bundled with the app.
        case bundle(URL)
        /// Media that already exists on the homeserver.
        case media(url: String)
    }
    
    let id: String
    let body: String
    let source: Source
    let width: UInt64?
    let height: UInt64?
    let fileSize: UInt64?
    let mimeType: String?
}

struct StickerCollection: Equatable {
    var userStickers: [Sticker] = []
    var builtInStickers: [Sticker] = []
}

enum StickerServiceError: Error {
    case uploadFailed
    case sendFailed
    case processingFailed
    case packUpdateFailed
}

// sourcery: AutoMockable
protocol StickerServiceProtocol {
    /// The stickers bundled with the app, always available.
    var builtInStickers: [Sticker] { get }
    
    /// Loads the user's own sticker pack alongside the built-in one.
    func loadStickers() async -> StickerCollection
    
    func send(_ sticker: Sticker,
              in timelineController: TimelineControllerProtocol) async -> Result<Void, StickerServiceError>
    
    /// Processes and uploads the image at the given URL, adding it to the
    /// user's sticker pack in their account data.
    func addUserSticker(fromMediaAt url: URL) async -> Result<Void, StickerServiceError>
    
    /// Removes the sticker with the given ID from the user's pack.
    func removeUserSticker(id: String) async -> Result<Void, StickerServiceError>
}
