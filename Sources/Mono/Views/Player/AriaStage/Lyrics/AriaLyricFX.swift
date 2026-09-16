//  Folia visualizer registry and shared lyric runtime.
//  Mode-specific renderers live in the neighboring AriaFolia*.swift files.

import SwiftUI
import UIKit

// MARK: - Folia visualizer registry

enum AriaLyricEffect: String, CaseIterable {
    // Keep this order aligned with folia-major's visualizer registry.
    case classic
    case cadenza
    case partita
    case fume
    case tilt
    case cappella
    case canopy
    case tide
    case echo
    case refraction
    case poster

    var label: String {
        switch self {
        case .classic: return String(localized: "追光")
        case .cadenza: return String(localized: "聚光")
        case .partita: return String(localized: "轮唱")
        case .fume: return String(localized: "全景")
        case .tilt: return String(localized: "独白")
        case .cappella: return String(localized: "对白")
        case .canopy: return String(localized: "巨幕")
        case .tide: return String(localized: "潮汐")
        case .echo: return String(localized: "回响")
        case .poster: return String(localized: "跃字")
        case .refraction: return String(localized: "折光")
        }
    }

    var caption: String {
        switch self {
        case .classic: return String(localized: "逐词高亮与柔和余晖")
        case .cadenza: return String(localized: "中心词块与空间聚焦")
        case .partita: return String(localized: "错落分行与顺序点亮")
        case .fume: return String(localized: "整篇歌词与镜头追焦")
        case .tilt: return String(localized: "分句大字与斜体强调")
        case .cappella: return String(localized: "双人头像与对话气泡")
        case .canopy: return String(localized: "巨幅淡字与注音细线")
        case .tide: return String(localized: "随演唱起伏的流动字浪")
        case .echo: return String(localized: "清晰主句与层叠余韵")
        case .poster: return String(localized: "粗字海报与错位字墙")
        case .refraction: return String(localized: "横向切片与折射聚合")
        }
    }

    /// Fume and Cappella own the full stage instead of a single 70%-height lyric viewport.
    var usesFullStage: Bool {
        self == .fume || self == .cappella || self == .poster
    }

    /// Removed legacy effects migrate to Folia's default visualizer.
    static func resolveStored(_ rawValue: String) -> AriaLyricEffect {
        AriaLyricEffect(rawValue: rawValue) ?? .classic
    }
}

// MARK: - Lyric font

enum AriaLyricFontChoice: String, CaseIterable {
    case system
    case serif
    case pomo
    case bantianyun
    case gangfengsong
    case paopao
    case pixel
    case custom

    /// 外语歌可选独立的自定义字体：舞台按当前歌词语言在渲染前设置，
    /// `.custom` 分支优先读取；nil 时回落到主歌词字体的自定义 ID。
    nonisolated(unsafe) static var customFontIDOverride: String?

    private static var effectiveCustomFontID: String? {
        customFontIDOverride
            ?? UserDefaults.standard.string(forKey: "ariaCustomLyricFontID")
    }

    var label: String {
        switch self {
        case .system: return String(localized: "系统圆体")
        case .serif: return String(localized: "系统衬线")
        case .pomo: return "三极泼墨体"
        case .bantianyun: return "半天云手书"
        case .gangfengsong: return "港风宋"
        case .paopao: return "文道泡泡体"
        case .pixel: return "汉仪像素"
        case .custom:
            return CustomFontStorage.record(withID: Self.effectiveCustomFontID)?.displayName
                ?? String(localized: "自定义字体")
        }
    }

    var cacheIdentity: String {
        guard self == .custom else { return rawValue }
        return "\(rawValue):\(Self.effectiveCustomFontID ?? "missing")"
    }

