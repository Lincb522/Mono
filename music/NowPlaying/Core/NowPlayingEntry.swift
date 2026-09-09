import Foundation
import WidgetKit
import SwiftUI

// MARK: - 时间线条目

/// Widget 单个时间点的完整播放快照。
struct NowPlayingEntry: TimelineEntry {
    var date: Date
    let songName: String
    let artistName: String
    let albumName: String
    let playbackState: PlaybackSurfaceState
    var coverImageData: Data?
    let theme: WidgetTheme
    let dominantRGB: [CGFloat]
    let secondaryRGB: [CGFloat]
    let coverIsDark: Bool
    let sourceName: String
    let qualityText: String
    let playModeText: String
    let queueIndex: Int
    let queueCount: Int
    let tempoBPM: Int?
    let tempoIsAnalyzing: Bool
    var lyricText: String
    var lyricTranslation: String = ""
    var prevLyricText: String = ""
    var nextLyricText: String = ""
    var lyricIndex: Int = -1
    var lyricCount: Int = 0
    /// 本条 entry 预计展示时长（到下一条 entry 的间隔），用于把过渡动画铺满整个展示期
    var entryDisplayDuration: TimeInterval = 0
    var playbackCurrentTime: TimeInterval
    var playbackDuration: TimeInterval
    var playbackReferenceDate: Date

    init(
        date: Date,
        songName: String,
        artistName: String,
        albumName: String,
        playbackState: PlaybackSurfaceState,
        coverImageData: Data?,
        theme: WidgetTheme,
        dominantRGB: [CGFloat],
        secondaryRGB: [CGFloat],
        coverIsDark: Bool,
        sourceName: String,
        qualityText: String,
        playModeText: String,
        queueIndex: Int,
        queueCount: Int,
        tempoBPM: Int?,
        tempoIsAnalyzing: Bool,
        lyricText: String,
        lyricTranslation: String = "",
        prevLyricText: String = "",
        nextLyricText: String = "",
        lyricIndex: Int = -1,
        lyricCount: Int = 0,
        playbackCurrentTime: TimeInterval = 0,
        playbackDuration: TimeInterval = 0,
        playbackReferenceDate: Date = .now
    ) {
        self.date = date
        self.songName = songName
        self.artistName = artistName
        self.albumName = albumName
        self.playbackState = playbackState
        self.coverImageData = coverImageData
        self.theme = theme
        self.dominantRGB = dominantRGB
        self.secondaryRGB = secondaryRGB
        self.coverIsDark = coverIsDark
        self.sourceName = sourceName
        self.qualityText = qualityText
        self.playModeText = playModeText
        self.queueIndex = queueIndex
        self.queueCount = queueCount
        self.tempoBPM = tempoBPM
        self.tempoIsAnalyzing = tempoIsAnalyzing
        self.lyricText = lyricText
        self.lyricTranslation = lyricTranslation
        self.prevLyricText = prevLyricText
        self.nextLyricText = nextLyricText
        self.lyricIndex = lyricIndex
        self.lyricCount = lyricCount
        self.playbackCurrentTime = playbackCurrentTime
        self.playbackDuration = playbackDuration
        self.playbackReferenceDate = playbackReferenceDate
    }

    var isEmpty: Bool { songName.isEmpty }

    var isPlaying: Bool {
        playbackState.isPlaying
    }

    var isLoading: Bool {
        playbackState.isLoading
    }

    var controlSymbolName: String {
        switch playbackState {
        case .loading:
            return "hourglass"
        case .playing:
            return "pause.fill"
        case .paused, .idle:
            return "play.fill"
        }
    }

    var statusSymbolName: String {
        switch playbackState {
        case .loading:
            return "hourglass"
        case .playing:
            return "waveform"
        case .paused, .idle:
            return "music.note"
        }
    }

    var dominantColor: Color {
        guard dominantRGB.count >= 3 else { return Color(hex: "1E1B4B") }
        return Color(.sRGB, red: dominantRGB[0], green: dominantRGB[1], blue: dominantRGB[2])
    }

    var secondaryColor: Color {
        guard secondaryRGB.count >= 3 else { return Color(hex: "0F0F23") }
        return Color(.sRGB, red: secondaryRGB[0], green: secondaryRGB[1], blue: secondaryRGB[2])
    }

