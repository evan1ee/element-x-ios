//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing
import UIKit
import WysiwygComposer

@MainActor
final class ComposerToolbarViewModelTests {
    private var wysiwygViewModel: WysiwygComposerViewModel!
    private var viewModel: ComposerToolbarViewModel!
    private var completionSuggestionServiceMock: CompletionSuggestionServiceMock!
    private var draftServiceMock: ComposerDraftServiceMock!
    private var emojiProviderSpy: EmojiProviderSpy!
    private var stickerServiceMock: StickerServiceMock!
    private var gifServiceMock: KlipyServiceMock!
    private var timelineControllerMock: TimelineControllerMock!
    
    init() {
        setUpViewModel()
    }
    
    @Test
    func composerFocus() {
        viewModel.process(timelineAction: .setMode(mode: .edit(originalEventOrTransactionID: .eventID("mock"), type: .default)))
        #expect(viewModel.state.bindings.composerFocused)
        viewModel.process(timelineAction: .removeFocus)
        #expect(!viewModel.state.bindings.composerFocused)
    }
    
    @Test
    func composerMode() {
        let mode: ComposerMode = .edit(originalEventOrTransactionID: .eventID("mock"), type: .default)
        viewModel.process(timelineAction: .setMode(mode: mode))
        #expect(viewModel.state.composerMode == mode)
        viewModel.process(timelineAction: .clear)
        #expect(viewModel.state.composerMode == .default)
    }
    
    @Test
    func composerModeIsPublished() async throws {
        let mode: ComposerMode = .edit(originalEventOrTransactionID: .eventID("mock"), type: .default)
        let deferred = deferFulfillment(viewModel.context.$viewState.map(\.composerMode).removeDuplicates().dropFirst()) { $0 == mode }
        viewModel.process(timelineAction: .setMode(mode: mode))
        try await deferred.fulfill()
    }
    
    @Test
    func handleKeyCommand() {
        #expect(viewModel.context.viewState.keyCommands.count == 1)
    }
    
    // MARK: - Media input
    
    @Test
    func togglingMediaInputPresentsTheEmojiTab() {
        #expect(viewModel.state.inputMode == .none)
        
        viewModel.process(viewAction: .toggleMediaInput)
        
        #expect(viewModel.state.inputMode == .media(.emoji))
    }
    
    @Test
    func togglingMediaInputAgainDismissesThePanel() {
        viewModel.process(viewAction: .toggleMediaInput)
        #expect(viewModel.state.inputMode == .media(.emoji))
        
        viewModel.process(viewAction: .toggleMediaInput)
        
        #expect(viewModel.state.inputMode == .none)
    }
    
    @Test
    func showKeyboardDismissesTheMediaPanel() {
        viewModel.process(viewAction: .toggleMediaInput)
        #expect(viewModel.state.inputMode == .media(.emoji))
        
        viewModel.process(viewAction: .showKeyboard)
        
        #expect(viewModel.state.inputMode == .none)
    }
    
    @Test
    func everyMediaTabIsRenderable() {
        // Guards the extensibility contract: adding a tab must not break rendering.
        for tab in MediaTab.allCases {
            #expect(!tab.rawValue.isEmpty)
        }
    }
    
    @Test
    func selectingATabSwitchesTheVisibleTab() {
        viewModel.process(viewAction: .toggleMediaInput)
        #expect(viewModel.state.inputMode == .media(.emoji))
        
        viewModel.process(viewAction: .selectMediaTab(.sticker))
        
        #expect(viewModel.state.inputMode == .media(.sticker))
    }
    
    @Test
    func selectingATabIsIgnoredWhenThePanelIsClosed() {
        viewModel.process(viewAction: .selectMediaTab(.gif))
        #expect(viewModel.state.inputMode == .none)
    }
    
    @Test
    func openingTheEmojiTabLoadsEmojis() async throws {
        let deferred = deferFulfillment(viewModel.context.$viewState.map(\.mediaEmojiCategories)) { !$0.isEmpty }
        viewModel.process(viewAction: .toggleMediaInput)
        try await deferred.fulfill()
        
        #expect(viewModel.state.mediaEmojiCategories == emojiProviderSpy.categoriesToReturn)
    }
    
    @Test
    func insertingAnEmojiRecordsARecentAndKeepsThePanelOpen() {
        viewModel.process(viewAction: .toggleMediaInput)
        #expect(viewModel.state.inputMode == .media(.emoji))
        
        viewModel.process(viewAction: .insertEmoji("😀"))
        
        #expect(emojiProviderSpy.markedEmojis == ["😀"])
        // Selection is an action, not a transition — the panel stays on the emoji tab.
        #expect(viewModel.state.inputMode == .media(.emoji))
    }
    
    @Test
    func openingTheGIFTabLoadsTrendingGIFs() async throws {
        let gif = makeGIF(id: "a")
        gifServiceMock.searchQueryPageReturnValue = .success(.init(stickers: [gif], hasNextPage: true, nextPage: 2))
        
        let deferred = deferFulfillment(viewModel.context.$viewState.map(\.mediaGIFs)) { !$0.isEmpty }
        viewModel.process(viewAction: .selectMediaTab(.gif))
        // selectMediaTab is ignored unless the panel is open, so open it first.
        viewModel.process(viewAction: .toggleMediaInput)
        viewModel.process(viewAction: .selectMediaTab(.gif))
        try await deferred.fulfill()
        
        #expect(viewModel.state.mediaGIFs.map(\.id) == ["a"])
        #expect(viewModel.state.mediaGIFsHasMore)
        #expect(gifServiceMock.searchQueryPageReceivedArguments?.query == "")
    }
    
