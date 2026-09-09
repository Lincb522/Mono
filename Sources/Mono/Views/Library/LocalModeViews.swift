import SwiftUI
import Combine
import UniformTypeIdentifiers

private func localModeText(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private func localModeFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localModeText(key), locale: Locale.current, arguments: arguments)
}

private struct LocalSystemPlaylistDestinationView: View {
    let playlistId: String?
    let fallbackFilter: LocalMusicFilter

    var body: some View {
        if let playlistId {
            LocalPlaylistDetailView(playlistId: playlistId)
        } else {
            LocalMusicView(initialFilter: fallbackFilter)
        }
    }
}

enum LocalMusicFilter: CaseIterable, Identifiable {
    case all
    case favorites
    case downloads
    case recent

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .all: return "local_filter_all"
        case .favorites: return "local_filter_favorites"
        case .downloads: return "local_filter_downloads"
        case .recent: return "local_filter_recent"
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .all: return .musicNoteList
        case .favorites: return .liked
        case .downloads: return .download
        case .recent: return .history
        }
    }
}

enum LocalMusicSort: CaseIterable, Identifiable {
    case newest
    case title
    case artist

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .newest: return "local_sort_newest"
        case .title: return "local_sort_title"
        case .artist: return "local_sort_artist"
        }
    }
}

@MainActor
private func offlinePlayableSongs(from songs: [Song], using downloadManager: DownloadManager) -> [Song] {
    var seen = Set<Int>()

    return songs.filter { song in
        let isPlayable = song.isLocal || downloadManager.isDownloaded(song: song)
        guard isPlayable, !seen.contains(song.id) else { return false }
        seen.insert(song.id)
        return true
    }
}

@MainActor
private func recentOfflineSongs(limit: Int, using downloadManager: DownloadManager) -> [Song] {
    let history = HistoryRepository().getPlayHistory(limit: max(limit * 3, 30))
    var seen = Set<Int>()
    var songs: [Song] = []

    for item in history {
        let song = item.toSong()
        let isPlayable = song.isLocal || downloadManager.isDownloaded(song: song)
        guard isPlayable, !seen.contains(song.id) else { continue }
        seen.insert(song.id)
        songs.append(song)
        if songs.count >= limit {
            break
        }
    }

    return songs
}

@MainActor
private func localTotalDurationText(for songs: [Song]) -> String {
    let totalMs = songs.reduce(0) { $0 + ($1.dt ?? 0) }
    let hours = Double(totalMs) / 3_600_000
    if hours >= 10 { return "\(Int(hours))h" }
    if hours >= 1 { return String(format: "%.1fh", hours) }
    return "\(max(totalMs / 60_000, 0))m"
}

// MARK: - 首页

struct LocalModeHomeView: View {
    @ObservedObject private var localLibrary = LocalMusicLibraryManager.shared
    @ObservedObject private var localPlaylists = LocalPlaylistManager.shared
    private let downloadManager = DownloadManager.shared
    @ObservedObject private var downloadStatus = DownloadedSongStatusModel.shared
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showImporter = false
    @State private var recentSongs: [Song] = []

    private var customPlaylists: [LocalPlaylist] {
        localPlaylists.playlists.filter { !$0.isSystem }
    }

    private var favoriteSongs: [Song] {
        guard let playlist = localPlaylists.favoritePlaylist else { return [] }
        return offlinePlayableSongs(from: localPlaylists.songs(for: playlist), using: downloadManager)
    }

    private var downloadedSongs: [Song] {
        offlinePlayableSongs(from: downloadManager.fetchDownloadPlaylistSongs(), using: downloadManager)
    }

    private var recentlyAddedSongs: [Song] {
        Array(localLibrary.songs.prefix(10))
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        NavigationStack {
            ZStack {
                ThemedPageBackground(useRenderLayer: true)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 12)
                            .monoPageHeaderCollapse()

                        if let progress = localLibrary.importProgress {
                            LocalImportProgressPanel(progress: progress)
                                .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                                .padding(.top, 18)
                        }

                        if localLibrary.songs.isEmpty {
                            // 空库时不摆一排 0 的数据带，直接给起步引导
                            LocalStarterPanel(onImport: { showImporter = true })
                                .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                                .padding(.top, 24)
                        } else {
                            LocalStatsBand(items: [
                                (value: "\(localLibrary.songCount)", label: localModeText("tabbar_local_music")),
                                (value: "\(favoriteSongs.count)", label: localModeText("local_filter_favorites")),
                                (value: localTotalDurationText(for: localLibrary.songs), label: localModeText("local_stat_duration"))
                            ])
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 22)
                        }

                        if !recentSongs.isEmpty {
                            localSongShelf(
                                title: localModeText("local_home_continue_title"),
                                songs: recentSongs,
                                destination: LocalMusicView(initialFilter: .recent)
                            )
                            .padding(.top, 30)
                        }

                        if !recentlyAddedSongs.isEmpty {
                            localSongShelf(
                                title: localModeText("local_home_recent_added_title"),
                                songs: recentlyAddedSongs,
                                destination: LocalMusicView(initialFilter: .all)
                            )
                            .padding(.top, 30)
                        }

                        quickAccessIndex
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 30)

