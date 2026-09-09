import SwiftUI

@MainActor
struct AudioTrainingDeveloperView: View {
    @ObservedObject private var store = AudioTrainingAdminStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var epochs = 40
    @State private var hiddenUnits = 64
    @State private var learningRate = 0.01
    @State private var validationPercent = 20
    @State private var minimumSamples = 32
    @State private var priorWeight = 1.0
    @State private var weightDecay = 0.0001
    @State private var earlyStoppingPatience = 8
    @State private var intentUnits = 32
    @State private var targetMode = AudioTrainingTargetMode.joint
    @State private var modelEnabled = true
    @State private var computeMode = AudioTrainingComputeMode.all
    @State private var legacyPriorStrength: Double = 1
    @State private var advancedStageMinimumSamples = 32
    @State private var showsDatasetDetails = false
    @State private var showsTrainingSettings = false
    @State private var showsModelDetails = false
    @State private var showsRuntimeSettings = false
    @State private var showsTestCases = false
    @State private var showsPublicationDetails = false

    var body: some View {
        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                LazyVStack(spacing: 24) {
                    DeveloperDiagnosticStatus(status: headerStatus)

                    trainingControlSection
                    datasetSection
                    modelSection
                    testingSection
                    FloatingBarBottomSpacer()
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                .iPadContentWidth(SettingsPageLayout.contentWidth)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
        }
        .developerDiagnosticPageChrome(title: String(localized: "audio_training_title"))
        .task {
            await store.refresh()
            applyRemoteSettings()
            applyOnDeviceSettings()
        }
        .onDisappear {
            store.stopPolling()
        }
    }

