//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

/// The narrow slice of the timeline controller that sticker/GIF sending needs. Kept separate from
/// `TimelineControllerProtocol` so the feature's additions live in the fork's own files and don't
/// have to be woven into the upstream protocol (which keeps upstream merges conflict-free).
///
/// Matches `TimelineControllerProtocol`'s isolation (`@MainActor`, `Sendable`) so it can be passed
/// into the nonisolated `StickerService`.
@MainActor
protocol StickerSending: Sendable {
    /// Sends an `m.sticker` event for already uploaded media, `url` being its `mxc://` URI.
    func sendSticker(body: String, url: String, imageInfo: ImageInfo) async -> Result<Void, TimelineControllerError>
}
