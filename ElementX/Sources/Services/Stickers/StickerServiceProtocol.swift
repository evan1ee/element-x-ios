//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct BuiltInSticker: Identifiable, Equatable {
    let id: String
    let body: String
    let fileURL: URL
    let width: UInt64
    let height: UInt64
    let fileSize: UInt64
}

enum StickerServiceError: Error {
    case uploadFailed
    case sendFailed
    case encodingFailure
}

// sourcery: AutoMockable
protocol StickerServiceProtocol {
    var stickers: [BuiltInSticker] { get }
    
    func send(_ sticker: BuiltInSticker,
              in roomProxy: JoinedRoomProxyProtocol,
              threadRootEventID: String?) async -> Result<Void, StickerServiceError>
}
