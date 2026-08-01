//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The mark shown wherever Saved Messages would otherwise use a room avatar.
///
/// A fixed icon rather than the room's own avatar, so the room looks the same on every
/// device — and the same in the chat list as it does in the room it opens.
struct SavedMessagesAvatarImage: View {
    let size: CGFloat
    
    var body: some View {
        Image(asset: Asset.Images.savedMessagesIcon)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(HaloBrand.gradient)
            .frame(width: size * 0.55, height: size * 0.55)
            .frame(width: size, height: size)
            .background(HaloBrand.gradientTop.opacity(0.14), in: Circle())
    }
}

extension SavedMessagesAvatarImage {
    init(avatarSize: Avatars.Size) {
        self.init(size: avatarSize.value)
    }
}

// MARK: - Previews

struct SavedMessagesAvatarImage_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        HStack(spacing: 16) {
            SavedMessagesAvatarImage(avatarSize: .room(on: .timeline))
            SavedMessagesAvatarImage(avatarSize: .room(on: .chats))
            SavedMessagesAvatarImage(avatarSize: .room(on: .details))
        }
        .padding()
    }
}
