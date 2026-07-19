//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import PhotosUI
import SwiftUI

struct StickerPickerScreen: View {
    @Bindable var context: StickerPickerScreenViewModel.Context
    
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !context.viewState.userStickers.isEmpty {
                    section(title: UntranslatedL10n.screenStickerPickerMyStickers,
                            stickers: context.viewState.userStickers,
                            allowsRemoval: true)
                    
                    section(title: UntranslatedL10n.screenStickerPickerBuiltInStickers,
                            stickers: context.viewState.builtInStickers,
                            allowsRemoval: false)
                } else {
                    grid(for: context.viewState.builtInStickers, allowsRemoval: false)
                }
            }
            .padding(16)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .navigationTitle(UntranslatedL10n.screenStickerPickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionCancel) {
                    context.send(viewAction: .cancel)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if context.viewState.isAddingSticker {
                    ProgressView()
                } else {
                    PhotosPicker(selection: $context.photosPickerItems,
                                 maxSelectionCount: 10,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        CompoundIcon(\.plus)
                    }
                    .disabled(context.viewState.isBusy)
                    .accessibilityLabel(UntranslatedL10n.screenStickerPickerAddSticker)
                    .accessibilityIdentifier(A11yIdentifiers.stickerPickerScreen.addSticker)
                }
            }
        }
        .onChange(of: context.photosPickerItems) {
            context.send(viewAction: .addSelectedPhotos)
        }
    }
    
    private func section(title: String, stickers: [Sticker], allowsRemoval: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.compound.bodySMSemibold)
                .foregroundColor(.compound.textSecondary)
            
            grid(for: stickers, allowsRemoval: allowsRemoval)
        }
    }
    
    private func grid(for stickers: [Sticker], allowsRemoval: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(stickers) { sticker in
                Button {
                    context.send(viewAction: .send(sticker))
                } label: {
                    stickerImage(for: sticker)
                        .overlay {
                            if context.viewState.sendingStickerID == sticker.id {
                                ProgressView()
                            }
                        }
                }
                .disabled(context.viewState.isBusy)
                .accessibilityLabel(sticker.body)
                .contextMenu {
                    if allowsRemoval {
                        Button(role: .destructive) {
                            context.send(viewAction: .removeSticker(sticker))
                        } label: {
                            Label(L10n.actionRemove, icon: \.delete)
                        }
                    }
                }
            }
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
                              mediaProvider: context.mediaProvider) {
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

// MARK: - Previews

struct StickerPickerScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    
    static var previews: some View {
        ElementNavigationStack {
            StickerPickerScreen(context: viewModel.context)
        }
        .previewDisplayName("Stickers")
    }
    
    static func makeViewModel() -> StickerPickerScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.accountDataEventTypeReturnValue = .success(nil)
        
        let stickerService = StickerService(clientProxy: clientProxy,
                                            mediaUploadingPreprocessor: MediaUploadingPreprocessor(appSettings: AppSettings.volatile()))
        
        return StickerPickerScreenViewModel(stickerService: stickerService,
                                            timelineController: TimelineControllerMock(.init()),
                                            mediaProvider: MediaProviderMock(.init()),
                                            userIndicatorController: UserIndicatorControllerMock())
    }
}
