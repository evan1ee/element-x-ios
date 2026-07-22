//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The segmented control at the top of the media panel that switches between the Emoji, GIF
/// and Sticker tabs. The selected segment sits on a raised white pill.
struct MediaTabBar: View {
    let selectedTab: MediaTab
    let onSelect: (MediaTab) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(MediaTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    CompoundIcon(tab.icon, size: .medium, relativeTo: .compound.bodyLG)
                        .foregroundStyle(tab == selectedTab ? Color.compound.iconPrimary : Color.compound.iconSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if tab == selectedTab {
                                Capsule()
                                    .fill(Color.compound.bgCanvasDefault)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.compound.bgSubtleSecondary, in: Capsule())
        .padding(.horizontal, 12)
    }
}

extension MediaTab {
    var icon: KeyPath<CompoundIcons, Image> {
        switch self {
        case .emoji: \.reaction
        case .gif: \.image
        case .sticker: \.sticker
        }
    }
    
    var title: String {
        switch self {
        case .emoji: UntranslatedL10n.screenMediaInputEmoji
        case .gif: UntranslatedL10n.screenMediaInputGifs
        case .sticker: UntranslatedL10n.screenMediaInputStickers
        }
    }
}

/// A translucent capsule background for the search field (Liquid Glass on iOS 26).
struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.snapshotableGlassEffect(.regular, snapshotBackground: .compound.bgSubtleSecondary, in: Capsule())
        } else {
            content.background(.compound.bgSubtleSecondary, in: Capsule())
        }
    }
}
