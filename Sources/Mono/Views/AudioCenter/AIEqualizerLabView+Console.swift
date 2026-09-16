import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
    private var consoleFeatures: AIEqualizerAudioFeatures? {
        guard let song = player.currentSong, let features = agent.measuredFeatures,
              features.songID == song.id, features.source == song.musicSource.rawValue else { return nil }
        return features
    }

    var immersiveTuningStage: AnyView {
        AnyView(
            VStack(spacing: 10) {
                MonoSoundCenterSplitPanel {
                    VStack(spacing: 10) {
                        measurementConsole
                        energyConsole
                    }
                } trailing: {
                    if let presentation = processPresentation {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let progress = presentation.state.progress(at: context.date)
                            tuningFocusCard(
                                value: Int(progress * 100).formatted(),
                                unit: "%",
                                fraction: progress,
                                elapsed: agent.tuningStartedAt.map { compactElapsed(since: $0, now: context.date) }
                            )
                        }
                    } else {
                        tuningFocusCard(
                            value: (agent.proposal?.graphicEQMode ?? eqManager.graphicEQMode).bandCount.formatted(),
                            unit: String(localized: "mono_audio_bands"),
                            fraction: agent.proposal == nil ? nil : 1
                        )
                    }
                }
                tuningCurveConsole
            }
        )
    }

    private var measurementConsole: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoSoundCenterMetric(
                title: String(localized: "mono_suite_metric_tempo"),
                value: consoleFeatures.flatMap { $0.estimatedBPM.isFinite && $0.estimatedBPM > 0 ? $0.estimatedBPM.formatted(.number.precision(.fractionLength(0))) : nil } ?? "—",
                unit: "BPM"
            )
            Divider().overlay(Color.white.opacity(0.08))
            MonoSoundCenterMetric(
                title: String(localized: "mono_suite_metric_loudness"),
                value: consoleFeatures.flatMap { $0.integratedLUFS.isFinite ? $0.integratedLUFS.formatted(.number.precision(.fractionLength(1))) : nil } ?? "—",
                unit: "LUFS"
            )
        }
        .padding(12)
        .background(MonoSoundCenterStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var energyConsole: some View {
        let arrangement = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
        return arrangement {
            energyDial(String(localized: "mono_audio_low"), ratio: consoleFeatures?.lowEnergyRatio)
            energyDial(String(localized: "mono_audio_mid"), ratio: consoleFeatures?.midEnergyRatio)
            energyDial(String(localized: "mono_audio_high"), ratio: consoleFeatures?.highEnergyRatio)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MonoSoundCenterStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func energyDial(_ title: String, ratio: Float?) -> some View {
        let fraction = ratio.flatMap { $0.isFinite ? Double(min(1, max(0, $0))) : nil }
        return MonoSoundCenterDial(
            accent: accent,
            title: title,
            value: fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
            fraction: fraction,
            icon: .waveform
        )
    }

    private var analysisActionTitle: String {
        if agent.phase.isWorking { return String(localized: "ai_lab_cancel") }
        let hasCurrentProposal = player.currentSong.map { song in
            agent.proposal?.songID == song.id
        } ?? false
        return hasCurrentProposal || eqManager.isAIManagedPresetActive
            ? String(localized: "ai_lab_retune")
            : String(localized: "ai_lab_analyze")
    }

    private func tuningFocusCard(value: String, unit: String, fraction: Double?, elapsed: String? = nil) -> some View {
        MonoSoundCenterFocusCard(
            accent: accent,
            foreground: accentForeground,
            value: value,
            unit: unit,
            title: tuningStageTitle,
            detail: elapsed.map { "\(agent.tuningProfile.title) · \($0)" } ?? agent.tuningProfile.title,
            fraction: fraction
        ) {
            Button(action: primaryAnalysisAction) {
                Text(analysisActionTitle)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(accent)
                    .background(accentForeground, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(player.currentSong == nil && !agent.phase.isWorking)
            .opacity(player.currentSong == nil && !agent.phase.isWorking ? 0.5 : 1)
        }
    }

    private var tuningCurveConsole: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "mono_audio_eq_curve"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(String(localized: agent.proposal == nil ? "mono_audio_current_eq" : "mono_audio_ai_curve"))
                    .font(.caption)
                    .foregroundStyle(accent)
            }
            if let presentation = processPresentation {
                AIEqualizerProcessVisualizer(
                    state: presentation.state,
                    mode: consoleFeatures?.graphicEQMode ?? eqManager.graphicEQMode,
                    accent: accent,
                    measuredBands: consoleFeatures?.bandEnergyDB ?? []
                )
                .frame(height: 140)
                .accessibilityHidden(true)
                AIEqualizerPhaseRail(currentStep: presentation.currentStep, accent: accent)
            } else {
                MonoSoundCenterEQChart(
                    accent: accent,
                    gains: agent.proposal?.gains ?? currentConsoleGains,
                    mode: agent.proposal?.graphicEQMode ?? eqManager.graphicEQMode,
                    selectedBand: $selectedCurveBand
                )
                if let proposal = agent.proposal {
                    Text(tuningStageDetail)
                        .font(.caption)
                        .foregroundStyle(MonoSoundCenterStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(proposal.confidenceDisplayText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(accent)
                }
            }
            HStack(spacing: 8) {
                MonoIcon(icon: .headphones, size: 14, color: MonoSoundCenterStyle.secondary)
                Text(eqManager.currentOutputName.isEmpty ? eqManager.currentOutputKind.title : eqManager.currentOutputName)
                    .font(.caption)
                    .foregroundStyle(MonoSoundCenterStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(MonoSoundCenterStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var currentConsoleGains: [Float] {
        guard eqManager.isEnabled, !eqManager.isAuditioningReference else {
            return Array(repeating: 0, count: eqManager.graphicEQMode.bandCount)
        }
        if let preset = eqManager.currentPreset, preset.id != "custom" {
            return preset.gains(in: eqManager.graphicEQMode)
        }
        return eqManager.customGains
    }
}