    /// Match the names already used by the player themes. `Font.custom`
    /// resolves these registered family names more consistently than the
    /// malformed PostScript names carried by some of the bundled font files.
    private var swiftUIFontName: String? {
        switch self {
        case .system, .serif:
            return nil
        case .pomo:
            return "三极泼墨体"
        case .bantianyun:
            return "zihunbantianyunmeiheishoushu"
        case .gangfengsong:
            return "YEFONTGangFengSong"
        case .paopao:
            return "WDPPT"
        case .pixel:
            return "HYPixel-11px-U"
        case .custom:
            return CustomFontStorage.postScriptName(for: Self.effectiveCustomFontID)
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight, design: .rounded)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        default:
            if let swiftUIFontName {
                return .custom(swiftUIFontName, size: size)
            }
            return .system(size: size, weight: weight, design: .rounded)
        }
    }

    /// 人声呼吸字重：按人声包络在基准字重附近连续插值
    /// （唱得越用力字越"绷"）。系统字体族在这里使用连续字重；
    /// 自定义/内置美术字体由下方字形完成层补齐增厚效果。
    func breathingFont(
        size: CGFloat,
        amount: Double,
        baseWeight: UIFont.Weight = .heavy
    ) -> Font {
        switch self {
        case .system, .serif:
            let clamped = min(1, max(0, amount))
            let raw = min(0.62, baseWeight.rawValue - 0.12 + clamped * 0.26)
            let base = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(rawValue: raw))
            let design: UIFontDescriptor.SystemDesign = self == .serif ? .serif : .rounded
            guard let descriptor = base.fontDescriptor.withDesign(design) else {
                return Font(base)
            }
            return Font(UIFont(descriptor: descriptor, size: size))
        default:
            return font(size: size, weight: baseWeight == .bold ? .bold : .heavy)
        }
    }

    /// 系统字体可以通过 UIFont 的连续字重直接呼吸；内置美术字体与
    /// 用户导入字体通常只有单一字重，需要在字形完成层做轻量增厚。
    var supportsNativeBreathingWeight: Bool {
        self == .system || self == .serif
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        for name in uiFontNames {
            if let custom = UIFont(name: name, size: size) {
                return custom
            }
        }

        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign = self == .serif ? .serif : .rounded
        guard let descriptor = base.fontDescriptor.withDesign(design) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private var uiFontNames: [String] {
        switch self {
        case .system, .serif:
            return []
        case .pomo:
            return ["Undefined", "三极泼墨体"]
        case .bantianyun:
            return [
                "zihun48hao-bantianyunmeiheishoushu-Regular",
                "zihunbantianyunmeiheishoushu"
            ]
        case .gangfengsong:
            return ["YEFONTGangFengSong"]
        case .paopao:
            return ["WDPPT"]
        case .pixel:
            return ["HYPixel-11px-U"]
        case .custom:
            return CustomFontStorage.postScriptName(for: Self.effectiveCustomFontID)
                .map { [$0] } ?? []
        }
    }
}

// MARK: - Synthetic breathing weight

extension View {
    /// 为没有可变字重轴的美术字体与导入字体补齐人声呼吸。
    /// 保留中心原字形，只用亚像素级的左右字形叠印增加墨量，避免模糊。
    func ariaSyntheticBreathingWeight(
        fontChoice: AriaLyricFontChoice,
        amount: Double,
        active: Bool
    ) -> some View {
        modifier(
            AriaSyntheticBreathingWeightModifier(
                fontChoice: fontChoice,
                amount: amount,
                active: active
            )
        )
    }
}

private struct AriaSyntheticBreathingWeightModifier: ViewModifier {
    let fontChoice: AriaLyricFontChoice
    let amount: Double
    let active: Bool

    func body(content: Content) -> some View {
        let envelope = pow(min(1, max(0, amount)), 0.72)
        let edgeOffset = 0.18 + envelope * 0.54
        let inkOpacity = 0.10 + envelope * 0.24

        Group {
            if active, envelope > 0.001, !fontChoice.supportsNativeBreathingWeight {
                content
                    .scaleEffect(x: 1 + envelope * 0.006, y: 1, anchor: .center)
                    .overlay {
                        content
                            .opacity(inkOpacity)
                            .offset(x: -edgeOffset)
                    }
                    .overlay {
                        content
                            .opacity(inkOpacity)
                            .offset(x: edgeOffset)
                    }
            } else {
                content
            }
        }
    }
}

