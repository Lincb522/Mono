import SwiftUI

// MARK: - Cross-platform artist detail

struct ArtistDetailView: View {
    let artistId: Int
    private let initialArtist: ArtistInfo?
    @StateObject private var viewModel = ArtistDetailViewModel()

    @State private var selectedTab = 0 // 0: 音乐, 1: 专辑, 2: 视频, 3: 相似
    @State private var showFullDescription = false
    @State private var selectedArtistId: Int?
    @State private var selectedArtistInfo: ArtistInfo?
    @State private var showArtistDetail = false
    @State private var selectedSongForDetail: Song?
    @State private var showSongDetail = false
    @State private var selectedAlbumId: Int?
    @State private var selectedAlbumInfo: AlbumInfo?
    @State private var showAlbumDetail = false
    @State private var selectedMV: MVIdItem?
    @State private var isArtistSelectMode = false
    @State private var artistSelectedSongIds: Set<String> = []
    @State private var showArtistBatchPlaylist = false
    @State private var artistSongSearch = ""
    @State private var isArtistSongSearching = false

    init(artistId: Int) {
        self.artistId = artistId
        self.initialArtist = nil
    }

    init(artist: ArtistInfo) {
        self.artistId = artist.id
        self.initialArtist = artist
    }

    private var displayArtist: ArtistInfo? { viewModel.artist ?? initialArtist }
    private var artistSongFiltered: [Song] { viewModel.songs.filtered(by: artistSongSearch) }
    private var songsToCollect: [Song] {
        isArtistSelectMode ? artistSongFiltered.filter { artistSelectedSongIds.contains($0.identityKey) } : viewModel.songs
    }

    private var tabs: [ArtistDetailTab] {
        var result = [
            ArtistDetailTab(id: 0, title: String(localized: "artist_tab_songs"), count: displayArtist?.musicSize),
            ArtistDetailTab(id: 1, title: String(localized: "artist_tab_album"), count: displayArtist?.albumSize)
        ]
        if initialArtist?.source != .appleMusic && initialArtist?.source != .kugou {
            result.append(ArtistDetailTab(id: 2, title: String(localized: "artist_tab_video"), count: displayArtist?.mvSize))
        }
        if initialArtist?.source != .kugou {
            result.append(ArtistDetailTab(id: 3, title: String(localized: "artist_tab_similar")))
        }
        return result
    }

