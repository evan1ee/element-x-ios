//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The composer's current input source. The media panel occupies the keyboard slot
/// via the editor's `inputView`, so switching between keyboard and panel never moves
/// the composer or the caret (the panel *is* the keyboard).
enum ComposerInputMode: Equatable {
    /// The editor is first responder with the system keyboard (`inputView == nil`).
    case keyboard
    /// The editor is first responder with the media panel in the keyboard slot.
    case media(MediaTab)
    /// No first responder.
    case none
    
    var isMedia: Bool {
        mediaTab != nil
    }
    
    var mediaTab: MediaTab? {
        if case let .media(tab) = self {
            return tab
        }
        return nil
    }
}

/// A tab in the media input panel. Adding a tab should only require a new case here,
/// a matching content view, and (optionally) a provider — never changes to the host or
/// the state machine.
enum MediaTab: String, CaseIterable, Identifiable {
    case emoji
    case gif
    case sticker
    
    var id: String {
        rawValue
    }
}
