//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum StickerDiscoveryScreenViewModelAction {
    case dismiss
    case sent
}

struct StickerDiscoveryScreenViewState: BindableState {
    var results: [KlipySticker] = []
    var isLoading = false
    var isLoadingMore = false
    var hasNextPage = false
    var hasFailed = false
    var sendingStickerID: String?
    var addingStickerIDs: Set<String> = []
    
    var bindings = StickerDiscoveryScreenViewStateBindings()
    
    var isSending: Bool {
        sendingStickerID != nil
    }
    
    /// No results and nothing in flight — either the query has no matches or an initial load hasn't happened.
    var showsEmptyState: Bool {
        results.isEmpty && !isLoading && !hasFailed
    }
}

struct StickerDiscoveryScreenViewStateBindings {
    var searchQuery = ""
}

enum StickerDiscoveryScreenViewAction {
    case search
    case send(KlipySticker)
    case add(KlipySticker)
    case loadMore
    case retry
    case cancel
}
