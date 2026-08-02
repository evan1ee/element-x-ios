//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A three across grid of thumbnails, newest first, with the month of whatever is at the top
/// of the screen floating over it so you always know roughly when you're looking at.
///
/// Shared by the Photos tab and the media results in search so the two can't drift apart.
struct MediaLibraryGrid: View {
    let assets: [MediaLibraryAsset]
    let isLoading: Bool
    let mediaProvider: MediaProviderProtocol?
    
    let onSelect: (MediaLibraryAsset) -> Void
    let onReachBottom: () -> Void
    /// Offered on a long press when there's somewhere to go. Tapping opens the viewer, which
    /// has no room for a button of its own.
    var onOpenInChat: ((MediaLibraryAsset) -> Void)?
    /// Scrolls away with the pictures, unlike the month, which stays put.
    var header: AnyView?
    
    @State private var headerHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    
    /// Hairline gutters, so the photos themselves carry the screen.
    private static let spacing: CGFloat = 1.5
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 3)
    
    @State private var visibleMonth: Date?
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if let header {
                    header
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                }
                
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    ForEach(assets) { asset in
                        Button {
                            onSelect(asset)
                        } label: {
                            MediaLibraryGridCell(asset: asset, mediaProvider: mediaProvider)
                        }
                        .buttonStyle(.plain)
                        .onAppear { paginateIfNeeded(at: asset) }
                        .contextMenu {
                            if let onOpenInChat {
                                Button(UntranslatedL10n.actionOpenInChat) { onOpenInChat(asset) }
                            }
                        }
                    }
                }
                
                if isLoading {
                    ProgressView().padding()
                }
            }
            // The cells are a uniform square, so the topmost row can be worked out from the
            // offset alone rather than by asking every cell where it is.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                scrollOffset = offset
                updateVisibleMonth(scrollOffset: offset, width: proxy.size.width)
            }
        }
        .overlay(alignment: .top) {
            FloatingDateBadge(dateText: monthText)
                .padding(.top, 8)
        }
    }
    
    /// Nil until the header has scrolled away, so the two badges take it in turns rather than
    /// sitting on top of each other at the top of the list.
    private var monthText: String? {
        guard scrollOffset > headerHeight else { return nil }
        return (visibleMonth ?? assets.first?.timestamp).map(Self.monthFormatter.string(from:))
    }
    
    private func paginateIfNeeded(at asset: MediaLibraryAsset) {
        guard asset.id == assets.last?.id else { return }
        onReachBottom()
    }
    
    private func updateVisibleMonth(scrollOffset: CGFloat, width: CGFloat) {
        guard !assets.isEmpty, width > 0 else { return }
        
        let columnCount = CGFloat(columns.count)
        let cellSize = (width - Self.spacing * (columnCount - 1)) / columnCount
        let rowHeight = cellSize + Self.spacing
        guard rowHeight > 0 else { return }
        
        let row = max(0, Int((scrollOffset - headerHeight) / rowHeight))
        let index = min(max(0, row * columns.count), assets.count - 1)
        visibleMonth = assets[index].timestamp
    }
    
    private static let monthFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()
}
