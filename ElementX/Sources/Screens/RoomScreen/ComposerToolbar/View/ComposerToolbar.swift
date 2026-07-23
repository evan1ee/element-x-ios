//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import MatrixRustSDK
import SwiftUI
import WysiwygComposer

struct ComposerToolbar: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The vertical space available to the composer and its media panel, measured by the room
    /// screen. `.infinity` until measured, meaning "no cap yet".
    @Environment(\.availableComposerHeight) private var availableComposerHeight
    /// The window's bottom safe-area inset, measured by the room screen alongside the above.
    @Environment(\.composerBottomSafeAreaInset) private var composerBottomSafeAreaInset
    
    @ObservedObject var context: ComposerToolbarViewModel.Context
    /// Measures the real system keyboard so the media panel can present itself as a keyboard of
    /// exactly matching size.
    @StateObject private var keyboardHeightObserver = KeyboardHeightObserver()
    
    @FocusState private var composerFocused: Bool
    @State private var frame: CGRect = .zero
    /// The measured height of the composer bar, so the media panel can leave room for it.
    @State private var composerBarHeight: CGFloat = 0
    
    /// - When Liquid Glass is available, the buttons and composer are all 44pt x 44pt.
    /// - On iOS 18 and below, the main buttons are 30pt x 30pt and the composer is 42pt high, so some
    ///   additional padding is required to centre the buttons vertically when there's a single line of text,
    ///   but preserve their position (using bottom alignment) when there's 2 or more lines of text.
    private var buttonVerticalPadding: CGFloat {
        Compound.supportsGlass ? 0 : 6
    }
    
    /// - When Liquid Glass is available, the buttons and composer are all 44pt x 44pt.
    /// - On iOS 18 and below, the trailing button is 36pt x 36pt and the composer is 42pt high, so some
    ///   additional padding is required to centre the button (and maintain alignment as described above).
    private var trailingButtonVerticalPadding: CGFloat {
        Compound.supportsGlass ? 0 : 3
    }
    
    /// The system keyboard's height, persisted so the panel can open at the keyboard's exact size
    /// even before the keyboard has been shown this session. Seeded with a sensible guess for the
    /// very first launch.
    @AppStorage("composerLastKeyboardHeight") private var lastKeyboardHeight = 336.0
    
    /// The panel's compact height, captured from the live keyboard at the moment the panel opens
    /// so the keyboard→panel swap is exactly height-neutral.
    @State private var compactMediaPanelHeight: CGFloat = 336
    
    /// The tallest the media panel may grow while keeping the composer fully visible. The panel
    /// presents as a keyboard, which reaches the bottom of the screen — hence adding the bottom
    /// safe-area inset to the space between the nav bar and the home indicator.
    private var expandedMediaPanelHeight: CGFloat {
        let smallest = compactMediaPanelHeight
        guard availableComposerHeight.isFinite else { return max(smallest, 720) }
        return max(smallest, availableComposerHeight + composerBottomSafeAreaInset - composerBarHeight - 8)
    }
    
    /// The only two heights the media panel snaps to: matching the keyboard it replaces, and as
    /// tall as the screen allows. (No intermediate stop — Discord-style panels only have two.)
    private var mediaPanelDetents: [CGFloat] {
        [min(compactMediaPanelHeight, expandedMediaPanelHeight), expandedMediaPanelHeight]
    }
    
    /// The media panel's current height while open. Reset to the compact detent on every open so
    /// the panel always starts exactly where the keyboard was.
    @State private var mediaPanelHeight: CGFloat = 336
    
    /// Creates and retains the `UIInputView` that presents the media panel as the composer's
    /// keyboard — see `MediaPanelInputView` for why this makes toggling jump-free.
    @State private var panelInputViewProvider = MediaPanelInputViewProvider()
    
    /// Whether the media panel's search field is focused. Fields inside an input view can't take
    /// focus (that would dismiss the keyboard hosting them), so while searching the panel is
    /// re-hosted inline below the composer instead, above the real keyboard.
    @State private var isMediaSearchFocused = false
    
    private var isMediaMode: Bool {
        context.viewState.inputMode.isMedia
    }
    
    var body: some View {
        VStack(spacing: 0) {
            composerBar
                .readHeight($composerBarHeight)
            
            if isMediaMode, isMediaSearchFocused {
                inlineSearchPanel
            }
        }
        .onChange(of: keyboardHeightObserver.height) { _, newHeight in
            // Remember the real keyboard's height for opens that happen before it has shown.
            guard let newHeight, !isMediaMode else { return }
            lastKeyboardHeight = newHeight
        }
        .onChange(of: mediaPanelHeight) { _, newHeight in
            // Forward height changes to the input view's constraint; the composer's text field
            // then reloads its input views (it receives the height too), which is what makes the
            // input system animate the keyboard frame to the new size.
            panelInputViewProvider.view?.setHeight(newHeight)
        }
        .onChange(of: expandedMediaPanelHeight) { _, newMax in
            // Keep the height within what the current screen allows (e.g. after rotation).
            guard isMediaMode else { return }
            mediaPanelHeight = min(mediaPanelHeight, newMax)
        }
        .onChange(of: context.viewState.inputMode.isMedia) { _, isMedia in
            if isMedia {
                // Match the panel to the keyboard it's replacing, measured live when possible,
                // so the swap doesn't change the input area's height at all.
                let keyboardOverlap = keyboardHeightObserver.overlap
                compactMediaPanelHeight = keyboardOverlap > 200 ? keyboardOverlap : lastKeyboardHeight
                mediaPanelHeight = compactMediaPanelHeight
                panelInputViewProvider.view?.setHeight(compactMediaPanelHeight)
                // The panel only shows while the composer holds focus (it's the composer's
                // keyboard), e.g. when the panel is opened without the keyboard on screen.
                composerFocused = true
            } else {
                isMediaSearchFocused = false
            }
        }
        .onChange(of: isMediaSearchFocused) { _, isFocused in
            // Leaving search returns focus to the composer, re-presenting the panel (which was
            // inline while searching) as its keyboard.
            guard !isFocused, isMediaMode else { return }
            composerFocused = true
        }
    }
    
    /// The media panel presented as the composer's keyboard.
    private var panelInputView: UIView {
        panelInputViewProvider.view(updatedWith: AnyView(keyboardHostedPanel), height: mediaPanelHeight)
    }
    
    private var keyboardHostedPanel: some View {
        MediaInputPanel(context: context,
                        height: $mediaPanelHeight,
                        detents: mediaPanelDetents,
                        isSearchFocused: $isMediaSearchFocused) {
            isMediaSearchFocused = true
        }
        .background(Color.compound.bgCanvasDefault)
    }
    
    /// The panel while its search field is in use: hosted inline below the composer (the system
    /// keyboard serves the search field), sized so its bottom meets the top of the keyboard.
    private var inlineSearchPanel: some View {
        MediaInputPanel(context: context,
                        height: $mediaPanelHeight,
                        detents: mediaPanelDetents,
                        isSearchFocused: $isMediaSearchFocused,
                        searchAutoFocus: true)
            .frame(height: inlineSearchPanelHeight)
            .clipped()
            .animation(.easeInOut(duration: 0.25), value: inlineSearchPanelHeight)
    }
    
    private var inlineSearchPanelHeight: CGFloat {
        let keyboardSpacing = max(keyboardHeightObserver.overlap - composerBottomSafeAreaInset, 0)
        let available = availableComposerHeight - composerBarHeight - 8 - keyboardSpacing
        return max(min(mediaPanelHeight - composerBottomSafeAreaInset, available), 150)
    }
    
    private var composerBar: some View {
        VStack(spacing: 8) {
            topBar
            
            if context.composerFormattingEnabled {
                if verticalSizeClass != .compact,
                   context.composerExpanded {
                    suggestionView
                        .padding(.leading, -5)
                        .padding(.trailing, -8)
                }
                bottomBar
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, context.composerFormattingEnabled ? 8 : 12)
        .background {
            if context.composerFormattingEnabled {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.compound.borderInteractiveSecondary, lineWidth: 0.5)
                    .ignoresSafeArea()
            }
        }
        .readFrame($frame)
        .safeAreaInset(edge: .top) {
            if !context.viewState.isRoomEncrypted {
                Label {
                    Text(L10n.commonNotEncrypted)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                } icon: {
                    CompoundIcon(\.lockOff, size: .xSmall, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconInfoPrimary)
                }
                .padding(4.0)
            }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if verticalSizeClass != .compact, !context.composerExpanded {
                    suggestionView
                        .offset(y: -frame.height)
                }
            }
        }
        .disabled(!context.viewState.canSend)
        .alert(item: $context.alertInfo)
    }
    
    private var suggestionView: some View {
        CompletionSuggestionView(mediaProvider: context.mediaProvider,
                                 items: context.viewState.suggestions,
                                 showBackgroundShadow: !context.composerExpanded) { suggestion in
            context.send(viewAction: .selectedSuggestion(suggestion))
        }
    }
    
    private var topBar: some View {
        topBarContent
            .animation(.linear(duration: 0.15), value: context.viewState.composerMode)
    }
    
    @ViewBuilder
    private var topBarContent: some View {
        if !context.composerFormattingEnabled, !context.viewState.isVoiceMessageModeActivated {
            // Two-line plain composer grouped in one box: the field on the first line, controls below.
            VStack(alignment: .leading, spacing: 4) {
                messageComposer(showsBackground: false)
                    .padding(.horizontal, 8)
                
                HStack(alignment: .center, spacing: 12) {
                    RoomAttachmentPicker(context: context)
                    
                    Spacer()
                    
                    KeyboardMediaToggleButton(inputMode: context.viewState.inputMode) {
                        context.send(viewAction: .toggleMediaInput)
                    }
                    
                    trailingButton
                }
            }
            .padding(8)
            .background(Color.compound.bgCanvasDefault,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Without this the card has no visible edge in dark mode, where the shadow alone
            // doesn't read against a dark background.
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.compound.borderInteractiveSecondary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        } else {
            // Voice recording and rich-text modes keep the single-line layout.
            topBarLayout {
                mainTopBarContent
                
                if !context.composerFormattingEnabled {
                    trailingButton
                        .scaledPadding(.vertical, trailingButtonVerticalPadding, relativeTo: .compound.headingLG)
                }
            }
        }
    }
    
    @ViewBuilder
    private var trailingButton: some View {
        if context.viewState.isUploading {
            ProgressView()
                .scaledFrame(size: Compound.supportsGlass ? 44 : 36, relativeTo: .compound.headingLG)
        } else if context.viewState.showSendButton {
            sendButton
        } else {
            voiceMessageRecordingButton(mode: context.viewState.isVoiceMessageModeActivated ? .recording : .idle)
        }
    }
    
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 4) {
            closeRTEButton
            
            FormattingToolbar(formatItems: context.formatItems) { action in
                context.send(viewAction: .composerAction(action: action.composerAction))
            }
            .padding(.horizontal, 5)
            
            sendButton
        }
    }
    
    private var topBarLayout: some Layout {
        HStackLayout(alignment: .bottom, spacing: 12)
    }
    
    private var mainTopBarContent: some View {
        ZStack(alignment: .bottom) {
            topBarLayout {
                if !context.composerFormattingEnabled {
                    RoomAttachmentPicker(context: context)
                        .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                }
                messageComposer()
                
                if !context.composerFormattingEnabled {
                    KeyboardMediaToggleButton(inputMode: context.viewState.inputMode) {
                        context.send(viewAction: .toggleMediaInput)
                    }
                    .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                }
            }
            .opacity(context.viewState.isVoiceMessageModeActivated ? 0 : 1)
            
            if context.viewState.isVoiceMessageModeActivated {
                voiceMessageContent
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var closeRTEButton: some View {
        Button {
            context.composerFormattingEnabled = false
            context.composerExpanded = false
        } label: {
            CompoundIcon(\.close,
                         size: Compound.supportsGlass ? .medium : .small,
                         relativeTo: .compound.headingLG)
        }
        .buttonStyle(ComposerToolbarButtonStyle())
        .accessibilityLabel(L10n.richTextEditorCloseFormattingOptions)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.composerToolbar.closeFormattingOptions)
    }
    
    private var sendButton: some View {
        SendButton(mode: context.viewState.sendButtonMode, action: sendMessage)
            .accessibilityLabel(context.viewState.sendButtonAccessibilityLabel)
            .disabled(context.viewState.sendButtonDisabled)
            .animation(.linear(duration: 0.1).disabledDuringTests(), value: context.viewState.sendButtonDisabled)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.sendButton)
    }
    
    private func messageComposer(showsBackground: Bool = true) -> some View {
        MessageComposer(plainComposerText: $context.plainComposerText,
                        presendCallback: $context.presendCallback,
                        selectedRange: $context.selectedRange,
                        composerView: composerView,
                        mode: context.viewState.composerMode,
                        placeholder: placeholder,
                        composerFormattingEnabled: context.composerFormattingEnabled,
                        showResizeGrabber: context.composerFormattingEnabled,
                        isExpanded: $context.composerExpanded,
                        customInputView: isMediaMode ? panelInputView : nil,
                        customInputViewHeight: mediaPanelHeight,
                        showsBackground: showsBackground) {
            sendMessage()
        } editAction: {
            context.send(viewAction: .editLastMessage)
        } pasteAction: { providers in
            context.send(viewAction: .handlePasteOrDrop(providers: providers))
        } cancellationAction: {
            switch context.viewState.composerMode {
            case .edit:
                context.send(viewAction: .cancelEdit)
            case .reply:
                context.send(viewAction: .cancelReply)
            default:
                break
            }
        } onAppearAction: {
            context.send(viewAction: .composerAppeared)
        }
        .onDisappear {
            context.send(viewAction: .composerDisappeared)
        }
        .environmentObject(context)
        .focused($composerFocused)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.messageComposer)
        .onTapGesture {
            guard !composerFocused else { return }
            composerFocused = true
        }
        .onChange(of: context.composerFocused) { _, newValue in
            guard composerFocused != newValue else { return }
            
            composerFocused = newValue
        }
        .onChange(of: composerFocused) { _, newValue in
            context.composerFocused = newValue
        }
        .onChange(of: context.plainComposerText) {
            context.send(viewAction: .plainComposerTextChanged)
        }
        .onChange(of: context.composerFormattingEnabled) {
            context.send(viewAction: .didToggleFormattingOptions)
        }
        .onChange(of: context.selectedRange) {
            context.send(viewAction: .selectedTextChanged)
        }
        .onAppear {
            composerFocused = context.composerFocused
        }
    }
    
    private func sendMessage() {
        // Allow the inner TextField do apply any final processing before
        // sending e.g. accepting current autocorrection.
        // Fixes https://github.com/element-hq/element-x-ios/issues/3216
        context.presendCallback?()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.send(viewAction: .sendMessage)
        }
    }
    
    private var placeholder: String {
        switch context.viewState.composerMode {
        case .reply(_, _, let isThread):
            return isThread ? L10n.actionReplyInThread : composerPlaceholder
        default:
            return composerPlaceholder
        }
    }
    
    private var composerPlaceholder: String {
        L10n.richTextEditorComposerPlaceholder
    }
    
    private var composerView: WysiwygComposerView {
        WysiwygComposerView(placeholder: placeholder,
                            placeholderColor: .compound.textSecondary,
                            viewModel: context.viewState.wysiwygViewModel,
                            itemProviderHelper: ItemProviderHelper(),
                            keyCommands: context.viewState.keyCommands) { provider in
            context.send(viewAction: .handlePasteOrDrop(providers: [provider]))
        }
    }
    
    private class ItemProviderHelper: WysiwygItemProviderHelper {
        func isPasteSupported(for itemProvider: NSItemProvider) -> Bool {
            itemProvider.isSupportedForPasteOrDrop
        }
    }
    
    // MARK: - Voice message
    
    @ViewBuilder
    private var voiceMessageContent: some View {
        // Display the voice message composer above to keep the focus and keep the keyboard open if it's already open.
        switch context.viewState.composerMode {
        case .recordVoiceMessage(let state):
            topBarLayout {
                voiceMessageTrashButton
                    .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                VoiceMessageRecordingComposer(recorderState: state)
            }
        case .previewVoiceMessage(let state, let waveform, let isUploading):
            topBarLayout {
                voiceMessageTrashButton
                    .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                voiceMessagePreviewComposer(audioPlayerState: state, waveform: waveform)
            }
            .disabled(isUploading)
        default:
            EmptyView()
        }
    }
    
    private func voiceMessageRecordingButton(mode: VoiceMessageRecordingButtonMode) -> some View {
        VoiceMessageRecordingButton(mode: mode) {
            context.send(viewAction: .voiceMessage(.startRecording))
        } stopRecording: {
            context.send(viewAction: .voiceMessage(.stopRecording))
        }
    }
    
    private var voiceMessageTrashButton: some View {
        VoiceMessageTrashButton {
            context.send(viewAction: .voiceMessage(.deleteRecording))
        }
        .accessibilityLabel(L10n.a11yDelete)
    }
    
    private func voiceMessagePreviewComposer(audioPlayerState: AudioPlayerState, waveform: WaveformSource) -> some View {
        VoiceMessagePreviewComposer(playerState: audioPlayerState, waveform: waveform) {
            context.send(viewAction: .voiceMessage(.startPlayback))
        } onPause: {
            context.send(viewAction: .voiceMessage(.pausePlayback))
        } onSeek: { progress in
            context.send(viewAction: .voiceMessage(.seekPlayback(progress: progress)))
        } onScrubbing: { isScrubbing in
            context.send(viewAction: .voiceMessage(.scrubPlayback(scrubbing: isScrubbing)))
        }
    }
}

