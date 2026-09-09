import Foundation
import UIKit

public struct MonoGlyphIcons {}

public enum MonoGlyphIconStyle: String, CaseIterable, Identifiable, Sendable {
    case classic
    case expressiveOutline

    public var id: String { rawValue }
}

public extension UIImage {
    convenience init?(monoGlyphIconId: String, style: MonoGlyphIconStyle = .classic) {
        let currentStyle = UITraitCollection.current.userInterfaceStyle
        self.init(
            monoGlyphIconId: monoGlyphIconId,
            userInterfaceStyle: currentStyle == .dark ? .dark : .light,
            style: style
        )
    }

    convenience init?(
        monoGlyphIconId: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        style: MonoGlyphIconStyle = .classic
    ) {
        let traits = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
        let assetName = style == .classic ? monoGlyphIconId : "expressiveOutline_\(monoGlyphIconId)"
        guard let resolvedImage = UIImage(
            named: assetName,
            in: Bundle.module,
            compatibleWith: traits
        ) else {
            return nil
        }

        // Copying the selected raster detaches it from UIImageAsset without
        // synchronously running ColorSync during SwiftUI scene updates.
        guard let cgImage = resolvedImage.cgImage else {
            return nil
        }

        self.init(
            cgImage: cgImage,
            scale: resolvedImage.scale,
            orientation: resolvedImage.imageOrientation
        )
    }
}
