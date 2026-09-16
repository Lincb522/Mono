import SwiftUI

// The companions share playback and gaze, with separately persisted colors.
enum BloudCharacter: String, CaseIterable, Identifiable {
    case bloud, paw, pawCat
    var id: String { rawValue }
    var isAnimal: Bool { self != .bloud }
    var title: String {
        switch self {
        case .bloud: "BLOUD"
        case .paw: "PAW SHIBA"
        case .pawCat: "PAW CAT"
        }
    }
}

struct BloudPalette {
    let body: Color
    var eyes: Color
    var features: BloudFeatureColors
    let paper: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let onAccent: Color

    init(character: BloudCharacter, customHex: String, dark: Bool, coverAccent: Color, followsCover: Bool = false, overrides: [String: String] = [:]) {
        let automaticSeed = Self.coverSeed(coverAccent)
        let customHex = followsCover ? automaticSeed.toHex() : customHex
        features = BloudFeatureColors(character: character, seed: automaticSeed, automatic: followsCover, overrides: overrides)
        let defaultInk = Color(hex: dark ? "F2F3F4" : "111214")
        let defaultPaper = Color(hex: dark ? "151719" : "F7F8FA")
        if customHex.isEmpty, character == .bloud {
            body = defaultInk
            eyes = overrides["eyes"].map { Color(hex: $0) } ?? defaultPaper
            paper = defaultPaper
            ink = defaultInk
            secondary = Self.mix(defaultInk, defaultPaper, fraction: 0.28)
            accent = ThemeColorCustomization.contrastRatio(between: coverAccent, and: defaultPaper) >= 3 ? coverAccent : defaultInk
            onAccent = Self.foreground(on: accent)
            return
        }
        let seed = Color(hex: customHex.isEmpty ? (character == .pawCat ? PawCatArtwork.furHex : "F4AE58") : customHex)
        body = seed
        eyes = customHex.isEmpty ? (character == .pawCat ? PawCatArtwork.ink : .black) : Self.foreground(on: seed)
        if !followsCover, let hex = overrides["eyes"] { eyes = Color(hex: hex) }
        paper = Self.mix(seed, dark ? Color(hex: "101114") : .white, fraction: dark ? 0.88 : 0.92)
        ink = Self.mix(seed, dark ? .white : Color(hex: "101114"), fraction: dark ? 0.88 : 0.84)
        secondary = Self.mix(ink, paper, fraction: 0.24)
        // Extreme picker colors need a visible seek marker and selection accent.
        accent = ThemeColorCustomization.contrastRatio(between: seed, and: paper) >= 3 ? seed : ink
        onAccent = Self.foreground(on: accent)
    }

    private static func coverSeed(_ color: Color) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let seed = Color(hue: Double(hue), saturation: Double(min(0.55, saturation * 0.7)), brightness: Double(min(0.88, max(0.66, brightness))))
        return mix(seed, .white, fraction: 0.25)
    }

    fileprivate static func foreground(on fill: Color) -> Color {
        let light = Color.white
        let dark = Color(hex: "111214")
        return ThemeColorCustomization.contrastRatio(between: light, and: fill)
            > ThemeColorCustomization.contrastRatio(between: dark, and: fill) ? light : dark
    }

    fileprivate static func mix(_ a: Color, _ b: Color, fraction: CGFloat) -> Color {
        let x = ThemeColorCustomization.resolvedRGBA(of: a, interfaceStyle: nil)
        let y = ThemeColorCustomization.resolvedRGBA(of: b, interfaceStyle: nil)
        return Color(.sRGB,
                     red: Double(x.red + (y.red - x.red) * fraction),
                     green: Double(x.green + (y.green - x.green) * fraction),
                     blue: Double(x.blue + (y.blue - x.blue) * fraction))
    }
}


enum BloudColorPart: String, CaseIterable, Identifiable {
    case body, eyes, blush, ears, muzzle, tongue, outline, nose, stripes, whiskers
    var id: String { rawValue }
    var title: String { NSLocalizedString("player_color_" + rawValue, comment: "") }
    static func parts(for character: BloudCharacter) -> [Self] {
        switch character {
        case .bloud: [.body, .eyes]
        case .paw: [.body, .eyes, .blush, .ears, .muzzle, .tongue, .nose, .outline]
        case .pawCat: [.body, .eyes, .blush, .ears, .tongue, .nose, .stripes, .whiskers, .outline]
        }
    }
}

struct BloudFeatureColors {
    private var colors: [BloudColorPart: Color]
    subscript(_ part: BloudColorPart) -> Color { colors[part] ?? .black }

    init(character: BloudCharacter, seed: Color = .white, automatic: Bool = false, overrides: [String: String] = [:]) {
        let cat = character == .pawCat
        let ink = cat ? PawCatArtwork.ink : .black
        let cream = Color(hex: "FDFDFD")
        let pink = cat ? PawCatArtwork.pink : Color(hex: "FF9295")
        colors = [.blush: pink, .ears: cat ? pink : cream, .muzzle: cream,
                  .tongue: PawTongueArtwork.color, .outline: ink, .nose: ink,
                  .stripes: PawCatArtwork.stripeColor, .whiskers: PawCatArtwork.whiskerInk]
        if automatic {
            // Keep facial details readable and skin tones warm; never copy unrelated cover swatches.
            let line = BloudPalette.foreground(on: seed)
            let warmPink = BloudPalette.mix(Color(hex: "EF9BA7"), seed, fraction: 0.12)
            colors[.outline] = line
            colors[.nose] = line
            colors[.whiskers] = line
            colors[.blush] = warmPink
            colors[.tongue] = warmPink
            colors[.ears] = cat ? warmPink : BloudPalette.mix(seed, .white, fraction: 0.9)
            colors[.muzzle] = BloudPalette.mix(seed, .white, fraction: 0.9)
            colors[.stripes] = BloudPalette.mix(seed, line, fraction: 0.3)
        } else {
            for (key, hex) in overrides {
                if let part = BloudColorPart(rawValue: key) { colors[part] = Color(hex: hex) }
            }
        }
    }
}
