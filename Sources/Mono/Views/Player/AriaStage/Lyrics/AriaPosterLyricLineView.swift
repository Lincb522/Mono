import SwiftUI
import UIKit

/// Timed typography compositions. The song, not a looping view animation, owns every phase.
struct AriaPosterLyricLineView: View {
    let line: AriaLine
    let palette: AriaPalette
    let arrangement: AriaPosterArrangement
    let compositionIndex: Int
    let fontChoice: AriaLyricFontChoice
    let fontScale: Double
    let time: Double
    @AppStorage("ariaPosterShowTranslation") private var showTranslation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tokens: [AriaFoliaToken] { AriaFoliaSemanticTokenCache.tokens(for: line) }
    var scene: AriaPosterScene { arrangement.scene(at: compositionIndex) }
    var composition: AriaPosterComposition { scene.composition }
    var variation: Int { scene.variation }
    var layoutDirection: CGFloat { variation.isMultiple(of: 2) ? arrangement.direction : -arrangement.direction }
    var phase: Double { min(1, elapsed / max(0.1, line.rawDuration)) }
    var elapsed: Double { max(0, time - line.startTime) }
    var entrance: Double { ease(elapsed / min(0.36, max(0.08, line.rawDuration * 0.18))) }
    static func contrastingInk(for accent: Color) -> Color {
        ThemeColorCustomization.contrastRatio(between: .white, and: accent)
            > ThemeColorCustomization.contrastRatio(between: Color(hex: "171A13"), and: accent)
            ? .white : Color(hex: "171A13")
    }
    var ink: Color { Self.contrastingInk(for: palette.accent) }
    private var colored: Bool { (composition.rawValue.isMultiple(of: 2)) != (variation >= 2) }
    var foreground: Color { colored ? ink : palette.accent }
    var background: Color { colored ? palette.accent : ink }

