import Foundation
import Combine
@preconcurrency import MusicKit
@preconcurrency import MediaPlayer

struct AppleMusicSearchPage {
    let songs: [Song]
    let hasMore: Bool
}

struct AppleMusicLibraryPage {
    let songs: [Song]
    let hasMore: Bool
    let nextOffset: Int
}

struct AppleMusicLibraryPlaylistPage {
    let playlists: [Playlist]
    let hasMore: Bool
    let nextOffset: Int
}

struct AppleMusicLibraryAlbumPage {
    let albums: [AlbumInfo]
    let hasMore: Bool
    let nextOffset: Int
}

struct AppleMusicLibraryArtistPage {
    let artists: [ArtistInfo]
    let hasMore: Bool
    let nextOffset: Int
}

struct AppleMusicPlaylistPage {
    let playlists: [Playlist]
    let hasMore: Bool
}

struct AppleMusicArtistPage {
    let artists: [ArtistInfo]
    let hasMore: Bool
}

struct AppleMusicAlbumSearchPage {
    let albums: [SearchAlbum]
    let hasMore: Bool
}

struct AppleMusicArtistDetailPage {
    let artist: ArtistInfo
    let songs: [Song]
    let albums: [AlbumInfo]
    let similarArtists: [ArtistInfo]
}

struct AppleMusicAlbumDetailPage {
    let album: AlbumInfo
    let songs: [Song]
}

enum AppleMusicServiceError: LocalizedError {
    case authorizationDenied
    case requestUnauthorized
    case subscriptionRequired
    case invalidCatalogID
    case itemUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return String(localized: "apple_music_error_authorization")
        case .requestUnauthorized:
            return String(localized: "apple_music_error_request_unauthorized")
        case .subscriptionRequired:
            return String(localized: "apple_music_error_subscription")
        case .invalidCatalogID:
            return String(localized: "apple_music_error_invalid_id")
        case .itemUnavailable:
            return String(localized: "apple_music_error_unavailable")
        }
    }
}

private struct AppleMediaLibraryArtworkRequest: Sendable {
    let identityKey: String
    let exactKey: String
    let titleArtistKey: String
    let titleAlbumKey: String
    let titleKey: String
}

@MainActor
final class AppleMusicService: ObservableObject {
    static let shared = AppleMusicService()

    @Published private(set) var authorizationStatus = MusicAuthorization.currentStatus
    @Published private(set) var canPlayCatalogContent = false

    private var songCache: [String: MusicKit.Song] = [:]
    private var artworkURLCache: [String: URL] = [:]
    private var animatedArtworkURLCache: [String: URL] = [:]
    private var unavailableAnimatedArtworkIDs = Set<String>()
    private var libraryAlbumArtworkCache: [String: URL] = [:]
    private var preparedLibraryAlbumArtwork = false
    private var playlistCache: [String: MusicKit.Playlist] = [:]
    private var playlistTrackCache: [String: MusicItemCollection<MusicKit.Track>] = [:]
    private var catalogEntryLimit = 256
    private var playlistTrackEntryLimit = 32
    /// `nil` 表示系统暂时无法读取订阅状态，而不是“没有订阅”。
    /// MusicKit 的账号服务偶发不可用时，播放命令本身仍可能成功，因此不能
    /// 把一次查询异常缓存为无订阅并在真正调用播放器前直接拦截。
    private var subscriptionCheckTask: Task<Bool?, Never>?
    private var cachedSubscriptionCapability: Bool?
    private var subscriptionStatusCheckedAt: Date?
    private let subscriptionStatusCacheDuration: TimeInterval = 5 * 60

    private init() {
        MonoMemoryEngine.shared.registerResource(
            id: "cache.apple-music",
            priority: .retained,
            budgetWeight: 0.10,
            minimumBudgetBytes: 6 * 1_024 * 1_024,
            applyBudget: { [weak self] bytes in
                self?.applyMemoryBudget(bytes)
            },
            trim: { [weak self] context in
                self?.trimMemory(context) ?? .none
            },
            measureUsage: { [weak self] in
                guard let self else { return .unknown }
                return .init(
                    itemCount: self.memoryCacheEntryCount,
                    estimatedBytes: self.memoryCacheEntryCount * 24 * 1_024
                )
            }
        )
    }

    private func applyMemoryBudget(_ bytes: Int) {
        catalogEntryLimit = max(64, min(640, bytes / (48 * 1_024)))
        playlistTrackEntryLimit = max(8, min(64, bytes / (512 * 1_024)))
        enforceMemoryLimits()
    }

    private func trimMemory(_ context: MonoMemoryEngine.TrimContext) -> MonoMemoryEngine.TrimResult {
        let before = memoryCacheEntryCount
        let currentCatalogID = PlayerManager.shared.currentSong?.appleMusicCatalogID

        switch context.level {
        case .routine:
            enforceMemoryLimits()
        case .background:
            Self.trim(&songCache, count: max(32, catalogEntryLimit / 3), preserving: currentCatalogID)
            Self.trim(&artworkURLCache, count: max(48, catalogEntryLimit / 2), preserving: currentCatalogID)
            Self.trim(&animatedArtworkURLCache, count: max(24, catalogEntryLimit / 4))
            Self.trim(&unavailableAnimatedArtworkIDs, count: max(24, catalogEntryLimit / 4))
            Self.trim(&libraryAlbumArtworkCache, count: max(64, catalogEntryLimit / 2))
            Self.trim(&playlistCache, count: 24)
            Self.trim(&playlistTrackCache, count: 4)
        case .warning, .critical:
            Self.trim(&songCache, count: currentCatalogID == nil ? 0 : 1, preserving: currentCatalogID)
            Self.trim(&artworkURLCache, count: currentCatalogID == nil ? 0 : 2, preserving: currentCatalogID)
            animatedArtworkURLCache.removeAll(keepingCapacity: false)
            unavailableAnimatedArtworkIDs.removeAll(keepingCapacity: false)
            libraryAlbumArtworkCache.removeAll(keepingCapacity: false)
            playlistCache.removeAll(keepingCapacity: false)
            playlistTrackCache.removeAll(keepingCapacity: false)
            preparedLibraryAlbumArtwork = false
        }

        let after = memoryCacheEntryCount
        let released = max(0, before - after)
        return .init(
            releasedItemCount: released,
            estimatedReleasedBytes: released * 24 * 1_024,
            preservedItemCount: after
        )
    }

    private var memoryCacheEntryCount: Int {
        songCache.count
            + artworkURLCache.count
            + animatedArtworkURLCache.count
            + unavailableAnimatedArtworkIDs.count
            + libraryAlbumArtworkCache.count
            + playlistCache.count
            + playlistTrackCache.count
    }

    private func enforceMemoryLimits() {
        Self.trim(&songCache, count: catalogEntryLimit, preserving: PlayerManager.shared.currentSong?.appleMusicCatalogID)
        Self.trim(&artworkURLCache, count: catalogEntryLimit * 2)
        Self.trim(&animatedArtworkURLCache, count: max(32, catalogEntryLimit / 2))
        Self.trim(&unavailableAnimatedArtworkIDs, count: max(32, catalogEntryLimit / 2))
        Self.trim(&libraryAlbumArtworkCache, count: catalogEntryLimit * 2)
        Self.trim(&playlistCache, count: max(32, catalogEntryLimit / 2))
        Self.trim(&playlistTrackCache, count: playlistTrackEntryLimit)
    }

    /// 批量分页完成前允许很小的暂时余量，超过预算即同步收敛，避免等到
    /// 30 秒巡检才处理 MusicKit 大集合造成的瞬时内存峰值。
    private func enforceMemoryLimitsIfNeeded() {
        guard songCache.count > catalogEntryLimit + 32
            || artworkURLCache.count > catalogEntryLimit * 2 + 32
            || animatedArtworkURLCache.count > max(32, catalogEntryLimit / 2) + 8
            || unavailableAnimatedArtworkIDs.count > max(32, catalogEntryLimit / 2) + 8
            || libraryAlbumArtworkCache.count > catalogEntryLimit * 2 + 32
            || playlistCache.count > max(32, catalogEntryLimit / 2) + 8
            || playlistTrackCache.count > playlistTrackEntryLimit + 2 else {
            return
        }
        enforceMemoryLimits()
    }

