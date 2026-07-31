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
            Image(asset: Asset.Images.savedMessagesIcon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(HaloBrand.gradient)
                .frame(width: 44, height: 44)
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