extension EnvironmentValues {
    /// The vertical space available to the composer and its media panel, supplied by the room
    /// screen so the panel can cap its height and never push the composer off-screen.
    @Entry var availableComposerHeight: CGFloat = .infinity
    /// The window's bottom safe-area inset (home indicator), supplied by the room screen. The
    /// media panel subtracts it from the keyboard height it mimics, because the keyboard covers
    /// that area while the panel is laid out above it.
    @Entry var composerBottomSafeAreaInset: CGFloat = 0
}

struct ComposerToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .modifier(GlassStyle())
        } else {
            configuration.label
                .modifier(FlatStyle(isPressed: configuration.isPressed))
        }
    }
    
    @available(iOS 26, *)
    private struct GlassStyle: ViewModifier {
        @Environment(\.isEnabled) private var isEnabled
        
        func body(content: Content) -> some View {
            if isEnabled {
                label(content: content)
                    .snapshotableGlassEffect(.regular.interactive(),
                                             snapshotBackground: .compound.bgSubtleSecondary,
                                             in: .circle)
            } else {
                label(content: content)
                    .background(.compound.bgSubtlePrimary, in: .circle)
            }
        }
        
        func label(content: Content) -> some View {
            content
                .foregroundStyle(isEnabled ? .compound.iconPrimary : .compound.iconDisabled)
                .scaledPadding(10, relativeTo: .compound.headingLG)
        }
    }
    
    private struct FlatStyle: ViewModifier {
        @Environment(\.isEnabled) private var isEnabled
        
        let isPressed: Bool
        
        func body(content: Content) -> some View {
            content
                .foregroundStyle(.compound.iconOnSolidPrimary)
                .scaledPadding(5, relativeTo: .compound.headingLG)
                .background(backgroundColor(isPressed: isPressed), in: .circle)
        }
        
        private func backgroundColor(isPressed: Bool) -> Color {
            guard isEnabled else { return .compound.bgActionPrimaryDisabled }
            return isPressed ? .compound.bgActionPrimaryPressed : .compound.bgActionPrimaryRest
        }
    }
}

