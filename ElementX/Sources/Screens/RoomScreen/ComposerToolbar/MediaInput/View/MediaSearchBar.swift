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
/// the panel is up (the panel then lifts above the keyboard, per `onFocusChange`).
struct MediaSearchBar: View {
    @Binding var query: String
    let tab: MediaTab
    /// Focus the field as soon as it appears — used when the panel is re-hosted inline so the
    /// search the user just requested starts immediately.
    var autoFocus = false
    /// When set, the field itself can't be focused; tapping the bar calls this instead. Used
    /// while the panel is presented as the composer's `inputView`, where focusing a field that
    /// lives inside the keyboard would dismiss the very keyboard hosting it.
    var tapOverride: (() -> Void)?
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
                .allowsHitTesting(tapOverride == nil)
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
        .contentShape(Rectangle())
        .onTapGesture {
            tapOverride?()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .onAppear {
            guard autoFocus else { return }
            // Deferred a beat so the field is fully in the hierarchy before taking focus.
            Task { isFocused = true }
        }
    }
    
    private var placeholder: String {
        tab == .gif ? UntranslatedL10n.screenMediaInputSearchGifs : UntranslatedL10n.screenMediaInputSearchEmojis
    }
}
