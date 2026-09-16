import SwiftUI

struct PlayerQualitySelectionAvailabilityModifier: ViewModifier {
    @ObservedObject private var player = PlayerManager.shared

    func body(content: Content) -> some View {
        content
            .disabled(!player.isCurrentPlaybackQualitySelectable)
            .opacity(player.isCurrentPlaybackQualitySelectable ? 1 : 0.42)
    }
}

extension View {
    func playerQualitySelectionAvailability() -> some View {
        modifier(PlayerQualitySelectionAvailabilityModifier())
    }
}

/// Full-screen scrim and scrollable menu anchored below its trigger.
struct PlayerMoreMenu: View {
    @Binding var isPresented: Bool
    let anchorFrame: CGRect
    var isDarkBackground: Bool = false
    /// 是否显示"沉浸模式"入口（沉浸模式内部的菜单不显示）
    var showImmersiveEntry: Bool = true
    /// 横屏播放器可直接在三点菜单内选择主题，避免再弹出受方向锁影响的 Sheet。
    var presentsThemeInline: Bool = false
    var onQuality: (() -> Void)? = nil
    var onEQ: () -> Void
    var onTheme: (() -> Void)? = nil
    var bloudGazeControl: BloudGazeMenuControl? = nil
    var palette: MonoMoreMenuPalette? = nil
    
    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var sleepTimer = PlayerManager.shared.sleepAndFade
    @ObservedObject private var gameMode = GameModeManager.shared
    @ObservedObject private var eqManager = EQManager.shared
    @ObservedObject private var aiEqualizerAgent = AIEqualizerAgent.shared
    @ObservedObject private var monoSuite = MonoNextSuiteManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var lyricViewModel = LyricViewModel.shared
    @ObservedObject private var monoSession = MonoSessionManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var lyricDownloadManager = LyricDownloadManager.shared
    @ObservedObject private var themeManager = PlayerThemeManager.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("enableKaraoke") private var enableKaraoke = false
    @AppStorage("showTranslation") private var showTranslation = true
    @State private var showTimerSheet = false
    @State private var showLyricSourceSheet = false
    @State private var showImmersiveSettings = false
    @State private var showPlayerTypography = false
    @State private var showMonoSession = false
    @State private var showCurrentSongDownload = false
    @State private var showDownloadManager = false
    @State private var showsInlineThemeChoices = false
    @State private var selectedSongForInfo: Song?
    /// 子级页面关闭时，Sheet 的绑定会先复位；单独保留转场状态，避免菜单短暂重绘。
    @State private var isPresentingChild = false

    private var textColor: Color { palette?.text ?? .monoTextPrimary }
    private var secondaryColor: Color { palette?.secondary ?? .monoTextSecondary }
    private var accentColor: Color { palette?.accent ?? .monoAccent }
    private var accentForeground: Color { palette?.onAccent ?? .monoAccentForeground }
    private var separatorColor: Color { palette?.separator ?? .monoSeparator }

    /// 自定义开关不能再借用正文色透明度：部分主题会覆盖正文色，导致
    /// 深色菜单里的关闭轨道和滑块一起发白。这里使用明确的深浅色语义色。
    private var toggleOffTrackColor: Color {
        Color(
            light: Color.black.opacity(0.13),
            dark: Color.white.opacity(0.18)
        )
    }

    private var toggleOffThumbColor: Color {
        Color(
            light: Color.white,
            dark: Color.white.opacity(0.76)
        )
    }

    private var currentLyricSource: LyricSource? {
        guard let song = player.currentSong else { return nil }
        return lyricViewModel.selectedSource(for: song)
    }
    
