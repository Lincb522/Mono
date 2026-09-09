import SwiftUI

struct SignatureArtworkFace<Cover: View>: View {
    let kind: SignatureFloatingBarKind
    let progress: Double
    let animates: Bool
    let accent: Color
    @ViewBuilder let cover: () -> Cover
    let asset: (String) -> Image

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            switch kind {
            case .vinylNeedle:
                let side = min(size.width * 0.84, size.height)
                ZStack(alignment: .leading) {
                    ZStack {
                        SignatureMotionTimeline(isAnimating: animates) { time in
                            ZStack {
                                asset("SignatureVinylDisc").resizable().interpolation(.high)
                                cover().aspectRatio(contentMode: .fill)
                                    .frame(width: side * 0.37, height: side * 0.37).clipShape(Circle())
                                Circle().fill(Color(white: 0.12)).frame(width: side * 0.025, height: side * 0.025)
                            }.rotationEffect(.degrees(time * 22))
                        }
                        Circle().trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90)).padding(side * 0.022)
                    }.frame(width: side, height: side)
                    SignatureTonearm().frame(width: size.width, height: size.height)
                }.frame(width: size.width, height: size.height, alignment: .leading)
            case .orbit:
                ZStack {
                    cover().aspectRatio(contentMode: .fill)
                        .frame(width: size.height * 0.77, height: size.height * 0.77).clipShape(Circle())
                        .overlay(Circle().strokeBorder(.primary.opacity(0.13), lineWidth: 0.8))
                    Ellipse().stroke(.primary.opacity(0.48), lineWidth: 0.8)
                        .frame(width: size.width * 1.02, height: size.height * 0.53)
                        .rotationEffect(.degrees(-37))
                    Circle().fill(accent).frame(width: 7, height: 7)
                        .position(x: size.width * 0.85, y: size.height * 0.095)
                }.frame(width: size.width, height: size.height)
            case .filmstrip:
                HStack(spacing: 4) {
                    perforations
                    cover().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    perforations
                }
                .padding(4)
                .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 4))
            default:
                cover().aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.38), lineWidth: 0.7))
            }
        }
        .accessibilityHidden(true)
    }

    private var perforations: some View {
        VStack(spacing: 4) {
            ForEach(0..<6) { _ in
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.91)).frame(width: 6, height: 7)
            }
        }.frame(width: 6)
    }
}

