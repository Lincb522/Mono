// 新歌速递页面 — 全新卡片式设计

import SwiftUI

struct NewSongExpressView: View {
    @StateObject private var viewModel = NewSongExpressViewModel()
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedArtistId: Int?
    @State private var showArtistDetail = false
    @State private var selectedSongForDetail: Song?
    @State private var showSongDetail = false
    @State private var selectedAlbumId: Int?
    @State private var showAlbumDetail = false
    @State private var isSelectMode = false
    @State private var selectedSongIds: Set<String> = []
    @State private var showBatchAddToPlaylist = false
    @State private var newSongSearch = ""
    @State private var isNewSongSearching = false

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            if MangaStyle.isActive {
                MangaRootBackdrop()
            } else if PetWhiteStyle.isActive {
                PetWhiteRootBackdrop()
            } else if MujiStyle.isActive {
                MujiRootBackdrop()
            } else if SignalStyle.isActive {
                ThemeRenderBackdrop(theme: .default)
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteRootBackdrop()
            } else {
                ThemedPageBackground()
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        if MangaStyle.isActive {
                            MangaPageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: ""
                            ) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                                        .fill(MangaStyle.labelYellow)
                                    MonoIcon(
                                        icon: .musicNote,
                                        size: 23,
                                        color: ThemeColorCustomization.readableForegroundColor(on: MangaStyle.labelYellow, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk),
                                        lineWidth: 2
                                    )
                                }
                                .frame(width: 48, height: 48)
                                .overlay(RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous).stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth))
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MangaStyle.strokeInk).offset(x: 2.5, y: 2.5))
                            }
                        } else if MinimalWhiteStyle.isActive {
                            MinimalWhitePageHeader(eyebrow: "", title: String(localized: "new_song_express"), icon: .musicNote)
                        } else if NeumorphicStyle.isActive {
                            NeumorphicPageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: ""
                            ) {
                                NeumorphicIconBadge(icon: .musicNote, tint: NeumorphicStyle.warm, size: 48)
                            }
                        } else if MujiStyle.isActive {
                            MujiPageHeader(
                                eyebrow: String(localized: "new_song_express"),
                                title: String(localized: "new_song_express"),
                                subtitle: ""
                            ) {
                                MujiIconBadge(icon: .musicNote, tint: MujiStyle.clay, size: 48)
                            }
                        } else if SignalStyle.isActive {
                            SignalPageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: ""
                            ) {
                                SignalIconBadge(icon: .musicNote, tint: SignalStyle.olive, size: 48)
                            }
                        } else if CapsuleStyle.isActive {
                            CapsulePageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: "\(viewModel.songs.count) \(String(localized: "songs_unit"))"
                            ) {
                                CapsuleIconBadge(icon: .musicNote, tint: CapsuleStyle.amber, size: 48)
                            }
                        } else if SequoiaStyle.isActive {
                            SequoiaPageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: ""
                            ) {
                                SequoiaIconBadge(icon: .musicNote, tint: SequoiaStyle.green, size: 48)
                            }
                        } else if PetWhiteStyle.isActive {
                            PetWhitePageHeader(
                                eyebrow: "NEW SONGS",
                                title: String(localized: "new_song_express"),
                                subtitle: "\(viewModel.songs.count) \(String(localized: "songs_unit"))",
                                icon: .musicNote
                            ) {
                                EmptyView()
                            }
                        }

                        typeSelector
                            .padding(.top, ThemedPageStyle.isActive ? 0 : 8)

                        if viewModel.isLoading {
                            MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 120)
                        } else if viewModel.songs.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 120)
                        } else {
                            VStack(spacing: 24) {
                                // 完整列表
                                fullListSection
                            }
                            .padding(.bottom, 120)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let shuffled = viewModel.songs.shuffled()
                    if let first = shuffled.first {
                        playerManager.playReplacingContext(song: first, in: shuffled)
                    }
                } label: {
                    MonoIcon(icon: .shuffle, size: 16)
                }
                .opacity(viewModel.songs.isEmpty ? 0.3 : 1)
                .disabled(viewModel.songs.isEmpty)
            }
        }
        .navigationDestination(isPresented: $showArtistDetail) {
            if let id = selectedArtistId {
                ArtistDetailView(artistId: id)

            }
        }
        .navigationDestination(isPresented: $showSongDetail) {
            if let song = selectedSongForDetail {
                SongDetailView(song: song)

            }
        }
        .navigationDestination(isPresented: $showAlbumDetail) {
            if let id = selectedAlbumId {
                AlbumDetailView(albumId: id, albumName: nil, albumCoverUrl: nil)

            }
        }
        .onAppear {
            if viewModel.songs.isEmpty {
                viewModel.loadSongs(type: 0)
            }
        }
    }

    // MARK: - 语种选择

    private var typeSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(NewSongExpressViewModel.songTypes) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.loadSongs(type: type.id)
                        }
                    } label: {
                        let isSelected = viewModel.selectedType == type.id
                        let mangaForeground = isSelected
                            ? ThemeColorCustomization.readableForegroundColor(on: MangaStyle.labelYellow, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk)
                            : MangaStyle.ink
                        Text(LocalizedStringKey(type.nameKey))
                            .font(typeChipFont(isSelected: isSelected))
                            .foregroundColor(MangaStyle.isActive ? mangaForeground : typeChipForeground(isSelected: isSelected))
                            .padding(.horizontal, MangaStyle.isActive ? 12 : (PetWhiteStyle.isActive ? 14 : (MujiStyle.isActive ? 13 : ((SignalStyle.isActive || NeumorphicStyle.isActive || CapsuleStyle.isActive || SequoiaStyle.isActive) ? 14 : 16))))
                            .padding(.vertical, ThemedPageStyle.isActive ? 9 : 8)
                            .background(typeChipBackground(isSelected: isSelected))
                            .clipShape(MangaStyle.isActive ? AnyShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)) : AnyShape(Capsule()))
                            .contentShape(MangaStyle.isActive ? AnyShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)) : AnyShape(Capsule()))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    @ViewBuilder
    private func typeChipBackground(isSelected: Bool) -> some View {
        if NeumorphicStyle.isActive {
            NeumorphicSurfaceBackground(
                cornerRadius: 16,
                elevated: isSelected,
                pressed: !isSelected,
                tint: isSelected ? NeumorphicStyle.accent.opacity(0.16) : NeumorphicStyle.surface
            )
        } else if SequoiaStyle.isActive {
            Capsule()
                .fill(isSelected ? SequoiaStyle.accent : SequoiaStyle.materialList.opacity(0.76))
                .overlay(
                    Capsule()
                        .stroke((isSelected ? SequoiaStyle.accent : SequoiaStyle.separator).opacity(0.42), lineWidth: 0.55)
                )
        } else if PetWhiteStyle.isActive {
            Capsule()
                .fill(isSelected ? PetWhiteStyle.butter : PetWhiteStyle.surfaceRaised)
                .overlay(
                    Capsule()
                        .stroke(PetWhiteStyle.stroke.opacity(isSelected ? 1 : 0.42), lineWidth: isSelected ? 1.4 : 1)
                )
        } else if SignalStyle.isActive {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? SignalStyle.accent : SignalStyle.control)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.22) : SignalStyle.separator.opacity(0.75), lineWidth: 0.8)
                )
                .shadow(color: isSelected ? SignalStyle.accent.opacity(0.18) : .clear, radius: 12, x: 0, y: 7)
        } else if CapsuleStyle.isActive {
            Capsule()
                .fill(isSelected ? CapsuleStyle.amber : CapsuleStyle.surfaceRaised.opacity(0.82))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.32) : CapsuleStyle.separator.opacity(0.48), lineWidth: 0.8)
                )
                .shadow(color: isSelected ? CapsuleStyle.amber.opacity(0.15) : .clear, radius: 12, x: 0, y: 7)
        } else if MangaStyle.isActive {
            RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                .fill(isSelected ? MangaStyle.labelYellow : MangaStyle.bubbleWhite.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                        .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.fineStrokeWidth)
                )
        } else {
            Capsule()
                .fill(MujiStyle.isActive ? (isSelected ? MujiStyle.clay : MujiStyle.surface.opacity(0.78)) : (isSelected ? Color.monoAccent : Color.clear))
                .overlay(
                    Capsule()
                        .stroke(MujiStyle.isActive && !isSelected ? MujiStyle.hairline.opacity(0.48) : Color.clear, lineWidth: 0.6)
                )
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            if SignalStyle.isActive {
                SignalIconBadge(icon: .musicNote, tint: SignalStyle.olive, size: 54)
            } else if CapsuleStyle.isActive {
                CapsuleIconBadge(icon: .musicNote, tint: CapsuleStyle.amber, size: 54)
            } else if SequoiaStyle.isActive {
                SequoiaIconBadge(icon: .musicNote, tint: SequoiaStyle.green, size: 54)
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteIconBadge(icon: .musicNote, size: 54)
            } else {
                MonoIcon(icon: .musicNote, size: 40, color: .monoTextSecondary.opacity(0.3))
            }
            Text(LocalizedStringKey("empty_no_results"))
                .font(emptyStateFont)
                .foregroundColor(emptyStateColor)
        }
        .padding(.vertical, MinimalWhiteStyle.isActive ? 44 : 0)
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

    // MARK: - 完整列表

    private var fullListSection: some View {
        Group {
            if CapsuleStyle.isActive {
                capsuleFullListSection
            } else if PetWhiteStyle.isActive {
                petWhiteFullListSection
            } else if MinimalWhiteStyle.isActive {
                minimalWhiteFullListSection
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    fullListToolbar
                    newSongSearchBar
                    newSongRows
                }
            }
        }
        .monoSheet(isPresented: $showBatchAddToPlaylist, preset: .standard) {
            BatchAddToPlaylistSheet(songs: newSongFiltered.filter { selectedSongIds.contains($0.identityKey) })
        }
    }

    private var minimalWhiteFullListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fullListToolbar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            newSongSearchBar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            newSongRows
        }
        .padding(14)
        .background(
            MinimalWhiteSurfaceBackground(
                cornerRadius: MinimalWhiteStyle.chromeRadius,
                elevated: false,
                tint: MinimalWhiteStyle.glassFill
            )
        )
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }

    private var petWhiteFullListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetWhiteSectionTitle(
                title: "NEW SONGS",
                detail: String(format: NSLocalizedString("songs_count_format", comment: ""), viewModel.songs.count),
                icon: .musicNote,
                tint: PetWhiteStyle.butter
            )

            fullListToolbar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            newSongSearchBar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            newSongRows
        }
        .padding(14)
        .background(PetWhiteSurfaceBackground(cornerRadius: PetWhiteStyle.cardRadius, elevated: true, tint: PetWhiteStyle.surfaceRaised, accent: PetWhiteStyle.butter))
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }

    private var capsuleFullListSection: some View {
        CapsuleDetailSection(
            title: "NEW SONGS",
            subtitle: String(format: NSLocalizedString("songs_count_format", comment: ""), viewModel.songs.count),
            icon: .musicNote,
            tint: CapsuleStyle.amber
        ) {
            fullListToolbar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)
                .padding(.bottom, 2)

            newSongSearchBar
                .padding(.horizontal, -DeviceLayout.viewHorizontalPadding)

            newSongRows
        }
    }

    private var fullListToolbar: some View {
        HStack {
            Button(action: {
                if let first = viewModel.songs.first {
                    playerManager.playReplacingContext(song: first, in: viewModel.songs)
                }
            }) {
                if MangaStyle.isActive {
                    HStack(spacing: 7) {
                        MonoIcon(icon: .play, size: 13, color: MangaStyle.onStrokeInk, lineWidth: 2)
                        Text(LocalizedStringKey("artist_play_all"))
                            .font(MangaStyle.labelFont(12, weight: .black))
                            .tracking(0.6)
                    }
                    .foregroundStyle(MangaStyle.onStrokeInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(MangaStyle.strokeInk))
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(MangaStyle.accentPink)
                            .offset(x: 2.2, y: 2.2)
                    )
                } else if MujiStyle.isActive {
                    MujiActionPill(title: String(localized: "artist_play_all"), icon: .play, selected: true, tint: MujiStyle.clay)
                } else if NeumorphicStyle.isActive {
                    NeumorphicPlayPill(title: String(localized: "artist_play_all"), tint: NeumorphicStyle.accent)
                } else if SignalStyle.isActive {
                    SignalPlayPill(title: String(localized: "artist_play_all"))
                } else if CapsuleStyle.isActive {
                    CapsuleDetailActionPill(
                        title: String(localized: "artist_play_all"),
                        icon: .play,
                        tint: CapsuleStyle.amber
                    )
                } else if SequoiaStyle.isActive {
                    SequoiaPill(text: String(localized: "artist_play_all"), icon: .play, tint: SequoiaStyle.accent, selected: true)
                } else if PetWhiteStyle.isActive {
                    HStack(spacing: 7) {
                        PetWhitePackIcon(icon: .play, size: 13, visualScale: 1.05, fallbackColor: PetWhiteStyle.onAccent)
                        Text(LocalizedStringKey("artist_play_all"))
                            .font(PetWhiteStyle.labelFont(12, weight: .black))
                    }
                    .foregroundStyle(PetWhiteStyle.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(PetWhiteStyle.dogOrange, in: Capsule())
                    .overlay(Capsule().stroke(PetWhiteStyle.stroke, lineWidth: PetWhiteStyle.fineStrokeWidth))
                } else if MinimalWhiteStyle.isActive {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .play, size: 14, color: MinimalWhiteStyle.onAccent, lineWidth: 1.6)
                        Text(LocalizedStringKey("artist_play_all"))
                            .font(MinimalWhiteStyle.labelFont(14, weight: .semibold))
                            .foregroundColor(MinimalWhiteStyle.onAccent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(MinimalWhiteStyle.ink, in: Capsule(style: .continuous))
                } else {
                    HStack(spacing: 6) {
                        MonoIcon(icon: .play, size: 12, color: .monoTextPrimary)
                        Text(LocalizedStringKey("artist_play_all"))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.monoTextPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.monoTextPrimary.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))

            Spacer()

            Text(String(format: NSLocalizedString("songs_count_format", comment: ""), viewModel.songs.count))
                .font(countFont)
                .foregroundColor(countColor)
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }

    private var newSongSearchBar: some View {
        PlaylistSearchBar(
            searchText: $newSongSearch,
            isSearching: $isNewSongSearching,
            isSelectMode: $isSelectMode,
            selectedIds: $selectedSongIds,
            songs: newSongFiltered,
            onBatchQueue: {
                let selected = newSongFiltered.filter { selectedSongIds.contains($0.identityKey) }
                SongBatchActionHelper.addToQueue(selected) {
                    isSelectMode = false
                    selectedSongIds.removeAll()
                }
            },
            onBatchDownload: { newSongBatchDownload() },
            onBatchCollect: { showBatchAddToPlaylist = true }
        )
    }

    private var newSongRows: some View {
        LazyVStack(spacing: PetWhiteStyle.isActive ? 0 : (CapsuleStyle.isActive ? 4 : 0)) {
            ForEach(Array(newSongFiltered.enumerated()), id: \.element.identityKey) { index, song in
                SongListRow(
                    song: song,
                    index: index,
                    isSelecting: isSelectMode,
                    isSelected: selectedSongIds.contains(song.identityKey),
                    onArtistTap: { id in
                        selectedArtistId = id
                        showArtistDetail = true
                    },
                    onDetailTap: { s in
                        selectedSongForDetail = s
                        showSongDetail = true
                    },
                    onAlbumTap: { id in
                        selectedAlbumId = id
                        showAlbumDetail = true
                    },
                    onTap: {
                        if isSelectMode {
                            if selectedSongIds.contains(song.identityKey) {
                                selectedSongIds.remove(song.identityKey)
                            } else {
                                selectedSongIds.insert(song.identityKey)
                            }
                        } else {
                            playerManager.play(song: song, in: newSongFiltered)
                        }
                    },
                    horizontalPadding: (PetWhiteStyle.isActive || MinimalWhiteStyle.isActive) ? CGFloat(0) : nil
                )
            }

            NoMoreDataView()
        }
    }

    private var newSongFiltered: [Song] { viewModel.songs.filtered(by: newSongSearch) }

    private var loadingTint: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.dogOrange }
        if SignalStyle.isActive { return SignalStyle.accent }
        if CapsuleStyle.isActive { return CapsuleStyle.amber }
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        return .monoTextSecondary
    }

    private func typeChipFont(isSelected: Bool) -> Font {
        if MangaStyle.isActive { return MangaStyle.labelFont(12, weight: .black) }
        if PetWhiteStyle.isActive { return PetWhiteStyle.labelFont(14, weight: isSelected ? .black : .bold) }
        if MujiStyle.isActive { return MujiStyle.labelFont(14, weight: isSelected ? .semibold : .regular) }
        if SignalStyle.isActive { return SignalStyle.labelFont(14, weight: isSelected ? .bold : .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(14, weight: isSelected ? .semibold : .medium) }
        if CapsuleStyle.isActive { return CapsuleStyle.labelFont(14, weight: isSelected ? .bold : .semibold) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(14, weight: isSelected ? .semibold : .medium) }
        return .system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded)
    }

    private func typeChipForeground(isSelected: Bool) -> Color {
        if PetWhiteStyle.isActive { return isSelected ? PetWhiteStyle.ink : PetWhiteStyle.inkSoft }
        if MujiStyle.isActive { return isSelected ? MujiStyle.onTint : MujiStyle.inkSoft }
        if SignalStyle.isActive { return isSelected ? SignalStyle.onAccent : SignalStyle.inkSoft }
        if NeumorphicStyle.isActive { return isSelected ? NeumorphicStyle.accent : NeumorphicStyle.inkSoft }
        if CapsuleStyle.isActive { return isSelected ? CapsuleStyle.readableLabel(on: CapsuleStyle.amber) : CapsuleStyle.inkSoft }
        if SequoiaStyle.isActive { return isSelected ? SequoiaStyle.onAccent : SequoiaStyle.inkSoft }
        return isSelected ? .monoIconForeground : .monoTextSecondary
    }

    private var emptyStateFont: Font {
        if PetWhiteStyle.isActive { return PetWhiteStyle.labelFont(14, weight: .bold) }
        if SignalStyle.isActive { return SignalStyle.labelFont(14, weight: .medium) }
        if CapsuleStyle.isActive { return CapsuleStyle.labelFont(14, weight: .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(14, weight: .medium) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(14, weight: .medium) }
        return .system(size: 14, weight: .medium, design: .rounded)
    }

    private var emptyStateColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.inkSoft }
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        return .monoTextSecondary
    }

    private var countFont: Font {
        if MangaStyle.isActive { return MangaStyle.bodyFont(13, weight: .bold) }
        if PetWhiteStyle.isActive { return PetWhiteStyle.labelFont(13, weight: .bold) }
        if MujiStyle.isActive { return MujiStyle.labelFont(13, weight: .regular) }
        if SignalStyle.isActive { return SignalStyle.labelFont(13, weight: .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(13, weight: .medium) }
        if CapsuleStyle.isActive { return CapsuleStyle.labelFont(13, weight: .bold) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(13, weight: .regular) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(13, weight: .regular) }
        return .system(size: 13, weight: .medium, design: .rounded)
    }

    private var countColor: Color {
        if MangaStyle.isActive { return MangaStyle.inkSub }
        if PetWhiteStyle.isActive { return PetWhiteStyle.inkSoft }
        if MujiStyle.isActive { return MujiStyle.inkSoft }
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        return .monoTextSecondary
    }

    private func newSongBatchDownload() {
        let selected = newSongFiltered.filter { selectedSongIds.contains($0.identityKey) }
        for song in selected {
            if song.isQQMusic {
                DownloadManager.shared.downloadQQ(song: song, quality: DownloadManager.defaultQQDownloadQuality)
            } else {
                DownloadManager.shared.download(song: song, quality: DownloadManager.defaultNeteaseDownloadQuality)
            }
        }
        AlertManager.shared.show(title: String(localized: "download_batch_added_title"), message: L10n.format("download_batch_queue_added_format", selected.count), primaryButtonTitle: String(localized: "common_confirm"), primaryAction: {})
        withAnimation { isSelectMode = false; selectedSongIds.removeAll() }
    }
}
