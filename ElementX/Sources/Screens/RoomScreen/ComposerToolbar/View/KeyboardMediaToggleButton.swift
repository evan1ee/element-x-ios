//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The composer toggle that swaps between the system keyboard and the media panel.
/// The glyph is driven purely by `inputMode`: a face when the keyboard is (or would be)
/// shown, a keyboard when the media panel is up — never both.
struct KeyboardMediaToggleButton: View {
    let inputMode: ComposerInputMode
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            // Explicitly sized (matching the "+" attachment button) so the frame doesn't shift
            // between the two glyphs, which otherwise have slightly different intrinsic bounds.
            CompoundIcon(inputMode.isMedia ? \.keyboard : \.reaction,
                         size: Compound.supportsGlass ? .medium : .small,
                         relativeTo: .compound.headingLG)
        }
        .buttonStyle(ComposerToolbarButtonStyle())
        .accessibilityLabel(inputMode.isMedia ? UntranslatedL10n.a11yShowKeyboard : UntranslatedL10n.a11yShowMediaInput)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.composerToolbar.mediaToggle)
    }
}
