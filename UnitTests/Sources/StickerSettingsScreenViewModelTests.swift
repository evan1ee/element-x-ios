//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct StickerSettingsScreenViewModelTests {
    @Test
    func editingTheKeyWritesToSettings() {
        let appSettings = AppSettings.volatile()
        let viewModel = StickerSettingsScreenViewModel(stickerSettings: appSettings)
        
        viewModel.context.klipyAPIKey = "my-custom-key"
        
        #expect(appSettings.klipyAPIKey == "my-custom-key")
    }
    
    @Test
    func resetRestoresTheDefaultKey() {
        let appSettings = AppSettings.volatile()
        appSettings.klipyAPIKey = "changed"
        let viewModel = StickerSettingsScreenViewModel(stickerSettings: appSettings)
        
        viewModel.context.send(viewAction: .reset)
        
        #expect(appSettings.klipyAPIKey == AppSettings.defaultKlipyAPIKey)
    }
}
