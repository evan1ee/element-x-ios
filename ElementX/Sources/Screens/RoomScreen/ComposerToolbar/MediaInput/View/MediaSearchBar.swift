//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media panel's search field. Unlike the composer, this is a normal, independent text
/// field: focusing it is the one case where the real system keyboard appears while the panel is
/// up, and the panel expands so the keyboard covers no more than its lower half.
struct MediaSearchBar: View {
    @Binding var query: String
    let tab: MediaTab
    /// Two-way focus control. When bound, the field focuses/blurs to match it and reports its own
    /// focus changes back into it, so the composer can expand the panel the moment focus moves —
    /// before the keyboard appears — rather than a beat later.
    var focus: Binding<Bool>?
    
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
                    focus?.wrappedValue = newValue
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
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .onAppear {
            if focus?.wrappedValue == true {
                isFocused = true
            }
        }
        .onChange(of: focus?.wrappedValue) { _, newValue in
            guard let newValue, newValue != isFocused else { return }
            isFocused = newValue
        }
    }
    
    private var placeholder: String {
        tab == .gif ? UntranslatedL10n.screenMediaInputSearchGifs : UntranslatedL10n.screenMediaInputSearchEmojis
    }
}
