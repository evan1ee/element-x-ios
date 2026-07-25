//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI
import UIKit

/// Observes the system keyboard so that the composer can make its own room for it — sizing the
/// media panel to take the keyboard's place exactly, and moving everything on the keyboard's own
/// animation timing rather than alongside it.
@MainActor
final class KeyboardHeightObserver: ObservableObject {
    /// The height of the last real keyboard, `nil` until one has appeared. Heights under 200pt
    /// are ignored so that placeholder input views are never mistaken for the real keyboard.
    @Published private(set) var height: CGFloat?
    /// How much of the screen the keyboard currently covers: 0 when hidden, its full height when
    /// fully shown. Unlike `height` this follows the keyboard's live state, including dismissal.
    @Published private(set) var overlap: CGFloat = 0
    
    /// The duration of the most recent keyboard show/hide animation.
    private(set) var animationDuration: TimeInterval = 0.25
    /// The curve of the most recent keyboard show/hide animation.
    private(set) var animationCurve = UIView.AnimationCurve.easeInOut
    
    /// A SwiftUI animation matching the most recent keyboard transition, so dependent layout can
    /// be updated in lockstep with it.
    var animation: Animation {
        // The keyboard uses a private curve (rawValue 7); its control points aren't public, but
        // this timing curve is the community-standard close match, and falls back cleanly to the
        // documented curves for the rare show/hide that reports one.
        switch animationCurve {
        case .easeInOut: return .timingCurve(0.42, 0, 0.58, 1, duration: animationDuration)
        case .easeIn: return .timingCurve(0.42, 0, 1, 1, duration: animationDuration)
        case .easeOut: return .timingCurve(0, 0, 0.58, 1, duration: animationDuration)
        case .linear: return .linear(duration: animationDuration)
        @unknown default: return .timingCurve(0.38, 0.7, 0.125, 1, duration: animationDuration)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] in
                self?.updateTiming(from: $0)
                self?.overlap = 0
            }
            .store(in: &cancellables)
    }
    
    private func handle(_ notification: Notification) {
        updateTiming(from: notification)
        
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let screenBounds = UIScreen.main.bounds
        overlap = min(max(screenBounds.maxY - frame.minY, 0), frame.height)
        
        if frame.height >= 200, overlap > 0 {
            height = frame.height
        }
    }
    
    private func updateTiming(from notification: Notification) {
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval, duration > 0 {
            animationDuration = duration
        }
        if let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
           let curve = UIView.AnimationCurve(rawValue: rawCurve) {
            animationCurve = curve
        }
    }
}
