//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

enum SavedMessagesServiceError: Error {
    case roomCreationFailed
    case accountDataUpdateFailed
    case roomUnavailable
    case sendFailed
}

// sourcery: AutoMockable
protocol SavedMessagesServiceProtocol {
    /// The room backing Saved Messages, `nil` until it has been resolved or created.
    var roomIDPublisher: CurrentValuePublisher<String?, Never> { get }
    
    /// Resolves the room from account data, creating and recording it when the account
    /// doesn't have one yet. Waits for the first sync so that a cold launch doesn't
    /// create a duplicate. Safe to call repeatedly — concurrent calls share one attempt,
    /// and a resolved room short circuits.
    @discardableResult
    func setUp() async -> Result<String, SavedMessagesServiceError>
    
    /// Kicks off `setUp` in the background, for callers that don't need the result.
    func start()
    
    /// Whether the given room is the one backing Saved Messages. `false` until `setUp`
    /// has resolved, so callers that need certainty should observe `roomIDPublisher`.
    func isSavedMessagesRoom(_ roomID: String) -> Bool
    
    /// Sends the given event content to Saved Messages, resolving the room first if needed.
    func save(_ content: RoomMessageEventContentWithoutRelation) async -> Result<Void, SavedMessagesServiceError>
}
