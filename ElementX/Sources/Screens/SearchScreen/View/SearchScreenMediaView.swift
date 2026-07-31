//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The media library: everything shared across every room, newest first, read from the
/// local index rather than the server.
///
/// Visual assets get a grid and everything else gets rows, because a filename or a URL
/// says more about a file or a link than any thumbnail of one would.
struct SearchScreenMediaView: View {
    let context: SearchScreenViewModel.Context
    
    /// Three across with hairline gutters, so the photos themselves carry the screen.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)
    
    var body: some View {
        VStack(spacing: 0) {
            filterBar
            
            if context.viewState.media.isEmpty {
                if context.viewState.isLoadingMedia {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            } else if showsGrid {
                grid
            } else {
                list
            }
        }
    }
    
    /// A grid only makes sense when everything in it has a picture. A mixed result set
    /// falls back to rows rather than showing placeholder tiles for files and links.
    private var showsGrid: Bool {
        context.viewState.media.allSatisfy(\.category.isVisual)
    }
    
    // MARK: - Filters
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryMenu
                senderMenu
                dateMenu
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
    
    private var categoryMenu: some View {
        Menu {
            Button(UntranslatedL10n.screenSearchMediaTypeAll) { setCategory(nil) }
            ForEach(MediaCategory.allCases, id: \.self) { category in
                Button(category.title) { setCategory(category) }
            }
        } label: {
            filterLabel(context.viewState.bindings.mediaCategory?.title ?? UntranslatedL10n.screenSearchMediaTypeAll,
                        isActive: context.viewState.bindings.mediaCategory != nil)
        }
    }
    
    private var senderMenu: some View {
        Menu {
            Button(UntranslatedL10n.screenSearchMediaFilterAllSenders) { setSender(nil) }
            ForEach(context.viewState.mediaSenders) { sender in
                Button(sender.name) { setSender(sender.id) }
            }
        } label: {
            let name = context.viewState.mediaSenders
                .first { $0.id == context.viewState.bindings.mediaSenderID }?.name
            filterLabel(name ?? UntranslatedL10n.screenSearchMediaFilterAllSenders,
                        isActive: context.viewState.bindings.mediaSenderID != nil)
        }
    }
    
    private var dateMenu: some View {
        Menu {
            ForEach(SearchScreenMediaDateRange.allCases) { range in
                Button(range.title) { setDateRange(range) }
            }
        } label: {
            filterLabel(context.viewState.bindings.mediaDateRange.title,
                        isActive: context.viewState.bindings.mediaDateRange != .anyTime)
        }
    }
    
    private func filterLabel(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.bodySM)
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(isActive ? .compound.textOnSolidPrimary : .compound.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? AnyShapeStyle(.compound.bgAccentRest) : AnyShapeStyle(.compound.bgSubtleSecondary),
                    in: Capsule())
    }
    
    private func setCategory(_ category: MediaCategory?) {
        context.mediaCategory = category
        context.send(viewAction: .mediaFiltersChanged)
    }
    
    private func setSender(_ senderID: String?) {
        context.mediaSenderID = senderID
        context.send(viewAction: .mediaFiltersChanged)
    }
    
    private func setDateRange(_ range: SearchScreenMediaDateRange) {
        context.mediaDateRange = range
        context.send(viewAction: .mediaFiltersChanged)
    }
    
    // MARK: - Results
    
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1.5) {
                ForEach(context.viewState.media) { asset in
                    Button {
                        context.send(viewAction: .selectAsset(asset))
                    } label: {
                        SearchScreenMediaGridCell(asset: asset, mediaProvider: context.mediaProvider)
                    }
                    .buttonStyle(.plain)
                    .onAppear { paginateIfNeeded(at: asset) }
                }
            }
            
            if context.viewState.isLoadingMedia {
                ProgressView().padding()
            }
        }
    }
    
    private var list: some View {
        List {
            ForEach(context.viewState.media) { asset in
                Button {
                    context.send(viewAction: .selectAsset(asset))
                } label: {
                    SearchScreenMediaRow(asset: asset, mediaProvider: context.mediaProvider)
                }
                .buttonStyle(.plain)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .onAppear { paginateIfNeeded(at: asset) }
            }
        }
        .compoundList(.plain)
    }
    
    private func paginateIfNeeded(at asset: SearchScreenMediaAsset) {
        guard asset.id == context.viewState.media.last?.id else { return }
        context.send(viewAction: .reachedMediaBottom)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(UntranslatedL10n.screenSearchMediaEmpty)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(.compound.textPrimary)
            
            Text(UntranslatedL10n.screenSearchMediaEmptyMessage)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One tile in the grid. Falls back to an icon when the thumbnail hasn't been fetched,
/// so the layout doesn't shift once images arrive.
struct SearchScreenMediaGridCell: View {
    /// Roughly a third of the screen at 3x, which is all a cell can show.
    private static let thumbnailSize = CGSize(width: 400, height: 400)
    
    let asset: SearchScreenMediaAsset
    let mediaProvider: MediaProviderProtocol?
    
    var body: some View {
        // The image is sized to the cell rather than to itself. Left to its own devices a
        // loaded photo takes its intrinsic size and blows the grid apart.
        GeometryReader { proxy in
            Group {
                if let source = asset.thumbnailSource {
                    // A size is what makes this ask the server for a scaled thumbnail.
                    // Without one the loader fetches the full original, and fifteen of those
                    // at once is enough to stall the grid indefinitely.
                    LoadableImage(mediaSource: source,
                                  mediaType: .timelineItem(uniqueID: .init(asset.id)),
                                  size: Self.thumbnailSize,
                                  mediaProvider: mediaProvider) {
                        placeholder
                    }
                    .scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let badge = asset.badge {
                    Text(badge)
                        .font(.compound.bodyXSSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private var placeholder: some View {
        Color.compound.bgSubtleSecondary
            .overlay {
                CompoundIcon(asset.category.icon, size: .small, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconQuaternary)
            }
    }
}

/// A row for the things a thumbnail wouldn't help with.
struct SearchScreenMediaRow: View {
    let asset: SearchScreenMediaAsset
    let mediaProvider: MediaProviderProtocol?
    
    var body: some View {
        HStack(spacing: 12) {
            icon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                
                Text(asset.subtitle)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var icon: some View {
        if asset.category.isVisual, let source = asset.thumbnailSource {
            LoadableImage(mediaSource: source,
                          mediaType: .timelineItem(uniqueID: .init(asset.id)),
                          mediaProvider: mediaProvider) {
                Color.compound.bgSubtleSecondary
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            CompoundIcon(asset.category.icon, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconSecondary)
                .frame(width: 44, height: 44)
                .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension MediaCategory {
    var title: String {
        switch self {
        case .photo: UntranslatedL10n.screenSearchMediaTypePhoto
        case .video: UntranslatedL10n.screenSearchMediaTypeVideo
        case .gif: UntranslatedL10n.screenSearchMediaTypeGif
        case .file: UntranslatedL10n.screenSearchMediaTypeFile
        case .link: UntranslatedL10n.screenSearchMediaTypeLink
        case .voice: UntranslatedL10n.screenSearchMediaTypeVoice
        }
    }
    
    var icon: KeyPath<CompoundIcons, Image> {
        switch self {
        case .photo: \.image
        case .video: \.videoCall
        case .gif: \.image
        case .file: \.attachment
        case .link: \.link
        case .voice: \.micOn
        }
    }
}
