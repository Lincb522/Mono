import SwiftUI

/// 最近播放 - 完整列表页
struct RecentPlayHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss
    private let playerManager = PlayerManager.shared
    @State private var playbackHistory = PlayerManager.shared.history
    @ObservedObject private var settings = SettingsManager.shared
    
    let explicitSongs: [Song]?
    
    init(songs: [Song]? = nil) {
        self.explicitSongs = songs
    }
    
    @State private var showClearConfirm = false
    @State private var isSelectMode = false
    @State private var selectedSongIds: Set<String> = []
    @State private var showBatchAddToPlaylist = false
    @State private var recentSearch = ""
    @State private var isRecentSearching = false
    
    private var displaySongs: [Song] { explicitSongs ?? playbackHistory }
    private var recentFiltered: [Song] { displaySongs.filtered(by: recentSearch) }
    
    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            if MangaStyle.isActive {
                MangaRootBackdrop()
            } else if MujiStyle.isActive {
                MujiRootBackdrop()
            } else if CapsuleStyle.isActive {
                CapsuleRootBackdrop()
            } else if SequoiaStyle.isActive {
                SequoiaRootBackdrop()
            } else if SignalStyle.isActive {
                SignalRootBackdrop()
            } else {
                ThemedPageBackground()
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        if MangaStyle.isActive {
                            MangaPageHeader(
                                eyebrow: "HISTORY",
                                title: String(localized: "profile_recently_played"),
                                subtitle: ""
                            ) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                                        .fill(MangaStyle.mint)
                                    MonoIcon(icon: .history, size: 23, color: MangaStyle.ink, lineWidth: 2)
                                }
                                .frame(width: 48, height: 48)
                                .overlay(RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous).stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth))
                                .background(RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous).fill(MangaStyle.strokeInk).offset(x: MangaStyle.shadowOffset, y: MangaStyle.shadowOffset))
                            }
                        } else if MujiStyle.isActive {
                            MujiPageHeader(
                                eyebrow: String(localized: "profile_recently_played"),
                                title: String(localized: "profile_recently_played"),
                                subtitle: ""
                            ) {
                                MujiIconBadge(icon: .history, tint: MujiStyle.tea, size: 48)
                            }
                        } else if NeumorphicStyle.isActive {
                            NeumorphicPageHeader(
                                eyebrow: "HISTORY",
                                title: String(localized: "profile_recently_played"),
                                subtitle: ""
                            ) {
                                NeumorphicIconBadge(icon: .history, tint: NeumorphicStyle.warm, size: 48)
                            }
                        } else if CapsuleStyle.isActive {
                            CapsulePageHeader(
                                eyebrow: "HISTORY",
                                title: String(localized: "profile_recently_played"),
                                subtitle: ""
                            ) {
                                CapsuleIconBadge(icon: .history, tint: CapsuleStyle.cyan, size: 48)
                            }
                        } else if SequoiaStyle.isActive {
                            SequoiaPageHeader(
                                eyebrow: "HISTORY",
                                title: String(localized: "profile_recently_played"),
                                subtitle: ""
                            ) {
                                SequoiaIconBadge(icon: .history, tint: SequoiaStyle.accent, size: 48)
                            }
                        } else if SignalStyle.isActive {
                            SignalNestedPageHeader(
                                title: String(localized: "profile_recently_played"),
                                eyebrow: "PLAYBACK LOG",
                                icon: .history,
                                module: .changelog
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        PlaylistSearchBar(
                            searchText: $recentSearch,
                            isSearching: $isRecentSearching,
                            isSelectMode: $isSelectMode,
                            selectedIds: $selectedSongIds,
                            songs: recentFiltered,
                            onBatchQueue: {
                                let selected = recentFiltered.filter { selectedSongIds.contains($0.identityKey) }
                                SongBatchActionHelper.addToQueue(selected) {
                                    isSelectMode = false
                                    selectedSongIds.removeAll()
                                }
                            },
                            onBatchDownload: { recentBatchDownload() },
                            onBatchCollect: { showBatchAddToPlaylist = true }
                        )
                        
                        LazyVStack(spacing: 0) {
                            ForEach(Array(recentFiltered.enumerated()), id: \.element.identityKey) { index, song in
                                SongListRow(
                                    song: song,
                                    index: index,
                                    isSelecting: isSelectMode,
                                    isSelected: selectedSongIds.contains(song.identityKey),
                                    onArtistTap: nil,
                                    onDetailTap: nil,
                                    onAlbumTap: nil,
                                    onTap: {
                                        if isSelectMode {
                                            if selectedSongIds.contains(song.identityKey) {
                                                selectedSongIds.remove(song.identityKey)
                                            } else {
                                                selectedSongIds.insert(song.identityKey)
                                            }
                                        } else {
                                            if let rid = song.podcastRadioId, rid > 0 {
                                                playerManager.playPodcast(song: song, in: recentFiltered, radioId: rid)
                                                NotificationCenter.default.post(name: .init("OpenRadioPlayer"), object: rid)
                                            } else {
                                                playerManager.play(song: song, in: recentFiltered)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    FloatingBarBottomSpacer()
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }
        .onReceive(playerManager.$history) { songs in
            if explicitSongs == nil { playbackHistory = songs }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .toolbar {
            HStack {
                if explicitSongs == nil {
                    Button {
                        showClearConfirm = true
                    } label: {
                        MonoIcon(
                            icon: .trash,
                            size: 16,
                            color: MangaStyle.isActive ? MangaStyle.red : (MujiStyle.isActive ? MujiStyle.red : (CapsuleStyle.isActive ? CapsuleStyle.coral : (SequoiaStyle.isActive ? SequoiaStyle.red : (NeumorphicStyle.isActive ? NeumorphicStyle.red : .monoTextPrimary))))
                        )
                    }
                    .disabled(playbackHistory.isEmpty)
                }
                
                Button {
                    if let first = displaySongs.first {
                        playerManager.playReplacingContext(song: first, in: displaySongs)
                    }
                } label: {
                    if MangaStyle.isActive {
                        MangaLabel(text: String(localized: "artist_play_all"), tint: MangaStyle.labelYellow, small: true)
                    } else if MujiStyle.isActive {
                        MujiActionPill(title: String(localized: "artist_play_all"), icon: .play, selected: true, tint: MujiStyle.clay)
                    } else if NeumorphicStyle.isActive {
                        NeumorphicPlayPill(title: String(localized: "artist_play_all"))
                    } else if CapsuleStyle.isActive {
                        CapsulePillLabel(
                            title: String(localized: "artist_play_all"),
                            icon: .play,
                            tint: CapsuleStyle.accent,
                            selected: true
                        )
                    } else if SequoiaStyle.isActive {
                        SequoiaPill(text: String(localized: "artist_play_all"), icon: .play, tint: SequoiaStyle.accent, selected: true)
                    } else if SignalStyle.isActive {
                        SignalPill(
                            text: String(localized: "artist_play_all"),
                            tint: SignalStyle.accent,
                            icon: .play,
                            selected: true,
                            compact: true
                        )
                    } else {
                        HStack(spacing: 6) {
                            MonoIcon(icon: .play, size: 12, color: .monoTextPrimary)
                            Text(LocalizedStringKey("artist_play_all"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.monoTextPrimary)
                        }
                    }
                }
                .disabled(displaySongs.isEmpty)
            }
        }
        .alert(String(localized: "清空播放历史"), isPresented: $showClearConfirm) {
            Button(String(localized: "cancel"), role: .cancel) { }
            Button(String(localized: "search_clear"), role: .destructive) {
                playerManager.clearPlaybackHistory()
            }
        } message: {
            Text(String(localized: "确定要清空所有播放历史吗？此操作无法撤销。"))
        }
        .monoSheet(isPresented: $showBatchAddToPlaylist, preset: .standard){
            BatchAddToPlaylistSheet(songs: recentFiltered.filter { selectedSongIds.contains($0.identityKey) })
        }
    }
    
    private func recentBatchDownload() {
        let selected = recentFiltered.filter { selectedSongIds.contains($0.identityKey) }
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
