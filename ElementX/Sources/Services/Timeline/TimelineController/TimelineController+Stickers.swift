//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

// Sticker sending lives in the fork's own file (rather than inline in TimelineController) so it
// never collides with upstream changes to the controller's other send methods.
extension TimelineController: StickerSending {
    func sendSticker(body: String, url: String, imageInfo: ImageInfo) async -> Result<Void, TimelineControllerError> {
        switch await activeTimeline.sendSticker(body: body, url: url, imageInfo: imageInfo).mapError(TimelineControllerError.timelineProxyError) {
        case .success:
            callbacks.send(.messageSentOrEdited)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
}
