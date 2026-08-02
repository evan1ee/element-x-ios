//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

/// Every picture and clip shared across every room, newest first, read from the local index.
///
/// No title bar: the pictures run the full height of the screen, with the month floating over
/// them, which is as much chrome as a library like this needs.
struct PhotosScreen: View {
    @ObservedObject var context: PhotosScreenViewModel.Context
    
    var body: some View {
        Group {
            if context.viewState.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .background(.compound.bgCanvasDefault)
        .onAppear { context.send(viewAction: .appeared) }
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            if context.viewState.isHistoryIncomplete {
                incompleteHistoryBanner
            }
            
            MediaLibraryGrid(assets: context.viewState.assets,
                             isLoading: context.viewState.isLoading,
                             mediaProvider: context.mediaProvider,
                             onSelect: { context.send(viewAction: .selectAsset($0)) },
                             onReachBottom: { context.send(viewAction: .reachedBottom) },
                             onOpenInChat: { context.send(viewAction: .openInChat($0)) },
                             header: AnyView(roomFilter))
        }
        .fullScreenCover(item: $context.previewedAsset) { asset in
            MediaLibraryPreviewScreen(assets: context.viewState.assets,
                                      initialAsset: asset,
                                      mediaProvider: context.mediaProvider,
                                      onDismiss: { context.previewedAsset = nil },
                                      onJumpToMessage: { context.send(viewAction: .openInChat($0)) })
                .ignoresSafeArea()
        }
    }
    
    /// Wears the month badge's clothes, but sits in the scroll view rather than over it, so
    /// it gets out of the way once you're actually looking at pictures.
    private var roomFilter: some View {
        Menu {
            Button(UntranslatedL10n.screenPhotosAllChats) { context.send(viewAction: .selectRoom(nil)) }
            
            ForEach(context.viewState.rooms) { room in
                Button(room.name) { context.send(viewAction: .selectRoom(room.id)) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(context.viewState.roomFilterTitle)
                CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.bodySM)
            }
            .font(.compound.bodySMSemibold)
            .foregroundStyle(.compound.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.compound.bgCanvasDefault, in: .capsule)
            .shadow(color: Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.1), radius: 12, x: 0, y: 4)
        }
        .padding(.vertical, 8)
    }
    
    private var incompleteHistoryBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            CompoundIcon(\.download, size: .xSmall, relativeTo: .compound.bodySM)
                .foregroundStyle(.compound.iconSecondary)
            
            Text(UntranslatedL10n.screenPhotosIncompleteHistory)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.compound.bgSubtleSecondary)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(UntranslatedL10n.screenPhotosEmptyTitle)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(.compound.textPrimary)
            
            Text(UntranslatedL10n.screenPhotosEmptyMessage)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

struct PhotosScreen_Previews: PreviewProvider, TestablePreview {
    static let emptyViewModel = makeViewModel()
    static let downloadingViewModel = makeViewModel(status: .downloading)
    
    static var previews: some View {
        ElementNavigationStack {
            PhotosScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            PhotosScreen(context: downloadingViewModel.context)
        }
        .previewDisplayName("Indexing")
    }
    
    /// An empty index. Thumbnails come from the server, which a snapshot can't wait on, so the
    /// grid itself is covered by the tests around the browse query rather than here.
    static func makeViewModel(status: HistoryDownloadStatus = .completed) -> PhotosScreenViewModel {
        let searchIndexService = SearchIndexServiceMock()
        searchIndexService.browseReturnValue = []
        searchIndexService.roomsWithMediaInReturnValue = []
        
        let historyDownloadManager = HistoryDownloadManagerMock()
        historyDownloadManager.underlyingProgressPublisher = CurrentValueSubject<HistoryDownloadProgress, Never>(.init(status: status)).asCurrentValuePublisher()
        historyDownloadManager.underlyingRoomStatesPublisher = CurrentValueSubject<[String: RoomHistoryState], Never>([:]).asCurrentValuePublisher()
        
        return PhotosScreenViewModel(clientProxy: ClientProxyMock(.init()),
                                     mediaProvider: MediaProviderMock(.init()),
                                     searchIndexService: searchIndexService,
                                     historyDownloadManager: historyDownloadManager)
    }
}