private struct SignatureTonearm: View {
    var body: some View {
        Canvas { context, size in
            let base = CGPoint(x: size.width * 0.91, y: size.height * 0.04)
            let elbow = CGPoint(x: size.width * 0.80, y: size.height * 0.60)
            let tip = CGPoint(x: size.width * 0.61, y: size.height * 0.88)
            var arm = Path()
            arm.move(to: base); arm.addLine(to: elbow); arm.addQuadCurve(to: tip, control: CGPoint(x: size.width * 0.75, y: size.height * 0.75))
            var shadow = context
            shadow.translateBy(x: 1.5, y: 1.5)
            shadow.addFilter(.blur(radius: 1.1))
            shadow.stroke(arm, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.stroke(arm, with: .linearGradient(Gradient(colors: [Color(white: 0.44), .white, Color(white: 0.59)]), startPoint: CGPoint(x: base.x - 4, y: 0), endPoint: CGPoint(x: tip.x + 4, y: size.height)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            context.stroke(arm, with: .color(.white.opacity(0.62)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            for (position, width, height, angle) in [(base, 8.0, 12.0, 16.0), (tip, 7.0, 13.0, 41.0)] {
                var part = context
                part.translateBy(x: position.x, y: position.y)
                part.rotate(by: .degrees(angle))
                let shape = RoundedRectangle(cornerRadius: 1.2).path(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                part.fill(shape, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.57), Color(white: 0.91)]), startPoint: CGPoint(x: -width/2, y: 0), endPoint: CGPoint(x: width/2, y: 0)))
                part.stroke(shape, with: .color(.black.opacity(0.30)), lineWidth: 0.5)
            }
        }
    }
}

struct SignatureCassetteArt: View {
    let progress: Double
    let animates: Bool
    let asset: (String) -> Image

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            asset("SignatureCassetteWindow").resizable().interpolation(.high)
            SignatureMotionTimeline(isAnimating: animates) { time in
                ZStack {
                    ForEach(0..<2) { index in
                        asset("SignatureCassetteRotor").resizable().interpolation(.high)
                            .frame(width: size.height * 0.696, height: size.height * 0.696)
                            .rotationEffect(.degrees(time * (index == 0 ? 82 : 76)))
                            .position(x: size.width * (index == 0 ? 0.1833 : 0.8135), y: size.height * 0.5179)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct SignatureWaveform: View {
    let bands: [Double]
    let progress: Double
    let accent: Color
    let ink: Color
    var body: some View {
        Canvas { context, size in
            let count = max(bands.count, 64)
            let stride = size.width / CGFloat(count)
            for index in 0..<count {
                let value = bands.isEmpty ? 0 : bands[min(index * bands.count / count, bands.count - 1)]
                let height = max(1, min(max(value, 0), 1) * size.height)
                let x = (CGFloat(index) + 0.5) * stride
                var bar = Path(); bar.move(to: CGPoint(x: x, y: (size.height - height) / 2)); bar.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                let played = Double(index) / Double(count) < progress
                context.stroke(bar, with: .color(played ? accent : ink.opacity(0.30)), style: StrokeStyle(lineWidth: max(1, stride * 0.30), lineCap: .round))
            }
        }
    }
}

struct SignatureFilmRuler: View {
    let progress: Double
    let accent: Color
    let ink: Color
    var body: some View {
        Canvas { context, size in
            let count = max(Int(size.width / 6), 2)
            for index in 0..<count {
                let x = Double(index) / Double(count - 1) * size.width
                let height = size.height * (index.isMultiple(of: 5) ? 0.76 : (index.isMultiple(of: 2) ? 0.48 : 0.28))
                var tick = Path(); tick.move(to: CGPoint(x: x, y: (size.height - height) / 2)); tick.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                context.stroke(tick, with: .color(ink.opacity(0.47)), lineWidth: 0.7)
            }
            var marker = Path(); marker.move(to: CGPoint(x: size.width * progress, y: 0)); marker.addLine(to: CGPoint(x: size.width * progress, y: size.height))
            context.stroke(marker, with: .color(accent), lineWidth: 1.4)
        }
    }
}

struct SignatureMeterFace: View {
    let level: Double
    let channel: Int
    let asset: (String) -> Image
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let unit = size.width / 108
            asset("SignatureMeterFace").resizable().interpolation(.high)
            Canvas { context, _ in
                let pivot = CGPoint(x: size.width * 0.58, y: size.height * 0.88)
                let radius = size.height * 0.60
                var arc = Path()
                arc.addArc(center: pivot, radius: radius, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
                context.stroke(arc, with: .color(.black.opacity(0.75)), lineWidth: 0.55 * unit)
                for index in 0...24 {
                    let angle = (-150 + Double(index) * 5) * .pi / 180
                    let length = (index.isMultiple(of: 4) ? 4.0 : 2.4) * unit
                    var tick = Path()
                    tick.move(to: CGPoint(x: pivot.x + cos(angle) * radius, y: pivot.y + sin(angle) * radius))
                    tick.addLine(to: CGPoint(x: pivot.x + cos(angle) * (radius + length), y: pivot.y + sin(angle) * (radius + length)))
                    context.stroke(tick, with: .color(index >= 20 ? .red.opacity(0.8) : .black.opacity(0.85)), lineWidth: 0.55 * unit)
                }
                let labels = ["−20", "−10", "−6", "−3", "0", "+3"]
                for index in labels.indices {
                    let angle = (-150 + Double(index) * 24) * .pi / 180
                    let center = CGPoint(x: pivot.x + cos(angle) * (radius + 10 * unit), y: pivot.y + sin(angle) * (radius + 10 * unit))
                    context.draw(Text(labels[index]).font(.system(size: 7.5 * unit)).foregroundColor(index == 5 ? .red : .black), at: center)
                }
                let angle = (-150 + min(max(level, 0), 1) * 120) * .pi / 180
                var needle = Path(); needle.move(to: pivot); needle.addLine(to: CGPoint(x: pivot.x + cos(angle) * (radius + 4 * unit), y: pivot.y + sin(angle) * (radius + 4 * unit)))
                context.stroke(needle, with: .color(Color(red: 0.85, green: 0.10, blue: 0.08)), style: StrokeStyle(lineWidth: 1.1 * unit, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: pivot.x - 2 * unit, y: pivot.y - 2 * unit, width: 4 * unit, height: 4 * unit)), with: .color(.black))
                context.draw(Text(channel == 0 ? "L" : "R").font(.system(size: 8 * unit)).foregroundColor(.black), at: CGPoint(x: size.width * 0.50, y: size.height * 0.76))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct SignatureMotionTimeline<Content: View>: View {
    let isAnimating: Bool
    @ViewBuilder var content: (TimeInterval) -> Content
    @State private var accumulated: TimeInterval = 0
    @State private var anchor = Date()
    @State private var running = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !running)) { context in
            content(accumulated + (running ? max(context.date.timeIntervalSince(anchor), 0) : 0))
        }
        .onAppear { synchronize() }
        .onChange(of: isAnimating) { _ in synchronize() }
        .onDisappear { freeze() }
    }
    private func freeze() {
        if running { accumulated += max(Date().timeIntervalSince(anchor), 0) }
        running = false
    }
    private func synchronize() {
        freeze(); anchor = Date(); running = isAnimating
    }
}
