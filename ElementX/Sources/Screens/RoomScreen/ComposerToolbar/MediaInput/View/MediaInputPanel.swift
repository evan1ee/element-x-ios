//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media panel shown in the keyboard's place. It hosts the emoji/GIF/sticker tabs, all
/// mounted simultaneously (only the selected one is visible/hit-testable) so switching tabs, or
/// closing and reopening the panel, never loses a tab's scroll position or in-flight content.
struct MediaInputPanel: View {
    @ObservedObject var context: ComposerToolbarViewModel.Context
    
    /// The panel's live height, owned by the composer so it survives tab switches and reopening.
    @Binding var height: CGFloat
    /// The two heights the grabber snaps to: compact first, expanded second.
    let detents: [CGFloat]
    /// Whether the search field is focused, owned by the composer so it can lift the panel above
    /// the system keyboard that the focused field summons.
    @Binding var isSearchFocused: Bool
    /// See `MediaSearchBar.tapOverride` — set while the panel is presented as an input view.
    var searchTapOverride: (() -> Void)?
    /// See `MediaSearchBar.autoFocus` — set while the panel is presented inline for searching.
    var searchAutoFocus = false
    
    /// The height when the current grabber drag began, so it tracks the finger from where it started.
    @State private var dragStartHeight: CGFloat?
    
    /// How far the user must pull down past a grid's top before the panel collapses back to
    /// its compact height.
    private let collapsePullThreshold: CGFloat = 40
    
    @State private var emojiScrollOffset: CGFloat = 0
    @State private var gifScrollOffset: CGFloat = 0
    @State private var stickerScrollOffset: CGFloat = 0
    
    private var selectedTab: MediaTab {
        context.viewState.inputMode.mediaTab ?? .emoji
    }
    
    private var selectedTabScrollOffset: CGFloat {
        switch selectedTab {
        case .emoji: emojiScrollOffset
        case .gif: gifScrollOffset
        case .sticker: stickerScrollOffset
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            grabber
            
            MediaTabBar(selectedTab: selectedTab) { tab in
                context.send(viewAction: .selectMediaTab(tab))
            }
            
            if selectedTab != .sticker {
                MediaSearchBar(query: $context.mediaSearchQuery,
                               tab: selectedTab,
                               autoFocus: searchAutoFocus,
                               tapOverride: searchTapOverride) { isFocused in
                    isSearchFocused = isFocused
                }
            }
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.compound.bgCanvasDefault)
        .onChange(of: selectedTabScrollOffset) { _, offset in
            guard dragStartHeight == nil, let compact = detents.first, let expanded = detents.last else { return }
            
            // The height change resizes the keyboard the panel presents as; the system animates
            // that frame change itself, so no SwiftUI animation is needed here.
            if offset > 0, height < expanded {
                // The user scrolled into the visible grid: grow to the expanded detent so the
                // content gets the room it clearly needs.
                height = expanded
            } else if offset < -collapsePullThreshold, height > compact {
                // The user pulled down past the grid's top: return to the compact height.
                height = compact
            }
        }
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
    
    /// The grabber's drag: the panel snaps to the nearest detent on release. It deliberately
    /// doesn't resize live under the finger — the panel presents as a keyboard, and keyboard
    /// frames animate between fixed sizes rather than tracking a drag.
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { _ in
                if dragStartHeight == nil {
                    dragStartHeight = height
                }
            }
            .onEnded { value in
                snap(from: dragStartHeight, predictedTranslation: value.predictedEndTranslation.height)
                dragStartHeight = nil
            }
    }
    
    private func snap(from startHeight: CGFloat?, predictedTranslation: CGFloat) {
        let start = startHeight ?? height
        let predicted = start - predictedTranslation
        // The system animates the resulting keyboard frame change itself.
        height = nearestDetent(to: clampedHeight(predicted))
    }
    
    private func clampedHeight(_ value: CGFloat) -> CGFloat {
        guard let min = detents.first, let max = detents.last else { return value }
        return Swift.min(Swift.max(value, min), max)
    }
    
    private func nearestDetent(to value: CGFloat) -> CGFloat {
        detents.min { abs($0 - value) < abs($1 - value) } ?? value
    }
    
    /// All three tabs stay mounted the whole time the panel exists; only the selected one is
    /// visible and hit-testable. This is what preserves each tab's scroll position and in-flight
    /// content across tab switches and panel close/reopen.
    private var content: some View {
        ZStack {
            EmojiTabView(categories: context.viewState.mediaEmojiCategories,
                         onSelect: { context.send(viewAction: .insertEmoji($0)) },
                         onDeleteBackward: { context.send(viewAction: .deleteBackward) },
                         onScrollOffsetChange: { emojiScrollOffset = $0 })
                .opacity(selectedTab == .emoji ? 1 : 0)
                .allowsHitTesting(selectedTab == .emoji)
            
            GIFTabView(gifs: context.viewState.mediaGIFs,
                       isLoading: context.viewState.mediaGIFsLoading,
                       sendingID: context.viewState.sendingMediaItemID,
                       onSelect: { context.send(viewAction: .sendMediaGIF($0)) },
                       onAddToStickers: { context.send(viewAction: .addMediaGIF($0)) },
                       onLoadMore: { context.send(viewAction: .loadMoreGIFs) },
                       onScrollOffsetChange: { gifScrollOffset = $0 })
                .opacity(selectedTab == .gif ? 1 : 0)
                .allowsHitTesting(selectedTab == .gif)
            
            StickerTabView(stickers: context.viewState.mediaStickers,
                           sendingID: context.viewState.sendingMediaItemID,
                           isAddingStickers: context.viewState.isAddingStickers,
                           photosPickerItems: $context.stickerPhotosPickerItems,
                           mediaProvider: context.mediaProvider,
                           onSelect: { context.send(viewAction: .sendMediaSticker($0)) },
                           onAddPhotos: { context.send(viewAction: .addStickerPhotos) },
                           onScrollOffsetChange: { stickerScrollOffset = $0 })
                .opacity(selectedTab == .sticker ? 1 : 0)
                .allowsHitTesting(selectedTab == .sticker)
        }
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }
}
