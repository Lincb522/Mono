import Combine
import QQMusicKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Neumorphic Library Redesign

struct LibraryCollapsingHeader<Content: View>: View {
    @Binding var progress: CGFloat
    let collapseDistance: CGFloat
    let content: Content

    init(progress: Binding<CGFloat>, collapseDistance: CGFloat, @ViewBuilder content: () -> Content) {
        self._progress = progress
        self.collapseDistance = collapseDistance
        self.content = content()
    }

    private var visibleHeight: CGFloat? {
        progress <= 0.001 ? nil : max(0, collapseDistance * (1 - progress))
    }

    var body: some View {
        content
            .offset(y: -collapseDistance * progress)
            .opacity(1 - progress * 0.2)
            .frame(height: visibleHeight, alignment: .top)
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: progress)
    }
}

// MARK: - Neumorphic Library Workspace

struct NeumorphicLibraryWorkspace: View {
    private enum Shelf: CaseIterable, Hashable {
        case localPlaylists
        case ncmPlaylists
        case qcmPlaylists
        case kcmPlaylists
        case appleMusic
        case localPodcasts
        case ncmPodcasts

        var title: String {
            switch self {
            case .localPlaylists: return String(localized: "lib_local_playlists")
            case .ncmPlaylists: return String(localized: "lib_netease_playlists")
            case .qcmPlaylists: return String(localized: "QCM歌单")
            case .kcmPlaylists: return "KCM 歌单"
            case .appleMusic: return String(localized: "apple_music_library")
            case .localPodcasts: return String(localized: "本地播客")
            case .ncmPodcasts: return String(localized: "NCM 播客")
            }
        }

        var icon: MonoIcon.IconType {
            switch self {
            case .localPlaylists: return .musicNoteList
            case .ncmPlaylists, .qcmPlaylists, .kcmPlaylists: return .list
            case .appleMusic: return .musicNote
            case .localPodcasts, .ncmPodcasts: return .radio
            }
        }
    }

    private enum ArtistSearchField: Hashable {
        case ncm
        case qq
        case kugou
        case appleMusic
    }

    @ObservedObject var viewModel: LibraryViewModel
    @Binding var tabIndex: Int
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var loginIdentity = LoginIdentityManager.shared
    @ObservedObject private var localManager = LocalPlaylistManager.shared
    @ObservedObject private var subManager = SubscriptionManager.shared
    @ObservedObject private var qqSession = QQUserSession.shared

    @State private var selectedShelf: Shelf = .localPlaylists
    @State private var showLibraryTools = false
    @State private var showFileImporter = false
    @State private var showQQImport = false
    @State private var isImporting = false
    @State private var qqUserPlaylists: [Playlist] = []
    @State private var isLoadingQQUserPlaylists = false
    @State private var hasLoadedQQUserPlaylists = false
    @State private var qqPlaylistRequest = LibraryRequestScope()
    @State private var showArtistFilters = false
    @State private var showQQArtistFilters = false
    @State private var showKugouArtistFilters = false
    @State private var showAppleMusicArtistFilters = false
    @FocusState private var focusedArtistSearchField: ArtistSearchField?
    @Namespace private var tabNamespace

