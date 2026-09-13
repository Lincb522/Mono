import QQMusicKit
import SwiftUI

struct ClarityLibraryView: View {
    private enum PersonalLibrarySection: String, CaseIterable {
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
            case .qcmPlaylists: return String(localized: "lib_qcm_playlists")
            case .kcmPlaylists: return String(localized: "lib_kcm_playlists")
            case .appleMusic: return String(localized: "apple_music_library")
            case .localPodcasts: return String(localized: "lib_local_podcasts")
            case .ncmPodcasts: return String(localized: "lib_ncm_podcasts")
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

    @StateObject private var model = LibraryViewModel()
    @ObservedObject private var localManager = LocalPlaylistManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var qqSession = QQUserSession.shared
    @ObservedObject private var loginIdentity = LoginIdentityManager.shared
    @State private var tab: LibraryViewModel.LibraryTab = .my
    @State private var personalSection: PersonalLibrarySection = .localPlaylists
    @State private var qcmPlaylists: [Playlist] = []
    @State private var isLoadingQCMPlaylists = false
    @State private var hasLoadedQCMPlaylists = false
    @State private var qqPlaylistRequest = LibraryRequestScope()

    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            GeometryReader { viewport in
                let artworkSize = libraryArtworkSize(for: viewport.size.width)

                ZStack {
                    ClarityBackdrop()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            header
                            tabPicker
                            if tab == .my {
                                personalSectionPicker
                            } else {
                                sourcePicker
                            }
                            bodyContent(artworkSize: artworkSize)
                            FloatingBarBottomSpacer()
                        }
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DeviceLayout.headerTopPadding + 8)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { reload(force: true) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themeRenderScrollLayer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryViewModel.NavigationDestination.self) { destination in
                switch destination {
                case .playlist, .localPlaylist:
                    destinationView(destination).clarityDetailChrome(preservesImmersiveBackdrop: true)
                default:
                    destinationView(destination).clarityDetailChrome()
                }
            }
        }
        .onChange(of: tab) { _, value in
            guard MainTabActivationGate.isSettled(.library) else { return }
            model.currentTab = value
            reload(force: false)
        }
        .onChange(of: personalSection) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
            loadPersonalSection(force: false)
        }
        .onDisappear {
            qqPlaylistRequest.cancel()
            isLoadingQCMPlaylists = false
        }
        .onChange(of: qqSession.sessionRevision) { _, _ in
            qqPlaylistRequest.cancel()
            qcmPlaylists = []
            hasLoadedQCMPlaylists = false
            isLoadingQCMPlaylists = false
            if qqSession.isLoggedIn, personalSection == .qcmPlaylists {
                loadQCMPlaylists(force: true)
            }
        }
        .onChange(of: loginIdentity.activeSource) { _, _ in
            guard MainTabActivationGate.isSettled(.library) else { return }
            selectActiveIdentityLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SwitchToLibrarySquare"))) { notification in
            let source = notification.object as? LibraryViewModel.MusicSource
            Task { @MainActor in
                guard await MainTabActivationGate.waitUntilSettled(.library) else { return }
                if let source {
                    model.squareSource = source
                }
                tab = .square
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SwitchToLibraryArtists"))) { _ in
            Task { @MainActor in
                guard await MainTabActivationGate.waitUntilSettled(.library) else { return }
                tab = .artists
            }
        }
        .task {
            guard await MainTabActivationGate.waitUntilSettled(.library) else { return }
            selectActiveIdentityLibrary()
            reload(force: false)
        }
    }

    private var header: some View {
        HStack {
            Text(String(localized: "tabbar_library"))
                .font(ClarityStyle.title(23, weight: .semibold))
                .foregroundStyle(ClarityStyle.ink)
            Spacer()
            NavigationLink(value: LibraryViewModel.NavigationDestination.externalPlaylistImport) {
                MonoIcon(icon: .add, size: 18, color: ClarityStyle.ink, lineWidth: 1.7)
                    .frame(width: 44, height: 44)
                    .background(ClarityMembrane(shape: Circle(), strength: .regular))
            }
            .buttonStyle(ClarityPressStyle())
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
        .monoPageHeaderCollapse()
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(LibraryViewModel.LibraryTab.allCases, id: \.rawValue) { item in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { tab = item }
                } label: {
                    Text(item.localizedKey)
                        .font(ClarityStyle.body(11.5, weight: tab == item ? .bold : .medium))
                        .foregroundStyle(tab == item ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if tab == item {
                                ClaritySelectionLens(shape: Capsule())
                                    .matchedGeometryEffect(id: "clarity-library-tab", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(ClarityMembrane(shape: Capsule(), strength: .regular))
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    @Namespace private var tabNamespace

    private var personalSectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(PersonalLibrarySection.allCases, id: \.rawValue) { section in
                    let selected = personalSection == section

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            personalSection = section
                        }
                    } label: {
                        HStack(spacing: 6) {
                            MonoIcon(
                                icon: section.icon,
                                size: 13,
                                color: selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft,
                                lineWidth: selected ? 1.7 : 1.45
                            )
                            Text(section.title)
                                .font(ClarityStyle.body(11, weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background {
                            if selected {
                                ClaritySelectionLens(shape: Capsule())
                            } else {
                                ClarityMembrane(shape: Capsule(), strength: .quiet)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(LibraryViewModel.MusicSource.allCases, id: \.rawValue) { source in
                    Button {
                        switch tab {
                        case .square: model.squareSource = source
                        case .artists: model.artistSource = source
                        case .charts: model.chartsSource = source
                        case .my: break
                        }
                        reload(force: false)
                    } label: {
                        Text(source.shortName)
                            .font(ClarityStyle.body(11, weight: .semibold))
                            .foregroundStyle(activeSource == source ? ClarityStyle.ink : ClarityStyle.inkFaint)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(ClarityMembrane(shape: Capsule(), strength: activeSource == source ? .regular : .quiet, selected: activeSource == source))
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func bodyContent(artworkSize: CGFloat) -> some View {
        switch tab {
        case .my: personalLibraryContent(artworkSize: artworkSize)
        case .square: playlistGrid(squarePlaylists, title: String(localized: "lib_tab_playlists"), artworkSize: artworkSize)
        case .artists: artistsGrid
        case .charts: chartGrid(artworkSize: artworkSize)
        }
    }

    @ViewBuilder
    private func personalLibraryContent(artworkSize: CGFloat) -> some View {
        switch personalSection {
        case .localPlaylists:
            localPlaylistGrid(artworkSize: artworkSize)
        case .ncmPlaylists:
            playlistGrid(
                model.userPlaylists,
                title: String(localized: "lib_netease_playlists"),
                artworkSize: artworkSize
            )
        case .qcmPlaylists:
            if !qqSession.isLoggedIn {
                statusSection(
                    title: String(localized: "lib_qcm_playlists"),
                    icon: .musicNoteList,
                    message: String(localized: "qcm_login_required")
                )
            } else {
                playlistGrid(
                    qcmPlaylists,
                    title: String(localized: "lib_qcm_playlists"),
                    artworkSize: artworkSize,
                    isLoading: isLoadingQCMPlaylists
                )
            }
        case .kcmPlaylists:
            if !KCMMusicService.shared.isAuthenticated {
                statusSection(
                    title: String(localized: "lib_kcm_playlists"),
                    icon: .musicNoteList,
                    message: String(localized: "kcm_login_required")
                )
            } else {
                playlistGrid(
                    model.kugouUserPlaylists,
                    title: String(localized: "lib_kcm_playlists"),
                    artworkSize: artworkSize
                )
            }
        case .appleMusic:
            VStack(alignment: .leading, spacing: 15) {
                ClaritySectionHeading(title: String(localized: "apple_music_library"))
                AppleMusicLibraryView(embeddedInParentScroll: true)
            }
            .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
        case .localPodcasts:
            podcastSection(
                subscriptionManager.localSubscribedRadios,
                title: String(localized: "lib_local_podcasts")
            )
        case .ncmPodcasts:
            podcastSection(
                subscriptionManager.subscribedRadios,
                title: String(localized: "lib_ncm_podcasts"),
                isLoading: subscriptionManager.isLoadingRadios
            )
        }
    }

    private func playlistGrid(
        _ playlists: [Playlist],
        title: String,
        artworkSize: CGFloat,
        isLoading: Bool? = nil
    ) -> some View {
        let showsLoading = isLoading ?? model.isLoading

        return VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: title)
            if playlists.isEmpty && showsLoading {
                ProgressView().tint(ClarityStyle.accent).frame(maxWidth: .infinity).padding(.vertical, 80)
            } else if playlists.isEmpty {
                emptyState(icon: .musicNoteList, title: String(localized: "library_empty_playlists"))
            } else {
                LazyVGrid(columns: grid, spacing: 20) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            VStack(alignment: .leading, spacing: 9) {
                                ClarityArtwork(url: playlist.coverUrl, size: artworkSize, radius: 27)
                                Text(playlist.name)
                                    .font(ClarityStyle.body(13, weight: .semibold))
                                    .foregroundStyle(ClarityStyle.ink)
                                    .lineLimit(2)
                                HStack(spacing: 5) {
                                    Text(playlist.sourceShortName)
                                    if let count = playlist.trackCount { Text("· \(count)") }
                                }
                                .font(ClarityStyle.body(10.5, weight: .medium))
                                .foregroundStyle(ClarityStyle.inkFaint)
                            }
                        }
                        .buttonStyle(ClarityPressStyle())
                    }
                }
            }
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private func localPlaylistGrid(artworkSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: String(localized: "lib_local_playlists"))

            if localManager.playlists.isEmpty {
                emptyState(icon: .musicNoteList, title: String(localized: "lib_no_local_playlists"))
            } else {
                LazyVGrid(columns: grid, spacing: 20) {
                    ForEach(localManager.playlists, id: \.id) { playlist in
                        let summary = localManager.summary(for: playlist)

                        NavigationLink(value: LibraryViewModel.NavigationDestination.localPlaylist(playlist.id)) {
                            VStack(alignment: .leading, spacing: 9) {
                                ClarityArtwork(url: summary.displayCoverUrl, size: artworkSize, radius: 27)
                                Text(summary.name)
                                    .font(ClarityStyle.body(13, weight: .semibold))
                                    .foregroundStyle(ClarityStyle.ink)
                                    .lineLimit(2)
                                Text(String(format: String(localized: "songs_count_format"), summary.trackCount))
                                    .font(ClarityStyle.body(10.5, weight: .medium))
                                    .foregroundStyle(ClarityStyle.inkFaint)
                            }
                        }
                        .buttonStyle(ClarityPressStyle())
                    }
                }
            }
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private func podcastSection(
        _ radios: [RadioStation],
        title: String,
        isLoading: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: title)

            if isLoading && radios.isEmpty {
                ProgressView()
                    .tint(ClarityStyle.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
            } else if radios.isEmpty {
                emptyState(icon: .radio, title: String(localized: "lib_no_podcasts"))
            } else {
                ClarityShell(cornerRadius: 30) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(radios.enumerated()), id: \.element.id) { index, radio in
                            if index > 0 {
                                Rectangle()
                                    .fill(ClarityStyle.line)
                                    .frame(height: 1)
                                    .padding(.leading, 86)
                            }

                            NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                                podcastRow(radio)
                            }
                            .buttonStyle(ClarityPressStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private func podcastRow(_ radio: RadioStation) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: radio.coverUrl?.sized(300), width: 58, height: 58) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(ClarityStyle.membraneQuiet)
                    .overlay(MonoIcon(icon: .radio, size: 19, color: ClarityStyle.inkFaint, lineWidth: 1.4))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(radio.name)
                    .font(ClarityStyle.body(14, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                    .lineLimit(2)
                Text(radio.dj?.nickname ?? radio.category ?? String(localized: "tabbar_podcast"))
                    .font(ClarityStyle.body(11))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            MonoIcon(icon: .chevronRight, size: 12, color: ClarityStyle.inkFaint, lineWidth: 1.4)
                .frame(width: 36, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func statusSection(
        title: String,
        icon: MonoIcon.IconType,
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: title)
            emptyState(icon: icon, title: message)
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private var artistsGrid: some View {
        VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: String(localized: "lib_tab_artists"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 16)], spacing: 21) {
                ForEach(displayedArtists, id: \.id) { artist in
                    NavigationLink(value: LibraryViewModel.NavigationDestination.artistInfo(artist)) {
                        VStack(spacing: 10) {
                            ClarityArtwork(url: artist.coverUrl, size: 96, radius: 48)
                            Text(artist.name)
                                .font(ClarityStyle.body(12.5, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
            if displayedArtists.isEmpty { emptyState(icon: .profile, title: String(localized: "library_empty_artists")) }
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private func chartGrid(artworkSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ClaritySectionHeading(title: String(localized: "lib_tab_charts"))
            if model.isLoadingDisplayedCharts && model.displayedTopLists.isEmpty {
                LibraryLoadingStateView()
            } else if model.displayedTopLists.isEmpty {
                emptyState(icon: .chart, title: String(localized: "empty_no_charts"))
            }
            LazyVGrid(columns: grid, spacing: 20) {
                ForEach(model.displayedTopLists) { chart in
                    let playlist = chart.playlist(description: chart.updateFrequency)
                    NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                        VStack(alignment: .leading, spacing: 9) {
                            ClarityArtwork(url: chart.coverUrl, size: artworkSize, radius: 27)
                            Text(chart.name).font(ClarityStyle.body(13, weight: .semibold)).foregroundStyle(ClarityStyle.ink).lineLimit(1)
                            Text(chart.updateFrequency).font(ClarityStyle.body(10.5)).foregroundStyle(ClarityStyle.inkFaint).lineLimit(1)
                        }
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
    }

    private func emptyState(icon: MonoIcon.IconType, title: String) -> some View {
        VStack(spacing: 12) {
            MonoIcon(icon: icon, size: 24, color: ClarityStyle.inkFaint, lineWidth: 1.5)
                .frame(width: 58, height: 58)
                .background(ClarityMembrane(shape: Circle(), strength: .regular))
            Text(title).font(ClarityStyle.body(13, weight: .medium)).foregroundStyle(ClarityStyle.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 74)
    }

    private var grid: [GridItem] {
        [GridItem(.flexible(), spacing: 15), GridItem(.flexible(), spacing: 15)]
    }

    private func libraryArtworkSize(for viewportWidth: CGFloat) -> CGFloat {
        let boundedWidth = min(max(viewportWidth, 320), 720)
        let available = boundedWidth - DeviceLayout.homeHorizontalPadding * 2 - 15
        return max(120, floor(available / 2))
    }

    private var squarePlaylists: [Playlist] {
        switch model.squareSource {
        case .ncm: model.squarePlaylists
        case .qq: model.qqSquarePlaylists
        case .kugou: model.kugouSquarePlaylists
        case .appleMusic: model.appleMusicSquarePlaylists
        }
    }

    private var displayedArtists: [ArtistInfo] {
        switch model.artistSource {
        case .ncm: model.topArtists
        case .qq: model.qqArtists
        case .kugou: model.kugouArtists
        case .appleMusic: model.appleMusicArtists
        }
    }

    private var activeSource: LibraryViewModel.MusicSource {
        switch tab {
        case .square: model.squareSource
        case .artists: model.artistSource
        case .charts: model.chartsSource
        case .my: .ncm
        }
    }

    private func reload(force: Bool) {
        switch tab {
        case .my:
            model.fetchPlaylists(force: force)
            loadPersonalSection(force: force)
        case .square: model.fetchSquareForSelectedSource()
        case .artists: model.fetchArtistsForSelectedSource(reset: force)
        case .charts: model.fetchChartsForSelectedSource(force: force)
        }
    }

    private func loadPersonalSection(force: Bool) {
        switch personalSection {
        case .qcmPlaylists:
            loadQCMPlaylists(force: force)
        case .ncmPodcasts:
            if force || subscriptionManager.subscribedRadios.isEmpty {
                subscriptionManager.fetchSubscribedRadios(force: force)
            }
        case .kcmPlaylists:
            if KCMMusicService.shared.isAuthenticated,
               force || model.kugouUserPlaylists.isEmpty {
                model.loadKugouUserPlaylists(force: force)
            }
        case .localPlaylists, .ncmPlaylists, .appleMusic, .localPodcasts:
            break
        }
    }

    private func selectActiveIdentityLibrary() {
        switch loginIdentity.activeSource {
        case .netease: personalSection = .ncmPlaylists
        case .qqmusic: personalSection = .qcmPlaylists
        case .kugou: personalSection = .kcmPlaylists
        case .qishui, .appleMusic, .local, nil: personalSection = .localPlaylists
        }
    }

    private func loadQCMPlaylists(force: Bool) {
        let session = qqSession.sessionSnapshot
        guard force || !hasLoadedQCMPlaylists else { return }
        guard !isLoadingQCMPlaylists else { return }
        guard session.isLoggedIn, let mid = session.musicID else {
            qcmPlaylists = []
            hasLoadedQCMPlaylists = true
            return
        }

        let request = qqPlaylistRequest.begin()
        isLoadingQCMPlaylists = true
        qqPlaylistRequest.task = Task { @MainActor in
            guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request) else { return }
            defer {
                if qqPlaylistRequest.isCurrent(request), qqSession.isCurrentSession(session) {
                    isLoadingQCMPlaylists = false
                    qqPlaylistRequest.finish(request)
                }
            }

            do {
                let result: JSON = try await QQUserSession.shared.withUserSession { client in
                    try await client.createdSonglist(uin: String(mid))
                }
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                qcmPlaylists = Self.parseQCMPlaylists(result)
                hasLoadedQCMPlaylists = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                AppLogger.error("[ClarityLibrary] 加载 QCM 歌单失败: \(error)")
            }
        }
    }

    private static func parseQCMPlaylists(_ result: JSON) -> [Playlist] {
        let list = result["playlists"]?.arrayValue
            ?? result["v_playlist"]?.arrayValue
            ?? result.arrayValue ?? []

        return list.compactMap { json in
            guard let object = json.objectValue else { return nil }
            let id = object["id"]?.intValue ?? object["tid"]?.intValue ?? 0
            let name = object["title"]?.stringValue
                ?? object["dirName"]?.stringValue
                ?? object["diss_name"]?.stringValue
                ?? ""
            let cover = object["picurl"]?.stringValue
                ?? object["picUrl"]?.stringValue
                ?? object["logo"]?.stringValue
                ?? ""
            let trackCount = object["songnum"]?.intValue
                ?? object["songNum"]?.intValue
                ?? object["song_cnt"]?.intValue
                ?? 0
            guard !name.isEmpty else { return nil }

            return Playlist(
                id: id,
                name: name,
                coverImgUrl: cover,
                picUrl: nil,
                trackCount: trackCount,
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

    @ViewBuilder
    private func destinationView(_ destination: LibraryViewModel.NavigationDestination) -> some View {
        switch destination {
        case let .playlist(playlist): PlaylistDetailView(playlist: playlist).id(playlist.navigationIdentity)
        case let .artist(id): ArtistDetailView(artistId: id)
        case let .artistInfo(artist): ArtistDetailView(artist: artist)
        case let .qqArtist(mid, name, cover): QQMusicDetailView(detailType: .artist(mid: mid, name: name, coverUrl: cover))
        case let .radioDetail(id): RadioDetailView(radioId: id)
        case let .localPlaylist(id): LocalPlaylistDetailView(playlistId: id)
        case .externalPlaylistImport: ExternalPlaylistImportView()
        }
    }
}
