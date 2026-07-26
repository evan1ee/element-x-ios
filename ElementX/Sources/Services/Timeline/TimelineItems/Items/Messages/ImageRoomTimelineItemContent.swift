//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct ImageRoomTimelineItemContent: Hashable {
    let filename: String
    var caption: String?
    var formattedCaption: AttributedString?
    /// The original textual representation of the formatted caption directly from the event (usually HTML code)
    var formattedCaptionHTMLString: String?
    
    let imageInfo: ImageInfoProxy
    let thumbnailInfo: ImageInfoProxy?
    
    var blurhash: String?
    var contentType: UTType?
    
    /// Whether this is an animated GIF, which the app treats like a sticker: tapping it opens
    /// nothing, and it can be added to the user's pack. `contentType` is absent on events that
    /// didn't declare a mimetype, so the filename is the fallback.
    var isGIF: Bool {
        if let contentType {
            return contentType.conforms(to: .gif)
        }
        return (filename as NSString).pathExtension.lowercased() == "gif"
    }
}
