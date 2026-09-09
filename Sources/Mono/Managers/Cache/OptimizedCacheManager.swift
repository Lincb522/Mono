import Foundation
import Combine
import UIKit
import SwiftUI

/// 优化的缓存管理器
/// 三级缓存架构：内存缓存 -> 本地数据库 -> 磁盘文件缓存
@MainActor
final class OptimizedCacheManager: ObservableObject {
    static let shared = OptimizedCacheManager()
    
    // MARK: - 内存缓存（L1）
    private let memoryCache = NSCache<NSString, AnyObject>()
    private struct MemoryEntryMetadata {
        let cost: Int
        var lastAccess: UInt64
    }
    private var memoryEntries: [String: MemoryEntryMetadata] = [:]
    private var memoryAccessSequence: UInt64 = 0
    private var memoryBudgetBytes = AppConfig.Cache.memoryLimit
    private var memoryCountLimit = 200
    
    // MARK: - 数据库仓库（L2）
    private lazy var songRepo = SongRepository()
    private lazy var playlistRepo = PlaylistRepository()
    private lazy var historyRepo = HistoryRepository()
    
    // MARK: - 磁盘缓存（L3）- 用于大文件如图片
    private let diskCache = CacheManager.shared
    
    // MARK: - 预加载状态
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0
    @Published var preloadStage: PreloadStage = .idle
    
    // MARK: - 数据就绪状态
    @Published var isDailySongsReady = false
    @Published var isPlaylistsReady = false
    @Published var isUserDataReady = false
    
    // MARK: - 缓存配置
    private let cacheValidityDuration: TimeInterval = AppConfig.Cache.defaultTTL
    
    private var cancellables = Set<AnyCancellable>()
    
    // 预加载阶段
    enum PreloadStage: String {
        case idle = "空闲"
        case loadingFromDB = "从数据库加载"
        case loadingFromDisk = "从磁盘加载"
        case fetchingFromNetwork = "从网络获取"
        case complete = "完成"
    }
    
    private struct QuickPreloadSnapshot: Sendable {
        struct WarmedEntry: Sendable {
            let key: String
            let data: Data
        }
        
        let warmedEntries: [WarmedEntry]
        let hasDailySongs: Bool
        let hasRecommendedPlaylists: Bool
    }
    
    private init() {
        memoryCache.totalCostLimit = memoryBudgetBytes
        memoryCache.countLimit = 200

        MonoMemoryEngine.shared.registerResource(
            id: "cache.models",
            priority: .essential,
            budgetWeight: 0.24,
            minimumBudgetBytes: 20 * 1_024 * 1_024,
            applyBudget: { [weak self] bytes in
                self?.applyMemoryBudget(bytes)
            },
            trim: { [weak self] context in
                self?.trimMemory(context) ?? .none
            },
            measureUsage: { [weak self] in
                self?.memoryUsage() ?? .unknown
            }
        )
    }

    private func storeInMemory(
        _ object: AnyObject,
        forKey key: NSString,
        cost explicitCost: Int? = nil
    ) {
        let cost = max(1, explicitCost ?? estimatedMemoryCost(of: object))
        memoryAccessSequence &+= 1
        memoryEntries[key as String] = MemoryEntryMetadata(
            cost: cost,
            lastAccess: memoryAccessSequence
        )
        memoryCache.setObject(object, forKey: key, cost: cost)
        evictMemoryMetadataOverflowIfNeeded()
    }

    private func memoryObject(forKey key: NSString) -> AnyObject? {
        guard let object = memoryCache.object(forKey: key) else {
            memoryEntries.removeValue(forKey: key as String)
            return nil
        }
        memoryAccessSequence &+= 1
        if var metadata = memoryEntries[key as String] {
            metadata.lastAccess = memoryAccessSequence
            memoryEntries[key as String] = metadata
        }
        return object
    }

    private func clearMemoryObjects() {
        memoryCache.removeAllObjects()
        memoryEntries.removeAll(keepingCapacity: false)
    }

    private func estimatedMemoryCost(of object: AnyObject) -> Int {
        if let data = object as? NSData { return max(1, data.length) }
        if let string = object as? NSString { return max(64, string.length * 2) }
        if let array = object as? NSArray { return max(1_024, array.count * 1_024) }
        if let dictionary = object as? NSDictionary { return max(1_024, dictionary.count * 768) }
        return 4 * 1_024
    }

