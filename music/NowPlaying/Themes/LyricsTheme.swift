import SwiftUI
import WidgetKit

struct LyricsWidgetTheme: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    var isDark = false

    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .title2) private var lyricScale: CGFloat = 24

    private var ink: Color {
        renderingMode == .fullColor ? Color(hex: isDark ? "F2F0EB" : "181818") : .primary
    }

    var body: some View {
        GeometryReader { geometry in
            let large = family == .systemLarge
            let inset: CGFloat = large ? 20 : 14
            let footerSpace: CGFloat = large ? 94 : (family == .systemSmall ? 33 : 52)
            let retainsFooter = LyricsWidgetTextSizing.fits(entry, family: family, compact: false, scale: lyricScale / 24, in: CGSize(width: geometry.size.width - inset * 2, height: geometry.size.height - inset * 2 - footerSpace))

            VStack(alignment: .leading, spacing: large ? 16 : 8) {
                LyricsWidgetPassage(entry: entry, family: family, ink: ink, showsContext: large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if retainsFooter && large {
                    LyricsWidgetProgress(entry: entry, ink: ink)
                }
                if retainsFooter || family != .systemSmall {
                    LyricsWidgetFooter(entry: entry, family: family, ink: ink)
                }
            }
            .padding(inset)
        }
        .widgetURL(URL(string: "mono://player"))
    }
}