                        playlistsPreviewSection
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 30)

                        FloatingBarBottomSpacer()
                    }
                    .iPadContentWidth(700)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .localRootNavigation()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            _ = await localLibrary.scanLibrary()
                            refreshRecentSongs()
                        }
                    } label: {
                        MonoIcon(icon: .refresh, size: 16, color: .monoTextPrimary)
                    }

                    Button {
                        showImporter = true
                    } label: {
                        MonoIcon(icon: .download, size: 16, color: .monoTextPrimary)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: LocalMusicLibraryManager.importableContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleMusicImport(result)
        }
        .task {
            guard await MainTabActivationGate.waitUntilSettled(.home) else { return }
            refreshRecentSongs()
            await LocalPlaylistCloudSyncManager.shared.refreshFromCloudIfNeeded()
        }
        .onReceive(playerManager.$currentSong.dropFirst()) { _ in
            guard MainTabActivationGate.isSettled(.home) else { return }
            refreshRecentSongs()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !SignalStyle.isActive {
                LocalEyebrowRow(label: "COLLECTION")
                    .padding(.bottom, 18)
            }

            Text(localModeText("local_home_hero_title"))
                .font(SignalStyle.isActive ? SignalStyle.titleFont(30, weight: .semibold) : .system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.monoTextPrimary)

            if !localLibrary.songs.isEmpty {
                Text(localModeFormat("local_home_hero_subtitle", localLibrary.songCount))
                    .font(SignalStyle.isActive ? SignalStyle.bodyFont(13) : .rounded(size: 13))
                    .foregroundColor(.monoTextSecondary)
                    .lineSpacing(3)
                    .padding(.top, 12)
            }

            HStack(spacing: 10) {
                LocalInkCapsuleButton(
                    title: localModeText("local_home_play_all"),
                    icon: .play,
                    disabled: localLibrary.songs.isEmpty
                ) {
                    playAllLocalSongs()
                }

                LocalHairlineCapsuleButton(
                    title: localModeText("local_action_import_title"),
                    icon: .download
                ) {
                    showImporter = true
                }
            }
            .padding(.top, 20)
        }
    }

    private var quickAccessIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSectionHeader(title: localModeText("local_home_quick_access_title"))
                .padding(.bottom, 6)

            NavigationLink(destination: LocalMusicView(initialFilter: .all)) {
                LocalIndexRow(index: 1, title: localModeText("local_filter_all"), value: "\(localLibrary.songCount)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(
                destination: LocalSystemPlaylistDestinationView(
                    playlistId: localPlaylists.favoritePlaylist?.id,
                    fallbackFilter: .favorites
                )
            ) {
                LocalIndexRow(index: 2, title: localModeText("local_filter_favorites"), value: "\(favoriteSongs.count)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(destination: LocalMusicView(initialFilter: .recent)) {
                LocalIndexRow(index: 3, title: localModeText("local_filter_recent"), value: "\(recentSongs.count)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            if !downloadedSongs.isEmpty {
                LocalIndexHairline()

                NavigationLink(destination: LocalMusicView(initialFilter: .downloads)) {
                    LocalIndexRow(index: 4, title: localModeText("local_downloads_title"), value: "\(downloadedSongs.count)")
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
            }
        }
    }

    @ViewBuilder
    private func localSongShelf<Destination: View>(
        title: String,
        songs: [Song],
        destination: Destination
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: destination) {
                HStack(spacing: 8) {
                    LocalSectionHeader(title: title)
                    MonoIcon(icon: .chevronRight, size: 11, color: .monoTextSecondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(songs.prefix(10), id: \.identityKey) { song in
                        SongCard(song: song) {
                            PlayerManager.shared.play(song: song, in: songs)
                        }
                    }
                }
                .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }

    private var playlistsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSectionHeader(title: localModeText("local_home_playlists_title"))
                .padding(.bottom, 6)

            if customPlaylists.isEmpty {
                Text(localModeText("local_home_playlist_empty_hint"))
                    .font(.rounded(size: 13))
                    .foregroundColor(.monoTextSecondary)
                    .lineSpacing(3)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(customPlaylists.prefix(3).enumerated()), id: \.element.id) { index, playlist in
                    if index > 0 {
                        LocalIndexHairline(leading: 64)
                    }

                    NavigationLink(destination: LocalPlaylistDetailView(playlistId: playlist.id)) {
                        LocalPlaylistIndexRow(summary: localPlaylists.summary(for: playlist))
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
                }

                LocalIndexHairline(leading: 0)

                NavigationLink(destination: LocalLibraryView()) {
                    LocalIndexRow(
                        title: localModeText("local_home_manage_playlists"),
                        value: "\(customPlaylists.count)"
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
            }
        }
    }

    private func playAllLocalSongs() {
        guard let first = localLibrary.songs.first else { return }
        PlayerManager.shared.playReplacingContext(song: first, in: localLibrary.songs)
    }

    private func handleMusicImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task {
                _ = await localLibrary.importItems(from: urls)
                refreshRecentSongs()
            }
        case .failure(let error):
            AlertManager.shared.show(
                title: localModeText("local_import_failed_title"),
                message: error.localizedDescription,
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        }
    }

    private func refreshRecentSongs() {
        recentSongs = recentOfflineSongs(limit: 10, using: downloadManager)
    }
}

// MARK: - 本地音乐

struct LocalMusicView: View {
    @ObservedObject private var localLibrary = LocalMusicLibraryManager.shared
    private let localPlaylists = LocalPlaylistManager.shared
    @ObservedObject private var downloadStatus = DownloadedSongStatusModel.shared
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showImporter = false
    @StateObject private var songList: LocalMusicListSnapshot

    let isRoot: Bool

    init(initialFilter: LocalMusicFilter = .all, isRoot: Bool = false) {
        self.isRoot = isRoot
        _songList = StateObject(wrappedValue: LocalMusicListSnapshot(initialFilter: initialFilter))
    }

    private var visibleFilters: [LocalMusicFilter] {
        LocalMusicFilter.allCases.filter { filter in
            guard filter == .downloads else { return true }
            return songList.selectedFilter == .downloads || downloadStatus.hasDownloads
        }
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        importConfiguredContent
            .task {
                guard await MainTabActivationGate.waitUntilSettled(.podcast) else { return }
                refreshRecentSongs()
            }
            .onReceive(playerManager.$currentSong.dropFirst()) { _ in
                guard MainTabActivationGate.isSettled(.podcast) else { return }
                refreshRecentSongs()
            }
    }

    private var navigationContent: AnyView {
        AnyView(
            LocalPageNavigationContainer(isRoot: isRoot) {
                pageContent
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .searchable(text: $songList.searchText, prompt: localModeText("local_music_search_prompt"))
                    .toolbar {
                        toolbarContent
                    }
            }
        )
    }

    private var pageContent: AnyView {
        AnyView(
            ZStack {
                ThemedPageBackground(useRenderLayer: true)
                    .ignoresSafeArea()

                musicContent
            }
        )
    }

    private var musicContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                    .padding(.top, 12)

                filterBar
                    .padding(.top, 18)

                if let progress = localLibrary.importProgress {
                    LocalImportProgressPanel(progress: progress)
                        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                        .padding(.top, 14)
                }

                songCollection
            }
        )
    }

    private var songCollection: AnyView {
        if songList.filteredSongs.isEmpty {
            return AnyView(
                ScrollView {
                    Group {
                        if localLibrary.songs.isEmpty && songList.selectedFilter == .all
                            && songList.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // 空库：给完整的起步引导，而不是一句话孤零零挂着
                            LocalStarterPanel(onImport: { showImporter = true })
                        } else {
                            LocalEmptyStateView(
                                title: emptyTitle,
                                subtitle: emptySubtitle
                            )
                        }
                    }
                    .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                    .padding(.top, 26)
                }
                .scrollIndicators(.hidden)
            )
        }

        return AnyView(
            List {
                ForEach(Array(songList.filteredSongs.enumerated()), id: \.element.identityKey) { index, song in
                    SongListRow(
                        song: song,
                        index: index,
                        onTap: {
                            playerManager.play(song: song, in: songList.filteredSongs)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteLocalEntry(song)
                        } label: {
                            Label(localModeText("local_action_delete_local_song"), systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteLocalEntry(song)
                        } label: {
                            Label(localModeText("local_action_delete_local_song"), systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Color.clear
                    .frame(height: 110)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        )
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            sortMenu
            importButton
        }
    }

    private var sortMenu: AnyView {
        AnyView(
            Menu {
                ForEach(LocalMusicSort.allCases) { mode in
                    Button {
                        songList.sortMode = mode
                    } label: {
                        if songList.sortMode == mode {
                            Label(localModeText(mode.titleKey), systemImage: "checkmark")
                        } else {
                            Text(localModeText(mode.titleKey))
                        }
                    }
                }
            } label: {
                MonoIcon(icon: .filter, size: 16, color: .monoTextPrimary)
            }
        )
    }

    private var importButton: AnyView {
        AnyView(
            Button {
                showImporter = true
            } label: {
                MonoIcon(icon: .download, size: 16, color: .monoTextPrimary)
            }
        )
    }

    private var importConfiguredContent: AnyView {
        AnyView(
            navigationContent
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: LocalMusicLibraryManager.importableContentTypes,
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard !urls.isEmpty else { return }
                        Task {
                            _ = await localLibrary.importItems(from: urls)
                            refreshRecentSongs()
                        }
                    case .failure(let error):
                        AlertManager.shared.show(
                            title: localModeText("local_import_failed_title"),
                            message: error.localizedDescription,
                            primaryButtonTitle: localModeText("common_ok"),
                            primaryAction: {}
                        )
                    }
                }
        )
    }

    /// 删除本地条目：导入的本地文件走曲库删除，下载的歌曲连记录带文件一起删
    private func deleteLocalEntry(_ song: Song) {
        if song.isLocal {
            localLibrary.deleteSong(song)
        } else {
            localPlaylists.removeDownloadedSong(song)
        }
        refreshRecentSongs()
    }

    @ViewBuilder
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !SignalStyle.isActive {
                LocalEyebrowRow(label: "TRACKS")
                    .padding(.bottom, 16)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(localModeText("tabbar_local_music"))
                    .font(SignalStyle.isActive ? SignalStyle.titleFont(28, weight: .semibold) : .system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.monoTextPrimary)

                Text("\(songList.filteredSongs.count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.monoAccent)
                    .monospacedDigit()

                Spacer(minLength: 0)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                ForEach(visibleFilters) { filter in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            songList.selectedFilter = filter
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(localModeText(filter.titleKey))
                                .font(.rounded(size: 14, weight: songList.selectedFilter == filter ? .bold : .semibold))
                                .foregroundColor(songList.selectedFilter == filter ? .monoTextPrimary : .monoTextSecondary.opacity(0.72))

                            Capsule()
                                .fill(songList.selectedFilter == filter ? Color.monoAccent : Color.clear)
                                .frame(width: 18, height: 2.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)

            Rectangle()
                .fill(Color.monoSeparator.opacity(0.5))
                .frame(height: 0.5)
        }
    }

    private var emptyTitle: String {
        if !songList.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localModeText("local_empty_search_title")
        }
        if songList.selectedFilter == .all {
            return localModeText("local_empty_music_title")
        }
        return localModeText("local_empty_collection_title")
    }

    private var emptySubtitle: String {
        if !songList.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localModeText("local_empty_search_subtitle")
        }
        if songList.selectedFilter == .all {
            return localModeText("local_empty_music_subtitle")
        }
        return localModeText("local_empty_collection_subtitle")
    }

    private func refreshRecentSongs() {
        songList.refreshRecentSongs()
    }
}

