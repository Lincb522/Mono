import SwiftUI
import FFmpegSwiftSDK

enum AIEqualizerMeasurementGroup: String, Hashable {
    case music
    case loudness
    case spatial
    case sample

    var title: String {
        switch self {
        case .music: return String(localized: "ai_lab_measurement_music")
        case .loudness: return String(localized: "ai_lab_measurement_loudness")
        case .spatial: return String(localized: "ai_lab_measurement_spatial")
        case .sample: return String(localized: "ai_lab_measurement_sample")
        }
    }
}

struct AIEqualizerActivityDot: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            AppFrameRate.throttledTimeline(
                maximumFramesPerSecond: 12,
                paused: reduceMotion
            )
        ) { timeline in
            let pulse: CGFloat = reduceMotion
                ? 0.5
                : CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 3.2) + 1) * 0.5)

            ZStack {
                Circle()
                    .fill(accent.opacity(0.16 + 0.12 * Double(pulse)))
                    .scaleEffect(1 + 0.7 * pulse)
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

struct AIEqualizerPhaseRail: View {
    let currentStep: Int
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var labels: [String] {
        [
            String(localized: "ai_tuning_sampling_time"),
            String(localized: "ai_tuning_generation_time"),
            String(localized: "ai_tuning_applying_time")
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.horizontal, 48)
                .offset(y: 5.5)

            HStack(spacing: 8) {
                ForEach(labels.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(index <= currentStep ? accent : Color.white.opacity(0.16))
                            .frame(
                                width: index == currentStep ? 11 : 9,
                                height: index == currentStep ? 11 : 9
                            )
                            .overlay {
                                if index == currentStep {
                                    Circle().stroke(accent.opacity(0.26), lineWidth: 4)
                                }
                            }

                        Text(labels[index])
                            .font(.system(size: 10, weight: index == currentStep ? .bold : .semibold))
                            .foregroundStyle(index <= currentStep ? .white.opacity(0.82) : .white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: currentStep
        )
        .accessibilityElement(children: .combine)
    }
}

struct MelodyContourView: View {
    let frequencies: [Float]
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let notes = frequencies.compactMap { frequency -> CGFloat? in
                guard frequency.isFinite, frequency > 0 else { return nil }
                return CGFloat(69 + 12 * log2f(frequency / 440))
            }
            guard notes.count >= 2 else { return }

            let lower = notes.min() ?? 0
            let upper = notes.max() ?? lower
            let span = max(4, upper - lower)
            let horizontalInset: CGFloat = 3
            let verticalInset: CGFloat = 5
            let width = max(1, size.width - horizontalInset * 2)
            let height = max(1, size.height - verticalInset * 2)

            for index in 0..<3 {
                let y = verticalInset + height * CGFloat(index) / 2
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: horizontalInset, y: y))
                gridLine.addLine(to: CGPoint(x: size.width - horizontalInset, y: y))
                context.stroke(gridLine, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }

            var contour = Path()
            for (index, note) in notes.enumerated() {
                let x = horizontalInset + width * CGFloat(index) / CGFloat(max(1, notes.count - 1))
                let normalized = (note - lower) / span
                let y = verticalInset + height * (1 - normalized)
                if index == 0 {
                    contour.move(to: CGPoint(x: x, y: y))
                } else {
                    contour.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                contour,
                with: .color(accent.opacity(0.86)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct AIEqualizerProcessVisualizer: View {
    enum State {
        case sampling(progress: Double, stage: AIEqualizerSamplingStage)
        case generating(stage: AIEqualizerGenerationStage, startedAt: Date?)
        case applying

        func progress(at date: Date) -> Double {
            switch self {
            case let .sampling(progress, _):
                return 0.04 + min(1, max(0, progress)) * 0.36
            case let .generating(stage, startedAt):
                let elapsed = max(
                    0,
                    startedAt.map { date.timeIntervalSince($0) } ?? 0
                )
                let advancement = 1 - exp(-elapsed / 42)
                let estimatedGenerationProgress = min(
                    0.88,
                    0.45 + advancement * 0.43
                )
                switch stage {
                case .preparingModel:
                    return 0.02
                case .preparing:
                    return elapsed > 1
                        ? estimatedGenerationProgress
                        : 0.42
                case .generating:
                    return estimatedGenerationProgress
                case .validating:
                    return 0.91
                case .finalizing:
                    return 0.96
                }
            case .applying:
                return 0.99
            }
        }

        var progress: Double { progress(at: .now) }

        var movement: Double {
            switch self {
            case let .sampling(_, stage):
                switch stage {
                case .preparing, .waitingForAudio: return 0.08
                case .collectingSpectrum: return 0.28
                case .measuringDynamics: return 0.2
                case .organizingFeatures: return 0.1
                case .finalizing: return 0.04
                }
            case let .generating(stage, _):
                switch stage {
                case .preparing, .preparingModel: return 0.08
                case .generating: return 0.15
                case .validating: return 0.06
                case .finalizing: return 0.025
                }
            case .applying:
                return 0.015
            }
        }

        var isGenerating: Bool {
            switch self {
            case .generating, .applying: return true
            case .sampling: return false
            }
        }
    }

    let state: State
    let mode: GraphicEQMode
    let accent: Color
    let measuredBands: [Float]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var performance = AriaPerformanceGovernor.shared

    private var animationFramesPerSecond: Int {
        switch performance.tier {
        case .high: return 18
        case .medium: return 10
        case .low: return 6
        }
    }

    var body: some View {
        TimelineView(
            AppFrameRate.throttledTimeline(
                maximumFramesPerSecond: animationFramesPerSecond,
                paused: reduceMotion
            )
        ) { timeline in
            let progress = state.progress(at: timeline.date)

            VStack(spacing: 12) {
                Canvas { context, size in
                    drawFrequencyRail(
                        in: &context,
                        size: size,
                        time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate,
                        progress: progress
                    )
                }

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(accent.opacity(0.88))
                        .scaleEffect(x: max(0.012, progress), y: 1, anchor: .leading)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.2),
                            value: progress
                        )
                }
                .frame(height: 2)
            }
        }
    }

    private func drawFrequencyRail(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        progress: Double
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let bandCount = mode.bandCount
        let divisor = max(1, bandCount - 1)
        let slotWidth = size.width / CGFloat(bandCount)
        let maximumBarWidth: CGFloat = mode == .tenBand ? 6 : 4
        let barWidth = min(maximumBarWidth, max(2, slotWidth * 0.38))
        let plotHeight = size.height - 8
        let baselineY = size.height - 4
        let scanPosition = reduceMotion
            ? progress
            : time.truncatingRemainder(dividingBy: 1.7) / 1.7

        for lineIndex in 0..<3 {
            let y = 4 + plotHeight * CGFloat(lineIndex) / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.white.opacity(lineIndex == 2 ? 0.08 : 0.045)), lineWidth: 1)
        }

        for index in 0..<bandCount {
            let position = Double(index) / Double(divisor)
            let height = plotHeight * CGFloat(
                bandHeight(index: index, divisor: divisor, time: time)
            )
            let x = slotWidth * (CGFloat(index) + 0.5)
            let isResolved = position <= progress
            let isScanning = abs(position - scanPosition) < 0.045
            let rect = CGRect(
                x: x - barWidth * 0.5,
                y: baselineY - height,
                width: barWidth,
                height: max(3, height)
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth * 0.5),
                with: .color(
                    isResolved
                        ? accent.opacity(isScanning ? 1 : 0.82)
                        : Color.white.opacity(isScanning ? 0.28 : 0.11)
                )
            )
        }

        let scanX = size.width * CGFloat(scanPosition)
        var scanLine = Path()
        scanLine.move(to: CGPoint(x: scanX, y: 2))
        scanLine.addLine(to: CGPoint(x: scanX, y: baselineY))
        context.stroke(scanLine, with: .color(accent.opacity(0.28)), lineWidth: 1)
    }

    private func bandHeight(index: Int, divisor: Int, time: TimeInterval) -> Double {
        let position = Double(index) / Double(divisor)
        let measured = normalizedMeasuredHeight(at: index, divisor: divisor)
        let envelope = 0.55 + 0.45 * sin(position * .pi)
        let base: Double
        if state.isGenerating, let measured {
            base = measured
        } else {
            base = 0.2 + 0.34 * envelope + 0.08 * sin(Double(index) * 1.37)
        }
        let motion = reduceMotion
            ? 0
            : state.movement * sin(time * 1.7 + Double(index) * 0.74)
        return min(0.96, max(0.08, base + motion))
    }

    private func normalizedMeasuredHeight(at index: Int, divisor: Int) -> Double? {
        guard !measuredBands.isEmpty else { return nil }
        let sourceIndex = Int(
            (Double(index) / Double(divisor) * Double(max(0, measuredBands.count - 1))).rounded()
        )
        guard measuredBands.indices.contains(sourceIndex) else { return nil }
        return min(0.92, max(0.12, Double((measuredBands[sourceIndex] + 60) / 60)))
    }
}

func normalizedAIEqualizerAccent(_ color: Color) -> Color {
    let uiColor = UIColor(color)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 1

    guard uiColor.getHue(
        &hue,
        saturation: &saturation,
        brightness: &brightness,
        alpha: &alpha
    ) else {
        return Color(red: 0.53, green: 0.62, blue: 1)
    }

    let adjustedSaturation = saturation < 0.08 ? saturation : min(saturation, 0.82)
    let candidate = Color(
        hue: Double(hue),
        saturation: Double(adjustedSaturation),
        brightness: Double(max(brightness, 0.82)),
        opacity: Double(alpha)
    )
    let background = Color(red: 0.055, green: 0.055, blue: 0.072)

    guard ThemeColorCustomization.contrastRatio(between: candidate, and: background) < 4.5 else {
        return candidate
    }

    return Color(
        hue: Double(hue),
        saturation: Double(saturation < 0.08 ? saturation : min(saturation, 0.56)),
        brightness: 0.96,
        opacity: Double(alpha)
    )
}