// MARK: - Previews

struct ComposerToolbar_Previews: PreviewProvider, TestablePreview {
    static let timelineViewModel = TimelineViewModel.mock
    
    static let viewModel = ComposerToolbarViewModel.mock()
    static let editingViewModel = ComposerToolbarViewModel.mock(message: "Hello, Wrold!", mockMode: .editing)
    static let multiLineViewModel = ComposerToolbarViewModel.mock(message: "Hello, World! This is a loooong message that wraps onto multiple lines.")
    static let voiceMessageRecordingViewModel = ComposerToolbarViewModel.mock(mockMode: .recordVoiceMessage)
    static let voiceMessagePreviewViewModel = ComposerToolbarViewModel.mock(mockMode: .previewVoiceMessage(isUploading: false))
    static let voiceMessageUploadingViewModel = ComposerToolbarViewModel.mock(mockMode: .previewVoiceMessage(isUploading: true))
    static let replyLoadingViewModel = ComposerToolbarViewModel.mock(mockMode: .reply(isLoading: true))
    static let replyLoadedViewModel = ComposerToolbarViewModel.mock(mockMode: .reply(isLoading: false))
    static let suggestionsViewModel = ComposerToolbarViewModel.mock(hasSuggestions: true)
    static let disabledViewModel = ComposerToolbarViewModel.mock(canSend: false)
    
    static var previews: some View {
        VStack(spacing: 8) {
            ComposerToolbar(context: viewModel.context)
            ComposerToolbar(context: editingViewModel.context)
            ComposerToolbar(context: multiLineViewModel.context)
                .padding(.bottom)
            
            ComposerToolbar(context: voiceMessageRecordingViewModel.context)
            ComposerToolbar(context: voiceMessagePreviewViewModel.context)
            ComposerToolbar(context: voiceMessageUploadingViewModel.context)
                .padding(.bottom)
            
            ComposerToolbar(context: disabledViewModel.context)
        }
        
        // Putting them in a VStack allows the completion suggestion preview to work properly in tests
        VStack(spacing: 8) {
            ComposerToolbar(context: suggestionsViewModel.context)
        }
        .previewDisplayName("With Suggestions")
        
        VStack(spacing: 8) {
            ComposerToolbar(context: replyLoadingViewModel.context)
            ComposerToolbar(context: replyLoadedViewModel.context)
        }
        .environmentObject(timelineViewModel.context)
        .previewDisplayName("Reply")
    }
}