// MARK: - 资料库

struct LocalLibraryView: View {
    var isRoot = false
    @ObservedObject private var localLibrary = LocalMusicLibraryManager.shared
    @ObservedObject private var localPlaylists = LocalPlaylistManager.shared
    private let downloadManager = DownloadManager.shared
    @ObservedObject private var downloadStatus = DownloadedSongStatusModel.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showFileImporter = false
    @State private var showMusicImporter = false
    @State private var recentSongs: [Song] = []

    private var customPlaylists: [LocalPlaylist] {
        localPlaylists.playlists.filter { !$0.isSystem }
    }

    private var favoriteSongs: [Song] {
        guard let playlist = localPlaylists.favoritePlaylist else { return [] }
        return offlinePlayableSongs(from: localPlaylists.songs(for: playlist), using: downloadManager)
    }

    private var downloadedSongs: [Song] {
        offlinePlayableSongs(from: downloadManager.fetchDownloadPlaylistSongs(), using: downloadManager)
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        LocalPageNavigationContainer(isRoot: isRoot) {
            ZStack {
                ThemedPageBackground(useRenderLayer: true)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 12)
                            .monoPageHeaderCollapse()

                        if let progress = localLibrary.importProgress {
                            LocalImportProgressPanel(progress: progress)
                                .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                                .padding(.top, 18)
                        }

                        LocalStatsBand(items: [
                            (value: "\(localLibrary.songCount)", label: localModeText("tabbar_local_music")),
                            (value: "\(favoriteSongs.count)", label: localModeText("local_filter_favorites")),
                            (value: "\(customPlaylists.count)", label: localModeText("profile_local_playlists"))
                        ])
                        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                        .padding(.top, 22)

                        systemCollectionsIndex
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 30)

                        customPlaylistsSection
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 30)

