//  游戏模式设置页：电源台主开关 + 场景预设 + 子项配置

import SwiftUI

struct GameModeSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var gameMode = GameModeManager.shared
    @ObservedObject private var localPlaylists = LocalPlaylistManager.shared

    @State private var showQualityDialog = false
    @State private var showPlaylistDialog = false
    @State private var powerPulse = false

    private let gameQualityOptions: [SoundQuality] = [
        .standard, .higher, .exhigh, .lossless
    ]

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedSettingsBackground()

            ScrollView {
                VStack(spacing: 24) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "game_mode_settings_title"),
                        eyebrow: String(localized: "settings_eyebrow_game_mode"),
                        icon: .playCircle,
                        artwork: .gameMode,
                        signalModule: .game
                    )

                    VStack(spacing: 24) {
                        powerConsole

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(
                                title: String(localized: "game_mode_preset_section_title"),
                                caption: String(localized: "game_mode_preset_section_subtitle")
                            )

                            HStack(spacing: 10) {
                                ForEach(GameModeScenarioPreset.allCases) { preset in
                                    scenarioCard(preset)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(title: String(localized: "game_mode_options_section_title"))
                            optionsSection
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(title: String(localized: "game_mode_presets_section_title"))
                            presetsSection
                        }

                        infoFootnote
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(700)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
            .onChange(of: settings.gameModeAutoDucking) { _, _ in refreshMatchedPreset() }
            .onChange(of: settings.gameModeLowerQuality) { _, _ in refreshMatchedPreset() }
            .onChange(of: settings.gameModeSilentNowPlaying) { _, _ in refreshMatchedPreset() }
            .onChange(of: settings.gameModeAutoExit) { _, _ in refreshMatchedPreset() }
        }
        .asideSettingsDetailChrome()
        .confirmationDialog(
            String(localized: "game_mode_preferred_quality_title"),
            isPresented: $showQualityDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "game_mode_preferred_quality_auto"), role: .none) {
                settings.gameModePreferredQuality = nil
            }
            ForEach(gameQualityOptions, id: \.self) { quality in
                Button(quality.displayName) {
                    settings.gameModePreferredQuality = quality
                }
            }
        } message: {
            Text(String(localized: "game_mode_preferred_quality_desc"))
        }
        .confirmationDialog(
            String(localized: "game_mode_preset_playlist_title"),
            isPresented: $showPlaylistDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "game_mode_preset_playlist_none"), role: .destructive) {
                settings.gameModeAutoPlaylistLocalId = ""
            }
            ForEach(localPlaylists.playlists, id: \.id) { playlist in
                Button(playlist.name) {
                    settings.gameModeAutoPlaylistLocalId = playlist.id
                }
            }
        } message: {
            Text(String(localized: "game_mode_preset_playlist_desc"))
        }
    }

    // MARK: - 小节标题

    private func sectionHeader(title: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(gameModeAccent)
                    .frame(width: 3, height: 12)

                Text(title)
                    .font(.rounded(size: 14.5, weight: .bold))
                    .foregroundColor(gameModePrimaryText)

                Rectangle()
                    .fill(gameModeDivider.opacity(0.5))
                    .frame(height: 0.5)
            }

            if let caption {
                Text(caption)
                    .font(.rounded(size: 11.5))
                    .foregroundColor(gameModeSecondaryText)
                    .padding(.leading, 11)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - 电源台（主开关）

    private var powerConsole: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            gameMode.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 状态眉题
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(gameMode.isActive ? gameModeAccent : gameModeMutedText.opacity(0.4))
                                    .frame(width: 6, height: 6)

                                if gameMode.isActive {
                                    Circle()
                                        .stroke(gameModeAccent.opacity(0.5), lineWidth: 1)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(powerPulse ? 2.6 : 1)
                                        .opacity(powerPulse ? 0 : 0.8)
                                }
                            }
                            .frame(width: 16, height: 16)

                            Text(gameMode.isActive ? "ACTIVE" : "STANDBY")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(2.2)
                                .foregroundColor(gameMode.isActive ? gameModeAccent : gameModeSecondaryText.opacity(0.7))
                        }

                        Text(String(localized: "game_mode_main_title"))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(gameModePrimaryText)
                            .padding(.top, 10)

                        Text(gameMode.isActive
                             ? String(localized: "game_mode_main_subtitle_on")
                             : String(localized: "game_mode_main_subtitle_off"))
                            .font(.rounded(size: 12.5))
                            .foregroundColor(gameModeSecondaryText)
                            .lineSpacing(2)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    // 电源钮
                    ZStack {
                        Circle()
                            .fill(gameMode.isActive ? gameModeAccent : gameModeIconFill)
                            .frame(width: 62, height: 62)
                            .shadow(
                                color: gameMode.isActive ? gameModeAccent.opacity(0.36) : .clear,
                                radius: 12, y: 5
                            )

                        Circle()
                            .stroke(
                                gameMode.isActive
                                    ? Color.white.opacity(0.35)
                                    : gameModeDivider.opacity(0.5),
                                lineWidth: 1
                            )
                            .frame(width: 62, height: 62)

                        MonoSemanticIcon(
                            semantic: .gameModePower,
                            fallback: .playCircle,
                            size: 23,
                            color: gameMode.isActive ? gameModeAccentText : gameModeSecondaryText
                        )
                    }
                    .animation(.spring(response: 0.34, dampingFraction: 0.75), value: gameMode.isActive)
                }

                // 生效项指示灯排
                HStack(spacing: 0) {
                    consoleLamp(
                        label: String(localized: "game_mode_lamp_ducking"),
                        lit: gameMode.isActive && settings.gameModeAutoDucking
                    )
                    consoleLamp(
                        label: String(localized: "game_mode_lamp_quality"),
                        lit: gameMode.isActive && settings.gameModeLowerQuality
                    )
                    consoleLamp(
                        label: String(localized: "game_mode_lamp_silent"),
                        lit: gameMode.isActive && settings.gameModeSilentNowPlaying
                    )
                    consoleLamp(
                        label: String(localized: "game_mode_lamp_auto_exit"),
                        lit: gameMode.isActive && settings.gameModeAutoExit
                    )
                }
                .padding(.top, 18)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(gameModeDivider.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.top, 9)
                }
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .themedPageSurface(cornerRadius: 20, elevated: true, mangaTint: MangaStyle.bubbleWhite)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: gameMode.isActive) { _, _ in startPulseIfNeeded() }
    }

    private func consoleLamp(label: String, lit: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(lit ? gameModeAccent : gameModeMutedText.opacity(0.25))
                .frame(width: 5, height: 5)

            Text(label)
                .font(.rounded(size: 10.5, weight: .semibold))
                .foregroundColor(lit ? gameModePrimaryText.opacity(0.85) : gameModeMutedText.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: lit)
    }

    private func startPulseIfNeeded() {
        powerPulse = false
        guard gameMode.isActive else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            powerPulse = true
        }
    }

    // MARK: - 场景预设（FPS / RPG / 音游）

    @State private var matchedPreset: GameModeScenarioPreset? = GameModeScenarioApplier.currentMatchedPreset

    private func refreshMatchedPreset() {
        let newValue = GameModeScenarioApplier.currentMatchedPreset
        if newValue != matchedPreset {
            withAnimation(.easeInOut(duration: 0.22)) {
                matchedPreset = newValue
            }
        }
    }

    private func scenarioCard(_ preset: GameModeScenarioPreset) -> some View {
        let isSelected = matchedPreset == preset
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            GameModeScenarioApplier.apply(preset)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                matchedPreset = preset
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoSemanticIcon(
                        semantic: preset.monoGlyphSemantic,
                        fallback: preset.fallbackIcon,
                        size: 17,
                        color: isSelected ? gameModeAccentText : gameModePrimaryText.opacity(0.8)
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isSelected ? gameModeAccent : gameModeIconFill.opacity(0.8))
                    )

                    Spacer(minLength: 0)

                    // 单选点
                    Circle()
                        .stroke(
                            isSelected ? gameModeAccent : gameModeDivider.opacity(0.8),
                            lineWidth: isSelected ? 4.5 : 1.2
                        )
                        .frame(width: isSelected ? 11 : 14, height: isSelected ? 11 : 14)
                        .frame(width: 14, height: 14)
                }

                Text(preset.localizedTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(gameModePrimaryText)
                    .lineLimit(1)
                    .padding(.top, 12)

                Text(preset.localizedSubtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(gameModeSecondaryText)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .themedPageSurface(cornerRadius: 16, elevated: isSelected, mangaTint: MangaStyle.bubbleWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? gameModeAccent.opacity(0.75) : Color.clear,
                        lineWidth: 1.3
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
    }

    // MARK: - 子项

    private var optionsSection: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(
                icon: .audioWave,
                artwork: .gameVoicePriority,
                title: String(localized: "game_mode_option_ducking_title"),
                subtitle: String(localized: "game_mode_option_ducking_subtitle"),
                isOn: Binding(
                    get: { settings.gameModeAutoDucking },
                    set: { newValue in
                        settings.gameModeAutoDucking = newValue
                        // 若游戏模式已开启，立即重新应用 AVAudioSession options
                        if gameMode.isActive {
                            PlayerManager.shared.handleGameModeDuckingChanged()
                        }
                    }
                )
            )

            Divider()
                .overlay(gameModeDivider)
                .opacity(0.65)
                .padding(.leading, 62)

            SettingsToggleRow(
                icon: .soundQuality,
                artwork: .gameLowerQuality,
                title: String(localized: "game_mode_option_quality_title"),
                subtitle: String(localized: "game_mode_option_quality_subtitle"),
                isOn: Binding(
                    get: { settings.gameModeLowerQuality },
                    set: { newValue in
                        settings.gameModeLowerQuality = newValue
                        gameMode.reapplyQualityPreference()
                    }
                )
            )

            Divider()
                .overlay(gameModeDivider)
                .opacity(0.65)
                .padding(.leading, 62)

            SettingsToggleRow(
                icon: .close,
                artwork: .gameAutoExit,
                title: String(localized: "game_mode_option_auto_exit_title"),
                subtitle: String(localized: "game_mode_option_auto_exit_subtitle"),
                isOn: Binding(
                    get: { settings.gameModeAutoExit },
                    set: { newValue in
                        settings.gameModeAutoExit = newValue
                        if gameMode.isActive {
                            gameMode.reapplyAutoExitObserver()
                        }
                    }
                )
            )

            Divider()
                .overlay(gameModeDivider)
                .opacity(0.65)
                .padding(.leading, 62)

            SettingsToggleRow(
                icon: .lock,
                artwork: .gameSilentNowPlaying,
                title: String(localized: "game_mode_option_silent_np_title"),
                subtitle: String(localized: "game_mode_option_silent_np_subtitle"),
                isOn: Binding(
                    get: { settings.gameModeSilentNowPlaying },
                    set: { newValue in
                        settings.gameModeSilentNowPlaying = newValue
                        if gameMode.isActive {
                            PlayerManager.shared.updateNowPlayingInfo()
                        }
                    }
                )
            )

            if settings.gameModeSilentNowPlaying {
                Divider()
                    .overlay(gameModeDivider)
                    .opacity(0.65)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .list,
                    artwork: .gameMinimalNowPlaying,
                    title: String(localized: "game_mode_option_minimal_np_title"),
                    subtitle: String(localized: "game_mode_option_minimal_np_subtitle"),
                    isOn: Binding(
                        get: { settings.gameModeMinimalNowPlaying },
                        set: { newValue in
                            settings.gameModeMinimalNowPlaying = newValue
                            if gameMode.isActive {
                                PlayerManager.shared.updateNowPlayingInfo()
                            }
                        }
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: settings.gameModeSilentNowPlaying)
        .themedPageSurface(cornerRadius: 18, elevated: true, mangaTint: MangaStyle.bubbleWhite)
    }

    // MARK: - 指定歌单 / 指定音质

    private var presetsSection: some View {
        VStack(spacing: 0) {
            // 指定音质
            Button {
                showQualityDialog = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconBadge(icon: .soundQuality, artwork: .gamePreferredQuality)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "game_mode_preferred_quality_entry_title"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(gameModePrimaryText)
                        Text(preferredQualitySubtitle)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(gameModeMutedText)
                            .lineLimit(1)
                    }
                    Spacer()
                    MonoIcon(icon: .chevronRight, size: 12, color: gameModeMutedText.opacity(0.55), lineWidth: 1.6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(gameModeDivider)
                .opacity(0.65)
                .padding(.leading, 62)

            // 指定歌单
            Button {
                showPlaylistDialog = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconBadge(icon: .list, artwork: .gameAutoPlaylist)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "game_mode_preset_playlist_entry_title"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(gameModePrimaryText)
                        Text(presetPlaylistSubtitle)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(gameModeMutedText)
                            .lineLimit(1)
                    }
                    Spacer()
                    MonoIcon(icon: .chevronRight, size: 12, color: gameModeMutedText.opacity(0.55), lineWidth: 1.6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .themedPageSurface(cornerRadius: 18, elevated: true, mangaTint: MangaStyle.bubbleWhite)
    }

    private var preferredQualitySubtitle: String {
        if let quality = settings.gameModePreferredQuality {
            return quality.displayName
        }
        return String(localized: "game_mode_preferred_quality_auto")
    }

    private var presetPlaylistSubtitle: String {
        let id = settings.gameModeAutoPlaylistLocalId
        if id.isEmpty {
            return String(localized: "game_mode_preset_playlist_none")
        }
        if let match = localPlaylists.playlists.first(where: { $0.id == id }) {
            return match.name
        }
        return String(localized: "game_mode_preset_playlist_invalid")
    }

    // MARK: - 说明

    private var infoFootnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "game_mode_info_title"))
                    .font(.rounded(size: 12, weight: .bold))
                    .foregroundColor(gameModeSecondaryText)

                Rectangle()
                    .fill(gameModeDivider.opacity(0.5))
                    .frame(height: 0.5)
            }

            Text(String(localized: "game_mode_info_body"))
                .font(.rounded(size: 12))
                .foregroundColor(gameModeSecondaryText.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var gameModeAccent: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.accent : Color(hex: "FF8FA8")
    }

    private var gameModeAccentText: Color {
        if NeumorphicStyle.isActive {
            return ThemeColorCustomization.readableForegroundColor(
                on: NeumorphicStyle.accent,
                light: Color(hex: "172026"),
                dark: .white
            )
        }
        return .white
    }

    private var gameModeIconFill: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : Color.monoIconBackground
    }

    private var gameModePrimaryText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary
    }

    private var gameModeSecondaryText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary
    }

    private var gameModeMutedText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : .monoTextSecondary
    }

    private var gameModeDivider: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.separator.opacity(0.65) : .monoSeparator
    }
}

private extension GameModeScenarioPreset {
    var monoGlyphSemantic: MonoGlyphSemantic {
        switch self {
        case .fps: return .gamePresetFPS
        case .rpg: return .gamePresetRPG
        case .rhythm: return .gamePresetRhythm
        }
    }

    var fallbackIcon: MonoIcon.IconType {
        switch self {
        case .fps: return .fullscreen
        case .rpg: return .catStory
        case .rhythm: return .musicNote
        }
    }
}
