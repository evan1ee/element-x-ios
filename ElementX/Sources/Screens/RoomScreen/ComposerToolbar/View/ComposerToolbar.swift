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
    /// Measures the real system keyboard: its height, so the media panel can size itself to take
    /// the keyboard's place exactly, and its animation, so everything here moves on its clock.
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
    
    /// The panel's compact height: whatever the keyboard measures, so that the panel can take the
    /// keyboard's place without the composer moving by so much as a point.
    @State private var compactMediaPanelHeight: CGFloat = 336
    
    /// Whether the panel sits at its expanded detent.
    @State private var isMediaPanelExpanded = false
    
    /// Whether the panel is claiming space below the composer. Owned locally rather than read
    /// straight from `isMediaMode` so that both opening and closing animate: the panel is mounted
    /// (at zero height) one update before this turns on, and stays mounted until `isMediaPanelMounted`
    /// lets go of it, one animation after it turns off.
    @State private var isMediaPanelOpen = false
    
    /// Keeps the panel alive while it animates away — see `closeMediaPanel`.
    @State private var isMediaPanelMounted = false
    
    /// Unmounts the panel once it has finished animating away — see `closeMediaPanel`.
    @State private var mediaPanelUnmountTask: Task<Void, Never>?
    
    /// Whether the media panel's search field is focused.
    @State private var isMediaSearchFocused = false
    
    /// The tallest the media panel may grow while keeping the composer fully visible. The panel
    /// reaches the bottom of the screen — hence adding the bottom safe-area inset to the space
    /// between the nav bar and the home indicator.
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
    
    /// How much of the screen the panel claims, measured from the bottom; zero when it's closed.
    private var mediaPanelFootprint: CGFloat {
        guard isMediaPanelOpen else { return 0 }
        return isMediaPanelExpanded ? expandedMediaPanelHeight : compactMediaPanelHeight
    }
    
    /// The whole input area below the composer bar, measured from the bottom of the screen: the
    /// panel, the keyboard, or whichever of the two is taller — the keyboard simply lies over the
    /// panel rather than displacing it.
    ///
    /// This single number is the composer's distance from the bottom of the screen, and it is the
    /// only thing that ever moves the composer. Every transition is one change to it, animated
    /// once on the keyboard's own clock, which is why focus handoffs (into search, out of search,
    /// back to the composer) move nothing at all: the taller of the two simply stays taller.
    private var inputAreaHeight: CGFloat {
        max(keyboardHeightObserver.overlap, mediaPanelFootprint)
    }
    
    /// The panel's height within the composer's container, which already sits above the home
    /// indicator.
    private var mediaPanelInsetHeight: CGFloat {
        max(mediaPanelFootprint - composerBottomSafeAreaInset, 0)
    }
    
    /// Whatever the keyboard needs beyond the space the panel already provides.
    private var keyboardInsetHeight: CGFloat {
        max(inputAreaHeight - composerBottomSafeAreaInset - mediaPanelInsetHeight, 0)
    }
    
    private var isMediaMode: Bool {
        context.viewState.inputMode.isMedia
    }
    
    var body: some View {
        VStack(spacing: 0) {
            composerBar
                .readHeight($composerBarHeight)
            
            if isMediaMode || isMediaPanelMounted {
                mediaPanel
            }
        }
        // The composer makes its own room for the keyboard (the screen opts out of SwiftUI's
        // automatic avoidance) so that the keyboard and the panel resolve to one animated height
        // instead of two that have to cancel each other out.
        .padding(.bottom, keyboardInsetHeight)
        .animation(keyboardHeightObserver.animation, value: keyboardInsetHeight)
        .onAppear {
            guard keyboardHeightObserver.height == nil else { return }
            compactMediaPanelHeight = lastKeyboardHeight
        }
        .onChange(of: keyboardHeightObserver.height) { _, newHeight in
            // Follow the real keyboard while it's the one on screen, so the panel is always
            // pre-sized to the keyboard whose place it takes.
            guard let newHeight, !isMediaMode else { return }
            lastKeyboardHeight = newHeight
            compactMediaPanelHeight = newHeight
        }
        .onChange(of: isMediaMode) { _, isMedia in
            if isMedia {
                openMediaPanel()
            } else {
                closeMediaPanel()
            }
        }
        .onChange(of: isMediaSearchFocused) { _, isFocused in
            // The search keyboard is about to cover the panel, so expand it to keep the results in
            // view. At the expanded detent this is already true and nothing moves at all.
            guard isMediaMode, isFocused, !isMediaPanelExpanded else { return }
            withAnimation(keyboardHeightObserver.animation) {
                isMediaPanelExpanded = true
            }
        }
    }
    
    /// Opens the panel at exactly the height of the keyboard it replaces, so that dismissing the
    /// keyboard doesn't move the composer — the keyboard slides away and uncovers the panel that
    /// is already sitting behind it.
    private func openMediaPanel() {
        let keyboardOverlap = keyboardHeightObserver.overlap
        if keyboardOverlap > 200 {
            compactMediaPanelHeight = keyboardOverlap
        }
        
        mediaPanelUnmountTask?.cancel()
        isMediaPanelMounted = true
        
        withAnimation(keyboardHeightObserver.animation) {
            isMediaPanelExpanded = false
            isMediaPanelOpen = true
        }
        
        // The composer stays first responder with its keyboard suppressed, so the caret and any
        // selection survive browsing the panel.
        composerFocused = true
    }
    
    /// Closes the panel. It collapses to the compact detent — the keyboard's own height, which the
    /// keyboard is rising into at that very moment — so the composer makes one continuous move
    /// down and then stops dead. Only once that has finished does the panel give up its space, by
    /// which point the keyboard is already holding it and nothing moves.
    private func closeMediaPanel() {
        isMediaSearchFocused = false
        
        withAnimation(keyboardHeightObserver.animation) {
            isMediaPanelExpanded = false
        }
        
        mediaPanelUnmountTask?.cancel()
        mediaPanelUnmountTask = Task {
            try? await Task.sleep(for: .seconds(keyboardHeightObserver.animationDuration))
            guard !Task.isCancelled else { return }
            withAnimation(keyboardHeightObserver.animation) {
                isMediaPanelOpen = false
            }
            
            try? await Task.sleep(for: .seconds(keyboardHeightObserver.animationDuration))
            guard !Task.isCancelled else { return }
            isMediaPanelMounted = false
        }
    }
    
    private var mediaPanel: some View {
        MediaInputPanel(context: context,
                        isExpanded: $isMediaPanelExpanded,
                        height: mediaPanelFootprint,
                        detents: mediaPanelDetents,
                        searchFocus: $isMediaSearchFocused)
            .frame(height: mediaPanelInsetHeight, alignment: .top)
            .clipped()
            .animation(keyboardHeightObserver.animation, value: mediaPanelInsetHeight)
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
                        suppressesSystemKeyboard: isMediaMode,
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
