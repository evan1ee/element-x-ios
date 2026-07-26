//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Kingfisher
import SwiftUI

/// The GIF tab: a grid of animated GIF results (trending or search) that send on tap.
///
/// The grid is the same view whether or not results have arrived — placeholders stand in for the
/// first screenful until they do — so it appears at its final size immediately and each GIF fades
/// into a tile that was already there, rather than the layout being rebuilt around it.
struct GIFTabView: View {
    let gifs: [KlipySticker]
    let isLoading: Bool
    let onSelect: (KlipySticker) -> Void
    let onAddToStickers: (KlipySticker) -> Void
    let onLoadMore: () -> Void
    /// Reports a GIF scrolling into view, so its full-size bytes can be fetched before it's tapped.
    let onPrefetch: (KlipySticker) -> Void
    /// Reports the grid's vertical scroll offset, so the panel can auto-expand when the user
    /// scrolls into the content and collapse when they pull down past the top.
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
    
    /// Roughly the first screenful at the panel's compact height. These are the GIFs the user is
    /// actually waiting on, so they're the ones that get a placeholder and download priority.
    private static let aboveTheFoldCount = 9
    
    /// How many tiles are still waiting on the first page of results.
    private var placeholderCount: Int {
        isLoading ? max(Self.aboveTheFoldCount - gifs.count, 0) : 0
    }
    
    var body: some View {
        if gifs.isEmpty, !isLoading {
            Text(UntranslatedL10n.screenMediaInputNoResults)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }
    
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(gifs.enumerated()), id: \.element.id) { index, gif in
                    cell(for: gif, isAboveTheFold: index < Self.aboveTheFoldCount)
                }
                
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    placeholder
                }
            }
            .padding(12)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            onScrollOffsetChange(offset)
        }
    }
    
    private func cell(for gif: KlipySticker, isAboveTheFold: Bool) -> some View {
        Button {
            onSelect(gif)
        } label: {
            KFAnimatedImage(gif.previewURL)
                .placeholder { _ in placeholder }
                // The first row is what the user is waiting on; the rest can queue behind it.
                .downloadPriority(isAboveTheFold ? URLSessionTask.highPriority : URLSessionTask.lowPriority)
                .fade(duration: 0.15)
                .cancelOnDisappear(true)
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onAddToStickers(gif)
            } label: {
                Label(UntranslatedL10n.screenStickerDiscoveryAddToMyStickers, icon: \.plus)
            }
        }
        .onAppear {
            onPrefetch(gif)
            
            if gif.id == gifs.last?.id {
                onLoadMore()
            }
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(.compound.bgSubtleSecondary)
            .aspectRatio(1, contentMode: .fit)
    }
}
