//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Which of the optional tabs appear at the bottom of the app.
struct DisplaySettingsScreen: View {
    @Bindable var context: DisplaySettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            Section {
                ListRow(label: .default(title: UntranslatedL10n.screenDisplaySettingsPhotosTitle,
                                        description: UntranslatedL10n.screenDisplaySettingsPhotosDescription,
                                        icon: \.image),
                        kind: .toggle($context.showPhotosTab))
                
                ListRow(label: .default(title: UntranslatedL10n.screenDisplaySettingsSpacesTitle,
                                        description: UntranslatedL10n.screenDisplaySettingsSpacesDescription,
                                        icon: \.space),
                        kind: .toggle($context.showSpacesTab))
            } header: {
                Text(UntranslatedL10n.screenDisplaySettingsTabsHeader)
                    .compoundListSectionHeader()
            } footer: {
                Text(UntranslatedL10n.screenDisplaySettingsTabsFooter)
                    .compoundListSectionFooter()
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenDisplaySettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

struct DisplaySettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = DisplaySettingsScreenViewModel(displaySettings: AppSettings.volatile())
    
    static var previews: some View {
        ElementNavigationStack {
            DisplaySettingsScreen(context: viewModel.context)
        }
    }
}
