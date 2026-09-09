import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
    func usesResonanceProposalLayout(_ proposal: AIEqualizerProposal) -> Bool {
        if let mode = proposal.skillCompliance?.executionMode {
            return mode == .trainedCoreMLModel
        }
        // Legacy local proposals predate execution metadata; remote model names
        // alone must not opt custom AI services into the Resonance layout.
        return proposal.provider == .appleIntelligence
            && (proposal.model.hasPrefix("mono-resonance-") || proposal.model.hasPrefix("mono-audio-"))
    }

    func resonanceProposalHeader(_ proposal: AIEqualizerProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(proposal.resolvedTuningProfile.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                Text(proposal.profileName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(proposal.profileSpecificSummary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            tuningReferenceRows(for: proposal)

            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.confidenceDisplayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)

                if let timing = proposal.timing {
                    Text(String(
                        format: String(localized: "ai_tuning_total_time_format"),
                        tuningDurationText(timing.total)
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func proposalSection(_ proposal: AIEqualizerProposal) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 22) {
            erasedSection(
                title: String(localized: "ai_lab_tuning_result"),
                content: AnyView(
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        if usesResonanceProposalLayout(proposal) {
                            resonanceProposalHeader(proposal)
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(proposal.resolvedTuningProfile.title)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(accent)
                                    Text(proposal.profileName)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(proposal.profileSpecificSummary)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .fixedSize(horizontal: false, vertical: true)
                                    tuningReferenceRows(for: proposal)
                                }
                                Spacer(minLength: 12)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(proposal.confidenceDisplayText)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(accent)
                                    if let timing = proposal.timing {
                                        Text(
                                            String(
                                                format: String(localized: "ai_tuning_total_time_format"),
                                                tuningDurationText(timing.total)
                                            )
                                        )
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.54))
                                        .lineLimit(1)
                                    }
                                }
                            }
                        }

                        if let timing = proposal.timing {
                            tuningTimingRow(timing)
                        }

                        AIEqualizerCurveView(
                            gains: proposal.gains,
                            mode: proposal.graphicEQMode,
                            accent: accent
                        )
                            .frame(height: 174)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                            spacing: 8
                        ) {
                            resultCell(
                                String(localized: "ai_tuning_intensity"),
                                (proposal.tuningIntensity ?? .smart).title
                            )
                            resultCell(String(localized: "ai_lab_preamp"), String(format: "%.1f dB", proposal.preampDB))
                            resultCell(String(localized: "eq_bass"), String(format: "%+.1f dB", proposal.tone.bassGain))
                            resultCell(String(localized: "eq_treble"), String(format: "%+.1f dB", proposal.tone.trebleGain))
                            resultCell(String(localized: "eq_surround"), "\(Int(proposal.spatial.surroundLevel * 100))%")
                            resultCell(String(localized: "eq_reverb"), "\(Int(proposal.spatial.reverbLevel * 100))%")
                            if let evidenceCount = proposal.learningEvidenceCount,
                               evidenceCount > 0 {
                                resultCell(
                                    String(localized: "ai_learning_enabled"),
                                    String(
                                        format: String(localized: "ai_learning_applied_value"),
                                        evidenceCount
                                    )
                                )
                            }
                        }
                    }
                    .padding(14)

                    divider.padding(.horizontal, 14)

                    erasedProposalDisclosure(
                        title: String(localized: "ai_lab_more_parameters"),
                        isExpanded: $isProposalParameterExpanded,
                        content: { AnyView(
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                            spacing: 8
                        ) {
                            resultCell(String(localized: "eq_processing_intensity"), String(format: "%.0f%%", proposal.professional.processingIntensity * 100))
                            resultCell(String(localized: "ai_lab_stereo_width"), String(format: "%.2fx", proposal.spatial.stereoWidth))
                            if proposal.effects.loudnessNormalizationEnabled {
                                resultCell(String(localized: "eq_target_lufs"), String(format: "%.1f LUFS", proposal.effects.targetLUFS))
                            }
                            if proposal.effects.compressorEnabled {
                                resultCell(String(localized: "eq_compressor"), String(format: "%.1f:1", proposal.effects.compressorRatio))
                            }
                            if proposal.effects.subboostEnabled {
                                resultCell(String(localized: "eq_subboost"), String(format: "%+.1f dB", proposal.effects.subboostGainDB))
                            }
                            if proposal.effects.virtualBassEnabled {
                                resultCell(String(localized: "eq_virtual_bass"), String(format: "%.1f", proposal.effects.virtualBassStrength))
                            }
                            if proposal.effects.exciterEnabled {
                                resultCell(String(localized: "eq_exciter"), String(format: "%+.1f dB", proposal.effects.exciterAmountDB))
                            }
                            if proposal.effects.bs2bEnabled || proposal.effects.crossfeedEnabled || proposal.effects.haasEnabled {
                                resultCell(String(localized: "eq_headphone_spatial"), headphoneEffectName(proposal.effects))
                            }
                            if proposal.effects.finalLimiterEnabled {
                                resultCell(String(localized: "eq_final_limiter"), String(format: "%.1f dBFS", proposal.effects.finalLimiterCeilingDB))
                            }
                        }
                        ) }
                    )

                    divider.padding(.horizontal, 14)

                    erasedProposalDisclosure(
                        title: String(localized: "eq_mono_calibration"),
                        isExpanded: $isCalibrationExpanded,
                        content: { AnyView(
                        VStack(spacing: 0) {
                            stateRow(String(localized: "eq_output_calibration"), isOn: proposal.calibration.outputCalibrationEnabled)
                            divider
                            stateRow(String(localized: "eq_loudness_matching"), isOn: proposal.calibration.loudnessMatchingEnabled)
                            divider
                            stateRow(String(localized: "eq_smart_song"), isOn: proposal.calibration.smartSongCompensationEnabled)
                            divider
                            stateRow(String(localized: "eq_dynamic_eq"), isOn: proposal.professional.dynamicEQ.enabled)
                            divider
                            stateRow(String(localized: "eq_multiband"), isOn: proposal.professional.multiband.enabled)
                            divider
                            stateRow(String(localized: "eq_parametric_eq"), isOn: proposal.professional.parametricEQ.enabled)
                        }
                        ) }
                    )
                }
                .background(cardBackground)
                )
            )

            HStack(spacing: 10) {
                Button(action: agent.applyCurrentProposal) {
                    Text(agent.isCurrentProposalApplied
                         ? String(localized: "ai_lab_applied")
                         : String(localized: "ai_lab_apply"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.78)))
                }
                .buttonStyle(MonoBouncingButtonStyle())
                .disabled(agent.isCurrentProposalApplied)

                Button(action: agent.analyzeCurrentSong) {
                    MonoIcon(icon: .refresh, size: 17, color: .white.opacity(0.86))
                        .monoIconArtwork(MonoGlyphSemantic.agentReanalyze.rawValue)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                }
                .buttonStyle(MonoBouncingButtonStyle())
                .accessibilityLabel(String(localized: "ai_lab_reanalyze"))
            }

            if agent.adaptiveLearningEnabled,
               agent.learnsFromExplicitFeedback,
               agent.isCurrentProposalApplied {
                adaptiveLearningFeedbackRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        })
    }

    var adaptiveLearningFeedbackRow: some View {
        HStack(spacing: 10) {
            learningFeedbackButton(
                title: String(localized: "ai_learning_positive"),
                feedback: .positive
            )
            learningFeedbackButton(
                title: String(localized: "ai_learning_negative"),
                feedback: .negative
            )
        }
    }

    func learningFeedbackButton(
        title: String,
        feedback: AIEqualizerLearningFeedback
    ) -> some View {
        let isSelected = agent.currentLearningFeedback == feedback
        return Button {
            agent.recordCurrentProposalFeedback(feedback)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? accentForeground : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.8) : Color.white.opacity(0.055))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(
                                    isSelected ? accent.opacity(0.9) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        }
                )
        }
        .buttonStyle(MonoBouncingButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var savedResultsSection: AnyView {
        erasedSection(
            title: String(localized: "ai_lab_saved_results"),
            content: AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(format: String(localized: "ai_lab_history_count"), agent.savedProposals.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Button {
                            agent.deleteAllSavedProposalsForCurrentSong()
                        } label: {
                            Text(String(localized: "ai_lab_delete_current_song"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.86))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(agent.savedProposals) { saved in
                        savedProposalRow(saved)
                    }
                }
                .padding(14)
                .background(cardBackground)
            )
        )
    }

    var clearAllProposalsButton: some View {
        Button {
            isShowingClearAllProposalsConfirmation = true
        } label: {
            HStack(spacing: 8) {
                MonoIcon(icon: .trash, size: 13, color: .red.opacity(0.88))
                Text(String(localized: "ai_lab_clear_all_proposals"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.red.opacity(0.88))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.16), lineWidth: 1)
                    }
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MonoBouncingButtonStyle())
    }

    func previousSavedProposal(
        for current: AIEqualizerProposal
    ) -> AIEqualizerSavedProposal? {
        agent.savedProposals.first { $0.id != current.id }
    }

    func automaticComparisonSection(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> AnyView {
        let bandChanges = changedBandCount(current: current, previous: previous)
        let largestChange = largestBandChange(current: current, previous: previous)
        let changes = keyParameterChanges(current: current, previous: previous)

        return erasedSection(
            title: String(localized: "ai_lab_automatic_comparison"),
            content: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    AIEqualizerComparisonCurve(
                        current: current.gains,
                        previous: previous.gains,
                        accent: accent
                    )
                    .frame(height: 94)

                    HStack(spacing: 8) {
                        comparisonSummaryMetric(
                            title: String(localized: "ai_lab_changed_bands"),
                            value: String(format: String(localized: "ai_lab_changed_bands_format"), bandChanges),
                            color: accent
                        )
                        comparisonSummaryMetric(
                            title: String(localized: "ai_lab_largest_change"),
                            value: largestChange.map {
                                "\(frequencyText($0.frequency)) \(String(format: "%+.1f dB", $0.delta))"
                            } ?? String(localized: "ai_lab_no_change"),
                            color: largestChange == nil ? .white.opacity(0.5) : accent
                        )
                    }

                    if changes.isEmpty {
                        Text(String(localized: "ai_lab_no_key_changes"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(changes) { change in
                                automaticChangeRow(change)
                                if change.id != changes.last?.id {
                                    divider
                                }
                            }
                        }
                    }

                    Button {
                        comparisonProposal = agent.savedProposals.first { $0.id == previous.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(localized: "ai_lab_view_full_comparison"))
                                .font(.system(size: 12, weight: .bold))
                            MonoIcon(icon: .chevronRight, size: 10, color: accent)
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(cardBackground)
            )
        )
    }

    func comparisonSummaryMetric(
        title: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.045)))
    }

    func automaticChangeRow(_ change: AIEqualizerComparisonChange) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(change.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(change.previousValue)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))

                MonoIcon(icon: .chevronRight, size: 8, color: .white.opacity(0.26))

                Text(change.currentValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)

                Text(change.deltaValue)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(change.delta >= 0 ? accent : .white.opacity(0.54))
                    .frame(width: 48, alignment: .trailing)
            }

            GeometryReader { proxy in
                let magnitude = min(1, abs(CGFloat(change.delta)) / 12)
                ZStack(alignment: change.delta >= 0 ? .leading : .trailing) {
                    Capsule().fill(Color.white.opacity(0.055))
                    Capsule()
                        .fill(change.delta >= 0 ? accent : Color.white.opacity(0.34))
                        .frame(width: max(3, proxy.size.width * magnitude))
                }
            }
            .frame(height: 2)
        }
        .padding(.vertical, 8)
    }

    func changedBandCount(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> Int {
        guard current.graphicEQMode == previous.graphicEQMode else {
            return current.gains.count
        }
        return zip(current.gains, previous.gains).filter { abs($0 - $1) >= 0.15 }.count
    }

    func largestBandChange(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> (frequency: Float, delta: Float)? {
        guard current.graphicEQMode == previous.graphicEQMode else { return nil }
        let frequencies = current.graphicEQMode.centerFrequencies
        let count = min(frequencies.count, min(current.gains.count, previous.gains.count))
        guard count > 0 else { return nil }
        let index = (0..<count).max {
            abs(current.gains[$0] - previous.gains[$0])
                < abs(current.gains[$1] - previous.gains[$1])
        }
        guard let index else { return nil }
        let delta = current.gains[index] - previous.gains[index]
        guard abs(delta) >= 0.15 else { return nil }
        return (frequencies[index], delta)
    }

    func keyParameterChanges(
        current: AIEqualizerProposal,
        previous: AIEqualizerProposal
    ) -> [AIEqualizerComparisonChange] {
        var changes: [AIEqualizerComparisonChange] = []
        appendChange(
            &changes,
            title: String(localized: "eq_bass"),
            current: current.tone.bassGain,
            previous: previous.tone.bassGain,
            suffix: " dB"
        )
        appendChange(
            &changes,
            title: String(localized: "eq_treble"),
            current: current.tone.trebleGain,
            previous: previous.tone.trebleGain,
            suffix: " dB"
        )
        appendChange(
            &changes,
            title: String(localized: "eq_surround"),
            current: current.spatial.surroundLevel * 100,
            previous: previous.spatial.surroundLevel * 100,
            suffix: "%"
        )
        appendChange(
            &changes,
            title: String(localized: "eq_reverb"),
            current: current.spatial.reverbLevel * 100,
            previous: previous.spatial.reverbLevel * 100,
            suffix: "%"
        )
        appendChange(
            &changes,
            title: String(localized: "eq_processing_intensity"),
            current: current.professional.processingIntensity * 100,
            previous: previous.professional.processingIntensity * 100,
            suffix: "%"
        )
        return changes
    }

    func appendChange(
        _ changes: inout [AIEqualizerComparisonChange],
        title: String,
        current: Float,
        previous: Float,
        suffix: String
    ) {
        let delta = current - previous
        guard abs(delta) >= 0.1 else { return }
        changes.append(
            AIEqualizerComparisonChange(
                id: title,
                title: title,
                previousValue: String(format: "%.1f%@", previous, suffix),
                currentValue: String(format: "%.1f%@", current, suffix),
                deltaValue: String(format: "%+.1f", delta),
                delta: delta
            )
        )
    }

}