    @Test
    func sendingAGIFDownloadsUploadsAndSendsIt() async throws {
        viewModel.process(viewAction: .toggleMediaInput)
        viewModel.process(viewAction: .selectMediaTab(.gif))
        
        viewModel.process(viewAction: .sendMediaGIF(makeGIF(id: "a")))
        #expect(viewModel.state.sendingMediaItemID == "a")
        
        while !stickerServiceMock.sendExternalStickerImageDataBodyWidthHeightMimeTypeInCalled {
            await Task.yield()
        }
        
        #expect(gifServiceMock.downloadImageFromCalled)
        let arguments = try #require(stickerServiceMock.sendExternalStickerImageDataBodyWidthHeightMimeTypeInReceivedArguments)
        #expect(arguments.mimeType == "image/gif")
        // The panel stays open so several GIFs can be sent in a row.
        #expect(viewModel.state.inputMode == .media(.gif))
    }
    
    @Test
    func addingAGIFToStickersDownloadsUploadsAndRefreshesThePack() async throws {
        stickerServiceMock.addExternalStickerImageDataBodyWidthHeightMimeTypeReturnValue = StickerBatchSummary(added: 1)
        let added = Sticker(id: "a", body: "GIF a", source: .media(url: "mxc://example.com/a"),
                            width: 200, height: 200, fileSize: 5000, mimeType: "image/gif")
        stickerServiceMock.loadStickersReturnValue = StickerCollection(userStickers: [added], builtInStickers: [])
        
        viewModel.process(viewAction: .toggleMediaInput)
        viewModel.process(viewAction: .selectMediaTab(.gif))
        
        viewModel.process(viewAction: .addMediaGIF(makeGIF(id: "a")))
        
        while !stickerServiceMock.addExternalStickerImageDataBodyWidthHeightMimeTypeCalled {
            await Task.yield()
        }
        
        #expect(gifServiceMock.downloadImageFromCalled)
        let arguments = try #require(stickerServiceMock.addExternalStickerImageDataBodyWidthHeightMimeTypeReceivedArguments)
        #expect(arguments.mimeType == "image/gif")
        // A successful add refreshes the grid and keeps the panel open.
        while viewModel.state.mediaStickers.isEmpty {
            await Task.yield()
        }
        #expect(viewModel.state.mediaStickers.map(\.id) == ["a"])
        #expect(viewModel.state.inputMode == .media(.gif))
    }
    
    @Test
    func openingTheStickerTabLoadsTheUserPack() async throws {
        let sticker = Sticker(id: "party", body: "Party", source: .media(url: "mxc://example.com/party"),
                              width: 512, height: 512, fileSize: 1024, mimeType: "image/png")
        stickerServiceMock.loadStickersReturnValue = StickerCollection(userStickers: [sticker], builtInStickers: [])
        
        viewModel.process(viewAction: .toggleMediaInput)
        let deferred = deferFulfillment(viewModel.context.$viewState.map(\.mediaStickers)) { !$0.isEmpty }
        viewModel.process(viewAction: .selectMediaTab(.sticker))
        try await deferred.fulfill()
        
        #expect(viewModel.state.mediaStickers.map(\.id) == ["party"])
    }
    
    @Test
    func sendingAStickerSendsItThroughTheStickerService() async {
        let sticker = Sticker(id: "party", body: "Party", source: .media(url: "mxc://example.com/party"),
                              width: 512, height: 512, fileSize: 1024, mimeType: "image/png")
        viewModel.process(viewAction: .toggleMediaInput)
        
        viewModel.process(viewAction: .sendMediaSticker(sticker))
        #expect(viewModel.state.sendingMediaItemID == "party")
        
        while !stickerServiceMock.sendInCalled {
            await Task.yield()
        }
        
        #expect(stickerServiceMock.sendInReceivedArguments?.sticker == sticker)
        #expect(viewModel.state.inputMode == .media(.emoji))
    }
    
    private func makeGIF(id: String) -> KlipySticker {
        KlipySticker(id: id, title: "GIF \(id)",
                     previewURL: gifURL("\(id)-sm"), fileURL: gifURL("\(id)-md"),
                     width: 200, height: 200, size: 5000, mimeType: "image/gif")
    }
    
    private func gifURL(_ name: String) -> URL {
        URL(string: "https://static.klipy.com/\(name).gif") ?? URL(filePath: "/")
    }
    
    @Test
    func composerFocusAfterEnablingRTE() {
        viewModel.process(viewAction: .enableTextFormatting)
        #expect(viewModel.state.bindings.composerFocused)
    }
    
    @Test
    func rteEnabledAfterSendingMessage() {
        viewModel.process(viewAction: .enableTextFormatting)
        #expect(viewModel.state.bindings.composerFocused)
        viewModel.state.composerEmpty = false
        viewModel.process(viewAction: .sendMessage)
        #expect(viewModel.state.bindings.composerFormattingEnabled)
    }
    