    private var matrixCover: Double { ease((phase - 0.68) / 0.2) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The parent already respects the system safe area, including the Dynamic Island.
            // Only the background extends edge-to-edge; do not inset the same safe area twice.
            let horizontal: CGFloat = 20
            let vertical: CGFloat = 30
            let hasTranslation = showTranslation && !(line.translation ?? "").isEmpty
            let captionHeight: CGFloat = hasTranslation ? min(64, size.height * 0.17) : 0
            let contentSize = CGSize(
                width: max(1, size.width - horizontal * 2),
                height: max(1, size.height - vertical * 2 - captionHeight)
            )
            ZStack {
                stageBackground(size: size)
                    .ignoresSafeArea(.container)
                VStack(spacing: 8) {
                    Group {
                        if reduceMotion {
                            headline(line.fullText, size: contentSize, color: foreground)
                        } else {
                            compositionView(size: contentSize)
                        }
                    }
                    .frame(width: contentSize.width, height: contentSize.height)
                    if showTranslation, let translation = line.translation, !translation.isEmpty {
                        AriaPosterFittedText(
                            text: translation,
                            font: fontChoice.uiFont(size: 22, weight: .medium),
                            color: foreground
                        )
                        .frame(width: contentSize.width, height: captionHeight)
                        .background(background)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([line.fullText, showTranslation ? line.translation : nil].compactMap { $0 }.joined(separator: "\n"))
    }

    @ViewBuilder
    private func stageBackground(size: CGSize) -> some View {
        if composition == .split && !reduceMotion {
            HStack(spacing: 0) { background; foreground }
        } else if composition == .matrix && matrixCover > 0 && !reduceMotion {
            foreground
        } else {
            background
        }
    }

    @ViewBuilder
    private func compositionView(size: CGSize) -> some View {
        switch composition {
        case .punch:
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, 28)
                .scaleEffect(0.65 + 0.35 * entrance)
        case .phrases:
            phraseStack(size: size)
        case .echo:
            ZStack {
                ForEach(1..<7, id: \.self) { layer in
                    AriaPosterOutline(text: line.fullText,
                                      font: fontChoice.uiFont(size: max(28, min(90, size.width * 0.11)) * CGFloat(fontScale), weight: .black),
                                      color: foreground.opacity(0.65))
                        .frame(width: size.width * 0.65, height: size.height * 0.24)
                        .offset(x: CGFloat(layer) * size.width * 0.012 * entrance * layoutDirection, y: -CGFloat(layer) * size.height * 0.02 * entrance)
                        .rotationEffect(.degrees(Double(layoutDirection) * 7 * entrance))
                }
                headline(line.fullText, size: size, color: foreground)
                    .padding(.horizontal, size.width * 0.1)
            }
            .scaleEffect(0.82 + 0.18 * entrance)
        case .wall:
            ZStack {
                typeWall(size: size)
                    .scaleEffect(1 - 0.9 * ease((elapsed / max(0.1, line.rawDuration) - 0.62) / 0.2))
                    .opacity(1 - ease((elapsed / max(0.1, line.rawDuration) - 0.78) / 0.1))
                headline(line.fullText, size: size, color: foreground)
                    .padding(.horizontal, 28)
                    .opacity(ease((elapsed / max(0.1, line.rawDuration) - 0.65) / 0.2))
            }
        case .matrix:
            matrix(size: size)
        case .quiet:
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, size.width * 0.1)
                .scaleEffect(0.38 + entrance * 0.06)
                .offset(x: variation.isMultiple(of: 2) ? -size.width * 0.14 : size.width * 0.14,
                        y: variation < 2 ? -size.height * 0.1 : size.height * 0.1)
                .opacity(entrance)
        case .split:
            splitStage(size: size)
        case .ribbon:
            ribbonStage(size: size)
        case .focus:
            focusStage(size: size)
        case .scatter:
            scatterStage(size: size)
        case .staircase:
            staircaseStage(size: size)
        case .shutters:
            shuttersStage(size: size)
        case .mosaic:
            mosaicStage(size: size)
        case .rail:
            railStage(size: size)
        case .pivot:
            pivotStage(size: size)
        case .orbit:
            orbitStage(size: size)
        case .brackets:
            bracketsStage(size: size)
        case .tunnel:
            tunnelStage(size: size)
        case .margin:
            marginStage(size: size)
        case .accordion:
            accordionStage(size: size)
        case .spotlight:
            spotlightStage(size: size)
        }
    }

    func headline(_ text: String, size: CGSize, color: Color) -> some View {
        AriaPosterFittedText(
            text: text,
            font: fontChoice.uiFont(size: min(112, max(32, size.width * 0.12)) * CGFloat(fontScale), weight: .black),
            color: color
        )
        .frame(maxWidth: .infinity)
        .frame(height: size.height * 0.64)
    }

    private func phraseStack(size: CGSize) -> some View {
        let groups = phraseGroups
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                let reveal = ease((time - (group.first?.start ?? line.startTime)) / 0.22)
                HStack(spacing: 14) {
                    AriaPosterFittedText(
                        text: group.map(\.text).joined(separator: group.allSatisfy(\.isCJK) ? "" : " "),
                        font: fontChoice.uiFont(size: min(70, max(25, size.height * 0.14)) * CGFloat(fontScale), weight: index == 1 ? .regular : .black),
                        color: foreground
                    )
                    .frame(height: max(1, (size.height * 0.68 - 24) / CGFloat(max(1, groups.count))))
                    .offset(y: (1 - reveal) * 8)
                    Rectangle()
                        .fill(foreground)
                        .frame(width: max(14, size.width * CGFloat(index + 1) * 0.035), height: max(8, size.height * 0.065))
                        .scaleEffect(x: reveal, y: 1, anchor: .trailing)
                }
                .opacity(reveal)
            }
        }
        .padding(.horizontal, size.width * 0.075)
        .padding(.vertical, size.height * 0.16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    var phraseGroups: [[AriaFoliaToken]] {
        let source = tokens
        guard !source.isEmpty else { return [] }
        let count = min(2 + (arrangement.phraseRows + variation) % 3, source.count)
        let stride = Int(ceil(Double(source.count) / Double(count)))
        return Swift.stride(from: 0, to: source.count, by: stride).map {
            Array(source[$0..<min(source.count, $0 + stride)])
        }
    }

    private func typeWall(size: CGSize) -> some View {
        let rowCount = min(arrangement.wallRows + variation * 2, max(3, Int(size.height / 26)))
        return VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                AriaPosterFittedText(
                    text: line.fullText,
                    font: fontChoice.uiFont(size: max(18, size.height / CGFloat(rowCount) * 0.85), weight: .black),
                    color: foreground
                )
                .frame(width: size.width * 0.88, height: size.height / CGFloat(rowCount))
                .offset(x: CGFloat(row.isMultiple(of: 2) ? -1 : 1) * size.width * 0.035 * (1 - entrance))

            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func matrix(size: CGSize) -> some View {
        let columns = 3 + (arrangement.columns + variation) % 3
        let spread = ease((elapsed / max(0.1, line.rawDuration) - 0.18) / 0.24)
        let cover = ease((elapsed / max(0.1, line.rawDuration) - 0.68) / 0.2)
        return ZStack {
            ZStack {
                ForEach(0..<(columns * 3), id: \.self) { cell in
                    AriaPosterFittedText(text: line.fullText,
                                         font: fontChoice.uiFont(size: max(16, size.width * 0.055), weight: .black),
                                         color: background)
                        .padding(14)
                        .frame(width: size.width * 0.64, height: size.height * 0.58)
                        .background(foreground)
                        .scaleEffect(1 - spread * (1 - 0.88 / CGFloat(columns) / 0.64))
                        .offset(x: (CGFloat(cell % columns) - CGFloat(columns - 1) / 2) * size.width / CGFloat(columns) * spread,
                                y: (CGFloat(cell / columns) - 1) * size.height * 0.28 * spread)
                        .opacity(cell == columns + columns / 2 ? 1 : spread)
                }
            }
            .opacity(1 - min(1, cover * 2))
            // The root background owns the full-screen color change; no central clipping box.
            if cover > 0 {
                headline(line.fullText, size: size, color: background)
                    .padding(.horizontal, 20)
                    .scaleEffect(0.7 + cover * 0.3)
            }
        }
    }

    /// Two color planes share one typographic layout; each half has its own contrast.
    private func splitStage(size: CGSize) -> some View {
        let groups = phraseGroups
        let middle = max(1, (groups.count + 1) / 2)
        let first = groups.prefix(middle).flatMap { $0 }
        let second = groups.dropFirst(middle).flatMap { $0 }
        let firstText = first.map(\.text).joined(separator: first.allSatisfy(\.isCJK) ? "" : " ")
        let secondText = second.map(\.text).joined(separator: second.allSatisfy(\.isCJK) ? "" : " ")
        return HStack(spacing: 24) {
            splitText(firstText, color: foreground)
            splitText(secondText, color: background)
        }
        .frame(width: size.width, height: size.height)
    }

    private func splitText(_ text: String, color: Color) -> some View {
        AriaPosterFittedText(text: text, font: fontChoice.uiFont(size: 96 * CGFloat(fontScale), weight: .black), color: color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(0.88 + entrance * 0.12)
    }

    /// Staggered text strips use timed phrases, rather than another miniature poster grid.
    private func ribbonStage(size: CGSize) -> some View {
        let groups = phraseGroups
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                let reveal = ease((time - (group.first?.start ?? line.startTime)) / 0.28)
                AriaPosterFittedText(
                    text: group.map(\.text).joined(separator: group.allSatisfy(\.isCJK) ? "" : " "),
                    font: fontChoice.uiFont(size: min(62, size.height * 0.12) * CGFloat(fontScale), weight: .black),
                    color: background
                )
                .frame(width: size.width * 0.68, height: size.height * 0.14)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(foreground)
                    .offset(x: (1 - reveal) * size.width * (index.isMultiple(of: 2) ? -0.035 : 0.035))
                    .opacity(reveal)
                    .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
            }
        }
        .padding(.horizontal, size.width * 0.1)
        .frame(width: size.width, height: size.height)
    }

    /// A compact opening aperture becomes a full phrase, leaving breathing room afterward.
    private func focusStage(size: CGSize) -> some View {
        headline(line.fullText, size: size, color: foreground)
            .padding(.horizontal, size.width * 0.08)
            .opacity(entrance)
            .scaleEffect(0.92 + entrance * 0.08)
    }

    func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return 1 - pow(1 - x, 3)
    }
}

/// UIKit/CoreText shapes genuine outline glyphs, including the selected custom font.
struct AriaPosterOutline: View {
    let text: String
    let font: UIFont
    let color: Color

    var body: some View {
        AriaPosterFittedText(text: text, font: font, color: color, outline: true)
    }
}
