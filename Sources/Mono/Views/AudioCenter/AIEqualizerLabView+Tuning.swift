import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
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