// MARK: - Stage placement

enum AriaLyricLayoutChoice: String, CaseIterable {
    case center
    case lower
    case upper

    var label: String {
        switch self {
        case .center: return String(localized: "居中")
        case .lower: return String(localized: "靠下")
        case .upper: return String(localized: "靠上")
        }
    }
}

// MARK: - Lyric language route

enum AriaLyricLanguage: Hashable {
    case chinese
    case foreign

    static func resolve(lines: [AriaLine]) -> AriaLyricLanguage {
        var hanCount = 0
        var kanaCount = 0
        var hangulCount = 0
        var latinCount = 0
        var inspectedCount = 0

        for line in lines where !line.isInterlude {
            for scalar in line.fullText.unicodeScalars {
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                    hanCount += 1
                case 0x3040...0x30FF, 0x31F0...0x31FF:
                    kanaCount += 1
                case 0xAC00...0xD7AF, 0x1100...0x11FF:
                    hangulCount += 1
                // 拉丁及其他外语文字（西里尔/希腊/阿拉伯/希伯来/泰文/天城文），
                // 保证俄语、泰语等歌曲也判定为外语，而不是被汉字比例误判成中文。
                case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F,
                     0x0370...0x03FF, 0x0400...0x04FF, 0x0530...0x058F,
                     0x0590...0x05FF, 0x0600...0x06FF, 0x0900...0x097F,
                     0x0E00...0x0E7F:
                    latinCount += 1
                default:
                    break
                }
                inspectedCount += 1
                if inspectedCount >= 1_200 {
                    break
                }
            }
            if inspectedCount >= 1_200 {
                break
            }
        }

        if kanaCount > 0 || hangulCount > 0 {
            return .foreign
        }
        let languageCharacters = max(hanCount + latinCount, 1)
        return hanCount >= 4 && Double(hanCount) / Double(languageCharacters) >= 0.42
            ? .chinese
            : .foreign
    }
}

extension String {
    /// Keeps the final four graphemes together so a long lyric cannot leave 1–3
    /// characters on a line by themselves.
    func preventingOrphanLastLine(minTail: Int = 4) -> String {
        let characters = Array(self)
        guard characters.count > minTail + 2 else { return self }

        let splitIndex = characters.count - minTail
        let joinedTail = characters[splitIndex...]
            .map(String.init)
            .joined(separator: "\u{2060}")
        return String(characters[..<splitIndex]) + joinedTail
    }
}

// MARK: - Shared Folia runtime

enum AriaWordStatus: Equatable {
    case waiting
    case active
    case passed
}

struct AriaFoliaToken: Identifiable {
    let id: Int
    let text: String
    let start: Double
    let end: Double
    let graphemes: [AriaGrapheme]
    let isCJK: Bool

    init(word: AriaWord) {
        id = word.id
        text = word.text
        start = word.startTime
        end = word.endTime
        graphemes = AriaLyricEngine.graphemeTimings(for: word)
        isCJK = word.text.contains(where: AriaLyricEngine.isCJKChar)
    }
}