                        FloatingBarBottomSpacer()
                    }
                    .iPadContentWidth(700)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
                .refreshable {
                    refreshRecentSongs()
                    _ = try? await LocalPlaylistCloudSyncManager.shared.refreshAndSync()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showMusicImporter = true
                    } label: {
                        if localLibrary.isProcessing {
                            ProgressView()
                                .scaleEffect(0.72)
                        } else {
                            MonoIcon(icon: .download, size: 16, color: .monoTextPrimary)
                        }
                    }
                    .disabled(localLibrary.isProcessing)
                }
            }
        }
        .fileImporter(
            isPresented: $showMusicImporter,
            allowedContentTypes: LocalMusicLibraryManager.importableContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleMusicImport(result)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePlaylistImport(result)
        }
        .task {
            guard await MainTabActivationGate.waitUntilSettled(.library) else { return }
            refreshRecentSongs()
            await LocalPlaylistCloudSyncManager.shared.refreshFromCloudIfNeeded()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !SignalStyle.isActive {
                LocalEyebrowRow(label: "SHELF")
                    .padding(.bottom, 16)
            }

            Text(localModeText("local_library_navigation_title"))
                .font(SignalStyle.isActive ? SignalStyle.titleFont(28, weight: .semibold) : .system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.monoTextPrimary)

            HStack(spacing: 10) {
                LocalInkCapsuleButton(
                    title: localModeText("lib_create_playlist"),
                    icon: .add
                ) {
                    createPlaylist()
                }

                LocalHairlineCapsuleButton(
                    title: localModeText("lib_import_playlist"),
                    icon: .arrowDownToLine
                ) {
                    showFileImporter = true
                }
            }
            .padding(.top, 18)
        }
    }

    private var systemCollectionsIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSectionHeader(title: localModeText("local_library_system_title"))
                .padding(.bottom, 6)

            NavigationLink(destination: LocalMusicView(initialFilter: .all)) {
                LocalIndexRow(index: 1, title: localModeText("local_filter_all"), value: "\(localLibrary.songCount)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(
                destination: LocalSystemPlaylistDestinationView(
                    playlistId: localPlaylists.favoritePlaylist?.id,
                    fallbackFilter: .favorites
                )
            ) {
                LocalIndexRow(index: 2, title: localModeText("local_filter_favorites"), value: "\(favoriteSongs.count)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(destination: LocalMusicView(initialFilter: .recent)) {
                LocalIndexRow(index: 3, title: localModeText("local_filter_recent"), value: "\(recentSongs.count)")
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            if !downloadedSongs.isEmpty {
                LocalIndexHairline()

                NavigationLink(destination: LocalMusicView(initialFilter: .downloads)) {
                    LocalIndexRow(index: 4, title: localModeText("local_downloads_title"), value: "\(downloadedSongs.count)")
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
            }
        }
    }

    private var customPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSectionHeader(title: localModeText("local_library_custom_title"))
                .padding(.bottom, 6)

            if customPlaylists.isEmpty {
                LocalEmptyStateView(
                    title: localModeText("local_empty_playlist_title"),
                    subtitle: localModeText("local_empty_playlist_subtitle"),
                    buttonTitle: localModeText("lib_create_playlist"),
                    buttonAction: createPlaylist
                )
                .padding(.top, 12)
            } else {
                ForEach(Array(customPlaylists.enumerated()), id: \.element.id) { index, playlist in
                    if index > 0 {
                        LocalIndexHairline(leading: 64)
                    }

                    NavigationLink(destination: LocalPlaylistDetailView(playlistId: playlist.id)) {
                        LocalPlaylistIndexRow(summary: localPlaylists.summary(for: playlist))
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
                    .contextMenu {
                        Button {
                            renamePlaylist(playlist)
                        } label: {
                            Label {
                                Text(localModeText("local_playlist_rename"))
                            } icon: {
                                MonoSemanticIcon(semantic: .rename, fallback: .save)
                            }
                        }

                        Button(role: .destructive) {
                            deletePlaylist(playlist)
                        } label: {
                            Label(localModeText("local_playlist_delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func createPlaylist() {
        AlertManager.shared.showInput(
            title: localModeText("lib_create_playlist"),
            message: "",
            placeholder: localModeText("local_playlist_name"),
            primaryButtonTitle: localModeText("lib_confirm"),
            secondaryButtonTitle: localModeText("alert_cancel"),
            onConfirm: { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                localPlaylists.createPlaylist(name: trimmed)
            }
        )
    }

    private func renamePlaylist(_ playlist: LocalPlaylist) {
        AlertManager.shared.showInput(
            title: localModeText("local_playlist_rename"),
            message: "",
            placeholder: localModeText("local_playlist_name"),
            primaryButtonTitle: localModeText("lib_confirm"),
            secondaryButtonTitle: localModeText("alert_cancel"),
            onConfirm: { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                localPlaylists.renamePlaylist(playlist, name: trimmed)
            }
        )
        AlertManager.shared.inputText = playlist.name
    }

    private func deletePlaylist(_ playlist: LocalPlaylist) {
        AlertManager.shared.show(
            title: localModeText("local_playlist_delete"),
            message: localModeFormat("local_playlist_delete_confirm", playlist.name),
            primaryButtonTitle: localModeText("local_playlist_delete"),
            secondaryButtonTitle: localModeText("alert_cancel"),
            primaryAction: {
                localPlaylists.deletePlaylist(playlist)
            }
        )
    }

    private func handleMusicImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task {
                _ = await localLibrary.importItems(from: urls)
                refreshRecentSongs()
            }
        case .failure(let error):
            AlertManager.shared.show(
                title: localModeText("local_import_failed_title"),
                message: error.localizedDescription,
                primaryButtonTitle: localModeText("lib_confirm"),
                primaryAction: {}
            )
        }
    }

    private func handlePlaylistImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importPlaylistFromFile(url: url)
        case .failure(let error):
            AlertManager.shared.show(
                title: localModeText("lib_import_failed"),
                message: error.localizedDescription,
                primaryButtonTitle: localModeText("lib_confirm"),
                primaryAction: {}
            )
        }
    }

    private func importPlaylistFromFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let parsed = try LocalPlaylistManager.parseExportFile(url: url)
            let localSongMap = Dictionary(uniqueKeysWithValues: localLibrary.songs.map { ($0.id, $0) })
            let matchedSongs = parsed.songIds.compactMap { localSongMap[$0] }

            guard !matchedSongs.isEmpty else {
                AlertManager.shared.show(
                    title: localModeText("lib_import_failed"),
                    message: localModeText("local_library_import_no_local_match"),
                    primaryButtonTitle: localModeText("lib_confirm"),
                    primaryAction: {}
                )
                return
            }

            localPlaylists.importPlaylist(name: parsed.name, songs: matchedSongs)

            AlertManager.shared.show(
                title: localModeText("local_import_complete_title"),
                message: localModeFormat("local_library_import_success", parsed.name, matchedSongs.count),
                primaryButtonTitle: localModeText("lib_confirm"),
                primaryAction: {}
            )
        } catch {
            AlertManager.shared.show(
                title: localModeText("lib_import_failed"),
                message: error.localizedDescription,
                primaryButtonTitle: localModeText("lib_confirm"),
                primaryAction: {}
            )
        }
    }

    private func refreshRecentSongs() {
        recentSongs = recentOfflineSongs(limit: 20, using: downloadManager)
    }
}

// MARK: - 我的

struct LocalModeProfileView: View {
    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @ObservedObject private var localLibrary = LocalMusicLibraryManager.shared
    @ObservedObject private var localPlaylists = LocalPlaylistManager.shared
    private let downloadManager = DownloadManager.shared
    @ObservedObject private var downloadStatus = DownloadedSongStatusModel.shared
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var tokenInput = SecureConfig.apiToken ?? ""
    @State private var isSubmitting = false
    @State private var isShowingTokenAgreement = false
    @State private var recentSongs: [Song] = []
    @State private var navigationPath = NavigationPath()

    private var customPlaylistCount: Int {
        localPlaylists.playlists.filter { !$0.isSystem }.count
    }

    private var favoriteSongs: [Song] {
        guard let playlist = localPlaylists.favoritePlaylist else { return [] }
        return offlinePlayableSongs(from: localPlaylists.songs(for: playlist), using: downloadManager)
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        NavigationStack(path: $navigationPath) {
            ZStack {
                ThemedPageBackground(useRenderLayer: true)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 12)
                            .monoPageHeaderCollapse()

                        LocalStatsBand(items: [
                            (value: "\(localLibrary.songCount)", label: localModeText("tabbar_local_music")),
                            (value: "\(customPlaylistCount)", label: localModeText("profile_local_playlists")),
                            (value: "\(favoriteSongs.count)", label: localModeText("local_filter_favorites"))
                        ])
                        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                        .padding(.top, 22)

                        if !recentSongs.isEmpty {
                            recentPlaysShelf
                                .padding(.top, 30)
                        }

                        menuIndex
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 30)

                        activationSection
                            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                            .padding(.top, 38)

                        FloatingBarBottomSpacer()
                    }
                    .iPadContentWidth(700)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .localRootNavigation()
            .toolbar {
                if settings.globalThemeId == .default {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: ProfileNavigationDestination.settings) {
                            DefaultHeaderActionLabel(icon: .settings, title: localModeText("settings_title"))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationDestination(for: ProfileNavigationDestination.self) { destination in
                switch destination {
                case .settings:
                    SettingsView()
                case .platformAccounts:
                    PlatformAccountManagementView()
                case .loginNCM:
                    PlatformLoginView(initialPlatform: .ncm)
                }
            }
        }
        .task {
            guard await MainTabActivationGate.waitUntilSettled(.profile) else { return }
            tokenInput = SecureConfig.apiToken ?? tokenInput
            refreshRecentSongs()
        }
        .onReceive(playerManager.$currentSong.dropFirst()) { _ in
            guard MainTabActivationGate.isSettled(.profile) else { return }
            refreshRecentSongs()
        }
        .monoSheet(isPresented: $isShowingTokenAgreement, onDismiss: {
            onlineAccess.declinePendingTokenAuthorization()
        }, preset: .standard) {
            TokenAgreementAuthorizationSheet(
                onAgree: acceptPendingTokenAuthorization,
                onDecline: declinePendingTokenAuthorization
            )
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.globalThemeId != .default && !SignalStyle.isActive {
                LocalEyebrowRow(label: "PROFILE")
                    .padding(.bottom, 18)
            }

            Text(String(localized: LocalizedStringResource(stringLiteral: MonoTimeGreeting.localizedKey)))
                .font(.rounded(size: 12.5, weight: .semibold))
                .foregroundColor(.monoTextSecondary.opacity(0.85))

            Text(localModeText("local_profile_hero_title"))
                .font(SignalStyle.isActive ? SignalStyle.titleFont(32, weight: .semibold) : .system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.monoTextPrimary)
                .padding(.top, 5)
        }
    }

    private var recentPlaysShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LocalSectionHeader(title: localModeText("profile_recently_played"))

                Spacer(minLength: 0)

                NavigationLink(destination: RecentPlayHistoryView()) {
                    HStack(spacing: 4) {
                        Text(localModeText("view_all"))
                            .font(.rounded(size: 12.5, weight: .semibold))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))

                        MonoIcon(icon: .chevronRight, size: 10, color: .monoTextSecondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(recentSongs.prefix(10), id: \.identityKey) { song in
                        SongCard(song: song) {
                            playerManager.play(song: song, in: recentSongs)
                        }
                    }
                }
                .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }

    private var menuIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalSectionHeader(title: localModeText("local_profile_manage_title"))
                .padding(.bottom, 6)

            NavigationLink(destination: LocalLibraryView()) {
                LocalIndexRow(
                    index: 1,
                    title: localModeText("local_library_navigation_title"),
                    value: "\(customPlaylistCount)"
                )
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(destination: ListeningStatsView()) {
                LocalIndexRow(index: 2, title: localModeText("听歌统计"))
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(destination: StorageManageView()) {
                LocalIndexRow(index: 3, title: localModeText("settings_storage_manage"))
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))

            LocalIndexHairline()

            NavigationLink(value: ProfileNavigationDestination.settings) {
                LocalIndexRow(index: 4, title: localModeText("settings_title"))
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
        }
    }

    /// Token 入口刻意保持低调：发丝线框内的一段小字与下划线输入，不做视觉重心
    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.monoSeparator.opacity(0.5))
                .frame(height: 0.5)
                .padding(.bottom, 16)

            Text(localModeText("access_unlock_title"))
                .font(.rounded(size: 13, weight: .semibold))
                .foregroundColor(.monoTextSecondary.opacity(0.85))

            HStack(spacing: 10) {
                TextField(localModeText("access_token_input_placeholder"), text: $tokenInput)
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.monoTextPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monoTextInputBehavior()
                    .submitLabel(.done)
                    .monoOnSubmit(text: $tokenInput) { _ in
                        submitToken()
                    }

                Button {
                    MonoTextInputCommitter.commit(text: $tokenInput) { _ in
                        submitToken()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting || onlineAccess.isVerifying {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        Text(localModeText("access_unlock_button"))
                            .font(.rounded(size: 12, weight: .semibold))
                            .foregroundColor(.monoTextSecondary.opacity(0.9))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .overlay(
                        Capsule().stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.8)
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                .disabled(isSubmitting || tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 12)

            Rectangle()
                .fill(Color.monoSeparator.opacity(0.7))
                .frame(height: 0.5)
                .padding(.top, 9)
        }
    }

    private func submitToken() {
        let value = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        isSubmitting = true
        Task {
            let outcome = await onlineAccess.submitToken(value)
            await MainActor.run {
                isSubmitting = false
                switch outcome {
                case .agreementRequired:
                    isShowingTokenAgreement = true
                case .status(let status):
                    handleTokenSubmissionStatus(status)
                }
            }
        }
    }

    private func acceptPendingTokenAuthorization() {
        guard let status = onlineAccess.acceptPendingTokenAuthorization() else { return }
        isShowingTokenAgreement = false
        handleTokenSubmissionStatus(status)
    }

    private func declinePendingTokenAuthorization() {
        onlineAccess.declinePendingTokenAuthorization()
        isShowingTokenAgreement = false
    }

    private func handleTokenSubmissionStatus(_ status: APIService.TokenStatus) {
        switch status {
        case .valid(let name):
            AlertManager.shared.show(
                title: localModeText("access_enabled_title"),
                message: name.isEmpty ? localModeText("access_enabled_message") : localModeFormat("access_enabled_message_name", name),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        case .validationDisabled:
            AlertManager.shared.show(
                title: localModeText("access_validation_bypassed_title"),
                message: localModeText("access_validation_bypassed_message"),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        case .invalid, .missing:
            AlertManager.shared.show(
                title: localModeText("access_invalid_title"),
                message: localModeText("access_invalid_message"),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        case .expired:
            AlertManager.shared.show(
                title: String(localized: "Token 已过期"),
                message: String(localized: "您输入的 Token 已经过期，请获取新的 Token 或者重新授权。"),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        case .deviceMismatch:
            AlertManager.shared.show(
                title: String(localized: "设备不匹配"),
                message: String(localized: "此 Token 已绑定到其他设备，无法在当前设备使用。"),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        case .networkError:
            AlertManager.shared.show(
                title: localModeText("access_network_error_title"),
                message: localModeText("access_network_error_message"),
                primaryButtonTitle: localModeText("common_ok"),
                primaryAction: {}
            )
        }
    }

    private func refreshRecentSongs() {
        recentSongs = recentOfflineSongs(limit: 12, using: downloadManager)
    }
}

// MARK: - 编辑部组件

/// 眉题行：强调色胶囊 + 追踪字距标签 + 发丝线
private struct LocalEyebrowRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.monoAccent)
                .frame(width: 18, height: 3)

            Text(label)
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundColor(.monoTextSecondary.opacity(0.72))
                .fixedSize()

            Rectangle()
                .fill(Color.monoSeparator.opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

/// 小节标题：短竖线 + 粗体
private struct LocalSectionHeader: View {
    let title: String

    var body: some View {
        Group {
            if SignalStyle.isActive {
                Text(title)
                    .font(SignalStyle.titleFont(17, weight: .semibold))
                    .foregroundColor(SignalStyle.ink)
            } else {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.monoAccent)
                        .frame(width: 3, height: 13)

                    Text(title)
                        .font(.rounded(size: 15, weight: .bold))
                        .foregroundColor(.monoTextPrimary)
                }
            }
        }
    }
}

/// 数据带：上下发丝线之间的裸排大数字
private struct LocalStatsBand: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.monoTextPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(SignalStyle.isActive ? SignalStyle.inkMuted : Color.monoAccent)
                            .frame(width: 4, height: 4)

                        Text(item.label)
                            .font(.rounded(size: 10.5, weight: .semibold))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.monoSeparator.opacity(0.55)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.monoSeparator.opacity(0.55)).frame(height: 0.5)
        }
    }
}

