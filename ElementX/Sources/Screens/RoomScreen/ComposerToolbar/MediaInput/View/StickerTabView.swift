//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import PhotosUI
import SwiftUI

/// The sticker tab: the built-in stickers plus the user's own pack, sent instantly on tap.
/// A picker at the top lets the user add images or GIFs from their library to their pack.
struct StickerTabView: View {
    let stickers: [Sticker]
    let sendingID: String?
    let isAddingStickers: Bool
    @Binding var photosPickerItems: [PhotosPickerItem]
    let mediaProvider: MediaProviderProtocol?
    let onSelect: (Sticker) -> Void
    let onAddPhotos: () -> Void
    /// Reports whether the grid is scrolled to its very top, so the panel can expand/collapse
    /// when the user keeps dragging past the edge.
    var onIsAtTopChange: (Bool) -> Void = { _ in }
    
    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                addTile
                
                ForEach(stickers) { sticker in
                    Button {
                        onSelect(sticker)
                    } label: {
                        stickerImage(for: sticker)
                            .opacity(sendingID == sticker.id ? 0.4 : 1)
                            .overlay {
                                if sendingID == sticker.id {
                                    ProgressView()
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sticker.body)
                }
            }
            .padding(12)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= 0
        } action: { _, isAtTop in
            onIsAtTopChange(isAtTop)
        }
    }
    
    /// A dashed-square "+" tile that opens the photo library to add images/GIFs to the pack.
    private var addTile: some View {
        PhotosPicker(selection: $photosPickerItems,
                     maxSelectionCount: 10,
                     matching: .images,
                     photoLibrary: .shared()) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.compound.borderInteractiveSecondary,
                                  style: StrokeStyle(lineWidth: 2, dash: [6]))
                
                if isAddingStickers {
                    ProgressView()
                } else {
                    // A thin SF Symbol plus: CompoundIcon's fixed weight looks too heavy at this size.
                    Image(systemName: "plus")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.compound.iconSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .disabled(isAddingStickers)
        .accessibilityLabel(UntranslatedL10n.screenMediaInputAddSticker)
        .onChange(of: photosPickerItems) {
            onAddPhotos()
        }
    }
    
    @ViewBuilder
    private func stickerImage(for sticker: Sticker) -> some View {
        switch sticker.source {
        case .bundle(let fileURL):
            if let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        case .media(let url):
            if let mediaSource = try? MediaSourceProxy(url: URL(string: url) ?? URL(filePath: "/"), mimeType: sticker.mimeType) {
                LoadableImage(mediaSource: mediaSource,
                              mediaType: .generic,
                              blurhash: nil,
                              size: nil,
                              mediaProvider: mediaProvider) {
                    placeholder
                }
                .aspectRatio(1, contentMode: .fit)
            } else {
                placeholder
            }
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(.compound.bgSubtleSecondary)
            .aspectRatio(1, contentMode: .fit)
    }
}
