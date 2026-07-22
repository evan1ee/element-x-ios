//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media panel shown in the keyboard slot. It hosts one tab at a time (emoji / GIF /
/// sticker) with a bottom tab bar; switching tabs swaps the content in place and never
/// touches the first responder, so the panel stays put.
struct MediaInputPanel: View {
    @ObservedObject var context: ComposerToolbarViewModel.Context
    
    /// The panel's live height, owned by the composer so it survives tab switches and reopening.
    @Binding var height: CGFloat
    /// The heights the grabber snaps to, smallest first.
    let detents: [CGFloat]
    
    /// The height when the current drag began, so the grabber tracks the finger from where it started.
    @State private var dragStartHeight: CGFloat?
    
    private var selectedTab: MediaTab {
        context.viewState.inputMode.mediaTab ?? .emoji
    }
    
    var body: some View {
        VStack(spacing: 8) {
            grabber
            
            MediaTabBar(selectedTab: selectedTab) { tab in
                context.send(viewAction: .selectMediaTab(tab))
            }
            
            if selectedTab != .sticker {
                MediaSearchBar(query: $context.mediaSearchQuery, tab: selectedTab)
            }
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .background(Color.compound.bgCanvasDefault)
    }
    
    /// A draggable handle that resizes the panel, snapping to the nearest detent on release.
    private var grabber: some View {
        Capsule()
            .foregroundStyle(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityLabel(UntranslatedL10n.screenMediaInputResizeHandle)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartHeight ?? height
                dragStartHeight = start
                // Dragging up (negative translation) grows the panel.
                height = clampedHeight(start - value.translation.height)
            }
            .onEnded { value in
                let start = dragStartHeight ?? height
                dragStartHeight = nil
                let predicted = start - value.predictedEndTranslation.height
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    height = nearestDetent(to: clampedHeight(predicted))
                }
            }
    }
    
    private func clampedHeight(_ value: CGFloat) -> CGFloat {
        guard let min = detents.first, let max = detents.last else { return value }
        return Swift.min(Swift.max(value, min), max)
    }
    
    private func nearestDetent(to value: CGFloat) -> CGFloat {
        detents.min { abs($0 - value) < abs($1 - value) } ?? value
    }
    
    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .emoji:
            EmojiTabView(categories: context.viewState.mediaEmojiCategories) { emoji in
                context.send(viewAction: .insertEmoji(emoji))
            }
        case .gif:
            GIFTabView(gifs: context.viewState.mediaGIFs,
                       isLoading: context.viewState.mediaGIFsLoading,
                       sendingID: context.viewState.sendingMediaItemID,
                       onSelect: { context.send(viewAction: .sendMediaGIF($0)) },
                       onAddToStickers: { context.send(viewAction: .addMediaGIF($0)) },
                       onLoadMore: { context.send(viewAction: .loadMoreGIFs) })
        case .sticker:
            StickerTabView(stickers: context.viewState.mediaStickers,
                           sendingID: context.viewState.sendingMediaItemID,
                           isAddingStickers: context.viewState.isAddingStickers,
                           photosPickerItems: $context.stickerPhotosPickerItems,
                           mediaProvider: context.mediaProvider,
                           onSelect: { context.send(viewAction: .sendMediaSticker($0)) },
                           onAddPhotos: { context.send(viewAction: .addStickerPhotos) })
        }
    }
}