/// 索引行：编号 + 标题 + 尾注 + 箭头
private struct LocalIndexRow: View {
    var index: Int? = nil
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let index {
                Text(String(format: "%02d", index))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.monoTextSecondary.opacity(0.45))
                    .monospacedDigit()
            }

            Text(title)
                .font(.rounded(size: 15.5, weight: .semibold))
                .foregroundColor(.monoTextPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let value {
                Text(value)
                    .font(.rounded(size: 12.5))
                    .foregroundColor(.monoTextSecondary.opacity(0.85))
                    .monospacedDigit()
            }

            MonoIcon(icon: .chevronRight, size: 12, color: .monoTextSecondary.opacity(0.4))
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

private struct LocalIndexHairline: View {
    var leading: CGFloat = 32

    var body: some View {
        Rectangle()
            .fill(Color.monoSeparator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

/// 歌单行：发丝描边封面 + 名称 + 曲目数
private struct LocalPlaylistIndexRow: View {
    let summary: LocalPlaylistSummary

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let url = summary.displayCoverUrl {
                    CachedAsyncImage(url: url.sized(200)) {
                        coverPlaceholder
                    }
                    .aspectRatio(contentMode: .fill)
                } else {
                    coverPlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.monoTextPrimary.opacity(0.1), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name)
                    .font(.rounded(size: 15, weight: .semibold))
                    .foregroundColor(.monoTextPrimary)
                    .lineLimit(1)

                Text(localModeFormat("local_playlist_track_count", summary.trackCount))
                    .font(.rounded(size: 12))
                    .foregroundColor(.monoTextSecondary.opacity(0.85))
            }

            Spacer(minLength: 0)

            MonoIcon(icon: .chevronRight, size: 12, color: .monoTextSecondary.opacity(0.4))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    private var coverPlaceholder: some View {
        LocalPlaylistPlaceholderArtwork()
    }
}

/// 墨色主按钮
private struct LocalInkCapsuleButton: View {
    let title: String
    var icon: MonoIcon.IconType? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    MonoIcon(icon: icon, size: 13, color: .monoIconForeground)
                }

                Text(title)
                    .font(.rounded(size: 14, weight: .bold))
                    .foregroundColor(.monoIconForeground)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.monoIconBackground))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }
}