    private func applyMemoryBudget(_ bytes: Int) {
        memoryBudgetBytes = max(8 * 1_024 * 1_024, bytes)
        memoryCountLimit = max(64, min(400, memoryBudgetBytes / (256 * 1_024)))
        memoryCache.totalCostLimit = memoryBudgetBytes
        memoryCache.countLimit = memoryCountLimit
        evictMemoryMetadataOverflowIfNeeded()
    }

    private func evictMemoryMetadataOverflowIfNeeded() {
        let overflow = memoryEntries.count - memoryCountLimit
        guard overflow > 0 else { return }
        for key in memoryEntries
            .sorted(by: { $0.value.lastAccess < $1.value.lastAccess })
            .prefix(overflow)
            .map(\.key) {
            memoryCache.removeObject(forKey: key as NSString)
            memoryEntries.removeValue(forKey: key)
        }
    }

    private func memoryUsage() -> MonoMemoryEngine.ResourceUsage {
        .init(
            itemCount: memoryEntries.count,
            estimatedBytes: memoryEntries.values.reduce(0) { $0 + $1.cost }
        )
    }

    private func trimMemory(_ context: MonoMemoryEngine.TrimContext) -> MonoMemoryEngine.TrimResult {
        let currentSong = PlayerManager.shared.currentSong
        let preservedKeys = Set([currentSong.map { "song_\($0.identityKey)" }].compactMap { $0 })
        let targetBytes: Int
        switch context.level {
        case .routine:
            targetBytes = memoryBudgetBytes
        case .background:
            targetBytes = max(8 * 1_024 * 1_024, memoryBudgetBytes / 3)
        case .warning:
            targetBytes = max(4 * 1_024 * 1_024, memoryBudgetBytes / 5)
        case .critical:
            targetBytes = 0
        }

        var currentBytes = memoryEntries.values.reduce(0) { $0 + $1.cost }
        var releasedBytes = 0
        var releasedItems = 0
        let candidates = memoryEntries
            .filter { !preservedKeys.contains($0.key) }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }

        for (key, metadata) in candidates where currentBytes > targetBytes {
            memoryCache.removeObject(forKey: key as NSString)
            memoryEntries.removeValue(forKey: key)
            currentBytes = max(0, currentBytes - metadata.cost)
            releasedBytes += metadata.cost
            releasedItems += 1
        }

        // 当前播放歌曲即使被 NSCache 自行淘汰，也从数据库轻量回填，确保回收
        // 不改变播放控制和 Now Playing 所依赖的歌曲模型。
        if let currentSong,
           memoryObject(forKey: "song_\(currentSong.identityKey)" as NSString) == nil,
           let dbSong = songRepo.getSong(id: currentSong.id, source: currentSong.musicSource) {
            storeInMemory(dbSong.toSong() as AnyObject, forKey: "song_\(currentSong.identityKey)" as NSString)
        }

