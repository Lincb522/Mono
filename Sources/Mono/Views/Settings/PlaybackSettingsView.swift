//  播放设置子页面

import Combine
import SwiftUI

struct PlaybackSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    private let eqManager = EQManager.shared
    @State private var isEqualizerEnabled = EQManager.shared.isEnabled
    @State private var equalizerPresetName = EQManager.shared.currentPreset?.name
    @ObservedObject private var gameMode = GameModeManager.shared

    @State private var showPlaybackQualitySheet = false
    @State private var showKugouPlaybackQualitySheet = false
    @State private var showQQPlaybackQualitySheet = false
    @State private var showQishuiPlaybackQualitySheet = false
    @State private var showBackgroundAudioPolicySheet = false

    var body: some View {
        ZStack {
            ThemedSettingsBackground()

            ScrollView {
                VStack(spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "settings_navigation_playback_title"),
                        eyebrow: String(localized: "settings_eyebrow_playback"),
                        icon: .playCircle,
                        signalModule: .playback
                    )

                    VStack(spacing: SettingsPageLayout.sectionSpacing) {
                        qualitySection
                        queueSection
                        effectsSection
                        storageSyncSection
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 44)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .onReceive(eqManager.$isEnabled.removeDuplicates()) {
            isEqualizerEnabled = $0
        }
        .onReceive(eqManager.$currentPreset.map { $0?.name }.removeDuplicates()) {
            equalizerPresetName = $0
        }
        .onChange(of: settings.gaplessPlaybackEnabled) { _, enabled in
            PlayerManager.shared.handleGaplessPlaybackSettingChanged(enabled: enabled)
        }
        .onChange(of: settings.crossfadePlaybackEnabled) { _, enabled in
            PlayerManager.shared.handleCrossfadePlaybackSettingChanged(enabled: enabled)
        }
        .onChange(of: settings.backgroundAudioPolicyRaw) { _, _ in
            PlayerManager.shared.handleBackgroundAudioPolicySettingChanged()
        }
        .monoSheet(isPresented: $showBackgroundAudioPolicySheet, preset: .standard) {
            BackgroundAudioPolicySheet()
        }
        .monoSheet(isPresented: $showPlaybackQualitySheet, preset: .standard) {
            SoundQualitySheet(
                currentQuality: SoundQuality(rawValue: settings.defaultPlaybackQuality) ?? .standard,
                currentQQQuality: .mp3_320,
                isQQMusic: false,
                onSelectNetease: { quality in
                    settings.defaultPlaybackQuality = quality.rawValue
                    showPlaybackQualitySheet = false
                },
                onSelectQQ: { _ in }
            )
        }
        .monoSheet(isPresented: $showQQPlaybackQualitySheet, preset: .standard) {
            SoundQualitySheet(
                currentQuality: .standard,
                currentQQQuality: QQMusicQuality(rawValue: settings.defaultQQPlaybackQuality) ?? .mp3_320,
                isQQMusic: true,
                onSelectNetease: { _ in },
                onSelectQQ: { quality in
                    settings.defaultQQPlaybackQuality = quality.rawValue
                    showQQPlaybackQualitySheet = false
                }
            )
        }
        .monoSheet(isPresented: $showKugouPlaybackQualitySheet, preset: .standard) {
            SoundQualitySheet(
                currentQuality: .standard,
                currentQQQuality: .mp3_320,
                isQQMusic: false,
                onSelectNetease: { _ in },
                onSelectQQ: { _ in },
                kugouMode: true,
                currentKugouQuality: SoundQuality(rawValue: settings.defaultKugouPlaybackQuality) ?? .standard,
                onSelectKugou: { quality in
                    settings.defaultKugouPlaybackQuality = quality.rawValue
                    PlayerManager.shared.kugouSoundQuality = quality
                    showKugouPlaybackQualitySheet = false
                }
            )
        }
        .monoSheet(isPresented: $showQishuiPlaybackQualitySheet, preset: .standard) {
            QishuiQualityPickerSheet(
                currentQuality: settings.defaultQishuiPlaybackQuality,
                onSelect: { quality in
                    settings.defaultQishuiPlaybackQuality = quality
                    PlayerManager.shared.qishuiSelectedQuality = quality
                    showQishuiPlaybackQualitySheet = false
                }
            )
        }
    }

    // MARK: - Sections

    private var qualitySection: some View {
        SettingsSection(title: String(localized: "settings_playback_quality_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .soundQuality,
                    title: String(localized: "settings_prefer_highest_playback_quality"),
                    subtitle: String(localized: "settings_prefer_highest_playback_quality_desc"),
                    isOn: $settings.preferHighestPlaybackQuality
                )

                if !settings.preferHighestPlaybackQuality {
                    Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                    SettingsNavigationRow(
                        icon: .soundQuality,
                        title: String(localized: "settings_netease_playback_quality"),
                        value: defaultPlaybackQualityText
                    ) {
                        showPlaybackQualitySheet = true
                    }

                    Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                    SettingsNavigationRow(
                        icon: .soundQuality,
                        title: String(localized: "settings_kcm_playback_quality"),
                        value: defaultKugouPlaybackQualityText
                    ) {
                        showKugouPlaybackQualitySheet = true
                    }

                    Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                    SettingsNavigationRow(
                        icon: .soundQuality,
                        title: String(localized: "settings_qq_playback_quality"),
                        value: defaultQQPlaybackQualityText
                    ) {
                        showQQPlaybackQualitySheet = true
                    }

                    Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                    SettingsNavigationRow(
                        icon: .soundQuality,
                        title: String(localized: "settings_qsm_playback_quality"),
                        value: defaultQishuiPlaybackQualityText
                    ) {
                        showQishuiPlaybackQualitySheet = true
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: settings.preferHighestPlaybackQuality)
        }
    }

    private var queueSection: some View {
        SettingsSection(title: String(localized: "settings_playback_queue_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .musicNoteList,
                    title: String(localized: "settings_insert_playback_context"),
                    subtitle: playbackContextModeSubtitle,
                    isOn: $settings.insertPlaybackContext
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .podcast,
                    title: String(localized: "播客播放顺序"),
                    subtitle: settings.podcastSortAscending ? String(localized: "最早一期优先") : String(localized: "最新一期优先"),
                    isOn: $settings.podcastSortAscending
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .playNext,
                    title: String(localized: "settings_gapless_playback"),
                    subtitle: String(localized: "settings_gapless_playback_desc"),
                    isOn: $settings.gaplessPlaybackEnabled
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .waveform,
                    title: String(localized: "settings_crossfade_playback"),
                    subtitle: String(localized: "settings_crossfade_playback_duration"),
                    isOn: $settings.crossfadePlaybackEnabled
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsNavigationRow(
                    icon: .headphones,
                    title: String(localized: "settings_background_audio_policy"),
                    subtitle: backgroundAudioPolicyRowSubtitle
                ) {
                    showBackgroundAudioPolicySheet = true
                }
            }
        }
    }

    private var effectsSection: some View {
        SettingsSection(title: String(localized: "settings_playback_effects_section")) {
            VStack(spacing: 0) {
                SettingsLinkRow(
                    icon: .waveform,
                    artwork: .gameMode,
                    title: String(localized: "game_mode_settings_entry"),
                    subtitle: gameModeSubtitle,
                    destination: GameModeSettingsView()
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .waveform,
                    title: String(localized: "settings_global_equalizer"),
                    subtitle: globalEqualizerSubtitle,
                    isOn: Binding(
                        get: { isEqualizerEnabled },
                        set: { eqManager.isEnabled = $0 }
                    )
                )

            }
        }
    }

    private var storageSyncSection: some View {
        SettingsSection(title: String(localized: "settings_playback_local_sync_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .lock,
                    title: String(localized: "settings_qmc_decrypt"),
                    subtitle: String(localized: "settings_qmc_decrypt_desc"),
                    isOn: $settings.qmcDecryptEnabled
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .like,
                    title: String(localized: "settings_sync_like_ncm_title"),
                    subtitle: String(localized: "settings_sync_like_ncm_subtitle"),
                    isOn: $settings.syncLikeToNetease
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .musicNoteList,
                    title: String(localized: "settings_like_choose_playlist_title"),
                    subtitle: String(localized: "settings_like_choose_playlist_subtitle"),
                    isOn: $settings.likeToChoosePlaylist
                )
            }
        }
    }

    // MARK: - Helpers

    private var defaultPlaybackQualityText: String {
        (SoundQuality(rawValue: settings.defaultPlaybackQuality) ?? .standard).displayName
    }

    private var defaultQQPlaybackQualityText: String {
        (QQMusicQuality(rawValue: settings.defaultQQPlaybackQuality) ?? .mp3_320).displayName
    }

    private var defaultKugouPlaybackQualityText: String {
        (SoundQuality(rawValue: settings.defaultKugouPlaybackQuality) ?? .standard).displayName
    }

    private var defaultQishuiPlaybackQualityText: String {
        QishuiQualityPickerSheet.displayName(for: settings.defaultQishuiPlaybackQuality)
    }

    private var playbackContextModeSubtitle: String {
        settings.insertPlaybackContext
            ? String(localized: "settings_insert_playback_context_desc_insert")
            : String(localized: "settings_insert_playback_context_desc_replace")
    }

    private var globalEqualizerSubtitle: String {
        if isEqualizerEnabled {
            let presetName = equalizerPresetName ?? NSLocalizedString("eq_custom", comment: "")
            return String(format: String(localized: "settings_global_equalizer_enabled"), presetName)
        }
        return String(localized: "settings_global_equalizer_desc")
    }

    private var gameModeSubtitle: String {
        gameMode.isActive
            ? String(localized: "game_mode_settings_subtitle_on")
            : String(localized: "game_mode_settings_subtitle_off")
    }

    /// 行内副标题：当前模式名 + 一句话说明
    private var backgroundAudioPolicyRowSubtitle: String {
        "\(settings.backgroundAudioPolicy.displayName) · \(settings.backgroundAudioPolicy.detailText)"
    }
}
