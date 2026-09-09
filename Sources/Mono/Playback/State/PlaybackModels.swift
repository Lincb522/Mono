// Mono播放引擎的纯值类型与播放策略读取：
// 播放模式、播放来源、播放上下文、队列事务快照、持久化状态模型。
// 全部以 PlayerManager 嵌套类型的形式保留，外部调用点无需任何改动。

import Foundation

// MARK: - 播放模式与队列行为

extension PlayerManager {

    enum PlayMode: String, Codable, Sendable {
        case sequence
        case loopSingle
        case shuffle

        var displayName: String {
            switch self {
            case .sequence:
                return NSLocalizedString("mode_sequence", comment: "")
            case .loopSingle:
                return NSLocalizedString("mode_loop_one", comment: "")
            case .shuffle:
                return NSLocalizedString("mode_shuffle", comment: "")
            }
        }

        var icon: String {
            switch self {
            case .sequence: return "repeat"
            case .loopSingle: return "repeat.1"
            case .shuffle: return "shuffle"
            }
        }

        var next: PlayMode {
            switch self {
            case .sequence: return .loopSingle
            case .loopSingle: return .shuffle
            case .shuffle: return .sequence
            }
        }
    }

    enum QueueExhaustionBehavior: String, Codable, Sendable {
        case loop
        case stopAtEnd
    }

    enum PlaybackHistoryMutation: Equatable {
        /// 普通点歌或向前播放，由加载链路记录当前歌曲。
        case automatic
        /// 上一曲已经提前整理好回退栈与前进栈，加载链路不再重复改写。
        case prearranged
    }

    // MARK: - 播放源类型

    enum PlaySource: Codable, Equatable, Sendable {
        case normal
        case fm
        case podcast(radioId: Int)

        var isPodcast: Bool {
            if case .podcast = self { return true }
            return false
        }
    }

    // MARK: - 播放来源上下文

    struct PlayContext: Codable, Equatable {
        enum ContextType: String, Codable {
            case playlist, album, artist, dailyRecommend, rank
            case search, recentPlay, newSong, cloud, download, unknown
        }
        let type: ContextType
        let id: Int?
        let name: String
    }

    // MARK: - 预装管线解析出的真实音质

    enum ResolvedPlaybackQuality {
        case netease(songId: Int, quality: SoundQuality)
        case kugou(hash: String, quality: SoundQuality)
        case qq(mid: String, quality: QQMusicQuality)
        case qishui(trackId: Int, quality: String)
    }

    struct RecentPlaybackInput {
        let input: String
        let decryptionKey: String?
        let resolvedQuality: ResolvedPlaybackQuality?
        let resolvedAt: Date
    }

    // MARK: - 队列事务快照
    //
    // 点歌过程中对队列和播放来源的临时修改。只有目标管线真正出声才提交；
    // 取址/下载/会话激活失败则恢复旧歌对应的完整队列状态。

    struct PlaybackQueueTransactionSnapshot {
        let context: [Song]
        let contextIndex: Int
        let shuffledContext: [Song]
        let playSource: PlaySource
        let queueExhaustionBehavior: QueueExhaustionBehavior
        let mode: PlayMode
        let playContext: PlayContext?
        let playbackBackStack: [Song]
        let playbackForwardStack: [Song]
        let savedMusicContext: [Song]
        let savedMusicContextIndex: Int
        let savedMusicShuffledContext: [Song]
        let savedMusicMode: PlayMode
        let savedMusicSong: Song?
        let savedPodcastContext: [Song]
        let savedPodcastContextIndex: Int
        let savedPodcastRadioId: Int?
        let savedPodcastSong: Song?
    }

    // MARK: - 持久化状态模型

    struct PlayerState: Codable, Sendable {
        let currentSong: Song?
        let mode: PlayMode
        let history: [Song]
        let podcastHistory: [Song]?
        let playSource: PlaySource?
        let queueExhaustionBehavior: QueueExhaustionBehavior?
        let context: [Song]?
        let contextIndex: Int?
        let shuffledContext: [Song]?
        let playbackBackStack: [Song]?
        let playbackForwardStack: [Song]?
        let currentTime: Double?
        let duration: Double?
        let wasPlaying: Bool?
        // 播客/音乐上下文隔离
        let savedMusicContext: [Song]?
        let savedMusicContextIndex: Int?
        let savedMusicShuffledContext: [Song]?
        let savedMusicMode: PlayMode?
        let savedMusicSong: Song?
        let savedPodcastContext: [Song]?
        let savedPodcastContextIndex: Int?
        let savedPodcastRadioId: Int?
        let savedPodcastSong: Song?
        // 快速续播：上次会话已解析的播放输入（http 地址或本地路径）
        let lastPlaybackInput: String?
        let lastPlaybackInputResolvedAt: Date?
        let lastPlaybackDecryptionKey: String?
    }
}

