//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media panel's search field. Unlike the composer, this is a normal, independent text
/// field: focusing it is the one case where the real system keyboard is allowed to appear while
/// the panel is up (the panel then expands to make room, per `onFocusChange`).
struct MediaSearchBar: View {
    @Binding var query: String
    let tab: MediaTab
    var onFocusChange: (Bool) -> Void = { _ in }
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            CompoundIcon(\.search, size: .small, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconSecondary)
            
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onChange(of: isFocused) { _, newValue in
                    onFocusChange(newValue)
                }
            
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