    var body: some View {
        if let artist = initialArtist, artist.source == .qqmusic {
            if let mid = artist.qqMid, !mid.isEmpty {
                QQMusicDetailView(detailType: .artist(
                    mid: mid,
                    name: artist.name,
                    coverUrl: artist.picUrl ?? artist.img1v1Url
                ))
                .id(artist.navigationIdentity)
            } else {
                Text(String(localized: "artist_missing_identifier"))
                    .foregroundStyle(Color.monoTextSecondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .monoNavigationBackButton()
            }
        } else {
            catalogBody
        }
    }

    private var catalogBody: some View {
        ArtistDetailPage(
            identity: ArtistNameArtworkIdentity(name: displayArtist?.name ?? "", aliases: displayArtist?.alias ?? [], qqMid: displayArtist?.qqMid),
            coverURL: displayArtist?.coverUrl?.sized(1000),
            source: (displayArtist?.source ?? .netease).shortName,
            fansCount: viewModel.fansCount,
            summary: displayArtist?.briefDesc,
            tabs: tabs,
            selectedTab: $selectedTab,
            canPlay: !viewModel.songs.isEmpty,
            play: {
                if let first = viewModel.songs.first {
                    PlayerManager.shared.playReplacingContext(song: first, in: viewModel.songs)
                }
            },
            secondaryAction: { showArtistBatchPlaylist = true },
            showBiography: { showFullDescription = true }
        ) {
            tabContent
        }
        .navigationDestination(isPresented: $showArtistDetail) {
            if let artist = selectedArtistInfo {
                ArtistDetailView(artist: artist)
            } else if let artistId = selectedArtistId {
                ArtistDetailView(artistId: artistId)

            }
        }
        .navigationDestination(isPresented: $showSongDetail) {
            if let song = selectedSongForDetail {
                SongDetailView(song: song)

            }
        }
        .navigationDestination(isPresented: $showAlbumDetail) {
            if let album = selectedAlbumInfo {
                AlbumDetailView(album: album)
            } else if let albumId = selectedAlbumId {
                AlbumDetailView(albumId: albumId, albumName: nil, albumCoverUrl: nil)

            }
        }
        .fullScreenCover(item: $selectedMV) { item in
            MVPlayerView(mvId: item.id)
        }
        .monoSheet(isPresented: $showFullDescription, preset: .standard){
            ArtistBioSheet(
                viewModel: viewModel,
                artistId: artistId,
                loadsRemoteDescription: initialArtist?.source != .appleMusic && initialArtist?.source != .kugou
            )
        }
        .monoSheet(isPresented: $showArtistBatchPlaylist, preset: .standard) {
            BatchAddToPlaylistSheet(songs: songsToCollect)
        }
        .onAppear {
            if let initialArtist {
                viewModel.loadData(artist: initialArtist)
            } else {
                viewModel.loadData(artistId: artistId)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            guard initialArtist?.source != .appleMusic && initialArtist?.source != .kugou else { return }
            if newTab == 1 { viewModel.loadAlbums(artistId: artistId) }
            if newTab == 2 { viewModel.loadMVs(artistId: artistId) }
            if newTab == 3 { viewModel.loadSimiArtists(artistId: artistId) }
        }
    }
}

private extension ArtistDetailView {
    func openArtist(_ artist: ArtistInfo) {
        selectedArtistInfo = artist
        selectedArtistId = nil
        showArtistDetail = true
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 1: albumsTab
        case 2: mvsTab
        case 3: similarArtistsTab
        default: songsTab
        }
    }

    @ViewBuilder
    var songsTab: some View {
        if viewModel.isLoading && viewModel.songs.isEmpty {
            ArtistContentState(isLoading: true, text: "")
        } else if viewModel.songs.isEmpty {
            ArtistContentState(text: String(localized: "artist_no_songs"))
        } else {
            VStack(spacing: 0) {
                ArtistSongToolbar(
                    searchText: $artistSongSearch,
                    isSearching: $isArtistSongSearching,
                    isSelectMode: $isArtistSelectMode,
                    selectedIds: $artistSelectedSongIds,
                    songs: artistSongFiltered,
                    onBatchQueue: {
                        SongBatchActionHelper.addToQueue(songsToCollect) {
                            isArtistSelectMode = false
                            artistSelectedSongIds.removeAll()
                        }
                    },
                    onBatchDownload: { artistBatchDownload() },
                    onBatchCollect: { showArtistBatchPlaylist = true }
                )
                artistSongRows
                if artistSongFiltered.isEmpty {
                    ArtistContentState(text: String(localized: "artist_no_songs"))
                }
            }
        }
    }
    private var artistSongRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(artistSongFiltered.enumerated()), id: \.element.identityKey) { index, song in
                SongListRow(song: song, index: index, isSelecting: isArtistSelectMode, isSelected: artistSelectedSongIds.contains(song.identityKey), onArtistTap: initialArtist?.source == .appleMusic || initialArtist?.source == .kugou ? nil : { artistId in
                    selectedArtistInfo = nil
                    selectedArtistId = artistId
                    showArtistDetail = true
                }, onDetailTap: { detailSong in
                    selectedSongForDetail = detailSong
                    showSongDetail = true
                }, onAlbumTap: initialArtist?.source == .appleMusic || initialArtist?.source == .kugou ? nil : { albumId in
                    selectedAlbumInfo = nil
                    selectedAlbumId = albumId
                    showAlbumDetail = true
                }, onTap: {
                    if isArtistSelectMode {
                        if artistSelectedSongIds.contains(song.identityKey) {
                            artistSelectedSongIds.remove(song.identityKey)
                        } else {
                            artistSelectedSongIds.insert(song.identityKey)
                        }
                    } else {
                        PlayerManager.shared.play(song: song, in: artistSongFiltered)
                    }
                }, usesArtistStyle: true)
            }
        }
    }

    private func artistBatchDownload() {
        let selected = artistSongFiltered.filter { artistSelectedSongIds.contains($0.identityKey) }
        for song in selected {
            if song.isQQMusic {
                DownloadManager.shared.downloadQQ(song: song, quality: PlayerManager.shared.qqMusicQuality)
            } else {
                DownloadManager.shared.download(song: song, quality: PlayerManager.shared.soundQuality)
            }
        }
        AlertManager.shared.show(title: String(localized: "download_batch_added_title"), message: L10n.format("download_batch_queue_added_format", selected.count), primaryButtonTitle: String(localized: "common_confirm"), primaryAction: {})
        withAnimation { isArtistSelectMode = false; artistSelectedSongIds.removeAll() }
    }


    @ViewBuilder
    var albumsTab: some View {
        if viewModel.isLoadingAlbums && viewModel.albums.isEmpty {
            ArtistContentState(isLoading: true, text: "")
        } else if viewModel.albums.isEmpty {
            ArtistContentState(text: String(localized: "artist_no_albums"))
        } else {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.albums) { album in
                    ArtistAlbumRow(album: album) {
                        if album.source == .appleMusic || album.source == .kugou {
                            selectedAlbumInfo = album
                            selectedAlbumId = nil
                        } else {
                            selectedAlbumInfo = nil
                            selectedAlbumId = album.id
                        }
                        showAlbumDetail = true
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    var mvsTab: some View {
        if viewModel.isLoadingMVs && viewModel.mvs.isEmpty {
            ArtistContentState(isLoading: true, text: "")
        } else if viewModel.mvs.isEmpty {
            ArtistContentState(text: String(localized: "artist_no_videos"))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                ForEach(viewModel.mvs) { mv in
                    ArtistVideoCard(name: mv.displayName, coverURL: mv.coverUrl.flatMap(URL.init(string:)), duration: mv.durationText) {
                        selectedMV = MVIdItem(id: mv.id)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    var similarArtistsTab: some View {
        if viewModel.isLoadingSimi && viewModel.simiArtists.isEmpty {
            ArtistContentState(isLoading: true, text: "")
        } else if viewModel.simiArtists.isEmpty {
            ArtistContentState(text: String(localized: "artist_no_similar"))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 20) {
                ForEach(viewModel.simiArtists) { artist in
                    Button { openArtist(artist) } label: {
                        VStack(spacing: 10) {
                            CachedAsyncImage(url: artist.coverUrl?.sized(240)) { Color.white.opacity(0.1) }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(Circle())
                            Text(artist.name).font(.subheadline).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

struct ArtistBioSheet: View {
    var viewModel: ArtistDetailViewModel
    let artistId: Int
    var loadsRemoteDescription = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss

    var body: some View {
        VStack(spacing: 0) {
            // 头部：歌手头像 + 名字
            HStack(spacing: 14) {
                if let artist = viewModel.artist {
                    CachedAsyncImage(url: artist.coverUrl?.sized(200)) {
                        Circle().fill(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.controlGlassFill : (SignalStyle.isActive ? SignalStyle.controlPressed : (NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : (SequoiaStyle.isActive ? SequoiaStyle.materialList : Color.monoGlassTint))))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay {
                        if NeumorphicStyle.isActive {
                            Circle()
                                .stroke(NeumorphicStyle.separator.opacity(0.35), lineWidth: 0.7)
                        } else if SignalStyle.isActive {
                            Circle()
                                .stroke(SignalStyle.separator.opacity(0.68), lineWidth: 0.8)
                        } else if SequoiaStyle.isActive {
                            Circle()
                                .stroke(SequoiaStyle.separator.opacity(0.78), lineWidth: 0.6)
                        } else if MinimalWhiteStyle.isActive {
                            Circle()
                                .stroke(MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.artist?.name ?? "")
                        .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.titleFont(20, weight: .semibold) : (SignalStyle.isActive ? SignalStyle.titleFont(20, weight: .bold) : (NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(20, weight: .semibold) : (SequoiaStyle.isActive ? SequoiaStyle.titleFont(20, weight: .semibold) : .rounded(size: 20, weight: .bold)))))
                        .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.ink : (SignalStyle.isActive ? SignalStyle.ink : (NeumorphicStyle.isActive ? NeumorphicStyle.ink : (SequoiaStyle.isActive ? SequoiaStyle.ink : .monoTextPrimary))))

                    HStack(spacing: 12) {
                        if let albumSize = viewModel.artist?.albumSize, albumSize > 0 {
                            HStack(spacing: 4) {
                                MonoIcon(icon: .album, size: 12, color: MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                                Text(String(format: NSLocalizedString("artist_album_count", comment: ""), albumSize))
                            }
                            .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(12, weight: .regular) : (SignalStyle.isActive ? SignalStyle.labelFont(12, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(12, weight: .regular) : .rounded(size: 12)))))
                            .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                        }
                        if let musicSize = viewModel.artist?.musicSize, musicSize > 0 {
                            HStack(spacing: 4) {
                                MonoIcon(icon: .musicNote, size: 12, color: MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                                Text(String(format: NSLocalizedString("artist_song_count", comment: ""), musicSize))
                            }
                            .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(12, weight: .regular) : (SignalStyle.isActive ? SignalStyle.labelFont(12, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(12, weight: .regular) : .rounded(size: 12)))))
                            .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                        }
                    }
                }

                Spacer()

                Button(action: { dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss) }) {
                    MonoIcon(icon: .close, size: 20, color: MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                        .frame(width: 32, height: 32)
                        .background {
                            if NeumorphicStyle.isActive {
                                NeumorphicSurfaceBackground(cornerRadius: 16, elevated: false, pressed: true, lightweight: true)
                            } else if SignalStyle.isActive {
                                SignalSurfaceBackground(cornerRadius: 16, elevated: false, pressed: true, fill: SignalStyle.controlPressed)
                            } else if SequoiaStyle.isActive {
                                SequoiaSurfaceBackground(cornerRadius: 16, elevated: false, pressed: true, role: .list)
                            } else if MinimalWhiteStyle.isActive {
                                MinimalWhiteCircleBackground(elevated: false)
                            } else {
                                Circle().fill(Color.monoSeparator)
                            }
                        }
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Rectangle()
                .fill(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.hairline : (SignalStyle.isActive ? SignalStyle.separator.opacity(0.52) : (NeumorphicStyle.isActive ? NeumorphicStyle.separator.opacity(0.45) : (SequoiaStyle.isActive ? SequoiaStyle.separator : Color.monoSeparator))))
                .frame(height: 0.5)

            if viewModel.isLoadingDesc {
                Spacer()
                MonoLoadingView(text: "LOADING")
                Spacer()
            } else if let desc = viewModel.descResult {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let brief = desc.briefDesc, !brief.isEmpty {
                            bioCard {
                                Text(brief)
                                    .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.bodyFont(15, weight: .regular) : (SignalStyle.isActive ? SignalStyle.bodyFont(15, weight: .regular) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .regular) : (SequoiaStyle.isActive ? SequoiaStyle.bodyFont(15, weight: .regular) : .rounded(size: 15, weight: .regular)))))
                                    .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkSoft : (SignalStyle.isActive ? SignalStyle.ink : (NeumorphicStyle.isActive ? NeumorphicStyle.ink : (SequoiaStyle.isActive ? SequoiaStyle.ink : .monoTextPrimary))))
                                    .lineSpacing(6)
                            }
                        }

                        ForEach(desc.sections) { section in
                            bioCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.title)
                                        .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.titleFont(16, weight: .semibold) : (SignalStyle.isActive ? SignalStyle.titleFont(16, weight: .bold) : (NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(16, weight: .semibold) : (SequoiaStyle.isActive ? SequoiaStyle.titleFont(16, weight: .semibold) : .rounded(size: 16, weight: .semibold)))))
                                        .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.ink : (SignalStyle.isActive ? SignalStyle.ink : (NeumorphicStyle.isActive ? NeumorphicStyle.ink : (SequoiaStyle.isActive ? SequoiaStyle.ink : .monoTextPrimary))))
                                    Text(section.content)
                                        .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.bodyFont(14, weight: .regular) : (SignalStyle.isActive ? SignalStyle.bodyFont(14, weight: .regular) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(14, weight: .regular) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(14, weight: .regular) : .rounded(size: 14, weight: .regular)))))
                                        .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkSoft : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
                                        .lineSpacing(5)
                                }
                            }
                        }

                        if (desc.briefDesc ?? "").isEmpty && desc.sections.isEmpty {
                            noContentView
                        }
                    }
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let brief = viewModel.artist?.briefDesc, !brief.isEmpty {
                            bioCard {
                                Text(brief)
                                    .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.bodyFont(15, weight: .regular) : (SignalStyle.isActive ? SignalStyle.bodyFont(15, weight: .regular) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .regular) : (SequoiaStyle.isActive ? SequoiaStyle.bodyFont(15, weight: .regular) : .rounded(size: 15, weight: .regular)))))
                                    .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkSoft : (SignalStyle.isActive ? SignalStyle.ink : (NeumorphicStyle.isActive ? NeumorphicStyle.ink : (SequoiaStyle.isActive ? SequoiaStyle.ink : .monoTextPrimary))))
                                    .lineSpacing(6)
                            }
                        } else {
                            noContentView
                        }
                    }
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }
        .onAppear {
            if loadsRemoteDescription {
                viewModel.loadDesc(artistId: artistId)
            }
        }
        .background {
            MonoSheetAwareBackground {
                if NeumorphicStyle.isActive {
                    ThemeRenderBackdrop(theme: .neumorphic)
                } else if SignalStyle.isActive {
                    ThemeRenderBackdrop(theme: .default)
                } else if SequoiaStyle.isActive {
                    SequoiaRootBackdrop()
                } else if MinimalWhiteStyle.isActive {
                    MinimalWhiteRootBackdrop()
                } else {
                    ThemedPageBackground()
                }
            }
        }
    }

    private func bioCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            if NeumorphicStyle.isActive {
                NeumorphicSurfaceBackground(cornerRadius: 22, elevated: false)
            } else if SignalStyle.isActive {
                SignalSurfaceBackground(cornerRadius: 24, elevated: false, fill: SignalStyle.paper)
            } else if SequoiaStyle.isActive {
                SequoiaSurfaceBackground(cornerRadius: 22, elevated: true, role: .chrome)
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteSurfaceBackground(
                    cornerRadius: MinimalWhiteStyle.cardRadius,
                    elevated: false,
                    tint: MinimalWhiteStyle.glassFill
                )
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.monoGlassTint)
                    .monoGlass(cornerRadius: 20)
            }
        }
    }

    private var noContentView: some View {
        VStack(spacing: 14) {
            if NeumorphicStyle.isActive {
                NeumorphicIconBadge(icon: .info, tint: NeumorphicStyle.sage, size: 52)
            } else if SignalStyle.isActive {
                SignalIconBadge(icon: .info, tint: SignalStyle.olive, size: 52)
            } else if SequoiaStyle.isActive {
                SequoiaIconBadge(icon: .info, tint: SequoiaStyle.aqua, size: 52)
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteIconBadge(icon: .info, size: 52)
            } else {
                MonoIcon(icon: .info, size: 36, color: .monoTextSecondary.opacity(0.3))
            }
            Text(LocalizedStringKey("artist_no_bio"))
                .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(14, weight: .medium) : (SignalStyle.isActive ? SignalStyle.labelFont(14, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(14, weight: .medium) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(14, weight: .medium) : .rounded(size: 15)))))
                .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SignalStyle.isActive ? SignalStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
