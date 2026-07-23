//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import MatrixRustSDK
import PhotosUI
import SwiftUI
import WysiwygComposer

enum ComposerToolbarVoiceMessageAction {
    case startRecording
    case stopRecording
    case cancelRecording
    case deleteRecording
    case startPlayback
    case pausePlayback
    case scrubPlayback(scrubbing: Bool)
    case seekPlayback(progress: Double)
    case send
}

enum ComposerToolbarViewModelAction {
    case sendMessage(plain: String, html: String?, mode: ComposerMode, intentionalMentions: IntentionalMentions)
    case editLastMessage
    case attach(ComposerAttachmentType)
    
    case handlePasteOrDrop(providers: [NSItemProvider])
    
    case composerModeChanged(mode: ComposerMode)
    case composerFocusedChanged(isFocused: Bool)
    
    case voiceMessage(ComposerToolbarVoiceMessageAction)
    
    case contentChanged(isEmpty: Bool)
}

enum ComposerToolbarViewAction {
    case composerAppeared
    case composerDisappeared
    
    case sendMessage
    case editLastMessage
    case cancelReply
    case cancelEdit
    case attach(ComposerAttachmentType)
    case handlePasteOrDrop(providers: [NSItemProvider])
    case enableTextFormatting
    case composerAction(action: ComposerAction)
    case selectedSuggestion(_ suggestion: SuggestionItem)
    
    case voiceMessage(ComposerToolbarVoiceMessageAction)
    
    case plainComposerTextChanged
    case didToggleFormattingOptions
    case selectedTextChanged
    
    /// Toggles between the system keyboard and the media panel.
    case toggleMediaInput
    /// Restores the system keyboard (e.g. the composer field was tapped while the panel was up).
    case showKeyboard
    /// Switches the visible media tab without touching the first responder.
    case selectMediaTab(MediaTab)
    /// The in-panel search query changed (currently filters the emoji grid).
    case mediaSearchQueryChanged
    /// Inserts the given emoji at the caret and keeps the panel open.
    case insertEmoji(String)
    /// Sends a discovered GIF into the timeline, keeping the panel open.
    case sendMediaGIF(KlipySticker)
    /// Adds a discovered GIF to the user's sticker pack (with dedup), keeping the panel open.
    case addMediaGIF(KlipySticker)
    /// Loads the next page of GIF results (infinite scroll).
    case loadMoreGIFs
    /// Sends one of the user's stickers into the timeline, keeping the panel open.
    case sendMediaSticker(Sticker)
    /// Uploads the images/GIFs picked in the sticker tab to the user's pack (with dedup).
    case addStickerPhotos
}

enum ComposerAttachmentType {
    case camera
    case photoLibrary
    case file
    case location
    case poll
    case sticker
}

/// The services the media panel needs to send/collect stickers and GIFs. Bundled so the composer's
/// dependency injection threads a single value instead of several parameters through the coordinators,
/// keeping the diff against upstream small.
struct ComposerMediaServices {
    let stickerService: StickerServiceProtocol
    let gifService: KlipyServiceProtocol
    let timelineController: StickerSending
    let userIndicatorController: UserIndicatorControllerProtocol
}

struct ComposerToolbarViewState: BindableState {
    let wysiwygViewModel: WysiwygComposerViewModel
    
    var composerMode: ComposerMode = .default
    /// The current input source (system keyboard vs media panel). Drives the composer's media toggle glyph.
    var inputMode: ComposerInputMode = .none
    /// The emoji grid shown in the media panel's emoji tab (recents first, then categories).
    var mediaEmojiCategories: [EmojiCategory] = []
    /// The GIF results shown in the media panel's GIF tab (trending, or search matches).
    var mediaGIFs: [KlipySticker] = []
    var mediaGIFsHasMore = false
    var mediaGIFsLoading = false
    /// The stickers shown in the media panel's sticker tab (built-in + the user's own pack).
    var mediaStickers: [Sticker] = []
    /// The id of the GIF/sticker currently being uploaded and sent, for a per-item spinner.
    var sendingMediaItemID: String?
    /// Whether images picked from the library are currently being added to the user's pack.
    var isAddingStickers = false
    var composerEmpty = true
    /// Could be false if sending is disabled in the room
    var canSend = true
    var suggestions: [SuggestionItem] = []
    
