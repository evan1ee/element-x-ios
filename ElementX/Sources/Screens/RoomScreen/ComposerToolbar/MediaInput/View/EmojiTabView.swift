//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The emoji tab: a sectioned grid (recents first, then categories) with sticky headers, and a
/// bottom bar (category jump + delete key) pinned to the bottom. Tapping an emoji inserts it and
/// keeps the panel open.
struct EmojiTabView: View {
    let categories: [EmojiCategory]
    let onSelect: (String) -> Void
    /// Deletes one character/emoji before the composer's caret. Called once per tap, and
    /// repeatedly while the delete key is held (like the system keyboard's backspace).
    let onDeleteBackward: () -> Void
    /// Reports the grid's vertical scroll offset, so the panel can auto-expand when the user
    /// scrolls into the content and collapse when they pull down past the top.
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }
    
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 8)]
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8, pinnedViews: [.sectionHeaders]) {
                        ForEach(categories) { category in
                            Section {
                                ForEach(items(for: category), id: \.id) { item in
                                    Button {
                                        onSelect(item.emoji.unicode)
                                    } label: {
                                        Text(item.emoji.unicode)
                                            .font(.system(size: 30))
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel(item.emoji.label)
                                }
                            } header: {
                                Text(EmojiTabView.title(for: category))
                                    .font(.compound.bodyMDSemibold)
                                    .foregroundStyle(.compound.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(Color.compound.bgCanvasDefault)
                            }
                            .id(category.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    onScrollOffsetChange(offset)
                }
                
                bottomBar(proxy: proxy)
            }
        }
    }
    
    /// Category jump buttons (when there's more than one category) plus a delete key, always
    /// available while the emoji tab is showing — mirrors the system emoji keyboard's layout.
    private func bottomBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            if categories.count > 1 {
                ForEach(categories) { category in
                    Button {
                        withAnimation {
                            proxy.scrollTo(category.id, anchor: .top)
                        }
                    } label: {
                        Image(systemName: EmojiTabView.symbol(for: category))
                            .font(.system(size: 18))
                            .foregroundStyle(.compound.iconSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(EmojiTabView.title(for: category))
                }
            }
            
            DeleteBackwardButton(action: onDeleteBackward)
        }
        .background {
            Color.compound.bgCanvasDefault
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        }
    }
    
    private func items(for category: EmojiCategory) -> [(id: String, emoji: EmojiItem)] {
        // Recents duplicate emojis from other categories, so combine category + index for a
        // globally unique id.
        category.emojis.enumerated().map { (id: "\(category.id)-\($0.offset)", emoji: $0.element) }
    }
    
    static func title(for category: EmojiCategory) -> String {
        switch category.id {
        case EmojiCategory.frequentlyUsedCategoryIdentifier: UntranslatedL10n.screenMediaInputCategoryFrequentlyUsed
        case "people": UntranslatedL10n.screenMediaInputCategoryPeople
        case "nature": UntranslatedL10n.screenMediaInputCategoryNature
        case "foods": UntranslatedL10n.screenMediaInputCategoryFood
        case "activity": UntranslatedL10n.screenMediaInputCategoryActivity
        case "places": UntranslatedL10n.screenMediaInputCategoryPlaces
        case "objects": UntranslatedL10n.screenMediaInputCategoryObjects
        case "symbols": UntranslatedL10n.screenMediaInputCategorySymbols
        case "flags": UntranslatedL10n.screenMediaInputCategoryFlags
        default: ""
        }
    }
    
    static func symbol(for category: EmojiCategory) -> String {
        switch category.id {
        case EmojiCategory.frequentlyUsedCategoryIdentifier: "clock"
        case "people": "face.smiling"
        case "nature": "leaf"
        case "foods": "fork.knife"
        case "activity": "gamecontroller"
        case "places": "car"
        case "objects": "lightbulb"
        case "symbols": "heart"
        case "flags": "flag"
        default: "questionmark"
        }
    }
}

/// A backspace key matching the system emoji keyboard's: one tap deletes once, holding it down
/// repeats the deletion until released.
private struct DeleteBackwardButton: View {
    let action: () -> Void
    
    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?
    
    var body: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 18))
            .foregroundStyle(.compound.iconSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.a11yDelete)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in beginPress() }
                .onEnded { _ in endPress() })
    }
    
    private func beginPress() {
        guard !isPressing else { return }
        isPressing = true
        action()
        
        repeatTask?.cancel()
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    
    private func endPress() {
        isPressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}
