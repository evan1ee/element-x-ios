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
    /// The two heights the grabber/edge-drag snap to: compact first, expanded second.
    let detents: [CGFloat]
    
    /// The height when the current drag began, so a drag tracks the finger from where it started.
    @State private var dragStartHeight: CGFloat?
    /// Whether the in-progress content-edge drag (if any) is allowed to resize the panel — decided
    /// once, at the start of that drag, from whether the visible tab was already at its scroll top.
    @State private var contentDragEngaged = false
    
    @State private var isEmojiAtTop = true
    @State private var isGIFAtTop = true
    @State private var isStickerAtTop = true
    
    private var selectedTab: MediaTab {
        context.viewState.inputMode.mediaTab ?? .emoji
    }
    
    private var isSelectedTabAtTop: Bool {
        switch selectedTab {
        case .emoji: isEmojiAtTop
        case .gif: isGIFAtTop
        case .sticker: isStickerAtTop
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            grabber
            
            MediaTabBar(selectedTab: selectedTab) { tab in
                context.send(viewAction: .selectMediaTab(tab))
            }
            
            if selectedTab != .sticker {
                MediaSearchBar(query: $context.mediaSearchQuery, tab: selectedTab) { isFocused in
                    // The one case where the real system keyboard is allowed to appear: expand to
                    // make room for it instead of overlapping the search field.
                    guard isFocused, let expanded = detents.last else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        height = expanded
                    }
                }
            }
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(edgeDragGesture)
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
    
    /// The grabber's drag: always active, tracking the finger 1:1 from wherever it started.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartHeight ?? height
                dragStartHeight = start
                // Dragging up (negative translation) grows the panel.
                height = clampedHeight(start - value.translation.height)
            }
            .onEnded { value in
                snap(from: dragStartHeight, predictedTranslation: value.predictedEndTranslation.height)
                dragStartHeight = nil
            }
    }
    
    /// A drag anywhere in the visible grid: only resizes the panel when that grid was already
    /// scrolled to its top when the drag began (checked once, so a drag that starts mid-scroll
    /// doesn't suddenly jump the panel height once the list happens to reach the top) — otherwise
    /// the `ScrollView` scrolls normally, since this is a `.simultaneousGesture`.
    private var edgeDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartHeight == nil {
                    contentDragEngaged = isSelectedTabAtTop
                    dragStartHeight = height
                }
                guard contentDragEngaged, let start = dragStartHeight else { return }
                height = clampedHeight(start - value.translation.height)
            }
            .onEnded { value in
                if contentDragEngaged {
                    snap(from: dragStartHeight, predictedTranslation: value.predictedEndTranslation.height)
                }
                dragStartHeight = nil
                contentDragEngaged = false
            }
    }
    
    private func snap(from startHeight: CGFloat?, predictedTranslation: CGFloat) {
        let start = startHeight ?? height
        let predicted = start - predictedTranslation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            height = nearestDetent(to: clampedHeight(predicted))
        }
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
                         onIsAtTopChange: { isEmojiAtTop = $0 })
                .opacity(selectedTab == .emoji ? 1 : 0)
                .allowsHitTesting(selectedTab == .emoji)
            
            GIFTabView(gifs: context.viewState.mediaGIFs,
                       isLoading: context.viewState.mediaGIFsLoading,
                       sendingID: context.viewState.sendingMediaItemID,
                       onSelect: { context.send(viewAction: .sendMediaGIF($0)) },
                       onAddToStickers: { context.send(viewAction: .addMediaGIF($0)) },
                       onLoadMore: { context.send(viewAction: .loadMoreGIFs) },
                       onIsAtTopChange: { isGIFAtTop = $0 })
                .opacity(selectedTab == .gif ? 1 : 0)
                .allowsHitTesting(selectedTab == .gif)
            
            StickerTabView(stickers: context.viewState.mediaStickers,
                           sendingID: context.viewState.sendingMediaItemID,
                           isAddingStickers: context.viewState.isAddingStickers,
                           photosPickerItems: $context.stickerPhotosPickerItems,
                           mediaProvider: context.mediaProvider,
                           onSelect: { context.send(viewAction: .sendMediaSticker($0)) },
                           onAddPhotos: { context.send(viewAction: .addStickerPhotos) },
                           onIsAtTopChange: { isStickerAtTop = $0 })
                .opacity(selectedTab == .sticker ? 1 : 0)
                .allowsHitTesting(selectedTab == .sticker)
        }
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }
}
