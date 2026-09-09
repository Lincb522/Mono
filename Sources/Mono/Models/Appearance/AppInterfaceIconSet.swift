import Foundation
import MonoGlyphIcons

enum AppInterfaceIconSet: String, CaseIterable, Identifiable {
    case hicon
    case sfSymbols
    case zappicon
    case lucide
    case solar
    case blobIcons
    case doodlePop
    case pawPrint
    case dotDogSnake
    case minimalWhiteIcons
    case pulseBloom
    case monoGlyph

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hicon:
            return "Hicon"
        case .sfSymbols:
            return "SF Symbols"
        case .zappicon:
            return "Zappicon"
        case .lucide:
            return "Lucide"
        case .solar:
            return "Solar"
        case .blobIcons:
            return "Blob Icons"
        case .doodlePop:
            return "doodlePop"
        case .pawPrint:
            return "Paw Print"
        case .dotDogSnake:
            return "Dot Dog-Snake"
        case .minimalWhiteIcons:
            return "Minimal White"
        case .pulseBloom:
            return "Pulse Bloom"
        case .monoGlyph:
            return "MONO Glyph"
        }
    }

    var usesOriginalArtwork: Bool {
        switch self {
        case .doodlePop, .pawPrint, .dotDogSnake, .minimalWhiteIcons, .pulseBloom, .monoGlyph:
            return true
        case .hicon, .sfSymbols, .zappicon, .lucide, .solar, .blobIcons:
            return false
        }
    }

    /// Zappicon 子风格（仅 .zappicon 时有效）
    static var zappiconStyleKey: String { "mono_zappicon_style" }

    static var selectedZappiconStyle: ZappiconIconStyle {
        let raw = UserDefaults.standard.string(forKey: zappiconStyleKey) ?? ZappiconIconStyle.light.rawValue
        return ZappiconIconStyle(rawValue: raw) ?? .light
    }

    static func setZappiconStyle(_ style: ZappiconIconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: zappiconStyleKey)
    }

    /// Solar 子风格（仅 .solar 时有效）
    static var solarStyleKey: String { "mono_solar_style" }

    static var selectedSolarStyle: SolarIconStyle {
        let raw = UserDefaults.standard.string(forKey: solarStyleKey) ?? SolarIconStyle.line.rawValue
        return SolarIconStyle(rawValue: raw) ?? .line
    }

    static func setSolarStyle(_ style: SolarIconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: solarStyleKey)
    }

    static var monoGlyphStyleKey: String { "mono_glyph_style" }

    static var selectedMonoGlyphStyle: MonoGlyphIconStyle {
        let raw = UserDefaults.standard.string(forKey: monoGlyphStyleKey) ?? MonoGlyphIconStyle.classic.rawValue
        return MonoGlyphIconStyle(rawValue: raw) ?? .classic
    }

    static func setMonoGlyphStyle(_ style: MonoGlyphIconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: monoGlyphStyleKey)
    }

    static var selectedFromDefaults: AppInterfaceIconSet {
        resolved(rawValue: UserDefaults.standard.string(forKey: AppConfig.StorageKeys.interfaceIconSet))
    }

    static func resolved(rawValue: String?) -> AppInterfaceIconSet {
        if let rawValue, let iconSet = AppInterfaceIconSet(rawValue: rawValue) {
            return iconSet
        }

        return GlobalThemeId.persistedOrDefault.preferredInterfaceIconSet
    }
}

extension MonoGlyphIconStyle {
    var displayName: String {
        switch self {
        case .classic:
            return String(localized: "settings_mono_glyph_style_classic")
        case .expressiveOutline:
            return String(localized: "settings_mono_glyph_style_expressive")
        }
    }
}

extension GlobalThemeId {
    var preferredInterfaceIconSet: AppInterfaceIconSet {
        switch self {
        case .petWhite:
            return .pawPrint
        case .default:
            return .hicon
        case .muji, .manga:
            return .doodlePop
        case .neumorphic, .capsule:
            return .blobIcons
        case .signal:
            return .lucide
        case .minimalWhite:
            return .minimalWhiteIcons
        case .clarity:
            return .pulseBloom
        }
    }
}

/// Zappicon 图标风格（Light / Regular / Filled / Duotone / Duotone Line）
enum ZappiconIconStyle: String, CaseIterable, Identifiable {
    case light
    case regular
    case filled
    case duotone
    case duotoneline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:        return "Light"
        case .regular:      return "Regular"
        case .filled:       return "Filled"
        case .duotone:      return "Duotone"
        case .duotoneline:  return "Duotone Line"
        }
    }
}

/// Solar 图标风格（Line / Filled / Broken / Duoline / Duotone / Mono）
enum SolarIconStyle: String, CaseIterable, Identifiable {
    case line
    case filled
    case broken
    case duoline
    case duotone
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .line:     return "Line"
        case .filled:   return "Filled"
        case .broken:   return "Broken"
        case .duoline:  return "Duoline"
        case .duotone:  return "Duotone"
        case .mono:     return "Mono"
        }
    }
}
