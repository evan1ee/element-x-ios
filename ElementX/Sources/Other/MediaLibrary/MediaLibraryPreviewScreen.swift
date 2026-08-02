//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import Compound
import SwiftUI

/// Full screen pictures, swiping between them in the order the grid shows them.
///
/// Hand rolled rather than QuickLook: QuickLook insists on its own bar — a list button, a
/// filename, an overflow menu and a markup tool — and offers no way to take them away. Here
/// there's nothing but the picture, sharing, and the way back to the conversation.
struct MediaLibraryPreviewScreen: View {
    let assets: [MediaLibraryAsset]
    let mediaProvider: MediaProviderProtocol?
    
    let onDismiss: () -> Void
    let onJumpToMessage: (MediaLibraryAsset) -> Void
    
    @State private var selection: String
    /// Downward drag, which dismisses in place of a close button.
    @State private var dragOffset: CGFloat = 0
    @State private var sharedURL: URL?
    
    init(assets: [MediaLibraryAsset],
         initialAsset: MediaLibraryAsset,
         mediaProvider: MediaProviderProtocol?,
         onDismiss: @escaping () -> Void,
         onJumpToMessage: @escaping (MediaLibraryAsset) -> Void) {
        self.assets = assets
        self.mediaProvider = mediaProvider
        self.onDismiss = onDismiss
        self.onJumpToMessage = onJumpToMessage
        _selection = State(initialValue: initialAsset.id)
    }
    
    private var currentAsset: MediaLibraryAsset? {
        assets.first { $0.id == selection }
    }
    
    var body: some View {
        TabView(selection: $selection) {
            ForEach(assets) { asset in
                MediaLibraryPreviewPage(asset: asset, mediaProvider: mediaProvider)
                    .tag(asset.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .overlay(alignment: .bottom) { buttons }
        .sheet(isPresented: .init(get: { sharedURL != nil }, set: {
            if !$0 {
                sharedURL = nil
            }
        })) {
            if let sharedURL {
                ShareSheet(url: sharedURL)
            }
        }
        .statusBarHidden()
    }
    
    /// Pull down to leave, in place of the close button that isn't wanted here.
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    onDismiss()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }
    
    private var buttons: some View {
        HStack(spacing: 32) {
            Button { share() } label: {
                CompoundIcon(\.share, size: .medium, relativeTo: .compound.bodyLG)
            }
            .accessibilityLabel(L10n.actionShare)
            
            Button {
                guard let currentAsset else { return }
                onJumpToMessage(currentAsset)
            } label: {
                CompoundIcon(\.chat, size: .medium, relativeTo: .compound.bodyLG)
            }
            .accessibilityLabel(UntranslatedL10n.actionOpenInChat)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.black.opacity(0.45), in: .capsule)
        .padding(.bottom, 24)
    }
    
    private func share() {
        guard let currentAsset, let source = currentAsset.mediaSource, let mediaProvider else { return }
        
        Task {
            guard case let .success(handle) = await mediaProvider.loadFileFromSource(source, filename: currentAsset.filename) else { return }
            sharedURL = handle.url
        }
    }
}

/// One picture or clip, fetched on the way past.
private struct MediaLibraryPreviewPage: View {
    let asset: MediaLibraryAsset
    let mediaProvider: MediaProviderProtocol?
    
    @State private var fileURL: URL?
    /// Held for as long as the page is: the handle deletes its file when released.
    @State private var fileHandle: MediaFileHandleProxy?
    @State private var scale: CGFloat = 1
    
    var body: some View {
        Group {
            if let fileURL {
                if asset.category == .video {
                    VideoPlayer(player: AVPlayer(url: fileURL))
                } else {
                    image(at: fileURL)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.id) { await load() }
    }
    
    private func image(at url: URL) -> some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                // Pinch to zoom, snapping back when it's let go so a page can't be left
                // half zoomed with no way to reset it.
                .gesture(MagnifyGesture()
                    .onChanged { scale = max(1, $0.magnification) }
                    .onEnded { _ in withAnimation(.snappy) { scale = 1 } })
        } placeholder: {
            ProgressView().tint(.white)
        }
    }
    
    private func load() async {
        guard fileURL == nil, let source = asset.mediaSource, let mediaProvider else { return }
        guard case let .success(handle) = await mediaProvider.loadFileFromSource(source, filename: asset.filename) else { return }
        
        fileHandle = handle
        fileURL = handle.url
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