    private let tabs = LibraryViewModel.LibraryTab.allCases
    private let controlColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let artistColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: DeviceLayout.artistGridColumns)

    private var playlistColumns: [GridItem] {
        if DeviceLayout.usesExpandedLayout {
            return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var deckOuterPadding: CGFloat {
        DeviceLayout.usesExpandedLayout ? DeviceLayout.libraryHorizontalPadding : 10
    }

    private var selectedTab: LibraryViewModel.LibraryTab {
        tabs[min(max(tabIndex, 0), tabs.count - 1)]
    }

    var body: some View {
        let _ = settings.globalThemeRevision
        ZStack {
            ThemedPageBackground(useRenderLayer: true)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    headerConsole
                        .monoPageHeaderCollapse()
                    pageContent
                }
                .padding(.bottom, 128)
                .iPadContentWidth(1100)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
        .task {
            guard await MainTabActivationGate.waitUntilSettled(.library) else { return }
            selectActiveIdentityLibrary()
            syncTabFromViewModel()
            loadCurrentTab()
            if subManager.subscribedRadios.isEmpty {
                subManager.fetchSubscribedRadios()
            }
        }
        .onChange(of: viewModel.currentTab) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
            syncTabFromViewModel()
        }
        .onChange(of: tabIndex) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
            if viewModel.currentTab != selectedTab {
                viewModel.currentTab = selectedTab
            }
            loadCurrentTab()
        }
        .onDisappear {
            qqPlaylistRequest.cancel()
            isLoadingQQUserPlaylists = false
        }
        .onChange(of: qqSession.sessionRevision) { _, _ in
            qqPlaylistRequest.cancel()
            qqUserPlaylists = []
            hasLoadedQQUserPlaylists = false
            isLoadingQQUserPlaylists = false
            guard MainTabActivationGate.isSettled(.library) else { return }
            if qqSession.isLoggedIn {
                loadQQUserPlaylistsIfNeeded(force: true)
            }
        }
        .onChange(of: loginIdentity.activeSource) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
            selectActiveIdentityLibrary()
            if selectedTab == .my {
                loadCurrentTab()
            }
        }
        .monoSheet(isPresented: $showQQImport, preset: .large) {
            QQPlaylistImportView()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                importPlaylistFromFile(url: url)
            case let .failure(error):
                AlertManager.shared.show(
                    title: String(localized: "lib_import_failed"),
                    message: error.localizedDescription,
                    primaryButtonTitle: String(localized: "lib_confirm"),
                    primaryAction: {}
                )
            }
        }
    }

    private func selectActiveIdentityLibrary() {
        switch loginIdentity.activeSource {
        case .netease: selectedShelf = .ncmPlaylists
        case .qqmusic: selectedShelf = .qcmPlaylists
        case .kugou: selectedShelf = .kcmPlaylists
        case .qishui, .appleMusic, .local, nil: selectedShelf = .localPlaylists
        }
    }

    private var headerConsole: some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryTopBar
            libraryTabRail
        }
        .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
        .padding(.top, DeviceLayout.headerTopPadding + 8)
    }

    private var libraryTopBar: some View {
        HStack(spacing: 13) {
            NeumorphicIconBadge(icon: .libraryFilled, tint: activeTint, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("LIBRARY")
                    .font(NeumorphicStyle.labelFont(10, weight: .semibold))
                    .foregroundStyle(NeumorphicStyle.inkMuted)

                Text(String(localized: "tabbar_library"))
                    .font(NeumorphicStyle.titleFont(23, weight: .semibold))
                    .foregroundStyle(NeumorphicStyle.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
    }

    private var libraryTabRail: some View {
        HStack(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                libraryRailButton(tab: tab, index: index)
            }
        }
        .padding(5)
        .background(NeumorphicSurfaceBackground(cornerRadius: 19, elevated: false, pressed: true, lightweight: true))
    }

    private func libraryRailButton(tab: LibraryViewModel.LibraryTab, index: Int) -> some View {
        let selected = tabIndex == index
        let tint = tint(for: tab)

        return Button {
            selectTab(tab, index: index)
        } label: {
            HStack(spacing: 6) {
                MonoIcon(
                    icon: icon(for: tab),
                    size: 12,
                    color: selected ? tint : NeumorphicStyle.inkSoft,
                    lineWidth: 1.55
                )
                Text(tab.localizedKey)
                    .font(NeumorphicStyle.labelFont(11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NeumorphicStyle.surfaceRaised)
                        .matchedGeometryEffect(id: "library-tab", in: tabNamespace)
                        .shadow(color: Color.black.opacity(0.09), radius: 5, x: 3, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch selectedTab {
            case .my:
                myLibraryPage
            case .square:
                playlistDiscoveryPage
            case .artists:
                artistIndexPage
            case .charts:
                chartFlowPage
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var myLibraryPage: some View {
        libraryDeck(
            title: selectedShelf.title,
            icon: selectedShelf.icon,
            tint: tint(for: selectedShelf),
            trailing: {
                libraryToolsButton
            }
        ) {
            shelfSelector

            LibraryDisclosureReveal(isExpanded: showLibraryTools) {
                LazyVGrid(columns: controlColumns, spacing: 9) {
                    actionChip(title: String(localized: "lib_create"), icon: .add, tint: NeumorphicStyle.accent) {
                        createLocalPlaylist()
                    }
                    actionChip(title: String(localized: "lib_import_playlist"), icon: .download, tint: NeumorphicStyle.warm, isLoading: isImporting) {
                        showFileImporter = true
                    }
                    actionChip(title: String(localized: "从链接导入"), icon: .share, tint: NeumorphicStyle.sage, isLoading: isImporting) {
                        showImportLinkPrompt()
                    }
                    actionChip(title: String(localized: "QCM歌单"), icon: .musicNoteList, tint: MusicSource.qqmusic.themedBadgeColor) {
                        showQQImport = true
                    }
                }
                .padding(12)
                .background(NeumorphicSurfaceBackground(cornerRadius: 24, elevated: true, lightweight: true))
            }

            shelfContent
        }
    }

    private var libraryToolsButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                showLibraryTools.toggle()
            }
        } label: {
            MonoIcon(
                icon: showLibraryTools ? .close : .more,
                size: 14,
                color: showLibraryTools ? NeumorphicStyle.accent : NeumorphicStyle.inkMuted,
                lineWidth: 1.65
            )
            .frame(width: 38, height: 38)
            .background(
                NeumorphicSurfaceBackground(
                    cornerRadius: 15,
                    elevated: showLibraryTools,
                    pressed: !showLibraryTools,
                    tint: showLibraryTools ? NeumorphicStyle.accent.opacity(0.14) : NeumorphicStyle.surface,
                    lightweight: true
                )
            )
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
    }

    private var shelfSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Shelf.allCases, id: \.self) { shelf in
                    let selected = selectedShelf == shelf
                    let tint = tint(for: shelf)
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            selectedShelf = shelf
                        }
                        if shelf == .qcmPlaylists {
                            loadQQUserPlaylistsIfNeeded()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            MonoIcon(icon: shelf.icon, size: 13, color: selected ? tint : NeumorphicStyle.inkMuted, lineWidth: selected ? 1.8 : 1.5)
                            Text(shelf.title)
                                .font(NeumorphicStyle.labelFont(12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(
                            NeumorphicSurfaceBackground(
                                cornerRadius: 17,
                                elevated: selected,
                                pressed: !selected,
                                tint: selected ? tint.opacity(0.17) : NeumorphicStyle.surface,
                                lightweight: true
                            )
                        )
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    @ViewBuilder
    private var shelfContent: some View {
        switch selectedShelf {
        case .localPlaylists:
            localPlaylistsContent
        case .ncmPlaylists:
            remotePlaylistsContent(playlists: viewModel.userPlaylists, emptyTitle: String(localized: "empty_no_playlists"), tint: MusicSource.netease.themedBadgeColor)
        case .qcmPlaylists:
            qcmPlaylistsContent
        case .kcmPlaylists:
            remotePlaylistsContent(
                playlists: viewModel.kugouUserPlaylists,
                emptyTitle: KCMMusicService.shared.isAuthenticated ? "暂无 KCM 歌单" : "请先登录 KCM",
                tint: MusicSource.kugou.themedBadgeColor
            )
        case .appleMusic:
            AppleMusicLibraryView(embeddedInParentScroll: true)
        case .localPodcasts:
            localPodcastsContent
        case .ncmPodcasts:
            ncmPodcastsContent
        }
    }

    private var localPlaylistsContent: some View {
        Group {
            if localManager.playlists.isEmpty {
                emptyCard(icon: .musicNoteList, title: String(localized: "lib_no_local_playlists"), tint: NeumorphicStyle.accent)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(localManager.playlists, id: \.id) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.localPlaylist(playlist.id)) {
                            let summary = localManager.summary(for: playlist)
                            NeumorphicLocalShelfRow(
                                summary: summary,
                                tint: summary.isFavorite ? NeumorphicStyle.red : (summary.isDownload ? NeumorphicStyle.sage : NeumorphicStyle.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func remotePlaylistsContent(playlists: [Playlist], emptyTitle: String, tint: Color) -> some View {
        Group {
            if playlists.isEmpty {
                emptyCard(icon: .list, title: emptyTitle, tint: tint)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            NeumorphicPlaylistShelfRow(playlist: playlist, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var qcmPlaylistsContent: some View {
        Group {
            if isLoadingQQUserPlaylists && qqUserPlaylists.isEmpty {
                LibraryLoadingStateView(horizontalPadding: 0, minHeight: 240)
            } else if !qqSession.isLoggedIn {
                emptyCard(icon: .musicNoteList, title: String(localized: "qcm_login_required"), tint: MusicSource.qqmusic.themedBadgeColor)
            } else {
                remotePlaylistsContent(playlists: qqUserPlaylists, emptyTitle: String(localized: "暂无 QCM 歌单"), tint: MusicSource.qqmusic.themedBadgeColor)
            }
        }
    }

    private var localPodcastsContent: some View {
        Group {
            if subManager.localSubscribedRadios.isEmpty {
                emptyCard(icon: .radio, title: String(localized: "暂无本地收藏"), tint: NeumorphicStyle.sage)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(subManager.localSubscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            NeumorphicPodcastShelfRow(radio: radio, tint: NeumorphicStyle.sage)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var ncmPodcastsContent: some View {
        Group {
            if subManager.isLoadingRadios && subManager.subscribedRadios.isEmpty {
                LibraryLoadingStateView(horizontalPadding: 0, minHeight: 240)
            } else if subManager.subscribedRadios.isEmpty {
                emptyCard(icon: .radio, title: String(localized: "lib_no_podcasts"), tint: NeumorphicStyle.warm)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(subManager.subscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            NeumorphicPodcastShelfRow(radio: radio, tint: NeumorphicStyle.warm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var playlistDiscoveryPage: some View {
        libraryDeck(
            title: String(localized: "歌单广场"),
            icon: .musicNoteList,
            tint: sourceTint(viewModel.squareSource)
        ) {
            sourceSwitch(selected: viewModel.squareSource) { source in
                viewModel.squareSource = source
                viewModel.fetchSquareForSelectedSource()
            }

            if viewModel.squareSource == .qq {
                filterBar {
                    ForEach(filteredQQCategories, id: \.id) { category in
                        filterChip(title: category.name, selected: viewModel.selectedQQCategoryId == category.id, tint: MusicSource.qqmusic.themedBadgeColor) {
                            viewModel.selectQQCategory(id: category.id, name: category.name)
                        }
                    }
                }
                playlistGrid(playlists: viewModel.qqSquarePlaylists, isLoading: viewModel.isLoadingQQSquare, emptyTitle: String(localized: "暂无QCM推荐歌单"))
                if viewModel.hasMoreQQSquare && !viewModel.qqSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreQQSquarePlaylists() }
                }
            } else if viewModel.squareSource == .kugou {
                filterBar {
                    ForEach(viewModel.kugouPlaylistCategories) { category in
                        filterChip(title: category.name, selected: viewModel.selectedKugouCategoryID == category.id, tint: MusicSource.kugou.themedBadgeColor) {
                            viewModel.selectKugouCategory(category)
                        }
                    }
                }
                playlistGrid(playlists: viewModel.kugouSquarePlaylists, isLoading: viewModel.isLoadingKugouSquare, emptyTitle: "暂无KCM推荐歌单")
                if viewModel.hasMoreKugouSquare && !viewModel.kugouSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreKugouSquarePlaylists() }
                }
            } else if viewModel.squareSource == .appleMusic {
                playlistGrid(playlists: viewModel.appleMusicSquarePlaylists, isLoading: viewModel.isLoadingAppleMusicSquare, emptyTitle: String(localized: "empty_no_playlists"))
                if viewModel.hasMoreAppleMusicSquare && !viewModel.appleMusicSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreAppleMusicSquarePlaylists() }
                }
            } else {
                filterBar {
                    ForEach(viewModel.playlistCategories, id: \.idString) { category in
                        filterChip(title: category.name, selected: viewModel.selectedCategory == category.name, tint: MusicSource.netease.themedBadgeColor) {
                            viewModel.selectedCategory = category.name
                            viewModel.loadSquarePlaylists(cat: category.name, reset: true)
                        }
                    }
                }
                playlistGrid(playlists: viewModel.squarePlaylists, isLoading: viewModel.isLoadingSquare, emptyTitle: String(localized: "empty_no_playlists"))
                if viewModel.hasMoreSquarePlaylists && !viewModel.squarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreSquarePlaylists() }
                }
            }
        }
    }

    private var artistIndexPage: some View {
        libraryDeck(
            title: String(localized: "lib_tab_artists"),
            icon: .personCircle,
            tint: viewModel.artistSource == .appleMusic ? MusicSource.appleMusic.themedBadgeColor : (viewModel.artistSource == .qq ? MusicSource.qqmusic.themedBadgeColor : NeumorphicStyle.warm)
        ) {
            sourceSwitch(selected: viewModel.artistSource, sources: [.ncm, .qq, .kugou, .appleMusic]) { source in
                dismissArtistSearchKeyboard()
                showArtistFilters = false
                showQQArtistFilters = false
                showKugouArtistFilters = false
                showAppleMusicArtistFilters = false
                viewModel.artistSource = source
                viewModel.fetchArtistsForSelectedSource(reset: true)
            }

            if viewModel.artistSource == .qq {
                qqArtistSearchAndFilters
                artistGrid(artists: viewModel.qqArtists, isLoading: viewModel.isLoadingQQArtists, tint: MusicSource.qqmusic.themedBadgeColor)
                if viewModel.hasMoreQQArtists && !viewModel.qqArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreQQArtists() }
                }
            } else if viewModel.artistSource == .kugou {
                kugouArtistSearchAndFilters
                artistGrid(artists: viewModel.kugouArtists, isLoading: viewModel.isLoadingKugouArtists, tint: MusicSource.kugou.themedBadgeColor)
            } else if viewModel.artistSource == .appleMusic {
                appleMusicArtistFilters
                artistGrid(artists: viewModel.appleMusicArtists, isLoading: viewModel.isLoadingAppleMusicArtists, tint: MusicSource.appleMusic.themedBadgeColor)
                if viewModel.hasMoreAppleMusicArtists && !viewModel.appleMusicArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreAppleMusicArtists() }
                }
            } else {
                ncmArtistSearchAndFilters
                artistGrid(artists: viewModel.topArtists, isLoading: viewModel.isLoadingArtists, tint: NeumorphicStyle.warm)
                if viewModel.hasMoreArtists && !viewModel.topArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreArtists() }
                }
            }
        }
    }

    private var ncmArtistSearchAndFilters: some View {
        VStack(spacing: 10) {
            artistSearchBar(
                text: $viewModel.artistSearchText,
                placeholder: LocalizedStringKey("search_artists"),
                field: .ncm,
                tint: NeumorphicStyle.warm,
                hasActiveFilter: hasActiveArtistFilter,
                isFilterExpanded: showArtistFilters,
                isSearching: viewModel.isSearchingArtists,
                onToggleFilter: {
                    showArtistFilters.toggle()
                },
                onClear: {
                    viewModel.artistSearchText = ""
                    viewModel.fetchArtistData(reset: true)
                },
                onSubmit: {
                    if viewModel.artistSearchText.isEmpty {
                        viewModel.fetchArtistData(reset: true)
                    } else {
                        viewModel.searchArtists(keyword: viewModel.artistSearchText)
                    }
                }
            )

            LibraryDisclosureReveal(isExpanded: !viewModel.isSearchingArtists && showArtistFilters) {
                VStack(spacing: 10) {
                    filterBar {
                        ForEach(viewModel.artistAreas, id: \.value) { area in
                            filterChip(title: NSLocalizedString(area.name, comment: ""), selected: viewModel.artistArea == area.value, tint: NeumorphicStyle.warm) {
                                viewModel.artistArea = area.value
                                viewModel.fetchArtistData(reset: true)
                            }
                        }
                    }
                    filterBar {
                        ForEach(viewModel.artistTypes, id: \.value) { type in
                            filterChip(title: NSLocalizedString(type.name, comment: ""), selected: viewModel.artistType == type.value, tint: NeumorphicStyle.sage) {
                                viewModel.artistType = type.value
                                viewModel.fetchArtistData(reset: true)
                            }
                        }
                    }
                    filterBar {
                        ForEach(viewModel.artistInitials, id: \.self) { initial in
                            filterChip(title: initial == "-1" ? NSLocalizedString("search_hot", comment: "") : initial, selected: viewModel.artistInitial == initial, tint: NeumorphicStyle.accent) {
                                viewModel.artistInitial = initial
                                viewModel.fetchArtistData(reset: true)
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    private var qqArtistSearchAndFilters: some View {
        VStack(spacing: 10) {
            artistSearchBar(
                text: $viewModel.qqArtistSearchText,
                placeholder: LocalizedStringKey("搜索QCM歌手"),
                field: .qq,
                tint: MusicSource.qqmusic.themedBadgeColor,
                hasActiveFilter: hasActiveQQArtistFilter,
                isFilterExpanded: showQQArtistFilters,
                isSearching: viewModel.isSearchingQQArtists,
                onToggleFilter: {
                    showQQArtistFilters.toggle()
                },
                onClear: {
                    viewModel.qqArtistSearchText = ""
                    viewModel.fetchQQArtistData(reset: true)
                },
                onSubmit: {
                    if !viewModel.qqArtistSearchText.isEmpty {
                        viewModel.searchQQArtists(keyword: viewModel.qqArtistSearchText)
                    }
                }
            )

            LibraryDisclosureReveal(isExpanded: !viewModel.isSearchingQQArtists && showQQArtistFilters) {
                VStack(spacing: 10) {
                    filterBar {
                        ForEach(viewModel.qqArtistAreas, id: \.value) { area in
                            filterChip(title: NSLocalizedString(area.name, comment: ""), selected: viewModel.qqArtistArea == area.value, tint: MusicSource.qqmusic.themedBadgeColor) {
                                viewModel.qqArtistArea = area.value
                                viewModel.fetchQQArtistData(reset: true)
                            }
                        }
                    }
                    filterBar {
                        ForEach(viewModel.qqArtistSexes, id: \.value) { sex in
                            filterChip(title: NSLocalizedString(sex.name, comment: ""), selected: viewModel.qqArtistSex == sex.value, tint: NeumorphicStyle.accent) {
                                viewModel.qqArtistSex = sex.value
                                viewModel.fetchQQArtistData(reset: true)
                            }
                        }
                    }
                    filterBar {
                        ForEach(viewModel.qqArtistGenres, id: \.value) { genre in
                            filterChip(title: NSLocalizedString(genre.name, comment: ""), selected: viewModel.qqArtistGenre == genre.value, tint: NeumorphicStyle.sage) {
                                viewModel.qqArtistGenre = genre.value
                                viewModel.fetchQQArtistData(reset: true)
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    private var kugouArtistSearchAndFilters: some View {
        VStack(spacing: 10) {
            artistSearchBar(
                text: $viewModel.kugouArtistSearchText,
                placeholder: LocalizedStringKey("搜索 KCM 歌手"),
                field: .kugou,
                tint: MusicSource.kugou.themedBadgeColor,
                hasActiveFilter: viewModel.kugouArtistType != 0 || viewModel.kugouArtistSex != 0,
                isFilterExpanded: showKugouArtistFilters,
                isSearching: viewModel.isSearchingKugouArtists,
                onToggleFilter: { showKugouArtistFilters.toggle() },
                onClear: { viewModel.kugouArtistSearchText = "" },
                onSubmit: { viewModel.searchKugouArtists(keyword: viewModel.kugouArtistSearchText) }
            )

            LibraryDisclosureReveal(isExpanded: !viewModel.isSearchingKugouArtists && showKugouArtistFilters) {
                VStack(spacing: 10) {
                    filterBar {
                        ForEach(viewModel.kugouArtistTypes, id: \.value) { type in
                            filterChip(title: NSLocalizedString(type.name, comment: ""), selected: viewModel.kugouArtistType == type.value, tint: MusicSource.kugou.themedBadgeColor) {
                                viewModel.kugouArtistType = type.value
                                viewModel.fetchKugouArtistData(reset: true)
                            }
                        }
                    }
                    filterBar {
                        ForEach(viewModel.kugouArtistSexes, id: \.value) { sex in
                            filterChip(title: NSLocalizedString(sex.name, comment: ""), selected: viewModel.kugouArtistSex == sex.value, tint: NeumorphicStyle.sage) {
                                viewModel.kugouArtistSex = sex.value
                                viewModel.fetchKugouArtistData(reset: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var appleMusicArtistFilters: some View {
        VStack(spacing: 10) {
            artistSearchBar(
                text: $viewModel.appleMusicArtistSearchText,
                placeholder: LocalizedStringKey("搜索 Apple Music 歌手"),
                field: .appleMusic,
                tint: MusicSource.appleMusic.themedBadgeColor,
                hasActiveFilter: viewModel.appleMusicArtistCategory != 0,
                isFilterExpanded: showAppleMusicArtistFilters,
                isSearching: viewModel.isSearchingAppleMusicArtists,
                onToggleFilter: { showAppleMusicArtistFilters.toggle() },
                onClear: { viewModel.appleMusicArtistSearchText = "" },
                onSubmit: { viewModel.searchAppleMusicArtists(keyword: viewModel.appleMusicArtistSearchText) }
            )

            LibraryDisclosureReveal(isExpanded: !viewModel.isSearchingAppleMusicArtists && showAppleMusicArtistFilters) {
                filterBar {
                    ForEach(Array(viewModel.appleMusicArtistCategories.enumerated()), id: \.offset) { index, category in
                        filterChip(title: NSLocalizedString(category.name, comment: ""), selected: viewModel.appleMusicArtistCategory == index, tint: MusicSource.appleMusic.themedBadgeColor) {
                            viewModel.selectAppleMusicArtistCategory(index)
                        }
                    }
                }
            }
        }
    }

    private func artistSearchBar(
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        field: ArtistSearchField,
        tint: Color,
        hasActiveFilter: Bool,
        isFilterExpanded: Bool,
        isSearching: Bool,
        onToggleFilter: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                MonoIcon(icon: .magnifyingGlass, size: 16, color: NeumorphicStyle.inkMuted, lineWidth: 1.7)

                TextField(placeholder, text: text)
                    .font(NeumorphicStyle.bodyFont(14, weight: .medium))
                    .foregroundStyle(NeumorphicStyle.ink)
                    .monoTextInputBehavior()
                    .focused($focusedArtistSearchField, equals: field)
                    .submitLabel(.search)
                    .monoOnSubmit(text: text) { _ in
                        dismissArtistSearchKeyboard()
                        onSubmit()
                    }

                if !text.wrappedValue.isEmpty {
                    Button {
                        dismissArtistSearchKeyboard()
                        onClear()
                    } label: {
                        MonoIcon(icon: .close, size: 13, color: NeumorphicStyle.inkMuted, lineWidth: 1.7)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(NeumorphicSurfaceBackground(cornerRadius: 17, elevated: false, pressed: true, lightweight: true))

            if !isSearching {
                Button {
                    dismissArtistSearchKeyboard()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        onToggleFilter()
                    }
                } label: {
                    MonoIcon(
                        icon: .filter,
                        size: 15,
                        color: hasActiveFilter || isFilterExpanded ? tint : NeumorphicStyle.inkMuted,
                        lineWidth: 1.7
                    )
                    .rotationEffect(.degrees(isFilterExpanded ? 90 : 0))
                    .frame(width: 42, height: 42)
                    .background(
                        NeumorphicSurfaceBackground(
                            cornerRadius: 16,
                            elevated: isFilterExpanded || hasActiveFilter,
                            pressed: !(isFilterExpanded || hasActiveFilter),
                            tint: hasActiveFilter ? tint.opacity(0.14) : NeumorphicStyle.surface,
                            lightweight: true
                        )
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
            }
        }
    }

    private var chartFlowPage: some View {
        libraryDeck(
            title: String(localized: "榜单"),
            icon: .chart,
            tint: viewModel.chartsSource == .qq
                ? MusicSource.qqmusic.themedBadgeColor
                : (viewModel.chartsSource == .kugou ? MusicSource.kugou.themedBadgeColor : NeumorphicStyle.red)
        ) {
            sourceSwitch(selected: viewModel.chartsSource, sources: [.ncm, .qq, .kugou, .appleMusic]) { source in
                viewModel.chartsSource = source
                viewModel.fetchChartsForSelectedSource()
            }

            if viewModel.chartsSource == .qq {
                if viewModel.isLoadingQQCharts && viewModel.qqTopLists.isEmpty {
                    LibraryLoadingStateView(horizontalPadding: 0, minHeight: 260)
                } else if viewModel.qqTopLists.isEmpty {
                    emptyCard(icon: .chart, title: String(localized: "暂无QCM排行榜"), tint: MusicSource.qqmusic.themedBadgeColor)
                } else {
                    ForEach(viewModel.qqTopLists) { group in
                        sectionTitle(group.groupName, tint: NeumorphicStyle.red)
                        LazyVStack(spacing: 10) {
                            ForEach(group.items) { item in
                                NavigationLink(value: qqChartDestination(item)) {
                                    NeumorphicQQChartShelfRow(item: item, tint: MusicSource.qqmusic.themedBadgeColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                if viewModel.isLoadingDisplayedCharts && viewModel.displayedTopLists.isEmpty {
                    LibraryLoadingStateView(horizontalPadding: 0, minHeight: 260)
                } else if viewModel.displayedTopLists.isEmpty {
                    emptyCard(icon: .chart, title: String(localized: "empty_no_charts"), tint: NeumorphicStyle.red)
                } else {
                    let officialIds: Set<Int> = [19_723_756, 3_779_629, 2_884_035, 3_778_678]
                    let official = viewModel.displayedTopLists.filter { officialIds.contains($0.id) }
                    let others = viewModel.displayedTopLists.filter { !officialIds.contains($0.id) }

                    if !official.isEmpty {
                        sectionTitle(String(localized: "charts_official"), tint: NeumorphicStyle.red)
                        officialChartRail(official)
                    }

                    if !others.isEmpty {
                        sectionTitle(String(localized: "charts_more"), tint: NeumorphicStyle.warm)
                        LazyVGrid(columns: playlistColumns, spacing: 12) {
                            ForEach(others) { list in
                                NavigationLink(value: chartDestination(list)) {
                                    NeumorphicChartTile(list: list, tint: NeumorphicStyle.warm)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func officialChartRail(_ lists: [TopList]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(lists) { list in
                    NavigationLink(value: chartDestination(list)) {
                        NeumorphicChartTile(list: list, tint: NeumorphicStyle.red)
                            .frame(width: DeviceLayout.usesExpandedLayout ? 180 : 148)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }


    private func libraryDeck<Content: View>(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        libraryDeck(
            title: title,
            icon: icon,
            tint: tint,
            trailing: {
                EmptyView()
            },
            content: content
        )
    }

    private func libraryDeck<Content: View, Trailing: View>(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                NeumorphicIconBadge(icon: icon, tint: tint, size: 38)

                Text(title)
                    .font(NeumorphicStyle.titleFont(18, weight: .semibold))
                    .foregroundStyle(NeumorphicStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                trailing()
            }

            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(neumorphicLibraryContentPanel(tint: tint))
        .padding(.horizontal, deckOuterPadding)
    }

    private func neumorphicLibraryContentPanel(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(NeumorphicStyle.surfaceRaised.opacity(0.96))
            .overlay(
                LinearGradient(
                    colors: [
                        Color(
                            light: Color.white.opacity(0.42),
                            dark: Color.white.opacity(0.05)
                        ),
                        tint.opacity(0.045),
                        NeumorphicStyle.surface.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        Color(
                            light: Color.white.opacity(0.44),
                            dark: Color.white.opacity(0.08)
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color(
                    light: Color.black.opacity(0.06),
                    dark: Color.black.opacity(0.26)
                ),
                radius: 12,
                x: 5,
                y: 7
            )
            .shadow(
                color: Color(
                    light: Color.white.opacity(0.54),
                    dark: Color.white.opacity(0.045)
                ),
                radius: 7,
                x: -4,
                y: -5
            )
    }

    private func sourceSwitch(
        selected: LibraryViewModel.MusicSource,
        sources: [LibraryViewModel.MusicSource] = LibraryViewModel.MusicSource.allCases,
        onSelect: @escaping (LibraryViewModel.MusicSource) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(sources, id: \.self) { source in
                let isSelected = selected == source
                let tint = sourceTint(source)
                Button {
                    guard !isSelected else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        onSelect(source)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tint)
                            .frame(width: 7, height: 7)
                        Text(source.shortName)
                            .font(NeumorphicStyle.labelFont(12, weight: .semibold))
                            .foregroundStyle(isSelected ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        NeumorphicSurfaceBackground(
                            cornerRadius: 17,
                            elevated: isSelected,
                            pressed: !isSelected,
                            tint: isSelected ? tint.opacity(0.16) : NeumorphicStyle.surface,
                            lightweight: true
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(NeumorphicSurfaceBackground(cornerRadius: 23, elevated: true, lightweight: true))
    }

    private func sourceTint(_ source: LibraryViewModel.MusicSource) -> Color {
        switch source {
        case .ncm: return MusicSource.netease.themedBadgeColor
        case .qq: return MusicSource.qqmusic.themedBadgeColor
        case .kugou: return MusicSource.kugou.themedBadgeColor
        case .appleMusic: return MusicSource.appleMusic.themedBadgeColor
        }
    }

    private func filterBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                content()
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    private func filterChip(title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            guard !selected else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                action()
            }
        } label: {
            Text(title)
                .font(NeumorphicStyle.labelFont(12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    NeumorphicSurfaceBackground(
                        cornerRadius: 16,
                        elevated: selected,
                        pressed: !selected,
                        tint: selected ? tint.opacity(0.16) : NeumorphicStyle.surface,
                        lightweight: true
                    )
                )
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
    }

    private func actionChip(title: String, icon: MonoIcon.IconType, tint: Color, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .tint(tint)
                        .scaleEffect(0.68)
                        .frame(width: 14, height: 14)
                } else {
                    MonoIcon(icon: icon, size: 14, color: tint, lineWidth: 1.6)
                }
                Text(title)
                    .font(NeumorphicStyle.labelFont(12, weight: .semibold))
                    .foregroundStyle(NeumorphicStyle.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(NeumorphicSurfaceBackground(cornerRadius: 16, elevated: false, pressed: true, tint: tint.opacity(0.09), lightweight: true))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }

    private func playlistGrid(playlists: [Playlist], isLoading: Bool, emptyTitle: String) -> some View {
        Group {
            if isLoading && playlists.isEmpty {
                LibraryLoadingStateView(horizontalPadding: 0, minHeight: 260)
            } else if playlists.isEmpty {
                emptyCard(icon: .list, title: emptyTitle, tint: NeumorphicStyle.sage)
            } else {
                LazyVGrid(columns: playlistColumns, spacing: 12) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            NeumorphicPlaylistShelfCard(
                                playlist: playlist,
                                tint: (playlist.source ?? .netease).themedBadgeColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func artistGrid(artists: [ArtistInfo], isLoading: Bool, tint: Color) -> some View {
        Group {
            if isLoading && artists.isEmpty {
                LibraryLoadingStateView(horizontalPadding: 0, minHeight: 260)
            } else if artists.isEmpty {
                emptyCard(icon: .personEmpty, title: String(localized: "empty_no_artists"), tint: tint)
            } else {
                LazyVGrid(columns: artistColumns, spacing: 12) {
                    ForEach(artists) { artist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.artistInfo(artist)) {
                            NeumorphicArtistShelfTile(artist: artist, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadMoreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey("查看更多"))
                .font(NeumorphicStyle.labelFont(13, weight: .semibold))
                .foregroundStyle(NeumorphicStyle.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(NeumorphicSurfaceBackground(cornerRadius: 18, elevated: true, tint: NeumorphicStyle.accent.opacity(0.12), lightweight: true))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
        .padding(.top, 2)
    }

    private func sectionTitle(_ title: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(NeumorphicStyle.titleFont(18, weight: .semibold))
                .foregroundStyle(NeumorphicStyle.ink)
            Spacer(minLength: 0)
        }
    }

    private func emptyCard(icon: MonoIcon.IconType, title: String, tint: Color) -> some View {
        VStack(spacing: 12) {
            MonoIcon(icon: icon, size: 27, color: tint.opacity(0.72), lineWidth: 1.8)
                .frame(width: 54, height: 54)
                .background(NeumorphicSurfaceBackground(cornerRadius: 20, elevated: true, tint: tint.opacity(0.11), lightweight: true))
            Text(title)
                .font(NeumorphicStyle.labelFont(13, weight: .medium))
                .foregroundStyle(NeumorphicStyle.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(NeumorphicSurfaceBackground(cornerRadius: 26, elevated: true, lightweight: true))
    }

    private var filteredQQCategories: [(id: Int, name: String)] {
        let hidden: Set<String> = [String(localized: "filter_all"), String(localized: "ai歌单"), String(localized: "私藏"), String(localized: "音乐人在听"), "chill vibes", String(localized: "ai 歌单")]
        return viewModel.qqPlaylistCategories.filter { !hidden.contains($0.name.lowercased()) }
    }

    private var activeTint: Color {
        tint(for: selectedTab)
    }

    private var hasActiveArtistFilter: Bool {
        viewModel.artistArea != -1 || viewModel.artistType != -1 || viewModel.artistInitial != "-1"
    }

    private var hasActiveQQArtistFilter: Bool {
        viewModel.qqArtistArea != .all || viewModel.qqArtistSex != .all || viewModel.qqArtistGenre != .all
    }

    private func dismissArtistSearchKeyboard() {
        focusedArtistSearchField = nil
    }

    private func icon(for tab: LibraryViewModel.LibraryTab) -> MonoIcon.IconType {
        switch tab {
        case .my: return .libraryFilled
        case .square: return .gridSquare
        case .artists: return .personCircle
        case .charts: return .chart
        }
    }

    private func tint(for tab: LibraryViewModel.LibraryTab) -> Color {
        switch tab {
        case .my: return NeumorphicStyle.accent
        case .square: return NeumorphicStyle.sage
        case .artists: return NeumorphicStyle.warm
        case .charts: return NeumorphicStyle.red
        }
    }

    private func tint(for shelf: Shelf) -> Color {
        switch shelf {
        case .localPlaylists: return NeumorphicStyle.accent
        case .ncmPlaylists: return MusicSource.netease.themedBadgeColor
        case .qcmPlaylists: return MusicSource.qqmusic.themedBadgeColor
        case .kcmPlaylists: return MusicSource.kugou.themedBadgeColor
        case .appleMusic: return MusicSource.appleMusic.themedBadgeColor
        case .localPodcasts: return NeumorphicStyle.sage
        case .ncmPodcasts: return NeumorphicStyle.warm
        }
    }

    private func selectTab(_ tab: LibraryViewModel.LibraryTab, index: Int) {
        guard tabIndex != index || viewModel.currentTab != tab else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            tabIndex = index
            viewModel.currentTab = tab
        }
    }

    private func syncTabFromViewModel() {
        if let index = tabs.firstIndex(of: viewModel.currentTab), index != tabIndex {
            tabIndex = index
        }
    }

    private func loadCurrentTab() {
        load(selectedTab)
    }

    private func load(_ tab: LibraryViewModel.LibraryTab) {
        switch tab {
        case .my:
            viewModel.fetchPlaylists()
            if selectedShelf == .qcmPlaylists {
                loadQQUserPlaylistsIfNeeded()
            }
            if subManager.subscribedRadios.isEmpty {
                subManager.fetchSubscribedRadios()
            }
        case .square:
            viewModel.fetchSquareForSelectedSource()
        case .artists:
            viewModel.fetchArtistsForSelectedSource()
        case .charts:
            viewModel.fetchChartsForSelectedSource()
        }
    }

    private func loadQQUserPlaylistsIfNeeded(force: Bool = false) {
        let session = qqSession.sessionSnapshot
        guard force || !hasLoadedQQUserPlaylists else { return }
        guard !isLoadingQQUserPlaylists else { return }
        guard session.isLoggedIn, let mid = session.musicID else {
            qqUserPlaylists = []
            hasLoadedQQUserPlaylists = true
            return
        }

        let request = qqPlaylistRequest.begin()
        isLoadingQQUserPlaylists = true
        qqPlaylistRequest.task = Task { @MainActor in
            guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request) else { return }
            defer {
                if qqPlaylistRequest.isCurrent(request), qqSession.isCurrentSession(session) {
                    isLoadingQQUserPlaylists = false
                    qqPlaylistRequest.finish(request)
                }
            }

            do {
                let result: JSON = try await QQUserSession.shared.withUserSession { client in
                    try await client.createdSonglist(uin: String(mid))
                }
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                qqUserPlaylists = Self.parseQQUserPlaylists(result)
                hasLoadedQQUserPlaylists = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                AppLogger.error("[Library] 加载 QCM 歌单失败: \(error)")
            }
        }
    }

    private static func parseQQUserPlaylists(_ result: JSON) -> [Playlist] {
        // 新版 API: { playlists: [{ id, dirid, title, picurl, songnum }], total }
        let list = result["playlists"]?.arrayValue
            ?? result["v_playlist"]?.arrayValue
            ?? result.arrayValue ?? []
        return list.compactMap { json in
            guard let obj = json.objectValue else { return nil }
            let tid = obj["id"]?.intValue ?? obj["tid"]?.intValue ?? 0
            let name = obj["title"]?.stringValue ?? obj["dirName"]?.stringValue ?? obj["diss_name"]?.stringValue ?? ""
            let cover = obj["picurl"]?.stringValue ?? obj["picUrl"]?.stringValue ?? obj["logo"]?.stringValue ?? ""
            let songCount = obj["songnum"]?.intValue ?? obj["songNum"]?.intValue ?? obj["song_cnt"]?.intValue ?? 0
            guard !name.isEmpty else { return nil }
            return Playlist(
                id: tid,
                name: name,
                coverImgUrl: cover,
                picUrl: nil,
                trackCount: songCount,
                playCount: nil,
                subscribedCount: nil,
                shareCount: nil,
                commentCount: nil,
                creator: nil,
                description: nil,
                tags: nil,
                source: .qqmusic
            )
        }
    }

    private func createLocalPlaylist() {
        AlertManager.shared.showInput(
            title: String(localized: "lib_create_playlist"),
            message: "",
            placeholder: String(localized: "lib_playlist_name"),
            primaryButtonTitle: String(localized: "lib_create"),
            secondaryButtonTitle: String(localized: "alert_cancel"),
            onConfirm: { name in
                guard !name.isEmpty else { return }
                _ = localManager.createPlaylist(name: name)
            }
        )
    }

    private func showImportLinkPrompt() {
        viewModel.navigationPath.append(
            LibraryViewModel.NavigationDestination.externalPlaylistImport
        )
    }

    private func importPlaylistFromFile(url: URL) {
        isImporting = true
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let parsed = try LocalPlaylistManager.parseExportFile(url: url)
            let ids = parsed.songIds
            let name = parsed.name
            guard !ids.isEmpty else {
                AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: String(localized: "lib_import_no_songs"), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
                isImporting = false
                return
            }

            Task {
                var allSongs: [Song] = []
                for i in stride(from: 0, to: ids.count, by: 50) {
                    let batch = Array(ids[i ..< min(i + 50, ids.count)])
                    do {
                        let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                            var cancellable: AnyCancellable?
                            cancellable = APIService.shared.fetchSongDetails(ids: batch)
                                .sink(receiveCompletion: { completion in
                                    if case let .failure(error) = completion {
                                        continuation.resume(throwing: error)
                                    }
                                    cancellable?.cancel()
                                }, receiveValue: { songs in
                                    continuation.resume(returning: songs)
                                    cancellable?.cancel()
                                })
                        }
                        allSongs.append(contentsOf: songs)
                    } catch {
                        AppLogger.error("导入歌单批次获取失败: \(error)")
                    }
                }

                await MainActor.run {
                    if allSongs.isEmpty {
                        AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: String(localized: "lib_import_fetch_failed"), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            }
        } catch {
            AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: error.localizedDescription, primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
            isImporting = false
        }
    }

    private func importPlaylistFromURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isImporting = true

        if let qqId = extractQQPlaylistId(from: trimmed) {
            importQQPlaylist(id: qqId)
        } else if let ncmId = extractNCMPlaylistId(from: trimmed) {
            importNCMPlaylist(id: ncmId)
        } else {
            AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: String(localized: "无法识别的歌单链接"), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
            isImporting = false
        }
    }

    private func extractQQPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist/(\d+)"#, options: .regularExpression) {
            return Int(url[range].replacingOccurrences(of: "playlist/", with: ""))
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("y.qq.com") {
            return Int(String(url[range]).replacingOccurrences(of: "id=", with: ""))
        }
        return nil
    }

    private func extractNCMPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist\?id=(\d+)"#, options: .regularExpression) {
            return Int(String(url[range]).replacingOccurrences(of: "playlist?id=", with: ""))
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("music.163.com") {
            return Int(String(url[range]).replacingOccurrences(of: "id=", with: ""))
        }
        return nil
    }

    private func importQQPlaylist(id: Int) {
        Task {
            do {
                let detail = try await APIService.shared.qqClient.songlistDetail(songlistId: id, num: 1, page: 1)
                let name = detail["dirinfo"]?["title"]?.stringValue ?? String(localized: "QCM歌单")
                var allSongs: [Song] = []
                var page = 1
                var hasMore = true

                while hasMore {
                    let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                        var resumed = false
                        var cancellable: AnyCancellable?
                        cancellable = APIService.shared.fetchQQPlaylistSongs(playlistId: id, page: page, num: 50)
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion, !resumed {
                                    resumed = true
                                    continuation.resume(throwing: error)
                                }
                                cancellable?.cancel()
                            }, receiveValue: { songs in
                                guard !resumed else { return }
                                resumed = true
                                continuation.resume(returning: songs)
                                cancellable?.cancel()
                            })
                    }
                    allSongs.append(contentsOf: songs)
                    hasMore = songs.count >= 50
                    page += 1
                }

                await MainActor.run {
                    if allSongs.isEmpty {
                        AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: String(localized: "playlist_empty_or_load_failed"), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: L10n.format("qcm_playlist_import_failed_format", error.localizedDescription), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
                    isImporting = false
                }
            }
        }
    }

    private func importNCMPlaylist(id: Int) {
        Task {
            var allSongs: [Song] = []
            var offset = 0
            let limit = 50
            var hasMore = true

            while hasMore {
                do {
                    let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                        var resumed = false
                        var cancellable: AnyCancellable?
                        cancellable = APIService.shared.fetchPlaylistTracks(id: id, limit: limit, offset: offset)
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion, !resumed {
                                    resumed = true
                                    continuation.resume(throwing: error)
                                }
                                cancellable?.cancel()
                            }, receiveValue: { songs in
                                guard !resumed else { return }
                                resumed = true
                                continuation.resume(returning: songs)
                                cancellable?.cancel()
                            })
                    }
                    allSongs.append(contentsOf: songs)
                    hasMore = songs.count >= limit
                    offset += limit
                } catch {
                    hasMore = false
                }
            }

            await MainActor.run {
                if allSongs.isEmpty {
                    AlertManager.shared.show(title: String(localized: "lib_import_failed"), message: String(localized: "playlist_empty_or_load_failed"), primaryButtonTitle: String(localized: "lib_confirm"), primaryAction: {})
                } else {
                    localManager.importPlaylist(name: String(localized: "NCM歌单"), songs: allSongs)
                }
                isImporting = false
            }
        }
    }

    private func chartDestination(_ list: TopList) -> LibraryViewModel.NavigationDestination {
        .playlist(list.playlist())
    }

    private func qqChartDestination(_ item: QQTopListItem) -> LibraryViewModel.NavigationDestination {
        .playlist(Playlist(id: item.topId, name: item.title, coverImgUrl: item.coverUrl, picUrl: nil, trackCount: nil, playCount: nil, subscribedCount: nil, shareCount: nil, commentCount: nil, creator: nil, description: item.intro.isEmpty ? nil : item.intro, tags: nil, source: .qqmusic, isTopList: true))
    }
}
