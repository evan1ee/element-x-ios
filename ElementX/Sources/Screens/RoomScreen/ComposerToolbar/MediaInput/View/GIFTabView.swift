//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Kingfisher
import SwiftUI

/// The GIF tab: a grid of animated GIF results (trending or search) that send instantly on tap.
struct GIFTabView: View {
    let gifs: [KlipySticker]
    let isLoading: Bool
    let sendingID: String?
    let onSelect: (KlipySticker) -> Void
    let onAddToStickers: (KlipySticker) -> Void
    let onLoadMore: () -> Void
    /// Reports the grid's vertical scroll offset, so the panel can auto-expand when the user
    /// scrolls into the content and collapse when they pull down past the top.
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
    
    var body: some View {
        if isLoading, gifs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gifs.isEmpty {
            Text(UntranslatedL10n.screenMediaInputNoResults)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(gifs) { gif in
                        Button {
                            onSelect(gif)
                        } label: {
                            KFAnimatedImage(gif.previewURL)
                                .placeholder { _ in placeholder }
                                .cancelOnDisappear(true)
                                .aspectRatio(1, contentMode: .fit)
                                .opacity(sendingID == gif.id ? 0.4 : 1)
                                .overlay {
                                    if sendingID == gif.id {
                                        ProgressView()
                                    }
                                }
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
                            if gif.id == gifs.last?.id {
                                onLoadMore()
                            }
                        }
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
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(.compound.bgSubtleSecondary)
            .aspectRatio(1, contentMode: .fit)
    }
}
