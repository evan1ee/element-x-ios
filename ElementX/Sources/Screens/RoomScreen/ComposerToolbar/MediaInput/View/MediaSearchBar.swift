//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media panel's search field. Because the panel is a sheet (not the keyboard slot), a
/// normal text field works: focusing it raises the system keyboard over the sheet.
struct MediaSearchBar: View {
    @Binding var query: String
    let tab: MediaTab
    
    var body: some View {
        HStack(spacing: 8) {
            CompoundIcon(\.search, size: .small, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconSecondary)
            
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    CompoundIcon(\.close, size: .small, relativeTo: .compound.bodyLG)
                        .foregroundStyle(.compound.iconSecondary)
                }
                .accessibilityLabel(L10n.actionClear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(GlassCapsuleBackground())
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private var placeholder: String {
        tab == .gif ? UntranslatedL10n.screenMediaInputSearchGifs : UntranslatedL10n.screenMediaInputSearchEmojis
    }
}
