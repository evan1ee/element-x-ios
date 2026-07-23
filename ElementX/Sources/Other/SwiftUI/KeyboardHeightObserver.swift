//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import UIKit

/// Observes the system keyboard so a replacement view (e.g. the composer's media panel) can match
/// its height and transition timing instead of guessing at both.
@MainActor
final class KeyboardHeightObserver: ObservableObject {
    /// The most recently reported system keyboard height, `nil` until it has appeared at least once.
    @Published private(set) var height: CGFloat?
    /// The duration of the most recent keyboard show/hide animation, so a replacement view's own
    /// transition can run on the same clock.
    @Published private(set) var animationDuration: TimeInterval = 0.25
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)
    }
    
    private func handle(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              frame.height > 0 else { return }
        height = frame.height
        
        if let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval, duration > 0 {
            animationDuration = duration
        }
    }
}
