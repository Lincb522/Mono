// 音乐平台来源标识

import Foundation

/// 音乐平台来源
enum MusicSource: String, Codable, CaseIterable, Sendable {
    /// ncm（默认）
    case netease = "netease"
    /// qcm
    case qqmusic = "qqmusic"
    /// 汽水音乐
    case qishui = "qishui"
    /// 酷狗概念版
    case kugou = "kugou"
    /// Apple Music
    case appleMusic = "appleMusic"
    /// 本地音乐
    case local = "local"
    
    var displayName: String {
        switch self {
        case .netease: return "NCM"
        case .qqmusic: return "QCM"
        case .qishui: return "QSM"
        case .kugou: return "KCM"
        case .appleMusic: return "Apple Music"
        case .local: return "Local"
        }
    }
    
    var shortName: String {
        switch self {
        case .netease: return "NCM"
        case .qqmusic: return "QCM"
        case .qishui: return "QSM"
        case .kugou: return "KCM"
        case .appleMusic: return "AM"
        case .local: return "Local"
        }
    }

    var widgetDisplayName: String {
        switch self {
        case .netease: return "NCM"
        case .qqmusic: return "QCM"
        case .qishui: return "QSM"
        case .kugou: return "KCM"
        case .appleMusic: return "Apple Music"
        case .local: return "Local"
        }
    }
}

/// 可独立于歌曲播放平台选择的歌词来源。
enum LyricSource: String, Codable, CaseIterable, Identifiable {
    case netease = "netease"
    case qqmusic = "qqmusic"
    case qishui = "qishui"
    case kugou = "kugou"

    static let storageKey = "defaultLyricSource"
    static let appleMusicStorageKey = "appleMusicDefaultLyricSource"
    static let followSongRawValue = "followSong"

    /// `nil` 表示关闭全局覆盖，歌词跟随歌曲自身的平台。
    static var globalDefaultOverride: LyricSource? {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey) else {
            return nil
        }
        guard rawValue != followSongRawValue else { return nil }
        return LyricSource(rawValue: rawValue)
    }

    /// Apple Music 不提供可供第三方读取的歌词正文，因此单独保存其默认匹配来源。
    static var appleMusicDefaultSource: LyricSource {
        let rawValue = UserDefaults.standard.string(forKey: appleMusicStorageKey)
        return rawValue.flatMap(LyricSource.init(rawValue:)) ?? .netease
    }

    static func resolvedGlobalSource(for song: Song) -> LyricSource {
        if song.isAppleMusic {
            return appleMusicDefaultSource
        }
        return globalDefaultOverride ?? source(matching: song.musicSource)
    }

    static func source(matching musicSource: MusicSource) -> LyricSource {
        switch musicSource {
        case .netease, .appleMusic, .local: return .netease
        case .qqmusic: return .qqmusic
        case .qishui: return .qishui
        case .kugou: return .kugou
        }
    }

    var id: String { rawValue }

    var musicSource: MusicSource {
        switch self {
        case .netease: return .netease
        case .qqmusic: return .qqmusic
        case .qishui: return .qishui
        case .kugou: return .kugou
        }
    }

    var shortName: String {
        musicSource.shortName
    }
}
