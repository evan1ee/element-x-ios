//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct StickerSettingsScreen: View {
    @Bindable var context: StickerSettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenStickerSettingsApiKeyTitle),
                        kind: .textField(text: $context.klipyAPIKey, axis: .vertical))
                
                ListRow(label: .action(title: UntranslatedL10n.screenStickerSettingsReset,
                                       icon: \.restart,
                                       role: .destructive),
                        kind: .button { context.send(viewAction: .reset) })
            } footer: {
                Text(UntranslatedL10n.screenStickerSettingsApiKeyFooter)
                    .compoundListSectionFooter()
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenStickerSettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

struct StickerSettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = StickerSettingsScreenViewModel(stickerSettings: AppSettings.volatile())
    
    static var previews: some View {
        ElementNavigationStack {
            StickerSettingsScreen(context: viewModel.context)
        }
    }
}
