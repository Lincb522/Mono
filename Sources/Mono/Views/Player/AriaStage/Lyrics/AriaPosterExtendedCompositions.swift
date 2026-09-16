import SwiftUI

/// Additional compositions share semantic lyric tokens, font selection and the existing
/// playback clock. No independent timers, repeated animations or stock video overlays.
extension AriaPosterLyricLineView {
    private func phraseText(_ group: [AriaFoliaToken]) -> String {
        group.map(\.text).joined(separator: group.allSatisfy(\.isCJK) ? "" : " ")
    }

    private func rowText(_ text: String, size: CGFloat, color: Color, height: CGFloat) -> some View {
        AriaPosterFittedText(
            text: text,
            font: fontChoice.uiFont(size: size * CGFloat(fontScale), weight: .black),
            color: color
        )
        .frame(height: max(1, height))
    }

    /// Reference 7.0–7.6 s: scattered semantic units settle into measured readable rows.
    func scatterStage(size: CGSize) -> some View {
        let groups = phraseGroups
        return Canvas { context, canvas in
            let fontSize = min(66, canvas.height * 0.13) * CGFloat(fontScale)
            for (row, group) in groups.enumerated() {
                let resolved = group.map {
                    context.resolve(Text($0.text).font(fontChoice.font(size: fontSize, weight: .black))
                        .foregroundColor(foreground))
                }
                let measures = resolved.map { $0.measure(in: CGSize(width: 10000, height: 1000)) }
                let gap: CGFloat = group.allSatisfy(\.isCJK) ? 1 : fontSize * 0.2
                let width = measures.reduce(CGFloat(0)) { $0 + $1.width } + gap * CGFloat(max(0, group.count - 1))
                let tallest: CGFloat = measures.map(\.height).max() ?? fontSize
                let widthScale: CGFloat = canvas.width * 0.72 / max(1, width)
                let heightScale: CGFloat = canvas.height * 0.1 / max(1, tallest)
                let scale: CGFloat = min(1, min(widthScale, heightScale))
                var x = (canvas.width - width * scale) / 2
                let y = canvas.height * 0.5 + (CGFloat(row) - CGFloat(groups.count - 1) / 2) * canvas.height * 0.16
                for (index, text) in resolved.enumerated() {
                    let settle = ease((elapsed - Double(index % 5) * min(0.055, line.rawDuration * 0.02)) / max(0.08, min(0.5, line.rawDuration * 0.28)))
                    var copy = context
                    let drift = CGFloat(1 - settle)
                    let dx = CGFloat((index * 7 + row * 3 + variation) % 9 - 4) * canvas.width * 0.11
                    let dy = CGFloat((index * 3 + row + variation) % 7 - 3) * canvas.height * 0.13
                    let angle: Double = Double((index % 3 - 1) * 24) * (1 - settle)
                    let radians: Double = angle * .pi / 180
                    let glyphWidth: CGFloat = measures[index].width * scale
                    let glyphHeight: CGFloat = measures[index].height * scale
                    let halfWidth: CGFloat = (abs(cos(radians)) * glyphWidth + abs(sin(radians)) * glyphHeight) / 2
                    let halfHeight: CGFloat = (abs(sin(radians)) * glyphWidth + abs(cos(radians)) * glyphHeight) / 2
                    let proposedX: CGFloat = x + glyphWidth / 2 + dx * drift
                    let proposedY: CGFloat = y + dy * drift
                    let centerX: CGFloat = min(canvas.width - halfWidth - 4, max(halfWidth + 4, proposedX))
                    let centerY: CGFloat = min(canvas.height - halfHeight - 4, max(halfHeight + 4, proposedY))
                    copy.translateBy(x: centerX, y: centerY)
                    copy.rotate(by: .degrees(angle))
                    copy.scaleBy(x: scale, y: scale)
                    copy.opacity = settle
                    copy.draw(text, at: .zero, anchor: .center)
                    x += (measures[index].width + gap) * scale
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Reference 21.4–22.6 s: rows arrive at different indents, then align as a column.
    func staircaseStage(size: CGSize) -> some View {
        let groups = phraseGroups
        let align = ease((phase - 0.55) / 0.25)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(groups.indices, id: \.self) { index in
                let reveal = ease((time - (groups[index].first?.start ?? line.startTime)) / max(0.08, min(0.28, line.rawDuration * 0.15)))
                rowText(phraseText(groups[index]), size: min(72, size.height * 0.15), color: foreground, height: size.height * 0.6 / CGFloat(max(1, groups.count)))
                    .frame(width: size.width * 0.65, alignment: .leading)
                    .offset(x: CGFloat(index) * size.width * 0.025 * (1 - align) * layoutDirection,
                            y: (1 - reveal) * size.height * 0.12)
                    .opacity(reveal)
            }
        }
        .frame(width: size.width * 0.8, alignment: .leading)
        .frame(width: size.width, height: size.height)
    }

    /// Alternate whole lyric rows; glyphs are never split by a strip mask.
    func shuttersStage(size: CGSize) -> some View {
        let groups = phraseGroups
        return VStack(spacing: 8) {
            ForEach(groups.indices, id: \.self) { row in
                let delay: Double = Double(row) * min(0.06, line.rawDuration * 0.02)
                let progress: Double = ease((elapsed - delay) / max(0.08, min(0.38, line.rawDuration * 0.25)))
                rowText(phraseText(groups[row]), size: size.height * 0.1, color: foreground, height: size.height * 0.6 / CGFloat(max(1, groups.count)))
                    .frame(width: size.width * 0.76)
                    .scaleEffect(x: 0.75 + progress * 0.25, y: 1)
                    .offset(x: size.width * 0.06 * (1 - progress) * (row.isMultiple(of: 2) ? -1 : 1))
                    .opacity(progress)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Pixel cells animate behind an intact lyric, rather than eroding the readable glyphs.
    func mosaicStage(size: CGSize) -> some View {
        let columns: Int = 18 + variation * 2
        let rows: Int = 10
        let seed: Int = variation * 11
        let clear: Double = ease((phase - 0.78) / 0.2)
        let holding: Bool = phase < 0.78
        return ZStack {
            Canvas { context, canvas in
                drawMosaicMask(
                    context: &context, size: canvas, columns: columns, rows: rows,
                    seed: seed, clear: clear, holding: holding
                )
            }
            .foregroundStyle(foreground)
            .opacity(0.12 * entrance)
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, size.width * 0.08)
                .scaleEffect(0.82 + 0.18 * entrance)
        }
        .frame(width: size.width, height: size.height)
    }

    // Keep numeric inference outside the nested SwiftUI result builder.
    private func drawMosaicMask(
        context: inout GraphicsContext,
        size: CGSize,
        columns: Int,
        rows: Int,
        seed: Int,
        clear: Double,
        holding: Bool
    ) {
        let cellWidth: CGFloat = size.width / CGFloat(columns)
        let cellHeight: CGFloat = size.height / CGFloat(rows)
        for row in 0..<rows {
            let rowSeed: Int = row * 31
            for column in 0..<columns {
                let columnSeed: Int = column * 17
                let combinedSeed: Int = columnSeed + rowSeed + seed
                let bucket: Int = combinedSeed % 101
                let order: Double = Double(bucket) / 101.0
                let remaining: Double = (1.0 - clear - order) * 12.0
                let visible: Double = min(1.0, max(0.0, remaining))
                let opacity: Double = holding ? 1.0 : visible
                let rect = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth + 0.5,
                    height: cellHeight + 0.5
                )
                context.stroke(Path(rect.insetBy(dx: 2, dy: 2)), with: .color(foreground.opacity(opacity)), lineWidth: 1)
            }
        }
    }

    /// Original: phrases ride separate typographic tracks and stop at a shared vertical axis.
    func railStage(size: CGSize) -> some View {
        let groups = phraseGroups
        return VStack(spacing: size.height * 0.025) {
            ForEach(groups.indices, id: \.self) { index in
                let reveal = ease((time - (groups[index].first?.start ?? line.startTime)) / max(0.08, min(0.42, line.rawDuration * 0.22)))
                VStack(spacing: 5) {
                    rowText(phraseText(groups[index]), size: min(62, size.height * 0.12), color: foreground, height: size.height * 0.56 / CGFloat(max(1, groups.count)))
                        .offset(x: size.width * 0.07 * (1 - reveal) * (index.isMultiple(of: 2) ? layoutDirection : -layoutDirection))
                    Rectangle().fill(foreground).frame(height: 1.5)
                        .scaleEffect(x: reveal, y: 1, anchor: index.isMultiple(of: 2) ? .leading : .trailing)
                }
                .frame(width: size.width * (index.isMultiple(of: 2) ? 0.78 : 0.61))
                .opacity(reveal)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Original: a typeset block swings into place around a corner, then holds still.
    func pivotStage(size: CGSize) -> some View {
        let angle: Double = (1 - entrance) * 35 * Double(layoutDirection)
        let width: CGFloat = size.width * 0.76
        let height: CGFloat = size.height * 0.8
        let radians: Double = angle * .pi / 180
        let rotatedWidth: CGFloat = width * abs(cos(radians)) + height * abs(sin(radians))
        let rotatedHeight: CGFloat = width * abs(sin(radians)) + height * abs(cos(radians))
        let fit: CGFloat = min(1, min(size.width * 0.94 / max(1, rotatedWidth), size.height * 0.94 / max(1, rotatedHeight)))
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(phraseGroups.enumerated()), id: \.offset) { item in
                rowText(phraseText(item.element), size: min(74, size.height * 0.12), color: foreground, height: size.height * 0.62 / CGFloat(max(1, phraseGroups.count)))
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(angle))
        .scaleEffect(fit)
        .opacity(entrance)
        .frame(width: size.width, height: size.height)
    }

    /// Original: phrase fragments occupy a ring, then gather onto a clean central title.
    func orbitStage(size: CGSize) -> some View {
        let groups = phraseGroups
        let gather = ease((phase - 0.48) / 0.24)
        return ZStack {
            ForEach(groups.indices, id: \.self) { index in
                let angle = Double(index) / Double(max(1, groups.count)) * .pi * 2
                    + Double(layoutDirection) * (1 - entrance) * 0.7
                    + Double(variation) * .pi / 4
                rowText(phraseText(groups[index]), size: min(42, size.height * 0.085), color: foreground, height: size.height * 0.16)
                    .frame(width: size.width * 0.36)
                    .offset(x: cos(angle) * size.width * 0.3 * (1 - gather),
                            y: sin(angle) * size.height * 0.28 * (1 - gather))
                    .opacity(entrance * (1 - gather))
            }
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, 28)
                .scaleEffect(0.6 + gather * 0.18)
                .opacity(gather)
        }
    }

    /// Reference 1.3–2.0 s: a central bar compresses into brackets enclosing small type.
    func bracketsStage(size: CGSize) -> some View {
        let open = ease((phase - 0.08) / 0.28)
        let horizontal = variation.isMultiple(of: 2)
        let separation = (horizontal ? size.width : size.height) * (0.05 + open * 0.36)
        return ZStack {
            ForEach(0..<2, id: \.self) { side in
                Rectangle().fill(foreground)
                    .frame(width: horizontal ? max(3, size.width * 0.018) : size.width * 0.6,
                           height: horizontal ? size.height * (0.4 - open * 0.2) : 3)
                    .offset(x: horizontal ? (side == 0 ? -separation : separation) : 0,
                            y: horizontal ? 0 : (side == 0 ? -separation : separation))
            }
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, size.width * 0.12)
                .scaleEffect(0.48 + 0.08 * open)
                .opacity(entrance)
        }
        .scaleEffect(0.9 + entrance * 0.1)
    }

    /// Original: nested rectangular outlines pull apart as the lyric moves to the foreground.
    func tunnelStage(size: CGSize) -> some View {
        return ZStack {
            ForEach(0..<5, id: \.self) { index in
                let progress = ease((phase - Double(index) * 0.035) / 0.4)
                Rectangle()
                    .stroke(foreground.opacity((1 - progress) * 0.65), lineWidth: 1.5)
                    .frame(width: size.width * (0.18 + progress * 1.25),
                           height: size.height * (0.2 + progress * 1.1))
                    .rotationEffect(.degrees(Double(variation - 1) * Double(index) * (1 - progress)))
            }
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, 28)
                .scaleEffect(0.3 + entrance * 0.55)
        }
    }

    /// Original editorial composition: a huge outline initial and readable offset paragraph.
    func marginStage(size: CGSize) -> some View {
        let first = tokens.first?.text ?? line.fullText
        let left = variation.isMultiple(of: 2)
        return ZStack(alignment: left ? .leading : .trailing) {
            AriaPosterOutline(text: first,
                              font: fontChoice.uiFont(size: size.height * 0.68, weight: .black),
                              color: foreground.opacity(0.45))
                .frame(width: size.width * 0.32, height: size.height * 0.76)
                .offset(x: (1 - entrance) * size.width * (left ? -0.035 : 0.035))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(phraseGroups.enumerated()), id: \.offset) { item in
                    rowText(phraseText(item.element), size: min(52, size.height * 0.085), color: foreground, height: size.height * 0.45 / CGFloat(max(1, phraseGroups.count)))
                        .opacity(ease((time - (item.element.first?.start ?? line.startTime)) / 0.2))
                }
            }
            .padding(18)
            .frame(width: size.width * 0.59, height: size.height * 0.7)
            .background(background)
            .offset(x: size.width * (left ? 0.3 : -0.3))
        }
        .frame(width: size.width * 0.88, height: size.height)
        .frame(width: size.width, height: size.height)
    }

    /// Folded typography, inspired by the paper section but not a fake crumpled-paper texture.
    /// Panel boundaries fall between complete phrases, never through a glyph.
    func accordionStage(size: CGSize) -> some View {
        let groups = phraseGroups
        let fold: Double = 1 - entrance
        return VStack(spacing: 6) {
            ForEach(groups.indices, id: \.self) { panel in
                rowText(phraseText(groups[panel]), size: size.height * 0.1, color: background, height: size.height * 0.6 / CGFloat(max(1, groups.count)))
                    .padding(.horizontal, 12)
                    .frame(width: size.width * 0.76)
                    .background(foreground)
                    .rotation3DEffect(
                        .degrees(fold * (panel.isMultiple(of: 2) ? 45 : -45)),
                        axis: (x: 1, y: 0, z: 0), perspective: 0
                    )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Original: a reverse-color reading band travels over a fixed typographic block.
    func spotlightStage(size: CGSize) -> some View {
        let horizontal = variation.isMultiple(of: 2)
        let travel = ease(phase / 0.82)
        return ZStack {
            headline(line.fullText, size: size, color: foreground)
                .padding(.horizontal, 28)
            ZStack {
                foreground
                headline(line.fullText, size: size, color: background)
                    .padding(.horizontal, 28)
            }
            .frame(width: size.width, height: size.height)
            .mask {
                Rectangle()
                    .frame(width: horizontal ? size.width : size.width * 0.24,
                           height: horizontal ? size.height * 0.22 : size.height)
                    .offset(x: horizontal ? 0 : size.width * (travel - 0.5) * 1.2 * layoutDirection,
                            y: horizontal ? size.height * (travel - 0.5) * 1.2 * layoutDirection : 0)
            }
        }
        .opacity(entrance)
    }
}
