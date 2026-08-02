//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// One tile in the grid. Falls back to an icon when the thumbnail hasn't been fetched,
/// so the layout doesn't shift once images arrive.
struct MediaLibraryGridCell: View {
    /// Roughly a third of the screen at 3x, which is all a cell can show.
    private static let thumbnailSize = CGSize(width: 400, height: 400)
    
    let asset: MediaLibraryAsset
    let mediaProvider: MediaProviderProtocol?
    
    var body: some View {
        // A square by construction, with the picture drawn inside it. Sizing the other way
        // round — the cell taking the image's size — both blows the grid apart and leaves
        // the tappable area somewhere other than the picture you can see.
        Color.compound.bgSubtleSecondary
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let source = asset.thumbnailSource {
                    // A size is what makes this ask the server for a scaled thumbnail.
                    // Without one the loader fetches the full original, and fifteen of those
                    // at once is enough to stall the grid indefinitely.
                    //
                    // `.generic` rather than `.timelineItem` for the sake of the placeholder:
                    // the timeline's is a spinner captioned "Loading", which is a lot of words
                    // for a tile this size.
                    LoadableImage(mediaSource: source,
                                  mediaType: .generic,
                                  size: Self.thumbnailSize,
                                  mediaProvider: mediaProvider) {
                        loadingPlaceholder
                    }
                    .scaledToFill()
                } else {
                    placeholder
                }
            }
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
            .contentShape(.rect)
    }
    
    /// Shown while the thumbnail is on its way.
    private var loadingPlaceholder: some View {
        Color.compound.bgSubtleSecondary
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .tint(.compound.iconQuaternary)
            }
    }
    
    /// Shown when there's no thumbnail to wait for, where a spinner would never stop.
    private var placeholder: some View {
        Color.compound.bgSubtleSecondary
            .overlay {
                CompoundIcon(asset.category.icon, size: .small, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconQuaternary)
            }
    }
}