    var isRoomEncrypted: Bool
    var isLocationSharingEnabled: Bool
    
    var keyCommands: [WysiwygKeyCommand] = []
    
    var bindings: ComposerToolbarViewStateBindings
    
    var isUploading: Bool {
        switch composerMode {
        case .previewVoiceMessage(_, _, let isUploading):
            return isUploading
        default:
            return false
        }
    }
    
    var showSendButton: Bool {
        switch composerMode {
        case .recordVoiceMessage:
            return false
        case .previewVoiceMessage:
            return true
        default:
            if bindings.composerFormattingEnabled {
                return !composerEmpty
            } else {
                return !bindings.plainComposerText.string.isEmpty
            }
        }
    }
    
    var sendButtonMode: SendButton.Mode {
        composerMode.isEdit ? .edit : .send
    }
    
    var sendButtonAccessibilityLabel: String {
        composerMode.isEdit ? L10n.actionConfirm : L10n.actionSend
    }
    
    var sendButtonDisabled: Bool {
        if !canSend {
            return true
        }
        
        if case .previewVoiceMessage = composerMode {
            return false
        }
        
        if bindings.composerFormattingEnabled {
            return composerEmpty
        } else {
            return bindings.plainComposerText.string.isEmpty
        }
    }
    
    var isVoiceMessageModeActivated: Bool {
        switch composerMode {
        case .recordVoiceMessage, .previewVoiceMessage:
            return true
        default:
            return false
        }
    }
}

struct ComposerToolbarViewStateBindings {
    var plainComposerText: NSAttributedString = .init(string: "")
    var composerFocused = false
    /// The media panel's in-panel search text.
    var mediaSearchQuery = ""
    /// Photos picked in the sticker tab to add to the user's pack.
    var stickerPhotosPickerItems: [PhotosPickerItem] = []
    var composerFormattingEnabled = false
    var composerExpanded = false
    var formatItems: [FormatItem] = .init()
    var alertInfo: AlertInfo<UUID>?
    var selectedRange = NSRange(location: 0, length: 0)
    
    var presendCallback: (() -> Void)?
}

/// An item in the toolbar
struct FormatItem {
    /// The type of the item
    let type: FormatType
    /// The state of the item
    let state: ActionState
}

/// The types of formatting actions
enum FormatType {
    case bold
    case italic
    case underline
    case strikeThrough
    case link
    case unorderedList
    case orderedList
    case indent
    case unindent
    case inlineCode
    case codeBlock
    case quote
}

extension FormatType: CaseIterable, Identifiable {
    var id: Self {
        self
    }
}

extension FormatItem: Identifiable {
    var id: FormatType {
        type
    }
}

extension FormatItem {
    /// The icon to display in the formatting toolbar.
    var icon: KeyPath<CompoundIcons, Image> {
        switch type {
        case .bold:
            return \.bold
        case .italic:
            return \.italic
        case .underline:
            return \.underline
        case .strikeThrough:
            return \.strikethrough
        case .unorderedList:
            return \.listBulleted
        case .orderedList:
            return \.listNumbered
        case .indent:
            return \.indentIncrease
        case .unindent:
            return \.indentDecrease
        case .inlineCode:
            return \.inlineCode
        case .codeBlock:
            return \.code
        case .quote:
            return \.quote
        case .link:
            return \.link
        }
    }
    
