//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct StickerPickerScreen: View {
    @Bindable var context: StickerPickerScreenViewModel.Context
    
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(context.viewState.stickers) { sticker in
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
                    .disabled(context.viewState.isSending)
                    .accessibilityLabel(sticker.body)
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
        }
    }
    
    @ViewBuilder
    private func stickerImage(for sticker: BuiltInSticker) -> some View {
        if let image = UIImage(contentsOfFile: sticker.fileURL.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .foregroundColor(.compound.bgSubtleSecondary)
                .aspectRatio(1, contentMode: .fit)
        }
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
        let stickerService = StickerService(clientProxy: ClientProxyMock(.init()))
        
        return StickerPickerScreenViewModel(stickerService: stickerService,
                                            roomProxy: JoinedRoomProxyMock(.init()),
                                            threadRootEventID: nil,
                                            userIndicatorController: UserIndicatorControllerMock())
    }
}
