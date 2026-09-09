import SwiftUI
import WidgetKit

struct LyricsCoverWidgetTheme: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .title2) private var lyricScale: CGFloat = 24

    private var ink: Color { renderingMode == .fullColor ? .white : .primary }

    var body: some View {
        GeometryReader { geometry in
            let artwork = entry.coverImageData.flatMap(UIImage.init(data:))
            let showsArtwork = artwork != nil && hasRoom(in: geometry.size, withArtwork: true)
            let retainsFooter = hasRoom(in: geometry.size, withArtwork: showsArtwork)

            if family == .systemMedium {
                HStack(spacing: 0) {
                    content(compact: showsArtwork, retainsFooter: retainsFooter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsArtwork, let artwork {
                        LyricsWidgetArtwork(image: artwork)
                            .frame(width: geometry.size.width * 0.30, height: geometry.size.height)
                            .clipped()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if showsArtwork, let artwork {
                        LyricsWidgetArtwork(image: artwork)
                            .frame(height: geometry.size.height * artworkFraction)
                            .clipped()
                    }
                    content(compact: family == .systemSmall, retainsFooter: retainsFooter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .widgetURL(URL(string: "mono://player"))
    }

    private func hasRoom(in size: CGSize, withArtwork: Bool) -> Bool {
        let inset: CGFloat = family == .systemLarge ? 18 : (family == .systemSmall ? 10 : 14)
        let width = withArtwork && family == .systemMedium ? size.width * 0.70 : size.width
        let height = withArtwork && family != .systemMedium ? size.height * (1 - artworkFraction) : size.height
        let footerSpace: CGFloat = family == .systemLarge ? 82 : (family == .systemSmall ? 31 : 50)
        return LyricsWidgetTextSizing.fits(entry, family: family, compact: family == .systemSmall || (family == .systemMedium && withArtwork), scale: lyricScale / 24, in: CGSize(width: width - inset * 2, height: height - inset * 2 - footerSpace))
    }

    private var artworkFraction: CGFloat {
        if dynamicType.isAccessibilitySize { return family == .systemSmall ? 0.20 : 0.25 }
        return family == .systemSmall ? 0.32 : 0.38
    }

    private func content(compact: Bool, retainsFooter: Bool) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            LyricsWidgetPassage(entry: entry, family: family, ink: ink, compact: compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if retainsFooter && family == .systemLarge {
                LyricsWidgetProgress(entry: entry, ink: ink)
            }
            if retainsFooter || family != .systemSmall {
                LyricsWidgetFooter(entry: entry, family: family, ink: ink, showsThumbnail: family == .systemLarge)
            }
        }
        .padding(family == .systemLarge ? 18 : (family == .systemSmall ? 10 : 14))
    }
}
