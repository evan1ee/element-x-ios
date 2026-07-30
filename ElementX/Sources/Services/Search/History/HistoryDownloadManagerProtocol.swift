//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// Where the download has got to overall.
enum HistoryDownloadStatus: Equatable, Sendable {
    case notStarted
    /// Working out what there is to do before any room has been touched.
    case preparing
    case downloading
    /// Stopped by the user, or by a condition they set such as Wi-Fi only.
    case paused(HistoryDownloadPauseReason)
    case completed
    case error(HistoryDownloadError)
}

enum HistoryDownloadPauseReason: Equatable, Sendable {
    case user
    /// Waiting for Wi-Fi because the user asked not to use cellular.
    case waitingForWiFi
    case offline
}

enum HistoryDownloadError: Equatable, Sendable {
    case network
    case server
    case storageFull
    case authenticationExpired
    
    /// Whether trying again could plausibly get further, which decides if the UI
    /// offers a retry.
    var isRetryable: Bool {
        switch self {
        case .network, .server: true
        case .storageFull, .authenticationExpired: false
        }
    }
}

/// How far a single room has got. Persisted, so a relaunch resumes rather than restarts.
struct RoomHistoryState: Equatable, Sendable, Codable {
    enum Status: String, Equatable, Sendable, Codable {
        case waiting
        case downloading
        case complete
        case paused
        case error
    }
    
    let roomID: String
    var status: Status = .waiting
    /// Events indexed from this room so far.
    var messagesIndexed = 0
    /// What the room claims to hold, when the server has told us. Nil until known,
    /// which is why the UI treats the estimate as optional.
    var estimatedTotal: Int?
    var lastUpdated: Date?
    
    var fractionComplete: Double? {
        guard let estimatedTotal, estimatedTotal > 0 else { return nil }
        return min(Double(messagesIndexed) / Double(estimatedTotal), 1)
    }
}

/// The snapshot the settings screen renders. Deliberately free of SDK types and of
/// anything resembling a sync or pagination token — the UI shows progress, not plumbing.
struct HistoryDownloadProgress: Equatable, Sendable {
    var status: HistoryDownloadStatus = .notStarted
    var roomsCompleted = 0
    var roomsTotal = 0
    var messagesIndexed = 0
    /// The room being worked on, for the advanced section.
    var activeRoomName: String?
    var queueLength = 0
    var lastSyncDate: Date?
    var lastError: HistoryDownloadError?
    
    /// Overall completion, by rooms rather than messages: message totals aren't known
    /// up front, so counting rooms is the honest measure.
    var fractionComplete: Double {
        guard roomsTotal > 0 else { return 0 }
        return Double(roomsCompleted) / Double(roomsTotal)
    }
    
    var isComplete: Bool {
        roomsTotal > 0 && roomsCompleted == roomsTotal
    }
}

/// Bytes on disk, split the way the settings screen shows them.
struct HistoryStorageUsage: Equatable, Sendable {
    var databaseBytes: Int64 = 0
    var mediaCacheBytes: Int64 = 0
    
    var totalBytes: Int64 {
        databaseBytes + mediaCacheBytes
    }
}

// sourcery: AutoMockable
protocol HistoryDownloadManagerProtocol: AnyObject {
    var progressPublisher: CurrentValuePublisher<HistoryDownloadProgress, Never> { get }
    var roomStatesPublisher: CurrentValuePublisher<[String: RoomHistoryState], Never> { get }
    
    /// Begins or resumes downloading. Safe to call when already running.
    func start()
    func pause()
    func resume()
    /// Re-queues rooms that stopped on an error, leaving completed ones alone.
    func retryFailed()
    
    /// Throws away the index and starts again, for when it's suspected of being wrong.
    func rebuildSearchIndex() async
    /// Drops indexed history without touching the messages themselves.
    func clearOfflineHistory() async
    
    func storageUsage() async -> HistoryStorageUsage
}