    private var timerStatusText: String? {
        if player.pendingSleepStopAfterCurrentTrack {
            return String(localized: "podcast_timer_pending_short")
        }
        guard let remaining = sleepTimer.remaining else { return nil }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var soundCenterStatusText: String {
        if player.currentSong?.isAppleMusic == true {
            return String(localized: "apple_music_protected_audio")
        }
        if aiEqualizerAgent.phase.isWorking {
            return String(localized: "mono_audio_tuning")
        }

        if aiEqualizerAgent.isCurrentProposalApplied {
            let name = aiEqualizerAgent.proposal?.profileName
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { return name }
        }

        if eqManager.isEnabled {
            let name = eqManager.currentPreset?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? String(localized: "eq_custom") : name
        }

        let activeEnhancements = [
            MonoNextFeature.spatialLive,
            .dna,
            .recovery
        ].filter { monoSuite.isEnabled($0) }.count
        if activeEnhancements > 0 {
            return String(
                format: String(localized: "mono_suite_running_count"),
                activeEnhancements,
                3
            )
        }

        return String(localized: "settings_off")
    }

    private var currentDownloadStatus: String? {
        guard let song = player.currentSong else { return nil }
        if song.isAppleMusic {
            return String(localized: "apple_music_download_unavailable")
        }
        if downloadManager.localFileURL(for: song) != nil {
            return String(localized: "已下载")
        }
        if let task = downloadManager.task(for: song) {
            return "\(Int(task.progress * 100))%"
        }
        if lyricDownloadManager.record(for: song) != nil {
            return String(localized: "歌词已下载")
        }
        return nil
    }

    private var downloadManagerStatus: String? {
        let count = downloadManager.fetchAllDownloaded().count + lyricDownloadManager.records.count
        return count > 0 ? "\(count)" : nil
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        GeometryReader { proxy in
            let panelWidth = min(292, max(0, proxy.size.width - 24))
            let top = max(12, anchorFrame.maxY + 8)
            let panelMaxHeight = max(0, proxy.size.height - top - max(12, proxy.safeAreaInsets.bottom))
            let preferredX = layoutDirection == .rightToLeft ? anchorFrame.minX : anchorFrame.maxX - panelWidth
            let left = min(max(12, preferredX), max(12, proxy.size.width - panelWidth - 12))
            // Anchors use physical coordinates; position mirrors its x value in RTL.
            let centerX = layoutDirection == .rightToLeft
                ? proxy.size.width - left - panelWidth / 2
                : left + panelWidth / 2

            ZStack(alignment: .topTrailing) {
                Color.black.opacity(isDarkBackground ? 0.07 : 0.035)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(0)
                    .onTapGesture {
                        closeMenu()
                    }

                if !isPresentingChild {
                    Group {
                        if presentsThemeInline {
                            landscapeMenuPanel
                        } else {
                            menuPanel
                        }
                    }
                    .frame(width: panelWidth, height: panelMaxHeight, alignment: .top)
                    .position(x: centerX, y: top + panelMaxHeight / 2)
                    .zIndex(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                }
            }
        }
        .monoIconDarkArtworkSurface(isDarkBackground)
        .monoSheet(isPresented: $showTimerSheet, onDismiss: {
            closeMenu()
        }, preset: .standard){
            PodcastTimerSheet()

        }
        .monoSheet(isPresented: $showLyricSourceSheet, onDismiss: {
            closeMenu()
        }, preset: .compact) {
            CurrentSongLyricSourceSheet()
        }
        .monoSheet(isPresented: $showCurrentSongDownload, onDismiss: {
            closeMenu()
        }, preset: .standard) {
            CurrentSongDownloadSheet()
        }
        .fullScreenCover(isPresented: $showImmersiveSettings, onDismiss: {
            closeMenu()
        }) {
            // 从普通播放器进入：全程竖屏，不做横竖屏切换
            NavigationStack {
                AriaSettingsPage(palette: .fallback, managesOrientation: false)
            }
        }
        .fullScreenCover(isPresented: $showPlayerTypography, onDismiss: {
            closeMenu()
        }) {
            NavigationStack {
                PlayerTypographySettingsView()
            }
        }
        .fullScreenCover(isPresented: $showMonoSession, onDismiss: {
            closeMenu()
        }) {
            NavigationStack {
                MonoSessionPlayerView()
            }
        }
        .fullScreenCover(isPresented: $showDownloadManager, onDismiss: {
            closeMenu()
        }) {
            NavigationStack {
                DownloadManageView()
            }
        }
        .fullScreenCover(item: $selectedSongForInfo, onDismiss: {
            closeMenu()
        }) { song in
            NavigationStack {
                SongDetailView(song: song)
            }
        }
    }

    private var menuPanel: some View {
        MonoMoreMenuPanel(
            title: String(localized: "player_more_title"),
            isDarkBackground: isDarkBackground,
            palette: palette,
            closeAction: closeMenu
        ) {
            ScrollView {
                menuPanelContent
            }
            .scrollIndicators(.hidden)
        }
    }

    /// 收音机使用独立的横屏菜单布局：工具卡片、主题入口和功能分组
    /// 都在同一块面板内完成，避免竖屏菜单的长列表在横屏下被截断。
    private var landscapeMenuPanel: some View {
        MonoMoreMenuPanel(
            title: String(localized: "player_more_title"),
            isDarkBackground: isDarkBackground,
            palette: palette,
            closeAction: closeMenu
        ) {
            ScrollView {
                if showsInlineThemeChoices {
                    inlineThemeChooserPage
                } else {
                    landscapeMenuContent
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var landscapeMenuContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bloudGazeControl { menuGroup { bloudGazeControl } }
            landscapeQuickActionGrid

            landscapeThemeCard

            menuSection(title: String(localized: "player_more_lyrics_section")) {
                lyricActionList
            }

            menuSection(title: String(localized: "player_more_player_section")) {
                playerActionList
            }
        }
    }

    private var landscapeQuickActionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8),
            ],
            spacing: 8
        ) {
            if let onQuality {
                landscapeQuickAction(
                    icon: .soundQuality,
                    title: String(localized: "quality_title"),
                    status: player.qualityButtonText,
                    isEnabled: player.currentSong != nil && player.isCurrentPlaybackQualitySelectable
                ) {
                    closeMenu()
                    onQuality()
                }
            }

            landscapeQuickAction(
                icon: .clock,
                title: String(localized: "podcast_timer_title"),
                status: timerStatusText
            ) {
                isPresentingChild = true
                showTimerSheet = true
            }

            landscapeQuickAction(
                icon: .audioWave,
                artwork: .soundCenter,
                title: String(localized: "mono_audio_center_title"),
                status: soundCenterStatusText
            ) {
                closeMenu()
                onEQ()
            }
        }
    }

