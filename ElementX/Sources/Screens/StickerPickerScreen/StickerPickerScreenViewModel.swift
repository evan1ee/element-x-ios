//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import PhotosUI
import SwiftUI

typealias StickerPickerScreenViewModelType = StateStoreViewModelV2<StickerPickerScreenViewState, StickerPickerScreenViewAction>

class StickerPickerScreenViewModel: StickerPickerScreenViewModelType, StickerPickerScreenViewModelProtocol {
    private let stickerService: StickerServiceProtocol
    private let timelineController: TimelineControllerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<StickerPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<StickerPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(stickerService: StickerServiceProtocol,
         timelineController: TimelineControllerProtocol,
         mediaProvider: MediaProviderProtocol?,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.stickerService = stickerService
        self.timelineController = timelineController
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: StickerPickerScreenViewState(builtInStickers: stickerService.builtInStickers),
                   mediaProvider: mediaProvider)
        
        Task {
            await loadStickers()
        }
    }
    
    // MARK: - Public
    
    override func process(viewAction: StickerPickerScreenViewAction) {
        switch viewAction {
        case .send(let sticker):
            send(sticker)
        case .addSelectedPhotos:
            addSelectedPhotos()
        case .removeSticker(let sticker):
            removeSticker(sticker)
        case .cancel:
            actionsSubject.send(.dismiss)
        }
    }
    
    // MARK: - Private
    
    private func loadStickers(animated: Bool = false) async {
        let collection = await stickerService.loadStickers()
        
        if animated {
            withAnimation {
                state.userStickers = collection.userStickers
                state.builtInStickers = collection.builtInStickers
            }
        } else {
            state.userStickers = collection.userStickers
            state.builtInStickers = collection.builtInStickers
        }
    }
    
    private func send(_ sticker: Sticker) {
        guard !state.isBusy else {
            return
        }
        
        state.sendingStickerID = sticker.id
        
        Task {
            switch await stickerService.send(sticker, in: timelineController) {
            case .success:
                actionsSubject.send(.dismiss)
            case .failure:
                state.sendingStickerID = nil
                showFailureIndicator()
            }
        }
    }
    
    private func addSelectedPhotos() {
        let items = state.bindings.photosPickerItems
        
        // Resetting the binding below re-triggers the view's onChange.
        guard !items.isEmpty else {
            return
        }
        
        state.bindings.photosPickerItems = []
        state.isAddingSticker = true
        
        Task {
            await addStickers(from: items)
            state.isAddingSticker = false
        }
    }
    
    private func addStickers(from items: [PhotosPickerItem]) async {
        var fileURLs = [URL]()
        var pendingIDs = [String]()
        var failedToLoadCount = 0
        
        for item in items {
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
            
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let fileURL = try? writeToTemporaryFile(data, fileExtension: fileExtension) else {
                failedToLoadCount += 1
                continue
            }
            
            let id = UUID().uuidString
            pendingIDs.append(id)
            fileURLs.append(fileURL)
            
            // Show the image uploading straight away, before the slow upload.
            withAnimation {
                state.uploadingStickers.append(PendingSticker(id: id, image: image))
            }
        }
        
        defer {
            for fileURL in fileURLs {
                try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            }
        }
        
        var summary = await stickerService.addUserStickers(fromMediaAt: fileURLs)
        summary.failed += failedToLoadCount
        
        // Reload before clearing placeholders so each new sticker replaces its
        // placeholder in one animation instead of flashing empty.
        if summary.added > 0 {
            await loadStickers(animated: true)
        }
        
        withAnimation {
            state.uploadingStickers.removeAll { pendingIDs.contains($0.id) }
        }
        
        // Added stickers appear in the grid, so only surface duplicates or failures.
        if summary.duplicates > 0 || summary.failed > 0 {
            showSummaryIndicator(summary)
        }
    }
    
    private func removeSticker(_ sticker: Sticker) {
        guard !state.isBusy else {
            return
        }
        
        state.isAddingSticker = true
        withAnimation { _ = state.removingStickerIDs.insert(sticker.id) }
        
        Task {
            switch await stickerService.removeUserSticker(id: sticker.id) {
            case .success:
                await loadStickers(animated: true)
            case .failure:
                showFailureIndicator()
            }
            withAnimation { state.removingStickerIDs.remove(sticker.id) }
            state.isAddingSticker = false
        }
    }
    
    private func writeToTemporaryFile(_ data: Data, fileExtension: String) throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "sticker-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "Sticker.\(fileExtension)")
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func showFailureIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorUnknown, icon: \.close))
    }
    
    private func showSummaryIndicator(_ summary: StickerBatchSummary) {
        var parts = [String]()
        if summary.added > 0 {
            parts.append(UntranslatedL10n.screenStickerPickerAddedCount(summary.added))
        }
        if summary.duplicates > 0 {
            parts.append(UntranslatedL10n.screenStickerPickerDuplicateCount(summary.duplicates))
        }
        if summary.failed > 0 {
            parts.append(UntranslatedL10n.screenStickerPickerFailedCount(summary.failed))
        }
        
        guard !parts.isEmpty else {
            return
        }
        
        userIndicatorController.submitIndicator(UserIndicator(title: parts.formatted(.list(type: .and, width: .narrow)),
                                                              icon: summary.failed == 0 ? \.check : \.close))
    }
}
