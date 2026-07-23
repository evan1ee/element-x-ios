//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import UIKit

/// Observes the system keyboard so the composer's media panel can present itself as a keyboard of
/// exactly matching size.
@MainActor
final class KeyboardHeightObserver: ObservableObject {
    /// The height of the last real keyboard, `nil` until one has appeared. Heights under 200pt
    /// are ignored so that placeholder input views are never mistaken for the real keyboard.
    @Published private(set) var height: CGFloat?
    /// How much of the screen the keyboard currently covers: 0 when hidden, its full height when
    /// fully shown. Unlike `height` this follows the keyboard's live state, including dismissal.
    @Published private(set) var overlap: CGFloat = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.overlap = 0 }
            .store(in: &cancellables)
    }
    
    private func handle(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let screenBounds = UIScreen.main.bounds
        overlap = min(max(screenBounds.maxY - frame.minY, 0), frame.height)
        
        if frame.height >= 200, overlap > 0 {
            height = frame.height
        }
    }
}