enum AriaFoliaTokenCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [String: [AriaFoliaToken]] = [:]

    static func tokens(for line: AriaLine) -> [AriaFoliaToken] {
        let key = "\(line.id)|\(line.startTime)|\(line.fullText.hashValue)|\(line.displayWords.count)"

        lock.lock()
        defer { lock.unlock() }

        if let cached = storage[key] {
            return cached
        }

        let tokens = line.displayWords.map(AriaFoliaToken.init)
        if storage.count >= 160 {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = tokens
        return tokens
    }

    static func clear() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Cadenza / Partita / Tilt use Folia's semantic layout units. Keeping this
/// cache separate prevents their phrase grouping from changing Classic and
/// Fume, which still need the original per-word timing stream.
enum AriaFoliaSemanticTokenCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [String: [AriaFoliaToken]] = [:]

    static func tokens(for line: AriaLine) -> [AriaFoliaToken] {
        let key = "\(line.id)|\(line.startTime)|\(line.fullText.hashValue)|semantic"

        lock.lock()
        defer { lock.unlock() }

        if let cached = storage[key] {
            return cached
        }

        let words = AriaLyricEngine.buildVisualizerDisplayWords(
            fullText: line.fullText,
            words: line.words
        )
        let tokens = words.map(AriaFoliaToken.init)
        if storage.count >= 160 {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = tokens
        return tokens
    }

    static func clear() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

enum AriaFoliaRuntime {
    static func activeEnd(for token: AriaFoliaToken, hints: AriaRenderHints) -> Double {
        switch hints.revealMode {
        case .instant:
            return hints.renderEndTime
        case .fast:
            return min(hints.renderEndTime, max(token.end, token.start + 0.12))
        case .normal:
            return token.end
        }
    }

    static func status(
        for token: AriaFoliaToken,
        hints: AriaRenderHints,
        time: Double
    ) -> AriaWordStatus {
        let activeEnd = activeEnd(for: token, hints: hints)
        if time >= token.start - hints.wordLookahead, time <= activeEnd {
            return .active
        }
        return time > activeEnd ? .passed : .waiting
    }

    static func progress(for token: AriaFoliaToken, time: Double) -> Double {
        clamp((time - token.start) / max(token.end - token.start, 0.05))
    }

    static func bodyMix(
        for token: AriaFoliaToken,
        hints: AriaRenderHints,
        time: Double
    ) -> Double {
        if time < token.start { return 0 }
        if hints.revealMode == .instant {
            return time <= hints.renderEndTime ? 1 : 0
        }
        if time <= token.end {
            return progress(for: token, time: time)
        }

        let fadeDuration = hints.revealMode == .fast ? 0.12 : 0.8
        return 1 - clamp((time - token.end) / fadeDuration)
    }

    static func glowEnvelope(
        for token: AriaFoliaToken,
        hints: AriaRenderHints,
        time: Double
    ) -> Double {
        if hints.revealMode == .instant {
            guard time >= token.start, time <= hints.renderEndTime else { return 0 }
            return keyframedGlow(clamp((time - token.start) / 0.067))
        }

        let duration = max(token.end - token.start, hints.revealMode == .fast ? 0.045 : 0.1)
        guard time >= token.start else { return 0 }
        if time <= token.end {
            let progress = clamp((time - token.start) / duration)
            if hints.revealMode == .fast {
                if progress < 0.14 { return easeOutCubic(progress / 0.14) }
                if progress < 0.82 { return 1 }
                return mix(1, 0.92, (progress - 0.82) / 0.18)
            }
            if progress < 0.18 { return easeOutCubic(progress / 0.18) }
            if progress < 0.9 { return 1 }
            return mix(1, 0.9, (progress - 0.9) / 0.1)
        }

        let fadeDuration = hints.revealMode == .fast ? 0.14 : 0.9
        let fade = clamp((time - token.end) / fadeDuration)
        return (hints.revealMode == .fast ? 1 : 0.9) * pow(1 - fade, 2)
    }

    static func passedDrift(for token: AriaFoliaToken, time: Double) -> Double {
        guard time > token.end else { return 0 }
        return easeInOutQuad(clamp((time - token.end) / 5))
    }

    static func revealProgress(at time: Double, start: Double, duration: Double) -> Double {
        easeOutCubic(clamp((time - start) / max(duration, 0.001)))
    }

    static func clamp(_ value: Double, min: Double = 0, max: Double = 1) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * clamp(amount)
    }

    static func easeOutCubic(_ value: Double) -> Double {
        1 - pow(1 - clamp(value), 3)
    }

    static func easeInOutQuad(_ value: Double) -> Double {
        let value = clamp(value)
        return value < 0.5
            ? 2 * value * value
            : 1 - pow(-2 * value + 2, 2) / 2
    }

    private static func keyframedGlow(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        if progress < 0.3 {
            return easeOutCubic(progress / 0.3)
        }
        return 1 - clamp((progress - 0.3) / 0.7)
    }
}

enum AriaFoliaColor {
    private struct Components {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Color: Components] = [:]

    /// Resolves both palette colors once for a render pass. Per-glyph animation
    /// then only performs scalar interpolation and never takes the color cache
    /// lock again.
    struct Mixer {
        private let fromColor: Color
        private let toColor: Color
        private let fromRed: Double
        private let fromGreen: Double
        private let fromBlue: Double
        private let fromAlpha: Double
        private let toRed: Double
        private let toGreen: Double
        private let toBlue: Double
        private let toAlpha: Double

        fileprivate init(
            fromColor: Color,
            toColor: Color,
            fromRed: Double,
            fromGreen: Double,
            fromBlue: Double,
            fromAlpha: Double,
            toRed: Double,
            toGreen: Double,
            toBlue: Double,
            toAlpha: Double
        ) {
            self.fromColor = fromColor
            self.toColor = toColor
            self.fromRed = fromRed
            self.fromGreen = fromGreen
            self.fromBlue = fromBlue
            self.fromAlpha = fromAlpha
            self.toRed = toRed
            self.toGreen = toGreen
            self.toBlue = toBlue
            self.toAlpha = toAlpha
        }

        func color(amount: Double) -> Color {
            let amount = AriaFoliaRuntime.clamp(amount)
            if amount <= 0.001 { return fromColor }
            if amount >= 0.999 { return toColor }
            return Color(
                red: fromRed + (toRed - fromRed) * amount,
                green: fromGreen + (toGreen - fromGreen) * amount,
                blue: fromBlue + (toBlue - fromBlue) * amount,
                opacity: fromAlpha + (toAlpha - fromAlpha) * amount
            )
        }
    }

    static func mixer(_ from: Color, _ to: Color) -> Mixer {
        let fromComponents = components(for: from)
        let toComponents = components(for: to)
        return Mixer(
            fromColor: from,
            toColor: to,
            fromRed: fromComponents.red,
            fromGreen: fromComponents.green,
            fromBlue: fromComponents.blue,
            fromAlpha: fromComponents.alpha,
            toRed: toComponents.red,
            toGreen: toComponents.green,
            toBlue: toComponents.blue,
            toAlpha: toComponents.alpha
        )
    }

    static func mix(_ from: Color, _ to: Color, amount: Double) -> Color {
        let amount = AriaFoliaRuntime.clamp(amount)
        guard amount > 0.001 else { return from }
        guard amount < 0.999 else { return to }

        let from = components(for: from)
        let to = components(for: to)
        return Color(
            red: from.red + (to.red - from.red) * amount,
            green: from.green + (to.green - from.green) * amount,
            blue: from.blue + (to.blue - from.blue) * amount,
            opacity: from.alpha + (to.alpha - from.alpha) * amount
        )
    }

    private static func components(for color: Color) -> Components {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[color] {
            return cached
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let components = Components(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
        if cache.count >= 64 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[color] = components
        return components
    }
}

// MARK: - Renderer

struct AriaFoliaLyricStage: View {
    let lines: [AriaLine]
    let activeIndex: Int
    let palette: AriaPalette
    let effect: AriaLyricEffect
    var songIdentity: String = ""
    let language: AriaLyricLanguage
    let fontChoice: AriaLyricFontChoice
    let fontScale: Double
    let time: Double
    let stageSize: CGSize

    @ViewBuilder
    var body: some View {
        switch effect {
        case .classic:
            EmptyView()
        case .cadenza:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else if language == .foreign {
                    AriaForeignCadenzaLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                } else {
                    AriaCadenzaLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .partita:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else if language == .foreign {
                    AriaForeignPartitaLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                } else {
                    AriaPartitaLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .tilt:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else if language == .foreign {
                    AriaForeignTiltLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                } else {
                    AriaTiltLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .fume:
            if language == .foreign {
                AriaForeignFumeStage(
                    lines: lines,
                    activeIndex: activeIndex,
                    palette: palette,
                    fontChoice: fontChoice,
                    fontScale: fontScale,
                    time: time,
                    stageSize: stageSize
                )
            } else {
                AriaFumeLyricStage(
                    lines: lines,
                    activeIndex: activeIndex,
                    palette: palette,
                    fontChoice: fontChoice,
                    fontScale: fontScale,
                    time: time,
                    stageSize: stageSize
                )
            }
        case .canopy:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else {
                    AriaCanopyLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        language: language,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize,
                        previousLine: lines.first { $0.id == line.id - 1 }
                    )
                }
            }
        case .tide:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else {
                    AriaTideLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .echo:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else {
                    AriaEchoLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .poster:
            // 海报按播放时间直接切场，通用换句会缩小并模糊整块背景。
            if lines.indices.contains(activeIndex) {
                let line = lines[activeIndex]
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(line: line, palette: palette, fontChoice: fontChoice,
                                        fontScale: fontScale, time: time)
                } else {
                    AriaPosterLyricLineView(line: line, palette: palette, arrangement: AriaPosterArrangement(songIdentity: songIdentity),
                                            compositionIndex: lines.prefix(activeIndex).filter { !$0.isInterlude && !$0.isCredit }.count,
                                            fontChoice: fontChoice, fontScale: fontScale, time: time)
                }
            }
        case .refraction:
            AriaFoliaLineHost(lines: lines, activeIndex: activeIndex) { line in
                if line.isInterlude {
                    AriaFoliaInterlude(line: line, palette: palette, time: time)
                } else if line.isCredit {
                    AriaFoliaCreditLine(
                        line: line,
                        palette: palette,
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time
                    )
                } else {
                    AriaRefractionLyricLineView(
                        line: line,
                        palette: palette.lineVariant(line.id),
                        fontChoice: fontChoice,
                        fontScale: fontScale,
                        time: time,
                        stageSize: stageSize
                    )
                }
            }
        case .cappella:
            if language == .foreign {
                AriaForeignCappellaStage(
                    lines: lines,
                    activeIndex: activeIndex,
                    palette: palette,
                    fontChoice: fontChoice,
                    fontScale: fontScale,
                    time: time,
                    stageSize: stageSize
                )
            } else {
                AriaCappellaLyricStage(
                    lines: lines,
                    activeIndex: activeIndex,
                    palette: palette,
                    fontChoice: fontChoice,
                    fontScale: fontScale,
                    time: time,
                    stageSize: stageSize
                )
            }
        }
    }
}

// MARK: - Shared line host

private struct AriaFoliaLineHost<Content: View>: View {
    let lines: [AriaLine]
    let activeIndex: Int
    let content: (AriaLine) -> Content

    @State private var displayedLineID = -1

    init(
        lines: [AriaLine],
        activeIndex: Int,
        @ViewBuilder content: @escaping (AriaLine) -> Content
    ) {
        self.lines = lines
        self.activeIndex = activeIndex
        self.content = content
    }

    private var activeLineID: Int {
        activeIndex >= 0 ? lines[activeIndex].id : -1
    }

    private var displayedLine: AriaLine? {
        let directIndex = displayedLineID - 1
        if lines.indices.contains(directIndex), lines[directIndex].id == displayedLineID {
            return lines[directIndex]
        }
        return lines.first { $0.id == displayedLineID }
    }

    var body: some View {
        ZStack {
            if let displayedLine {
                content(displayedLine)
                    .id(displayedLine.id)
                    .transition(.ariaFoliaLine(displayedLine.hints.transitionMode))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            displayedLineID = activeLineID
        }
        .onChange(of: activeLineID) { _, newValue in
            withAnimation(.easeOut(duration: 0.28)) {
                displayedLineID = newValue
            }
        }
    }
}

private struct AriaFoliaLineTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .blur(radius: blur)
    }
}

private extension AnyTransition {
    static func ariaFoliaLine(_ mode: AriaTransitionMode) -> AnyTransition {
        switch mode {
        case .none:
            return .asymmetric(
                insertion: .identity,
                removal: .modifier(
                    active: AriaFoliaLineTransitionModifier(opacity: 0, scale: 1.02, blur: 6),
                    identity: AriaFoliaLineTransitionModifier(opacity: 1, scale: 1, blur: 0)
                )
            )
        case .fast:
            return .asymmetric(
                insertion: .modifier(
                    active: AriaFoliaLineTransitionModifier(opacity: 0.35, scale: 0.96, blur: 4),
                    identity: AriaFoliaLineTransitionModifier(opacity: 1, scale: 1, blur: 0)
                ),
                removal: .modifier(
                    active: AriaFoliaLineTransitionModifier(opacity: 0, scale: 1.04, blur: 10),
                    identity: AriaFoliaLineTransitionModifier(opacity: 1, scale: 1, blur: 0)
                )
            )
        case .normal:
            return .asymmetric(
                insertion: .modifier(
                    active: AriaFoliaLineTransitionModifier(opacity: 0, scale: 0.9, blur: 10),
                    identity: AriaFoliaLineTransitionModifier(opacity: 1, scale: 1, blur: 0)
                ),
                removal: .modifier(
                    active: AriaFoliaLineTransitionModifier(opacity: 0, scale: 1.1, blur: 20),
                    identity: AriaFoliaLineTransitionModifier(opacity: 1, scale: 1, blur: 0)
                )
            )
        }
    }
}

private struct AriaFoliaInterlude: View {
    let line: AriaLine
    let palette: AriaPalette
    let time: Double

    var body: some View {
        let progress = AriaFoliaRuntime.clamp(
            (time - line.startTime) / max(line.rawDuration, 0.1)
        )
        let activeDot = min(5, Int(progress * 6))

        HStack(spacing: 18) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index <= activeDot ? palette.accent : palette.primary.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == activeDot ? 1.25 : 1)
                    .shadow(
                        color: palette.accent.opacity(index == activeDot ? 0.55 : 0),
                        radius: 10
                    )
            }
        }
        .animation(.smooth(duration: 0.22), value: activeDot)
    }
}

/// 制作/发行信息行的克制渲染：小号静态排版 + 缓入，
/// 不吃巨字、碎幕、逐字弹跳等强动画，开场不至于满屏乱飞。
struct AriaFoliaCreditLine: View {
    let line: AriaLine
    let palette: AriaPalette
    let fontChoice: AriaLyricFontChoice
    let fontScale: Double
    let time: Double

    private var parts: (label: String, value: String)? {
        guard let separator = line.fullText.firstIndex(
            where: { $0 == ":" || $0 == "：" }
        ) else { return nil }
        let label = line.fullText[..<separator].trimmingCharacters(in: .whitespaces)
        let value = line.fullText[line.fullText.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return (label, value)
    }

    var body: some View {
        let appear = AriaFoliaRuntime.easeOutCubic(
            AriaFoliaRuntime.clamp((time - line.startTime) / 0.6)
        )
        let size = 17 * CGFloat(fontScale)

        Group {
            if let parts {
                HStack(spacing: 10) {
                    Text(parts.label)
                        .font(fontChoice.font(size: size * 0.82, weight: .semibold))
                        .foregroundStyle(palette.accent.opacity(0.85))

                    Rectangle()
                        .fill(palette.primary.opacity(0.25))
                        .frame(width: 1, height: size * 0.8)

                    Text(parts.value)
                        .font(fontChoice.font(size: size, weight: .medium))
                        .foregroundStyle(palette.primary.opacity(0.78))
                }
            } else {
                Text(line.fullText)
                    .font(fontChoice.font(size: size, weight: .medium))
                    .foregroundStyle(palette.primary.opacity(0.78))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 32)
        .opacity(appear)
        .offset(y: CGFloat(1 - appear) * 8)
    }
}
