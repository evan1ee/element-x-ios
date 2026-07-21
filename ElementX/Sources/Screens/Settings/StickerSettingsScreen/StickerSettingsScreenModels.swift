//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct StickerSettingsScreenViewState: BindableState {
    var bindings: StickerSettingsScreenViewStateBindings
}

// periphery:ignore - subscript are seen as false positives
@dynamicMemberLookup
struct StickerSettingsScreenViewStateBindings {
    private let stickerSettings: StickerSettingsProtocol
    
    init(stickerSettings: StickerSettingsProtocol) {
        self.stickerSettings = stickerSettings
    }
    
    subscript<Setting>(dynamicMember keyPath: ReferenceWritableKeyPath<StickerSettingsProtocol, Setting>) -> Setting {
        get { stickerSettings[keyPath: keyPath] }
        set { stickerSettings[keyPath: keyPath] = newValue }
    }
}

enum StickerSettingsScreenViewAction {
    case reset
}

protocol StickerSettingsProtocol: AnyObject {
    var klipyAPIKey: String { get set }
}

extension AppSettings: StickerSettingsProtocol { }
