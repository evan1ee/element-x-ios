// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal nonisolated enum UntranslatedL10n {
  /// Show keyboard
  internal static var a11yShowKeyboard: String { return UntranslatedL10n.tr("Untranslated", "a11y_show_keyboard") }
  /// Show emoji, GIFs and stickers
  internal static var a11yShowMediaInput: String { return UntranslatedL10n.tr("Untranslated", "a11y_show_media_input") }
  /// Add to stickers
  internal static var actionAddToStickers: String { return UntranslatedL10n.tr("Untranslated", "action_add_to_stickers") }
  /// Sticker added
  internal static var commonStickerAdded: String { return UntranslatedL10n.tr("Untranslated", "common_sticker_added") }
  /// Delete existing backup
  internal static var screenBackupConfirmDisableDelete: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_confirm_disable_delete") }
  /// Keep existing backup
  internal static var screenBackupConfirmDisableKeep: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_confirm_disable_keep") }
  /// What should happen to the backup that is already stored?
  internal static var screenBackupConfirmDisableMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_confirm_disable_message") }
  /// Disable Backup
  internal static var screenBackupConfirmDisableTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_confirm_disable_title") }
  /// Your messages, search index and app preferences are copied. Downloaded media is not — it is fetched again when needed.
  /// 
  /// The backup is encrypted on this device before it is uploaded. Keep your passphrase safe: without it the backup cannot be restored.
  internal static var screenBackupContentsMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_contents_message") }
  /// What gets backed up
  internal static var screenBackupContentsTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_contents_title") }
  /// Backup destination
  internal static var screenBackupDestination: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_destination") }
  /// Enable backup
  internal static var screenBackupEnable: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_enable") }
  /// Automatically back up your offline data. Your backup is encrypted before upload.
  internal static var screenBackupEnableFooter: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_enable_footer") }
  /// This backup belongs to a different account
  internal static var screenBackupErrorAccountMismatch: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_account_mismatch") }
  /// The backup is damaged and cannot be read
  internal static var screenBackupErrorCorrupted: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_corrupted") }
  /// Wrong passphrase
  internal static var screenBackupErrorDecryption: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_decryption") }
  /// Could not encrypt the backup
  internal static var screenBackupErrorEncryption: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_encryption") }
  /// Network unavailable
  internal static var screenBackupErrorNetwork: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_network") }
  /// Sign in to the backup destination
  internal static var screenBackupErrorNotAuthenticated: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_not_authenticated") }
  /// Permission denied
  internal static var screenBackupErrorPermission: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_permission") }
  /// Backup destination unavailable
  internal static var screenBackupErrorProviderUnavailable: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_provider_unavailable") }
  /// Storage full
  internal static var screenBackupErrorStorageFull: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_storage_full") }
  /// This backup was made by a newer version of the app
  internal static var screenBackupErrorVersion: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_error_version") }
  /// Last backup
  internal static var screenBackupLastBackup: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_last_backup") }
  /// Never
  internal static var screenBackupNever: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_never") }
  /// No backups yet
  internal static var screenBackupNoBackups: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_no_backups") }
  /// You will need this passphrase to restore on another device. It cannot be recovered.
  internal static var screenBackupPassphraseFooter: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_passphrase_footer") }
  /// Backup passphrase
  internal static var screenBackupPassphrasePlaceholder: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_passphrase_placeholder") }
  /// Choose a passphrase
  internal static var screenBackupPassphraseTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_passphrase_title") }
  /// Compressing
  internal static var screenBackupPhaseCompressing: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_phase_compressing") }
  /// Encrypting
  internal static var screenBackupPhaseEncrypting: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_phase_encrypting") }
  /// Exporting
  internal static var screenBackupPhaseExporting: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_phase_exporting") }
  /// Preparing
  internal static var screenBackupPhasePreparing: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_phase_preparing") }
  /// Uploading
  internal static var screenBackupPhaseUploading: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_phase_uploading") }
  /// iCloud Drive
  internal static var screenBackupProviderIcloud: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_provider_icloud") }
  /// Local file
  internal static var screenBackupProviderLocalFile: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_provider_local_file") }
  /// WebDAV
  internal static var screenBackupProviderWebdav: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_provider_webdav") }
  /// Restore from backup
  internal static var screenBackupRestore: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore") }
  /// Downloading
  internal static var screenBackupRestorePhaseDownloading: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_phase_downloading") }
  /// Finding backup
  internal static var screenBackupRestorePhaseFinding: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_phase_finding") }
  /// Restoring
  internal static var screenBackupRestorePhaseRestoring: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_phase_restoring") }
  /// Validating
  internal static var screenBackupRestorePhaseValidating: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_phase_validating") }
  /// The backup has been decrypted and will be put in place the next time you open the app. Close and reopen %1$@ to finish restoring.
  internal static func screenBackupRestoreStagedMessage(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_staged_message", String(describing: p1))
  }
  /// Restart to finish
  internal static var screenBackupRestoreStagedTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_restore_staged_title") }
  /// Backup size
  internal static var screenBackupSize: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_size") }
  /// Status
  internal static var screenBackupStatus: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_status") }
  /// Complete
  internal static var screenBackupStatusCompleted: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_status_completed") }
  /// Failed
  internal static var screenBackupStatusFailed: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_status_failed") }
  /// Not backed up
  internal static var screenBackupStatusIdle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_status_idle") }
  /// Storage & Backup
  internal static var screenBackupTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_title") }
  /// Back up now
  internal static var screenBackupUpNow: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_up_now") }
  /// Wi-Fi only
  internal static var screenBackupWifiOnly: String { return UntranslatedL10n.tr("Untranslated", "screen_backup_wifi_only") }
  /// Search
  internal static var screenHomeTabSearch: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_search") }
  /// Add image or GIF
  internal static var screenMediaInputAddSticker: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_add_sticker") }
  /// Activity
  internal static var screenMediaInputCategoryActivity: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_activity") }
  /// Flags
  internal static var screenMediaInputCategoryFlags: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_flags") }
  /// Food & Drink
  internal static var screenMediaInputCategoryFood: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_food") }
  /// Frequently Used
  internal static var screenMediaInputCategoryFrequentlyUsed: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_frequently_used") }
  /// Animals & Nature
  internal static var screenMediaInputCategoryNature: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_nature") }
  /// Objects
  internal static var screenMediaInputCategoryObjects: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_objects") }
  /// Smileys & People
  internal static var screenMediaInputCategoryPeople: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_people") }
  /// Travel & Places
  internal static var screenMediaInputCategoryPlaces: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_places") }
  /// Symbols
  internal static var screenMediaInputCategorySymbols: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_category_symbols") }
  /// Emoji
  internal static var screenMediaInputEmoji: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_emoji") }
  /// GIFs
  internal static var screenMediaInputGifs: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_gifs") }
  /// No results
  internal static var screenMediaInputNoResults: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_no_results") }
  /// Resize panel
  internal static var screenMediaInputResizeHandle: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_resize_handle") }
  /// Search emoji
  internal static var screenMediaInputSearchEmojis: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_search_emojis") }
  /// Search GIFs
  internal static var screenMediaInputSearchGifs: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_search_gifs") }
  /// Stickers
  internal static var screenMediaInputStickers: String { return UntranslatedL10n.tr("Untranslated", "screen_media_input_stickers") }
  /// %1$@ Default
  internal static func screenNotificationSettingsSoundAppDefaultIos(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_notification_settings_sound_app_default_ios", String(describing: p1))
  }
  /// %1$@ Fade
  internal static func screenNotificationSettingsSoundAppFadeIos(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_notification_settings_sound_app_fade_ios", String(describing: p1))
  }
  /// Be in your %1$@
  internal static func screenOnboardingWelcomeTitleIos(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_onboarding_welcome_title_ios", String(describing: p1))
  }
  /// Sticker
  internal static var screenRoomAttachmentSourceSticker: String { return UntranslatedL10n.tr("Untranslated", "screen_room_attachment_source_sticker") }
  /// Offline history
  internal static var screenRoomDetailsOfflineHistory: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history") }
  /// Available
  internal static var screenRoomDetailsOfflineHistoryComplete: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history_complete") }
  /// Downloading…
  internal static var screenRoomDetailsOfflineHistoryDownloading: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history_downloading") }
  /// Incomplete
  internal static var screenRoomDetailsOfflineHistoryError: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history_error") }
  /// Partly available
  internal static var screenRoomDetailsOfflineHistoryPartial: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history_partial") }
  /// Paused
  internal static var screenRoomDetailsOfflineHistoryPaused: String { return UntranslatedL10n.tr("Untranslated", "screen_room_details_offline_history_paused") }
  /// Unsupported call. Ask if the caller can use the new %1$@ app.
  internal static func screenRoomTimelineLegacyCallIos(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_legacy_call_ios", String(describing: p1))
  }
  /// Search for chats and messages
  internal static var screenSearchEmptyStateMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_message") }
  /// Start searching...
  internal static var screenSearchEmptyStateTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_title") }
  /// Older messages are still downloading. Results may be incomplete.
  internal static var screenSearchIncompleteHistory: String { return UntranslatedL10n.tr("Untranslated", "screen_search_incomplete_history") }
  /// There are no results for “%1$@.” Try a new search term.
  internal static func screenSearchNoResultsMessage(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_search_no_results_message", String(describing: p1))
  }
  /// Messages
  internal static var screenSearchTabMessages: String { return UntranslatedL10n.tr("Untranslated", "screen_search_tab_messages") }
  /// Rooms
  internal static var screenSearchTabRooms: String { return UntranslatedL10n.tr("Untranslated", "screen_search_tab_rooms") }
  /// View download progress
  internal static var screenSearchViewDownloadProgress: String { return UntranslatedL10n.tr("Untranslated", "screen_search_view_download_progress") }
  /// Add to my stickers
  internal static var screenStickerDiscoveryAddToMyStickers: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_discovery_add_to_my_stickers") }
  /// No stickers found
  internal static var screenStickerDiscoveryEmpty: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_discovery_empty") }
  /// Couldn’t load stickers
  internal static var screenStickerDiscoveryError: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_discovery_error") }
  /// Search stickers
  internal static var screenStickerDiscoverySearchPlaceholder: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_discovery_search_placeholder") }
  /// Discover
  internal static var screenStickerDiscoveryTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_discovery_title") }
  /// Add sticker
  internal static var screenStickerPickerAddSticker: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_add_sticker") }
  /// Plural format key: "%#@COUNT@"
  internal static func screenStickerPickerAddedCount(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_added_count", p1)
  }
  /// Built-in
  internal static var screenStickerPickerBuiltInStickers: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_built_in_stickers") }
  /// Plural format key: "%#@COUNT@"
  internal static func screenStickerPickerDuplicateCount(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_duplicate_count", p1)
  }
  /// Plural format key: "%#@COUNT@"
  internal static func screenStickerPickerFailedCount(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_failed_count", p1)
  }
  /// My stickers
  internal static var screenStickerPickerMyStickers: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_my_stickers") }
  /// Stickers
  internal static var screenStickerPickerTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_picker_title") }
  /// Used to search and download stickers from Klipy in the sticker discovery screen.
  internal static var screenStickerSettingsApiKeyFooter: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_settings_api_key_footer") }
  /// Klipy API key
  internal static var screenStickerSettingsApiKeyTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_settings_api_key_title") }
  /// Reset to default
  internal static var screenStickerSettingsReset: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_settings_reset") }
  /// Stickers
  internal static var screenStickerSettingsTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_sticker_settings_title") }
  /// Active room
  internal static var screenSyncStorageActiveRoom: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_active_room") }
  /// Advanced
  internal static var screenSyncStorageAdvanced: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_advanced") }
  /// Continue in the background
  internal static var screenSyncStorageBackground: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_background") }
  /// Keep downloading history while the app is in the background.
  internal static var screenSyncStorageBackgroundDescription: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_background_description") }
  /// Calculating…
  internal static var screenSyncStorageCalculating: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_calculating") }
  /// Clear offline history
  internal static var screenSyncStorageClearHistory: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_clear_history") }
  /// Downloaded history will be removed from this device. Your messages are not deleted.
  internal static var screenSyncStorageClearHistoryConfirmation: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_clear_history_confirmation") }
  /// All synchronised messages are now available offline.
  internal static var screenSyncStorageCompletedDescription: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_completed_description") }
  /// Database
  internal static var screenSyncStorageDatabase: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_database") }
  /// Download full history
  internal static var screenSyncStorageDownloadHistory: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_download_history") }
  /// Fetches every message so search covers your whole history, not only what has been read on this device.
  internal static var screenSyncStorageDownloadHistoryDescription: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_download_history_description") }
  /// Sign-in expired
  internal static var screenSyncStorageErrorAuthentication: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_error_authentication") }
  /// Network unavailable
  internal static var screenSyncStorageErrorNetwork: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_error_network") }
  /// Server temporarily unavailable
  internal static var screenSyncStorageErrorServer: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_error_server") }
  /// Storage full
  internal static var screenSyncStorageErrorStorageFull: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_error_storage_full") }
  /// History Download
  internal static var screenSyncStorageHistoryDownload: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_history_download") }
  /// Last error
  internal static var screenSyncStorageLastError: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_last_error") }
  /// Last synchronised
  internal static var screenSyncStorageLastSync: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_last_sync") }
  /// Media cache
  internal static var screenSyncStorageMediaCache: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_media_cache") }
  /// Messages
  internal static var screenSyncStorageMessages: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_messages") }
  /// Waiting for a connection
  internal static var screenSyncStorageOffline: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_offline") }
  /// Pause download
  internal static var screenSyncStoragePause: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_pause") }
  /// Queued
  internal static var screenSyncStorageQueueLength: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_queue_length") }
  /// Rebuild search index
  internal static var screenSyncStorageRebuildIndex: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_rebuild_index") }
  /// The index will be discarded and built again. Search will be incomplete until it finishes.
  internal static var screenSyncStorageRebuildIndexConfirmation: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_rebuild_index_confirmation") }
  /// Resume download
  internal static var screenSyncStorageResume: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_resume") }
  /// Retry failed downloads
  internal static var screenSyncStorageRetry: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_retry") }
  /// Rooms
  internal static var screenSyncStorageRooms: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_rooms") }
  /// Search index
  internal static var screenSyncStorageSearchIndex: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_search_index") }
  /// Empty
  internal static var screenSyncStorageSearchIndexEmpty: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_search_index_empty") }
  /// Healthy
  internal static var screenSyncStorageSearchIndexHealthy: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_search_index_healthy") }
  /// Complete
  internal static var screenSyncStorageStatusCompleted: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_completed") }
  /// Downloading
  internal static var screenSyncStorageStatusDownloading: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_downloading") }
  /// Error
  internal static var screenSyncStorageStatusError: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_error") }
  /// Not started
  internal static var screenSyncStorageStatusNotStarted: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_not_started") }
  /// Paused
  internal static var screenSyncStorageStatusPaused: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_paused") }
  /// Preparing
  internal static var screenSyncStorageStatusPreparing: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_status_preparing") }
  /// About %1$@ remaining
  internal static func screenSyncStorageTimeRemaining(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_time_remaining", String(describing: p1))
  }
  /// Sync & Storage
  internal static var screenSyncStorageTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_title") }
  /// Total
  internal static var screenSyncStorageTotal: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_total") }
  /// Waiting for Wi-Fi
  internal static var screenSyncStorageWaitingForWifi: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_waiting_for_wifi") }
  /// Wi-Fi only
  internal static var screenSyncStorageWifiOnly: String { return UntranslatedL10n.tr("Untranslated", "screen_sync_storage_wifi_only") }
  /// Clear all data currently stored on this device?
  /// Sign in again to access your account data and messages.
  internal static var softLogoutClearDataDialogContent: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_content") }
  /// Clear data
  internal static var softLogoutClearDataDialogTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_title") }
  /// Warning: Your personal data (including encryption keys) is still stored on this device.
  /// 
  /// Clear it if you’re finished using this device, or want to sign in to another account.
  internal static var softLogoutClearDataNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_notice") }
  /// Clear all data
  internal static var softLogoutClearDataSubmit: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_submit") }
  /// Clear personal data
  internal static var softLogoutClearDataTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_title") }
  /// Sign in to recover encryption keys stored exclusively on this device. You need them to read all of your secure messages on any device.
  internal static var softLogoutSigninE2eWarningNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_e2e_warning_notice") }
  /// Your homeserver (%1$s) admin has signed you out of your account %2$s (%3$s).
  internal static func softLogoutSigninNotice(_ p1: UnsafePointer<CChar>, _ p2: UnsafePointer<CChar>, _ p3: UnsafePointer<CChar>) -> String {
    return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_notice", p1, p2, p3)
  }
  /// Sign in
  internal static var softLogoutSigninTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_title") }
  /// Untranslated
  internal static var untranslated: String { return UntranslatedL10n.tr("Untranslated", "untranslated") }
  /// Plural format key: "%#@VARIABLE@"
  internal static func untranslatedPlural(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "untranslated_plural", p1)
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

nonisolated extension UntranslatedL10n {
  static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    // No need to check languages, we always default to en for untranslated strings
    guard let bundle = Bundle.lprojBundle(for: "en") else { return key }
    let format = NSLocalizedString(key, tableName: table, bundle: bundle, comment: "")
    return String(format: format, locale: Locale(identifier: "en"), arguments: args)
  }
}

// swiftlint:enable all
