//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Kingfisher
import SwiftUI

struct StickerDiscoveryScreen: View {
    @Bindable var context: StickerDiscoveryScreenViewModel.Context
    
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]
    
    var body: some View {
        mainContent
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationTitle(UntranslatedL10n.screenStickerDiscoveryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $context.searchQuery,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: UntranslatedL10n.screenStickerDiscoverySearchPlaceholder)
            .autocorrectionDisabled()
            .onChange(of: context.searchQuery) {
                context.send(viewAction: .search)
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if context.viewState.isLoading, context.viewState.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if context.viewState.hasFailed {
            errorState
        } else if context.viewState.showsEmptyState {
            emptyState
        } else {
            grid
        }
    }
    
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(context.viewState.results) { sticker in
                    stickerButton(for: sticker)
                        .onAppear {
                            if sticker.id == context.viewState.results.last?.id {
                                context.send(viewAction: .loadMore)
                            }
                        }
                }
            }
            .padding(16)
            
            if context.viewState.isLoadingMore {
                ProgressView()
                    .padding()
            }
        }
    }
    
    private func stickerButton(for sticker: KlipySticker) -> some View {
        let isAdding = context.viewState.addingStickerIDs.contains(sticker.id)
        let isSending = context.viewState.sendingStickerID == sticker.id
        
        return Button {
            context.send(viewAction: .send(sticker))
        } label: {
            // Kingfisher animates the GIF preview and caches it to memory + disk, so
            // scrolling back doesn't re-download and cells appear instantly once cached.
            KFAnimatedImage(sticker.previewURL)
                .placeholder { _ in placeholder }
                .cancelOnDisappear(true)
                .fade(duration: 0.15)
                .aspectRatio(1, contentMode: .fit)
                .opacity(isAdding ? 0.4 : 1)
                .overlay {
                    if isSending || isAdding {
                        ProgressView()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(context.viewState.isSending)
        .accessibilityLabel(sticker.title)
        .contextMenu {
            Button {
                context.send(viewAction: .add(sticker))
            } label: {
                Label(UntranslatedL10n.screenStickerDiscoveryAddToMyStickers, icon: \.plus)
            }
        }
    }
    
    private var emptyState: some View {
        Text(UntranslatedL10n.screenStickerDiscoveryEmpty)
            .font(.compound.bodyLG)
            .foregroundStyle(.compound.textSecondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorState: some View {
        VStack(spacing: 16) {
            Text(UntranslatedL10n.screenStickerDiscoveryError)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(L10n.actionRetry) {
                context.send(viewAction: .retry)
            }
            .buttonStyle(.compound(.secondary))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var placeholder: some View {
        Rectangle()
            .foregroundColor(.compound.bgSubtleSecondary)
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Previews

struct StickerDiscoveryScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    
    static var previews: some View {
        ElementNavigationStack {
            StickerDiscoveryScreen(context: viewModel.context)
        }
        .previewDisplayName("Discovery")
    }
    
    static func makeViewModel() -> StickerDiscoveryScreenViewModel {
        let klipyService = KlipyServiceMock()
        let stickers = (0..<6).compactMap { index -> KlipySticker? in
            guard let previewURL = URL(string: "https://static.klipy.com/preview-\(index).gif"),
                  let fileURL = URL(string: "https://static.klipy.com/file-\(index).gif") else {
                return nil
            }
            return KlipySticker(id: "sticker-\(index)",
                                title: "Sticker \(index)",
                                previewURL: previewURL,
                                fileURL: fileURL,
                                width: 480,
                                height: 480,
                                size: 80000,
                                mimeType: "image/gif")
        }
        klipyService.searchQueryPageReturnValue = .success(.init(stickers: stickers, hasNextPage: false, nextPage: 2))
        
        return StickerDiscoveryScreenViewModel(klipyService: klipyService,
                                               stickerService: StickerServiceMock(),
                                               timelineController: TimelineControllerMock(.init()),
                                               mediaProvider: MediaProviderMock(.init()),
                                               userIndicatorController: UserIndicatorControllerMock())
    }
}