    private static func trim<Value>(
        _ source: inout [String: Value],
        count: Int,
        preserving preservedKey: String? = nil
    ) {
        let limit = max(0, count)
        guard source.count > limit else { return }
        if limit == 0 {
            source.removeAll(keepingCapacity: false)
            return
        }

        let removalCount = source.count - limit
        let keys = Array(
            source.keys.lazy
                .filter { $0 != preservedKey }
                .prefix(removalCount)
        )
        for key in keys { source.removeValue(forKey: key) }
    }

    private static func trim(
        _ source: inout Set<String>,
        count: Int
    ) {
        let limit = max(0, count)
        guard source.count > limit else { return }
        let removals = Array(source.prefix(source.count - limit))
        source.subtract(removals)
    }

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    var authorizationRequiresSettings: Bool {
        MusicAuthorization.currentStatus == .denied
    }

    var authorizationIsRestricted: Bool {
        MusicAuthorization.currentStatus == .restricted
    }

    var authorizationStateText: String {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限制"
        case .notDetermined:
            return "未授权"
        @unknown default:
            return "未授权"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded(
        refreshesSubscription: Bool = false
    ) async -> Bool {
        let status: MusicAuthorization.Status
        if MusicAuthorization.currentStatus == .notDetermined {
            status = await MusicAuthorization.request()
        } else {
            status = MusicAuthorization.currentStatus
        }
        authorizationStatus = status
        guard status == .authorized else {
            subscriptionCheckTask?.cancel()
            subscriptionCheckTask = nil
            subscriptionStatusCheckedAt = nil
            cachedSubscriptionCapability = nil
            canPlayCatalogContent = false
            return false
        }

        if refreshesSubscription {
            _ = await refreshSubscriptionStatusIfNeeded()
        }
        return true
    }

    /// 订阅状态属于播放能力，不应被每次目录搜索、歌单翻页重复查询。
    /// MusicKit 的账号解析失败时系统会产生大量 DSID 日志，因此这里合并
    /// 并缓存并发请求；真正播放或用户主动授权时才刷新。
    private func refreshSubscriptionStatusIfNeeded(
        force: Bool = false
    ) async -> Bool? {
        if !force,
           let checkedAt = subscriptionStatusCheckedAt,
           Date().timeIntervalSince(checkedAt) < subscriptionStatusCacheDuration {
            return cachedSubscriptionCapability
        }

        if let task = subscriptionCheckTask {
            return await task.value
        }

        let task = Task { @MainActor () -> Bool? in
            do {
                let subscription = try await MusicSubscription.current
                return subscription.canPlayCatalogContent
            } catch {
                AppLogger.warning(
                    "[AppleMusic] 暂时无法读取订阅状态，交由 MusicKit 播放命令确认: \(error.localizedDescription)",
                    step: "apple-music.subscription"
                )
                return nil
            }
        }
        subscriptionCheckTask = task
        let capability = await task.value
        subscriptionCheckTask = nil
        cachedSubscriptionCapability = capability
        if let capability {
            // 只有拿到系统明确结果时才进入五分钟缓存。查询异常不缓存，
            // 下一次播放仍会重新检查，同时本次继续交给 MusicKit 判断。
            subscriptionStatusCheckedAt = Date()
            canPlayCatalogContent = capability
        } else {
            subscriptionStatusCheckedAt = nil
        }
        return capability
    }

    func searchSongs(
        term: String,
        offset: Int,
        limit: Int = 25
    ) async throws -> AppleMusicSearchPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.offset = max(0, offset)
        request.limit = max(1, min(limit, 25))
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let musicKitSongs: [MusicKit.Song] = Array(response.songs)
        for song in musicKitSongs {
            songCache[song.id.rawValue] = song
        }
        enforceMemoryLimitsIfNeeded()
        let songs: [Song] = musicKitSongs.compactMap { song in
            Self.convert(song)
        }
        return AppleMusicSearchPage(
            songs: songs,
            hasMore: musicKitSongs.count >= max(1, min(limit, 25))
        )
    }

    func librarySongs(
        offset: Int,
        limit: Int = 50
    ) async throws -> AppleMusicLibraryPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        await prepareLibraryAlbumArtworkIfNeeded()

