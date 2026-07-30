//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Identifies a backup destination.
///
/// Lives beside the settings rather than with the rest of the backup code because
/// `AppSettings` persists it, and the app extensions compile `AppSettings` without
/// compiling the backup engine.
///
/// The raw values are written into preferences and into every backup manifest, so
/// they are a wire format: add cases, never rename them.
nonisolated enum BackupProviderID: String, Codable, Sendable, CaseIterable {
    case iCloud
    case localFile
    case webDAV
}
