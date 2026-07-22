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
    
    private var selectedTab: MediaTab {
        context.viewState.inputMode.mediaTab ?? .emoji
    }
    
    var body: some View {
        VStack(spacing: 8) {
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
        // Clear the sheet's drag indicator so the tabs aren't cramped against it.
        .padding(.top, 16)
        .background(Color.compound.bgCanvasDefault)
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
