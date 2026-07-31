//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Points at the room backing Saved Messages, held in global account data so that
/// every device the user signs in on finds the same room instead of creating its own.
struct SavedMessagesRoomInfo: Codable, Equatable {
    static let eventType = "io.element.saved_messages"
    
    /// Bumped if the shape of this event ever changes. Written by us, and read back
    /// so a future client can recognise an event it may not fully understand.
    static let currentVersion = 1
    
    let roomID: String
    /// Milliseconds since the epoch, matching the units used elsewhere in our account data.
    let createdAt: UInt64
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case createdAt = "created_at"
        case version
    }
    
    init(roomID: String,
         createdAt: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
         version: Int = Self.currentVersion) {
        self.roomID = roomID
        self.createdAt = createdAt
        self.version = version
    }
}
