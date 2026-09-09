import SwiftUI

struct ClarityLocalHomeView: View {
    @ObservedObject private var library = LocalMusicLibraryManager.shared
    @ObservedObject private var playlists = LocalPlaylistManager.shared
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                ClarityBackdrop()
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            compactHeader
                            homeShell(in: proxy)
                            FloatingBarBottomSpacer()
                        }
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 28 : 14)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                    .themeRenderScrollLayer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: LocalMusicLibraryManager.importableContentTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { _ = await library.importItems(from: urls) }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "local_home_hero_title"))
                    .font(ClarityStyle.title(23, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                Text(String(format: String(localized: "local_home_hero_subtitle"), library.songCount))
                    .font(ClarityStyle.body(11.5))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ClarityGlowButton(icon: .download, size: 43) { showImporter = true }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .monoPageHeaderCollapse()
    }

    private func homeShell(in proxy: GeometryProxy) -> some View {
        ClarityShell(cornerRadius: DeviceLayout.usesExpandedLayout ? 38 : 32) {
            VStack(spacing: 0) {
                localBanner(width: min(proxy.size.width - 28, 680))
                quickAccess
                Rectangle().fill(ClarityStyle.line).frame(height: 1)

                if let progress = library.importProgress {
                    importProgress(progress)
                } else if library.songs.isEmpty {
                    emptyLibrary
                } else {
                    recentSongs
                }

                if !playlists.playlists.isEmpty {
                    Rectangle().fill(ClarityStyle.line).frame(height: 1).padding(.horizontal, 20)
                    playlistStrip
                }
            }
        }
    }

    private func localBanner(width: CGFloat) -> some View {
        let song = library.songs.first
        let height = min(max(width * 0.43, 154), 206)

        return ZStack {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "E9ECEE"), Color(hex: "DDE5E8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(ClarityStyle.cyan.opacity(0.20))
                .frame(width: height * 1.12)
                .blur(radius: 34)
                .offset(x: width * 0.32, y: -height * 0.20)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(String(localized: "tabbar_local_music"))
                        .font(ClarityStyle.title(min(24, width * 0.063), weight: .semibold))
                        .foregroundStyle(ClarityStyle.ink)
                    Text("\(library.songCount)")
                        .font(ClarityStyle.title(min(34, width * 0.086), weight: .regular))
                        .foregroundStyle(ClarityStyle.ink)
                    Text(String(localized: "clarity_recent_added"))
                        .font(ClarityStyle.body(11.5))
                        .foregroundStyle(ClarityStyle.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ClarityArtwork(url: song?.coverUrl, size: min(height * 0.66, 132), radius: 24)
                    .rotationEffect(.degrees(-2.2))
                    .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)
                    .overlay(alignment: .bottomTrailing) {
                        NavigationLink(destination: ClarityLocalMusicContent(isRoot: false).monoNavigationBackButton(iconColor: ClarityStyle.ink).clarityDetailChrome()) {
                            MonoIcon(icon: .chevronRight, size: 16, color: ClarityStyle.ink, lineWidth: 1.6)
                                .frame(width: 43, height: 43)
                                .background(ClarityMembrane(shape: Circle(), strength: .strong))
                        }
                        .buttonStyle(ClarityPressStyle())
                        .offset(x: 10, y: 8)
                    }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: height)
        .padding(12)
    }

    private var quickAccess: some View {
        HStack(spacing: 0) {
            localShortcut(.musicNoteList, "local_filter_all", ClarityLocalMusicContent(isRoot: false).monoNavigationBackButton(iconColor: ClarityStyle.ink).clarityDetailChrome())
            localShortcut(.liked, "local_filter_favorites", LocalMusicView(initialFilter: .favorites).clarityDetailChrome())
            localShortcut(.history, "local_filter_recent", LocalMusicView(initialFilter: .recent).clarityDetailChrome())
            localShortcut(.download, "local_filter_downloads", LocalMusicView(initialFilter: .downloads).clarityDetailChrome())
        }
        .padding(.horizontal, 12)
        .padding(.top, 3)
        .padding(.bottom, 14)
    }

    private func localShortcut<Destination: View>(
        _ icon: MonoIcon.IconType,
        _ key: String,
        _ destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 6) {
                MonoIcon(icon: icon, size: 17, color: ClarityStyle.ink, lineWidth: 1.5)
                    .frame(width: 42, height: 42)
                    .background(ClarityMembrane(shape: Circle(), strength: .quiet))
                Text(String(localized: String.LocalizationValue(key)))
                    .font(ClarityStyle.body(9.5, weight: .medium))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ClarityPressStyle())
    }

    private var emptyLibrary: some View {
        Button { showImporter = true } label: {
            VStack(spacing: 10) {
                ClarityGlowButton(icon: .download, size: 56, action: { showImporter = true })
                    .allowsHitTesting(false)
                Text(String(localized: "local_empty_music_title"))
                    .font(ClarityStyle.body(14, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                Text(String(localized: "local_empty_music_subtitle"))
                    .font(ClarityStyle.body(11.5))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(ClarityStyle.line, style: StrokeStyle(lineWidth: 0.8, dash: [5, 6]))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
        .buttonStyle(ClarityPressStyle())
    }

    private func importProgress(_ progress: LocalMusicLibraryManager.ImportProgress) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(String(localized: "local_action_import_title"))
                    .font(ClarityStyle.body(13, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                Spacer()
                Text(progress.countText)
                    .font(ClarityStyle.body(10.5, weight: .medium))
                    .foregroundStyle(ClarityStyle.inkSoft)
            }
            GeometryReader { geometry in
                Capsule().fill(ClarityStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ClarityStyle.accent)
                            .frame(width: geometry.size.width * progress.fraction)
                    }
            }
            .frame(height: 4)
        }
        .padding(20)
    }

    private var recentSongs: some View {
        VStack(alignment: .leading, spacing: 7) {
            ClaritySectionHeading(title: String(localized: "clarity_recent_added"))
            ForEach(Array(library.songs.prefix(4).enumerated()), id: \.element.identityKey) { index, song in
                claritySongRow(index: index, song: song, songs: library.songs)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var playlistStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClaritySectionHeading(title: String(localized: "clarity_local_playlists"))
            ScrollView(.horizontal) {
                HStack(spacing: 13) {
                    ForEach(playlists.playlists, id: \.id) { playlist in
                        let summary = playlists.summary(for: playlist)
                        NavigationLink(destination: LocalPlaylistDetailView(playlistId: playlist.id).clarityDetailChrome(preservesImmersiveBackdrop: true)) {
                            HStack(spacing: 10) {
                                ClarityArtwork(url: summary.displayCoverUrl, size: 58, radius: 17)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(ClarityStyle.body(12.5, weight: .semibold))
                                        .foregroundStyle(ClarityStyle.ink)
                                        .lineLimit(1)
                                    Text(String(format: String(localized: "local_playlist_track_count"), summary.trackCount))
                                        .font(ClarityStyle.body(10))
                                        .foregroundStyle(ClarityStyle.inkFaint)
                                }
                            }
                            .frame(width: 176, alignment: .leading)
                        }
                        .buttonStyle(ClarityPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
        .padding(20)
    }
}

struct ClarityLocalMusicView: View {
    var body: some View {
        NavigationStack {
            ClarityLocalMusicContent()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ClarityLocalMusicContent: View {
    var isRoot = true
    @ObservedObject private var library = LocalMusicLibraryManager.shared

    var body: some View {
        ClarityLocalScene(title: String(localized: "tabbar_local_music"), showsTitle: isRoot) {
            ClarityLocalSongList(title: String(localized: "local_filter_all"), songs: library.songs)
        }
    }
}

struct ClarityLocalLibraryView: View {
    @ObservedObject private var playlists = LocalPlaylistManager.shared
    private let columns = [GridItem(.adaptive(minimum: 138, maximum: 190), spacing: 14)]

    var body: some View {
        NavigationStack {
            ClarityLocalScene(title: String(localized: "tabbar_library")) {
                if playlists.playlists.isEmpty {
                    VStack(spacing: 12) {
                        MonoIcon(icon: .musicNoteList, size: 25, color: ClarityStyle.inkFaint, lineWidth: 1.5)
                            .frame(width: 58, height: 58)
                            .background(ClarityMembrane(shape: Circle(), strength: .regular))
                        Text(String(localized: "library_empty_playlists"))
                            .font(ClarityStyle.body(13, weight: .medium))
                            .foregroundStyle(ClarityStyle.inkSoft)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(playlists.playlists, id: \.id) { playlist in
                            let summary = playlists.summary(for: playlist)
                            NavigationLink(destination: LocalPlaylistDetailView(playlistId: playlist.id).clarityDetailChrome(preservesImmersiveBackdrop: true)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    GeometryReader { geometry in
                                        ClarityArtwork(url: summary.displayCoverUrl, size: geometry.size.width, radius: 22)
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    Text(playlist.name)
                                        .font(ClarityStyle.body(13, weight: .semibold))
                                        .foregroundStyle(ClarityStyle.ink)
                                        .lineLimit(2)
                                    Text(String(format: String(localized: "local_playlist_track_count"), summary.trackCount))
                                        .font(ClarityStyle.body(10.5))
                                        .foregroundStyle(ClarityStyle.inkFaint)
                                }
                            }
                            .buttonStyle(ClarityPressStyle())
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ClarityLocalProfileView: View {
    var body: some View {
        NavigationStack {
            ClarityLocalScene(title: String(localized: "tabbar_profile")) {
                ClarityShell(cornerRadius: 28) {
                    VStack(spacing: 0) {
                        NavigationLink(destination: ListeningStatsView().clarityDetailChrome()) {
                            ClarityLocalLinkRow(icon: .chart, title: String(localized: "listening_stats"))
                        }
                        Rectangle().fill(ClarityStyle.line).frame(height: 1).padding(.leading, 54)
                        NavigationLink(destination: SettingsView()) {
                            ClarityLocalLinkRow(icon: .settings, title: String(localized: "settings_title"))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ClarityLocalScene<Content: View>: View {
    let title: String
    var showsTitle = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            ClarityBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if showsTitle {
                        Text(title)
                            .font(ClarityStyle.title(23, weight: .semibold))
                            .foregroundStyle(ClarityStyle.ink)
                            .accessibilityAddTraits(.isHeader)
                            .monoPageHeaderCollapse()
                    }
                    content()
                    FloatingBarBottomSpacer()
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.top, showsTitle ? DeviceLayout.headerTopPadding + 4 : 8)
                .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 28 : 16)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct ClarityLocalSongList: View {
    let title: String
    let songs: [Song]

    var body: some View {
        // Local libraries can contain thousands of songs. A regular VStack
        // eagerly constructs every artwork, button and glass sublayer before
        // the first scroll frame; keep the exact row design but instantiate
        // rows with the surrounding scroll viewport instead.
        LazyVStack(alignment: .leading, spacing: 10) {
            ClaritySectionHeading(title: title)
            if songs.isEmpty {
                Text(String(localized: "empty_no_songs"))
                    .font(ClarityStyle.body(12.5))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.identityKey) { index, song in
                    claritySongRow(index: index, song: song, songs: songs)
                }
            }
        }
        .padding(18)
        .background(ClarityMembrane(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), strength: .strong))
    }
}

private func claritySongRow(index: Int, song: Song, songs: [Song]) -> some View {
    Button { PlayerManager.shared.play(song: song, in: songs) } label: {
        HStack(spacing: 11) {
            Text(String(format: "%02d", index + 1))
                .font(ClarityStyle.body(9.5, weight: .semibold))
                .foregroundStyle(ClarityStyle.inkFaint)
                .frame(width: 20)
            ClarityArtwork(url: song.coverUrl, size: 46, radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(ClarityStyle.body(13, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(ClarityStyle.body(10.5))
                    .foregroundStyle(ClarityStyle.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MonoIcon(icon: .play, size: 13, color: ClarityStyle.inkSoft, lineWidth: 1.45)
                .frame(width: 34, height: 34)
                .background(ClarityMembrane(shape: Circle(), strength: .quiet))
        }
        .padding(.vertical, 3)
    }
    .buttonStyle(ClarityPressStyle())
}

private struct ClarityLocalLinkRow: View {
    let icon: MonoIcon.IconType
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            MonoIcon(icon: icon, size: 17, color: ClarityStyle.ink, lineWidth: 1.5)
                .frame(width: 34, height: 50)
            Text(title)
                .font(ClarityStyle.body(13.5, weight: .semibold))
                .foregroundStyle(ClarityStyle.ink)
            Spacer()
            MonoIcon(icon: .chevronRight, size: 13, color: ClarityStyle.inkFaint, lineWidth: 1.4)
        }
    }
}
