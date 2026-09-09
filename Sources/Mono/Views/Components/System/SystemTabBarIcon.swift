import SwiftUI
import UIKit

/// Native tab items extract UIImage rather than respecting the SwiftUI image frame.
struct SystemTabBarIcon: View {
    let tab: Tab
    let isLocalMode: Bool
    let colorScheme: ColorScheme

    @AppStorage(AppConfig.StorageKeys.interfaceIconSet) private var iconSetRaw = AppInterfaceIconSet.hicon.rawValue
    @AppStorage(AppInterfaceIconSet.zappiconStyleKey) private var zappiconStyleRaw = ZappiconIconStyle.light.rawValue
    @AppStorage(AppInterfaceIconSet.solarStyleKey) private var solarStyleRaw = SolarIconStyle.line.rawValue
    @AppStorage(AppInterfaceIconSet.monoGlyphStyleKey) private var monoGlyphStyleRaw = AppInterfaceIconSet.selectedMonoGlyphStyle.rawValue

    var body: some View {
        let _ = iconSetRaw
        let _ = zappiconStyleRaw
        let _ = solarStyleRaw
        let _ = monoGlyphStyleRaw
        let iconSet = AppInterfaceIconSet.selectedFromDefaults

        // Selection belongs to UIKit; changing tabs must not rebuild item identity.
        if iconSet == .sfSymbols {
            Image(systemName: tab.navigationSymbol(isLocalMode: isLocalMode))
                .symbolVariant(.none)
        } else {
            Image(uiImage: artwork(for: iconSet))
        }
    }

    private func artwork(for iconSet: AppInterfaceIconSet) -> UIImage {
        let image = iconSet.image(
            for: tab.navigationIcon(isLocalMode: isLocalMode),
            prefersLightOutline: colorScheme == .dark
        )
        let renderingMode: UIImage.RenderingMode = iconSet.usesOriginalArtwork ? .alwaysOriginal : .alwaysTemplate
        guard let cgImage = image.cgImage else {
            return image.withRenderingMode(renderingMode)
        }

        // Reuse source pixels while giving UIKit the intended point size.
        let pixelExtent = CGFloat(max(cgImage.width, cgImage.height))
        return UIImage(
            cgImage: cgImage,
            scale: pixelExtent / visualSize(for: iconSet),
            orientation: image.imageOrientation
        )
        .withRenderingMode(renderingMode)
    }

    private func visualSize(for iconSet: AppInterfaceIconSet) -> CGFloat {
        switch iconSet {
        case .doodlePop:
            return 16.5
        case .blobIcons, .dotDogSnake, .minimalWhiteIcons, .pulseBloom, .monoGlyph:
            return 17
        case .pawPrint:
            return tab == .library ? 23 : 18.5
        case .hicon, .sfSymbols, .zappicon, .lucide, .solar:
            return 23
        }
    }
}