    @Test
    func alertIsShownAfterLinkAction() {
        #expect(viewModel.state.bindings.alertInfo == nil)
        viewModel.process(viewAction: .enableTextFormatting)
        viewModel.process(viewAction: .composerAction(action: .link))
        #expect(viewModel.state.bindings.alertInfo != nil)
    }
    
    @Test
    func suggestions() {
        let suggestions: [SuggestionItem] = [.init(suggestionType: .user(.init(id: "@user_mention_1:matrix.org", displayName: "User 1", avatarURL: nil)), range: .init(), rawSuggestionText: ""),
                                             .init(suggestionType: .user(.init(id: "@user_mention_2:matrix.org", displayName: "User 2", avatarURL: nil)), range: .init(), rawSuggestionText: "")]
        let mockCompletionSuggestionService = CompletionSuggestionServiceMock(configuration: .init(suggestions: suggestions))
        
        let appSettings = AppSettings.volatile()
        
        viewModel = ComposerToolbarViewModel(roomProxy: JoinedRoomProxyMock(.init()),
                                             wysiwygViewModel: wysiwygViewModel,
                                             completionSuggestionService: mockCompletionSuggestionService,
                                             mediaProvider: MediaProviderMock(.init()),
                                             mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                             appSettings: appSettings,
                                             analyticsService: AnalyticsServiceMock(.init()),
                                             composerDraftService: draftServiceMock)
        
        #expect(viewModel.state.suggestions == suggestions)
    }
    
