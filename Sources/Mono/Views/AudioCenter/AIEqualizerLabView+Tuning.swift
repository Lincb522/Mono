import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
    var immersiveTuningStage: AnyView {
        AnyView(
            VStack(spacing: 0) {
                Group {
                    if let proposal = agent.proposal,
                       usesResonanceProposalLayout(proposal),
                       !agent.phase.isWorking, processPresentation == nil {
                        resonanceTuningStageHeader(proposal)
                    } else {
                        HStack(spacing: 10) {
                            tuningStageIndicator

                            VStack(alignment: .leading, spacing: 3) {
                                Text(tuningStageTitle)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(tuningStageDetail)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            tuningStageProgress
                        }
                    }
                }
                .padding(.horizontal, centerLayout.isCompactWidth ? 12 : 16)
                .padding(.top, centerLayout.isCompactHeight ? 12 : 16)

                tuningStageVisualization
                    .frame(height: centerLayout.isCompactHeight ? 132 : 172)
                    .padding(.horizontal, centerLayout.isCompactWidth ? 12 : 16)
                    .padding(.top, centerLayout.isCompactHeight ? 9 : 14)

                if let presentation = processPresentation {
                    AIEqualizerPhaseRail(
                        currentStep: presentation.currentStep,
                        accent: accent
                    )
                    .padding(.horizontal, centerLayout.isCompactWidth ? 12 : 16)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                divider
                    .padding(.top, 14)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "eq_current_device"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))

                        Text(tuningStageSummary)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)
                    analysisActionButton
                }
                .padding(centerLayout.isCompactHeight ? 12 : 16)
            }
            .background(tuningStageBackground)
        )
    }

    func resonanceTuningStageHeader(_ proposal: AIEqualizerProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                tuningStageIndicator

                Text(tuningStageTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(tuningStageDetail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(proposal.confidenceDisplayText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var tuningStageVisualization: AnyView {
        if let presentation = processPresentation {
            return AnyView(
                AIEqualizerProcessVisualizer(
                    state: presentation.state,
                    mode: agent.measuredFeatures?.graphicEQMode ?? eqManager.graphicEQMode,
                    accent: accent,
                    measuredBands: agent.measuredFeatures?.bandEnergyDB ?? []
                )
                .accessibilityHidden(true)
            )
        }

        let proposal = agent.proposal
        return AnyView(
            AIEqualizerCurveView(
                gains: proposal?.gains ?? eqManager.customGains,
                mode: proposal?.graphicEQMode ?? eqManager.graphicEQMode,
                accent: accent
            )
            .padding(.vertical, 4)
            .accessibilityHidden(true)
        )
    }

    @ViewBuilder
    var tuningStageProgress: some View {
        if let startedAt = agent.tuningStartedAt, let presentation = processPresentation {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let progress = presentation.state.progress(at: context.date)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(compactElapsed(since: startedAt, now: context.date))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
        } else if let proposal = agent.proposal {
            Text(proposal.confidenceDisplayText)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    var tuningStageTitle: String {
        processPresentation?.title
            ?? agent.proposal?.profileName
            ?? statusText
    }

    var tuningStageDetail: String {
        if let proposal = agent.proposal, !agent.phase.isWorking {
            let summary = proposal.profileSpecificSummary.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !summary.isEmpty {
                return summary
            }
            return proposal.graphicEQMode == .thirtyTwoBand
                ? String(localized: "eq_thirty_two_band")
                : String(localized: "eq_ten_band")
        }
        return agent.measuredFeatures?.outputDevice
            ?? EQManager.shared.currentOutputKind.title
    }

    var tuningStageSummary: String {
        let output = agent.measuredFeatures?.outputDevice
            ?? eqManager.currentOutputKind.title
        let mode = (agent.proposal?.graphicEQMode ?? eqManager.graphicEQMode) == .thirtyTwoBand
            ? String(localized: "eq_thirty_two_band")
            : String(localized: "eq_ten_band")
        return "\(output) · \(mode)"
    }

    @ViewBuilder
    var tuningStageIndicator: some View {
        if agent.phase.isWorking {
            AIEqualizerActivityDot(accent: accent)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .frame(width: 12, height: 12)
        }
    }

    var tuningStageBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.26))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
    }

    func workspaceEmptyState(
        icon: MonoIcon.IconType,
        title: String
    ) -> some View {
        VStack(spacing: 12) {
            MonoIcon(
                icon: icon,
                size: 24,
                color: accent
            )
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.055))
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            )

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(
            maxWidth: .infinity,
            minHeight: centerLayout.isCompactHeight ? 190 : 260
        )
    }

    var trackCard: some View {
        Group {
            if let song = player.currentSong {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: song.coverUrl?.sized(240), width: 66, height: 66) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(MonoIcon(icon: .musicNote, size: 22, color: .white.opacity(0.45)))
                    }
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                accent.opacity(agent.phase.isWorking ? 0.7 : 0.2),
                                lineWidth: agent.phase.isWorking ? 1.5 : 1
                            )
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "ai_lab_title"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .lineLimit(1)

                        Text(song.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(song.artistName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 14) {
                    MonoIcon(icon: .musicNote, size: 22, color: .white.opacity(0.42))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                    Text(String(localized: "ai_error_no_song"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    var analysisActionButton: some View {
        Button(action: primaryAnalysisAction) {
            ZStack {
                Circle().fill(accent.opacity(0.78))

                if let presentation = processPresentation {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        progressRing(
                            presentation.state.progress(at: context.date)
                        )
                    }
                }

                MonoIcon(
                    icon: agent.phase.isWorking ? .close : .sparkle,
                    size: 16,
                    color: accentForeground
                )
                .monoIconArtwork(
                    (agent.phase.isWorking
                        ? MonoGlyphSemantic.agentStopAnalysis
                        : MonoGlyphSemantic.agentAnalyze).rawValue
                )
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(MonoBouncingButtonStyle())
        .accessibilityLabel(
            agent.phase.isWorking
                ? String(localized: "ai_lab_cancel")
                : String(localized: "ai_lab_analyze")
        )
    }

    func progressRing(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(accentForeground.opacity(0.18), lineWidth: 1.5)
                .padding(4)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(
                    accentForeground,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.16),
                    value: progress
                )
        }
    }

    var tuningControlSection: AnyView {
        AnyView(
            VStack(spacing: 0) {
                automationToggleRow(
                    title: String(localized: "ai_lab_auto_configure"),
                    isOn: Binding(
                        get: { agent.isAutomaticTuningActive },
                        set: { agent.automaticConfigurationEnabled = $0 }
                    )
                )
                .disabled(!tuningServiceStore.settings.isEnabled)

                divider

                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                        isTuningConfigurationExpanded.toggle()
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 12) {
                        Text(String(localized: "ai_tuning_settings"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 8)

                        Text("\(agent.tuningProfile.title) · \(agent.tuningIntensity.title) · \(agent.samplingMode.title)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        MonoIcon(
                            icon: .chevronDown,
                            size: 11,
                            color: isTuningConfigurationExpanded ? accent : .white.opacity(0.38),
                            lineWidth: 1.8
                        )
                        .rotationEffect(.degrees(isTuningConfigurationExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTuningConfigurationExpanded {
                    divider

                    automationToggleRow(
                        title: String(localized: "ai_learning_enabled"),
                        isOn: $agent.adaptiveLearningEnabled
                    )

                    if agent.learningEvidenceCount > 0 {
                        divider

                        Button {
                            isShowingClearLearningConfirmation = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(
                                    String(
                                        format: String(localized: "ai_learning_evidence_count"),
                                        agent.learningEvidenceCount
                                    )
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.68))

                                Spacer(minLength: 8)

                                MonoIcon(icon: .trash, size: 13, color: .white.opacity(0.42))
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    divider

                    automationToggleRow(
                        title: String(localized: "ai_player_status_toggle"),
                        isOn: $agent.showsPlayerTuningStatus
                    )

                    divider

                    tuningParameterControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(cardBackground)
        )
    }

    var tuningParameterControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "ai_tuning_profile"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 7) {
                ForEach(AIEqualizerTuningProfile.allCases) { profile in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            agent.selectTuningProfile(profile)
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(profile.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(agent.tuningProfile == profile ? accentForeground : .white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                if agent.tuningProfile == profile {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(accent.opacity(0.78))
                                        .matchedGeometryEffect(
                                            id: "ai-tuning-profile-selection",
                                            in: controlSelectionNamespace
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.phase.isWorking)
                }
            }

            divider

            Text(String(localized: "ai_tuning_intensity"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 7) {
                ForEach(AIEqualizerTuningIntensity.allCases) { intensity in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            agent.tuningIntensity = intensity
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(intensity.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(agent.tuningIntensity == intensity ? accentForeground : .white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                if agent.tuningIntensity == intensity {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(accent.opacity(0.78))
                                        .matchedGeometryEffect(
                                            id: "ai-tuning-intensity-selection",
                                            in: controlSelectionNamespace
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.phase.isWorking)
                }
            }

            divider

            Text(String(localized: "ai_sampling_mode"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 7) {
                ForEach(AIEqualizerSamplingMode.allCases) { mode in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            agent.samplingMode = mode
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(agent.samplingMode == mode ? accentForeground : .white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                if agent.samplingMode == mode {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(accent.opacity(0.78))
                                        .matchedGeometryEffect(
                                            id: "ai-sampling-mode-selection",
                                            in: controlSelectionNamespace
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.045))
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.phase.isWorking)
                }
            }

            if agent.samplingMode == .custom {
                HStack(spacing: 12) {
                    Slider(value: $agent.customSamplingDuration, in: 10...120, step: 1)
                        .tint(accent)
                        .disabled(agent.phase.isWorking)

                    Text(String(format: String(localized: "ai_sampling_seconds"), Int(agent.customSamplingDuration)))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 54, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
    }

    func automationToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 10)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var analysisNotice: some View {
        if tuningServiceStore.settings.isEnabled {
            HStack(alignment: .top, spacing: 10) {
                MonoIcon(icon: .infoCircle, size: 14, color: accent)
                    .frame(width: 18, height: 18)

                Text(tuningServiceStore.settings.service.availabilityNotice)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
        }
    }

    func progressSection(
        state: AIEqualizerProcessVisualizer.State,
        title: String,
        currentStep: Int
    ) -> AnyView {
        return erasedSection(
            title: String(localized: "ai_lab_analysis_progress"),
            content: AnyView(
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    AIEqualizerActivityDot(accent: accent)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    if let startedAt = agent.tuningStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let progress = state.progress(at: context.date)
                            Text(
                                String(
                                    format: String(localized: "ai_tuning_elapsed_format"),
                                    compactElapsed(since: startedAt, now: context.date)
                                ) + " · \(Int(progress * 100))%"
                            )
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .contentTransition(.numericText())
                        }
                    } else {
                        Text("\(Int(state.progress(at: .now) * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                AIEqualizerProcessVisualizer(
                    state: state,
                    mode: agent.measuredFeatures?.graphicEQMode ?? eqManager.graphicEQMode,
                    accent: accent,
                    measuredBands: agent.measuredFeatures?.bandEnergyDB ?? []
                )
                .frame(height: 126)
                .accessibilityHidden(true)

                AIEqualizerPhaseRail(
                    currentStep: currentStep,
                    accent: accent
                )
            }
            .padding(16)
            .background(cardBackground)
            )
        )
    }

}
