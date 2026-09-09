import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget 视图

/// 根据组件尺寸与主题渲染当前播放快照。
struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:    circularWidget
            case .accessoryRectangular: rectangularWidget
            default:                    themedBody
            }
        }
        .containerBackground(for: .widget) {
            themeBackground
        }
    }

    @ViewBuilder
    private var themedBody: some View {
        switch entry.theme {
        case .polaroid:
            PolaroidTheme(entry: entry, family: family)
        case .vinyl:
            VinylTheme(entry: entry, family: family)
        case .vinylDark:
            VinylTheme(entry: entry, family: family, isDark: true)
        case .poster:
            PosterWidgetTheme(entry: entry, family: family)
        case .magazine:
            MagazineTheme(entry: entry, family: family)
        case .aperture:
            ApertureWidgetTheme(entry: entry, family: family)
        case .pager:
            PagerWidgetTheme(entry: entry, family: family, isLight: false)
        case .pagerLight:
            PagerWidgetTheme(entry: entry, family: family, isLight: true)
        case .radio:
            RadioTheme(entry: entry, family: family)
        case .dashboard:
            DashboardTheme(entry: entry, family: family)
        case .soundwave:
            SoundwaveTheme(entry: entry, family: family)
        case .typewriter:
            TypewriterWidgetTheme(entry: entry, family: family)
        case .lyrics:
            LyricsWidgetTheme(entry: entry, family: family)
        case .lyricsDark:
            LyricsWidgetTheme(entry: entry, family: family, isDark: true)
        case .lyricsCover:
            LyricsCoverWidgetTheme(entry: entry, family: family)
        }
    }

    @ViewBuilder
    private var themeBackground: some View {
        switch entry.theme {
        case .polaroid:
            Color(hex: "F7F6F3")
                .ignoresSafeArea()
        case .vinyl:
            Color(hex: "F7F7F5")
                .ignoresSafeArea()
        case .vinylDark:
            Color(hex: "0C0D0C")
                .ignoresSafeArea()
        case .poster:
            Color(hex: "0A0A0C").ignoresSafeArea()
        case .magazine:
            Color(hex: "F4F1EA").ignoresSafeArea()
        case .aperture:
            Color(hex: "F2F2F2").ignoresSafeArea()
        case .pager, .pagerLight:
            Color.clear.ignoresSafeArea()
        case .radio:
            Color(hex: "1E1E1E").ignoresSafeArea()
        case .dashboard:
            Color(hex: "1A1A1E").ignoresSafeArea()
        case .soundwave:
            Color(hex: "151515").ignoresSafeArea()
        case .typewriter:
            Color(hex: "DED0B6").ignoresSafeArea()
        case .lyrics:
            Color.white.ignoresSafeArea()
        case .lyricsDark:
            Color(hex: "181818").ignoresSafeArea()
        case .lyricsCover:
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Lock Screen
    private var circularWidget: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.controlSymbolName)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
        }
        .widgetURL(URL(string: "mono://player"))
    }

    private var rectangularWidget: some View {
        HStack(spacing: 8) {
            if entry.isPlaying {
                PlaybackWave(isActive: true, barCount: 3, color: .primary, height: 14)
                    .frame(width: 14)
            } else {
                Image(systemName: entry.statusSymbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isEmpty ? "未在播放" : entry.songName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(entry.isEmpty ? "暂无歌曲信息" : entry.artistName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "mono://player"))
    }
}
