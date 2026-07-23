//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI
import UIKit

/// Hosts the media panel as a custom keyboard (a `UITextView.inputView`). Presenting it this way
/// makes opening/closing the panel a native keyboard swap — as far as layout is concerned a
/// keyboard is up the whole time, so the composer cannot move, exactly as when switching to the
/// system emoji keyboard.
@MainActor
final class MediaPanelInputView: UIInputView {
    private let hostingController: UIHostingController<AnyView>
    private var heightConstraint: NSLayoutConstraint?
    
    init(rootView: AnyView, height: CGFloat) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: height)), inputViewStyle: .keyboard)
        
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        
        guard let hostingView = hostingController.view else { return }
        hostingView.backgroundColor = .clear
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        
        let heightConstraint = heightAnchor.constraint(equalToConstant: height)
        // Slightly below required so the system can momentarily override it (e.g. during
        // rotation) without raising a constraint conflict.
        heightConstraint.priority = .init(999)
        self.heightConstraint = heightConstraint
        
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func update(rootView: AnyView) {
        hostingController.rootView = rootView
    }
    
    /// Resizes the keyboard the panel presents as. The presenting text view must call
    /// `reloadInputViews()` afterwards so the input system re-measures, animates the frame change
    /// and posts the keyboard notifications that drive the composer's keyboard avoidance.
    func setHeight(_ height: CGFloat) {
        guard let heightConstraint, abs(heightConstraint.constant - height) > 0.5 else { return }
        heightConstraint.constant = height
    }
}

/// Creates the input view lazily and keeps it alive across renders, refreshing its SwiftUI
/// content on demand.
@MainActor
final class MediaPanelInputViewProvider {
    private(set) var view: MediaPanelInputView?
    
    func view(updatedWith rootView: @autoclosure () -> AnyView, height: CGFloat) -> MediaPanelInputView {
        if let view {
            view.update(rootView: rootView())
            return view
        }
        
        let newView = MediaPanelInputView(rootView: rootView(), height: height)
        view = newView
        return newView
    }
}
