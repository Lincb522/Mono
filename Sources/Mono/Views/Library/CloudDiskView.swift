// 我的云盘页面 — 浏览、播放、删除云盘歌曲

import SwiftUI
import Combine

struct CloudDiskView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @StateObject private var requests = CloudDiskRequestStore()
    @State private var songs: [CloudSong] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var totalCount = 0
    @State private var usedSpace = ""
    @State private var totalSpace = ""
    @State private var offset = 0
    @State private var songToDelete: CloudSong? = nil
    @State private var isEnrichingMetadata = false
    @State private var pendingMetadataRefresh = false
    @State private var pendingForcedQQRefresh = false
    @State private var showMoreMenu = false
    
    private let pageSize = 30

    private struct Theme {
        static var accent: Color {
            if SignalStyle.isActive { return SignalStyle.accent }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
            if MangaStyle.isActive { return MangaStyle.accentPink }
            if MujiStyle.isActive { return MujiStyle.clay }
            if CapsuleStyle.isActive { return CapsuleStyle.cyan }
            if SequoiaStyle.isActive { return SequoiaStyle.accent }
            if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
            return Color.monoIconBackground
        }

        static var accentForeground: Color {
            if SignalStyle.isActive { return SignalStyle.onAccent }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.onAccent }
            if MangaStyle.isActive { return MangaStyle.ink }
            if MujiStyle.isActive { return MujiStyle.paper }
            if CapsuleStyle.isActive { return CapsuleStyle.readableLabel(on: accent) }
            if SequoiaStyle.isActive { return SequoiaStyle.onAccent }
            if NeumorphicStyle.isActive { return Color(light: .white, dark: .black) }
            return Color.monoIconForeground
        }

        static var text: Color {
            if SignalStyle.isActive { return SignalStyle.ink }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
            if CapsuleStyle.isActive { return CapsuleStyle.ink }
            if SequoiaStyle.isActive { return SequoiaStyle.ink }
            if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
            return Color.monoTextPrimary
        }

        static var secondaryText: Color {
            if SignalStyle.isActive { return SignalStyle.inkSoft }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkSoft }
            if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
            if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
            if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
            return Color.monoTextSecondary
        }

        static var mutedText: Color {
            if SignalStyle.isActive { return SignalStyle.inkMuted }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
            if CapsuleStyle.isActive { return CapsuleStyle.inkMuted }
            if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
            if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
            return Color.monoTextSecondary.opacity(0.5)
        }

        static var coverFill: Color {
            if SignalStyle.isActive { return SignalStyle.controlPressed }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.controlGlassFill }
            if CapsuleStyle.isActive { return CapsuleStyle.surfaceTint }
            if SequoiaStyle.isActive { return SequoiaStyle.materialPressed.opacity(0.74) }
            if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
            return Color.monoGlassTint
        }

        static func labelFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            if SignalStyle.isActive { return SignalStyle.labelFont(size, weight: weight) }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(size, weight: weight) }
            if CapsuleStyle.isActive { return CapsuleStyle.labelFont(size, weight: weight) }
            if SequoiaStyle.isActive { return SequoiaStyle.labelFont(size, weight: weight) }
            if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(size, weight: weight) }
            return .system(size: size, weight: weight, design: .rounded)
        }

        static func bodyFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            if SignalStyle.isActive { return SignalStyle.bodyFont(size, weight: weight) }
            if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.bodyFont(size, weight: weight) }
            if CapsuleStyle.isActive { return CapsuleStyle.bodyFont(size, weight: weight) }
            if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(size, weight: weight) }
            if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(size, weight: weight) }
            return .system(size: size, weight: weight, design: .rounded)
        }
    }
    
    /// aside 默认主题（编辑部风格分支）
    private var isAside: Bool {
        GlobalThemeId.persistedOrDefault == .default
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if SignalStyle.isActive {
                    SignalNestedPageHeader(
                        title: String(localized: "cloud_title"),
                        eyebrow: "CLOUD LIBRARY",
                        icon: .cloud,
                        module: .cloud
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }

                if isLoading && songs.isEmpty {
                    Spacer()
                    MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING")
                    Spacer()
                } else if songs.isEmpty {
                    emptyState
                } else if isAside {
                    asideContent
                } else {
                    songList
                }
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showMoreMenu.toggle()
                    }
                } label: {
                    MonoIcon(icon: .more, size: 16, color: .monoTextSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "player_more_title"))
            }
        }
        .overlay {
            if showMoreMenu {
                MonoMoreMenuOverlay(
                    isPresented: $showMoreMenu,
                    title: String(localized: "player_more_title"),
                    isDarkBackground: colorScheme == .dark
                ) {
                    MonoMoreMenuSection(title: String(localized: "more_menu_cloud_section")) {
                        MonoMoreMenuGroup {
                            MonoMoreMenuRow(
                                icon: .refresh,
                                title: NSLocalizedString("cloud_refresh_metadata", comment: ""),
                                trailingText: isEnrichingMetadata
                                    ? NSLocalizedString("cloud_syncing_metadata", comment: "")
                                    : nil,
                                isEnabled: !isEnrichingMetadata
                            ) {
                                showMoreMenu = false
                                triggerMetadataEnrichment(forceQQMetadata: true)
                            }
                        }
                    }
                }
                .zIndex(20)
            }
        }
        .onAppear { loadFirstPage() }
        .onDisappear {
            requests.initial.cancel()
            requests.page.cancel()
            isLoading = false
            isLoadingMore = false
        }
        
    }
    
    // MARK: - 空状态
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if MinimalWhiteStyle.isActive {
                MinimalWhiteIconBadge(icon: .cloud, size: 54)
            } else {
                MonoIcon(icon: .cloud, size: 48, color: Theme.mutedText.opacity(0.42), lineWidth: 1.4)
            }
            Text(LocalizedStringKey("cloud_empty"))
                .font(Theme.bodyFont(15))
                .foregroundColor(Theme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background {
            if MinimalWhiteStyle.isActive {
                MinimalWhiteSurfaceBackground(
                    cornerRadius: MinimalWhiteStyle.cardRadius,
                    elevated: false,
                    tint: MinimalWhiteStyle.glassFill
                )
            }
        }
        .padding(.horizontal, MinimalWhiteStyle.isActive ? DeviceLayout.viewHorizontalPadding : 0)
    }
    
    // MARK: - 歌曲列表
    
    private var songList: some View {
        VStack(spacing: 0) {
            // 统计信息
            HStack {
                Text(String(format: NSLocalizedString("cloud_song_count", comment: ""), totalCount))
                    .font(Theme.labelFont(13))
                    .foregroundColor(Theme.secondaryText)
                if isEnrichingMetadata {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.secondaryText)
                        Text(LocalizedStringKey("cloud_syncing_metadata"))
                            .font(Theme.labelFont(12))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer()
                if !usedSpace.isEmpty && !totalSpace.isEmpty {
                    Text("\(formatBytes(usedSpace)) / \(formatBytes(totalSpace))")
                        .font(Theme.labelFont(13))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(.horizontal, ThemedPageStyle.isActive ? 16 : 24)
            .padding(.vertical, 12)
            .themedOnlyPageSurface(cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius, elevated: false)
            .padding(.horizontal, ThemedPageStyle.horizontalInset)
            
            // 全部播放按钮
            Button {
                let allSongs = songs.map { $0.toSong() }
                if let first = allSongs.first {
                    playerManager.playReplacingContext(song: first, in: allSongs)
                }
            } label: {
                if CapsuleStyle.isActive {
                    CapsulePillLabel(
                        title: String(localized: "cloud_play_all"),
                        icon: .play,
                        tint: Theme.accent,
                        selected: true
                    )
                } else if MinimalWhiteStyle.isActive {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .play, size: 14, color: Theme.accentForeground, lineWidth: 1.6)
                        Text(LocalizedStringKey("cloud_play_all"))
                            .font(Theme.labelFont(14, weight: .semibold))
                            .foregroundColor(Theme.accentForeground)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule(style: .continuous))
                } else if SequoiaStyle.isActive {
                    HStack(spacing: 7) {
                        MonoIcon(icon: .play, size: 14, color: Theme.accentForeground, lineWidth: 1.6)
                        Text(LocalizedStringKey("cloud_play_all"))
                            .font(Theme.labelFont(14, weight: .semibold))
                            .foregroundColor(Theme.accentForeground)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accent))
                    .overlay(Capsule().stroke(SequoiaStyle.luminousSeparator.opacity(0.28), lineWidth: 0.55))
                } else if NeumorphicStyle.isActive {
                    NeumorphicPlayPill(title: String(localized: "cloud_play_all"), tint: NeumorphicStyle.accent)
                } else {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .play, size: 16, color: Theme.accentForeground, lineWidth: 1.6)
                        Text(LocalizedStringKey("cloud_play_all"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.accentForeground)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(MangaStyle.isActive ? AnyShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)) : AnyShape(Capsule()))
                    .overlay {
                        if MangaStyle.isActive {
                            RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                                .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth)
                        }
                    }
                    .shadow(color: Theme.accent.opacity(0.18), radius: 6, x: 0, y: 2)
                }
            }
            .buttonStyle(MonoBouncingButtonStyle())
            .padding(.horizontal, ThemedPageStyle.isActive ? DeviceLayout.viewHorizontalPadding : 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                    ForEach(songs) { song in
                        cloudSongRow(song)
                            .onAppear {
                                // 加载更多
                                if song.id == songs.last?.id && hasMore && !isLoadingMore {
                                    loadMore()
                                }
                            }
                    }
                    
                    if isLoadingMore {
                        ProgressView()
                            .tint(Theme.secondaryText)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, ThemedPageStyle.horizontalInset)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }
    
    // MARK: - aside 编辑部风格

    private var asideContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                asideHero
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 20)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    asideCloudRow(song, index: index)
                        .onAppear {
                            if song.id == songs.last?.id && hasMore && !isLoadingMore {
                                loadMore()
                            }
                        }
                }

                if isLoadingMore {
                    ProgressView()
                        .tint(.monoTextSecondary)
                        .padding(.vertical, 20)
                }
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    /// 编辑部式页头：眉题 + 大标题 + 容量刻度 + 操作行
    private var asideHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: NSLocalizedString("cloud_song_count", comment: ""), totalCount))
                    .font(.rounded(size: 13, weight: .semibold))
                    .foregroundColor(.monoTextSecondary)

                if isEnrichingMetadata {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.monoTextSecondary)
                        Text(LocalizedStringKey("cloud_syncing_metadata"))
                            .font(.rounded(size: 11.5))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))
                    }
                }
            }
            .padding(.bottom, 16)

            if usedBytes > 0, totalBytes > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.monoSeparator.opacity(0.4))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.monoAccent)
                                .frame(
                                    width: max(geo.size.width * CGFloat(min(Double(usedBytes) / Double(totalBytes), 1)), 4),
                                    height: 3
                                )
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 3)

                    HStack {
                        Text(formatBytes(usedSpace))
                            .font(.rounded(size: 12, weight: .semibold))
                            .foregroundColor(.monoTextPrimary.opacity(0.82))
                            .monospacedDigit()

                        Spacer()

                        Text(formatBytes(totalSpace))
                            .font(.rounded(size: 12))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 18)
            }

            HStack(spacing: 12) {
                Button {
                    let allSongs = songs.map { $0.toSong() }
                    if let first = allSongs.first {
                        playerManager.playReplacingContext(song: first, in: allSongs)
                    }
                } label: {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .play, size: 14, color: .monoIconForeground)
                        Text(LocalizedStringKey("cloud_play_all"))
                            .font(.rounded(size: 14, weight: .bold))
                            .foregroundColor(.monoIconForeground)
                    }
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.monoIconBackground))
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 编辑部式歌曲行：序号 + 封面 + 标题元信息 + 发丝码率徽章
    private func asideCloudRow(_ song: CloudSong, index: Int) -> some View {
        CloudSongPlaybackReader(songID: song.songId) { isCurrent, isPlaying in

            Button {
                playCloudSong(song)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        if isCurrent {
                            PlayingVisualizerView(isAnimating: isPlaying, color: .monoAccent)
                                .frame(width: 16, height: 16)
                        } else {
                            Text(String(format: "%02d", index + 1))
                                .font(.rounded(size: 12, weight: .semibold))
                                .foregroundColor(.monoTextSecondary.opacity(0.4))
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 26)

                    CachedAsyncImage(url: song.simpleSong?.coverUrl) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.monoGlassTint)
                            .overlay(
                                MonoIcon(icon: .cloud, size: 16, color: .monoTextSecondary.opacity(0.45), lineWidth: 1.3)
                            )
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: DeviceLayout.listRowCoverSmall, height: DeviceLayout.listRowCoverSmall)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.songName)
                            .font(.rounded(size: 15, weight: .semibold))
                            .foregroundColor(.monoTextPrimary)
                            .lineLimit(1)

                        HStack(spacing: 7) {
                            Text(song.bitrateText)
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .tracking(0.4)
                                .foregroundColor(.monoTextPrimary.opacity(0.72))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .overlay(
                                    Capsule().stroke(Color.monoTextPrimary.opacity(0.3), lineWidth: 0.8)
                                )

                            Text("\(song.artist) · \(song.fileSizeText)")
                                .font(.rounded(size: 12))
                                .foregroundColor(.monoTextSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                .padding(.vertical, 8)
                .background {
                    if isCurrent {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.monoAccent.opacity(0.07))

                            Capsule()
                                .fill(Color.monoAccent)
                                .frame(width: 3, height: 24)
                                .padding(.leading, 8)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98, opacity: 0.8))
            .contextMenu {
                Button {
                    addCloudSongToPlayNext(song)
                } label: {
                    Label(NSLocalizedString("cloud_play_next", comment: ""), systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    addCloudSongToQueue(song)
                } label: {
                    Label(NSLocalizedString("cloud_add_queue", comment: ""), systemImage: "text.append")
                }

                Divider()

                Button(role: .destructive) {
                    AlertManager.shared.show(
                        title: NSLocalizedString("cloud_delete_title", comment: ""),
                        message: String(format: NSLocalizedString("cloud_delete_message", comment: ""), song.songName),
                        primaryButtonTitle: NSLocalizedString("cloud_delete_action", comment: ""),
                        secondaryButtonTitle: NSLocalizedString("alert_cancel", comment: ""),
                        primaryAction: { deleteSong(song) }
                    )
                } label: {
                    Label(NSLocalizedString("cloud_delete_from", comment: ""), systemImage: "trash")
                }
            }
        }
    }

    private var usedBytes: Int64 { Int64(usedSpace) ?? 0 }
    private var totalBytes: Int64 { Int64(totalSpace) ?? 0 }

    // MARK: - 单行歌曲
    
    private func cloudSongRow(_ song: CloudSong) -> some View {
        CloudSongPlaybackReader(songID: song.songId) { isCurrent, isPlaying in

            Button {
                playCloudSong(song)
            } label: {
                HStack(spacing: 14) {
                    // 封面
                    if let coverUrl = song.simpleSong?.coverUrl {
                        CachedAsyncImage(url: coverUrl) {
                            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                                .fill(Theme.coverFill)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: DeviceLayout.listRowCoverSmall, height: DeviceLayout.listRowCoverSmall)
                        .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
                        .overlay(coverStroke)
                    } else {
                        RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                            .fill(Theme.coverFill)
                            .frame(width: DeviceLayout.listRowCoverSmall, height: DeviceLayout.listRowCoverSmall)
                            .overlay(
                                MonoIcon(icon: .cloud, size: 20, color: Theme.secondaryText.opacity(0.5), lineWidth: 1.4)
                            )
                            .overlay(coverStroke)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.songName)
                            .font(Theme.bodyFont(15, weight: .semibold))
                            .foregroundColor(isCurrent && (MinimalWhiteStyle.isActive || CapsuleStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? Theme.accent : Theme.text)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if CapsuleStyle.isActive {
                                CapsulePillLabel(title: song.bitrateText, tint: Theme.accent, selected: isCurrent)
                            } else if SequoiaStyle.isActive {
                                SequoiaPill(text: song.bitrateText, tint: Theme.accent, selected: isCurrent, compact: true)
                            } else if NeumorphicStyle.isActive {
                                NeumorphicPill(text: song.bitrateText, tint: Theme.accent, selected: isCurrent, compact: true)
                            } else if MinimalWhiteStyle.isActive {
                                Text(song.bitrateText)
                                    .font(MinimalWhiteStyle.labelFont(10, weight: .medium))
                                    .foregroundColor(isCurrent ? MinimalWhiteStyle.ink : MinimalWhiteStyle.inkMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(MinimalWhiteCapsuleBackground(selected: isCurrent))
                            } else {
                                Text(song.bitrateText)
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: MangaStyle.isActive ? 6 : 2)
                                            .stroke(Theme.accent, lineWidth: 0.5)
                                    )
                            }

                            Text("\(song.artist) · \(song.fileSizeText)")
                                .font(Theme.labelFont(12))
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if isCurrent {
                        PlayingVisualizerView(isAnimating: isPlaying, color: (MinimalWhiteStyle.isActive || CapsuleStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? Theme.accent : .monoTextPrimary)
                            .frame(width: 20)
                    }
                }
                .padding(.horizontal, ThemedPageStyle.isActive ? 16 : 24)
                .padding(.vertical, 8)
                .background(isCurrent ? Theme.accent.opacity((MinimalWhiteStyle.isActive || SequoiaStyle.isActive || CapsuleStyle.isActive) ? 0.08 : 0.05) : Color.clear)
                .themedOnlyPageSurface(
                    cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius,
                    elevated: isCurrent,
                    mangaTint: isCurrent ? MangaStyle.labelYellow.opacity(0.92) : MangaStyle.bubbleWhite
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98, opacity: 0.8))
            .contextMenu {
                Button {
                    addCloudSongToPlayNext(song)
                } label: {
                    Label(NSLocalizedString("cloud_play_next", comment: ""), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                
                Button {
                    addCloudSongToQueue(song)
                } label: {
                    Label(NSLocalizedString("cloud_add_queue", comment: ""), systemImage: "text.append")
                }

                Divider()
                
                Button(role: .destructive) {
                    AlertManager.shared.show(
                        title: NSLocalizedString("cloud_delete_title", comment: ""),
                        message: String(format: NSLocalizedString("cloud_delete_message", comment: ""), song.songName),
                        primaryButtonTitle: NSLocalizedString("cloud_delete_action", comment: ""),
                        secondaryButtonTitle: NSLocalizedString("alert_cancel", comment: ""),
                        primaryAction: { deleteSong(song) }
                    )
                } label: {
                    Label(NSLocalizedString("cloud_delete_from", comment: ""), systemImage: "trash")
                }
            }
        }
    }

    private var coverRadius: CGFloat {
        if MinimalWhiteStyle.isActive { return 12 }
        if CapsuleStyle.isActive { return 16 }
        if SequoiaStyle.isActive { return 12 }
        return NeumorphicStyle.isActive ? 14 : 10
    }

    @ViewBuilder
    private var coverStroke: some View {
        if CapsuleStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(CapsuleStyle.hairline.opacity(0.72), lineWidth: 0.8)
        } else if NeumorphicStyle.isActive || SequoiaStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(SequoiaStyle.isActive ? SequoiaStyle.separator : NeumorphicStyle.separator.opacity(0.5), lineWidth: 0.7)
        } else if MinimalWhiteStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth)
        }
    }
    
    // MARK: - 数据加载
    
    private func loadFirstPage() {
        guard songs.isEmpty, !requests.initial.isRunning else { return }
        isLoading = true
        offset = 0

        let request = requests.initial.begin()
        requests.initial.cancellable = APIService.shared.fetchCloudSongs(limit: pageSize, offset: 0)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                guard requests.initial.isCurrent(request) else { return }
                requests.initial.finish(request)
                isLoading = false
                if case .failure(let error) = completion {
                    AppLogger.error("加载云盘失败: \(error)")
                }
            }, receiveValue: { response in
                guard requests.initial.isCurrent(request) else { return }
                songs = response.data
                totalCount = response.count
                hasMore = response.hasMore
                usedSpace = response.size
                totalSpace = response.maxSize
                offset = response.data.count
                triggerMetadataEnrichment(for: response.data)
            })
    }
    
    private func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore, !requests.initial.isRunning else { return }
        isLoadingMore = true
        
        let request = requests.page.begin()
        requests.page.cancellable = APIService.shared.fetchCloudSongs(limit: pageSize, offset: offset)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                guard requests.page.isCurrent(request) else { return }
                requests.page.finish(request)
                isLoadingMore = false
                if case .failure(let error) = completion {
                    AppLogger.error("加载更多云盘歌曲失败: \(error)")
                }
            }, receiveValue: { response in
                guard requests.page.isCurrent(request) else { return }
                songs.append(contentsOf: response.data)
                hasMore = response.hasMore
                offset += response.data.count
                triggerMetadataEnrichment(for: response.data)
            })
    }
    
    private func deleteSong(_ song: CloudSong) {
        APIService.shared.deleteCloudSong(ids: [song.songId])
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    AppLogger.error("删除云盘歌曲失败: \(error)")
                }
            }, receiveValue: { response in
                if response.code == 200 {
                    songs.removeAll { $0.songId == song.songId }
                    totalCount = max(totalCount - 1, 0)
                }
                songToDelete = nil
            })
            .store(in: &requests.mutations)
    }
    
    // MARK: - 工具方法
    
    /// 将字节字符串格式化为可读大小
    private func formatBytes(_ str: String) -> String {
        guard let bytes = Int64(str) else { return str }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func playCloudSong(_ cloudSong: CloudSong) {
        Task {
            let resolvedSong = await resolveCloudSongForPlayback(cloudSong)
            await MainActor.run {
                let allSongs = songs.map { $0.songId == resolvedSong.songId ? resolvedSong.toSong() : $0.toSong() }
                playerManager.play(song: resolvedSong.toSong(), in: allSongs)
            }
        }
    }

    private func addCloudSongToPlayNext(_ cloudSong: CloudSong) {
        Task {
            let resolvedSong = await resolveCloudSongForPlayback(cloudSong)
            await MainActor.run {
                playerManager.playNext(song: resolvedSong.toSong())
            }
        }
    }

    private func addCloudSongToQueue(_ cloudSong: CloudSong) {
        Task {
            let resolvedSong = await resolveCloudSongForPlayback(cloudSong)
            await MainActor.run {
                playerManager.addToQueue(song: resolvedSong.toSong())
            }
        }
    }

    private func resolveCloudSongForPlayback(_ cloudSong: CloudSong) async -> CloudSong {
        let song = cloudSong.toSong()
        let needsMetadata = cloudSong.simpleSong == nil
            || song.coverUrl == nil
            || (song.qqMid?.isEmpty ?? true)

        guard needsMetadata else { return cloudSong }

        AppLogger.info("播放前补全云盘歌曲元数据: \(cloudSong.songName) - \(cloudSong.artist)")
        let enrichedSongs = await APIService.shared.enrichCloudSongsMetadata([cloudSong], forceQQMetadata: true)
        guard let resolvedSong = enrichedSongs.first else { return cloudSong }

        await MainActor.run {
            applyEnrichedSongs([resolvedSong], scopedTo: [cloudSong.songId])
        }

        return resolvedSong
    }

    private func triggerMetadataEnrichment(for targetSongs: [CloudSong]? = nil, forceQQMetadata: Bool = false) {
        let songsToEnrich = targetSongs ?? songs
        guard !songsToEnrich.isEmpty else { return }

        if isEnrichingMetadata {
            pendingMetadataRefresh = true
            pendingForcedQQRefresh = pendingForcedQQRefresh || forceQQMetadata
            AppLogger.info("云盘元数据补全已排队，等待当前任务结束")
            return
        }

        isEnrichingMetadata = true
        pendingMetadataRefresh = false
        pendingForcedQQRefresh = false
        let scopedIDs = Set(songsToEnrich.map(\.songId))
        AppLogger.info("开始补全云盘元数据: \(songsToEnrich.count) 首，forceQQ=\(forceQQMetadata)")

        Task {
            let enrichedSongs = await APIService.shared.enrichCloudSongsMetadata(
                songsToEnrich,
                forceQQMetadata: forceQQMetadata
            )
            await MainActor.run {
                applyEnrichedSongs(enrichedSongs, scopedTo: scopedIDs)
                isEnrichingMetadata = false
                AppLogger.info("云盘元数据补全完成: \(enrichedSongs.count) 首")

                if pendingMetadataRefresh {
                    let shouldForceQQRefresh = pendingForcedQQRefresh
                    pendingMetadataRefresh = false
                    pendingForcedQQRefresh = false
                    triggerMetadataEnrichment(forceQQMetadata: shouldForceQQRefresh)
                }
            }
        }
    }

    private func applyEnrichedSongs(_ enrichedSongs: [CloudSong], scopedTo scopedIDs: Set<Int>) {
        guard !enrichedSongs.isEmpty else { return }

        let enrichedByID = Dictionary(uniqueKeysWithValues: enrichedSongs.map { ($0.songId, $0) })
        songs = songs.map { existingSong in
            guard scopedIDs.contains(existingSong.songId),
                  let enrichedSong = enrichedByID[existingSong.songId] else {
                return existingSong
            }
            return enrichedSong
        }

        syncPlayerMetadataIfNeeded(using: enrichedByID)
    }

    private func syncPlayerMetadataIfNeeded(using enrichedByID: [Int: CloudSong]) {
        let enrichedSongs = enrichedByID.mapValues { $0.toSong() }
        playerManager.context = playerManager.context.map { enrichedSongs[$0.id] ?? $0 }
        playerManager.shuffledContext = playerManager.shuffledContext.map { enrichedSongs[$0.id] ?? $0 }

        guard let currentSong = playerManager.currentSong,
              let enrichedCurrentSong = enrichedSongs[currentSong.id] else { return }

        let needsCover = currentSong.coverUrl == nil && enrichedCurrentSong.coverUrl != nil
        let needsQQMid = (currentSong.qqMid?.isEmpty ?? true) && !(enrichedCurrentSong.qqMid?.isEmpty ?? true)
        let needsName = currentSong.name.isEmpty && !enrichedCurrentSong.name.isEmpty
        let needsArtist = currentSong.artistName.isEmpty && !enrichedCurrentSong.artistName.isEmpty
        let needsLyricsRetry = !LyricViewModel.shared.hasLyrics

        guard needsCover || needsQQMid || needsName || needsArtist || needsLyricsRetry else { return }

        if needsCover || needsQQMid || needsName || needsArtist {
            playerManager.currentSong = enrichedCurrentSong
            playerManager.loadSongExtras(for: enrichedCurrentSong)
            playerManager.updateNowPlayingArtwork(for: enrichedCurrentSong)
            playerManager.syncWidgetState()
        }

        playerManager.fetchLyricsForSong(enrichedCurrentSong)
    }
}

@MainActor
private final class CloudDiskRequestStore: ObservableObject {
    let initial = LibraryRequestScope()
    let page = LibraryRequestScope()
    var mutations = Set<AnyCancellable>()
}

private struct CloudSongPlaybackReader<Content: View>: View {
    private struct Selection: Equatable {
        let isCurrent: Bool
        let isPlaying: Bool
    }

    let songID: Int
    private let player = PlayerManager.shared
    @State private var selection: Selection
    private let content: (Bool, Bool) -> Content

    init(songID: Int, @ViewBuilder content: @escaping (Bool, Bool) -> Content) {
        self.songID = songID
        self.content = content
        let player = PlayerManager.shared
        let isCurrent = player.currentSong?.id == songID
        _selection = State(initialValue: Selection(isCurrent: isCurrent, isPlaying: isCurrent && player.isPlaying))
    }

    var body: some View {
        content(selection.isCurrent, selection.isPlaying)
            .onReceive(Publishers.CombineLatest(player.$currentSong, player.$isPlaying)
                .map { song, playing in
                    let isCurrent = song?.id == songID
                    return Selection(isCurrent: isCurrent, isPlaying: isCurrent && playing)
                }
                .removeDuplicates()) { selection = $0 }
    }
}
