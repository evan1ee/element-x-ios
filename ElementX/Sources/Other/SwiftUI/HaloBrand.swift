//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The fork's own brand colours, for the few places that need the logo's green rather than a
/// Compound token. Compound covers everything else — reach for this only when the thing being
/// drawn is meant to read as the app's mark.
///
/// These mirror the gradient in `AppIcon.icon/Assets/halo-icon-1024.svg`, which is itself the
/// login screen logo's. Change one and change the other.
enum HaloBrand {
    static let gradientTop = Color(red: 0.361, green: 0.776, blue: 0.596) // #5CC698
    static let gradientBottom = Color(red: 0.325, green: 0.702, blue: 0.604) // #53B39A
    
    /// Top to bottom, matching the logo. Sized to whatever it's applied to.
    static let gradient = LinearGradient(colors: [gradientTop, gradientBottom],
                                         startPoint: .top,
                                         endPoint: .bottom)
}
