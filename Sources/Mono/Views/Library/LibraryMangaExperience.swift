import Combine
import QQMusicKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Manga Library Redesign

struct MangaLibraryExperience: View {
    private enum MangaMyLibraryColumn: CaseIterable, Hashable {
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

        var tint: Color {
            switch self {
            case .localPlaylists: return MangaStyle.labelYellow
            case .ncmPlaylists: return MangaStyle.bubbleBlue
            case .qcmPlaylists: return MangaStyle.bubblePink
            case .kcmPlaylists: return MusicSource.kugou.themedBadgeColor
            case .appleMusic: return MusicSource.appleMusic.themedBadgeColor
            case .localPodcasts: return MangaStyle.mint
            case .ncmPodcasts: return MangaStyle.decoBlue
            }
        }
    }

    @ObservedObject var viewModel: LibraryViewModel
    @Binding var tabIndex: Int
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var loginIdentity = LoginIdentityManager.shared
    @ObservedObject private var localManager = LocalPlaylistManager.shared
    @ObservedObject private var subManager = SubscriptionManager.shared
    @ObservedObject private var qqSession = QQUserSession.shared
    @State private var showFileImporter = false
    @State private var showQQImport = false
    @State private var isImporting = false
    @State private var selectedMyLibraryColumn: MangaMyLibraryColumn = .localPlaylists
    @State private var isLibraryActionsExpanded = false
    @State private var qqUserPlaylists: [Playlist] = []
    @State private var isLoadingQQUserPlaylists = false
    @State private var hasLoadedQQUserPlaylists = false
    @State private var qqPlaylistRequest = LibraryRequestScope()