    @Test
    func suggestionTrigger() async throws {
        let deferred = deferFulfillment(wysiwygViewModel.$attributedContent) { $0.plainText == "#room-alias-test" }
        wysiwygViewModel.setMarkdownContent("@user-test")
        wysiwygViewModel.setMarkdownContent("#room-alias-test")
        try await deferred.fulfill()
        
        // The first one is nil because when initialised the view model is empty
        #expect(completionSuggestionServiceMock.setSuggestionTriggerReceivedInvocations == [nil,
                                                                                            .init(type: .user, text: "user-test", range: .init(location: 0, length: 10)),
                                                                                            .init(type: .room, text: "room-alias-test",
                                                                                                  range: .init(location: 0, length: 16))])
    }
    
    @Test
    func selectedUserSuggestion() {
        let suggestion = SuggestionItem(suggestionType: .user(.init(id: "@test:matrix.org", displayName: "Test", avatarURL: nil)), range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        // The display name can be used for HTML injection in the rich text editor and it's useless anyway as the clients don't use it when resolving display names
        #expect(wysiwygViewModel.content.html == "<a href=\"https://matrix.to/#/@test:matrix.org\">@test:matrix.org</a> ")
    }
    
    @Test
    func selectedRoomSuggestion() {
        let suggestion = SuggestionItem(suggestionType: .room(.init(id: "!room:matrix.org",
                                                                    canonicalAlias: "#room-alias:matrix.org",
                                                                    name: "Room",
                                                                    avatar: .room(id: "!room:matrix.org",
                                                                                  name: "Room",
                                                                                  avatarURL: nil))),
                                        range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        // The display name can be used for HTML injection in the rich text editor and it's useless anyway as the clients don't use it when resolving display names
        
        #expect(wysiwygViewModel.content.html == "<a href=\"https://matrix.to/#/%23room-alias:matrix.org\">#room-alias:matrix.org</a> ")
    }
    
    @Test
    func allUsersSuggestion() throws {
        let suggestion = SuggestionItem(suggestionType: .allUsers(.room(id: "", name: nil, avatarURL: nil)), range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        var string = "@room"
        try string.unicodeScalars.append(#require(UnicodeScalar(String.nbsp)))
        #expect(wysiwygViewModel.content.html == string)
    }
    
    @Test
    func userMentionPillInRTE() async {
        viewModel.context.send(viewAction: .composerAppeared)
        await Task.yield()
        let userID = "@test:matrix.org"
        let suggestion = SuggestionItem(suggestionType: .user(.init(id: userID, displayName: "Test", avatarURL: nil)), range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        let attachment = wysiwygViewModel.textView.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? PillTextAttachment
        #expect(attachment?.pillData?.type == .user(userID: userID))
    }
    
    @Test
    func roomMentionPillInRTE() async {
        viewModel.context.send(viewAction: .composerAppeared)
        await Task.yield()
        let roomAlias = "#test:matrix.org"
        let suggestion = SuggestionItem(suggestionType: .room(.init(id: "room-id", canonicalAlias: roomAlias, name: "Room", avatar: .room(id: "room-id", name: "Room", avatarURL: nil))), range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        let attachment = wysiwygViewModel.textView.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? PillTextAttachment
        #expect(attachment?.pillData?.type == .roomAlias(roomAlias))
    }
    
    @Test
    func allUsersMentionPillInRTE() async {
        viewModel.context.send(viewAction: .composerAppeared)
        await Task.yield()
        let suggestion = SuggestionItem(suggestionType: .allUsers(.room(id: "", name: nil, avatarURL: nil)), range: .init(), rawSuggestionText: "")
        viewModel.context.send(viewAction: .selectedSuggestion(suggestion))
        
        let attachment = wysiwygViewModel.textView.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? PillTextAttachment
        #expect(attachment?.pillData?.type == .allUsers)
    }
    
    @Test
    func intentionalMentions() async throws {
        wysiwygViewModel.setHtmlContent("""
        <p>Hello @room \
        and especially hello to <a href=\"https://matrix.to/#/@test:matrix.org\">Test</a></p>
        """)
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            switch action {
            case let .sendMessage(_, _, _, intentionalMentions):
                return intentionalMentions == IntentionalMentions(userIDs: ["@test:matrix.org"], atRoom: true)
            default:
                return false
            }
        }
        viewModel.context.send(viewAction: .sendMessage)
        
        try await deferred.fulfill()
    }
    
    // MARK: - Draft
    
    @Test
    func saveDraftPlainText() async throws {
        viewModel.context.composerFormattingEnabled = false
        viewModel.context.plainComposerText = .init(string: "Hello world!")
        
        var capturedDraft: ComposerDraftProxy?
        await waitForConfirmation("Save draft") { confirmation in
            draftServiceMock.saveDraftClosure = { draft in
                capturedDraft = draft
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        let draft = try #require(capturedDraft)
        #expect(draft.plainText == "Hello world!")
        #expect(draft.htmlText == nil)
        #expect(draft.draftType == .newMessage)
        #expect(draftServiceMock.saveDraftCallsCount == 1)
        #expect(!draftServiceMock.clearDraftCalled)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func saveDraftFormattedText() async throws {
        viewModel.context.composerFormattingEnabled = true
        wysiwygViewModel.setHtmlContent("<strong>Hello</strong> world!")
        
        var capturedDraft: ComposerDraftProxy?
        await waitForConfirmation("Save draft") { confirmation in
            draftServiceMock.saveDraftClosure = { draft in
                capturedDraft = draft
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        let draft = try #require(capturedDraft)
        #expect(draft.plainText == "__Hello__ world!")
        #expect(draft.htmlText == "<strong>Hello</strong> world!")
        #expect(draft.draftType == .newMessage)
        #expect(draftServiceMock.saveDraftCallsCount == 1)
        #expect(!draftServiceMock.clearDraftCalled)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func saveDraftEdit() async throws {
        viewModel.context.composerFormattingEnabled = false
        viewModel.process(timelineAction: .setMode(mode: .edit(originalEventOrTransactionID: .eventID("testID"), type: .default)))
        viewModel.context.plainComposerText = .init(string: "Hello world!")
        
        var capturedDraft: ComposerDraftProxy?
        await waitForConfirmation("Save draft") { confirmation in
            draftServiceMock.saveDraftClosure = { draft in
                capturedDraft = draft
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        let draft = try #require(capturedDraft)
        #expect(draft.plainText == "Hello world!")
        #expect(draft.htmlText == nil)
        #expect(draft.draftType == .edit(eventID: "testID"))
        #expect(draftServiceMock.saveDraftCallsCount == 1)
        #expect(!draftServiceMock.clearDraftCalled)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func saveDraftReply() async throws {
        viewModel.context.composerFormattingEnabled = false
        viewModel.process(timelineAction: .setMode(mode: .reply(eventID: "testID",
                                                                replyDetails: .loaded(sender: .init(id: ""),
                                                                                      eventID: "testID",
                                                                                      eventContent: .message(.text(.init(body: "reply text")))),
                                                                isThread: false)))
        viewModel.context.plainComposerText = .init(string: "Hello world!")
        
        var capturedDraft: ComposerDraftProxy?
        await waitForConfirmation("Save draft") { confirmation in
            draftServiceMock.saveDraftClosure = { draft in
                capturedDraft = draft
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        let draft = try #require(capturedDraft)
        #expect(draft.plainText == "Hello world!")
        #expect(draft.htmlText == nil)
        #expect(draft.draftType == .reply(eventID: "testID"))
        #expect(draftServiceMock.saveDraftCallsCount == 1)
        #expect(!draftServiceMock.clearDraftCalled)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func saveDraftWhenEmptyReply() async throws {
        viewModel.context.composerFormattingEnabled = false
        viewModel.process(timelineAction: .setMode(mode: .reply(eventID: "testID",
                                                                replyDetails: .loaded(sender: .init(id: ""),
                                                                                      eventID: "testID",
                                                                                      eventContent: .message(.text(.init(body: "reply text")))),
                                                                isThread: false)))
        
        var capturedDraft: ComposerDraftProxy?
        await waitForConfirmation("Save draft") { confirmation in
            draftServiceMock.saveDraftClosure = { draft in
                capturedDraft = draft
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        let draft = try #require(capturedDraft)
        #expect(draft.plainText == "")
        #expect(draft.htmlText == nil)
        #expect(draft.draftType == .reply(eventID: "testID"))
        #expect(draftServiceMock.saveDraftCallsCount == 1)
        #expect(!draftServiceMock.clearDraftCalled)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func clearDraftWhenEmptyNormalMessage() async {
        viewModel.context.composerFormattingEnabled = false
        
        await waitForConfirmation("Clear draft") { confirmation in
            draftServiceMock.clearDraftClosure = {
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        #expect(!draftServiceMock.saveDraftCalled)
        #expect(draftServiceMock.clearDraftCallsCount == 1)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func clearDraftForNonTextMode() async {
        viewModel.context.composerFormattingEnabled = false
        let waveformData: [Float] = Array(repeating: 1.0, count: 1000)
        viewModel.context.plainComposerText = .init(string: "Hello world!")
        viewModel.process(timelineAction: .setMode(mode: .previewVoiceMessage(state: AudioPlayerState(id: .recorderPreview, title: "", duration: 10.0),
                                                                              waveform: .data(waveformData),
                                                                              isUploading: false)))
        
        await waitForConfirmation("Clear draft") { confirmation in
            draftServiceMock.clearDraftClosure = {
                confirmation()
                return .success(())
            }
            viewModel.saveDraft()
        }
        
        #expect(!draftServiceMock.saveDraftCalled)
        #expect(draftServiceMock.clearDraftCallsCount == 1)
        #expect(!draftServiceMock.loadDraftCalled)
    }
    
    @Test
    func nothingToRestore() async {
        viewModel.context.composerFormattingEnabled = false
        draftServiceMock.loadDraftClosure = {
            .success(nil)
        }
        
        await viewModel.loadDraft()
        #expect(!viewModel.context.composerFormattingEnabled)
        #expect(viewModel.state.composerEmpty)
        #expect(viewModel.state.composerMode == .default)
    }
    
    @Test
    func restoreNormalPlainTextMessage() async {
        viewModel.context.composerFormattingEnabled = false
        draftServiceMock.loadDraftClosure = {
            .success(.init(plainText: "Hello world!",
                           htmlText: nil,
                           draftType: .newMessage))
        }
        await viewModel.loadDraft()
        
        #expect(!viewModel.context.composerFormattingEnabled)
        #expect(viewModel.state.composerMode == .default)
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: "Hello world!"))
    }
    
    @Test
    func restoreNormalFormattedTextMessage() async throws {
        viewModel.context.composerFormattingEnabled = false
        
        try await confirmation { confirmation in
            draftServiceMock.loadDraftClosure = {
                defer { confirmation() }
                return .success(.init(plainText: "__Hello__ world!",
                                      htmlText: "<strong>Hello</strong> world!",
                                      draftType: .newMessage))
            }
            
            let deferred = deferFulfillment(wysiwygViewModel.$isContentEmpty) { !$0 }
            await viewModel.loadDraft()
            try await deferred.fulfill()
        }
        
        #expect(viewModel.context.composerFormattingEnabled)
        #expect(viewModel.state.composerMode == .default)
        #expect(wysiwygViewModel.content.html == "<strong>Hello</strong> world!")
        #expect(wysiwygViewModel.content.markdown == "__Hello__ world!")
    }
    
    @Test
    func restoreEdit() async {
        viewModel.context.composerFormattingEnabled = false
        draftServiceMock.loadDraftClosure = {
            .success(.init(plainText: "Hello world!",
                           htmlText: nil,
                           draftType: .edit(eventID: "testID")))
        }
        await viewModel.loadDraft()
        
        #expect(!viewModel.context.composerFormattingEnabled)
        #expect(viewModel.state.composerMode == .edit(originalEventOrTransactionID: .eventID("testID"), type: .default))
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: "Hello world!"))
    }
    
    @Test
    func restoreReply() async throws {
        let testEventID = "testID"
        let text = "Hello world!"
        let loadedReply = TimelineItemReplyDetails.loaded(sender: .init(id: "userID",
                                                                        displayName: "Username"),
                                                          eventID: testEventID,
                                                          eventContent: .message(.text(.init(body: "Reply text"))))
        
        viewModel.context.composerFormattingEnabled = false
        draftServiceMock.loadDraftClosure = {
            .success(.init(plainText: text,
                           htmlText: nil,
                           draftType: .reply(eventID: testEventID)))
        }
        
        let deferredReplyLoaded = deferFulfillment(viewModel.context.$viewState) {
            $0.composerMode == .reply(eventID: testEventID, replyDetails: loadedReply, isThread: true)
        }
        draftServiceMock.getReplyEventIDClosure = { eventID in
            #expect(eventID == testEventID)
            try? await Task.sleep(for: .seconds(1))
            return .success(.init(details: loadedReply,
                                  isThreaded: true))
        }
        await viewModel.loadDraft()
        
        #expect(!viewModel.context.composerFormattingEnabled)
        // Testing the loading state first
        #expect(viewModel.state.composerMode == .reply(eventID: testEventID,
                                                       replyDetails: .loading(eventID: testEventID),
                                                       isThread: false))
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: text))
        
        try await deferredReplyLoaded.fulfill()
        #expect(viewModel.state.composerMode == .reply(eventID: testEventID,
                                                       replyDetails: loadedReply,
                                                       isThread: true))
    }
    
    @Test
    func restoreReplyAndCancelReplyMode() async throws {
        let testEventID = "testID"
        let text = "Hello world!"
        let loadedReply = TimelineItemReplyDetails.loaded(sender: .init(id: "userID", displayName: "Username"),
                                                          eventID: testEventID,
                                                          eventContent: .message(.text(.init(body: "Reply text"))))
        
        viewModel.context.composerFormattingEnabled = false
        draftServiceMock.loadDraftClosure = {
            .success(.init(plainText: text,
                           htmlText: nil,
                           draftType: .reply(eventID: testEventID)))
        }
        
        let replyLoadedSubject = PassthroughSubject<Void, Never>()
        let deferredReplyLoaded = deferFulfillment(replyLoadedSubject) { _ in true }
        draftServiceMock.getReplyEventIDClosure = { eventID in
            defer { replyLoadedSubject.send(()) }
            #expect(eventID == testEventID)
            try? await Task.sleep(for: .seconds(1))
            return .success(.init(details: loadedReply,
                                  isThreaded: true))
        }
        await viewModel.loadDraft()
        
        #expect(!viewModel.context.composerFormattingEnabled)
        // Testing the loading state first
        #expect(viewModel.state.composerMode == .reply(eventID: testEventID,
                                                       replyDetails: .loading(eventID: testEventID),
                                                       isThread: false))
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: text))
        
        // Now we change the state to cancel the reply mode update
        viewModel.process(viewAction: .cancelReply)
        try await deferredReplyLoaded.fulfill()
        #expect(viewModel.state.composerMode == .default)
    }
    
    @Test
    func saveVolatileDraftWhenEditing() {
        viewModel.context.composerFormattingEnabled = false
        viewModel.context.plainComposerText = .init(string: "Hello world!")
        viewModel.process(timelineAction: .setMode(mode: .edit(originalEventOrTransactionID: .eventID(UUID().uuidString), type: .default)))
        
        let draft = draftServiceMock.saveVolatileDraftReceivedDraft
        #expect(draft != nil)
        #expect(draft?.plainText == "Hello world!")
        #expect(draft?.htmlText == nil)
        #expect(draft?.draftType == .newMessage)
    }
    
    @Test
    func restoreVolatileDraftWhenCancellingEdit() async {
        await waitForConfirmation("Volatile draft loaded") { confirmation in
            draftServiceMock.loadVolatileDraftClosure = {
                defer { confirmation() }
                return .init(plainText: "Hello world",
                             htmlText: nil,
                             draftType: .newMessage)
            }
            DispatchQueue.main.async {
                self.viewModel.process(viewAction: .cancelEdit)
            }
        }
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: "Hello world"))
    }
    
    @Test
    func restoreVolatileDraftWhenClearing() async {
        await waitForConfirmation("Volatile draft loaded and cleared", expectedCount: 2) { confirmation in
            draftServiceMock.loadVolatileDraftClosure = {
                defer { confirmation() }
                return .init(plainText: "Hello world",
                             htmlText: nil,
                             draftType: .newMessage)
            }
            draftServiceMock.clearVolatileDraftClosure = {
                confirmation()
            }
            DispatchQueue.main.async {
                self.viewModel.process(timelineAction: .clear)
            }
        }
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: "Hello world"))
    }
    
    @Test
    func restoreVolatileDraftDoubleClear() async {
        await waitForConfirmation("Volatile draft loaded and cleared", expectedCount: 2) { confirmation in
            draftServiceMock.loadVolatileDraftClosure = {
                defer { confirmation() }
                return .init(plainText: "Hello world",
                             htmlText: nil,
                             draftType: .newMessage)
            }
            draftServiceMock.clearVolatileDraftClosure = {
                confirmation()
            }
            DispatchQueue.main.async {
                self.viewModel.process(timelineAction: .clear)
            }
        }
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: "Hello world"))
    }
    
    @Test
    func restoreUserMentionInPlainText() async throws {
        viewModel.context.composerFormattingEnabled = false
        let text = "Hello [TestName](https://matrix.to/#/@test:matrix.org)!"
        viewModel.process(timelineAction: .setText(plainText: text, htmlText: nil))
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            switch action {
            case let .sendMessage(plainText, _, _, intentionalMentions):
                // As of right now the markdown loses the display name when restored
                return plainText == "Hello [@test:matrix.org](https://matrix.to/#/@test:matrix.org)!" &&
                    intentionalMentions == IntentionalMentions(userIDs: ["@test:matrix.org"], atRoom: false)
            default:
                return false
            }
        }
        
        viewModel.process(viewAction: .sendMessage)
        try await deferred.fulfill()
    }
    
    @Test
    func restoreAllUsersMentionInPlainText() async throws {
        viewModel.context.composerFormattingEnabled = false
        let text = "Hello @room"
        viewModel.process(timelineAction: .setText(plainText: text, htmlText: nil))
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            switch action {
            case let .sendMessage(plainText, _, _, intentionalMentions):
                return plainText == "Hello @room" &&
                    intentionalMentions == IntentionalMentions(userIDs: [], atRoom: true)
            default:
                return false
            }
        }
        
        viewModel.process(viewAction: .sendMessage)
        try await deferred.fulfill()
    }
    
    @Test
    func restoreMixedMentionsInPlainText() async throws {
        viewModel.context.composerFormattingEnabled = false
        let text = "Hello [User1](https://matrix.to/#/@user1:matrix.org), [User2](https://matrix.to/#/@user2:matrix.org) and @room"
        viewModel.process(timelineAction: .setText(plainText: text, htmlText: nil))
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            switch action {
            case let .sendMessage(plainText, _, _, intentionalMentions):
                // As of right now the markdown loses the display name when restored
                return plainText == "Hello [@user1:matrix.org](https://matrix.to/#/@user1:matrix.org), [@user2:matrix.org](https://matrix.to/#/@user2:matrix.org) and @room" &&
                    intentionalMentions == IntentionalMentions(userIDs: ["@user1:matrix.org", "@user2:matrix.org"], atRoom: true)
            default:
                return false
            }
        }
        
        viewModel.process(viewAction: .sendMessage)
        try await deferred.fulfill()
    }
    
    @Test
    func restoreAmbiguousMention() async throws {
        viewModel.context.composerFormattingEnabled = false
        let text = "Hello [User1](https://matrix.to/#/@roomuser:matrix.org)"
        viewModel.process(timelineAction: .setText(plainText: text, htmlText: nil))
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            switch action {
            case let .sendMessage(plainText, _, _, intentionalMentions):
                // As of right now the markdown loses the display name when restored
                return plainText == "Hello [@roomuser:matrix.org](https://matrix.to/#/@roomuser:matrix.org)" &&
                    intentionalMentions == IntentionalMentions(userIDs: ["@roomuser:matrix.org"], atRoom: false)
            default:
                return false
            }
        }
        
        viewModel.process(viewAction: .sendMessage)
        try await deferred.fulfill()
    }
    
    @Test
    func restoreDoesntOverwriteInitialText() async {
        let sharedText = "Some shared text"
        var draftLoadCalled = false
        setUpViewModel(initialText: sharedText) {
            draftLoadCalled = true
            return .success(.init(plainText: "Hello world!",
                                  htmlText: nil,
                                  draftType: .newMessage))
        }
        viewModel.context.composerFormattingEnabled = false
        await viewModel.loadDraft()
        
        #expect(!draftLoadCalled)
        #expect(!viewModel.context.composerFormattingEnabled)
        #expect(viewModel.state.composerMode == .default)
        #expect(viewModel.context.plainComposerText == NSAttributedString(string: sharedText))
    }
    
    // MARK: - Identity Violation
    
    @Test
    func verificationViolationDisablesComposer() async throws {
        let mockCompletionSuggestionService = CompletionSuggestionServiceMock(configuration: .init())
        
        let roomProxyMock = JoinedRoomProxyMock(.init(name: "Test"))
        
        let roomMemberProxyMock = RoomMemberProxyMock(with: .init(userID: "@alice:localhost", membership: .join))
        roomProxyMock.getMemberUserIDClosure = { _ in
            .success(roomMemberProxyMock)
        }
        
        let mockSubject = CurrentValueSubject<[IdentityStatusChange], Never>([])
        roomProxyMock.identityStatusChangesPublisher = mockSubject.asCurrentValuePublisher()
        
        let appSettings = AppSettings.volatile()
        
        viewModel = ComposerToolbarViewModel(roomProxy: roomProxyMock,
                                             wysiwygViewModel: wysiwygViewModel,
                                             completionSuggestionService: mockCompletionSuggestionService,
                                             mediaProvider: MediaProviderMock(.init()),
                                             mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                             appSettings: appSettings,
                                             analyticsService: AnalyticsServiceMock(.init()),
                                             composerDraftService: draftServiceMock)
        
        var fulfillment = deferFulfillment(viewModel.context.$viewState, message: "Composer is disabled") { $0.canSend == false }
        mockSubject.send([IdentityStatusChange(userId: "@alice:localhost", changedTo: .verificationViolation)])
        try await fulfillment.fulfill()
        
        fulfillment = deferFulfillment(viewModel.context.$viewState, message: "Composer is enabled") { $0.canSend == true }
        mockSubject.send([IdentityStatusChange(userId: "@alice:localhost", changedTo: .pinned)])
        try await fulfillment.fulfill()
    }
    
    @Test
    func multipleViolation() async throws {
        let mockCompletionSuggestionService = CompletionSuggestionServiceMock(configuration: .init())
        
        let roomProxyMock = JoinedRoomProxyMock(.init(name: "Test"))
        
        let aliceRoomMemberProxyMock = RoomMemberProxyMock(with: .init(userID: "@alice:localhost", membership: .join))
        let bobRoomMemberProxyMock = RoomMemberProxyMock(with: .init(userID: "@bob:localhost", membership: .join))
        
        roomProxyMock.getMemberUserIDClosure = { userId in
            if userId == "@alice:localhost" {
                return .success(aliceRoomMemberProxyMock)
            } else if userId == "@bob:localhost" {
                return .success(bobRoomMemberProxyMock)
            } else {
                return .failure(.sdkError(ClientProxyMockError.generic))
            }
        }
        
        let mockSubject = CurrentValueSubject<[IdentityStatusChange], Never>([])
        
        roomProxyMock.identityStatusChangesPublisher = mockSubject.asCurrentValuePublisher()
        
        let appSettings = AppSettings.volatile()
        
        viewModel = ComposerToolbarViewModel(roomProxy: roomProxyMock,
                                             wysiwygViewModel: wysiwygViewModel,
                                             completionSuggestionService: mockCompletionSuggestionService,
                                             mediaProvider: MediaProviderMock(.init()),
                                             mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                             appSettings: appSettings,
                                             analyticsService: AnalyticsServiceMock(.init()),
                                             composerDraftService: draftServiceMock)
        
        var fulfillment = deferFulfillment(viewModel.context.$viewState, message: "Composer is disabled") { $0.canSend == false }
        mockSubject.send([
            IdentityStatusChange(userId: "@alice:localhost", changedTo: .verificationViolation),
            IdentityStatusChange(userId: "@bob:localhost", changedTo: .verificationViolation)
        ])
        try await fulfillment.fulfill()
        
        // There are 2 violations, ensure that resolving the first one is not enough.
        let failure = deferFailure(viewModel.context.$viewState, timeout: .seconds(1), message: "Composer should still be disabled") { $0.canSend == true }
        mockSubject.send([IdentityStatusChange(userId: "@alice:localhost", changedTo: .pinned)])
        try await failure.fulfill()
        
        fulfillment = deferFulfillment(viewModel.context.$viewState, message: "Composer is now enabled") { $0.canSend == true }
        mockSubject.send([IdentityStatusChange(userId: "@bob:localhost", changedTo: .pinned)])
        try await fulfillment.fulfill()
    }
    
    @Test
    func pinViolationDoesNotDisableComposer() async throws {
        let mockCompletionSuggestionService = CompletionSuggestionServiceMock(configuration: .init())
        
        let roomProxyMock = JoinedRoomProxyMock(.init(name: "Test"))
        let roomMemberProxyMock = RoomMemberProxyMock(with: .init(userID: "@alice:localhost", membership: .join))
        
        roomProxyMock.getMemberUserIDClosure = { _ in
            .success(roomMemberProxyMock)
        }
        
        roomProxyMock.identityStatusChangesPublisher = CurrentValueSubject([IdentityStatusChange(userId: "@alice:localhost", changedTo: .pinViolation)]).asCurrentValuePublisher()
        let appSettings = AppSettings.volatile()
        
        viewModel = ComposerToolbarViewModel(roomProxy: roomProxyMock,
                                             wysiwygViewModel: wysiwygViewModel,
                                             completionSuggestionService: mockCompletionSuggestionService,
                                             mediaProvider: MediaProviderMock(.init()),
                                             mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                             appSettings: appSettings,
                                             analyticsService: AnalyticsServiceMock(.init()),
                                             composerDraftService: draftServiceMock)
        
        let deferred = deferFulfillment(viewModel.context.$viewState, message: "Composer should be enabled") { $0.canSend == true }
        try await deferred.fulfill()
    }
    
    // MARK: - Helpers
    
    private func setUpViewModel(initialText: String? = nil, loadDraftClosure: (() async -> Result<ComposerDraftProxy?, ComposerDraftServiceError>)? = nil) {
        wysiwygViewModel = WysiwygComposerViewModel()
        completionSuggestionServiceMock = CompletionSuggestionServiceMock(configuration: .init())
        draftServiceMock = ComposerDraftServiceMock(.init())
        emojiProviderSpy = EmojiProviderSpy()
        if let loadDraftClosure {
            draftServiceMock.loadDraftClosure = loadDraftClosure
        }
        
        stickerServiceMock = StickerServiceMock()
        stickerServiceMock.builtInStickers = []
        stickerServiceMock.loadStickersReturnValue = StickerCollection()
        stickerServiceMock.sendInReturnValue = .success(())
        stickerServiceMock.sendExternalStickerImageDataBodyWidthHeightMimeTypeInReturnValue = .success(())
        gifServiceMock = KlipyServiceMock()
        gifServiceMock.searchQueryPageReturnValue = .success(.init(stickers: [], hasNextPage: false, nextPage: 2))
        gifServiceMock.downloadImageFromReturnValue = .success(Data("gif".utf8))
        timelineControllerMock = TimelineControllerMock(.init())
        
        let appSettings = AppSettings.volatile()
        
        viewModel = ComposerToolbarViewModel(initialText: initialText,
                                             roomProxy: JoinedRoomProxyMock(.init()),
                                             wysiwygViewModel: wysiwygViewModel,
                                             completionSuggestionService: completionSuggestionServiceMock,
                                             mediaProvider: MediaProviderMock(.init()),
                                             mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                             appSettings: appSettings,
                                             analyticsService: AnalyticsServiceMock(.init()),
                                             composerDraftService: draftServiceMock,
                                             emojiProvider: emojiProviderSpy,
                                             stickerService: stickerServiceMock,
                                             gifService: gifServiceMock,
                                             timelineController: timelineControllerMock,
                                             mediaUserIndicatorController: UserIndicatorControllerMock())
        viewModel.context.composerFormattingEnabled = true
    }
}

private final class EmojiProviderSpy: EmojiProviderProtocol {
    var state: EmojiProviderState = .notLoaded
    var categoriesToReturn: [EmojiCategory] = [EmojiCategory(id: "smileys", emojis: [EmojiItem(label: "grinning", unicode: "😀", keywords: [], shortcodes: [])])]
    private(set) var markedEmojis: [String] = []
    
    func categories(searchString: String?) async -> [EmojiCategory] {
        categoriesToReturn
    }
    
    func frequentlyUsedSystemEmojis() -> [String] {
        []
    }
    
    func markEmojiAsFrequentlyUsed(_ emoji: String) {
        markedEmojis.append(emoji)
    }
}