    var accessibilityIdentifier: String {
        switch type {
        case .bold:
            return A11yIdentifiers.roomScreen.composerToolbar.bold
        case .italic:
            return A11yIdentifiers.roomScreen.composerToolbar.italic
        case .underline:
            return A11yIdentifiers.roomScreen.composerToolbar.underline
        case .strikeThrough:
            return A11yIdentifiers.roomScreen.composerToolbar.strikethrough
        case .unorderedList:
            return A11yIdentifiers.roomScreen.composerToolbar.unorderedList
        case .orderedList:
            return A11yIdentifiers.roomScreen.composerToolbar.orderedList
        case .indent:
            return A11yIdentifiers.roomScreen.composerToolbar.indent
        case .unindent:
            return A11yIdentifiers.roomScreen.composerToolbar.unindent
        case .inlineCode:
            return A11yIdentifiers.roomScreen.composerToolbar.inlineCode
        case .codeBlock:
            return A11yIdentifiers.roomScreen.composerToolbar.codeBlock
        case .quote:
            return A11yIdentifiers.roomScreen.composerToolbar.quote
        case .link:
            return A11yIdentifiers.roomScreen.composerToolbar.link
        }
    }
    
    var accessibilityLabel: String {
        let localizedAction = switch type {
        case .bold:
            L10n.richTextEditorFormatBold
        case .italic:
            L10n.richTextEditorFormatItalic
        case .underline:
            L10n.richTextEditorFormatUnderline
        case .strikeThrough:
            L10n.richTextEditorFormatStrikethrough
        case .unorderedList:
            L10n.richTextEditorBulletList
        case .orderedList:
            L10n.richTextEditorNumberedList
        case .indent:
            L10n.richTextEditorIndent
        case .unindent:
            L10n.richTextEditorUnindent
        case .inlineCode:
            L10n.richTextEditorInlineCode
        case .codeBlock:
            L10n.richTextEditorCodeBlock
        case .quote:
            L10n.richTextEditorQuote
        case .link:
            L10n.richTextEditorLink
        }
        return L10n.richTextEditorFormatAction(localizedAction, state.localizedDescription)
    }
}

extension ActionState {
    /// Returns a localized string that describes the action state.
    var localizedDescription: String {
        switch self {
        case .disabled:
            L10n.richTextEditorFormatStateDisabled
        case .enabled:
            L10n.richTextEditorFormatStateOff
        case .reversed:
            L10n.richTextEditorFormatStateOn
        }
    }
}

extension FormatType {
    /// The associated library composer action.
    var composerAction: ComposerAction {
        switch self {
        case .bold:
            return .bold
        case .italic:
            return .italic
        case .underline:
            return .underline
        case .strikeThrough:
            return .strikeThrough
        case .unorderedList:
            return .unorderedList
        case .orderedList:
            return .orderedList
        case .indent:
            return .indent
        case .unindent:
            return .unindent
        case .inlineCode:
            return .inlineCode
        case .codeBlock:
            return .codeBlock
        case .quote:
            return .quote
        case .link:
            return .link
        }
    }
}

enum ComposerMode: Equatable {
    enum EditType { case `default`, addCaption, editCaption }
    
    case `default`
    case reply(eventID: String, replyDetails: TimelineItemReplyDetails, isThread: Bool)
    case edit(originalEventOrTransactionID: TimelineItemIdentifier.EventOrTransactionID, type: EditType)
    case recordVoiceMessage(state: AudioRecorderState)
    case previewVoiceMessage(state: AudioPlayerState, waveform: WaveformSource, isUploading: Bool)
    
    var isEdit: Bool {
        switch self {
        case .edit:
            return true
        default:
            return false
        }
    }
    
    var isTextEditingEnabled: Bool {
        switch self {
        case .default, .reply, .edit:
            return true
        case .recordVoiceMessage, .previewVoiceMessage:
            return false
        }
    }
    
    var isLoadingReply: Bool {
        switch self {
        case .reply(_, let replyDetails, _):
            switch replyDetails {
            case .loading:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    var replyEventID: String? {
        switch self {
        case .reply(let eventID, _, _):
            return eventID
        default:
            return nil
        }
    }
    
    var isComposingNewMessage: Bool {
        switch self {
        case .default, .reply:
            return true
        default:
            return false
        }
    }
}
