//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Foundation
import PhotosUI
import SwiftUI

// The GIF and sticker halves of the media panel live in the fork's own file: they're what pushed
// the view model past SwiftLint's type body limit, and keeping them out of the upstream file means
// upstream changes to the composer never collide with them.
extension ComposerToolbarViewModel {
    // MARK: GIFs
    
    func loadGIFs(reset: Bool) {
        guard let gifService else { return }
        
        let query = state.bindings.mediaSearchQuery
        let page = reset ? 1 : mediaGIFPage + 1
        
        if reset {
            mediaGIFPage = 1
            // Trending is kept between panel opens, so reopening the tab shows the grid it had
            // rather than an empty one, and only goes to the network once that has gone stale.
            if query.isBlank, let cachedTrendingGIFs {
                applyGIFResults(cachedTrendingGIFs, reset: true)
                guard isTrendingGIFCacheStale else {
                    mediaGIFLoadTask?.cancel()
                    state.mediaGIFsLoading = false
                    return
                }
            }
            state.mediaGIFsLoading = true
        }
        
        mediaGIFLoadTask?.cancel()
        mediaGIFLoadTask = Task { [weak self] in
            guard let self else { return }
            let result = await gifService.search(query: query, page: page)
            guard !Task.isCancelled, query == state.bindings.mediaSearchQuery else { return }
            
            if case let .success(results) = result {
                mediaGIFPage = page
                if reset, query.isBlank {
                    cacheTrendingGIFs(results)
                }
                applyGIFResults(results, reset: reset)
            } else if reset, !query.isBlank || cachedTrendingGIFs == nil {
                // A failed refresh leaves whatever is on screen alone; a failed search has
                // nothing to fall back on, so it shows the empty state instead.
                state.mediaGIFs = []
                state.mediaGIFsHasMore = false
            }
            state.mediaGIFsLoading = false
        }
    }
    
    func applyGIFResults(_ results: KlipySearchResults, reset: Bool) {
        if reset {
            state.mediaGIFs = results.stickers
        } else {
            let existingIDs = Set(state.mediaGIFs.map(\.id))
            state.mediaGIFs += results.stickers.filter { !existingIDs.contains($0.id) }
        }
        state.mediaGIFsHasMore = results.hasNextPage
    }
    
    var isTrendingGIFCacheStale: Bool {
        guard let trendingGIFsFetchDate else { return true }
        return Date.now.timeIntervalSince(trendingGIFsFetchDate) > Self.trendingGIFCacheLifetime
    }
    
    func cacheTrendingGIFs(_ results: KlipySearchResults) {
        cachedTrendingGIFs = results
        trendingGIFsFetchDate = .now
    }
    
    /// Fetches trending GIFs while the user is on another tab, so opening the GIF tab shows
    /// content straight away instead of starting from an empty grid.
    func prefetchTrendingGIFs() {
        guard let gifService, cachedTrendingGIFs == nil, trendingGIFPrefetchTask == nil else { return }
        
        trendingGIFPrefetchTask = Task { [weak self] in
            guard let self else { return }
            defer { trendingGIFPrefetchTask = nil }
            
            guard case let .success(results) = await gifService.search(query: "", page: 1) else { return }
            cacheTrendingGIFs(results)
            
            // The user may have reached the tab while this was in flight.
            if state.inputMode.mediaTab == .gif, state.mediaGIFs.isEmpty, state.bindings.mediaSearchQuery.isBlank {
                applyGIFResults(results, reset: true)
                state.mediaGIFsLoading = false
            }
        }
    }
    
    func loadMoreGIFs() {
        guard state.inputMode.mediaTab == .gif, state.mediaGIFsHasMore, !state.mediaGIFsLoading else { return }
        loadGIFs(reset: false)
    }
    
    /// Sends a GIF the way a picked image is sent: the panel closes at once and the timeline's own
    /// local echo carries the upload progress, retry and failure states from there. Nothing is
    /// shown in the panel, so the user can keep sending without waiting on the previous one.
    ///
    /// The bytes are normally already in hand from `prefetchMediaGIF`, which is what lets the GIF
    /// appear in the timeline the moment it's tapped rather than a download later.
    func sendMediaGIF(_ gif: KlipySticker) {
        guard let gifService, let stickerService, let timelineController else { return }
        
        showKeyboard()
        
        Task { [weak self] in
            guard let self else { return }
            
            var gifData = preloadedGIFs[gif.id]
            if gifData == nil {
                guard case let .success(downloaded) = await gifService.downloadImage(from: gif.fileURL) else {
                    showMediaFailureIndicator()
                    return
                }
                gifData = downloaded
            }
            
            guard let gifData else { return }
            
            if case .failure = await stickerService.sendImage(data: gifData,
                                                              filename: gif.uploadFilename,
                                                              in: timelineController) {
                showMediaFailureIndicator()
            }
        }
    }
    
