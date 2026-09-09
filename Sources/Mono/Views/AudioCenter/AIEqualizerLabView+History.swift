import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
    func savedProposalRow(_ saved: AIEqualizerSavedProposal) -> some View {
        let isCurrent = agent.proposal?.id == saved.id
        let canApply = saved.proposal.graphicEQMode == eqManager.graphicEQMode
            && saved.outputIdentity == currentOutputIdentity

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(saved.proposal.resolvedTuningProfile.title)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(accent)
                    Text(saved.proposal.profileName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if isCurrent {
                        Text(String(localized: "ai_lab_current_result"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(accent.opacity(0.15)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(saved.proposal.createdAt, style: .date)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(saved.proposal.profileSpecificSummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            tuningReferenceRows(for: saved.proposal, compact: true)

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    savedMetadataPill(saved.proposal.graphicEQMode == .thirtyTwoBand
                                      ? String(localized: "eq_thirty_two_band")
                                      : String(localized: "eq_ten_band"))
                    savedMetadataPill(saved.outputIdentity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    agent.applySavedProposal(saved)
                } label: {
                    MonoIcon(icon: .play, size: 13, color: canApply ? .white.opacity(0.86) : .white.opacity(0.28))
                        .monoIconArtwork(MonoGlyphSemantic.agentApplySavedProposal.rawValue)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(!canApply)
                .accessibilityLabel(String(localized: "ai_lab_apply_saved"))

                Button(role: .destructive) {
                    agent.deleteSavedProposal(saved)
                } label: {
                    MonoIcon(icon: .trash, size: 13, color: .red.opacity(0.84))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "ai_lab_delete"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? accent.opacity(0.1) : Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCurrent ? accent.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 1)
                }
        )
    }

    func savedMetadataPill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.52))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Capsule().fill(Color.white.opacity(0.055)))
    }

    @ViewBuilder
    func tuningReferenceRows(
        for proposal: AIEqualizerProposal,
        compact: Bool = false
    ) -> some View {
        let references = tuningReferences(for: proposal)
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                ForEach(references) { reference in
                    HStack(alignment: .top, spacing: 7) {
                        Text(reference.title)
                            .font(.system(size: compact ? 9.5 : 10, weight: .bold))
                            .foregroundStyle(accent.opacity(compact ? 0.72 : 0.86))
                            .fixedSize(horizontal: true, vertical: false)
                        Text(reference.value)
                            .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                            .foregroundStyle(.white.opacity(compact ? 0.48 : 0.54))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, compact ? 1 : 3)
        }
    }

    func tuningReferences(for proposal: AIEqualizerProposal) -> [AIEqualizerTuningReference] {
        var references: [AIEqualizerTuningReference] = []
        if let artist = proposal.artistStyleReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !artist.isEmpty {
            references.append(
                AIEqualizerTuningReference(
                    id: "artist",
                    title: String(localized: "ai_lab_artist_reference"),
                    value: artist
                )
            )
        }
        if let vocal = proposal.vocalCharacterReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vocal.isEmpty {
            references.append(
                AIEqualizerTuningReference(
                    id: "vocal",
                    title: String(localized: "ai_lab_vocal_reference"),
                    value: vocal
                )
            )
        }
        return references
    }

    func erasedProposalDisclosure(
        title: String,
        isExpanded: Binding<Bool>,
        content: @escaping () -> AnyView
    ) -> AnyView {
        AnyView(VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    isExpanded.wrappedValue.toggle()
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))

                    Spacer()

                    MonoIcon(
                        icon: .chevronDown,
                        size: 11,
                        color: isExpanded.wrappedValue ? accent : .white.opacity(0.38),
                        lineWidth: 1.8
                    )
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isExpanded.wrappedValue
                    ? String(localized: "ai_lab_measurement_expanded")
                    : String(localized: "ai_lab_measurement_collapsed")
            )

            if isExpanded.wrappedValue {
                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.22),
            value: isExpanded.wrappedValue
        )
        )
    }

    func resultCell(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.045)))
    }

    func tuningTimingRow(_ timing: AIEqualizerTiming) -> some View {
        HStack(spacing: 0) {
            tuningTimingMetric(
                String(localized: "ai_tuning_sampling_time"),
                value: timing.samplingReused == true
                    ? String(localized: "ai_tuning_measurement_reused")
                    : tuningDurationText(timing.sampling)
            )
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 24)
            tuningTimingMetric(
                String(localized: "ai_tuning_generation_time"),
                value: tuningDurationText(timing.generation)
            )
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 24)
            tuningTimingMetric(
                String(localized: "ai_tuning_applying_time"),
                value: tuningDurationText(timing.applying)
            )
        }
        .padding(.vertical, 2)
    }

    func tuningTimingMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    func headphoneEffectName(_ effects: MonoEffectTuningConfiguration) -> String {
        if effects.bs2bEnabled { return String(localized: "eq_bs2b") }
        if effects.crossfeedEnabled { return String(localized: "eq_crossfeed") }
        if effects.haasEnabled { return String(localized: "eq_haas") }
        return "—"
    }

    func stateRow(_ title: String, isOn: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
            Circle()
                .fill(isOn ? accent : Color.white.opacity(0.18))
                .frame(width: 7, height: 7)
        }
        .frame(height: 44)
    }

    func failureSection(_ message: String) -> AnyView {
        erasedSection(
            title: String(localized: "ai_lab_failed"),
            content: AnyView(
            HStack(alignment: .top, spacing: 12) {
                MonoIcon(icon: .warning, size: 17, color: .red.opacity(0.9))
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(cardBackground)
            )
        )
    }

    var statusLabel: some View {
        Text(statusText)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(statusColor.opacity(0.13)))
    }

    var statusText: String {
        switch agent.phase {
        case .sampling: return agent.samplingStage.title
        case .requesting: return agent.generationStage.title
        case .applying: return String(localized: "ai_lab_applying")
        case .ready:
            return agent.isCurrentProposalApplied
                ? String(localized: "ai_lab_applied")
                : String(localized: "ai_lab_ready")
        case .failed: return String(localized: "ai_lab_failed")
        case .idle: return String(localized: "ai_lab_not_analyzed")
        }
    }

    var statusColor: Color {
        switch agent.phase {
        case .failed: return .red.opacity(0.9)
        case .ready where agent.isCurrentProposalApplied: return .green.opacity(0.9)
        default: return accent
        }
    }

    var processPresentation: (
        state: AIEqualizerProcessVisualizer.State,
        title: String,
        currentStep: Int
    )? {
        switch agent.phase {
        case let .sampling(progress):
            return (
                .sampling(progress: progress, stage: agent.samplingStage),
                agent.samplingStage.title,
                0
            )
        case .requesting:
            return (
                .generating(
                    stage: agent.generationStage,
                    startedAt: agent.generationStartedAt
                ),
                agent.generationStage.title,
                1
            )
        case .applying:
            return (
                .applying,
                String(localized: "ai_lab_applying"),
                2
            )
        case .idle, .ready, .failed:
            return nil
        }
    }

    var serviceFooter: some View {
        NavigationLink {
            AITuningServiceSettingsView()
        } label: {
            VStack(spacing: 4) {
                Text(tuningServiceStore.settings.isEnabled
                     ? tuningServiceStore.settings.service.serviceCredit
                     : String(localized: "ai_tuning_service_disabled"))
                    .font(.caption2.weight(.medium))

                if tuningServiceStore.settings.isEnabled,
                   tuningServiceStore.settings.service == .resonance {
                    AIEqualizerResonanceVersionLabel()
                }
            }
            .foregroundStyle(.white.opacity(0.52))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "ai_tuning_service_title"))
    }

    var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    /// Heavy measurement content is intentionally erased before it is inserted
    /// into the page. Keeping its deeply nested disclosure/grid tree as one
    /// concrete SwiftUI type can overflow Swift's runtime metadata demangler on
    /// device when measured features first become available.
}

@MainActor
private struct AIEqualizerResonanceVersionLabel: View {
    @ObservedObject private var updates = AIResonanceUpdateStore.shared
    @ScaledMetric(relativeTo: .caption2) private var versionFontSize: CGFloat = 10

    var body: some View {
        if let model = updates.tuningModel {
            Text(String(
                format: String(localized: "ai_lab_service_version_format"),
                AudioTrainingModelPresentation.versionText(model.version)
            ))
                .font(.system(size: versionFontSize))
        }
    }
}