        let pageSize = max(1, min(limit, 100))
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.offset = max(0, offset)
        request.limit = pageSize
        request.sort(by: \.libraryAddedDate, ascending: false)
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let musicKitSongs: [MusicKit.Song] = Array(response.items)
        cache(musicKitSongs)
        let songs = await enrichedLibrarySongs(musicKitSongs)
        return AppleMusicLibraryPage(
            songs: songs,
            hasMore: response.items.hasNextBatch || musicKitSongs.count == pageSize,
            nextOffset: max(0, offset) + musicKitSongs.count
        )
    }

    /// 把资料库内部 `musicKit://` 封面批量转换为界面可加载的 URL。
    private func enrichedLibrarySongs(
        _ sources: [MusicKit.Song]
    ) async -> [Song] {
        let mediaLibraryArtworkRequests: [AppleMediaLibraryArtworkRequest] =
            sources.compactMap { source in
                guard Self.convert(source)?.coverUrl == nil else { return nil }
                if let albumTitle = source.albumTitle,
                   cachedLibraryAlbumArtwork(
                       albumTitle: albumTitle,
                       artistName: source.artistName
                   ) != nil {
                    return nil
                }
                return Self.mediaLibraryArtworkRequest(for: source)
            }
        let mediaLibraryArtworkURLs = await Self.materializeMediaLibraryArtwork(
            for: mediaLibraryArtworkRequests
        )
        if !mediaLibraryArtworkRequests.isEmpty {
            AppLogger.info(
                "[AppleMusic] 系统资料库封面物化 \(mediaLibraryArtworkURLs.count)/\(mediaLibraryArtworkRequests.count)",
                step: "apple-music.library-artwork"
            )
        }

        var songs: [Song] = []
        songs.reserveCapacity(sources.count)
        for source in sources {
            guard let converted = Self.convert(source) else { continue }
            if let directArtworkURL = converted.coverUrl {
                cacheArtworkURL(directArtworkURL, for: converted, source: source)
                songs.append(converted)
                continue
            }

            let indexedArtworkURL = source.albumTitle.flatMap { albumTitle in
                cachedLibraryAlbumArtwork(
                    albumTitle: albumTitle,
                    artistName: source.artistName
                )
            }
            let localArtworkURL = mediaLibraryArtworkURLs[source.id.rawValue]
            var fallbackArtworkURL = Self.firstRenderableArtworkURL(
                indexedArtworkURL,
                localArtworkURL
            )
            if fallbackArtworkURL == nil {
                fallbackArtworkURL = await resolvedArtworkURL(
                    for: converted,
                    preferred: source,
                    preferredPropertySource: .library
                )
            }

            if let fallbackArtworkURL,
               let enriched = Self.convert(
                   source,
                   artworkURL: fallbackArtworkURL
               ) {
                cacheArtworkURL(
                    fallbackArtworkURL,
                    for: enriched,
                    source: source
                )
                songs.append(enriched)
            } else {
                songs.append(converted)
            }
        }
        return songs
    }

    func libraryPlaylists(
        offset: Int,
        limit: Int = 50
    ) async throws -> AppleMusicLibraryPlaylistPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        await prepareLibraryAlbumArtworkIfNeeded()

        let pageSize = max(1, min(limit, 100))
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let sources = Array(response.items).sorted {
            ($0.libraryAddedDate ?? .distantPast) > ($1.libraryAddedDate ?? .distantPast)
        }
        var hydratedSources: [MusicKit.Playlist] = []
        hydratedSources.reserveCapacity(sources.count)

        for source in sources {
            let hydrated = (try? await Self.performMusicKitRequest {
                try await source.with(.tracks)
            }) ?? source
            playlistCache[source.id.rawValue] = hydrated
            if let tracks = hydrated.tracks {
                playlistTrackCache[source.id.rawValue] = tracks
            }
            hydratedSources.append(hydrated)
        }

        let firstSongs = hydratedSources.compactMap {
            Self.firstSong(in: $0.tracks)
        }
        cache(firstSongs)
        let enrichedFirstSongs = await enrichedLibrarySongs(firstSongs)
        var firstSongArtworkByID: [String: URL] = [:]
        for song in enrichedFirstSongs {
            guard let appleMusicID = song.appleMusicCatalogID,
                  let artworkURL = song.coverUrl,
                  firstSongArtworkByID[appleMusicID] == nil else {
                continue
            }
            firstSongArtworkByID[appleMusicID] = artworkURL
        }

        var playlists: [Playlist] = []
        playlists.reserveCapacity(hydratedSources.count)

        for source in hydratedSources {
            var artworkURL = Self.firstRenderableArtworkURL(
                source.artwork?.url(width: 1200, height: 1200),
                Self.firstSong(in: source.tracks).flatMap {
                    firstSongArtworkByID[$0.id.rawValue]
                }
            )
            if artworkURL == nil,
               let firstSong = Self.firstSong(in: source.tracks) {
                artworkURL = firstSong.albumTitle.flatMap { albumTitle in
                    cachedLibraryAlbumArtwork(
                        albumTitle: albumTitle,
                        artistName: firstSong.artistName
                    )
                }
            }

            let completeTrackCount: Int?
            if let tracks = source.tracks, !tracks.hasNextBatch {
                completeTrackCount = tracks.count
            } else {
                completeTrackCount = nil
            }
            if let converted = Self.convert(
                source,
                artworkURL: artworkURL,
                trackCount: completeTrackCount
            ) {
                playlists.append(converted)
            }
        }

        return AppleMusicLibraryPlaylistPage(
            playlists: playlists,
            hasMore: response.items.hasNextBatch || sources.count == pageSize,
            nextOffset: max(0, offset) + sources.count
        )
    }

    func libraryAlbums(
        offset: Int,
        limit: Int = 50
    ) async throws -> AppleMusicLibraryAlbumPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        let pageSize = max(1, min(limit, 100))
        var request = MusicLibraryRequest<MusicKit.Album>()
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let sources = Array(response.items).sorted {
            ($0.libraryAddedDate ?? .distantPast) > ($1.libraryAddedDate ?? .distantPast)
        }
        var albums: [AlbumInfo] = []
        albums.reserveCapacity(sources.count)

        for source in sources {
            let directArtworkURL = Self.firstRenderableArtworkURL(
                source.artwork?.url(width: 1200, height: 1200),
                cachedLibraryAlbumArtwork(
                    albumTitle: source.title,
                    artistName: source.artistName
                )
            )
            var fallbackArtworkURL: URL?
            if directArtworkURL == nil,
               let hydrated = try? await Self.performMusicKitRequest({
                   try await source.with(.tracks)
               }),
               let firstSong = Self.firstSong(in: hydrated.tracks) {
                songCache[firstSong.id.rawValue] = firstSong
                fallbackArtworkURL = await artworkURL(
                    from: firstSong,
                    preferredSource: .library
                )
                if fallbackArtworkURL == nil,
                   let converted = Self.convert(firstSong) {
                    fallbackArtworkURL = await resolvedArtworkURL(
                        for: converted,
                        preferred: firstSong,
                        preferredPropertySource: .library
                    )
                }
            } else {
                fallbackArtworkURL = nil
            }

            let resolvedArtworkURL = directArtworkURL ?? fallbackArtworkURL
            if let resolvedArtworkURL {
                cacheLibraryAlbumArtwork(
                    resolvedArtworkURL,
                    albumTitle: source.title,
                    artistName: source.artistName
                )
            }
            if let converted = Self.convert(
                source,
                artworkURL: resolvedArtworkURL
            ) {
                albums.append(converted)
            }
        }

        return AppleMusicLibraryAlbumPage(
            albums: albums,
            hasMore: response.items.hasNextBatch || sources.count == pageSize,
            nextOffset: max(0, offset) + sources.count
        )
    }

    func libraryArtists(
        offset: Int,
        limit: Int = 50
    ) async throws -> AppleMusicLibraryArtistPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        let pageSize = max(1, min(limit, 100))
        var request = MusicLibraryRequest<MusicKit.Artist>()
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let sources = Array(response.items).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var artists: [ArtistInfo] = []
        artists.reserveCapacity(sources.count)

        for source in sources {
            if Self.renderableArtworkURL(
                source.artwork?.url(width: 1200, height: 1200)
            ) != nil,
               let converted = Self.convert(source) {
                artists.append(converted)
                continue
            }

            var search = MusicCatalogSearchRequest(
                term: source.name,
                types: [MusicKit.Artist.self]
            )
            search.limit = 5
            let searchResponse = try? await Self.performMusicKitRequest {
                try await search.response()
            }
            let catalogMatch = searchResponse?.artists.first(where: {
                Self.normalizedArtworkMatchText($0.name)
                    == Self.normalizedArtworkMatchText(source.name)
            })
            if let converted = Self.convert(catalogMatch ?? source) {
                artists.append(converted)
            }
        }

        return AppleMusicLibraryArtistPage(
            artists: artists,
            hasMore: response.items.hasNextBatch || sources.count == pageSize,
            nextOffset: max(0, offset) + sources.count
        )
    }

    func topLists() async throws -> [TopList] {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }
        var request = MusicCatalogChartsRequest(
            kinds: [.dailyGlobalTop, .cityTop], types: [MusicKit.Playlist.self]
        )
        request.limit = 100
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        var lists: [TopList] = []
        var seen = Set<String>()
        for chart in response.playlistCharts {
            for item in chart.items {
                guard seen.insert(item.id.rawValue).inserted,
                      let playlist = Self.convert(item) else { continue }
                playlistCache[item.id.rawValue] = item
                lists.append(TopList(
                    id: playlist.id, name: playlist.name, coverImgUrl: playlist.coverImgUrl,
                    updateFrequency: chart.title, source: .appleMusic,
                    appleMusicID: item.id.rawValue
                ))
            }
        }
        enforceMemoryLimitsIfNeeded()
        return lists
    }

    func searchPlaylists(
        term: String,
        offset: Int,
        limit: Int = 25
    ) async throws -> AppleMusicPlaylistPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        let pageSize = max(1, min(limit, 25))
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Playlist.self])
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let playlists: [MusicKit.Playlist] = Array(response.playlists)
        for playlist in playlists {
            playlistCache[playlist.id.rawValue] = playlist
        }
        enforceMemoryLimitsIfNeeded()
        let convertedPlaylists: [Playlist] = playlists.compactMap { playlist in
            Self.convert(playlist)
        }
        return AppleMusicPlaylistPage(
            playlists: convertedPlaylists,
            hasMore: playlists.count >= pageSize
        )
    }

    func searchArtists(
        term: String,
        offset: Int,
        limit: Int = 25
    ) async throws -> AppleMusicArtistPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        let pageSize = max(1, min(limit, 25))
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Artist.self])
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let artists: [MusicKit.Artist] = Array(response.artists)
        let convertedArtists: [ArtistInfo] = artists.compactMap { artist in
            Self.convert(artist)
        }
        return AppleMusicArtistPage(
            artists: convertedArtists,
            hasMore: artists.count >= pageSize
        )
    }

    func searchAlbums(
        term: String,
        offset: Int,
        limit: Int = 25
    ) async throws -> AppleMusicAlbumSearchPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        let pageSize = max(1, min(limit, 25))
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Album.self])
        request.offset = max(0, offset)
        request.limit = pageSize
        let response = try await Self.performMusicKitRequest {
            try await request.response()
        }
        let albums = Array(response.albums)
        let converted = albums.compactMap { source -> SearchAlbum? in
            guard let album = Self.convert(source) else { return nil }
            let fallbackArtist = album.artist.map { Artist(id: $0.id, name: $0.name) }
            return SearchAlbum(
                id: album.id,
                name: album.name,
                picUrl: album.picUrl,
                artist: album.artists?.first ?? fallbackArtist,
                artists: album.artists ?? fallbackArtist.map { [$0] },
                size: album.size,
                publishTime: album.publishTime,
                source: .appleMusic,
                qqMid: nil,
                appleMusicID: album.appleMusicID,
                kugouID: nil
            )
        }
        return AppleMusicAlbumSearchPage(
            albums: converted,
            hasMore: albums.count >= pageSize
        )
    }

    func artistDetail(artistID: String) async throws -> AppleMusicArtistDetailPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }

        var request = MusicCatalogResourceRequest<MusicKit.Artist>(
            matching: \.id,
            equalTo: MusicItemID(artistID)
        )
        request.limit = 1
        request.properties = [
            .topSongs,
            .albums,
            .similarArtists
        ]

        let source: MusicKit.Artist
        if let catalogArtist = try? await Self.performMusicKitRequest({
            try await request.response()
        }).items.first {
            source = catalogArtist
        } else {
            var libraryRequest = MusicLibraryRequest<MusicKit.Artist>()
            libraryRequest.limit = 1
            libraryRequest.filter(
                matching: \.id,
                equalTo: MusicItemID(artistID)
            )
            guard let libraryArtist = try await Self.performMusicKitRequest({
                try await libraryRequest.response()
            }).items.first else {
                throw AppleMusicServiceError.itemUnavailable
            }
            source = (try? await Self.performMusicKitRequest {
                try await libraryArtist.with(
                    .topSongs,
                    .albums,
                    .similarArtists
                )
            }) ?? libraryArtist
        }

        let musicKitSongs: [MusicKit.Song] = source.topSongs.map { collection in
            Array(collection)
        } ?? []
        cache(musicKitSongs)
        let songs: [Song] = musicKitSongs.compactMap { song in
            Self.convert(song)
        }
        let musicKitAlbums: [MusicKit.Album] = source.albums.map { collection in
            Array(collection)
        } ?? []
        let albums: [AlbumInfo] = musicKitAlbums.compactMap { album in
            Self.convert(album)
        }
        let relatedArtists: [MusicKit.Artist] = source.similarArtists.map { collection in
            Array(collection)
        } ?? []
        let similarArtists: [ArtistInfo] = relatedArtists.compactMap { relatedArtist in
            Self.convert(relatedArtist)
        }
        let artist = Self.convert(
            source,
            musicSize: songs.count,
            albumSize: albums.count,
            mvSize: source.musicVideos?.count
        )

        guard let artist else {
            throw AppleMusicServiceError.itemUnavailable
        }

        return AppleMusicArtistDetailPage(
            artist: artist,
            songs: songs,
            albums: albums,
            similarArtists: similarArtists
        )
    }

    func albumDetail(albumID: String) async throws -> AppleMusicAlbumDetailPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }
        await prepareLibraryAlbumArtworkIfNeeded()

        var request = MusicCatalogResourceRequest<MusicKit.Album>(
            matching: \.id,
            equalTo: MusicItemID(albumID)
        )
        request.limit = 1
        request.properties = [.tracks]

        let source: MusicKit.Album
        if let catalogAlbum = try? await Self.performMusicKitRequest({
            try await request.response()
        }).items.first {
            source = catalogAlbum
        } else {
            var libraryRequest = MusicLibraryRequest<MusicKit.Album>()
            libraryRequest.limit = 1
            libraryRequest.filter(
                matching: \.id,
                equalTo: MusicItemID(albumID)
            )
            guard let libraryAlbum = try await Self.performMusicKitRequest({
                try await libraryRequest.response()
            }).items.first else {
                throw AppleMusicServiceError.itemUnavailable
            }
            source = (try? await Self.performMusicKitRequest {
                try await libraryAlbum.with(.tracks)
            }) ?? libraryAlbum
        }
        var tracks = source.tracks ?? []
        while tracks.hasNextBatch,
              let nextBatch = try await Self.performMusicKitRequest({
                  try await tracks.nextBatch(limit: 100)
              }) {
            tracks += nextBatch
        }

        let musicKitSongs = Array(tracks).compactMap { track -> MusicKit.Song? in
            guard case let .song(song) = track else { return nil }
            return song
        }
        cache(musicKitSongs)
        let songs = await enrichedLibrarySongs(musicKitSongs)

        var albumArtworkURL = Self.firstRenderableArtworkURL(
            source.artwork?.url(width: 1200, height: 1200),
            cachedLibraryAlbumArtwork(
                albumTitle: source.title,
                artistName: source.artistName
            ),
            songs.first?.coverUrl
        )
        if albumArtworkURL == nil,
           let firstSong = musicKitSongs.first,
           let converted = Self.convert(firstSong) {
            albumArtworkURL = await resolvedArtworkURL(
                for: converted,
                preferred: firstSong,
                preferredPropertySource: .library
            )
        }
        guard let album = Self.convert(
            source,
            artworkURL: albumArtworkURL
        ) else {
            throw AppleMusicServiceError.itemUnavailable
        }

        return AppleMusicAlbumDetailPage(
            album: album,
            songs: songs
        )
    }

    /// 分页读取 Apple Music 歌单曲目，并缓存已补全的歌单关系与已拉取批次。
    ///
    /// `offset` 超出当前缓存时会按需请求后续批次；非歌曲类型的 Track 会被过滤。
    func playlistSongs(
        playlistID: String,
        offset: Int,
        limit: Int = 30
    ) async throws -> AppleMusicSearchPage {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }
        await prepareLibraryAlbumArtworkIfNeeded()

        let pageSize = max(1, min(limit, 100))
        let playlist: MusicKit.Playlist
        if let cached = playlistCache[playlistID] {
            playlist = cached
        } else {
            var request = MusicCatalogResourceRequest<MusicKit.Playlist>(
                matching: \.id,
                equalTo: MusicItemID(playlistID)
            )
            request.limit = 1
            let catalogPlaylist = try? await Self.performMusicKitRequest({
                try await request.response()
            }).items.first

            var libraryRequest = MusicLibraryRequest<MusicKit.Playlist>()
            libraryRequest.limit = 1
            libraryRequest.filter(
                matching: \.id,
                equalTo: MusicItemID(playlistID)
            )
            let libraryResponse = try? await Self.performMusicKitRequest {
                try await libraryRequest.response()
            }
            let libraryPlaylist = libraryResponse?.items.first

            guard let resolved = catalogPlaylist ?? libraryPlaylist else {
                throw AppleMusicServiceError.itemUnavailable
            }
            playlistCache[playlistID] = resolved
            playlist = resolved
        }

        var trackCollection: MusicItemCollection<MusicKit.Track>
        if let cachedTracks = playlistTrackCache[playlistID] {
            trackCollection = cachedTracks
        } else {
            let hydratedPlaylist = try await Self.performMusicKitRequest {
                try await playlist.with(.tracks)
            }
            playlistCache[playlistID] = hydratedPlaylist
            guard let hydratedTracks = hydratedPlaylist.tracks else {
                return AppleMusicSearchPage(songs: [], hasMore: false)
            }
            trackCollection = hydratedTracks
        }

        let requiredCount = max(0, offset) + pageSize
        while trackCollection.count < requiredCount,
              trackCollection.hasNextBatch,
              let nextBatch = try await Self.performMusicKitRequest({
                  try await trackCollection.nextBatch(limit: pageSize)
              }) {
            trackCollection += nextBatch
        }
        playlistTrackCache[playlistID] = trackCollection

        let tracks = Array(trackCollection)
        let start = min(max(0, offset), tracks.count)
        let end = min(start + pageSize, tracks.count)
        let musicKitSongs = tracks[start..<end].compactMap { track -> MusicKit.Song? in
            guard case let .song(song) = track else { return nil }
            songCache[song.id.rawValue] = song
            return song
        }
        enforceMemoryLimitsIfNeeded()
        let songs = await enrichedLibrarySongs(musicKitSongs)
        return AppleMusicSearchPage(
            songs: songs,
            hasMore: end < tracks.count || trackCollection.hasNextBatch
        )
    }

    /// 资料库歌曲的 `Song.artwork` 偶尔为空，但其专辑关系或对应目录歌曲仍有封面。
    /// 播放链路调用此方法异步补图，不阻塞 MusicKit 开始播放。
    func resolvedArtworkURL(
        for song: Song,
        preferred source: MusicKit.Song? = nil,
        preferredPropertySource: MusicPropertySource? = nil
    ) async -> URL? {
        let cacheKey = song.appleMusicCatalogID ?? String(song.id)
        if let cached = Self.renderableArtworkURL(artworkURLCache[cacheKey]) {
            return cached
        }

        var checkedIDs = Set<String>()
        var candidates: [MusicKit.Song] = []
        if let source {
            candidates.append(source)
        }
        if let catalogID = song.appleMusicCatalogID,
           let cachedSong = songCache[catalogID],
           !candidates.contains(where: { $0.id == cachedSong.id }) {
            candidates.append(cachedSong)
        }

        for candidate in candidates {
            checkedIDs.insert(candidate.id.rawValue)
            if let url = await artworkURL(
                from: candidate,
                preferredSource: preferredPropertySource
            ) {
                cacheArtworkURL(url, for: song, source: candidate)
                return url
            }
        }

        if let catalogID = song.appleMusicCatalogID,
           !catalogID.isEmpty,
           !checkedIDs.contains(catalogID) {
            var request = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.id,
                equalTo: MusicItemID(catalogID)
            )
            request.limit = 1
            request.properties = [.albums]
            if let resolved = try? await Self.performMusicKitRequest({
                try await request.response()
            }).items.first {
                songCache[catalogID] = resolved
                if let url = await artworkURL(from: resolved) {
                    cacheArtworkURL(url, for: song, source: resolved)
                    return url
                }
            }
        }

        if let isrc = song.appleMusicISRC, !isrc.isEmpty {
            var request = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.isrc,
                equalTo: isrc
            )
            request.limit = 1
            request.properties = [.albums]
            if let resolved = try? await Self.performMusicKitRequest({
                try await request.response()
            }).items.first {
                songCache[resolved.id.rawValue] = resolved
                if let url = await artworkURL(from: resolved) {
                    cacheArtworkURL(url, for: song, source: resolved)
                    return url
                }
            }
        }

        let query = "\(song.artistName) \(song.name)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            var request = MusicCatalogSearchRequest(
                term: query,
                types: [MusicKit.Song.self]
            )
            request.limit = 10
            if let response = try? await Self.performMusicKitRequest({
                try await request.response()
            }) {
                let matches = Array(response.songs)
                    .sorted {
                        Self.artworkMatchScore($0, target: song)
                            > Self.artworkMatchScore($1, target: song)
                    }
                for resolved in matches
                where Self.artworkMatchScore(resolved, target: song) >= 0.72 {
                    songCache[resolved.id.rawValue] = resolved
                    if let url = await artworkURL(from: resolved) {
                        cacheArtworkURL(url, for: song, source: resolved)
                        return url
                    }
                }
            }
        }

        if let existing = Self.renderableArtworkURL(song.coverUrl) {
            artworkURLCache[cacheKey] = existing
            return existing
        }
        return nil
    }

    /// 返回当前歌曲可用的 Apple Music 动态专辑封面。
    /// Apple Music 歌曲直接使用目录 ID；其他平台先严格匹配目录歌曲，
    /// 避免只按同名歌曲误用其他专辑的动态封面。
    func animatedArtworkURL(matching song: Song) async -> URL? {
        if song.isAppleMusic {
            return await animatedArtworkURL(for: song)
        }

        let cacheKey = Self.animatedArtworkMatchCacheKey(for: song)
        if let cached = animatedArtworkURLCache[cacheKey] {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 命中跨平台动态封面缓存",
                step: "apple-music.animated-artwork.match",
                category: .appleMusic,
                event: "match_cache_hit",
                context: [
                    "songSource": song.musicSource.rawValue,
                    "assetHost": cached.host ?? "unknown",
                ]
            )
            return cached
        }
        if unavailableAnimatedArtworkIDs.contains(cacheKey) {
            return nil
        }

        let query = [song.name, song.artistName, song.al?.name ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }

        AppLogger.debug(
            "[AppleMusicDynamicArtwork] 开始为其他平台歌曲匹配 Apple Music 动态封面",
            step: "apple-music.animated-artwork.match",
            category: .appleMusic,
            event: "cross_source_match_started",
            context: ["songSource": song.musicSource.rawValue]
        )

        do {
            var request = MusicCatalogSearchRequest(
                term: query,
                types: [MusicKit.Song.self]
            )
            request.limit = 8
            let response = try await Self.performMusicKitRequest {
                try await request.response()
            }
            guard let match = response.songs.max(by: {
                Self.artworkMatchScore($0, target: song)
                    < Self.artworkMatchScore($1, target: song)
            }) else {
                unavailableAnimatedArtworkIDs.insert(cacheKey)
                enforceMemoryLimitsIfNeeded()
                return nil
            }

            let score = Self.artworkMatchScore(match, target: song)
            guard score >= 0.86, let matchedSong = Self.convert(match) else {
                unavailableAnimatedArtworkIDs.insert(cacheKey)
                enforceMemoryLimitsIfNeeded()
                AppLogger.info(
                    "[AppleMusicDynamicArtwork] 未找到可靠的 Apple Music 目录匹配",
                    step: "apple-music.animated-artwork.match",
                    category: .appleMusic,
                    event: "cross_source_match_rejected",
                    context: [
                        "songSource": song.musicSource.rawValue,
                        "matchScore": String(format: "%.3f", score),
                    ]
                )
                return nil
            }

            songCache[match.id.rawValue] = match
            guard let videoURL = await animatedArtworkURL(for: matchedSong) else {
                return nil
            }
            animatedArtworkURLCache[cacheKey] = videoURL
            enforceMemoryLimitsIfNeeded()
            AppLogger.success(
                "[AppleMusicDynamicArtwork] 跨平台动态封面匹配成功",
                step: "apple-music.animated-artwork.match",
                category: .appleMusic,
                event: "cross_source_match_resolved",
                context: [
                    "songSource": song.musicSource.rawValue,
                    "catalogID": match.id.rawValue,
                    "matchScore": String(format: "%.3f", score),
                    "assetHost": videoURL.host ?? "unknown",
                ]
            )
            return videoURL
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.warning(
                "[AppleMusicDynamicArtwork] 跨平台目录匹配失败：\(error.localizedDescription)",
                step: "apple-music.animated-artwork.match",
                category: .appleMusic,
                event: "cross_source_match_failed",
                context: ["songSource": song.musicSource.rawValue]
            )
            return nil
        }
    }

    func animatedArtworkURL(for song: Song) async -> URL? {
        guard let catalogID = song.appleMusicCatalogID, !catalogID.isEmpty else {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 跳过：歌曲缺少目录 ID",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "lookup_skipped_missing_catalog_id"
            )
            return nil
        }

        AppLogger.debug(
            "[AppleMusicDynamicArtwork] 开始解析动态专辑封面",
            step: "apple-music.animated-artwork",
            category: .appleMusic,
            event: "lookup_started",
            context: ["catalogID": catalogID]
        )

        var catalogSong = songCache[catalogID]
        let songCacheHit = catalogSong != nil
        if catalogSong == nil || catalogSong?.url == nil {
            var request = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.id,
                equalTo: MusicItemID(catalogID)
            )
            request.limit = 1
            request.properties = [.albums]
            catalogSong = try? await Self.performMusicKitRequest {
                try await request.response().items.first
            }
        }

        var albumID = Self.albumID(fromAppleMusicURL: catalogSong?.url)
        if albumID == nil,
           catalogSong?.albums?.first?.url == nil,
           let source = catalogSong {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 补充读取歌曲的专辑关系",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "album_relationship_hydration_started",
                context: [
                    "catalogID": catalogID,
                    "songCacheHit": String(songCacheHit),
                ]
            )
            catalogSong = try? await Self.performMusicKitRequest {
                try await source.with(.albums)
            }
        }
        if albumID == nil {
            albumID = Self.albumID(
                fromAppleMusicURL: catalogSong?.albums?.first?.url
            )
        }

        guard let catalogSong, let albumID, !albumID.isEmpty else {
            AppLogger.warning(
                "[AppleMusicDynamicArtwork] 无法取得歌曲对应的 Apple Music 专辑",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "album_resolution_failed",
                context: [
                    "catalogID": catalogID,
                    "songCacheHit": String(songCacheHit),
                ]
            )
            return nil
        }
        songCache[catalogID] = catalogSong

        if let cached = animatedArtworkURLCache[albumID] {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 命中动态封面缓存",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "cache_hit",
                context: [
                    "albumID": albumID,
                    "assetHost": cached.host ?? "unknown",
                ]
            )
            return cached
        }
        if unavailableAnimatedArtworkIDs.contains(albumID) {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 命中无动态封面缓存，继续使用静态封面",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "negative_cache_hit",
                context: ["albumID": albumID]
            )
            return nil
        }

        do {
            let currentCountryCode = try await MusicDataRequest.currentCountryCode
            let countryCode = currentCountryCode.lowercased()
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.music.apple.com"
            components.path = "/v1/catalog/\(countryCode)/albums/\(albumID)"
            components.queryItems = [
                URLQueryItem(
                    name: "extend",
                    value: "editorialVideo,extendedAssetUrls"
                )
            ]
            guard let url = components.url else { return nil }

            AppLogger.network(
                "[AppleMusicDynamicArtwork] 请求专辑 editorialVideo",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "catalog_request_started",
                context: [
                    "albumID": albumID,
                    "storefront": countryCode,
                ]
            )
            let response = try await Self.performMusicKitRequest {
                try await MusicDataRequest(
                    urlRequest: URLRequest(url: url)
                ).response()
            }
            AppLogger.network(
                "[AppleMusicDynamicArtwork] 收到专辑扩展数据",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "catalog_response_received",
                context: [
                    "albumID": albumID,
                    "responseBytes": String(response.data.count),
                ]
            )
            guard let videoURL = AppleMusicEditorialVideoParser.videoURL(
                from: response.data
            ) else {
                let diagnostic = AppleMusicEditorialVideoParser.diagnosticSummary(
                    from: response.data
                )
                if let webVideoURL = try await webAnimatedArtworkURL(
                    albumID: albumID,
                    storefront: countryCode
                ) {
                    animatedArtworkURLCache[albumID] = webVideoURL
                    enforceMemoryLimitsIfNeeded()
                    AppLogger.success(
                        "[AppleMusicDynamicArtwork] 已从 Apple Music 官方专辑页解析动态封面",
                        step: "apple-music.animated-artwork",
                        category: .appleMusic,
                        event: "web_asset_resolved",
                        context: [
                            "albumID": albumID,
                            "assetHost": webVideoURL.host ?? "unknown",
                            "assetType": webVideoURL.pathExtension.lowercased(),
                            "catalogDiagnostic": diagnostic,
                        ]
                    )
                    return webVideoURL
                }
                unavailableAnimatedArtworkIDs.insert(albumID)
                enforceMemoryLimitsIfNeeded()
                AppLogger.info(
                    "[AppleMusicDynamicArtwork] 未解析到方形动态封面 albumID=\(albumID) \(diagnostic)",
                    step: "apple-music.animated-artwork",
                    category: .appleMusic,
                    event: "asset_unavailable",
                    context: [
                        "albumID": albumID,
                        "responseBytes": String(response.data.count),
                    ]
                )
                return nil
            }

            animatedArtworkURLCache[albumID] = videoURL
            enforceMemoryLimitsIfNeeded()
            AppLogger.success(
                "[AppleMusicDynamicArtwork] 已解析动态封面资源",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "asset_resolved",
                context: [
                    "albumID": albumID,
                    "assetHost": videoURL.host ?? "unknown",
                    "assetType": videoURL.pathExtension.lowercased(),
                ]
            )
            return videoURL
        } catch is CancellationError {
            AppLogger.debug(
                "[AppleMusicDynamicArtwork] 读取任务已取消",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "lookup_cancelled",
                context: ["albumID": albumID]
            )
            return nil
        } catch {
            AppLogger.warning(
                "[AppleMusicDynamicArtwork] 动态封面读取失败：\(error.localizedDescription)",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "lookup_failed",
                context: ["albumID": albumID]
            )
            return nil
        }
    }

    private func webAnimatedArtworkURL(
        albumID: String,
        storefront: String
    ) async throws -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.apple.com"
        components.path = "/\(storefront)/album/\(albumID)"
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        AppLogger.network(
            "[AppleMusicDynamicArtwork] 目录接口未返回动态资源，读取 Apple Music 官方专辑页",
            step: "apple-music.animated-artwork",
            category: .appleMusic,
            event: "web_fallback_started",
            context: [
                "albumID": albumID,
                "storefront": storefront,
            ]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.url?.host?.lowercased() == "music.apple.com" else {
                AppLogger.warning(
                    "[AppleMusicDynamicArtwork] Apple Music 专辑页响应无效",
                    step: "apple-music.animated-artwork",
                    category: .appleMusic,
                    event: "web_fallback_invalid_response",
                    context: [
                        "albumID": albumID,
                        "statusCode": String((response as? HTTPURLResponse)?.statusCode ?? 0),
                    ]
                )
                return nil
            }

            let videoURL = AppleMusicEditorialVideoParser.videoURL(
                fromAppleMusicWebPage: data
            )
            AppLogger.network(
                "[AppleMusicDynamicArtwork] Apple Music 专辑页读取完成",
                step: "apple-music.animated-artwork",
                category: .appleMusic,
                event: "web_fallback_received",
                context: [
                    "albumID": albumID,
                    "responseBytes": String(data.count),
                    "hasSquareVideo": String(videoURL != nil),
                ]
            )
            return videoURL
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    private static func albumID(fromAppleMusicURL url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let albumIndex = components.firstIndex(of: "album"),
              albumIndex + 1 < components.count else {
            return nil
        }
        return components[(albumIndex + 1)...]
            .reversed()
            .first { component in
                !component.isEmpty && component.allSatisfy { $0.isNumber }
            }
    }

    func playableSong(for song: Song) async throws -> MusicKit.Song {
        guard await requestAuthorizationIfNeeded() else {
            throw AppleMusicServiceError.authorizationDenied
        }
        if await refreshSubscriptionStatusIfNeeded() == false {
            throw AppleMusicServiceError.subscriptionRequired
        }
        guard let catalogID = song.appleMusicCatalogID, !catalogID.isEmpty else {
            throw AppleMusicServiceError.invalidCatalogID
        }
        if let cached = songCache[catalogID] {
            return cached
        }

        var request = MusicCatalogResourceRequest<MusicKit.Song>(
            matching: \.id,
            equalTo: MusicItemID(catalogID)
        )
        request.limit = 1
        do {
            if let resolved = try await request.response().items.first {
                songCache[catalogID] = resolved
                return resolved
            }
        } catch let serviceError as AppleMusicServiceError {
            throw serviceError
        } catch {
            if Self.isUnauthorizedMusicKitError(error) {
                throw AppleMusicServiceError.requestUnauthorized
            }
            AppLogger.debug(
                "[AppleMusic] 目录 ID 恢复失败，尝试资料库与 ISRC: \(catalogID)",
                step: "apple-music.catalog-id-fallback"
            )
        }

        // 资料库歌曲在部分地区会返回 library ID。重启后内存缓存不存在时，
        // 先从用户资料库按 ID 恢复，再用 ISRC 回退到当前 storefront。
        var libraryRequest = MusicLibraryRequest<MusicKit.Song>()
        libraryRequest.limit = 1
        libraryRequest.filter(
            matching: \.id,
            equalTo: MusicItemID(catalogID)
        )
        do {
            if let resolved = try await libraryRequest.response().items.first {
                songCache[catalogID] = resolved
                return resolved
            }
        } catch {
            if Self.isUnauthorizedMusicKitError(error) {
                throw AppleMusicServiceError.requestUnauthorized
            }
        }

        if let isrc = song.appleMusicISRC, !isrc.isEmpty {
            var isrcRequest = MusicCatalogResourceRequest<MusicKit.Song>(
                matching: \.isrc,
                equalTo: isrc
            )
            isrcRequest.limit = 1
            do {
                if let resolved = try await isrcRequest.response().items.first {
                    songCache[catalogID] = resolved
                    songCache[resolved.id.rawValue] = resolved
                    return resolved
                }
            } catch {
                throw Self.normalizedError(error)
            }
        }
        throw AppleMusicServiceError.itemUnavailable
    }

    /// Reads Apple Music catalog metadata directly through MusicKit. This is
    /// the song-information replacement for the former generated story copy.
    func platformSongDetail(for song: Song) async throws -> PlatformSongDetail {
        let catalogSong = try await playableSong(for: song)
        var detail = PlatformSongDetail.empty

        if let releaseDate = catalogSong.releaseDate {
            detail.releaseDate = releaseDate.formatted(date: .abbreviated, time: .omitted)
        }

        if let introduction = Self.appleMusicEditorialText(catalogSong.editorialNotes) {
            detail.sections.append(
                PlatformSongSection(
                    id: "apple-music-introduction",
                    title: String(localized: "song_detail_introduction"),
                    body: introduction
                )
            )
        }

        if let composer = catalogSong.composerName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !composer.isEmpty {
            detail.sections.append(
                PlatformSongSection(
                    id: "apple-music-composer",
                    title: String(localized: "song_detail_composer"),
                    body: composer
                )
            )
        }

        let genres = catalogSong.genreNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !genres.isEmpty {
            detail.sections.append(
                PlatformSongSection(
                    id: "apple-music-genres",
                    title: String(localized: "song_detail_genres"),
                    body: genres.joined(separator: " · ")
                )
            )
        }

        if let isrc = catalogSong.isrc?.trimmingCharacters(in: .whitespacesAndNewlines),
           !isrc.isEmpty {
            detail.attributes.append(
                PlatformSongAttribute(
                    id: "apple-music-isrc",
                    label: "ISRC",
                    value: isrc
                )
            )
        }

        return detail
    }

    private static func appleMusicEditorialText(_ notes: EditorialNotes?) -> String? {
        guard let rawValue = notes?.standard ?? notes?.short else { return nil }
        var value = rawValue
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        value = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return value.isEmpty ? nil : value
    }

    private static func normalizedError(_ error: Error) -> Error {
        if let serviceError = error as? AppleMusicServiceError {
            return serviceError
        }
        if isUnauthorizedMusicKitError(error) {
            return AppleMusicServiceError.requestUnauthorized
        }
        return error
    }

    private static func performMusicKitRequest<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw normalizedError(error)
        }
    }

    private static func isUnauthorizedMusicKitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == 401 { return true }

        let description = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if description.contains("401") || description.contains("unauthorized") {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isUnauthorizedMusicKitError(underlying)
        }
        return false
    }

    private func cache(_ songs: [MusicKit.Song]) {
        for song in songs {
            songCache[song.id.rawValue] = song
        }
        enforceMemoryLimitsIfNeeded()
    }

    private static func firstSong(
        in tracks: MusicItemCollection<MusicKit.Track>?
    ) -> MusicKit.Song? {
        guard let tracks else { return nil }
        for track in tracks {
            if case let .song(song) = track {
                return song
            }
        }
        return nil
    }

    private func prepareLibraryAlbumArtworkIfNeeded() async {
        guard !preparedLibraryAlbumArtwork else { return }
        preparedLibraryAlbumArtwork = true

        var offset = 0
        let pageSize = 100
        while !Task.isCancelled {
            var request = MusicLibraryRequest<MusicKit.Album>()
            request.offset = offset
            request.limit = pageSize
            guard let response = try? await Self.performMusicKitRequest({
                try await request.response()
            }) else {
                preparedLibraryAlbumArtwork = false
                return
            }

            let albums = Array(response.items)
            for album in albums {
                guard let url = album.artwork?.url(width: 1200, height: 1200) else {
                    continue
                }
                cacheLibraryAlbumArtwork(
                    url,
                    albumTitle: album.title,
                    artistName: album.artistName
                )
            }

            guard response.items.hasNextBatch,
                  albums.count == pageSize else { return }
            offset += albums.count
        }
        preparedLibraryAlbumArtwork = false
    }

    private func artworkURL(
        from song: MusicKit.Song,
        preferredSource: MusicPropertySource? = nil
    ) async -> URL? {
        if let direct = Self.renderableArtworkURL(
            song.artwork?.url(width: 1200, height: 1200)
        ) {
            return direct
        }
        if let albumArtwork = Self.renderableArtworkURL(
            song.albums?.first?.artwork?.url(width: 1200, height: 1200)
        ) {
            return albumArtwork
        }

        var hydrated: MusicKit.Song?
        if let preferredSource {
            hydrated = try? await Self.performMusicKitRequest {
                try await song.with(
                    [.albums],
                    preferredSource: preferredSource
                )
            }
        }
        if hydrated == nil {
            hydrated = try? await Self.performMusicKitRequest {
                try await song.with(.albums)
            }
        }
        guard let hydrated else {
            return nil
        }
        songCache[song.id.rawValue] = hydrated
        return Self.firstRenderableArtworkURL(
            hydrated.artwork?.url(width: 1200, height: 1200),
            hydrated.albums?.first?.artwork?.url(width: 1200, height: 1200)
        )
    }

    private func cacheArtworkURL(
        _ url: URL,
        for song: Song,
        source: MusicKit.Song
    ) {
        guard Self.renderableArtworkURL(url) != nil else { return }
        artworkURLCache[song.appleMusicCatalogID ?? String(song.id)] = url
        artworkURLCache[source.id.rawValue] = url
        songCache[source.id.rawValue] = source
        enforceMemoryLimitsIfNeeded()
        SongArtworkFallbackRegistry.shared.registerResolvedArtwork(url, for: song)
    }

    private static func artworkMatchScore(
        _ candidate: MusicKit.Song,
        target: Song
    ) -> Double {
        let targetTitle = normalizedArtworkMatchText(target.name)
        let targetArtist = normalizedArtworkMatchText(target.artistName)
        let candidateTitle = normalizedArtworkMatchText(candidate.title)
        let candidateArtist = normalizedArtworkMatchText(candidate.artistName)

        let titleScore = targetTitle == candidateTitle
            ? 1.0
            : (targetTitle.contains(candidateTitle) || candidateTitle.contains(targetTitle) ? 0.82 : 0)
        let artistScore = targetArtist.isEmpty || targetArtist == candidateArtist
            ? 1.0
            : (targetArtist.contains(candidateArtist) || candidateArtist.contains(targetArtist) ? 0.76 : 0)

        let durationScore: Double = {
            guard let targetDuration = target.dt,
                  let candidateDuration = candidate.duration else {
                return 0.72
            }
            let difference = abs(Double(targetDuration) / 1_000 - candidateDuration)
            switch difference {
            case 0...3: return 1
            case 3...8: return 0.82
            case 8...15: return 0.55
            default: return 0
            }
        }()

        return titleScore * 0.58 + artistScore * 0.27 + durationScore * 0.15
    }

    private nonisolated static func normalizedArtworkMatchText(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
    }

    private nonisolated static func animatedArtworkMatchCacheKey(for song: Song) -> String {
        let title = normalizedArtworkMatchText(song.name)
        let artist = normalizedArtworkMatchText(song.artistName)
        let album = normalizedArtworkMatchText(song.al?.name ?? "")
        let durationBucket = (song.dt ?? 0) / 5_000
        return "match|\(song.musicSource.rawValue)|\(title)|\(artist)|\(album)|\(durationBucket)"
    }

    /// MusicKit 资料库对象可能返回 `musicKit://artwork/...`，该地址只供
    /// Apple 内部渲染，URLSession/CachedAsyncImage 无法读取。
    private nonisolated static func renderableArtworkURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        switch url.scheme?.lowercased() {
        case "https", "http", "file":
            return url
        default:
            return nil
        }
    }

    private nonisolated static func firstRenderableArtworkURL(
        _ urls: URL?...
    ) -> URL? {
        for url in urls {
            if let resolved = renderableArtworkURL(url) {
                return resolved
            }
        }
        return nil
    }

    private static func libraryAlbumArtworkKey(
        albumTitle: String,
        artistName: String
    ) -> String {
        "album|\(normalizedArtworkMatchText(albumTitle))|\(normalizedArtworkMatchText(artistName))"
    }

    private static func libraryAlbumTitleArtworkKey(
        albumTitle: String
    ) -> String {
        "title|\(normalizedArtworkMatchText(albumTitle))"
    }

    private func cacheLibraryAlbumArtwork(
        _ url: URL,
        albumTitle: String,
        artistName: String
    ) {
        guard Self.renderableArtworkURL(url) != nil else { return }
        let normalizedTitle = Self.normalizedArtworkMatchText(albumTitle)
        guard !normalizedTitle.isEmpty else { return }

        libraryAlbumArtworkCache[
            Self.libraryAlbumArtworkKey(
                albumTitle: albumTitle,
                artistName: artistName
            )
        ] = url

        // 资料库歌曲经常返回曲目艺人，而专辑条目返回专辑艺人。
        // 精确键匹配不到时，用专辑名作为同一资料库内的稳定回退。
        let titleKey = Self.libraryAlbumTitleArtworkKey(albumTitle: albumTitle)
        if libraryAlbumArtworkCache[titleKey] == nil {
            libraryAlbumArtworkCache[titleKey] = url
        }
        enforceMemoryLimitsIfNeeded()
    }

    private func cachedLibraryAlbumArtwork(
        albumTitle: String,
        artistName: String
    ) -> URL? {
        libraryAlbumArtworkCache[
            Self.libraryAlbumArtworkKey(
                albumTitle: albumTitle,
                artistName: artistName
            )
        ] ?? libraryAlbumArtworkCache[
            Self.libraryAlbumTitleArtworkKey(albumTitle: albumTitle)
        ]
    }

    private static func mediaLibraryArtworkRequest(
        for source: MusicKit.Song
    ) -> AppleMediaLibraryArtworkRequest {
        let title = normalizedArtworkMatchText(source.title)
        let artist = normalizedArtworkMatchText(source.artistName)
        let album = normalizedArtworkMatchText(source.albumTitle ?? "")
        return AppleMediaLibraryArtworkRequest(
            identityKey: source.id.rawValue,
            exactKey: "\(title)|\(artist)|\(album)",
            titleArtistKey: "\(title)|\(artist)",
            titleAlbumKey: "\(title)|\(album)",
            titleKey: title
        )
    }

    private nonisolated static func materializeMediaLibraryArtwork(
        for requests: [AppleMediaLibraryArtworkRequest]
    ) async -> [String: URL] {
        guard !requests.isEmpty,
              await requestMediaLibraryAuthorizationIfNeeded() else {
            return [:]
        }

        return await Task.detached(priority: .utility) {
            var exactRequests: [String: [AppleMediaLibraryArtworkRequest]] = [:]
            var titleArtistRequests: [String: [AppleMediaLibraryArtworkRequest]] = [:]
            var titleAlbumRequests: [String: [AppleMediaLibraryArtworkRequest]] = [:]
            var titleRequests: [String: [AppleMediaLibraryArtworkRequest]] = [:]

            for request in requests {
                exactRequests[request.exactKey, default: []].append(request)
                titleArtistRequests[request.titleArtistKey, default: []].append(request)
                titleAlbumRequests[request.titleAlbumKey, default: []].append(request)
                titleRequests[request.titleKey, default: []].append(request)
            }

            let fileManager = FileManager.default
            guard let cachesDirectory = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                return [:]
            }
            let artworkDirectory = cachesDirectory
                .appendingPathComponent("AppleMusicLibraryArtwork", isDirectory: true)
            do {
                try fileManager.createDirectory(
                    at: artworkDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                return [:]
            }

            var resolved: [String: URL] = [:]
            let mediaItems = MPMediaQuery.songs().items ?? []
            for item in mediaItems where resolved.count < requests.count {
                guard let rawTitle = item.title else { continue }
                let title = normalizedArtworkMatchText(rawTitle)
                guard !title.isEmpty else { continue }

                let album = normalizedArtworkMatchText(item.albumTitle ?? "")
                let artists = [item.artist, item.albumArtist]
                    .compactMap { $0 }
                    .map(normalizedArtworkMatchText)
                    .filter { !$0.isEmpty }

                var matches: [AppleMediaLibraryArtworkRequest] = []
                for artist in artists {
                    matches.append(
                        contentsOf: exactRequests["\(title)|\(artist)|\(album)"] ?? []
                    )
                }
                if matches.isEmpty {
                    for artist in artists {
                        matches.append(
                            contentsOf: titleArtistRequests["\(title)|\(artist)"] ?? []
                        )
                    }
                }
                if matches.isEmpty {
                    matches = titleAlbumRequests["\(title)|\(album)"] ?? []
                }
                if matches.isEmpty,
                   let titleMatches = titleRequests[title],
                   titleMatches.count == 1 {
                    matches = titleMatches
                }

                var seen = Set<String>()
                let uniqueMatches = matches.filter {
                    seen.insert($0.identityKey).inserted &&
                        resolved[$0.identityKey] == nil
                }
                guard !uniqueMatches.isEmpty else { continue }

                var missing: [(request: AppleMediaLibraryArtworkRequest, url: URL)] = []
                for request in uniqueMatches {
                    let fileURL = artworkDirectory
                        .appendingPathComponent(
                            "\(mediaLibraryArtworkFileID(request.identityKey)).jpg"
                        )
                    if fileManager.fileExists(atPath: fileURL.path) {
                        resolved[request.identityKey] = fileURL
                    } else {
                        missing.append((request, fileURL))
                    }
                }
                guard !missing.isEmpty,
                      let image = item.artwork?.image(
                          at: CGSize(width: 1_200, height: 1_200)
                      ),
                      let data = image.jpegData(compressionQuality: 0.9) else {
                    continue
                }

                for entry in missing {
                    do {
                        try data.write(to: entry.url, options: .atomic)
                        resolved[entry.request.identityKey] = entry.url
                    } catch {
                        continue
                    }
                }
            }
            return resolved
        }.value
    }

    private nonisolated static func requestMediaLibraryAuthorizationIfNeeded() async -> Bool {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func mediaLibraryArtworkFileID(
        _ value: String
    ) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func convert(
        _ source: MusicKit.Song,
        artworkURL resolvedArtworkURL: URL? = nil
    ) -> Song? {
        let catalogID = source.id.rawValue
        let numericID = Int(catalogID) ?? stableNumericID(for: catalogID)
        let artworkURL = firstRenderableArtworkURL(
            resolvedArtworkURL,
            source.artwork?.url(width: 1200, height: 1200)
        )?.absoluteString
        let durationMilliseconds = source.duration.map {
            Int(($0 * 1_000).rounded())
        }

        return Song(
            id: numericID,
            name: source.title,
            ar: [Artist(id: 0, name: source.artistName)],
            al: Album(
                id: 0,
                name: source.albumTitle ?? "",
                picUrl: artworkURL
            ),
            dt: durationMilliseconds,
            fee: 0,
            mv: 0,
            h: nil,
            m: nil,
            l: nil,
            sq: nil,
            hr: nil,
            alia: nil,
            source: .appleMusic,
            appleMusicID: catalogID,
            appleMusicISRC: source.isrc,
            genreTags: SongGenreMetadata.clean(source.genreNames)
        )
    }

    private static func convert(
        _ source: MusicKit.Playlist,
        artworkURL resolvedArtworkURL: URL? = nil,
        trackCount: Int? = nil
    ) -> Playlist? {
        let catalogID = source.id.rawValue
        let numericID = stableNumericID(for: "playlist:\(catalogID)")
        let artworkURL = firstRenderableArtworkURL(
            resolvedArtworkURL,
            source.artwork?.url(width: 1200, height: 1200)
        )?.absoluteString
        return Playlist(
            id: numericID,
            name: source.name,
            coverImgUrl: artworkURL,
            picUrl: nil,
            trackCount: trackCount,
            playCount: nil,
            subscribedCount: nil,
            shareCount: nil,
            commentCount: nil,
            creator: source.curatorName.map {
                PlaylistCreator(userId: 0, nickname: $0, avatarUrl: nil)
            },
            description: source.standardDescription ?? source.shortDescription,
            tags: nil,
            source: .appleMusic,
            appleMusicID: catalogID
        )
    }

    private static func convert(
        _ source: MusicKit.Artist,
        musicSize: Int? = nil,
        albumSize: Int? = nil,
        mvSize: Int? = nil
    ) -> ArtistInfo? {
        let catalogID = source.id.rawValue
        let numericID = stableNumericID(for: "artist:\(catalogID)")
        let artworkURL = renderableArtworkURL(
            source.artwork?.url(width: 1200, height: 1200)
        )?.absoluteString
        return ArtistInfo(
            id: numericID,
            name: source.name,
            picUrl: artworkURL,
            img1v1Url: artworkURL,
            cover: artworkURL,
            avatar: artworkURL,
            musicSize: musicSize,
            albumSize: albumSize,
            mvSize: mvSize,
            briefDesc: source.editorialNotes?.standard,
            alias: nil,
            followed: nil,
            accountId: nil,
            source: .appleMusic,
            qqMid: nil,
            appleMusicID: catalogID
        )
    }

    private static func convert(
        _ source: MusicKit.Album,
        artworkURL resolvedArtworkURL: URL? = nil
    ) -> AlbumInfo? {
        let catalogID = source.id.rawValue
        let numericID = stableNumericID(for: "album:\(catalogID)")
        let artworkURL = firstRenderableArtworkURL(
            resolvedArtworkURL,
            source.artwork?.url(width: 1200, height: 1200)
        )?.absoluteString
        let publishTime = source.releaseDate.map {
            Int($0.timeIntervalSince1970 * 1_000)
        }
        let artistInfo = ArtistInfo(
            id: stableNumericID(for: "album-artist:\(source.artistName)"),
            name: source.artistName,
            picUrl: nil,
            img1v1Url: nil,
            cover: nil,
            avatar: nil,
            musicSize: nil,
            albumSize: nil,
            mvSize: nil,
            briefDesc: nil,
            alias: nil,
            followed: nil,
            accountId: nil,
            source: .appleMusic
        )

        return AlbumInfo(
            id: numericID,
            name: source.title,
            picUrl: artworkURL,
            publishTime: publishTime,
            size: source.trackCount,
            artist: artistInfo,
            artists: [Artist(id: artistInfo.id, name: source.artistName)],
            description: source.editorialNotes?.standard,
            company: source.recordLabelName,
            subType: source.isSingle == true ? "Single" : nil,
            qqAlbumMid: nil,
            source: .appleMusic,
            appleMusicID: catalogID
        )
    }

    private static func stableNumericID(for rawValue: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in rawValue.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash & UInt64(Int.max))
    }
}
