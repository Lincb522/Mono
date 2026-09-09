import SwiftUI

struct QCMNewSongsView: View {
    @ObservedObject private var viewModel = HomeViewModel.shared
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isSelectMode = false
    @State private var selectedSongIds: Set<String> = []
    @State private var showBatchAddToPlaylist = false

    private var songs: [Song] {
        viewModel.qqNewSongs
    }

    private var qcmAccent: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if PetWhiteStyle.isActive { return PetWhiteStyle.sky }
        if CapsuleStyle.isActive { return CapsuleStyle.mint }
        return NeumorphicStyle.isActive ? NeumorphicStyle.accent : MusicSource.qqmusic.themedBadgeColor
    }

    private var qcmAccentForeground: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.onAccent }
        if PetWhiteStyle.isActive { return PetWhiteStyle.ink }
        if CapsuleStyle.isActive {
            return CapsuleStyle.readableLabel(on: CapsuleStyle.mint)
        }
        if NeumorphicStyle.isActive {
            return ThemeColorCustomization.readableForegroundColor(
                on: NeumorphicStyle.accent,
                light: Color(hex: "172026"),
                dark: .white
            )
        }
        return Color(light: .white, dark: .black)
    }

    private var qcmPrimaryText: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if PetWhiteStyle.isActive { return PetWhiteStyle.ink }
        if CapsuleStyle.isActive { return CapsuleStyle.ink }
        return NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary
    }

    private var qcmSecondaryText: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if PetWhiteStyle.isActive { return PetWhiteStyle.inkSoft }
        if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            if PetWhiteStyle.isActive {
                PetWhiteRootBackdrop()
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteRootBackdrop()
            } else {
                ThemedPageBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                LazyVStack(spacing: ThemedPageStyle.isActive ? 10 : 0) {
                    header

                    if viewModel.isLoading && songs.isEmpty {
                        loadingState
                    } else if songs.isEmpty {
                        emptyState
                    } else if CapsuleStyle.isActive {
                        capsuleSongList
                    } else if PetWhiteStyle.isActive || MinimalWhiteStyle.isActive {
                        // PetWhite / 纯白极简的 songRows 卡片内部已含 toolbar，
                        // 外层不能再渲染一次，否则"全部播放"等按钮会重复
                        songRows
                    } else {
                        toolbar

                        songRows
                    }

                    FloatingBarBottomSpacer()
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            if songs.isEmpty {
                viewModel.fetchData()
            }
        }
        .monoSheet(isPresented: $showBatchAddToPlaylist, preset: .standard) {
            BatchAddToPlaylistSheet(songs: songs.filter { selectedSongIds.contains($0.identityKey) })
        }
    }

    @ViewBuilder
    private var header: some View {
        if SignalStyle.isActive {
            SignalPageHeader(
                eyebrow: "QCM NEW",
                title: "QCM 新歌",
                subtitle: "\(songs.count) \(String(localized: "songs_unit"))"
            ) {
                SignalIconBadge(icon: .musicNote, tint: MusicSource.qqmusic.themedBadgeColor, size: 48)
            }
            .padding(.bottom, 2)
        } else if CapsuleStyle.isActive {
            CapsulePageHeader(
                eyebrow: "QCM NEW",
                title: "QCM 新歌",
                subtitle: "\(songs.count) \(String(localized: "songs_unit"))"
            ) {
                CapsuleIconBadge(icon: .musicNote, tint: CapsuleStyle.mint, size: 48)
            }
            .padding(.bottom, 2)
        } else if PetWhiteStyle.isActive {
            PetWhitePageHeader(
                eyebrow: "QCM NEW",
                title: "QCM 新歌",
                subtitle: "\(songs.count) \(String(localized: "songs_unit"))",
                icon: .musicNote
            ) {
                EmptyView()
            }
            .padding(.bottom, 2)
        } else if MinimalWhiteStyle.isActive {
            MinimalWhitePageHeader(eyebrow: "", title: "QCM 新歌", icon: .musicNote) {
                Text("\(songs.count) \(String(localized: "songs_unit"))")
                    .font(MinimalWhiteStyle.labelFont(12, weight: .regular))
                    .foregroundStyle(MinimalWhiteStyle.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(MinimalWhiteStyle.controlGlassFill))
                    .overlay(Capsule().stroke(MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth))
            }
            .padding(.bottom, 2)
        } else if ThemedPageStyle.isActive {
            ThemedPageHeader(
                eyebrow: "QCM NEW",
                title: "QCM 新歌",
                subtitle: "\(songs.count) \(String(localized: "songs_unit"))",
                icon: .musicNote
            )
            .padding(.bottom, 2)
        } else {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("QCM NEW")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.monoTextSecondary)
                        .tracking(1.3)

                    Text("QCM 新歌")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.monoTextPrimary)

                    Text("\(songs.count) \(String(localized: "songs_unit"))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.monoTextSecondary)
                }

                Spacer(minLength: 10)

                MonoIcon(icon: .musicNote, size: 22, color: .monoTextPrimary, lineWidth: 1.8)
                    .frame(width: 46, height: 46)
                    .background(Color.monoTextPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.top, DeviceLayout.headerTopPadding + 8)
            .padding(.bottom, 12)
            .monoPageHeaderCollapse()
        }
    }

    private var capsuleSongList: some View {
        CapsuleDetailSection(
            title: "QCM NEW",
            subtitle: "\(songs.count) \(String(localized: "songs_unit"))",
            icon: .musicNote,
            tint: CapsuleStyle.mint
        ) {
            toolbar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            songRows
        }
    }

    private var songRows: some View {
        Group {
            if PetWhiteStyle.isActive {
                VStack(alignment: .leading, spacing: 12) {
                    PetWhiteSectionTitle(
                        title: "QCM NEW",
                        detail: "\(songs.count) \(String(localized: "songs_unit"))",
                        icon: .musicNote,
                        assetName: "qqMusic",
                        tint: PetWhiteStyle.sky
                    )
                    toolbar
                        .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)
                    songRowsContent
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PetWhiteSurfaceBackground(cornerRadius: PetWhiteStyle.cardRadius, elevated: true, tint: PetWhiteStyle.surfaceRaised, accent: PetWhiteStyle.sky))
                .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 8 : 4)
            } else if MinimalWhiteStyle.isActive {
                VStack(alignment: .leading, spacing: 12) {
                    toolbar
                        .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)
                    songRowsContent
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MinimalWhiteSurfaceBackground(
                        cornerRadius: MinimalWhiteStyle.chromeRadius,
                        elevated: false,
                        tint: MinimalWhiteStyle.glassFill
                    )
                )
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                songRowsContent
            }
        }
    }

    private var songRowsContent: some View {
        ForEach(Array(songs.enumerated()), id: \.element.identityKey) { index, song in
            SongListRow(
                song: song,
                index: index,
                isSelecting: isSelectMode,
                isSelected: selectedSongIds.contains(song.identityKey),
                onTap: {
                    if isSelectMode {
                        toggleSelection(song.identityKey)
                    } else {
                        playerManager.play(song: song, in: songs)
                    }
                },
                horizontalPadding: (PetWhiteStyle.isActive || MinimalWhiteStyle.isActive) ? CGFloat(0) : nil
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                playAll()
            } label: {
                toolbarPill(title: String(localized: "artist_play_all"), icon: .play, tint: qcmAccent)
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    isSelectMode.toggle()
                    if !isSelectMode {
                        selectedSongIds.removeAll()
                    }
                }
            } label: {
                toolbarIcon(icon: isSelectMode ? .close : .checkmark, tint: isSelectMode ? qcmSecondaryText : qcmAccent)
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))

            if isSelectMode {
                Button {
                    showBatchAddToPlaylist = true
                } label: {
                    toolbarIcon(icon: .add, tint: qcmAccent)
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
                .disabled(selectedSongIds.isEmpty)
                .opacity(selectedSongIds.isEmpty ? 0.4 : 1)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        .padding(.vertical, ThemedPageStyle.isActive ? 4 : 8)
    }

    private func toolbarPill(title: String, icon: MonoIcon.IconType, tint: Color) -> some View {
        Group {
            if SignalStyle.isActive {
                SignalPlayPill(title: title, icon: icon, tint: tint)
            } else if CapsuleStyle.isActive {
                CapsuleDetailActionPill(title: title, icon: icon, tint: tint)
            } else if MinimalWhiteStyle.isActive {
                HStack(spacing: 8) {
                    MonoIcon(icon: icon, size: 14, color: qcmAccentForeground, lineWidth: 1.6)
                    Text(title)
                        .font(MinimalWhiteStyle.labelFont(14, weight: .semibold))
                        .foregroundStyle(qcmAccentForeground)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(qcmAccent, in: Capsule(style: .continuous))
            } else {
                HStack(spacing: 7) {
                    MonoIcon(icon: icon, size: 12, color: qcmAccentForeground, lineWidth: 1.7)
                        .frame(width: 24, height: 24)
                        .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text(title)
                        .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .semibold) : .rounded(size: 13, weight: .semibold))
                        .foregroundStyle(qcmPrimaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .themedPageSurface(cornerRadius: 15, elevated: false)
            }
        }
    }

    private func toolbarIcon(icon: MonoIcon.IconType, tint: Color) -> some View {
        Group {
            if CapsuleStyle.isActive {
                CapsuleDetailIconButton(icon: icon, tint: tint)
                    .frame(width: 34, height: 34)
            } else if MinimalWhiteStyle.isActive {
                MonoIcon(icon: icon, size: 13, color: tint, lineWidth: 1.7)
                    .frame(width: 34, height: 34)
                    .background(MinimalWhiteCircleBackground(elevated: false))
            } else {
                MonoIcon(icon: icon, size: 13, color: tint, lineWidth: 1.7)
                    .frame(width: 32, height: 32)
                    .themedPageSurface(cornerRadius: 13, elevated: true)
            }
        }
    }

    private var loadingState: some View {
        MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING QCM")
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if SignalStyle.isActive {
                SignalIconBadge(icon: .musicNote, tint: MusicSource.qqmusic.themedBadgeColor, size: 54)
            } else if NeumorphicStyle.isActive {
                NeumorphicIconBadge(icon: .musicNote, tint: qcmAccent, size: 54)
            } else if CapsuleStyle.isActive {
                CapsuleIconBadge(icon: .musicNote, tint: CapsuleStyle.mint, size: 54)
            } else if PetWhiteStyle.isActive {
                PetWhiteAssetIconBadge(assetName: "qqMusic", tint: PetWhiteStyle.sky, size: 54)
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteIconBadge(icon: .musicNote, size: 54)
            } else {
                MonoIcon(icon: .musicNote, size: 38, color: MusicSource.qqmusic.themedBadgeColor.opacity(0.65), lineWidth: 1.7)
            }
            Text("暂无 QCM 新歌")
                .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(14, weight: .medium) : (SignalStyle.isActive ? SignalStyle.bodyFont(15, weight: .semibold) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .semibold) : (CapsuleStyle.isActive ? CapsuleStyle.bodyFont(15, weight: .semibold) : .rounded(size: 15, weight: .semibold)))))
                .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : qcmSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func toggleSelection(_ id: String) {
        if selectedSongIds.contains(id) {
            selectedSongIds.remove(id)
        } else {
            selectedSongIds.insert(id)
        }
    }

    private func playAll() {
        guard let first = songs.first else { return }
        playerManager.play(song: first, in: songs)
    }
}
