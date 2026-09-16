import SwiftUI
import FFmpegSwiftSDK

enum MonoSoundCenterStyle {
    static let surface = Color(hex: "1C1C1C")
    static let raised = Color(hex: "292929")
    static let secondary = Color(hex: "A4A4A4")
}

struct MonoSoundCenterSplitPanel<Leading: View, Trailing: View>: View {
    @Environment(\.monoSoundCenterLayout) private var layout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if layout.availableSize.width < 360 || dynamicTypeSize >= .xxLarge {
            VStack(spacing: 10) {
                leading()
                trailing()
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                leading()
                    .frame(width: (layout.workspaceMaxWidth - layout.horizontalInset * 2 - 10) * 0.58)
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MonoSoundCenterMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.title.weight(.light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(MonoSoundCenterStyle.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(MonoSoundCenterStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value == "—" ? String(localized: "ai_lab_not_analyzed") : "\(value) \(unit)")
    }
}

struct MonoSoundCenterDial: View {
    let accent: Color
    let title: String
    let value: String
    let fraction: Double?
    let icon: MonoIcon.IconType

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                MonoSoundCenterDottedRing(
                    count: 24,
                    isActive: fraction != nil,
                    foreground: accent,
                    track: Color.white.opacity(0.16),
                    progress: fraction ?? 0
                )
                MonoIcon(icon: icon, size: 14, color: .white.opacity(0.75))
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(MonoSoundCenterStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct MonoSoundCenterFocusCard<Controls: View>: View {
    let accent: Color
    let foreground: Color
    let value: String
    let unit: String
    let title: String
    let detail: String
    let fraction: Double?
    @ViewBuilder let controls: () -> Controls
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                MonoSoundCenterDottedRing(
                    count: 40,
                    isActive: fraction != nil,
                    foreground: foreground,
                    track: foreground.opacity(0.18),
                    progress: fraction ?? 0
                )
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    Text(value)
                        .font(.title.weight(.medium))
                        .monospacedDigit()
                    Text(unit).font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(foreground.opacity(0.8))
            }
            .fixedSize(horizontal: false, vertical: true)
            controls()
        }
        .foregroundStyle(foreground)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(accent, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct MonoSoundCenterDottedRing: View {
    let count: Int
    let isActive: Bool
    let foreground: Color
    let track: Color
    var progress: Double = 1

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let dotSize: CGFloat = diameter > 60 ? 4 : 2.5
            let radius = (diameter - dotSize) / 2
            for index in 0..<count {
                let angle = Double(index) / Double(count) * .pi * 2 - .pi / 2
                let rect = CGRect(
                    x: size.width / 2 + CGFloat(cos(angle)) * radius - dotSize / 2,
                    y: size.height / 2 + CGFloat(sin(angle)) * radius - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let isFilled = isActive && Double(index) < min(1, max(0, progress)) * Double(count)
                context.fill(Path(ellipseIn: rect), with: .color(isFilled ? foreground : track))
            }
        }
        .accessibilityHidden(true)
    }
}

struct MonoSoundCenterEQChart: View {
    let accent: Color
    let gains: [Float]
    let mode: GraphicEQMode
    @Binding var selectedBand: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var normalizedGains: [Float] { mode.normalizedGains(gains) }
    private var band: Int { min(max(0, selectedBand ?? mode.bandCount / 2), mode.bandCount - 1) }
    private var bandValue: String {
        let frequency = mode.centerFrequencies[band]
        let frequencyText = frequency >= 1_000
            ? "\((frequency / 1_000).formatted(.number.precision(.fractionLength(0...2)))) kHz"
            : "\(frequency.formatted(.number.precision(.fractionLength(0...1)))) Hz"
        return "\(frequencyText) · \(normalizedGains[band].formatted(.number.precision(.fractionLength(1)))) dB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if selectedBand != nil {
                    Text(bandValue)
                        .foregroundStyle(accent)
                } else {
                    Text(mode == .thirtyTwoBand ? String(localized: "eq_thirty_two_band") : String(localized: "eq_ten_band"))
                        .foregroundStyle(MonoSoundCenterStyle.secondary)
                }
                Spacer(minLength: 4)
                Text("dB")
                    .foregroundStyle(MonoSoundCenterStyle.secondary)
            }
            .font(.caption)
            .monospacedDigit()
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                GeometryReader { proxy in
                    Canvas { context, size in
                        drawChart(context: &context, size: size)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            selectBand(at: value.location.x, width: proxy.size.width)
                        }
                    )
                }
                VStack {
                    Text("+12")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("−12")
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(MonoSoundCenterStyle.secondary)
                .accessibilityHidden(true)
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 120)

            HStack {
                Text("\(mode.frequencyLabels.first ?? "") Hz")
                Spacer(minLength: 8)
                Text("\((mode.centerFrequencies.last ?? 0) / 1_000, format: .number.precision(.fractionLength(0...1))) kHz")
            }
            .font(.caption2)
            .foregroundStyle(MonoSoundCenterStyle.secondary)
            .padding(.trailing, 28)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "mono_audio_eq_curve"))
        .accessibilityValue(bandValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectedBand = min(mode.bandCount - 1, band + 1)
            case .decrement: selectedBand = max(0, band - 1)
            @unknown default: break
            }
        }
        .onChange(of: mode) { _, _ in selectedBand = nil }
    }

    private func selectBand(at x: CGFloat, width: CGFloat) {
        let fraction = min(1, max(0, (x - 4) / max(1, width - 8)))
        selectedBand = Int((fraction * CGFloat(mode.bandCount - 1)).rounded())
    }

    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 4
        let width = max(1, size.width - inset * 2)
        let height = max(1, size.height - inset * 2)
        var grid = Path()
        for index in 0...4 {
            let x = inset + width * CGFloat(index) / 4
            grid.move(to: CGPoint(x: x, y: inset))
            grid.addLine(to: CGPoint(x: x, y: inset + height))
            let y = inset + height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: inset, y: y))
            grid.addLine(to: CGPoint(x: inset + width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.09)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

        let points = normalizedGains.enumerated().map { index, gain in
            CGPoint(
                x: inset + width * CGFloat(index) / CGFloat(mode.bandCount - 1),
                y: inset + height * (0.5 - CGFloat(min(12, max(-12, gain))) / 24)
            )
        }
        guard let first = points.first else { return }
        var curve = Path()
        curve.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let point = points[index]
            let midX = (previous.x + point.x) / 2
            curve.addCurve(
                to: point,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: point.y)
            )
        }
        context.stroke(curve, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        for (index, point) in points.enumerated() {
            let isSelected = selectedBand == index
            let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            context.fill(dot, with: .color(isSelected ? accent : MonoSoundCenterStyle.surface))
            context.stroke(dot, with: .color(isSelected ? accent : .white.opacity(0.7)), lineWidth: 1)
        }
        if selectedBand != nil {
            let point = points[band]
            var guide = Path()
            guide.move(to: CGPoint(x: point.x, y: inset))
            guide.addLine(to: CGPoint(x: point.x, y: inset + height))
            context.stroke(guide, with: .color(accent.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
    }
}
