import SwiftUI
import WidgetKit
import AppIntents

private let lyricsAccent = Color(hex: "CA3025")
private let lyricsFontName = "YEFONTGangFengSong"

enum LyricsWidgetTextSizing {
    static func preferredSize(family: WidgetFamily, compact: Bool, scale: CGFloat) -> CGFloat {
        let base: CGFloat = family == .systemSmall ? (compact ? 16 : 20) : (family == .systemLarge ? 29 : (compact ? 20 : 25))
        return min(base * scale, family == .systemLarge ? 36 : 29)
    }

    static func fits(_ entry: NowPlayingEntry, family: WidgetFamily, compact: Bool, scale: CGFloat, in size: CGSize) -> Bool {
        guard !entry.isEmpty, !entry.lyricText.isEmpty else { return true }
        let pointSize = preferredSize(family: family, compact: compact, scale: scale) * 0.8
        return height(of: entry.lyricText, pointSize: pointSize, width: size.width, spacing: family == .systemLarge ? 4 : 2) <= size.height
    }

    static func fittedSize(_ text: String, maximum: CGFloat, in size: CGSize, spacing: CGFloat) -> CGFloat {
        if height(of: text, pointSize: maximum, width: size.width, spacing: spacing) <= size.height { return maximum }
        var lower: CGFloat = 0.5
        var upper = maximum
        for _ in 0..<12 {
            let candidate = (lower + upper) / 2
            if height(of: text, pointSize: candidate, width: size.width, spacing: spacing) <= size.height {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }

    private static func height(of text: String, pointSize: CGFloat, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.lineBreakMode = .byWordWrapping
        let font = UIFont(name: lyricsFontName, size: pointSize) ?? .systemFont(ofSize: pointSize)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(1, width - 2), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil
        )
        return ceil(bounds.height) + 9
    }
}

struct LyricsWidgetArtwork: View {
    let image: UIImage

    var body: some View {
        GeometryReader { geometry in
            artwork
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor)
        } else {
            Image(uiImage: image).resizable()
        }
    }
}

struct LyricsWidgetPassage: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    let ink: Color
    var showsContext = false
    var compact = false

    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .title2) private var lyricSize: CGFloat = 24

    private var pointSize: CGFloat {
        LyricsWidgetTextSizing.preferredSize(family: family, compact: compact, scale: lyricSize / 24)
    }

    private var hasLyrics: Bool {
        !entry.isEmpty && !entry.lyricText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if hasLyrics {
                // Show complete lines; secondary content yields space before the current lyric is resized.
                ViewThatFits(in: .vertical) {
                    if showsContext && !dynamicType.isAccessibilitySize {
                        passage(neighbors: true, translation: true)
                    }
                    if family == .systemLarge {
                        passage(neighbors: false, translation: true)
                    }
                    passage(neighbors: false, translation: false)
                    GeometryReader { geometry in
                        currentLyric(size: LyricsWidgetTextSizing.fittedSize(entry.lyricText, maximum: pointSize, in: geometry.size, spacing: family == .systemLarge ? 4 : 2))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.isEmpty ? "未在播放" : "暂无歌词")
                        .font(.custom(lyricsFontName, fixedSize: min(pointSize, 26)))
                    if entry.isEmpty {
                        Label("打开 Mono", systemImage: "arrow.up.forward")
                            .font(.system(size: 11))
                            .foregroundStyle(ink.opacity(0.65))
                    }
                }
            }
        }
        .foregroundStyle(ink)
    }

    private func passage(neighbors: Bool, translation: Bool) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 5) {
            if neighbors, !entry.prevLyricText.isEmpty {
                context(entry.prevLyricText)
            }

            currentLyric(size: pointSize)

            if translation, !entry.lyricTranslation.isEmpty {
                Text(entry.lyricTranslation)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if neighbors, !entry.nextLyricText.isEmpty {
                context(entry.nextLyricText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func currentLyric(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.lyricText)
                .font(.custom(lyricsFontName, fixedSize: size))
                .lineSpacing(family == .systemLarge ? 4 : 2)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("当前歌词：\(entry.lyricText)"))
            Rectangle()
                .fill(lyricsAccent)
                .frame(width: 32, height: 1.5)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
    }

    private func context(_ text: String) -> some View {
        Text(text)
            .font(.custom(lyricsFontName, fixedSize: 13))
            .foregroundStyle(ink.opacity(0.6))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LyricsWidgetFooter: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    let ink: Color
    var showsThumbnail = true

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 7) {
                if showsThumbnail {
                    CoverImage(data: entry.coverImageData, radius: 3)
                        .frame(width: 25, height: 25)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.isEmpty ? "MONO" : entry.songName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if !entry.isEmpty {
                        Text(entry.artistName)
                            .font(.system(size: 9))
                            .foregroundStyle(ink.opacity(0.65))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if family != .systemSmall, !entry.isEmpty {
                HStack(spacing: 0) {
                    if family == .systemLarge {
                        LyricsWidgetControl(intent: PreviousTrackIntent(), icon: "backward.end.fill", label: "上一首", ink: ink)
                    }
                    LyricsWidgetControl(intent: TogglePlaybackIntent(), icon: entry.controlSymbolName, label: entry.isLoading ? "正在加载" : (entry.isPlaying ? "暂停" : "播放"), ink: ink, prominent: true)
                    LyricsWidgetControl(intent: NextTrackIntent(), icon: "forward.end.fill", label: "下一首", ink: ink)
                }
                .fixedSize()
            }
        }
        .foregroundStyle(ink)
        .frame(height: family == .systemSmall || entry.isEmpty ? 25 : 44)
    }
}

private struct LyricsWidgetControl<I: AppIntent>: View {
    let intent: I
    let icon: String
    let label: LocalizedStringKey
    let ink: Color
    var prominent = false

    var body: some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 18 : 13, weight: .regular))
                .foregroundStyle(prominent ? lyricsAccent : ink)
                .widgetAccentable(prominent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct LyricsWidgetProgress: View {
    let entry: NowPlayingEntry
    let ink: Color

    private var validDuration: Bool {
        !entry.isEmpty && entry.playbackDuration.isFinite && entry.playbackDuration > 0 && entry.playbackCurrentTime.isFinite
    }

    private var interval: ClosedRange<Date> {
        let elapsed = min(max(entry.playbackCurrentTime, 0), entry.playbackDuration)
        let start = entry.playbackReferenceDate.addingTimeInterval(-elapsed)
        return start...start.addingTimeInterval(entry.playbackDuration)
    }

    var body: some View {
        if validDuration {
            VStack(spacing: 6) {
                Group {
                    if entry.isPlaying {
                        ProgressView(timerInterval: interval, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    } else {
                        ProgressView(value: min(max(entry.playbackCurrentTime / entry.playbackDuration, 0), 1))
                    }
                }
                .progressViewStyle(.linear)
                .tint(lyricsAccent)
                .widgetAccentable()
                .scaleEffect(x: 1, y: 0.4)
                .frame(height: 2)
                .accessibilityLabel("播放进度")

                HStack {
                    if entry.isPlaying {
                        Text(timerInterval: interval, countsDown: false, showsHours: false)
                            .frame(width: 48, alignment: .leading)
                    } else {
                        Text(Duration.seconds(min(max(entry.playbackCurrentTime, 0), entry.playbackDuration)).formatted(.time(pattern: .minuteSecond)))
                    }
                    Spacer(minLength: 8)
                    Text(Duration.seconds(entry.playbackDuration).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(0.6))
                .accessibilityHidden(true)
            }
        }
    }
}