// MARK: - 播放策略（UserDefaults 读取）

extension PlayerManager {

    static func defaultNeteasePlaybackQuality() -> SoundQuality {
        let defaultRaw = UserDefaults.standard.string(forKey: AppConfig.StorageKeys.defaultPlaybackQuality)
            ?? SoundQuality.standard.rawValue
        return SoundQuality(rawValue: defaultRaw) ?? .standard
    }

    static func defaultKugouPlaybackQuality() -> SoundQuality {
        let defaultRaw = UserDefaults.standard.string(forKey: AppConfig.StorageKeys.defaultKugouPlaybackQuality)
            ?? SoundQuality.standard.rawValue
        return SoundQuality(rawValue: defaultRaw) ?? .standard
    }

    static func defaultQQPlaybackQuality() -> QQMusicQuality {
        let defaultRaw = UserDefaults.standard.string(forKey: AppConfig.StorageKeys.qqMusicQuality)
            ?? QQMusicQuality.mp3_320.rawValue
        return QQMusicQuality(rawValue: defaultRaw) ?? .mp3_320
    }

    static func prefersHighestPlaybackQuality() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppConfig.StorageKeys.preferHighestPlaybackQuality) != nil else {
            return true
        }
        return defaults.bool(forKey: AppConfig.StorageKeys.preferHighestPlaybackQuality)
    }

    static func gaplessPlaybackEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: AppConfig.StorageKeys.gaplessPlaybackEnabledMigrationV2) {
            defaults.set(true, forKey: AppConfig.StorageKeys.gaplessPlaybackEnabled)
            defaults.set(true, forKey: AppConfig.StorageKeys.gaplessPlaybackEnabledMigrationV2)
            return true
        }
        guard defaults.object(forKey: AppConfig.StorageKeys.gaplessPlaybackEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: AppConfig.StorageKeys.gaplessPlaybackEnabled)
    }

    static let crossfadePlaybackDuration: Float = 2.5

    static func crossfadePlaybackEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: AppConfig.StorageKeys.crossfadePlaybackEnabled)
    }

    static func initialNeteasePlaybackQuality() -> SoundQuality {
        prefersHighestPlaybackQuality() ? .jymaster : defaultNeteasePlaybackQuality()
    }

    static func initialKugouPlaybackQuality() -> SoundQuality {
        prefersHighestPlaybackQuality() ? .jymaster : defaultKugouPlaybackQuality()
    }

    static func initialQQPlaybackQuality() -> QQMusicQuality {
        prefersHighestPlaybackQuality() ? .master : defaultQQPlaybackQuality()
    }

    // MARK: - 播放身份（跨来源歌曲判等）

    nonisolated static func playbackIdentityKey(for song: Song) -> String {
        if song.isQQMusic {
            return "qq:\(song.qqMid ?? String(song.id))"
        }
        if song.isQishui {
            return "qishui:\(song.qishuiTrackId.map { String($0) } ?? String(song.id))"
        }
        if song.isAppleMusic {
            return "apple:\(song.appleMusicCatalogID ?? String(song.id))"
        }
        return "\(song.musicSource.rawValue):\(song.id)"
    }

    nonisolated static func matchesPlaybackTarget(_ candidate: Song?, expected: Song) -> Bool {
        guard let candidate,
              candidate.id == expected.id,
              candidate.musicSource == expected.musicSource else { return false }

        if expected.isQQMusic {
            return candidate.qqMid == expected.qqMid
        }
        if expected.isQishui {
            return candidate.qishuiTrackId == expected.qishuiTrackId
        }
        if expected.isAppleMusic {
            return candidate.appleMusicCatalogID == expected.appleMusicCatalogID
        }
        return true
    }
}