/// 发丝描边次按钮
private struct LocalHairlineCapsuleButton: View {
    let title: String
    var icon: MonoIcon.IconType? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    MonoIcon(icon: icon, size: 13, color: .monoTextPrimary.opacity(0.85))
                }

                Text(title)
                    .font(.rounded(size: 14, weight: .semibold))
                    .foregroundColor(.monoTextPrimary.opacity(0.85))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .overlay(
                Capsule().stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
    }
}

/// 空状态：左对齐的编辑部排版
private struct LocalEmptyStateView: View {
    let title: String
    let subtitle: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.monoTextPrimary)

            Text(subtitle)
                .font(SignalStyle.isActive ? SignalStyle.bodyFont(13) : .rounded(size: 13))
                .foregroundColor(.monoTextSecondary)
                .lineSpacing(3)
                .padding(.top, 12)

            if let buttonTitle, let buttonAction {
                LocalInkCapsuleButton(title: buttonTitle, action: buttonAction)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.monoSeparator.opacity(0.55)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.monoSeparator.opacity(0.55)).frame(height: 0.5)
        }
    }
}

/// 起步引导面板：资料库为空时的主指引 —— 虚线卡片 + 步骤索引 + 支持格式
private struct LocalStarterPanel: View {
    let onImport: () -> Void

