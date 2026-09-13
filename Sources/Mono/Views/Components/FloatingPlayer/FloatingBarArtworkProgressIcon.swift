import SwiftUI

struct FloatingBarArtworkProgressIcon: View {
    let icon: MonoIcon.IconType
    let size: CGFloat
    let frameSize: CGFloat
    let lineWidth: CGFloat
    let panelColor: Color
    let coveredColor: Color
    let panelBackgroundColor: Color
    let coveredBackgroundColor: Color
    let coverage: Double

    var body: some View {
        let fraction = CGFloat(min(max(coverage, 0), 1))

        // Original artwork must switch assets, not tint. Complementary masks
        // prevent the uncovered rendition from showing through the covered one.
        ZStack {
            MonoIcon(
                icon: icon,
                size: size,
                color: panelColor,
                lineWidth: lineWidth,
                normalizesBitmapScale: true,
                artworkContrastBackground: panelBackgroundColor
            )
            .frame(width: frameSize, height: frameSize)
            .mask {
                Rectangle().scaleEffect(x: 1 - fraction, y: 1, anchor: .trailing)
            }

            MonoIcon(
                icon: icon,
                size: size,
                color: coveredColor,
                lineWidth: lineWidth,
                normalizesBitmapScale: true,
                artworkContrastBackground: coveredBackgroundColor
            )
            .frame(width: frameSize, height: frameSize)
            .mask {
                Rectangle().scaleEffect(x: fraction, y: 1, anchor: .leading)
            }
        }
        .frame(width: frameSize, height: frameSize)
    }
}
