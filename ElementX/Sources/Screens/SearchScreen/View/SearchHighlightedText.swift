//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Emphasises the terms a search matched inside a result's preview.
///
/// The highlight is applied here rather than carried up from the index because
/// results arrive from two sources — the SDK's index and ours — and only one of
/// them reports match ranges. Re-matching against the query treats both alike.
extension AttributedString {
    func highlighting(_ query: String) -> AttributedString {
        let terms = SearchIndexService.terms(in: query)
        guard !terms.isEmpty else { return self }
        
        var result = self
        for term in terms {
            var searchRange = result.startIndex..<result.endIndex
            while let found = result[searchRange].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[found].inlinePresentationIntent = .stronglyEmphasized
                result[found].foregroundColor = .compound.textPrimary
                
                guard found.upperBound < result.endIndex else { break }
                searchRange = found.upperBound..<result.endIndex
            }
        }
        return result
    }
}
