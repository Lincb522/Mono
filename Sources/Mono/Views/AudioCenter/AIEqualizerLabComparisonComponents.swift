import SwiftUI
import FFmpegSwiftSDK

enum AIEqualizerWorkspace: String, CaseIterable, Identifiable {
    case tuning
    case measurement
    case result
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tuning: return String(localized: "ai_lab_workspace_tuning")
        case .measurement: return String(localized: "ai_lab_workspace_measurement")
        case .result: return String(localized: "ai_lab_workspace_result")
        case .history: return String(localized: "ai_lab_workspace_history")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .tuning: return .equalizer
        case .measurement: return .waveform
        case .result: return .sparkle
        case .history: return .history
        }
    }

    var monoGlyphSemantic: MonoGlyphSemantic {
        switch self {
        case .tuning: return .aiTuningWorkspace
        case .measurement: return .aiMeasurementWorkspace
        case .result: return .aiResultWorkspace
        case .history: return .aiHistoryWorkspace
        }
    }
}

struct AIEqualizerComparisonChange: Identifiable {
    let id: String
    let title: String
    let previousValue: String
    let currentValue: String
    let deltaValue: String
    let delta: Float
}

struct AIEqualizerTuningReference: Identifiable {
    let id: String
    let title: String
    let value: String
}

struct AIEqualizerProposalComparisonView: View {
    let current: AIEqualizerProposal?
    let historical: AIEqualizerSavedProposal
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.072)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(historical.proposal.resolvedTuningProfile.title)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(accent)
                        Text(historical.proposal.profileName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(localized: "ai_lab_compare_subtitle"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let current, current.id != historical.id {
                        comparisonHeader(current: current, previous: historical.proposal)
                        comparisonMetrics(current: current, previous: historical.proposal)
                        if current.graphicEQMode == historical.proposal.graphicEQMode {
                            bandComparison(current: current, previous: historical.proposal)
                        }
                    } else {
                        HStack(spacing: 10) {
                            MonoIcon(icon: .infoCircle, size: 16, color: accent)
                            Text(String(localized: "ai_lab_no_comparison"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(cardBackground)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .iPadContentWidth(720)
            }
        }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
    }

    private func comparisonHeader(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> some View {
        HStack(spacing: 8) {
            comparisonLegend(
                title: String(localized: "ai_lab_current_result"),
                profile: current.resolvedTuningProfile.title,
                value: current.profileName,
                color: accent
            )
            comparisonLegend(
                title: String(localized: "ai_lab_previous_result"),
                profile: previous.resolvedTuningProfile.title,
                value: previous.profileName,
                color: .white.opacity(0.46)
            )
        }
    }

    private func comparisonLegend(
        title: String,
        profile: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(profile)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private func comparisonMetrics(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> some View {
        VStack(spacing: 0) {
            comparisonMetric(
                String(localized: "ai_lab_preamp"),
                current: current.preampDB,
                previous: previous.preampDB,
                suffix: " dB"
            )
            divider
            comparisonMetric(
                String(localized: "eq_bass"),
                current: current.tone.bassGain,
                previous: previous.tone.bassGain,
                suffix: " dB"
            )
            divider
            comparisonMetric(
                String(localized: "eq_treble"),
                current: current.tone.trebleGain,
                previous: previous.tone.trebleGain,
                suffix: " dB"
            )
            divider
            comparisonMetric(
                String(localized: "eq_surround"),
                current: current.spatial.surroundLevel * 100,
                previous: previous.spatial.surroundLevel * 100,
                suffix: "%"
            )
            divider
            comparisonMetric(
                String(localized: "eq_reverb"),
                current: current.spatial.reverbLevel * 100,
                previous: previous.spatial.reverbLevel * 100,
                suffix: "%"
            )
            divider
            comparisonMetric(
                String(localized: "ai_lab_stereo_width"),
                current: current.spatial.stereoWidth,
                previous: previous.spatial.stereoWidth,
                suffix: "x"
            )
            divider
            comparisonMetric(
                String(localized: "eq_processing_intensity"),
                current: current.professional.processingIntensity * 100,
                previous: previous.professional.processingIntensity * 100,
                suffix: "%"
            )
        }
        .padding(14)
        .background(cardBackground)
    }

    private func comparisonMetric(
        _ title: String,
        current: Float,
        previous: Float,
        suffix: String
    ) -> some View {
        let delta = current - previous
        return HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 92, alignment: .leading)
            Text(String(format: "%.1f%@", current, suffix))
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%@", previous, suffix))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%+.1f", delta))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(delta >= 0 ? accent : .white.opacity(0.46))
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minHeight: 36)
    }

    private func bandComparison(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> some View {
        let frequencies = current.graphicEQMode.centerFrequencies
        let count = min(frequencies.count, min(current.gains.count, previous.gains.count))

        return VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ai_lab_eq_band_comparison"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(String(localized: "ai_lab_frequency"))
                            .frame(width: 74, alignment: .leading)
                        Text(String(localized: "ai_lab_current_short"))
                            .frame(width: 78, alignment: .trailing)
                        Text(String(localized: "ai_lab_previous_short"))
                            .frame(width: 78, alignment: .trailing)
                        Text(String(localized: "ai_lab_difference_short"))
                            .frame(width: 78, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 8)

                    ForEach(0..<count, id: \.self) { index in
                        let delta = current.gains[index] - previous.gains[index]
                        HStack(spacing: 0) {
                            Text(frequencyText(frequencies[index]))
                                .frame(width: 74, alignment: .leading)
                            Text(String(format: "%+.1f dB", current.gains[index]))
                                .foregroundStyle(accent)
                                .frame(width: 78, alignment: .trailing)
                            Text(String(format: "%+.1f dB", previous.gains[index]))
                                .foregroundStyle(.white.opacity(0.56))
                                .frame(width: 78, alignment: .trailing)
                            Text(String(format: "%+.1f", delta))
                                .foregroundStyle(delta >= 0 ? accent : .white.opacity(0.46))
                                .frame(width: 78, alignment: .trailing)
                        }
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .frame(height: 27)
                    }
                }
                .frame(minWidth: 308, alignment: .leading)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }

    private func frequencyText(_ frequency: Float) -> String {
        frequency >= 1_000
            ? String(format: "%.1f kHz", frequency / 1_000)
            : String(format: "%.0f Hz", frequency)
    }
}