    static func preview(theme: WidgetTheme) -> NowPlayingEntry {
        switch theme {
        case .polaroid:
            return NowPlayingEntry(
                date: .now,
                songName: "纸飞机",
                artistName: "Mono",
                albumName: "Polaroid Preview",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: [0.93, 0.74, 0.33],
                secondaryRGB: [0.95, 0.94, 0.90],
                coverIsDark: false,
                sourceName: "ncm",
                qualityText: "HQ",
                playModeText: "顺序",
                queueIndex: 3,
                queueCount: 12,
                tempoBPM: 112,
                tempoIsAnalyzing: false,
                lyricText: ""
            )
        case .vinyl, .vinylDark:
            return NowPlayingEntry(
                date: .now,
                songName: "Midnight Drive",
                artistName: "Mono",
                albumName: "Vinyl Preview",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: [0.78, 0.52, 0.28],
                secondaryRGB: [0.20, 0.13, 0.09],
                coverIsDark: true,
                sourceName: "qcm",
                qualityText: "320K",
                playModeText: "顺序",
                queueIndex: 2,
                queueCount: 9,
                tempoBPM: 126,
                tempoIsAnalyzing: false,
                lyricText: ""
            )
        case .pager:
            return NowPlayingEntry(
                date: .now,
                songName: "READY...",
                artistName: "M O T O P A G E R",
                albumName: "Preview",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: [0.99, 0.64, 0.07],
                secondaryRGB: [0.12, 0.10, 0.08],
                coverIsDark: true,
                sourceName: "ncm",
                qualityText: "HQ",
                playModeText: "顺序",
                queueIndex: 1,
                queueCount: 8,
                tempoBPM: 96,
                tempoIsAnalyzing: false,
                lyricText: "PRINTING..."
            )
        case .lyrics, .lyricsDark, .lyricsCover:
            return NowPlayingEntry(
                date: .now,
                songName: "海阔天空",
                artistName: "Beyond",
                albumName: "乐与怒",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: [0.36, 0.54, 0.86],
                secondaryRGB: [0.10, 0.14, 0.26],
                coverIsDark: true,
                sourceName: "ncm",
                qualityText: "HQ",
                playModeText: "顺序",
                queueIndex: 5,
                queueCount: 18,
                tempoBPM: 82,
                tempoIsAnalyzing: false,
                lyricText: "原谅我这一生不羁放纵爱自由",
                lyricTranslation: "",
                prevLyricText: "背弃了理想 谁人都可以",
                nextLyricText: "也会怕有一天会跌倒",
                lyricIndex: 12,
                lyricCount: 36,
                playbackCurrentTime: 118,
                playbackDuration: 323,
                playbackReferenceDate: .now
            )
        case .aperture:
            return NowPlayingEntry(
                date: .now,
                songName: "Wonderwall",
                artistName: "Oasis",
                albumName: "Aperture Preview",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: [0.62, 0.58, 0.52],
                secondaryRGB: [0.90, 0.88, 0.84],
                coverIsDark: false,
                sourceName: "ncm",
                qualityText: "HQ",
                playModeText: "顺序",
                queueIndex: 3,
                queueCount: 12,
                tempoBPM: 96,
                tempoIsAnalyzing: false,
                lyricText: "",
                playbackCurrentTime: 82,
                playbackDuration: 238,
                playbackReferenceDate: .now
            )
        default:
            let isDark = [.vinyl, .poster].contains(theme)
            return NowPlayingEntry(
                date: .now,
                songName: "Midnight Drive",
                artistName: "Mono",
                albumName: "Preview",
                playbackState: .playing,
                coverImageData: nil,
                theme: theme,
                dominantRGB: isDark ? [0.65, 0.42, 0.22] : [0.93, 0.74, 0.33],
                secondaryRGB: isDark ? [0.15, 0.10, 0.06] : [0.95, 0.94, 0.90],
                coverIsDark: isDark,
                sourceName: "ncm",
                qualityText: "HQ",
                playModeText: "顺序",
                queueIndex: 3,
                queueCount: 12,
                tempoBPM: 120,
                tempoIsAnalyzing: false,
                lyricText: "在这寂静的夜里"
            )
        }
    }

    static let placeholder = preview(theme: .polaroid)

}
