//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct DisplaySettingsScreenViewState: BindableState {
    var bindings: DisplaySettingsScreenViewStateBindings
}

/// Reads and writes the settings in place, so a toggle takes effect as it moves rather
/// than on the way out of the screen.
@dynamicMemberLookup
struct DisplaySettingsScreenViewStateBindings {
    private let displaySettings: DisplaySettingsProtocol
    
    init(displaySettings: DisplaySettingsProtocol) {
        self.displaySettings = displaySettings
    }
    
    subscript<Setting>(dynamicMember keyPath: ReferenceWritableKeyPath<DisplaySettingsProtocol, Setting>) -> Setting {
        get { displaySettings[keyPath: keyPath] }
        set { displaySettings[keyPath: keyPath] = newValue }
    }
}

enum DisplaySettingsScreenViewAction { }

protocol DisplaySettingsProtocol: AnyObject {
    var showSpacesTab: Bool { get set }
    var showPhotosTab: Bool { get set }
}

extension AppSettings: DisplaySettingsProtocol { }
