import SwiftUI

/// iCloud 同步设置页：展示同步状态与本地内容概览，
/// 提供自动同步开关、手动上传/恢复以及清除云端快照（需二次确认）等操作。
struct CloudSyncSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @ObservedObject private var playlistCloudSync = LocalPlaylistCloudSyncManager.shared

    @State private var showClearCloudConfirm = false

    private var accent: Color {
        return .monoAccent
    }

    private var summary: CloudSyncContentSummary {
        playlistCloudSync.localContentSummary
    }

    var body: some View {
        ZStack {
            ThemedSettingsBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "settings_navigation_cloud_sync_title"),
                        eyebrow: String(localized: "settings_eyebrow_cloud"),
                        icon: .cloud,
                        signalModule: .cloud
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        statusPanel
                        cloudContentSection
                        syncSection
                        actionSection
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 44)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .onChange(of: settings.playlistSyncAutoEnabled) { _, enabled in
            guard enabled else { return }
            playlistCloudSync.resumeAutomaticSync()
        }
        .confirmationDialog(
            String(localized: "playlist_sync_clear_cloud_button"),
            isPresented: $showClearCloudConfirm
        ) {
            Button(String(localized: "playlist_sync_clear_cloud_confirm"), role: .destructive) {
                runSyncAction {
                    try await playlistCloudSync.clearCloudSnapshot()
                }
            }
        } message: {
            Text(String(localized: "playlist_sync_clear_cloud_message"))
        }
    }

    // MARK: - 分区视图

    /// 顶部状态卡：服务端未提供字节级上传进度，因此同步中明确使用不定进度，
    /// 不伪造百分比；空闲时显示真实在线状态。
    private var statusPanel: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.16))
                MonoIcon(
                    icon: playlistCloudSync.isSyncing ? .refresh : .cloud,
                    size: 19,
                    color: accent
                )
                .monoCompletionMotion(trigger: playlistCloudSync.isSyncing)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.monoTextPrimary)
                    .lineLimit(1)

                Text(playlistSyncStatusText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.monoTextSecondary)
                    .lineLimit(2)

                if playlistCloudSync.isSyncing {
                    MonoLiquidProgressBar(
                        progress: nil,
                        tint: accent,
                        secondaryTint: accent.opacity(0.58),
                        isActive: true,
                        height: 4
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                }
            }

            Spacer(minLength: 8)

            if playlistCloudSync.isSyncing {
                MonoStatusBeacon(kind: .active, tint: accent, size: 9)
            } else {
                MonoStatusBeacon(
                    kind: onlineAccess.canUseOnlineFeatures ? .success : .failed,
                    tint: accent,
                    size: 9
                )
                    .accessibilityLabel(statusTitle)
            }
        }
        .padding(14)
        .background(cardBackground)
        .monoGlass(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 本地可同步内容的数量概览（歌单/下载/播客/个性化等）。
    private var cloudContentSection: some View {
        section(title: String(localized: "cloud_sync_content_title")) {
            VStack(spacing: 0) {
                contentRow(
                    icon: .musicNoteList,
                    title: String(localized: "cloud_sync_playlists"),
                    value: String(
                        format: String(localized: "cloud_sync_playlist_value"),
                        locale: Locale.current,
                        summary.playlists,
                        summary.playlistSongs
                    )
                )
                contentDivider
                contentRow(
                    icon: .download,
                    title: String(localized: "cloud_sync_downloads"),
                    value: countText(summary.downloads)
                )
                contentDivider
                contentRow(
                    icon: .podcast,
                    title: String(localized: "cloud_sync_podcasts"),
                    value: countText(summary.podcastSubscriptions)
                )
                contentDivider
                contentRow(
                    icon: .sparkle,
                    title: String(localized: "cloud_sync_personalization"),
                    value: countText(summary.colorConfigurations)
                )
                contentDivider
                contentRow(
                    icon: .chart,
                    title: String(localized: "cloud_sync_listening_stats"),
                    value: countText(summary.listeningRecords)
                )
                contentDivider
                contentRow(
                    icon: .history,
                    title: String(localized: "cloud_sync_playback_history"),
                    value: countText(summary.playbackRecords)
                )
                contentDivider
                contentRow(
                    icon: .waveform,
                    title: String(localized: "cloud_sync_ai_tuning"),
                    value: countText(summary.aiTuningPlans)
                )
                contentDivider
                contentRow(
                    icon: .equalizer,
                    title: String(localized: "cloud_sync_custom_eq"),
                    value: countText(summary.customEQPresets)
                )
                contentDivider
                contentRow(
                    icon: .sparkle,
                    title: String(localized: "cloud_sync_audio_agent_skills"),
                    value: countText(summary.audioAgentSkills)
                )
            }
            .background(cardBackground)
            .monoGlass(cornerRadius: 14)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var syncSection: some View {
        section(title: String(localized: "playlist_sync_settings_title")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .cloud,
                    title: String(localized: "playlist_sync_auto_toggle_title"),
                    subtitle: String(localized: "playlist_sync_auto_toggle_desc"),
                    isOn: $settings.playlistSyncAutoEnabled
                )

                contentDivider

                SettingsToggleRow(
                    icon: .trash,
                    title: String(localized: "playlist_sync_delete_remote_toggle_title"),
                    subtitle: String(localized: "playlist_sync_delete_remote_toggle_desc"),
                    isOn: $settings.playlistSyncDeleteCloudSnapshot
                )
            }
            .background(cardBackground)
            .monoGlass(cornerRadius: 14)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var actionSection: some View {
        section(title: String(localized: "playlist_sync_actions_title")) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    actionButton(
                        icon: .save,
                        title: String(localized: "playlist_sync_upload_button"),
                        primary: true
                    ) {
                        runSyncAction {
                            _ = try await playlistCloudSync.syncToCloud()
                        }
                    }

                    actionButton(
                        icon: .download,
                        title: String(localized: "playlist_sync_restore_button")
                    ) {
                        runSyncAction {
                            _ = try await playlistCloudSync.restoreFromCloud()
                        }
                    }
                }

                Button {
                    showClearCloudConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .trash, size: 14, color: .red)
                        Text(String(localized: "playlist_sync_clear_cloud_button"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                        Spacer()
                        MonoIcon(icon: .chevronRight, size: 11, color: .red.opacity(0.62))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(cardBackground)
                    .monoGlass(cornerRadius: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .disabled(actionsDisabled)
            .opacity(actionsDisabled ? 0.5 : 1)
        }
    }

    // MARK: - 通用构建块

    private func contentRow(
        icon: MonoIcon.IconType,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon: icon, size: 14, color: accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.monoTextPrimary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.monoTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }

    private var contentDivider: some View {
        Rectangle()
            .fill(Color.monoSeparator.opacity(settings.globalThemeId == .default ? 0.52 : 0.4))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func actionButton(
        icon: MonoIcon.IconType,
        title: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MonoIcon(
                    icon: icon,
                    size: 14,
                    color: primary ? readableAccentForeground : Color.monoTextPrimary
                )
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primary ? readableAccentForeground : Color.monoTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(primary ? accent : secondarySurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(primary ? Color.white.opacity(0.04) : secondaryStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.monoTextSecondary)
            content()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(secondarySurface)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(secondaryStroke, lineWidth: 1)
            }
    }

    private var secondarySurface: Color {
        Color.monoGlassTint.opacity(settings.globalThemeId == .default ? 0.68 : 0.78)
    }

    private var secondaryStroke: Color {
        Color.monoSeparator.opacity(settings.globalThemeId == .default ? 0.52 : 0.36)
    }

    private var readableAccentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "111821"),
            dark: .white
        )
    }

    // MARK: - 状态派生与操作

    private var actionsDisabled: Bool {
        !onlineAccess.canUseOnlineFeatures || playlistCloudSync.isSyncing
    }

    private var statusTitle: String {
        if playlistCloudSync.isSyncing {
            return String(localized: "cloud_sync_syncing")
        }
        return onlineAccess.canUseOnlineFeatures
            ? String(localized: "playlist_sync_status_title")
            : String(localized: "settings_navigation_cloud_sync_disabled")
    }

    private var playlistSyncStatusText: String {
        if let message = playlistCloudSync.lastStatusMessage, !message.isEmpty {
            if let date = playlistCloudSync.lastSyncedAt {
                return "\(message) · \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return message
        }
        return String(localized: "playlist_sync_idle")
    }

    private func countText(_ count: Int) -> String {
        String(
            format: String(localized: "cloud_sync_count"),
            locale: Locale.current,
            count
        )
    }

    /// 执行同步操作，失败时弹窗提示错误。
    private func runSyncAction(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                showFailure(error)
            }
        }
    }

    private func showFailure(_ error: Error) {
        AlertManager.shared.show(
            title: String(localized: "playlist_sync_failed_title"),
            message: String(
                format: String(localized: "playlist_sync_failed_format"),
                locale: Locale.current,
                error.localizedDescription
            ),
            primaryButtonTitle: String(localized: "common_ok"),
            primaryAction: {}
        )
    }
}
