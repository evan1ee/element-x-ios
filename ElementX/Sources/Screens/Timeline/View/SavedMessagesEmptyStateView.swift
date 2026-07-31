//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Shown over an empty Saved Messages timeline, where the room's purpose isn't obvious
/// from an empty list of messages.
struct SavedMessagesEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.saveSolid, size: .custom(32), relativeTo: .compound.headingLG)
                .foregroundStyle(.compound.iconSecondary)
                .padding(.bottom, 8)
            
            Text(UntranslatedL10n.screenSavedMessagesEmptyStateTitle)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(.compound.textPrimary)
            
            Text(UntranslatedL10n.screenSavedMessagesEmptyStateMessage)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.compound.bgCanvasDefault)
    }
}

// MARK: - Previews

struct SavedMessagesEmptyStateView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        SavedMessagesEmptyStateView()
    }
}