    private static let formats = ["MP3", "FLAC", "WAV", "M4A", "AAC", "OGG"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.monoAccent.opacity(0.12))

                    MonoIcon(icon: .download, size: 17, color: .monoAccent, lineWidth: 1.8)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localModeText("local_starter_title"))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.monoTextPrimary)

                    Text(localModeText("local_starter_subtitle"))
                        .font(.rounded(size: 12))
                        .foregroundColor(.monoTextSecondary.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                starterStep(1, text: localModeText("local_starter_step1"))
                LocalIndexHairline(leading: 30)
                starterStep(2, text: localModeText("local_starter_step2"))
                LocalIndexHairline(leading: 30)
                starterStep(3, text: localModeText("local_starter_step3"))
            }
            .padding(.top, 12)

            LocalInkCapsuleButton(
                title: localModeText("local_action_import_title"),
                icon: .download,
                action: onImport
            )
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(localModeText("local_starter_formats_label"))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.monoTextSecondary.opacity(0.6))

                HStack(spacing: 6) {
                    ForEach(Self.formats, id: \.self) { format in
                        Text(format)
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .tracking(0.4)
                            .foregroundColor(.monoTextSecondary.opacity(0.78))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(
                                Capsule().stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.7)
                            )
                    }
                }
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if SignalStyle.isActive {
                SignalSurfaceBackground(cornerRadius: 16, elevated: false, fill: SignalStyle.surface)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.monoGlassTint.opacity(0.55))
            }
        }
        .overlay {
            if !SignalStyle.isActive {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.monoSeparator.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                    )
            }
        }
    }

    private func starterStep(_ number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", number))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(SignalStyle.isActive ? SignalStyle.inkMuted : Color.monoAccent)
                .monospacedDigit()

            Text(text)
                .font(.rounded(size: 13))
                .foregroundColor(.monoTextSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }
}

