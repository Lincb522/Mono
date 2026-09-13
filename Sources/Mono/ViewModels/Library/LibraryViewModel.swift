import SwiftUI
import Combine
@preconcurrency import QQMusicKit

// MARK: - LibraryViewModel (extracted from LibraryView.swift)

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var navigationPath = NavigationPath()

    enum LibraryTab: String, CaseIterable {
        case my = "My Library"
        case square = "Playlists"
        case artists = "Artists"
        case charts = "Charts"

        var localizedKey: LocalizedStringKey {
            switch self {
            case .my: return "tab_library"
            case .square: return "lib_tab_playlists"
            case .artists: return "lib_tab_artists"
            case .charts: return "lib_tab_charts"
            }
        }
    }

    enum NavigationDestination: Hashable {
        case playlist(Playlist)
        case artist(Int)
        case artistInfo(ArtistInfo)
        case qqArtist(mid: String, name: String, coverUrl: String?)
        case radioDetail(Int)
        case localPlaylist(String)
        case externalPlaylistImport

        func hash(into hasher: inout Hasher) {
            switch self {
            case .playlist(let p): hasher.combine("p_\(p.navigationIdentity)")
            case .artist(let id): hasher.combine("a_\(id)")
            case .artistInfo(let a): hasher.combine("a_\(a.navigationIdentity)")
            case .qqArtist(let mid, _, _): hasher.combine("qa_\(mid)")
            case .radioDetail(let id): hasher.combine("r_\(id)")
            case .localPlaylist(let id): hasher.combine("lp_\(id)")
            case .externalPlaylistImport: hasher.combine("external_playlist_import")
            }
        }

        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            switch (lhs, rhs) {
            case (.playlist(let l), .playlist(let r)): return l.navigationIdentity == r.navigationIdentity
            case (.artist(let l), .artist(let r)): return l == r
            case (.artistInfo(let l), .artistInfo(let r)): return l.navigationIdentity == r.navigationIdentity
            case (.qqArtist(let lm, _, _), .qqArtist(let rm, _, _)): return lm == rm
            case (.radioDetail(let l), .radioDetail(let r)): return l == r
            case (.localPlaylist(let l), .localPlaylist(let r)): return l == r
            case (.externalPlaylistImport, .externalPlaylistImport): return true
            default: return false
            }
        }
    }

    /// 歌单广场/歌手/榜单的音源选择
    enum MusicSource: String, CaseIterable {
        case ncm = "NCM"
        case qq = "QQ"
        case kugou = "KCM"
        case appleMusic = "Apple Music"

        var shortName: String {
            switch self {
            case .ncm: return "NCM"
            case .qq: return "QCM"
            case .kugou: return "KCM"
            case .appleMusic: return "AM"
            }
        }
    }

    @Published var currentTab: LibraryTab = .my

    @Published var userPlaylists: [Playlist] = [] {
        didSet { userPlaylistRevision &+= 1 }
    }
    @Published var kugouUserPlaylists: [Playlist] = [] {
        didSet { kugouUserPlaylistRevision &+= 1 }
    }

    // MARK: - Playlist Square (NCM)
    @Published var squarePlaylists: [Playlist] = []
    @Published var playlistCategories: [PlaylistCategory] = []
    @Published var selectedCategory: String = NSLocalizedString("filter_all", comment: "")
    @Published var squareOffset: Int = 0
    @Published var hasMoreSquarePlaylists: Bool = true
    @Published var isLoadingMoreSquare: Bool = false
    @Published var isLoadingSquare: Bool = false
    @Published var squareSource: MusicSource = .ncm

    // MARK: - Playlist Square (QQ)
    @Published var qqSquarePlaylists: [Playlist] = []
    @Published var isLoadingQQSquare: Bool = false
    @Published var qqPlaylistCategories: [(id: Int, name: String)] = []
    @Published var selectedQQCategoryId: Int = 3317
    @Published var selectedQQCategoryName: String = String(localized: "官方歌单")
    @Published var qqSquarePage: Int = 0
    @Published var hasMoreQQSquare: Bool = true
    @Published var isLoadingMoreQQSquare: Bool = false
    @Published var qqSquareSortId: Int = 5

    // MARK: - Playlist Square (KCM)
    @Published var kugouSquarePlaylists: [Playlist] = []
    @Published var kugouPlaylistCategories: [KCMPlaylistCategory] = []
    @Published var selectedKugouCategoryID: Int = 0
    @Published var kugouSquarePage: Int = 1
    @Published var hasMoreKugouSquare: Bool = true
    @Published var isLoadingKugouSquare: Bool = false
    @Published var isLoadingMoreKugouSquare: Bool = false

    // MARK: - Playlist Square (Apple Music)
    @Published var appleMusicSquarePlaylists: [Playlist] = []
    @Published var isLoadingAppleMusicSquare: Bool = false
    @Published var isLoadingMoreAppleMusicSquare: Bool = false
    @Published var hasMoreAppleMusicSquare: Bool = true
    @Published var appleMusicSquarePage: Int = 0
    @Published var appleMusicSquareKeyword: String = String(localized: "apple_music_featured_playlists_query")

    // MARK: - Artists (NCM)
    @Published var topArtists: [ArtistInfo] = []
    @Published var artistOffset: Int = 0
    @Published var hasMoreArtists: Bool = true
    @Published var isLoadingArtists: Bool = false
    @Published var artistSource: MusicSource = .ncm

    // MARK: - Artists (QQ)
    @Published var qqArtists: [ArtistInfo] = []
    @Published var qqArtistPage: Int = 1
    @Published var qqArtistSin: Int = 0
    @Published var hasMoreQQArtists: Bool = true
    @Published var isLoadingQQArtists: Bool = false
    @Published var qqArtistArea: AreaType = .all
    @Published var qqArtistSex: SexType = .all
    @Published var qqArtistGenre: GenreType = .all
    @Published var qqArtistSearchText: String = ""
    @Published var isSearchingQQArtists: Bool = false

    // MARK: - Artists (KCM)
    @Published var kugouArtists: [ArtistInfo] = []
    @Published var isLoadingKugouArtists: Bool = false
    @Published var isSearchingKugouArtists: Bool = false
    @Published var kugouArtistSearchText: String = ""
    @Published var kugouArtistType: Int = 0
    @Published var kugouArtistSex: Int = 0

    // MARK: - Artists (Apple Music)
    @Published var appleMusicArtists: [ArtistInfo] = []
    @Published var appleMusicArtistPage: Int = 0
    @Published var hasMoreAppleMusicArtists: Bool = true
    @Published var isLoadingAppleMusicArtists: Bool = false
    @Published var isSearchingAppleMusicArtists: Bool = false
    @Published var appleMusicArtistSearchText: String = ""
    @Published var appleMusicArtistKeyword: String = String(localized: "apple_music_featured_artists_query")
    @Published var appleMusicArtistCategory: Int = 0

    let qqArtistAreas: [(name: String, value: AreaType)] = [
        ("filter_all", .all), ("filter_chinese", .china), ("filter_western", .america),
        ("filter_japanese", .japan), ("filter_korean", .korea), (String(localized: "台湾"), .taiwan)
    ]
    let qqArtistSexes: [(name: String, value: SexType)] = [
        ("filter_all", .all), ("filter_male", .male), ("filter_female", .female), ("filter_band", .group)
    ]
    let qqArtistGenres: [(name: String, value: GenreType)] = [
        ("filter_all", .all), (String(localized: "流行"), .pop), (String(localized: "说唱"), .rap), (String(localized: "摇滚"), .rock),
        (String(localized: "电子"), .electronic), (String(localized: "民谣"), .folk), ("R&B", .rnb), (String(localized: "爵士"), .jazz), (String(localized: "古典"), .classical)
    ]

    let kugouArtistTypes: [(name: String, value: Int)] = [
        ("filter_all", 0), ("filter_chinese", 1), (String(localized: "粤语"), 7),
        (String(localized: "闽南语"), 8), ("filter_korean", 6), ("filter_japanese", 5),
        ("filter_western", 2), ("filter_others", 4),
    ]
    let kugouArtistSexes: [(name: String, value: Int)] = [
        ("filter_all", 0), ("filter_male", 1), ("filter_female", 2), ("filter_band", 3),
    ]
    let appleMusicArtistCategories: [(name: String, keyword: String)] = [
        ("filter_chinese", String(localized: "apple_music_featured_artists_query")),
        ("filter_western", "欧美 歌手"),
        (String(localized: "日韩"), "日韩 歌手"),
    ]

    // MARK: - Charts (NCM)
    @Published var topLists: [TopList] = []
    @Published var chartsSource: MusicSource = .ncm

    // MARK: - Charts (QQ)
    @Published var qqTopLists: [QQTopListGroup] = []
    @Published var isLoadingQQCharts: Bool = false

    // MARK: - Charts (KCM)
    @Published var kugouTopLists: [TopList] = []
    @Published var isLoadingKugouCharts: Bool = false

    @Published var appleMusicTopLists: [TopList] = []
    @Published var isLoadingAppleMusicCharts = false

    var displayedTopLists: [TopList] {
        switch chartsSource {
        case .ncm: return topLists
        case .kugou: return kugouTopLists
        case .appleMusic: return appleMusicTopLists
        case .qq:
            return qqTopLists.flatMap(\.items).map { item in
                TopList(
                    id: item.topId, name: item.title, coverImgUrl: item.coverUrl,
                    updateFrequency: item.updateTime, source: .qqmusic
                )
            }
        }
    }

    var isLoadingDisplayedCharts: Bool {
        switch chartsSource {
        case .ncm: return isLoadingCharts
        case .qq: return isLoadingQQCharts
        case .kugou: return isLoadingKugouCharts
        case .appleMusic: return isLoadingAppleMusicCharts
        }
    }

    @Published var artistArea: Int = -1
    @Published var artistType: Int = -1
    @Published var artistInitial: String = "-1"
    @Published var artistSearchText: String = ""
    @Published var isSearchingArtists = false

    let artistAreas: [(name: String, value: Int)] = [
        ("filter_all", -1), ("filter_chinese", 7), ("filter_western", 96), ("filter_japanese", 8), ("filter_korean", 16), ("filter_others", 0)
    ]
    let artistTypes: [(name: String, value: Int)] = [
        ("filter_all", -1), ("filter_male", 1), ("filter_female", 2), ("filter_band", 3)
    ]
    let artistInitials: [String] = ["-1"] + (65...90).map { String(UnicodeScalar($0)) } + ["#"]

    @Published var isLoadingCharts: Bool = false
    @Published var isLoading = false

    var cancellables = Set<AnyCancellable>()
    let playlistStatusRequest = LibraryRequestScope()
    let userPlaylistRequest = LibraryRequestScope()
    let kugouUserPlaylistRequest = LibraryRequestScope()
    let playlistCacheRequest = LibraryRequestScope()
    var playlistRequestSession: APIService.NCMSessionSnapshot?
    var kugouPlaylistRequestSession: KCMMusicService.SessionSnapshot?
    var playlistCacheNCMSession: APIService.NCMSessionSnapshot?
    var playlistCacheKCMSession: KCMMusicService.SessionSnapshot?
    var userPlaylistRevision = 0
    var kugouUserPlaylistRevision = 0
    let chartsRequest = LibraryRequestScope()
    let qqChartsRequest = LibraryRequestScope()
    let kugouChartsRequest = LibraryRequestScope()
    let appleChartsRequest = LibraryRequestScope()
    let categoryRequest = LibraryRequestScope()
    let qqCategoryRequest = LibraryRequestScope()
    let kugouCategoryRequest = LibraryRequestScope()
    let squareRequest = LibraryRequestScope()
    let qqSquareRequest = LibraryRequestScope()
    let kugouSquareRequest = LibraryRequestScope()
    let appleSquareRequest = LibraryRequestScope()
    let artistRequest = LibraryRequestScope()
    let qqArtistRequest = LibraryRequestScope()
    let kugouArtistRequest = LibraryRequestScope()
    let appleArtistRequest = LibraryRequestScope()

    let apiService = APIService.shared
    var playlistRetryCount = 0
    let maxPlaylistRetries = 2

    init() {
        // 订阅 GlobalRefreshManager 的刷新事件
        GlobalRefreshManager.shared.refreshLibraryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] force in
                self?.fetchPlaylists(force: force)
            }
            .store(in: &cancellables)
        
        // 监听登录成功，强制刷新歌单
        NotificationCenter.default.publisher(for: .didLogin)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.apiService.isLoggedIn else { return }
                self.playlistRetryCount = 0
                self.userPlaylists = []
                SubscriptionManager.shared.resetRemoteNCMState()
                self.fetchPlaylists(force: true)
            }
            .store(in: &cancellables)
        
        // .didLogout 属于 NCM 会话，不影响仍有效的 QCM / KCM 数据。
        NotificationCenter.default.publisher(for: .didLogout)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleNCMLogout()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .kcmSessionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleKCMSessionDidChange()
            }
            .store(in: &cancellables)

        $artistSearchText
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(AppConfig.UI.searchDebounceMs), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.searchArtists(keyword: text)
                } else {
                    self?.fetchArtistData(reset: true)
                }
            }
            .store(in: &cancellables)

        $qqArtistSearchText
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(AppConfig.UI.searchDebounceMs), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.searchQQArtists(keyword: text)
                } else {
                    self?.isSearchingQQArtists = false
                    self?.fetchQQArtistData(reset: true)
                }
            }
            .store(in: &cancellables)

        $kugouArtistSearchText
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(AppConfig.UI.searchDebounceMs), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self?.isSearchingKugouArtists = false
                    self?.fetchKugouArtistData(reset: true)
                } else {
                    self?.searchKugouArtists(keyword: text)
                }
            }
            .store(in: &cancellables)

        $appleMusicArtistSearchText
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(AppConfig.UI.searchDebounceMs), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                if !text.isEmpty {
                    self.searchAppleMusicArtists(keyword: text)
                } else {
                    self.isSearchingAppleMusicArtists = false
                    self.fetchAppleMusicArtistData(reset: true)
                }
            }
            .store(in: &cancellables)
    }

    func fetchSquareForSelectedSource() {
        switch squareSource {
        case .ncm:
            fetchSquareData()
        case .qq:
            fetchQQSquareData()
        case .kugou:
            fetchKugouSquareData()
        case .appleMusic:
            fetchAppleMusicSquareData()
        }
    }

    func fetchArtistsForSelectedSource(reset: Bool = false) {
        switch artistSource {
        case .ncm:
            guard reset || topArtists.isEmpty else { return }
            fetchArtistData(reset: reset)
        case .qq:
            guard reset || qqArtists.isEmpty else { return }
            fetchQQArtistData(reset: reset)
        case .appleMusic:
            guard reset || appleMusicArtists.isEmpty else { return }
            fetchAppleMusicArtistData(reset: reset)
        case .kugou:
            guard reset || kugouArtists.isEmpty else { return }
            fetchKugouArtistData(reset: reset)
        }
    }

    func fetchChartsForSelectedSource(force: Bool = false) {
        switch chartsSource {
        case .ncm:
            if force {
                chartsRequest.cancel()
                topLists = []
                OptimizedCacheManager.shared.setObject([TopList](), forKey: "top_charts_lists")
            }
            fetchTopLists()
        case .appleMusic:
            if force {
                appleChartsRequest.cancel()
                appleMusicTopLists = []
            }
            fetchAppleMusicTopLists()
        case .qq:
            if force {
                qqChartsRequest.cancel()
                qqTopLists = []
                OptimizedCacheManager.shared.setObject([QQTopListGroup](), forKey: "qq_top_charts")
            }
            fetchQQTopLists()
        case .kugou:
            if force {
                kugouChartsRequest.cancel()
                kugouTopLists = []
                OptimizedCacheManager.shared.setObject([TopList](), forKey: "kcm_top_charts")
            }
            fetchKugouTopLists()
        }
    }
}