    private let tabs = LibraryViewModel.LibraryTab.allCases
    private let twoColumns = [
        GridItem(.flexible(), spacing: 13),
        GridItem(.flexible(), spacing: 13),
    ]
    private let controlColumns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9),
    ]
    private let threeColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let _ = settings.globalThemeRevision
        ZStack {
            ThemedPageBackground(useRenderLayer: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    magazineHeader
                        .monoPageHeaderCollapse()
                    tabContent
                }
                .padding(.bottom, 128)
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
            loadCurrentTab()
        }
        .onChange(of: tabIndex) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
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
        case .netease: selectedMyLibraryColumn = .ncmPlaylists
        case .qqmusic: selectedMyLibraryColumn = .qcmPlaylists
        case .kugou: selectedMyLibraryColumn = .kcmPlaylists
        case .qishui, .appleMusic, .local, nil: selectedMyLibraryColumn = .localPlaylists
        }
    }

    private var selectedTab: LibraryViewModel.LibraryTab {
        tabs[min(max(tabIndex, 0), tabs.count - 1)]
    }

    private var magazineHeader: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                // 印章式栏目标：色章直接盖在纸上，无框无投影
                ZStack {
                    RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                        .fill(MangaStyle.bubblePink)
                    MonoIcon(icon: .libraryFilled, size: 22, color: MangaStyle.ink, lineWidth: 2)
                }
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(-3))

                VStack(alignment: .leading, spacing: 6) {
                    MangaLabel(text: "LIBRARY", tint: MangaStyle.labelYellow, small: true)

                    MangaMisprintTitle(text: String(localized: "tabbar_library"), size: DeviceLayout.usesExpandedLayout ? 30 : 26)
                }

                Spacer(minLength: 0)
            }

            mangaTabStrip
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        .padding(.top, DeviceLayout.headerTopPadding + 8)
    }

    private var mangaTabStrip: some View {
        // 报刊栏目条：上下规则线之间的文字页签，选中项底部压粗墨线
        VStack(spacing: 0) {
            Rectangle()
                .fill(MangaStyle.ink.opacity(0.7))
                .frame(height: 1.6)

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    Button {
                        selectTab(tab, index: index)
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 5) {
                                MonoIcon(
                                    icon: icon(for: tab),
                                    size: 12,
                                    color: tabIndex == index ? MangaStyle.ink : MangaStyle.inkMuted,
                                    lineWidth: tabIndex == index ? 2 : 1.6
                                )
                                Text(tab.localizedKey)
                                    .font(MangaStyle.labelFont(11, weight: tabIndex == index ? .black : .bold))
                                    .foregroundStyle(tabIndex == index ? MangaStyle.ink : MangaStyle.inkMuted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                            }

                            Rectangle()
                                .fill(tabIndex == index ? MangaStyle.accentPink : Color.clear)
                                .frame(height: 2.5)
                                .padding(.horizontal, 8)
                        }
                        .padding(.top, 11)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < tabs.count - 1 {
                        Rectangle()
                            .fill(MangaStyle.strokeInk.opacity(0.18))
                            .frame(width: 1)
                            .padding(.vertical, 9)
                    }
                }
            }

            Rectangle()
                .fill(MangaStyle.ink.opacity(0.3))
                .frame(height: 0.8)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .my:
            myLibraryPage
        case .square:
            playlistSquarePage
        case .artists:
            artistsPage
        case .charts:
            chartsPage
        }
    }

    private var myLibraryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            mangaMyLibraryControlPanel
            mangaMyLibraryColumnContent
        }
    }

    private var mangaMyLibraryControlPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                mangaMyLibraryColumnStrip
                    .layoutPriority(1)

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isLibraryActionsExpanded.toggle()
                    }
                } label: {
                    MonoIcon(
                        icon: isLibraryActionsExpanded ? .close : .more,
                        size: 16,
                        color: MangaStyle.strokeInk,
                        lineWidth: 1.8
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                            .fill(isLibraryActionsExpanded ? MangaStyle.labelYellow : MangaStyle.bubbleWhite.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                            .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.fineStrokeWidth)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous))
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
            }

            LibraryDisclosureReveal(isExpanded: isLibraryActionsExpanded) {
                mangaImportActionStrip
                    .padding(10)
                    .background(MangaCardBackground(cornerRadius: MangaStyle.cardRadius + 2, elevated: true, tint: MangaStyle.bubbleWhite))
            }
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }

    private var mangaMyLibraryColumnStrip: some View {
        // 目录式子栏：文字 + 选中下划线，直接排在纸上
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(MangaMyLibraryColumn.allCases, id: \.self) { column in
                    let selected = selectedMyLibraryColumn == column
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selectedMyLibraryColumn = column
                        }
                        if column == .qcmPlaylists {
                            loadQQUserPlaylistsIfNeeded()
                        }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                MonoIcon(
                                    icon: column.icon,
                                    size: 13,
                                    color: selected ? MangaStyle.ink : MangaStyle.inkMuted,
                                    lineWidth: selected ? 2 : 1.6
                                )

                                Text(column.title)
                                    .font(MangaStyle.labelFont(12, weight: selected ? .black : .bold))
                                    .foregroundStyle(selected ? MangaStyle.ink : MangaStyle.inkMuted)
                                    .lineLimit(1)
                            }

                            Rectangle()
                                .fill(selected ? MangaStyle.accentPink : Color.clear)
                                .frame(height: 2.5)
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    @ViewBuilder
    private var mangaMyLibraryColumnContent: some View {
        switch selectedMyLibraryColumn {
        case .localPlaylists:
            mangaLocalPlaylistsGrid
        case .ncmPlaylists:
            mangaNCMPlaylistsGrid
        case .qcmPlaylists:
            mangaQCMPlaylistsGrid
        case .kcmPlaylists:
            mangaKCMPlaylistsGrid
        case .appleMusic:
            AppleMusicLibraryView(embeddedInParentScroll: true)
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        case .localPodcasts:
            mangaLocalPodcastsGrid
        case .ncmPodcasts:
            mangaNCMPodcastsGrid
        }
    }

    private var mangaLocalPlaylistsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.localPlaylists.title)

            if localManager.playlists.isEmpty {
                MangaEmptyPanel(icon: .musicNoteList, title: String(localized: "lib_no_local_playlists"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(localManager.playlists, id: \.id) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.localPlaylist(playlist.id)) {
                            MangaLocalPlaylistPoster(summary: localManager.summary(for: playlist))
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private var mangaNCMPlaylistsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.ncmPlaylists.title)

            if viewModel.userPlaylists.isEmpty {
                MangaEmptyPanel(icon: .list, title: String(localized: "empty_no_playlists"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                mangaPlaylistGrid(playlists: viewModel.userPlaylists, isLoading: false)
            }
        }
    }

    private var mangaQCMPlaylistsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.qcmPlaylists.title)

            if isLoadingQQUserPlaylists && qqUserPlaylists.isEmpty {
                LibraryLoadingStateView(text: "LOADING QCM", horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if !qqSession.isLoggedIn {
                MangaEmptyPanel(icon: .musicNoteList, title: String(localized: "qcm_login_required"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else if qqUserPlaylists.isEmpty {
                MangaEmptyPanel(icon: .list, title: String(localized: "暂无 QCM 歌单"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(qqUserPlaylists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            MangaPlaylistPoster(playlist: playlist, tint: MangaStyle.bubblePink)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private var mangaKCMPlaylistsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.kcmPlaylists.title)

            if !KCMMusicService.shared.isAuthenticated {
                MangaEmptyPanel(icon: .musicNoteList, title: "请先登录 KCM")
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else if viewModel.kugouUserPlaylists.isEmpty {
                MangaEmptyPanel(icon: .list, title: "暂无 KCM 歌单")
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                mangaPlaylistGrid(playlists: viewModel.kugouUserPlaylists, isLoading: false)
            }
        }
    }

    private var mangaLocalPodcastsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.localPodcasts.title)

            if subManager.localSubscribedRadios.isEmpty {
                MangaEmptyPanel(icon: .radio, title: String(localized: "暂无本地收藏"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(subManager.localSubscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            MangaPodcastPoster(radio: radio)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    subManager.removeLocalRadio(radio)
                                }
                            } label: {
                                Label(String(localized: "lib_unsubscribe"), systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private var mangaNCMPodcastsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaLibrarySectionHeader(title: MangaMyLibraryColumn.ncmPodcasts.title)

            if subManager.isLoadingRadios && subManager.subscribedRadios.isEmpty {
                LibraryLoadingStateView(text: "LOADING PODCASTS", horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if subManager.subscribedRadios.isEmpty {
                MangaEmptyPanel(icon: .radio, title: String(localized: "lib_no_podcasts"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(subManager.subscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            MangaPodcastPoster(radio: radio)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private var mangaImportActionStrip: some View {
        LazyVGrid(columns: controlColumns, spacing: 9) {
            MangaLibraryActionChip(
                title: String(localized: "lib_create"),
                icon: .add,
                tint: MangaStyle.labelYellow
            ) {
                createLocalPlaylist()
            }

            MangaLibraryActionChip(
                title: String(localized: "lib_import_playlist"),
                icon: .download,
                tint: MangaStyle.bubbleBlue,
                isLoading: isImporting
            ) {
                showFileImporter = true
            }
            .disabled(isImporting)

            MangaLibraryActionChip(
                title: String(localized: "从链接导入"),
                icon: .share,
                tint: MangaStyle.mint,
                isLoading: isImporting
            ) {
                showImportLinkPrompt()
            }
            .disabled(isImporting)

            MangaLibraryActionChip(
                title: String(localized: "QCM歌单"),
                icon: .musicNoteList,
                tint: MangaStyle.bubblePink
            ) {
                showQQImport = true
            }
        }
    }

    private var playlistSquarePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            MangaLibrarySourceStrip(
                selected: viewModel.squareSource,
                sources: [.ncm, .qq, .kugou, .appleMusic]
            ) { source in
                viewModel.squareSource = source
                viewModel.fetchSquareForSelectedSource()
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

            if viewModel.squareSource == .qq {
                qqCategoryBar
                mangaPlaylistGrid(playlists: viewModel.qqSquarePlaylists, isLoading: viewModel.isLoadingQQSquare)

                if viewModel.hasMoreQQSquare && !viewModel.qqSquarePlaylists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreQQSquarePlaylists()
                    }
                }
            } else if viewModel.squareSource == .kugou {
                kugouCategoryBar
                mangaPlaylistGrid(playlists: viewModel.kugouSquarePlaylists, isLoading: viewModel.isLoadingKugouSquare)

                if viewModel.hasMoreKugouSquare && !viewModel.kugouSquarePlaylists.isEmpty {
                    loadMorePanel { viewModel.loadMoreKugouSquarePlaylists() }
                }
            } else if viewModel.squareSource == .appleMusic {
                mangaPlaylistGrid(playlists: viewModel.appleMusicSquarePlaylists, isLoading: viewModel.isLoadingAppleMusicSquare)

                if viewModel.hasMoreAppleMusicSquare && !viewModel.appleMusicSquarePlaylists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreAppleMusicSquarePlaylists()
                    }
                }
            } else {
                ncmCategoryBar
                mangaPlaylistGrid(playlists: viewModel.squarePlaylists, isLoading: viewModel.isLoadingSquare)

                if viewModel.hasMoreSquarePlaylists && !viewModel.squarePlaylists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreSquarePlaylists()
                    }
                }
            }
        }
    }

    private var artistsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            MangaLibrarySourceStrip(
                selected: viewModel.artistSource,
                sources: [.ncm, .qq, .kugou, .appleMusic]
            ) { source in
                viewModel.artistSource = source
                viewModel.fetchArtistsForSelectedSource(reset: true)
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

            if viewModel.artistSource == .qq {
                qqArtistFilterBar
                qqArtistSexBar
                qqArtistGenreBar
                artistGrid(artists: viewModel.qqArtists, isLoading: viewModel.isLoadingQQArtists)
                if viewModel.hasMoreQQArtists && !viewModel.qqArtists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreQQArtists()
                    }
                }
            } else if viewModel.artistSource == .kugou {
                kugouArtistTypeBar
                kugouArtistSexBar
                artistGrid(artists: viewModel.kugouArtists, isLoading: viewModel.isLoadingKugouArtists)
            } else if viewModel.artistSource == .appleMusic {
                appleMusicArtistFilterBar
                artistGrid(artists: viewModel.appleMusicArtists, isLoading: viewModel.isLoadingAppleMusicArtists)
                if viewModel.hasMoreAppleMusicArtists && !viewModel.appleMusicArtists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreAppleMusicArtists()
                    }
                }
            } else {
                ncmArtistFilterBar
                ncmArtistTypeBar
                ncmArtistInitialBar
                artistGrid(artists: viewModel.topArtists, isLoading: viewModel.isLoadingArtists)
                if viewModel.hasMoreArtists && !viewModel.topArtists.isEmpty {
                    loadMorePanel {
                        viewModel.loadMoreArtists()
                    }
                }
            }
        }
    }

    private var chartsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            MangaLibrarySourceStrip(
                selected: viewModel.chartsSource,
                sources: [.ncm, .qq, .kugou, .appleMusic]
            ) { source in
                viewModel.chartsSource = source
                viewModel.fetchChartsForSelectedSource()
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

            if viewModel.chartsSource == .qq {
                if viewModel.isLoadingQQCharts && viewModel.qqTopLists.isEmpty {
                    LibraryLoadingStateView(text: "LOADING CHARTS", horizontalPadding: DeviceLayout.viewHorizontalPadding)
                } else if viewModel.qqTopLists.isEmpty {
                    MangaEmptyPanel(icon: .chart, title: String(localized: "empty_no_charts"))
                        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                } else {
                    ForEach(viewModel.qqTopLists) { group in
                        MangaLibrarySectionHeader(title: group.groupName)
                        LazyVGrid(columns: twoColumns, spacing: 14) {
                            ForEach(group.items) { item in
                                NavigationLink(value: qqChartDestination(item)) {
                                    MangaQQChartPoster(item: item)
                                }
                                .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                            }
                        }
                        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    }
                }
            } else {
                if viewModel.isLoadingDisplayedCharts && viewModel.displayedTopLists.isEmpty {
                    LibraryLoadingStateView(text: "LOADING CHARTS", horizontalPadding: DeviceLayout.viewHorizontalPadding)
                } else if viewModel.displayedTopLists.isEmpty {
                    MangaEmptyPanel(icon: .chart, title: String(localized: "empty_no_charts"))
                        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                } else {
                    MangaLibrarySectionHeader(title: String(localized: "lib_tab_charts"))
                    LazyVGrid(columns: twoColumns, spacing: 14) {
                        ForEach(viewModel.displayedTopLists) { list in
                            NavigationLink(value: chartDestination(list)) {
                                MangaChartPoster(list: list)
                            }
                            .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                        }
                    }
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                }
            }
        }
    }

    private var ncmCategoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Array(viewModel.playlistCategories.prefix(18)), id: \.idString) { category in
                    MangaFilterChip(
                        title: category.name,
                        selected: viewModel.selectedCategory == category.name,
                        tint: MangaStyle.labelYellow
                    ) {
                        viewModel.selectedCategory = category.name
                        viewModel.loadSquarePlaylists(cat: category.name, reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var qqCategoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Array(viewModel.qqPlaylistCategories.prefix(18)), id: \.id) { category in
                    MangaFilterChip(
                        title: category.name,
                        selected: viewModel.selectedQQCategoryId == category.id,
                        tint: MangaStyle.bubbleBlue
                    ) {
                        viewModel.selectedQQCategoryId = category.id
                        viewModel.selectedQQCategoryName = category.name
                        viewModel.loadQQSquarePlaylists(categoryId: category.id, reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var kugouCategoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Array(viewModel.kugouPlaylistCategories.prefix(18))) { category in
                    MangaFilterChip(
                        title: category.name,
                        selected: viewModel.selectedKugouCategoryID == category.id,
                        tint: MusicSource.kugou.themedBadgeColor
                    ) {
                        viewModel.selectKugouCategory(category)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    private var ncmArtistFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.artistAreas, id: \.value) { area in
                    MangaFilterChip(
                        title: NSLocalizedString(area.name, comment: ""),
                        selected: viewModel.artistArea == area.value,
                        tint: MangaStyle.mint
                    ) {
                        viewModel.artistArea = area.value
                        viewModel.fetchArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var kugouArtistTypeBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.kugouArtistTypes, id: \.value) { type in
                    MangaFilterChip(
                        title: NSLocalizedString(type.name, comment: ""),
                        selected: viewModel.kugouArtistType == type.value,
                        tint: MusicSource.kugou.themedBadgeColor
                    ) {
                        viewModel.kugouArtistType = type.value
                        viewModel.fetchKugouArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    private var kugouArtistSexBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.kugouArtistSexes, id: \.value) { sex in
                    MangaFilterChip(
                        title: NSLocalizedString(sex.name, comment: ""),
                        selected: viewModel.kugouArtistSex == sex.value,
                        tint: MangaStyle.mint
                    ) {
                        viewModel.kugouArtistSex = sex.value
                        viewModel.fetchKugouArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    private var appleMusicArtistFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Array(viewModel.appleMusicArtistCategories.enumerated()), id: \.offset) { index, category in
                    MangaFilterChip(
                        title: NSLocalizedString(category.name, comment: ""),
                        selected: viewModel.appleMusicArtistCategory == index,
                        tint: MusicSource.appleMusic.themedBadgeColor
                    ) {
                        viewModel.selectAppleMusicArtistCategory(index)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
        .themeRenderScrollLayer()
    }

    private var ncmArtistTypeBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.artistTypes, id: \.value) { type in
                    MangaFilterChip(
                        title: NSLocalizedString(type.name, comment: ""),
                        selected: viewModel.artistType == type.value,
                        tint: MangaStyle.bubbleBlue
                    ) {
                        viewModel.artistType = type.value
                        viewModel.fetchArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var ncmArtistInitialBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.artistInitials, id: \.self) { initial in
                    MangaFilterChip(
                        title: initial == "-1" ? NSLocalizedString("search_hot", comment: "") : initial,
                        selected: viewModel.artistInitial == initial,
                        tint: MangaStyle.labelYellow
                    ) {
                        viewModel.artistInitial = initial
                        viewModel.fetchArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var qqArtistFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.qqArtistAreas, id: \.value) { area in
                    MangaFilterChip(
                        title: NSLocalizedString(area.name, comment: ""),
                        selected: viewModel.qqArtistArea == area.value,
                        tint: MangaStyle.bubblePink
                    ) {
                        viewModel.qqArtistArea = area.value
                        viewModel.fetchQQArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var qqArtistSexBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.qqArtistSexes, id: \.value) { sex in
                    MangaFilterChip(
                        title: NSLocalizedString(sex.name, comment: ""),
                        selected: viewModel.qqArtistSex == sex.value,
                        tint: MangaStyle.labelYellow
                    ) {
                        viewModel.qqArtistSex = sex.value
                        viewModel.fetchQQArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private var qqArtistGenreBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(viewModel.qqArtistGenres, id: \.value) { genre in
                    MangaFilterChip(
                        title: NSLocalizedString(genre.name, comment: ""),
                        selected: viewModel.qqArtistGenre == genre.value,
                        tint: MangaStyle.mint
                    ) {
                        viewModel.qqArtistGenre = genre.value
                        viewModel.fetchQQArtistData(reset: true)
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private func mangaPlaylistGrid(playlists: [Playlist], isLoading: Bool) -> some View {
        Group {
            if isLoading && playlists.isEmpty {
                LibraryLoadingStateView(text: "LOADING PLAYLISTS", horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if playlists.isEmpty {
                MangaEmptyPanel(icon: .list, title: String(localized: "empty_no_playlists"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            MangaPlaylistPoster(
                                playlist: playlist,
                                tint: playlist.isKugou
                                    ? MusicSource.kugou.themedBadgeColor
                                    : (playlist.isQQMusic ? MangaStyle.bubbleBlue : MangaStyle.labelYellow)
                            )
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private func artistGrid(artists: [ArtistInfo], isLoading: Bool) -> some View {
        Group {
            if isLoading && artists.isEmpty {
                LibraryLoadingStateView(text: "LOADING ARTISTS", horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if artists.isEmpty {
                MangaEmptyPanel(icon: .personCircle, title: String(localized: "artist_no_similar"))
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            } else {
                LazyVGrid(columns: threeColumns, spacing: 15) {
                    ForEach(artists) { artist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.artistInfo(artist)) {
                            MangaArtistPoster(artist: artist)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            }
        }
    }

    private func loadMorePanel(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MangaLabel(text: String(localized: "common_view_more"), tint: MangaStyle.decoBlue, small: true)
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 50)
        .padding(.top, 6)
        .padding(.bottom, 78)
    }

    private func selectTab(_ tab: LibraryViewModel.LibraryTab, index: Int) {
        tabIndex = index
        viewModel.currentTab = tab
        load(tab)
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
            loadQQUserPlaylistsIfNeeded()
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
                AppLogger.error("[MangaLibrary] 加载 QCM 歌单失败: \(error)")
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
                AlertManager.shared.show(
                    title: String(localized: "lib_import_failed"),
                    message: String(localized: "lib_import_no_songs"),
                    primaryButtonTitle: String(localized: "lib_confirm"),
                    primaryAction: {}
                )
                isImporting = false
                return
            }

            Task {
                var allSongs: [Song] = []
                let batchSize = 50

                for i in stride(from: 0, to: ids.count, by: batchSize) {
                    let batch = Array(ids[i ..< min(i + batchSize, ids.count)])
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
                        AlertManager.shared.show(
                            title: String(localized: "lib_import_failed"),
                            message: String(localized: "lib_import_fetch_failed"),
                            primaryButtonTitle: String(localized: "lib_confirm"),
                            primaryAction: {}
                        )
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            }
        } catch {
            AlertManager.shared.show(
                title: String(localized: "lib_import_failed"),
                message: error.localizedDescription,
                primaryButtonTitle: String(localized: "lib_confirm"),
                primaryAction: {}
            )
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
            AlertManager.shared.show(
                title: String(localized: "lib_import_failed"),
                message: String(localized: "无法识别的歌单链接"),
                primaryButtonTitle: String(localized: "lib_confirm"),
                primaryAction: {}
            )
            isImporting = false
        }
    }

    private func extractQQPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist/(\d+)"#, options: .regularExpression) {
            let match = url[range]
            let digits = match.replacingOccurrences(of: "playlist/", with: "")
            return Int(digits)
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("y.qq.com") {
            let match = String(url[range])
            let digits = match.replacingOccurrences(of: "id=", with: "")
            return Int(digits)
        }
        return nil
    }

    private func extractNCMPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist\?id=(\d+)"#, options: .regularExpression) {
            let match = String(url[range])
            let digits = match.replacingOccurrences(of: "playlist?id=", with: "")
            return Int(digits)
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("music.163.com") {
            let match = String(url[range])
            let digits = match.replacingOccurrences(of: "id=", with: "")
            return Int(digits)
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
                    if songs.count < 50 { hasMore = false }
                    page += 1
                }

                await MainActor.run {
                    if allSongs.isEmpty {
                        AlertManager.shared.show(
                            title: String(localized: "lib_import_failed"),
                            message: String(localized: "playlist_empty_or_load_failed"),
                            primaryButtonTitle: String(localized: "lib_confirm"),
                            primaryAction: {}
                        )
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    AlertManager.shared.show(
                        title: String(localized: "lib_import_failed"),
                        message: L10n.format(
                            "qcm_playlist_import_failed_format",
                            error.localizedDescription
                        ),
                        primaryButtonTitle: String(localized: "lib_confirm"),
                        primaryAction: {}
                    )
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
                    if songs.count < limit { hasMore = false }
                    offset += limit
                } catch {
                    hasMore = false
                }
            }

            await MainActor.run {
                if allSongs.isEmpty {
                    AlertManager.shared.show(
                        title: String(localized: "lib_import_failed"),
                        message: String(localized: "playlist_empty_or_load_failed"),
                        primaryButtonTitle: String(localized: "lib_confirm"),
                        primaryAction: {}
                    )
                } else {
                    localManager.importPlaylist(name: String(localized: "NCM歌单"), songs: allSongs)
                }
                isImporting = false
            }
        }
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
        case .my: return MangaStyle.labelYellow
        case .square: return MangaStyle.bubbleBlue
        case .artists: return MangaStyle.mint
        case .charts: return MangaStyle.bubblePink
        }
    }

    private func tabForeground(for tab: LibraryViewModel.LibraryTab, selected: Bool) -> Color {
        guard selected else { return MangaStyle.ink }
        return ThemeColorCustomization.readableForegroundColor(
            on: tint(for: tab),
            light: MangaStyle.strokeInk,
            dark: MangaStyle.onStrokeInk
        )
    }

    private func chartDestination(_ list: TopList) -> LibraryViewModel.NavigationDestination {
        .playlist(list.playlist())
    }

    private func qqChartDestination(_ item: QQTopListItem) -> LibraryViewModel.NavigationDestination {
        .playlist(Playlist(
            id: item.topId,
            name: item.title,
            coverImgUrl: item.coverUrl,
            picUrl: nil,
            trackCount: nil,
            playCount: nil,
            subscribedCount: nil,
            shareCount: nil,
            commentCount: nil,
            creator: nil,
            description: item.intro.isEmpty ? nil : item.intro,
            tags: nil,
            source: .qqmusic,
            isTopList: true
        ))
    }
}

struct MangaLibrarySectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        MangaSectionTitle(
            title: title,
            actionTitle: actionTitle,
            mark: .star,
            action: action
        )
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        .padding(.top, 4)
    }
}

struct MangaLibrarySourceStrip: View {
    let selected: LibraryViewModel.MusicSource
    let sources: [LibraryViewModel.MusicSource]
    let onSelect: (LibraryViewModel.MusicSource) -> Void

    init(
        selected: LibraryViewModel.MusicSource,
        firstTitle: String = "NCM",
        secondTitle: String = "QCM",
        sources: [LibraryViewModel.MusicSource]? = nil,
        onSelect: @escaping (LibraryViewModel.MusicSource) -> Void
    ) {
        self.selected = selected
        self.sources = sources ?? [.ncm, .qq]
        self.onSelect = onSelect
    }

    var body: some View {
        // 去卡片化：印章式源切换，选中为实色小章，未选中为纯文字
        HStack(spacing: 14) {
            ForEach(sources, id: \.self) { source in
                sourceButton(title: sourceTitle(source), source: source, tint: sourceTint(source))
            }
            Spacer(minLength: 0)
        }
    }

    private func sourceTitle(_ source: LibraryViewModel.MusicSource) -> String {
        switch source {
        case .ncm: return "NCM"
        case .qq: return "QCM"
        case .kugou: return "KCM"
        case .appleMusic: return "AM"
        }
    }

    private func sourceTint(_ source: LibraryViewModel.MusicSource) -> Color {
        switch source {
        case .ncm: return MusicSource.netease.themedBadgeColor
        case .qq: return MusicSource.qqmusic.themedBadgeColor
        case .kugou: return MusicSource.kugou.themedBadgeColor
        case .appleMusic: return MusicSource.appleMusic.themedBadgeColor
        }
    }

    private func sourceButton(title: String, source: LibraryViewModel.MusicSource, tint: Color) -> some View {
        Button {
            onSelect(source)
        } label: {
            Text(title)
                .font(MangaStyle.labelFont(12, weight: .black))
                .tracking(0.6)
                .foregroundStyle(
                    selected == source
                        ? ThemeColorCustomization.readableForegroundColor(on: tint, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk)
                        : MangaStyle.inkMuted
                )
                .padding(.horizontal, selected == source ? 14 : 2)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected == source ? tint : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MangaLibraryActionChip: View {
    let title: String
    let icon: MonoIcon.IconType
    var tint: Color
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.72)
                        .frame(width: 16, height: 16)
                } else {
                    MonoIcon(icon: icon, size: 16, color: chipForeground, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(MangaStyle.labelFont(12, weight: .black))
                    .foregroundStyle(chipForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                    .fill(tint.opacity(0.92))
            )
            .clipShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous))
            .compositingGroup()
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
    }

    private var chipForeground: Color {
        ThemeColorCustomization.readableForegroundColor(on: tint, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk)
    }
}

struct MangaFilterChip: View {
    let title: String
    let selected: Bool
    var tint: Color
    let action: () -> Void

    var body: some View {
        // 去卡片化筛选签：未选中纯文字，选中盖一枚实色小章
        Button(action: action) {
            Text(title)
                .font(MangaStyle.labelFont(11, weight: .black))
                .foregroundStyle(
                    selected
                        ? ThemeColorCustomization.readableForegroundColor(on: tint, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk)
                        : MangaStyle.inkSub
                )
                .lineLimit(1)
                .padding(.horizontal, selected ? 12 : 4)
                .frame(minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? tint : Color.clear)
                )
                .contentShape(Rectangle())
                .compositingGroup()
        }
        .buttonStyle(.plain)
    }
}

struct MangaPodcastPoster: View {
    let radio: RadioStation

    var body: some View {
        MangaPosterShell(tint: MangaStyle.mint.opacity(0.92)) {
            VStack(alignment: .leading, spacing: 10) {
                MangaSquareArtwork {
                    CachedAsyncImage(url: radio.coverUrl?.sized(300)) {
                        RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                            .fill(MangaStyle.paperCool)
                            .overlay(MangaDotsTexture(opacity: 0.04, gap: 10))
                            .overlay(
                                MonoIcon(icon: .radio, size: 30, color: MangaStyle.inkSub, lineWidth: 1.8)
                            )
                    }
                }

                Text(radio.name)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.ink)
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                MangaLabel(text: radio.category ?? radio.dj?.nickname ?? "PODCAST", tint: MangaStyle.labelYellow, small: true)
            }
        }
    }
}

struct MangaLocalPlaylistPoster: View {
    let summary: LocalPlaylistSummary

    var body: some View {
        MangaPosterShell(tint: summary.isFavorite ? MangaStyle.bubblePink : (summary.isDownload ? MangaStyle.bubbleBlue : MangaStyle.bubbleWhite)) {
            VStack(alignment: .leading, spacing: 10) {
                cover

                Text(summary.name)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.ink)
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                MangaLabel(text: "\(summary.trackCount) \(String(localized: "songs_unit"))", tint: MangaStyle.mint, small: true)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        MangaSquareArtwork {
            if let url = summary.displayCoverUrl {
                CachedAsyncImage(url: url.sized(300)) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LocalPlaylistPlaceholderArtwork()
    }
}

struct MangaPlaylistPoster: View {
    let playlist: Playlist
    var tint: Color

    var body: some View {
        MangaPosterShell(tint: tint.opacity(0.9)) {
            VStack(alignment: .leading, spacing: 10) {
                MangaSquareArtwork {
                    CachedAsyncImage(url: playlist.coverUrl?.sized(400)) {
                        RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                            .fill(MangaStyle.paperCool)
                            .overlay(MangaDotsTexture(opacity: 0.04, gap: 10))
                    }
                }

                Text(playlist.name)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.ink)
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                HStack(spacing: 6) {
                    if let count = playlist.trackCount {
                        MangaLabel(text: "\(count)", tint: MangaStyle.mint, small: true)
                    }
                    if let playCount = playlist.playCount {
                        MangaLabel(text: mangaFormatCount(playCount), tint: MangaStyle.bubblePink, small: true, foreground: MangaStyle.ink)
                    }
                }
            }
        }
    }
}

struct MangaArtistPoster: View {
    let artist: ArtistInfo

    var body: some View {
        VStack(spacing: 9) {
            MangaSquareArtwork(cornerRadius: MangaStyle.cardRadius + 2) {
                CachedAsyncImage(url: artist.coverUrl?.sized(300)) {
                    RoundedRectangle(cornerRadius: MangaStyle.cardRadius + 2, style: .continuous)
                        .fill(MangaStyle.paperCool)
                        .overlay(MangaDotsTexture(opacity: 0.05, gap: 10))
                }
            }

            Text(artist.name)
                .font(MangaStyle.bodyFont(12, weight: .black))
                .foregroundStyle(MangaStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct MangaChartPoster: View {
    let list: TopList

    var body: some View {
        MangaPosterShell(tint: MangaStyle.bubblePink) {
            VStack(alignment: .leading, spacing: 10) {
                MangaSquareArtwork {
                    CachedAsyncImage(url: list.coverUrl?.sized(400)) {
                        RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                            .fill(MangaStyle.paperCool)
                    }
                }

                Text(list.name)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.ink)
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                MangaLabel(text: list.updateFrequency.isEmpty ? "CHART" : list.updateFrequency, tint: MangaStyle.labelYellow, small: true)
            }
        }
    }
}

struct MangaQQChartPoster: View {
    let item: QQTopListItem

    var body: some View {
        MangaPosterShell(tint: MangaStyle.bubbleBlue) {
            VStack(alignment: .leading, spacing: 10) {
                MangaSquareArtwork {
                    CachedAsyncImage(url: item.coverURL?.sized(400)) {
                        RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                            .fill(MangaStyle.paperCool)
                    }
                }

                Text(item.title)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.ink)
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                MangaLabel(text: item.period.isEmpty ? "QCM" : item.period, tint: MangaStyle.labelYellow, small: true)
            }
        }
    }
}

struct MangaSquareArtwork<Content: View>: View {
    var cornerRadius: CGFloat = MangaStyle.cardRadius
    let content: Content

    init(cornerRadius: CGFloat = MangaStyle.cardRadius, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.fineStrokeWidth)
        )
    }
}

struct MangaPosterShell<Content: View>: View {
    var tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        // 去卡片化：图文直接排在纸面上，封面自带照片框
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MangaEmptyPanel: View {
    let icon: MonoIcon.IconType
    let title: String

    var body: some View {
        // 去卡片化空态：上下细规则线之间的居中排版
        VStack(spacing: 0) {
            Rectangle()
                .fill(MangaStyle.strokeInk.opacity(0.22))
                .frame(height: 1)

            VStack(spacing: 10) {
                MonoIcon(icon: icon, size: 32, color: MangaStyle.inkMuted, lineWidth: 1.8)
                Text(title)
                    .font(MangaStyle.bodyFont(14, weight: .black))
                    .foregroundStyle(MangaStyle.inkSub)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)

            Rectangle()
                .fill(MangaStyle.strokeInk.opacity(0.22))
                .frame(height: 1)
        }
    }
}

func mangaFormatCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f亿", Double(count) / 100_000_000)
    }
    if count >= 10000 {
        return String(format: "%.1f万", Double(count) / 10000)
    }
    return "\(count)"
}