private extension View {
    func localRootNavigation() -> some View {
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private struct LocalPageNavigationContainer<Content: View>: View {
    let isRoot: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isRoot {
            NavigationStack {
                content().localRootNavigation()
            }
        } else {
            content().monoNavigationBackButton()
        }
    }
}


/// Recomputes the local list when its data or filter changes, independently of view rendering.
@MainActor
private final class LocalMusicListSnapshot: ObservableObject {
    @Published var selectedFilter: LocalMusicFilter {
        didSet { if selectedFilter != oldValue { refreshSource() } }
    }
    @Published var sortMode: LocalMusicSort = .newest {
        didSet { if sortMode != oldValue { refreshSource() } }
    }
    @Published var searchText = "" {
        didSet { if searchText != oldValue { applySearch() } }
    }
    @Published private(set) var filteredSongs: [Song] = []

    private let localLibrary = LocalMusicLibraryManager.shared
    private let localPlaylists = LocalPlaylistManager.shared
    private let downloadManager = DownloadManager.shared
    private var recentSongs: [Song] = []
    private var cachedSortedSongs: [Song] = []
    private var subscription: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    init(initialFilter: LocalMusicFilter) {
        selectedFilter = initialFilter
        refreshSource()
        subscription = Publishers.MergeMany(
            localLibrary.$songs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            localPlaylists.$playlists.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            downloadManager.$downloadedSongIds.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
                .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in self?.scheduleRefresh() }
    }

    deinit { refreshTask?.cancel() }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        // Read the settled values after @Published willSet notifications coalesce.
        refreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.refreshSource()
            self.refreshTask = nil
        }
    }

    func refreshRecentSongs() {
        recentSongs = recentOfflineSongs(limit: 40, using: downloadManager)
        if selectedFilter == .recent { refreshSource() }
    }

    private func refreshSource() {
        cachedSortedSongs = sortedSongs
        applySearch()
    }

    private func applySearch() {
        filteredSongs = matchingSongs
    }

    private var sourceSongs: [Song] {
        switch selectedFilter {
        case .all:
            return localLibrary.songs
        case .favorites:
            guard let playlist = localPlaylists.favoritePlaylist else { return [] }
            return offlinePlayableSongs(from: localPlaylists.songs(for: playlist), using: downloadManager)
        case .downloads:
            return offlinePlayableSongs(from: downloadManager.fetchDownloadPlaylistSongs(), using: downloadManager)
        case .recent:
            return recentSongs
        }
    }

    private var sortedSongs: [Song] {
        switch sortMode {
        case .newest:
            if selectedFilter == .recent {
                return sourceSongs
            }
            return sourceSongs.sorted { lhs, rhs in
                let lhsDate = lhs.localImportedAt ?? .distantPast
                let rhsDate = rhs.localImportedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .title:
            return sourceSongs.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .artist:
            return sourceSongs.sorted {
                if $0.artistName != $1.artistName {
                    return $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var matchingSongs: [Song] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return cachedSortedSongs }

        return cachedSortedSongs.filter { song in
            song.name.localizedCaseInsensitiveContains(keyword)
                || song.artistName.localizedCaseInsensitiveContains(keyword)
                || (song.album?.name.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }
}