    private var landscapeThemeCard: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                showsInlineThemeChoices = true
            }
        } label: {
            HStack(spacing: 11) {
                menuRowIcon(.playerTheme, isActive: true, isEnabled: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "theme_title"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(textColor.opacity(0.94))

                    Text(themeManager.currentTheme.displayName)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                MonoIcon(icon: .chevronRight, size: 11, color: textColor.opacity(0.62))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accentColor.opacity(0.10))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(accentColor.opacity(0.32), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func landscapeQuickAction(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        status: String?,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                MonoIcon(icon: icon, size: 16, color: isEnabled ? accentColor : textColor.opacity(0.34))
                    .monoIconArtwork(artwork?.rawValue)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor.opacity(isEnabled ? 0.92 : 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryColor.opacity(isEnabled ? 1 : 0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(textColor.opacity(isEnabled ? 0.055 : 0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(separatorColor.opacity(0.5), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var menuPanelContent: some View {
        Group {
            if presentsThemeInline && showsInlineThemeChoices {
                inlineThemeChooserPage
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let bloudGazeControl { menuGroup { bloudGazeControl } }
                    // 横屏收音机的主题入口固定在三点菜单首屏，
                    // 不依赖菜单滚动到播放器分组后才能触发。
                    if presentsThemeInline {
                        menuGroup {
                            menuActionRow(
                                icon: .playerTheme,
                                title: String(localized: "theme_title"),
                                status: themeManager.currentTheme.displayName
                            ) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showsInlineThemeChoices = true
                                }
                            }
                        }
                    }

                    menuSection(title: String(localized: "player_more_playback_section")) {
                        playbackQuickActions
                    }

                    menuSection(title: String(localized: "player_more_lyrics_section")) {
                        lyricActionList
                    }

                    menuSection(title: String(localized: "player_more_player_section")) {
                        playerActionList
                    }
                }
            }
        }
    }

    private var lyricActionList: some View {
        menuGroup {
            menuActionRow(
                icon: .musicNoteList,
                title: String(localized: "lyric_source_change"),
                status: currentLyricSource?.shortName,
                statusSource: currentLyricSource?.musicSource,
                isEnabled: player.currentSong != nil
            ) {
                isPresentingChild = true
                showLyricSourceSheet = true
            }

            menuDivider

            menuActionRow(
                icon: .translate,
                title: String(localized: "player_more_lyrics_appearance")
            ) {
                isPresentingChild = true
                showPlayerTypography = true
            }

            menuDivider

            menuToggleRow(
                icon: .karaoke,
                title: String(localized: "逐字歌词"),
                isOn: $enableKaraoke
            )

            menuDivider

            menuToggleRow(
                icon: .translate,
                title: String(localized: "显示翻译"),
                isOn: $showTranslation
            )
        }
    }

    private var playerActionList: some View {
        menuGroup {
            menuActionRow(
                icon: .infoCircle,
                title: String(localized: "player_more_song_info"),
                isEnabled: player.currentSong != nil
            ) {
                guard let song = player.currentSong else { return }
                isPresentingChild = true
                selectedSongForInfo = song
            }

            menuDivider

            menuActionRow(
                icon: .personCircle,
                title: String(localized: "mono_session_title"),
                status: monoSessionMenuStatus
            ) {
                isPresentingChild = true
                showMonoSession = true
            }

            if !presentsThemeInline, let onTheme {
                menuDivider

                menuActionRow(
                    icon: .playerTheme,
                    title: String(localized: "theme_title")
                ) {
                    closeMenu()
                    onTheme()
                }
            }

            if showImmersiveEntry {
                menuDivider
                immersiveMenuRow
            }

            menuDivider

            menuToggleRow(
                icon: .waveform,
                title: String(localized: "player_more_game_mode"),
                isOn: Binding(
                    get: { gameMode.isActive },
                    set: { newValue in
                        guard newValue != gameMode.isActive else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        gameMode.toggle()
                    }
                )
            )

            if AppConfig.Features.restrictedDownloadEnabled {
                menuDivider

                menuActionRow(
                    icon: .playerDownload,
                    title: String(localized: "下载当前歌曲"),
                    status: currentDownloadStatus,
                    isEnabled: player.currentSong != nil
                        && player.currentSong?.isAppleMusic != true
                ) {
                    isPresentingChild = true
                    showCurrentSongDownload = true
                }

                menuDivider

                menuActionRow(
                    icon: .storage,
                    title: String(localized: "下载管理"),
                    status: downloadManagerStatus
                ) {
                    isPresentingChild = true
                    showDownloadManager = true
                }
            }
        }
    }

    private var inlineThemeChooser: some View {
        // The menu already owns a vertical ScrollView. A nested horizontal
        // ScrollView/LazyHGrid was unreliable in the forced-landscape radio
        // layout: the cards rendered, but their hit regions could be consumed
        // by the parent gesture area. Keep a single scroll container and let
        // the parent menu scroll through a regular two-column grid.
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 7),
                GridItem(.flexible(minimum: 0), spacing: 7),
            ],
            spacing: 7
        ) {
            ForEach(PlayerTheme.allCases) { theme in
                inlineThemeButton(theme)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var inlineThemeChooserPage: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsInlineThemeChoices = false
                }
            } label: {
                HStack(spacing: 9) {
                    MonoIcon(icon: .chevronLeft, size: 13, color: textColor.opacity(0.78))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(textColor.opacity(0.045))
                        )

                    Text(String(localized: "theme_title"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(textColor.opacity(0.92))

                    Spacer(minLength: 0)

                    Text(themeManager.currentTheme.displayName)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            inlineThemeChooser
        }
        .contentShape(Rectangle())
    }

    private func inlineThemeButton(_ theme: PlayerTheme) -> some View {
        let isSelected = themeManager.currentTheme == theme

        return Button {
            guard !isSelected else {
                closeMenu()
                return
            }
            HapticManager.shared.light()
            themeManager.setTheme(theme)
            closeMenu()
        } label: {
            HStack(spacing: 6) {
                Text(theme.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? accentColor : textColor.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                if isSelected {
                    MonoIcon(icon: .checkmark, size: 9, color: accentColor, lineWidth: 2)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 112, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? accentColor.opacity(0.13)
                            : textColor.opacity(0.045)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isSelected
                            ? accentColor.opacity(0.5)
                            : separatorColor.opacity(0.45),
                        lineWidth: 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var playbackQuickActions: some View {
        HStack(spacing: 8) {
            if let onQuality {
                quickAction(
                    icon: .soundQuality,
                    title: String(localized: "quality_title"),
                    status: player.qualityButtonText,
                    isEnabled: player.currentSong != nil && player.isCurrentPlaybackQualitySelectable
                ) {
                    closeMenu()
                    onQuality()
                }
            }

            quickAction(
                icon: .clock,
                title: String(localized: "podcast_timer_title"),
                status: timerStatusText
            ) {
                isPresentingChild = true
                showTimerSheet = true
            }

            quickAction(
                icon: .audioWave,
                artwork: .soundCenter,
                title: String(localized: "mono_audio_center_title"),
                status: soundCenterStatusText
            ) {
                closeMenu()
                onEQ()
            }
        }
    }

    private var monoSessionMenuStatus: String? {
        guard let room = monoSession.room else { return nil }
        return String(format: String(localized: "mono_session_member_count"), room.participants.count)
    }

    private func menuActionRow(
        icon: MonoIcon.IconType,
        title: String,
        status: String? = nil,
        statusSource: MusicSource? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                menuRowIcon(icon, isActive: false, isEnabled: isEnabled)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor.opacity(isEnabled ? 0.92 : 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                if let status, !status.isEmpty {
                    if let statusSource {
                        PlatformBadgeLabel(text: status, source: statusSource, fontSize: 9.5)
                            .opacity(isEnabled ? 1 : 0.34)
                    } else {
                        Text(status)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(secondaryColor.opacity(isEnabled ? 1 : 0.34))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .monospacedDigit()
                    }
                }

                MonoIcon(
                    icon: .chevronRight,
                    size: 10,
                    color: secondaryColor.opacity(isEnabled ? 0.62 : 0.22)
                )
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityValue(status ?? "")
    }

    private func menuToggleRow(
        icon: MonoIcon.IconType,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                isOn.wrappedValue.toggle()
            }
            HapticManager.shared.light()
        } label: {
            HStack(spacing: 10) {
                menuRowIcon(icon, isActive: isOn.wrappedValue, isEnabled: true)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? accentColor : toggleOffTrackColor)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle()
                            .fill(
                                isOn.wrappedValue
                                    ? accentForeground
                                    : toggleOffThumbColor
                            )
                            .frame(width: 14, height: 14)
                            .padding(2)
                            .shadow(
                                color: Color.black.opacity(isOn.wrappedValue ? 0.12 : 0.18),
                                radius: 1.5,
                                y: 0.5
                            )
                    }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "1" : "0")
    }

    private var immersiveMenuRow: some View {
        HStack(spacing: 0) {
            Button {
                closeMenu()
                ImmersiveModeController.shared.present()
            } label: {
                HStack(spacing: 10) {
                    menuRowIcon(.immersive, isActive: false, isEnabled: true)

                    Text(String(localized: "player_more_enter_immersive"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(textColor.opacity(0.92))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(separatorColor.opacity(0.8))
                .frame(width: 0.5, height: 22)

            Button {
                isPresentingChild = true
                showImmersiveSettings = true
            } label: {
                MonoIcon(icon: .settings, size: 15, color: textColor.opacity(0.72))
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "player_more_immersive_settings"))
        }
    }

    private func menuRowIcon(
        _ icon: MonoIcon.IconType,
        isActive: Bool,
        isEnabled: Bool
    ) -> some View {
        MonoIcon(
            icon: icon,
            size: 14,
            color: isActive
                ? accentColor
                : textColor.opacity(isEnabled ? 0.78 : 0.3)
        )
        .frame(width: 26, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isActive
                        ? accentColor.opacity(0.13)
                        : textColor.opacity(isEnabled ? 0.04 : 0.02)
                )
        )
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(separatorColor.opacity(0.72))
            .frame(height: 0.5)
            .padding(.leading, 47)
    }

    private func menuGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(textColor.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(separatorColor.opacity(0.52), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func menuSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(secondaryColor)
                .padding(.horizontal, 4)

            content()
        }
    }

    private func quickAction(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        status: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                MonoIcon(
                    icon: icon,
                    size: 16,
                    color: textColor.opacity(isEnabled ? 0.9 : 0.34)
                )
                .monoIconArtwork(artwork?.rawValue)

                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor.opacity(isEnabled ? 0.9 : 0.34))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .center)

                if let status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryColor.opacity(isEnabled ? 1 : 0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66, alignment: .center)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(textColor.opacity(isEnabled ? 0.055 : 0.025))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityValue(status ?? "")
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
            showsInlineThemeChoices = false
        }
    }
}

struct CurrentSongLyricSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss
    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var lyricViewModel = LyricViewModel.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let _ = settings.globalThemeRevision

        VStack(spacing: 18) {
            header

            if let song = player.currentSong {
                VStack(spacing: 0) {
                    automaticSourceRow(song)

                    Rectangle()
                        .fill(Color.monoSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, 18)

                    ForEach(LyricSource.allCases) { source in
                        sourceRow(source, song: song)

                        if source != LyricSource.allCases.last {
                            Rectangle()
                                .fill(Color.monoSeparator)
                                .frame(height: 0.5)
                                .padding(.leading, 18)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.monoTextPrimary.opacity(0.055))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.monoSeparator, lineWidth: 0.5)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        .padding(.bottom, 10)
        .iPadContentWidth(500)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "lyric_source_change"))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundColor(.monoTextPrimary)

                if let song = player.currentSong {
                    Text(song.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.monoTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                close()
            } label: {
                MonoIcon(icon: .close, size: 14, color: .monoTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.monoTextPrimary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common_close"))
        }
    }

    private func automaticSourceRow(_ song: Song) -> some View {
        let isSelected = lyricViewModel.pinnedSource(for: song) == nil
        let tint = (lyricViewModel.activeSource?.musicSource ?? song.musicSource).themedBadgeColor

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            lyricViewModel.useAutomaticSource(for: song)
            close()
        } label: {
            HStack(spacing: 12) {
                Text(String(localized: "lyric_source_automatic"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.monoTextPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    if lyricViewModel.isLoading {
                        ProgressView()
                            .tint(tint)
                            .controlSize(.small)
                    } else {
                        MonoIcon(icon: .checkmark, size: 15, color: tint, lineWidth: 2)
                    }
                }
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? String(localized: "lyric_source_selected") : "")
    }

    private func sourceRow(_ source: LyricSource, song: Song) -> some View {
        let isSelected = lyricViewModel.pinnedSource(for: song) == source
        let tint = source.musicSource.themedBadgeColor

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            lyricViewModel.changeSource(source, for: song)
            close()
        } label: {
            HStack(spacing: 12) {
                PlatformBadgeLabel(text: source.shortName, source: source.musicSource, fontSize: 12)

                Spacer(minLength: 0)

                if isSelected {
                    if lyricViewModel.isLoading && lyricViewModel.activeSource == source {
                        ProgressView()
                            .tint(tint)
                            .controlSize(.small)
                    } else {
                        MonoIcon(icon: .checkmark, size: 15, color: tint, lineWidth: 2)
                    }
                }
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? String(localized: "lyric_source_selected") : "")
    }

    private func close() {
        dismissCurrentPresentation(
            systemDismiss: dismiss,
            monoSheetDismiss: monoSheetDismiss
        )
    }
}