    private var trainingControlSection: some View {
        trainingSurface(
            title: String(localized: "audio_training_control_section"),
            icon: progressIcon,
            tint: statusTint
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(jobStatusText)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(progressAccessibilityValue)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(statusTint)
                }

                ProgressView(value: progressValue)
                    .tint(statusTint)
                    .scaleEffect(x: 1, y: 1.35, anchor: .center)
                    .accessibilityLabel(String(localized: "audio_training_progress"))
                    .accessibilityValue(progressAccessibilityValue)

                trainingStageRail

                HStack {
                    Text(epochText)
                    Spacer()
                    Text(lossText)
                }
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))

                if let error = visibleError {
                    Text(error)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.red.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 10) {
                    trainingActionButton(
                        title: store.status?.currentJob?.isActive == true
                            ? String(localized: "audio_training_cancel")
                            : String(localized: "audio_training_start"),
                        icon: store.status?.currentJob?.isActive == true ? .stop : .play,
                        tint: store.status?.currentJob?.isActive == true ? .red : .cyan,
                        enabled: store.status?.currentJob?.isActive == true
                            ? !store.isMutating
                            : canStartTraining,
                        action: store.status?.currentJob?.isActive == true
                            ? cancelTraining
                            : startTraining
                    )

                    compactActionButton(
                        icon: .refresh,
                        label: String(localized: "audio_training_refresh"),
                        enabled: !store.isBusy,
                        action: refresh
                    )
                }

                trainingDisclosure(
                    title: String(localized: "audio_training_settings_section"),
                    isExpanded: $showsTrainingSettings
                ) {
                    integerSettingRow(
                        title: String(localized: "audio_training_epochs"),
                        value: $epochs,
                        range: 1...200
                    )
                    divider
                    integerSettingRow(
                        title: String(localized: "audio_training_hidden_units"),
                        value: $hiddenUnits,
                        range: 4...128,
                        step: 4
                    )
                    divider
                    doubleSettingRow(
                        title: String(localized: "audio_training_learning_rate"),
                        value: $learningRate,
                        range: 0.0005...0.05,
                        step: 0.0005
                    )
                    divider
                    integerSettingRow(
                        title: String(localized: "audio_training_validation_percent"),
                        value: $validationPercent,
                        range: 10...40,
                        step: 5,
                        suffix: "%"
                    )
                    divider
                    integerSettingRow(
                        title: String(localized: "audio_training_minimum_samples"),
                        value: $minimumSamples,
                        range: 4...100_000,
                        step: 4
                    )
                    divider
                    HStack(spacing: 12) {
                        Text(String(localized: "audio_training_target_mode"))
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Picker(String(localized: "audio_training_target_mode"), selection: $targetMode) {
                            ForEach(AudioTrainingTargetMode.allCases) { mode in
                                Text(targetModeTitle(mode)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(.white.opacity(0.72))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    divider
                    doubleSettingRow(
                        title: String(localized: "audio_training_prior_weight"),
                        value: $priorWeight,
                        range: 0.05...4,
                        step: 0.05,
                        fractionDigits: 2
                    )
                    divider
                    doubleSettingRow(
                        title: String(localized: "audio_training_weight_decay"),
                        value: $weightDecay,
                        range: 0...0.01,
                        step: 0.0001,
                        fractionDigits: 4
                    )
                    divider
                    integerSettingRow(
                        title: String(localized: "audio_training_early_stopping_patience"),
                        value: $earlyStoppingPatience,
                        range: 0...50
                    )
                    divider
                    integerSettingRow(
                        title: String(localized: "audio_training_intent_units"),
                        value: $intentUnits,
                        range: 0...64,
                        step: 2
                    )
                    divider
                    inlineActionRow(
                        title: String(localized: "audio_training_save_settings"),
                        icon: .save,
                        enabled: !store.isBusy && store.status?.currentJob?.isActive != true,
                        action: saveSettings
                    )
                }
            }
            .padding(16)
        }
    }

    private var datasetSection: some View {
        trainingSurface(
            title: String(localized: "audio_training_coverage_section"),
            icon: .cloud
        ) {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 2),
                    alignment: .leading,
                    spacing: 18
                ) {
                    trainingMetric(
                        String(localized: "audio_training_trainable_samples"),
                        value: count(trainableSampleCount)
                    )
                    trainingMetric(
                        String(localized: "audio_training_complete_samples"),
                        value: count(store.status?.dataset.completeSamples)
                    )
                    trainingMetric(
                        String(localized: "audio_training_distinct_tracks"),
                        value: count(store.status?.dataset.distinctTracks)
                    )
                    trainingMetric(
                        String(localized: "audio_training_contributing_accounts"),
                        value: count(store.status?.dataset.contributingAccounts)
                    )
                }

                divider

                distributionRow(
                    title: String(localized: "audio_training_band_distribution"),
                    leadingTitle: "10",
                    leadingValue: store.status?.dataset.tenBandSamples ?? 0,
                    trailingTitle: "32",
                    trailingValue: store.status?.dataset.thirtyTwoBandSamples ?? 0,
                    tint: .cyan
                )

                distributionRow(
                    title: String(localized: "audio_training_profile_distribution"),
                    leadingTitle: String(localized: "audio_training_profile_standard"),
                    leadingValue: store.status?.dataset.standardProfileSamples ?? 0,
                    trailingTitle: String(localized: "audio_training_profile_spatial"),
                    trailingValue: store.status?.dataset.spatialProfileSamples ?? 0,
                    tint: .purple
                )

                if !missingRequiredTrainingBranches.isEmpty {
                    Text(String(
                        format: String(localized: "audio_training_missing_branches_format"),
                        missingRequiredTrainingBranches.map(trainingBranchTitle).joined(separator: "、")
                    ))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                trainingDisclosure(
                    title: String(localized: "audio_training_dataset_details"),
                    isExpanded: $showsDatasetDetails
                ) {
                    infoRow(icon: .waveform, title: String(localized: "audio_training_branch_10_standard"), value: branchSampleCount("tenBand:standard"))
                    divider
                    infoRow(icon: .waveform, title: String(localized: "audio_training_branch_10_spatial"), value: branchSampleCount("tenBand:monoSpatialEnhancement"))
                    divider
                    infoRow(icon: .waveform, title: String(localized: "audio_training_branch_32_standard"), value: branchSampleCount("thirtyTwoBand:standard"))
                    divider
                    infoRow(icon: .waveform, title: String(localized: "audio_training_branch_32_spatial"), value: branchSampleCount("thirtyTwoBand:monoSpatialEnhancement"))
                    divider
                    infoRow(icon: .chart, title: String(localized: "audio_training_style_conditioned_samples"), value: count(store.status?.dataset.styleConditionedSamples))
                    divider
                    infoRow(icon: .waveform, title: String(localized: "audio_training_temporal_samples"), value: count(store.status?.dataset.temporallyConditionedSamples))
                    divider
                    infoRow(icon: .chart, title: String(localized: "audio_training_learning_conditioned_samples"), value: count(store.status?.dataset.learningConditionedSamples))
                    divider
                    infoRow(icon: .headphones, title: String(localized: "audio_training_device_conditioned_samples"), value: count(store.status?.dataset.deviceConditionedSamples))
                    divider
                    infoRow(icon: .checkmark, title: String(localized: "audio_training_confirmed_samples"), value: count(store.status?.dataset.feedbackConfirmedSamples))
                    divider
                    infoRow(icon: .close, title: String(localized: "audio_training_excluded_outcomes"), value: count(store.status?.dataset.excludedOutcomeSamples))
                    divider
                    infoRow(icon: .history, title: String(localized: "audio_training_legacy_plans"), value: count(store.status?.dataset.legacyPlans))
                }
            }
            .padding(16)
        }
    }

    private var modelSection: some View {
        trainingSurface(
            title: String(localized: "audio_training_model_pipeline_section"),
            icon: .chart,
            tint: store.activeInstalledModel == nil ? .cyan : .green
        ) {
            VStack(alignment: .leading, spacing: 0) {
            expandedInfoRow(
                icon: .cloud,
                title: String(localized: "audio_training_latest_trained_model"),
                value: store.status?.currentModel?.displayName
                    ?? String(localized: "audio_training_no_model")
            )
            divider
            expandedInfoRow(
                icon: .cloud,
                title: String(localized: "audio_training_published_model"),
                value: store.status?.publishedModel?.displayName ?? String(localized: "audio_training_no_published_model")
            )
            divider
            infoRow(
                icon: .play,
                title: String(localized: "audio_training_active_model"),
                value: store.activeInstalledModel.map { AudioTrainingModelPresentation.name(version: $0.version) }
                    ?? String(localized: "audio_training_no_active_model")
            )

            if store.status?.currentModel != nil {
                divider
                distributionRow(
                    title: String(localized: "audio_training_band_distribution"),
                    leadingTitle: "10",
                    leadingValue: modelTenBandSampleCount,
                    trailingTitle: "32",
                    trailingValue: modelThirtyTwoBandSampleCount,
                    tint: .cyan
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                distributionRow(
                    title: String(localized: "audio_training_profile_distribution"),
                    leadingTitle: String(localized: "audio_training_profile_standard"),
                    leadingValue: modelStandardProfileSampleCount,
                    trailingTitle: String(localized: "audio_training_profile_spatial"),
                    trailingValue: modelSpatialProfileSampleCount,
                    tint: .purple
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                if let error = store.publicationError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                }
                if let message = store.publicationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                }
                publicationDescription

                adaptiveActionPair {
                    trainingActionButton(
                        title: String(localized: "audio_training_download"),
                        icon: .playerDownload,
                        enabled: !store.isBusy && store.status?.currentJob?.isActive != true,
                        action: downloadModel
                    )
                } second: {
                    trainingActionButton(
                        title: String(localized: "audio_training_publish"),
                        icon: .cloud,
                        enabled: !store.isBusy && store.status?.currentJob?.isActive != true,
                        action: confirmPublish
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            trainingDisclosure(
                title: String(localized: "audio_training_model_details"),
                isExpanded: $showsModelDetails
            ) {
                ForEach(modelDetailRows) { row in
                    if row.showsLeadingDivider { divider }
                    if row.usesExpandedLayout {
                        expandedInfoRow(icon: row.icon, title: row.title, value: row.value)
                    } else {
                        infoRow(icon: row.icon, title: row.title, value: row.value)
                    }
                }
            }

            trainingDisclosure(
                title: String(localized: "audio_training_on_device_settings_section"),
                isExpanded: $showsRuntimeSettings
            ) {
                HStack(spacing: 12) {
                    Text(String(localized: "audio_training_model_enabled"))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $modelEnabled)
                        .labelsHidden()
                        .accessibilityLabel(String(localized: "audio_training_model_enabled"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                divider
                HStack(spacing: 12) {
                    Text(String(localized: "audio_training_compute_mode"))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker(String(localized: "audio_training_compute_mode"), selection: $computeMode) {
                        ForEach(AudioTrainingComputeMode.allCases) { mode in
                            Text(computeModeTitle(mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                divider
                doubleSettingRow(title: String(localized: "audio_training_legacy_prior_strength"), value: $legacyPriorStrength, range: 0...1, step: 0.05, fractionDigits: 2)
                divider
                integerSettingRow(title: String(localized: "audio_training_advanced_stage_minimum"), value: $advancedStageMinimumSamples, range: 16...512, step: 16)
                divider
                inlineActionRow(title: String(localized: "audio_training_save_model_settings"), icon: .save, enabled: !store.isBusy, action: saveOnDeviceSettings)
            }

            if store.previousInstalledModel != nil || store.activeInstalledModel != nil {
                divider
                adaptiveActionPair {
                    if store.previousInstalledModel != nil {
                        inlineActionRow(title: String(localized: "audio_training_rollback"), icon: .history, enabled: !store.isBusy, action: rollbackModel)
                    }
                } second: {
                    if store.activeInstalledModel != nil {
                        inlineActionRow(title: String(localized: "audio_training_deactivate"), icon: .stop, tint: .red, enabled: !store.isBusy, action: confirmDeactivate)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            }
        }
    }

    private func trainingSurface<Content: View>(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color = .cyan,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MonoIcon(icon: icon, size: 15, color: tint, lineWidth: 1.7)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            divider
            content()
        }
        .background(
            Color(red: 0.045, green: 0.05, blue: 0.061),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.65)
        }
    }

    private var trainingStageRail: some View {
        let stages = [
            String(localized: "audio_training_status_collecting"),
            String(localized: "audio_training_status_training"),
            String(localized: "audio_training_status_validating"),
            String(localized: "audio_training_status_completed")
        ]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(trainingStageIsReached(index)
                                    ? statusTint
                                    : Color.white.opacity(0.12))
                                .frame(width: 7, height: 7)
                            trainingStageTitle(title, index: index)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 7) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, title in
                        VStack(alignment: .leading, spacing: 7) {
                            Capsule()
                                .fill(trainingStageIsReached(index)
                                    ? statusTint
                                    : Color.white.opacity(0.1))
                                .frame(height: 4)
                            trainingStageTitle(title, index: index)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "audio_training_progress"))
        .accessibilityValue(jobStatusText)
    }

    private func trainingStageTitle(_ title: String, index: Int) -> some View {
        Text(title)
            .font(.system(
                .caption2,
                design: .rounded,
                weight: currentTrainingStageIndex == index ? .bold : .medium
            ))
            .foregroundStyle(
                currentTrainingStageIndex == index
                    ? Color.white.opacity(0.9)
                    : Color.white.opacity(0.38)
            )
    }

    private func trainingMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func distributionRow(
        title: String,
        leadingTitle: String,
        leadingValue: Int,
        trailingTitle: String,
        trailingValue: Int,
        tint: Color
    ) -> some View {
        let total = leadingValue + trailingValue
        let fraction = total > 0 ? CGFloat(leadingValue) / CGFloat(total) : 0.5
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, (proxy.size.width - 2) * fraction))
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                }
            }
            .frame(height: 5)

            HStack {
                Text("\(leadingTitle) · \(leadingValue)")
                Spacer()
                Text("\(trailingTitle) · \(trailingValue)")
            }
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }

    private func trainingDisclosure<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer(minLength: 8)
                    MonoIcon(
                        icon: .chevronRight,
                        size: 11,
                        color: .white.opacity(0.42)
                    )
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isExpanded.wrappedValue
                    ? String(localized: "audio_training_diagnostic_expanded")
                    : String(localized: "audio_training_diagnostic_collapsed")
            )

            if isExpanded.wrappedValue {
                divider
                content()
            }
        }
        .background(Color.white.opacity(0.026), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trainingActionButton(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color = .cyan,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MonoIcon(icon: icon, size: 14, color: enabled ? tint : .white.opacity(0.28))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(enabled ? Color.white.opacity(0.9) : Color.white.opacity(0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.horizontal, 10)
            .background(
                enabled ? tint.opacity(0.13) : Color.white.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(enabled ? tint.opacity(0.24) : Color.white.opacity(0.05), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func compactActionButton(
        icon: MonoIcon.IconType,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonoIcon(icon: icon, size: 15, color: enabled ? .cyan : .white.opacity(0.28))
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(enabled ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func inlineActionRow(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color = .cyan,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                MonoIcon(icon: icon, size: 13, color: enabled ? tint : .white.opacity(0.25))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(enabled ? Color.white.opacity(0.8) : Color.white.opacity(0.28))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func adaptiveActionPair<First: View, Second: View>(
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                first()
                second()
            }
            VStack(spacing: 10) {
                first()
                second()
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 0.7)
    }

    private var testingSection: some View {
        trainingSurface(
            title: String(localized: "audio_training_testing_section"),
            icon: .waveform,
            tint: .purple
        ) {
            VStack(alignment: .leading, spacing: 0) {
            adaptiveActionPair {
                trainingActionButton(
                    title: store.isTestingModel
                        ? String(localized: "audio_training_model_testing")
                        : String(localized: "audio_training_run_model_test"),
                    icon: .play,
                    tint: .purple,
                    enabled: !store.isBusy && store.activeInstalledModel != nil,
                    action: runModelTest
                )
            } second: {
                trainingActionButton(
                    title: store.isTestingTuning
                        ? String(localized: "audio_training_tuning_testing")
                        : String(localized: "audio_training_run_tuning_test"),
                    icon: .waveform,
                    enabled: !store.isBusy
                        && store.activeInstalledModel != nil
                        && store.onDeviceSettings.isEnabled,
                    action: runTuningTest
                )
            }
            .padding(16)

            if let result = store.modelTestResult {
                divider
                expandedInfoRow(
                    icon: .chart,
                    title: String(localized: "audio_training_model_test_result"),
                    value: modelTestResultText(result)
                )

                trainingDisclosure(
                    title: String(localized: "audio_training_test_cases"),
                    isExpanded: $showsTestCases
                ) {
                    ForEach(Array(result.testCases.enumerated()), id: \.element.id) { index, testCase in
                        if index > 0 { divider }
                        AudioTrainingDiagnosticDisclosure(
                            title: testCaseTitle(testCase.id),
                            subtitle: String(
                                format: String(localized: "audio_training_case_latency_format"),
                                testCase.input.count,
                                testCase.rawOutput.count,
                                testCase.latencyMilliseconds
                            ),
                            text: """
                            \(String(localized: "audio_training_complete_model_input")) [\(testCase.input.count)]
                            \(tensorText(testCase.input))

                            \(String(localized: "audio_training_raw_model_output")) [\(testCase.rawOutput.count)]
                            \(tensorText(testCase.rawOutput))
                            """
                        )
                    }
                }
            }

            if let result = store.tuningTestResult {
                divider
                expandedInfoRow(
                    icon: .waveform,
                    title: String(localized: "audio_training_tuning_test_result"),
                    value: tuningTestResultText(result)
                )

                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_sampling_diagnostic"),
                    subtitle: samplingSubtitle(result),
                    text: samplingDiagnosticText(result)
                )

                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_complete_model_input"),
                    subtitle: String(
                        format: String(localized: "audio_training_value_count_format"),
                        result.inference.input.count
                    ),
                    text: tensorText(result.inference.input)
                )

                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_raw_model_output"),
                    subtitle: String(
                        format: String(localized: "audio_training_value_count_format"),
                        result.inference.rawOutput.count
                    ),
                    text: tensorText(result.inference.rawOutput)
                )

                if !result.inference.priorInput.isEmpty {
                    divider
                    AudioTrainingDiagnosticDisclosure(
                        title: String(localized: "audio_training_prior_pass"),
                        subtitle: String(format: "%.1f%%", result.inference.trackCorrectionStrength * 100),
                        text: tensorText(result.inference.priorInput) + "\n\n"
                            + tensorText(result.inference.priorOutput)
                    )
                }
                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_blended_output"),
                    subtitle: String(format: "%.1f%%", result.inference.trackCorrectionStrength * 100),
                    text: tensorText(result.inference.blendedOutput)
                )

                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_final_compiled_result"),
                    subtitle: String(
                        format: String(localized: "audio_training_band_result_format"),
                        result.bandCount
                    ),
                    text: proposalJSON(result.finalProposal)
                )
                divider
                AudioTrainingDiagnosticDisclosure(
                    title: String(localized: "audio_training_applied_dsp"),
                    subtitle: result.profileName,
                    text: result.appliedDSPJSON
                )
            }
            }
        }
    }

    private func infoRow(
        icon: MonoIcon.IconType,
        title: String,
        value: String
    ) -> some View {
        SettingsInfoRow(icon: icon, title: title, value: value)
    }

    private func expandedInfoRow(
        icon: MonoIcon.IconType,
        title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconBadge(icon: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .regular))
                    .foregroundColor(.white.opacity(0.68))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func integerSettingRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = ""
    ) -> some View {
        adaptiveSettingRow(title: title) {
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(minWidth: 62, alignment: .trailing)
            }
            .fixedSize()
        }
    }

    private func doubleSettingRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        fractionDigits: Int = 4
    ) -> some View {
        adaptiveSettingRow(title: title) {
            Stepper(value: value, in: range, step: step) {
                Text(String(format: "%.*f", fractionDigits, value.wrappedValue))
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(minWidth: 72, alignment: .trailing)
            }
            .fixedSize()
        }
    }

    private func adaptiveSettingRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                control()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundColor(.white)
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var headerStatus: String {
        if store.isRefreshing && store.status == nil {
            return String(localized: "audio_training_loading")
        }
        return jobStatusText
    }

    private var statusTint: Color {
        switch store.status?.currentJob?.state {
        case "completed": return .green
        case "failed", "cancelled": return .red
        case "queued", "collecting", "training", "validating": return .cyan
        default: return .cyan
        }
    }

    private var progressIcon: MonoIcon.IconType {
        store.status?.currentJob?.isActive == true ? .refresh : .chart
    }

    private var currentTrainingStageIndex: Int {
        switch store.status?.currentJob?.state {
        case "queued", "collecting": return 0
        case "training": return 1
        case "validating": return 2
        case "completed": return 3
        default: return -1
        }
    }

    private func trainingStageIsReached(_ index: Int) -> Bool {
        currentTrainingStageIndex >= index
    }

    private var jobStatusText: String {
        switch store.status?.currentJob?.state {
        case "queued": return String(localized: "audio_training_status_queued")
        case "collecting": return String(localized: "audio_training_status_collecting")
        case "training": return String(localized: "audio_training_status_training")
        case "validating": return String(localized: "audio_training_status_validating")
        case "completed": return String(localized: "audio_training_status_completed")
        case "failed": return String(localized: "audio_training_status_failed")
        case "cancelled": return String(localized: "audio_training_status_cancelled")
        default: return String(localized: "audio_training_status_idle")
        }
    }

    private var progressValue: Double {
        min(1, max(0, store.status?.currentJob?.progress ?? 0))
    }

    private var progressAccessibilityValue: String {
        String(format: "%.0f%%", progressValue * 100)
    }

    private var epochText: String {
        guard let job = store.status?.currentJob else { return "—" }
        return String(
            format: String(localized: "audio_training_epoch_format"),
            job.epoch,
            job.totalEpochs
        )
    }

    private var lossText: String {
        guard let loss = store.status?.currentJob?.validationLoss else { return "—" }
        return String(format: "val %.4f", loss)
    }

    private var visibleError: String? {
        store.errorMessage ?? store.status?.currentJob?.errorMessage
    }

    private var modelTenBandSampleCount: Int {
        guard let metrics = store.status?.currentModel?.metrics else { return 0 }
        return (metrics.tenBandTrainingSamples ?? 0) + (metrics.tenBandValidationSamples ?? 0)
    }

    private var modelThirtyTwoBandSampleCount: Int {
        guard let metrics = store.status?.currentModel?.metrics else { return 0 }
        return (metrics.thirtyTwoBandTrainingSamples ?? 0)
            + (metrics.thirtyTwoBandValidationSamples ?? 0)
    }

    private var modelStandardProfileSampleCount: Int {
        guard let metrics = store.status?.currentModel?.metrics else { return 0 }
        return (metrics.standardProfileTrainingSamples ?? 0)
            + (metrics.standardProfileValidationSamples ?? 0)
    }

    private var modelSpatialProfileSampleCount: Int {
        guard let metrics = store.status?.currentModel?.metrics else { return 0 }
        return (metrics.spatialProfileTrainingSamples ?? 0)
            + (metrics.spatialProfileValidationSamples ?? 0)
    }

    private var modelDetailRows: [AudioTrainingModelDetailRow] {
        let currentModel = store.status?.currentModel
        let metrics = currentModel?.metrics
        var rows = [
            AudioTrainingModelDetailRow(
                id: "samples",
                icon: .waveform,
                title: String(localized: "audio_training_model_samples"),
                value: count(currentModel?.sampleCount),
                showsLeadingDivider: false
            ),
            AudioTrainingModelDetailRow(
                id: "mode",
                icon: .chart,
                title: String(localized: "audio_training_model_mode"),
                value: (modelCompleteSampleCount ?? 0) > 0
                    ? String(localized: "audio_training_model_mode_supervised")
                    : String(localized: "audio_training_model_mode_prior")
            )
        ]

        func append(
            _ id: String,
            icon: MonoIcon.IconType,
            title: String,
            value: String?,
            usesExpandedLayout: Bool = false
        ) {
            guard let value else { return }
            rows.append(AudioTrainingModelDetailRow(
                id: id,
                icon: icon,
                title: title,
                value: value,
                usesExpandedLayout: usesExpandedLayout
            ))
        }

        append("completeSamples", icon: .waveform, title: String(localized: "audio_training_model_complete_samples"), value: modelCompleteSampleCount.map(String.init))
        append("styleSamples", icon: .chart, title: String(localized: "audio_training_model_style_samples"), value: modelStyleConditionedSampleCount.map(String.init))
        append("temporalSamples", icon: .waveform, title: String(localized: "audio_training_model_temporal_samples"), value: modelTemporalSampleCount.map(String.init))
        append("learningSamples", icon: .chart, title: String(localized: "audio_training_model_learning_samples"), value: modelLearningSampleCount.map(String.init))
        append("deviceSamples", icon: .headphones, title: String(localized: "audio_training_model_device_samples"), value: modelDeviceSampleCount.map(String.init))
        append("tracks", icon: .musicNote, title: String(localized: "audio_training_model_distinct_tracks"), value: modelDistinctTrackCount.map(String.init))
        append("confirmedSamples", icon: .checkmark, title: String(localized: "audio_training_model_confirmed_samples"), value: modelConfirmedSampleCount.map(String.init))
        append("legacySamples", icon: .history, title: String(localized: "audio_training_model_legacy_samples"), value: modelLegacySampleCount.map(String.init))

        let validationLoss = metrics?.initialValidationLoss.flatMap { initialLoss in
            metrics?.validationLoss.map { loss in
                String(format: "%.4f → %.4f", initialLoss, loss)
            }
        }
        append("validationLoss", icon: .chart, title: String(localized: "audio_training_validation_loss"), value: validationLoss)
        append("optimizationSteps", icon: .chart, title: String(localized: "audio_training_optimization_steps"), value: metrics?.optimizationSteps.map(String.init))

        let bestEpoch = metrics?.epochsRun.flatMap { epochsRun in
            metrics?.bestEpoch.map { "\($0) / \(epochsRun)" }
        }
        append("bestEpoch", icon: .chart, title: String(localized: "audio_training_best_epoch"), value: bestEpoch)
        append("architecture", icon: .chart, title: String(localized: "audio_training_architecture"), value: metrics?.architecture)
        if let source = metrics?.selectionSource {
            let selection = source == "heldOutTracks"
                ? String(localized: "audio_training_selection_held_out")
                : String(localized: "audio_training_selection_training")
            append("selectionSource", icon: .chart, title: String(localized: "audio_training_selection_source"), value: selection, usesExpandedLayout: true)
        }
        append("accounts", icon: .chart, title: String(localized: "audio_training_model_complete_accounts"), value: metrics?.completeAccountCount.map(String.init))

        let excludedSamples = metrics?.selfGeneratedSamplesExcluded.flatMap { samples in
            metrics?.selfGeneratedPlansExcluded.map { "\(samples) / \($0)" }
        }
        append("excludedSamples", icon: .stop, title: String(localized: "audio_training_model_self_generated_excluded"), value: excludedSamples)
        append("targetMode", icon: .chart, title: String(localized: "audio_training_target_mode"), value: metrics?.targetMode.map(targetModeTitle))
        if let calibration = metrics?.confidenceCalibration {
            let text = ["tenBand:standard", "tenBand:monoSpatialEnhancement", "thirtyTwoBand:standard", "thirtyTwoBand:monoSpatialEnhancement"].map { branch in
                let strength = Float(calibration.branches[branch]?.trackCorrectionStrength ?? 0)
                let evidence = calibration.evidence(for: branch, trackCorrectionStrength: strength)
                return String(format: String(localized: "audio_training_branch_calibration_format"),
                              trainingBranchTitle(branch), evidence?.displayText ?? String(localized: "audio_training_confidence_uncalibrated"))
            }.joined(separator: "\n")
            append("branchCalibration", icon: .chart, title: String(localized: "audio_training_branch_calibration"), value: text, usesExpandedLayout: true)
        }
        if let validation = metrics?.branchValidation {
            let text = validation.keys.sorted().map { branch in
                guard let result = validation[branch],
                      let error = result.eqMAEDB, let prior = result.priorEQMAEDB else {
                    return String(format: String(localized: "audio_training_branch_unvalidated_format"), branch)
                }
                return String(
                    format: String(localized: "audio_training_branch_validation_format"),
                    branch, result.samples, error, prior
                )
            }.joined(separator: "\n")
            append("branchValidation", icon: .chart, title: String(localized: "audio_training_branch_validation"), value: text, usesExpandedLayout: true)
            let errors = validation.keys.sorted().compactMap { branch -> String? in
                guard let result = validation[branch], let p90 = result.trackEQMAEP90DB else { return nil }
                return String(format: String(localized: "audio_training_track_error_format"), branch, result.tracks ?? 0, p90)
            }.joined(separator: "\n")
            if !errors.isEmpty {
                append("trackErrors", icon: .chart, title: String(localized: "audio_training_track_error"), value: errors, usesExpandedLayout: true)
            }
        }
        if let validation = metrics?.conditionValidation {
            let text = validation.keys.sorted().compactMap { condition -> String? in
                guard let result = validation[condition], let error = result.eqMAEDB,
                      let prior = result.priorEQMAEDB else { return nil }
                return String(format: String(localized: "audio_training_branch_validation_format"), condition, result.samples, error, prior)
            }.joined(separator: "\n")
            if !text.isEmpty {
                append("conditionValidation", icon: .chart, title: String(localized: "audio_training_condition_validation"), value: text, usesExpandedLayout: true)
            }
        }
        if let pairs = metrics?.preferenceValidationPairs, pairs > 0,
           let accuracy = metrics?.preferenceValidationAccuracy {
            append("preferenceValidation", icon: .chart, title: String(localized: "audio_training_preference_validation"), value: String(
                format: String(localized: "audio_training_preference_validation_format"), pairs, accuracy * 100
            ), usesExpandedLayout: true)
        }

        if let branches = metrics?.completeBranchTrainingSamples {
            append(
                "branches",
                icon: .waveform,
                title: String(localized: "audio_training_model_complete_branches"),
                value: branchSummary(branches, validation: metrics?.completeBranchValidationSamples),
                usesExpandedLayout: true
            )
        }
        if let warnings = metrics?.qualityWarnings, !warnings.isEmpty {
            append(
                "warnings",
                icon: .stop,
                title: String(localized: "audio_training_quality_warnings"),
                value: warnings.joined(separator: "\n"),
                usesExpandedLayout: true
            )
        }

        rows.append(AudioTrainingModelDetailRow(
            id: "coreML",
            icon: .save,
            title: String(localized: "audio_training_coreml_artifact"),
            value: currentModel?.coreMLArtifact == nil
                ? String(localized: "audio_training_coreml_on_demand")
                : String(localized: "audio_training_coreml_ready")
        ))
        append("downloaded", icon: .save, title: String(localized: "audio_training_downloaded"), value: store.downloadedModelFileName, usesExpandedLayout: true)
        append("previousModel", icon: .history, title: String(localized: "audio_training_previous_model"), value: store.previousInstalledModel?.version, usesExpandedLayout: true)
        return rows
    }

    private var canStartTraining: Bool {
        guard !store.isBusy,
              let dataset = store.status?.dataset else {
            return false
        }
        let hasEnoughSamples = (
            dataset.trainableSamples ?? dataset.completeSamples + dataset.legacyPlans
        ) >= minimumSamples
        return hasEnoughSamples && missingRequiredTrainingBranches.isEmpty
    }

    private var missingRequiredTrainingBranches: [String] {
        guard let branchSamples = store.status?.dataset.branchSamples else { return [] }
        return [
            "tenBand:standard",
            "tenBand:monoSpatialEnhancement"
        ].filter { (branchSamples[$0] ?? 0) < 1 }
    }

    private func branchSampleCount(_ branch: String) -> String {
        count(store.status?.dataset.branchSamples?[branch])
    }

    private func trainingBranchTitle(_ branch: String) -> String {
        switch branch {
        case "tenBand:standard": return String(localized: "audio_training_branch_10_standard")
        case "tenBand:monoSpatialEnhancement": return String(localized: "audio_training_branch_10_spatial")
        case "thirtyTwoBand:standard": return String(localized: "audio_training_branch_32_standard")
        case "thirtyTwoBand:monoSpatialEnhancement": return String(localized: "audio_training_branch_32_spatial")
        default: return branch
        }
    }

    private var trainableSampleCount: Int? {
        guard let dataset = store.status?.dataset else { return nil }
        return dataset.trainableSamples ?? dataset.completeSamples + dataset.legacyPlans
    }

    private var modelCompleteSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.completeTrainingSamples != nil || metrics.completeValidationSamples != nil else {
            return nil
        }
        return (metrics.completeTrainingSamples ?? 0) + (metrics.completeValidationSamples ?? 0)
    }

    private var modelLegacySampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.legacyTrainingSamples != nil || metrics.legacyValidationSamples != nil else {
            return nil
        }
        return (metrics.legacyTrainingSamples ?? 0) + (metrics.legacyValidationSamples ?? 0)
    }

    private var modelStyleConditionedSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.styleConditionedTrainingSamples != nil
                || metrics.styleConditionedValidationSamples != nil else {
            return nil
        }
        return (metrics.styleConditionedTrainingSamples ?? 0)
            + (metrics.styleConditionedValidationSamples ?? 0)
    }

    private var modelTemporalSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.temporallyConditionedTrainingSamples != nil
                || metrics.temporallyConditionedValidationSamples != nil else {
            return nil
        }
        return (metrics.temporallyConditionedTrainingSamples ?? 0)
            + (metrics.temporallyConditionedValidationSamples ?? 0)
    }

    private var modelLearningSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.learningConditionedTrainingSamples != nil
                || metrics.learningConditionedValidationSamples != nil else {
            return nil
        }
        return (metrics.learningConditionedTrainingSamples ?? 0)
            + (metrics.learningConditionedValidationSamples ?? 0)
    }

    private var modelDeviceSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.deviceConditionedTrainingSamples != nil
                || metrics.deviceConditionedValidationSamples != nil else {
            return nil
        }
        return (metrics.deviceConditionedTrainingSamples ?? 0)
            + (metrics.deviceConditionedValidationSamples ?? 0)
    }

    private var modelDistinctTrackCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.distinctTrainingTracks != nil
                || metrics.distinctValidationTracks != nil else {
            return nil
        }
        return (metrics.distinctTrainingTracks ?? 0)
            + (metrics.distinctValidationTracks ?? 0)
    }

    private var modelConfirmedSampleCount: Int? {
        guard let metrics = store.status?.currentModel?.metrics,
              metrics.feedbackConfirmedTrainingSamples != nil
                || metrics.feedbackConfirmedValidationSamples != nil else {
            return nil
        }
        return (metrics.feedbackConfirmedTrainingSamples ?? 0)
            + (metrics.feedbackConfirmedValidationSamples ?? 0)
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private func applyRemoteSettings() {
        guard let settings = store.status?.settings else { return }
        epochs = settings.epochs
        hiddenUnits = settings.hiddenUnits
        learningRate = settings.learningRate
        validationPercent = settings.validationPercent
        minimumSamples = settings.minimumSamples
        priorWeight = settings.priorWeight ?? 1
        weightDecay = settings.weightDecay ?? 0.0001
        earlyStoppingPatience = settings.earlyStoppingPatience ?? 8
        intentUnits = settings.intentUnits ?? 32
        targetMode = settings.targetMode ?? .joint
    }

    private func targetModeTitle(_ mode: AudioTrainingTargetMode) -> String {
        switch mode {
        case .population: return String(localized: "audio_training_target_mode_population")
        case .personalized: return String(localized: "audio_training_target_mode_personalized")
        case .joint: return String(localized: "audio_training_target_mode_joint")
        }
    }

    private func branchSummary(_ training: [String: Int], validation: [String: Int]?) -> String {
        let order = [
            "tenBand:standard", "tenBand:monoSpatialEnhancement",
            "thirtyTwoBand:standard", "thirtyTwoBand:monoSpatialEnhancement"
        ]
        return order.map { key in
            "\(key) = \(training[key] ?? 0) + \(validation?[key] ?? 0)"
        }.joined(separator: "\n")
    }

    private func applyOnDeviceSettings() {
        let settings = store.onDeviceSettings
        modelEnabled = settings.isEnabled
        computeMode = settings.computeMode
        legacyPriorStrength = settings.legacyPriorStrength
        advancedStageMinimumSamples = settings.advancedStageMinimumSamples
    }

    private func computeModeTitle(_ mode: AudioTrainingComputeMode) -> String {
        switch mode {
        case .all: return String(localized: "audio_training_compute_all")
        case .cpuAndGPU: return String(localized: "audio_training_compute_cpu_gpu")
        case .cpuOnly: return String(localized: "audio_training_compute_cpu")
        }
    }

    private func tuningTestResultText(_ result: AudioTrainingTuningTestResult) -> String {
        let warnings = result.warningCodes.isEmpty
            ? String(localized: "audio_training_no_warnings")
            : result.warningCodes.joined(separator: ", ")
        let modelMode = result.isTrackConditioned
            ? String(localized: "audio_training_inference_track_conditioned")
            : String(localized: "audio_training_inference_population_prior")
        return String(
            format: String(localized: "audio_training_tuning_test_summary_format"),
            result.version,
            result.profileName,
            result.bandCount,
            modelMode,
            result.finalProposal.confidenceDisplayText,
            result.modelOutputStrength * 100,
            result.preampDB,
            result.elapsedMilliseconds,
            warnings
        )
    }

    private func modelTestResultText(_ result: AudioTrainingModelTestResult) -> String {
        let sensitivity = result.isInputSensitive
            ? String(localized: "audio_training_input_sensitive")
            : String(localized: "audio_training_input_insensitive")
        let inputResult = String(
            format: String(localized: "audio_training_model_test_summary_format"),
            result.version,
            result.testCaseCount,
            result.averageLatencyMilliseconds,
            Double(result.outputMinimum),
            Double(result.outputMaximum),
            sensitivity,
            Double(result.maximumInputResponseDelta)
        )
        let styleSensitivity = result.isStyleSensitive
            ? String(localized: "audio_training_style_sensitive")
            : String(localized: "audio_training_style_insensitive")
        let styleResult = String(
            format: String(localized: "audio_training_style_test_summary_format"),
            styleSensitivity,
            Double(result.maximumStyleResponseDelta)
        )
        let trackSensitivity = result.isTrackSensitive
            ? String(localized: "audio_training_track_sensitive")
            : String(localized: "audio_training_track_insensitive")
        let trackResult = String(
            format: String(localized: "audio_training_track_test_summary_format"),
            trackSensitivity,
            Double(result.maximumTrackResponseDelta)
        )
        let learningSensitivity = result.isLearningSensitive
            ? String(localized: "audio_training_learning_sensitive")
            : String(localized: "audio_training_learning_insensitive")
        let learningResult = String(
            format: String(localized: "audio_training_learning_test_summary_format"),
            learningSensitivity,
            Double(result.maximumLearningResponseDelta)
        )
        let deviceSensitivity = result.isDeviceSensitive
            ? String(localized: "audio_training_device_sensitive")
            : String(localized: "audio_training_device_insensitive")
        let deviceResult = String(
            format: String(localized: "audio_training_device_test_summary_format"),
            deviceSensitivity,
            Double(result.maximumDeviceResponseDelta)
        )
        let profileSensitivity = result.isTuningProfileSensitive
            ? String(localized: "audio_training_profile_sensitive")
            : String(localized: "audio_training_profile_insensitive")
        let profileResult = String(
            format: String(localized: "audio_training_profile_test_summary_format"),
            profileSensitivity,
            Double(result.tenBandTuningProfileResponseDelta),
            Double(result.thirtyTwoBandTuningProfileResponseDelta)
        )
        return inputResult + "\n" + styleResult + "\n" + trackResult + "\n"
            + profileResult + "\n" + learningResult + "\n" + deviceResult
    }

    private func testCaseTitle(_ id: String) -> String {
        switch id {
        case "zero": return String(localized: "audio_training_case_zero")
        case "ramp": return String(localized: "audio_training_case_ramp")
        case "alternating": return String(localized: "audio_training_case_alternating")
        case "zero-repeat": return String(localized: "audio_training_case_zero_repeat")
        case "mode-10-band": return String(localized: "audio_training_case_mode_10_band")
        case "mode-32-band": return String(localized: "audio_training_case_mode_32_band")
        case "profile-10-standard": return String(localized: "audio_training_case_profile_10_standard")
        case "profile-10-spatial": return String(localized: "audio_training_case_profile_10_spatial")
        case "profile-32-standard": return String(localized: "audio_training_case_profile_32_standard")
        case "profile-32-spatial": return String(localized: "audio_training_case_profile_32_spatial")
        case "style-rock": return String(localized: "audio_training_case_style_rock")
        case "style-ballad": return String(localized: "audio_training_case_style_ballad")
        case "track-rock-a": return String(localized: "audio_training_case_track_rock_a")
        case "track-rock-b": return String(localized: "audio_training_case_track_rock_b")
        case "learning-warm": return String(localized: "audio_training_case_learning_warm")
        case "learning-cool": return String(localized: "audio_training_case_learning_cool")
        case "device-opra": return String(localized: "audio_training_case_device_opra")
        case "device-custom": return String(localized: "audio_training_case_device_custom")
        default: return id
        }
    }

    private func samplingSubtitle(_ result: AudioTrainingTuningTestResult) -> String {
        result.samplingReused
            ? String(localized: "audio_training_sampling_reused")
            : String(localized: "audio_training_sampling_fresh")
    }

    private func samplingDiagnosticText(_ result: AudioTrainingTuningTestResult) -> String {
        """
        measurementReused = \(result.samplingReused)
        sampledAudioDurationSeconds = \(String(format: "%.6f", result.sampleDuration))
        sampleRateHz = \(String(format: "%.3f", result.sampleRate))
        acceptedFeatureFrames = \(result.frameCount)
        samplingElapsedMilliseconds = \(String(format: "%.6f", result.samplingElapsedMilliseconds))
        modelInferenceMilliseconds = \(String(format: "%.6f", result.inference.latencyMilliseconds))
        generationAndValidationMilliseconds = \(String(format: "%.6f", result.generationElapsedMilliseconds))
        dspApplyMilliseconds = \(String(format: "%.6f", result.applyingElapsedMilliseconds))
        completeTrainingSamples = \(result.completeSampleCount)
        legacyTrainingSamples = \(result.legacySampleCount)
        detailedDeviceTrainingSamples = \(result.deviceConditionedSampleCount)
        """
    }

    private func tensorText(_ values: [AudioTrainingTensorValue]) -> String {
        values.map { item in
            let value = String(format: "%.9g", Double(item.value))
            return String(format: "[%03d] %@ = %@", item.index, item.name, value)
        }
        .joined(separator: "\n")
    }

    private func proposalJSON(_ proposal: AIEqualizerProposal) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(proposal),
              let text = String(data: data, encoding: .utf8) else {
            return String(localized: "audio_training_result_encoding_failed")
        }
        return text
    }

    private func refresh() {
        Task {
            await store.refresh()
            applyRemoteSettings()
            applyOnDeviceSettings()
        }
    }

    private func saveSettings() {
        Task {
            await store.updateSettings(
                AudioTrainingSettingsUpdate(
                    epochs: epochs,
                    hiddenUnits: hiddenUnits,
                    learningRate: learningRate,
                    validationPercent: validationPercent,
                    minimumSamples: minimumSamples,
                    priorWeight: priorWeight,
                    weightDecay: weightDecay,
                    earlyStoppingPatience: earlyStoppingPatience,
                    intentUnits: intentUnits,
                    targetMode: targetMode
                )
            )
            applyRemoteSettings()
        }
    }

    private func startTraining() {
        Task {
            await store.startTraining()
            applyRemoteSettings()
        }
    }

    private func cancelTraining() {
        Task { await store.cancelTraining() }
    }

    private func downloadModel() {
        Task {
            await store.downloadCurrentModel()
            applyOnDeviceSettings()
        }
    }

    private func rollbackModel() {
        Task {
            await store.rollbackModel()
            applyOnDeviceSettings()
        }
    }

    private func saveOnDeviceSettings() {
        Task {
            await store.updateOnDeviceSettings(
                AudioTrainingOnDeviceSettings(
                    isEnabled: modelEnabled,
                    computeMode: computeMode,
                    legacyPriorStrength: legacyPriorStrength,
                    advancedStageMinimumSamples: advancedStageMinimumSamples
                )
            )
            applyOnDeviceSettings()
        }
    }

    private func runModelTest() {
        Task { await store.runModelTest() }
    }

    private func runTuningTest() {
        Task { await store.runTuningTest() }
    }

    private func confirmDeactivate() {
        AlertManager.shared.show(
            title: String(localized: "audio_training_deactivate_confirm_title"),
            message: String(localized: "audio_training_deactivate_confirm_message"),
            primaryButtonTitle: String(localized: "audio_training_deactivate"),
            secondaryButtonTitle: String(localized: "dev_mode_cancel"),
            primaryAction: {
                Task {
                    await store.deactivateModel()
                    applyOnDeviceSettings()
                }
            }
        )
    }

    @ViewBuilder
    private var publicationDescription: some View {
        if let preview = store.status?.currentModel?.releasePreview {
            Text(preview.summary)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
            trainingDisclosure(
                title: String(localized: "audio_training_release_notes_detailed"),
                isExpanded: $showsPublicationDetails
            ) {
                Text(preview.notes)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
        }
    }

    private func confirmPublish() {
        guard let model = store.status?.currentModel else { return }
        let summary = model.releasePreview?.summary ?? String(localized: "audio_training_release_generated_on_publish")
        AlertManager.shared.show(
            title: String(localized: "audio_training_publish_confirm_title"),
            message: String(format: String(localized: "audio_training_publish_release_confirm"), model.displayName, summary),
            primaryButtonTitle: String(localized: "audio_training_publish"),
            secondaryButtonTitle: String(localized: "dev_mode_cancel"),
            primaryAction: {
                Task { await store.publishModel(id: model.id) }
            }
        )
    }
}

private struct AudioTrainingModelDetailRow: Identifiable {
    let id: String
    let icon: MonoIcon.IconType
    let title: String
    let value: String
    var usesExpandedLayout = false
    var showsLeadingDivider = true
}

private struct AudioTrainingDiagnosticDisclosure: View {
    let title: String
    let subtitle: String
    let text: String

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(.caption2, design: .monospaced, weight: .regular))
                            .foregroundColor(.white.opacity(0.58))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isExpanded
                    ? String(localized: "audio_training_diagnostic_expanded")
                    : String(localized: "audio_training_diagnostic_collapsed")
            )

            if isExpanded {
                ScrollView(.horizontal) {
                    Text(text)
                        .font(.system(.caption2, design: .monospaced, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.2))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
    }
}