    /// Queues a GIF that has scrolled into view for download at upload quality, so that tapping it
    /// goes straight to the timeline. Only what the user actually sees is fetched, and only up to
    /// `maxPreloadedGIFs` of it — past that, tapping falls back to downloading on demand.
    func prefetchMediaGIF(_ gif: KlipySticker) {
        guard gifService != nil,
              preloadedGIFs.count < Self.maxPreloadedGIFs,
              preloadedGIFs[gif.id] == nil,
              !queuedGIFPrefetches.contains(where: { $0.id == gif.id }) else {
            return
        }
        
        queuedGIFPrefetches.append(gif)
        
        guard gifPrefetchTask == nil, let gifService else { return }
        
        gifPrefetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                queuedGIFPrefetches.removeAll()
                gifPrefetchTask = nil
            }
            
            // One at a time: these are full-size GIFs, and running them in parallel would queue
            // the grid's own previews behind them, making the tab slower to fill in.
            while !queuedGIFPrefetches.isEmpty, preloadedGIFs.count < Self.maxPreloadedGIFs {
                let next = queuedGIFPrefetches.removeFirst()
                guard preloadedGIFs[next.id] == nil else { continue }
                
                if case let .success(data) = await gifService.downloadImage(from: next.fileURL) {
                    preloadedGIFs[next.id] = data
                }
            }
        }
    }
    
    /// Downloads a discovered GIF and adds it to the user's sticker pack (preserving animation),
    /// then refreshes the sticker grid. Mirrors the discover screen's "Add to My Stickers" action.
    func addMediaGIF(_ gif: KlipySticker) {
        guard let gifService, let stickerService, !state.isAddingStickers else { return }
        state.isAddingStickers = true
        
        Task { [weak self] in
            guard let self else { return }
            defer { state.isAddingStickers = false }
            
            guard case let .success(data) = await gifService.downloadImage(from: gif.fileURL) else {
                showStickerAddSummary(StickerBatchSummary(failed: 1))
                return
            }
            let body = gif.title.isEmpty ? "GIF" : gif.title
            let summary = await stickerService.addExternalSticker(imageData: data,
                                                                  body: body,
                                                                  width: gif.width,
                                                                  height: gif.height,
                                                                  mimeType: gif.mimeType)
            if summary.added > 0 {
                let collection = await stickerService.loadStickers()
                state.mediaStickers = collection.userStickers + collection.builtInStickers
            }
            showStickerAddSummary(summary)
        }
    }
    
    // MARK: Stickers
    
    func loadStickers() {
        guard let stickerService else { return }
        Task { [weak self] in
            guard let self else { return }
            let collection = await stickerService.loadStickers()
            state.mediaStickers = collection.userStickers + collection.builtInStickers
        }
    }
    
    func sendMediaSticker(_ sticker: Sticker) {
        guard let stickerService, let timelineController, state.sendingMediaItemID == nil else { return }
        state.sendingMediaItemID = sticker.id
        
        Task { [weak self] in
            guard let self else { return }
            defer { state.sendingMediaItemID = nil }
            
            if case .failure = await stickerService.send(sticker, in: timelineController) {
                showMediaFailureIndicator()
            }
        }
    }
    
    func showMediaFailureIndicator() {
        mediaUserIndicatorController?.submitIndicator(UserIndicator(title: L10n.errorUnknown, icon: \.close))
    }
    
    /// Adds the images/GIFs picked in the sticker tab to the user's pack, reusing the batch
    /// upload with content-hash dedup, then refreshes the grid so the new stickers appear.
    func addStickerPhotos() {
        guard let stickerService else { return }
        let items = state.bindings.stickerPhotosPickerItems
        // Resetting the binding below re-triggers the view's onChange.
        guard !items.isEmpty else { return }
        state.bindings.stickerPhotosPickerItems = []
        state.isAddingStickers = true
        
        Task { [weak self] in
            guard let self else { return }
            defer { state.isAddingStickers = false }
            
            var fileURLs = [URL]()
            var failedToLoadCount = 0
            for item in items {
                let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
                guard let data = try? await item.loadTransferable(type: Data.self),
                      UIImage(data: data) != nil,
                      let fileURL = try? writeStickerToTemporaryFile(data, fileExtension: fileExtension) else {
                    failedToLoadCount += 1
                    continue
                }
                fileURLs.append(fileURL)
            }
            defer {
                for fileURL in fileURLs {
                    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
                }
            }
            
            var summary = await stickerService.addUserStickers(fromMediaAt: fileURLs)
            summary.failed += failedToLoadCount
            
            if summary.added > 0 {
                let collection = await stickerService.loadStickers()
                state.mediaStickers = collection.userStickers + collection.builtInStickers
            }
            showStickerAddSummary(summary)
        }
    }
    
    func writeStickerToTemporaryFile(_ data: Data, fileExtension: String) throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "sticker-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "Sticker.\(fileExtension)")
        try data.write(to: fileURL)
        return fileURL
    }
    
    func showStickerAddSummary(_ summary: StickerBatchSummary) {
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
        guard !parts.isEmpty else { return }
        
        mediaUserIndicatorController?.submitIndicator(UserIndicator(title: parts.formatted(.list(type: .and, width: .narrow)),
                                                                    icon: summary.failed == 0 ? \.check : \.close))
    }
}