        return .init(
            releasedItemCount: releasedItems,
            estimatedReleasedBytes: releasedBytes,
            preservedItemCount: preservedKeys.count
        )
    }
    
    // MARK: - 数据就绪检查
    
    var isAllDataReady: Bool {
        return isDailySongsReady && isPlaylistsReady
    }
    
    func resetDataReadyState() {
        isDailySongsReady = false
        isPlaylistsReady = false
        isUserDataReady = false
    }
    
    func markDailySongsReady() {
        isDailySongsReady = true
        AppLogger.success("每日推荐数据就绪")
    }
    
    func markPlaylistsReady() {
        isPlaylistsReady = true
        AppLogger.success("歌单数据就绪")
    }
    
    func markUserDataReady() {
        isUserDataReady = true
        AppLogger.success("用户数据就绪")
    }
    
    // MARK: - 预加载系统
    
    /// 预加载核心数据（登录后调用）
    /// 这是一个快速的本地缓存加载，不涉及网络请求
    func preloadCoreData() async {
        isPreloading = true
        preloadProgress = 0
        preloadStage = .loadingFromDB
        
        AppLogger.info("开始预加载核心数据...")
        
        // 1. 从数据库加载缓存的歌曲到内存 (20%)
        await preloadSongsToMemory()
        preloadProgress = 0.2
        
        // 2. 从数据库加载缓存的歌单到内存 (40%)
        await preloadPlaylistsToMemory()
        preloadProgress = 0.4
        
        // 3. 预热磁盘缓存的关键数据 (60%)
        preloadStage = .loadingFromDisk
        await warmupDiskCache()
        preloadProgress = 0.6
        
        // 4. 加载用户偏好数据 (80%)
        await loadUserPreferences()
        preloadProgress = 0.8
        
        // 5. 完成
        preloadProgress = 1.0
        preloadStage = .complete
        isPreloading = false
        
        AppLogger.success("核心数据预加载完成")
    }
    
    /// 快速预加载 - 仅加载最关键的数据用于首屏显示
    func quickPreload() async {
        isPreloading = true
        preloadProgress = 0
        preloadStage = .loadingFromDisk
        
        AppLogger.info("快速预加载开始...")
        
        let keysToWarmup = [
            "daily_songs",
            "popular_songs",
            "recent_songs",
            "qq_new_songs",
            "recommend_playlists",
            "user_playlists",
            "qq_recommend_playlists",
            "kcm_recommend_playlists",
            "user_profile_detail",
            "banners"
        ]
        let diskCache = CacheManager.shared
        
        let snapshot = await Task.detached(priority: .utility) {
            var warmedEntries: [QuickPreloadSnapshot.WarmedEntry] = []
            warmedEntries.reserveCapacity(keysToWarmup.count)
            
            for key in keysToWarmup {
                if let data = diskCache.getData(forKey: key) {
                    warmedEntries.append(.init(key: key, data: data))
                }
            }
            
            let warmedData = Dictionary(uniqueKeysWithValues: warmedEntries.map { ($0.key, $0.data) })
            let decoder = JSONDecoder()
            let hasDailySongs = warmedData["daily_songs"]
                .flatMap { try? decoder.decode([Song].self, from: $0) }
                .map { !$0.isEmpty } ?? false
            let hasRecommendedPlaylists = warmedData["recommend_playlists"]
                .flatMap { try? decoder.decode([Playlist].self, from: $0) }
                .map { !$0.isEmpty } ?? false
            
            return QuickPreloadSnapshot(
                warmedEntries: warmedEntries,
                hasDailySongs: hasDailySongs,
                hasRecommendedPlaylists: hasRecommendedPlaylists
            )
        }.value
        
        // 关键列表必须以解码后的模型放入 L1。旧实现放的是 NSData，后续
        // getObject(..., type: [Song].self) 无法命中，实际上仍会再次读取磁盘。
        let decoder = JSONDecoder()
        for entry in snapshot.warmedEntries {
            let cacheKey = entry.key as NSString
            switch entry.key {
            case "daily_songs", "popular_songs", "recent_songs", "qq_new_songs":
                if let songs = try? decoder.decode([Song].self, from: entry.data) {
                    storeInMemory(songs as AnyObject, forKey: cacheKey)
                    warmSongsInMemory(songs)
                }
            case "recommend_playlists", "user_playlists",
                 "qq_recommend_playlists", "kcm_recommend_playlists":
                if let playlists = try? decoder.decode([Playlist].self, from: entry.data) {
                    storeInMemory(playlists as AnyObject, forKey: cacheKey)
                    warmPlaylistsInMemory(playlists)
                }
            default:
                // 读取本身已完成文件页预热；未知模型不要用 NSData 污染同名 L1 键。
                break
            }
        }
        preloadProgress = 0.85
        
        isDailySongsReady = snapshot.hasDailySongs
        isPlaylistsReady = snapshot.hasRecommendedPlaylists
        preloadProgress = 1.0
        preloadStage = .complete
        isPreloading = false
        
        AppLogger.success("快速预加载完成")
    }
    
    /// 预加载歌曲到内存
    private func preloadSongsToMemory() async {
        // 把旧磁盘缓存先并入数据库。这样升级到 MonoVault 后第一次启动也能立刻预热，
        // 不必等应用进入后台执行同步。
        let diskSongs = mergedDiskSongCache()
        let restoredSongs = restoredPlaybackSongs()
        let seedSongs = mergeSongs(diskSongs + restoredSongs)
        if !seedSongs.isEmpty {
            warmSongsInMemory(seedSongs)
            songRepo.save(songs: seedSongs)
        }

        let candidates = songRepo.getWarmupCandidates(limit: 40)
        for dbSong in candidates {
            let song = dbSong.toSong()
            let cacheKey = "song_\(song.identityKey)" as NSString
            storeInMemory(song as AnyObject, forKey: cacheKey)
        }
        
        AppLogger.debug(
            "预加载了 \(candidates.count) 首歌曲到内存（磁盘回填 \(diskSongs.count) 首，播放状态回填 \(restoredSongs.count) 首）"
        )
    }
    
    /// 预加载歌单到内存
    private func preloadPlaylistsToMemory() async {
        let diskPlaylists = mergedDiskPlaylistCache()
        if !diskPlaylists.isEmpty {
            warmPlaylistsInMemory(diskPlaylists)
            playlistRepo.save(playlists: diskPlaylists)
        }

        let candidates = playlistRepo.getWarmupCandidates(limit: 20)
        for dbPlaylist in candidates {
            let playlist = dbPlaylist.toPlaylist()
            let cacheKey = "playlist_\(playlist.id)" as NSString
            storeInMemory(playlist as AnyObject, forKey: cacheKey)
        }
        
        AppLogger.debug("预加载了 \(candidates.count) 个歌单到内存（磁盘回填 \(diskPlaylists.count) 个）")
    }

    private func mergedDiskSongCache() -> [Song] {
        let keys = ["daily_songs", "popular_songs", "recent_songs", "qq_new_songs"]
        var songs: [Song] = []
        for key in keys {
            guard let cached = diskCache.getObject(forKey: key, type: [Song].self) else { continue }
            songs.append(contentsOf: cached)
        }
        return mergeSongs(songs)
    }

    private func restoredPlaybackSongs() -> [Song] {
        let player = PlayerManager.shared
        var songs = player.currentContextList
        songs.append(contentsOf: player.history)
        songs.append(contentsOf: player.podcastHistory)
        if let currentSong = player.currentSong {
            songs.insert(currentSong, at: 0)
        }
        return mergeSongs(songs)
    }

    private func mergeSongs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.identityKey).inserted }
    }

    private func mergedDiskPlaylistCache() -> [Playlist] {
        let keys = [
            "recommend_playlists",
            "user_playlists",
            "qq_recommend_playlists",
            "kcm_recommend_playlists"
        ]
        var seen = Set<Int>()
        var playlists: [Playlist] = []
        for key in keys {
            guard let cached = diskCache.getObject(forKey: key, type: [Playlist].self) else { continue }
            for playlist in cached where seen.insert(playlist.id).inserted {
                playlists.append(playlist)
            }
        }
        return playlists
    }

    private func warmSongsInMemory(_ songs: [Song]) {
        for song in songs {
            storeInMemory(song as AnyObject, forKey: "song_\(song.identityKey)" as NSString)
        }
    }

    private func warmPlaylistsInMemory(_ playlists: [Playlist]) {
        for playlist in playlists {
            storeInMemory(playlist as AnyObject, forKey: "playlist_\(playlist.id)" as NSString)
        }
    }
    
    /// 预热磁盘缓存
    private func warmupDiskCache() async {
        // 将关键的磁盘缓存数据加载到内存。列表型缓存必须保持模型类型，
        // 不能在 quickPreload 之后又被同名 NSData 覆盖。
        let keysToWarmup = [
            "daily_songs",
            "popular_songs", 
            "recent_songs",
            "qq_new_songs",
            "recommend_playlists",
            "user_playlists",
            "qq_recommend_playlists",
            "kcm_recommend_playlists",
            "user_profile_detail",
            "banners"
        ]
        let decoder = JSONDecoder()

        for key in keysToWarmup {
            guard let data = diskCache.getData(forKey: key) else { continue }
            let cacheKey = key as NSString
            switch key {
            case "daily_songs", "popular_songs", "recent_songs", "qq_new_songs":
                guard let songs = try? decoder.decode([Song].self, from: data) else { continue }
                storeInMemory(songs as AnyObject, forKey: cacheKey)
                warmSongsInMemory(songs)
            case "recommend_playlists", "user_playlists",
                 "qq_recommend_playlists", "kcm_recommend_playlists":
                guard let playlists = try? decoder.decode([Playlist].self, from: data) else { continue }
                storeInMemory(playlists as AnyObject, forKey: cacheKey)
                warmPlaylistsInMemory(playlists)
            default:
                // 读取即可预热文件页；未知模型由 getObject 按目标类型解码。
                break
            }
        }
        
        AppLogger.debug("磁盘缓存预热完成")
    }
    
    /// 加载用户偏好
    private func loadUserPreferences() async {
        // 加载搜索历史
        _ = historyRepo.getSearchHistory(limit: 20)
        
        // 加载播放历史
        _ = historyRepo.getPlayHistory(limit: 50)
        
        AppLogger.debug("用户偏好数据加载完成")
    }
    
    // MARK: - 后台同步
    
    /// 后台同步数据到数据库
    func syncToDatabase() async {
        AppLogger.info("开始后台同步数据到数据库...")
        
        // 同步每日推荐歌曲
        if let songs = diskCache.getObject(forKey: "daily_songs", type: [Song].self) {
            songRepo.save(songs: songs)
        }
        
        // 同步热门歌曲
        if let songs = diskCache.getObject(forKey: "popular_songs", type: [Song].self) {
            songRepo.save(songs: songs)
        }
        
        // 同步最近播放
        if let songs = diskCache.getObject(forKey: "recent_songs", type: [Song].self) {
            songRepo.save(songs: songs)
        }
        
        // 同步推荐歌单
        if let playlists = diskCache.getObject(forKey: "recommend_playlists", type: [Playlist].self) {
            playlistRepo.save(playlists: playlists)
        }
        
        // 同步用户歌单
        if let playlists = diskCache.getObject(forKey: "user_playlists", type: [Playlist].self) {
            playlistRepo.save(playlists: playlists)
        }
        
        // 记录同步时间
        UserDefaults.standard.set(Date(), forKey: AppConfig.StorageKeys.lastSyncTimestamp)
        
        AppLogger.success("后台同步完成")
    }
    
    /// 检查是否需要同步
    func shouldSync() -> Bool {
        guard let lastSync = UserDefaults.standard.object(forKey: AppConfig.StorageKeys.lastSyncTimestamp) as? Date else {
            return true
        }
        // 每小时同步一次
        return Date().timeIntervalSince(lastSync) > 3600
    }
    
    // MARK: - 智能刷新策略
    
    /// 检查是否需要刷新每日数据
    func shouldRefreshDailyData() -> Bool {
        guard let lastUpdate = UserDefaults.standard.object(forKey: AppConfig.StorageKeys.dailyCacheTimestamp) as? Date else {
            return true
        }
        
        let calendar = Calendar.current
        // 如果不是今天，需要刷新
        if !calendar.isDateInToday(lastUpdate) {
            return true
        }
        
        // 如果超过缓存有效期，需要刷新
        if Date().timeIntervalSince(lastUpdate) > cacheValidityDuration {
            return true
        }
        
        return false
    }
    
    /// 标记每日数据已刷新
    func markDailyDataRefreshed() {
        UserDefaults.standard.set(Date(), forKey: AppConfig.StorageKeys.dailyCacheTimestamp)
    }
    
    /// 智能获取数据（优先缓存，必要时刷新）
    func smartFetch<T: Codable>(
        key: String,
        type: T.Type,
        maxAge: TimeInterval = 3600, // 默认1小时
        fetcher: @escaping () async throws -> T
    ) async -> T? {
        // 1. 检查内存缓存
        let cacheKey = key as NSString
        if let cached = memoryObject(forKey: cacheKey) as? T {
            return cached
        }
        
        // 2. 检查磁盘缓存（带时间戳）
        let timestampKey = AppConfig.StorageKeys.timestampKey(for: key)
        if let diskCached = diskCache.getObject(forKey: key, type: type),
           let timestamp = UserDefaults.standard.object(forKey: timestampKey) as? Date,
           Date().timeIntervalSince(timestamp) < maxAge {
            // 缓存有效，回填内存
            storeInMemory(diskCached as AnyObject, forKey: cacheKey)
            return diskCached
        }
        
        // 3. 需要从网络获取
        do {
            let freshData = try await fetcher()
            // 更新所有缓存层
            storeInMemory(freshData as AnyObject, forKey: cacheKey)
            diskCache.setObject(freshData, forKey: key)
            UserDefaults.standard.set(Date(), forKey: timestampKey)
            return freshData
        } catch {
            AppLogger.error("获取数据失败: \(error)")
            // 返回过期的缓存数据（如果有）
            return diskCache.getObject(forKey: key, type: type)
        }
    }
    
    // MARK: - 歌曲缓存（增强版）
    
    /// 获取歌曲（优先内存 -> 数据库）
    func getSong(id: Int, source: MusicSource = .netease) -> Song? {
        let cacheKey = "song_\(source.rawValue):\(id)" as NSString
        
        // L1: 内存缓存
        if let cached = memoryObject(forKey: cacheKey) as? Song {
            return cached
        }
        
        // L2: 数据库
        if let dbSong = songRepo.getSong(id: id, source: source) {
            let song = dbSong.toSong()
            storeInMemory(song as AnyObject, forKey: cacheKey)
            return song
        }
        
        return nil
    }
    
    /// 批量获取歌曲（优化版）
    func getSongs(ids: [Int], source: MusicSource = .netease) -> [Song] {
        var result: [Song] = []
        var missedIds: [Int] = []
        
        // 先从内存获取
        for id in ids {
            let cacheKey = "song_\(source.rawValue):\(id)" as NSString
            if let cached = memoryObject(forKey: cacheKey) as? Song {
                result.append(cached)
            } else {
                missedIds.append(id)
            }
        }
        
        // 从数据库批量获取缺失的
        if !missedIds.isEmpty {
            let dbSongs = songRepo.getSongs(ids: missedIds, source: source)
            for dbSong in dbSongs {
                let song = dbSong.toSong()
                let cacheKey = "song_\(song.identityKey)" as NSString
                storeInMemory(song as AnyObject, forKey: cacheKey)
                result.append(song)
            }
        }
        
        return result
    }
    
    /// 缓存歌曲
    func cacheSong(_ song: Song) {
        let cacheKey = "song_\(song.identityKey)" as NSString
        storeInMemory(song as AnyObject, forKey: cacheKey)
        
        Task { @MainActor in
            self.songRepo.save(song: song)
        }
    }
    
    /// 批量缓存歌曲（优化版 - 批量写入）
    func cacheSongs(_ songs: [Song]) {
        // 先更新内存缓存
        for song in songs {
            let cacheKey = "song_\(song.identityKey)" as NSString
            storeInMemory(song as AnyObject, forKey: cacheKey)
        }
        
        // 异步批量写入数据库
        Task { @MainActor in
            self.songRepo.save(songs: songs)
        }
    }
    
    /// 记录歌曲播放
    func recordSongPlay(_ song: Song, duration: Int = 0, completed: Bool = false) {
        let trackDuration = max(0, (song.dt ?? 0) / 1_000)
        let effective = ListeningPlaybackPolicy.isEffective(
            actualPlayback: TimeInterval(max(0, duration)),
            trackDuration: TimeInterval(trackDuration)
        )

        // 兼容离线批量导入调用，但仍使用统一有效播放阈值。
        songRepo.save(song: song)
        if effective {
            songRepo.recordPlay(song: song)
        }
        let record = historyRepo.addPlayHistory(
            song: song,
            duration: max(0, duration),
            completed: completed && ListeningPlaybackPolicy.isCompleted(
                actualPlayback: TimeInterval(max(0, duration)),
                trackDuration: TimeInterval(trackDuration)
            )
        )
        record.trackDuration = trackDuration
        record.effectivePlay = effective
        record.qualificationVersion = ListeningPlaybackPolicy.qualificationVersion
        historyRepo.savePlayHistoryUpdates()
    }
    
    // MARK: - 歌单缓存（增强版）
    
    /// 获取歌单
    func getPlaylist(id: Int) -> Playlist? {
        let cacheKey = "playlist_\(id)" as NSString
        
        if let cached = memoryObject(forKey: cacheKey) as? Playlist {
            return cached
        }
        
        if let dbPlaylist = playlistRepo.getPlaylist(id: id) {
            let playlist = dbPlaylist.toPlaylist()
            storeInMemory(playlist as AnyObject, forKey: cacheKey)
            playlistRepo.recordAccess(playlistId: id)
            return playlist
        }
        
        return nil
    }
    
    /// 获取歌单的歌曲 ID 列表
    func getPlaylistTrackIds(playlistId: Int) -> [Int]? {
        if let dbPlaylist = playlistRepo.getPlaylist(id: playlistId) {
            return dbPlaylist.trackIds.isEmpty ? nil : dbPlaylist.trackIds
        }
        return nil
    }
    
    /// 缓存歌单
    func cachePlaylist(_ playlist: Playlist, trackIds: [Int] = []) {
        let cacheKey = "playlist_\(playlist.id)" as NSString
        storeInMemory(playlist as AnyObject, forKey: cacheKey)
        
        Task.detached { @MainActor in
            self.playlistRepo.save(playlist: playlist, trackIds: trackIds)
        }
    }
    
    /// 批量缓存歌单
    func cachePlaylists(_ playlists: [Playlist]) {
        for playlist in playlists {
            let cacheKey = "playlist_\(playlist.id)" as NSString
            storeInMemory(playlist as AnyObject, forKey: cacheKey)
        }
        
        Task.detached { @MainActor in
            self.playlistRepo.save(playlists: playlists)
        }
    }
    
    /// 更新歌单歌曲列表
    func updatePlaylistTracks(playlistId: Int, songs: [Song]) {
        let trackIds = songs.map { $0.id }
        playlistRepo.updateTrackIds(playlistId: playlistId, trackIds: trackIds)
        cacheSongs(songs)
    }
    
    // MARK: - 历史记录
    
    func getPlayHistory(limit: Int = 100) -> [PlayHistory] {
        return historyRepo.getPlayHistory(limit: limit)
    }
    
    func getSearchHistory(limit: Int = 20) -> [SearchHistory] {
        return historyRepo.getSearchHistory(limit: limit)
    }
    
    func addSearchHistory(keyword: String, resultCount: Int = 0) {
        historyRepo.addSearchHistory(keyword: keyword, resultCount: resultCount)
    }
    
    func deleteSearchHistory(keyword: String) {
        historyRepo.deleteSearchHistory(keyword: keyword)
    }
    
    func clearSearchHistory() {
        historyRepo.clearSearchHistory()
    }
    
    // MARK: - 歌词缓存
    
    func getLyrics(songId: Int, source: MusicSource = .netease) -> (lyrics: String, translated: String?)? {
        if let cached = historyRepo.getLyrics(songId: songId, source: source) {
            return (cached.lyrics, cached.translatedLyrics)
        }
        return nil
    }
    
    func cacheLyrics(songId: Int, source: MusicSource = .netease, lyrics: String, translated: String? = nil) {
        historyRepo.saveLyrics(songId: songId, source: source, lyrics: lyrics, translated: translated)
    }

    func removeLyrics(songId: Int, source: MusicSource = .netease) {
        historyRepo.deleteLyrics(songId: songId, source: source)
    }
    
    // MARK: - 通用对象缓存（兼容旧 API）
    
    func getObject<T: Codable>(forKey key: String, type: T.Type) -> T? {
        let cacheKey = key as NSString
        
        if let cached = memoryObject(forKey: cacheKey) as? T {
            return cached
        }
        
        if let diskCached = diskCache.getObject(forKey: key, type: type) {
            storeInMemory(diskCached as AnyObject, forKey: cacheKey)
            return diskCached
        }
        
        return nil
    }

    /// UI-safe cache restore. Memory hits remain immediate and disk access no
    /// longer blocks the main actor. Decoding stays actor-isolated so model types
    /// do not need to opt in to `Sendable` merely for cache restoration.
    func getObjectAsync<T: Codable>(forKey key: String, type: T.Type) async -> T? {
        let cacheKey = key as NSString
        if let cached = memoryObject(forKey: cacheKey) as? T {
            return cached
        }

        guard let data = await diskCache.getDataAsync(forKey: key) else {
            return nil
        }
        let decoded = try? JSONDecoder().decode(T.self, from: data)
        if let decoded {
            storeInMemory(decoded as AnyObject, forKey: cacheKey, cost: data.count)
        }
        return decoded
    }
    
    func setObject<T: Codable>(_ object: T, forKey key: String, ttl: TimeInterval? = nil) {
        let cacheKey = key as NSString
        let encodedCost = (try? JSONEncoder().encode(object).count)
        storeInMemory(object as AnyObject, forKey: cacheKey, cost: encodedCost)
        diskCache.setObject(object, forKey: key, ttl: ttl)
    }

    func setObjectInBackground<T: Codable & Sendable>(
        _ object: T,
        forKey key: String,
        estimatedCost: Int
    ) {
        // Make reads immediately consistent without encoding just to count bytes.
        storeInMemory(object as AnyObject, forKey: key as NSString, cost: estimatedCost)
        diskCache.setObjectInBackground(object, forKey: key)
    }

    func clearNCMAccountData() {
        let keys = [
            AppConfig.CacheKeys.dailySongs,
            AppConfig.CacheKeys.recommendPlaylists,
            AppConfig.CacheKeys.recentSongs,
            AppConfig.CacheKeys.userProfile,
            AppConfig.CacheKeys.userPlaylists,
        ]

        for key in keys {
            memoryCache.removeObject(forKey: key as NSString)
            memoryEntries.removeValue(forKey: key)
            diskCache.removeObject(forKey: key)
            UserDefaults.standard.removeObject(
                forKey: AppConfig.StorageKeys.timestampKey(for: key)
            )
        }

        UserDefaults.standard.removeObject(forKey: AppConfig.StorageKeys.dailyCacheTimestamp)
        resetDataReadyState()
    }
    
    // MARK: - 内存管理
    
    /// 清理过期数据（增强版 — 触发数据库维护）
    func cleanupExpiredData() async {
        DatabaseManager.shared.performMaintenance()
        DatabaseManager.shared.cleanExpiredData(olderThan: 30)
    }
    
    /// 清空所有缓存（保留下载记录和本地歌单）
    func clearAll() {
        clearMemoryObjects()
        DatabaseManager.shared.clearCacheData()
        diskCache.clearAll()
        UserDefaults.standard.removeObject(forKey: AppConfig.StorageKeys.dailyCacheTimestamp)
    }
    
    // MARK: - 智能预取
    
    /// 预取即将播放的歌曲信息（基于播放队列）
    func prefetchUpcomingSongs(queue: [Song], currentIndex: Int, count: Int = 3) {
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + count, queue.count)
        guard startIndex < endIndex else { return }
        
        let upcoming = Array(queue[startIndex..<endIndex])
        
        // 预加载到内存缓存
        for song in upcoming {
            let cacheKey = "song_\(song.identityKey)" as NSString
            if memoryObject(forKey: cacheKey) == nil {
                storeInMemory(song as AnyObject, forKey: cacheKey)
            }
        }
        
        // 异步写入数据库
        Task { @MainActor in
            self.songRepo.save(songs: upcoming)
        }
    }
    
    /// 预取歌单详情（用户可能点击的歌单）
    func prefetchPlaylistIfNeeded(id: Int) {
        let cacheKey = "playlist_\(id)" as NSString
        guard memoryObject(forKey: cacheKey) == nil else { return }
        
        if let dbPlaylist = playlistRepo.getPlaylist(id: id) {
            let playlist = dbPlaylist.toPlaylist()
            storeInMemory(playlist as AnyObject, forKey: cacheKey)
        }
    }
    
    /// 获取缓存大小
    func getCacheSize() -> String {
        let dbSize = DatabaseManager.shared.calculateDatabaseSize()
        let diskSize = diskCache.calculateCacheSize()
        return L10n.format("cache_storage_summary_format", dbSize, diskSize)
    }
    
    // MARK: - 统计
    
    func getStatistics() -> CacheStatistics {
        return CacheStatistics(
            cachedSongs: songRepo.count(),
            cachedPlaylists: playlistRepo.count(),
            databaseSize: DatabaseManager.shared.calculateDatabaseSize(),
            diskCacheSize: diskCache.calculateCacheSize()
        )
    }
}

// MARK: - 缓存统计

struct CacheStatistics {
    let cachedSongs: Int
    let cachedPlaylists: Int
    let databaseSize: String
    let diskCacheSize: String
    
    var totalSize: String {
        return L10n.format(
            "cache_storage_summary_format",
            databaseSize,
            diskCacheSize
        )
    }
}
