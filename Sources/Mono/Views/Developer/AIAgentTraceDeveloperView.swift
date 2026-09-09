import SwiftUI
import UIKit

@MainActor
struct AIAgentTraceDeveloperView: View {
    @ObservedObject private var store = AIAgentTraceStore.shared
    @State private var showsClearConfirmation = false

    var body: some View {
        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    DeveloperDiagnosticStatus(status: String(format: String(localized: "agent_trace_session_count"), store.sessions.count))

                    traceLegend

                    if store.sessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                AIAgentTraceDetailView(sessionID: session.id)
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    FloatingBarBottomSpacer()
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                .padding(.top, 8)
                .iPadContentWidth(SettingsPageLayout.contentWidth)
            }
            .scrollIndicators(.hidden)
        }
        .developerDiagnosticPageChrome(title: String(localized: "agent_trace_title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsClearConfirmation = true
                } label: {
                    MonoIcon(icon: .trash, size: 15, color: store.sessions.isEmpty ? .white.opacity(0.25) : .red)
                        .frame(width: 44, height: 44)
                }
                .disabled(store.sessions.isEmpty)
                .accessibilityLabel(String(localized: "agent_trace_clear_action"))
            }
        }
        .alert(String(localized: "agent_trace_clear_title"), isPresented: $showsClearConfirmation) {
            Button(String(localized: "alert_cancel"), role: .cancel) {}
            Button(String(localized: "agent_trace_clear_action"), role: .destructive) {
                store.clear()
            }
        } message: {
            Text(String(localized: "agent_trace_clear_message"))
        }
    }

    private var traceLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legendItem(.conversation, color: .cyan)
                legendItem(.reasoning, color: .orange)
                legendItem(.skill, color: .purple)
            }

            Text(String(localized: "agent_trace_reasoning_notice"))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
        }
    }

    private func legendItem(_ category: AIAgentTraceCategory, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(category.localizedTitle)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MonoSemanticIcon(
                semantic: .agentTraceRoot,
                fallback: .sparkle,
                size: 28,
                color: .purple.opacity(0.9)
            )
            Text(String(localized: "agent_trace_empty_title"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(localized: "agent_trace_empty_message"))
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sessionRow(_ session: AIAgentTraceSession) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(session.status.tint.opacity(0.12))
                MonoSemanticIcon(
                    semantic: .agentTraceRoot,
                    fallback: .sparkle,
                    size: 16,
                    color: session.status.tint
                )
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(session.agentName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(session.status.localizedTitle)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(session.status.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(session.status.tint.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text(session.subject)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                Text("\(session.executionProvider) · \(session.executionModelDisplayName) · \(session.startedAt.agentTraceDateText)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(session.events.count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Text(String(localized: "agent_trace_events"))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.32))
            }

            MonoIcon(icon: .chevronRight, size: 11, color: .white.opacity(0.28))
        }
        .padding(15)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 0.7)
        }
    }
}

@MainActor
private struct AIAgentTraceDetailView: View {
    @ObservedObject private var store = AIAgentTraceStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessionID: UUID
    @State private var selectedCategory: AIAgentTraceCategory?

    private var session: AIAgentTraceSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        ZStack {
            DeveloperDiagnosticBackdrop()

            if let session {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        DeveloperDiagnosticStatus(status: session.subject)

                        overviewSection(session)
                        executionChainSection(session)

                        if session.agentID == "equalizer" {
                            skillsSection(session)
                            toolContractSection(session)
                            tuningRuntimeSection(session)
                        } else {
                            genericRuntimeSection(session)
                        }

                        modelRecordsSection(session)
                        rawTraceSection(session)

                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.top, 8)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
                .scrollIndicators(.hidden)
            } else {
                Text(String(localized: "agent_trace_missing"))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .developerDiagnosticPageChrome(title: session?.agentName ?? String(localized: "agent_trace_title"))
    }

    private func overviewSection(_ session: AIAgentTraceSession) -> some View {
        traceSection(
            title: String(localized: "agent_trace_overview"),
            icon: .infoCircle,
            tint: session.status.tint,
            artwork: .agentTraceOverview
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(session.status.tint)
                        .frame(width: 8, height: 8)

                    Text(session.status.localizedTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    Text(String(format: String(localized: "agent_trace_duration_format"), max(0, session.duration)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(session.subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    summaryLine(String(localized: "agent_trace_agent_id"), session.agentID)
                    summaryLine(String(localized: "agent_trace_provider"), "\(session.executionProvider) · \(session.executionModelDisplayName)")
                    summaryLine(String(localized: "agent_trace_started"), session.startedAt.agentTraceDateText)
                    summaryLine(
                        String(localized: "agent_trace_events"),
                        String(session.events.count)
                    )
                    if let failure = session.failureMessage, !failure.isEmpty {
                        summaryLine(
                            String(localized: "agent_trace_failure"),
                            failure,
                            valueColor: .red.opacity(0.92)
                        )
                    }
                }
            }
        }
    }

    private func executionChainSection(_ session: AIAgentTraceSession) -> some View {
        let events = session.events.filter { $0.stage != nil }
        return traceSection(
            title: String(localized: "agent_trace_execution_chain"),
            icon: .layers,
            tint: .cyan,
            artwork: .agentExecutionChain
        ) {
            if events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "agent_trace_legacy_chain_title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(String(localized: "agent_trace_legacy_chain_message"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        pipelineEventRow(event, isLast: index == events.count - 1)
                    }
                }
            }
        }
    }

    private func pipelineEventRow(_ event: AIAgentTraceEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill((event.stage?.tint ?? event.level.tint).opacity(0.16))
                    MonoIcon(
                        icon: event.stage?.icon ?? .logInfo,
                        size: 13,
                        color: event.stage?.tint ?? event.level.tint
                    )
                    .monoIconArtwork(event.stage?.monoGlyphSemantic.rawValue)
                }
                .frame(width: 32, height: 32)

                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.stage?.localizedTitle ?? String(localized: "agent_trace_stage_unknown"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer(minLength: 6)

                    if let duration = event.durationSeconds, duration >= 0.001 {
                        Text(String(format: String(localized: "agent_trace_duration_format"), duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.38))
                    } else {
                        Text(event.timestamp.agentTraceTimeText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.32))
                    }
                }

                Text(event.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.67))
                    .fixedSize(horizontal: false, vertical: true)

                if event.level == .warning || event.level == .error {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(event.level == .error ? Color.red.opacity(0.84) : Color.orange.opacity(0.84))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }

    private func skillsSection(_ session: AIAgentTraceSession) -> some View {
        let metadata = mergedMetadata(session)
        let requiredIDs = metadataList(metadata["required"] ?? metadata["requiredSkills"])
        let enabledIDs = metadataList(metadata["enabled"] ?? metadata["enabledSkills"])
        let customSkills = metadataList(metadata["customSkills"])
        let customSources = metadataList(metadata["customSources"])
        let builtInSources = metadataAssignments(metadata["builtInSources"])
        let requiredSet = Set(requiredIDs)
        let builtInIDs = enabledIDs.filter { !$0.lowercased().hasPrefix("custom.") }

        return traceSection(
            title: String(localized: "agent_trace_current_skills"),
            icon: .sparkle,
            tint: .purple,
            artwork: .agentCurrentSkills
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if builtInIDs.isEmpty && customSkills.isEmpty {
                    unavailableValue
                } else {
                    ForEach(Array(builtInIDs.enumerated()), id: \.offset) { index, skillID in
                        skillRow(
                            title: localizedSkillTitle(skillID),
                            detail: [
                                requiredSet.contains(skillID)
                                    ? String(localized: "agent_trace_skill_required")
                                    : String(localized: "agent_trace_skill_optional"),
                                builtInSources[skillID].map(localizedSource)
                            ]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                            isRequired: requiredSet.contains(skillID)
                        )
                        if index < builtInIDs.count - 1 || !customSkills.isEmpty { traceDivider }
                    }

                    ForEach(Array(customSkills.enumerated()), id: \.offset) { index, skill in
                        skillRow(
                            title: skill,
                            detail: index < customSources.count
                                ? localizedSource(customSources[index])
                                : String(localized: "agent_trace_skill_custom"),
                            isRequired: false
                        )
                        if index < customSkills.count - 1 { traceDivider }
                    }
                }

                if let revision = metadataValue(metadata, keys: ["revision", "skillRevision"]),
                   let fingerprint = metadataValue(metadata, keys: ["runtimeFingerprint", "skillFingerprint", "fingerprint"]) {
                    traceDivider
                    VStack(spacing: 9) {
                        summaryLine(String(localized: "agent_trace_skill_revision"), revision)
                        summaryLine(String(localized: "agent_trace_skill_fingerprint"), fingerprint)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private func skillRow(title: String, detail: String, isRequired: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.13))
                MonoIcon(icon: isRequired ? .lock : .checkmark, size: 12, color: .purple)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
    }

    private func toolContractSection(_ session: AIAgentTraceSession) -> some View {
        let metadata = mergedMetadata(session)
        return traceSection(
            title: String(localized: "agent_trace_tool_contract"),
            icon: .equalizer,
            tint: .orange,
            artwork: .agentToolContract
        ) {
            VStack(spacing: 9) {
                summaryLine(
                    String(localized: "agent_trace_tool_name"),
                    metadataValue(metadata, keys: ["toolName"]) ?? "mono_audio_tuning"
                )
                summaryLine(
                    String(localized: "agent_trace_policy_revision"),
                    metadataValue(metadata, keys: ["toolPolicyRevision", "policyRevision"]) ?? unavailableText
                )
                summaryLine(
                    String(localized: "agent_trace_invocation_mode"),
                    metadataValue(metadata, keys: ["invocationMode", "invocation"]) ?? unavailableText
                )
                summaryLine(
                    String(localized: "agent_trace_exactly_once"),
                    booleanText(metadata["requireExactlyOnce"])
                )
                summaryLine(
                    String(localized: "agent_trace_actual_invocations"),
                    metadataValue(metadata, keys: ["invocationCount", "modelToolInvocationCount"]) ?? unavailableText
                )
                summaryLine(
                    String(localized: "agent_trace_local_validation"),
                    booleanText(metadata["localValidationRequired"])
                )
                summaryLine(
                    String(localized: "agent_trace_prompt_fallback"),
                    booleanText(metadata["allowPromptFallback"])
                )
            }
        }
    }

    private func tuningRuntimeSection(_ session: AIAgentTraceSession) -> some View {
        let metadata = mergedMetadata(session)
        let identityRows: [(String, String?)] = [
            (String(localized: "agent_trace_agent_version"), metadata["agentVersion"]),
            (String(localized: "agent_trace_knowledge_version"), metadataValue(metadata, keys: ["knowledgeVersion"])),
            (String(localized: "agent_trace_tool_version"), metadataValue(metadata, keys: ["toolVersion"])),
            (String(localized: "agent_trace_configuration_source"), metadata["configurationSource"].map(localizedSource)),
            (String(localized: "agent_trace_sampling_mode"), metadata["samplingMode"]),
            (String(localized: "agent_trace_sampling_duration"), metadata["samplingSeconds"]),
            (String(localized: "agent_trace_audio_variant"), metadata["audioVariant"]),
            (String(localized: "agent_trace_device_target"), metadata["deviceTuningIdentity"]),
            (String(localized: "agent_trace_learning_revision"), metadata["learningRevision"])
        ]
        let resultRows: [(String, String?)] = [
            (String(localized: "agent_trace_result"), metadata["result"]),
            (String(localized: "agent_trace_cache_reused"), metadata["cacheReused"].map { booleanText($0) }),
            (String(localized: "agent_trace_profile"), metadata["profile"]),
            (String(localized: "agent_trace_output"), metadata["output"]),
            (String(localized: "agent_trace_eq_mode"), metadata["eqMode"]),
            (String(localized: "agent_trace_band_count"), metadata["bands"]),
            (String(localized: "agent_trace_preamp"), metadata["preampDB"]),
            (String(localized: "agent_trace_confidence"), metadata["confidence"]),
            (String(localized: "agent_trace_checked_rules"), metadata["checkedRuleCount"]),
            (String(localized: "agent_trace_warning_codes"), metadata["warningCodes"]),
            (String(localized: "agent_trace_proposal_id"), metadata["proposalID"])
        ]

        return traceSection(
            title: String(localized: "agent_trace_runtime_and_result"),
            icon: .audioWave,
            tint: .green,
            artwork: .agentRuntimeResult
        ) {
            VStack(alignment: .leading, spacing: 14) {
                labeledValues(
                    title: String(localized: "agent_trace_runtime_identity"),
                    rows: identityRows
                )

                traceDivider

                labeledValues(
                    title: String(localized: "agent_trace_tuning_result"),
                    rows: resultRows
                )
            }
        }
    }

    private func genericRuntimeSection(_ session: AIAgentTraceSession) -> some View {
        let metadata = mergedMetadata(session)
        let rows: [(String, String?)] = [
            (String(localized: "agent_trace_agent_id"), session.agentID),
            (String(localized: "agent_trace_provider"), session.executionProvider),
            (String(localized: "agent_trace_model"), session.executionModelDisplayName),
            (String(localized: "agent_trace_scope"), metadata["scope"]),
            (String(localized: "agent_trace_attempt"), metadataValue(metadata, keys: ["attempt", "nextAttempt"])),
            (String(localized: "agent_trace_result"), metadata["result"])
        ]

        return traceSection(
            title: String(localized: "agent_trace_runtime_identity"),
            icon: .logDebug,
            tint: .cyan,
            artwork: .agentRuntimeIdentity
        ) {
            labeledValues(title: nil, rows: rows)
        }
    }

    @ViewBuilder
    private func modelRecordsSection(_ session: AIAgentTraceSession) -> some View {
        let records = session.events.filter { event in
            event.metadata["recordType"]?.isEmpty == false
        }
        if !records.isEmpty {
            traceSection(
                title: String(localized: "agent_trace_model_records"),
                icon: .logDebug,
                tint: .indigo,
                artwork: .agentRuntimeIdentity
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(records) { event in
                        NavigationLink {
                            AIAgentTraceModelRecordView(event: event)
                        } label: {
                            modelRecordRow(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func modelRecordRow(_ event: AIAgentTraceEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(event.level.tint.opacity(0.13))
                MonoIcon(icon: .logDebug, size: 14, color: event.level.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)

                Text([
                    event.metadata["modelSource"],
                    event.metadata["provider"],
                    event.metadata["model"]
                ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)

                if let inputCount = event.metadata["inputCount"],
                   let outputCount = event.metadata["outputCount"] {
                    Text("\(inputCount) → \(outputCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.34))
                }
            }

            Spacer(minLength: 4)

            Text(event.timestamp.agentTraceTimeText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.3))

            MonoIcon(icon: .chevronRight, size: 10, color: .white.opacity(0.28))
        }
        .padding(13)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func rawTraceSection(_ session: AIAgentTraceSession) -> some View {
        let category = effectiveCategory(for: session)
        let events = session.events.filter {
            $0.category == category && shouldShowInRawTrace($0)
        }

        return traceSection(
            title: String(localized: "agent_trace_raw_records"),
            icon: .history,
            tint: category.tint,
            artwork: .agentRawRecords
        ) {
            VStack(alignment: .leading, spacing: 12) {
                categoryPicker(session)

                if events.isEmpty {
                    Text(String(localized: "agent_trace_category_empty"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func labeledValues(
        title: String?,
        rows: [(String, String?)]
    ) -> some View {
        let availableRows = rows.compactMap { title, value -> (String, String)? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (title, value)
        }
        return VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            if availableRows.isEmpty {
                unavailableValue
            } else {
                ForEach(Array(availableRows.enumerated()), id: \.offset) { _, row in
                    summaryLine(row.0, row.1)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryLine(
        _ title: String,
        _ value: String,
        valueColor: Color = .white.opacity(0.7)
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                summaryTitle(title)
                summaryValue(value, color: valueColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 14) {
                summaryTitle(title)
                    .frame(minWidth: 92, alignment: .leading)
                summaryValue(value, color: valueColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summaryValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func traceSection<Content: View>(
        title: String,
        icon: MonoIcon.IconType,
        tint: Color,
        artwork: MonoGlyphSemantic? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                MonoIcon(icon: icon, size: 14, color: tint)
                    .monoIconArtwork(artwork?.rawValue)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.94))

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.7)
                .offset(y: 12)
        }
        .padding(.bottom, 12)
    }

    private var traceDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 0.7)
    }

    private var unavailableText: String {
        String(localized: "agent_trace_unavailable")
    }

    private var unavailableValue: some View {
        Text(unavailableText)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func effectiveCategory(for session: AIAgentTraceSession) -> AIAgentTraceCategory {
        if let selectedCategory,
           session.events.contains(where: {
               $0.category == selectedCategory && shouldShowInRawTrace($0)
           }) {
            return selectedCategory
        }
        return AIAgentTraceCategory.allCases.first(where: { category in
            session.events.contains(where: {
                $0.category == category && shouldShowInRawTrace($0)
            })
        }) ?? .conversation
    }

    private func categoryPicker(_ session: AIAgentTraceSession) -> some View {
        let selected = effectiveCategory(for: session)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(AIAgentTraceCategory.allCases, id: \.self) { category in
                    let count = session.events.lazy.filter {
                        $0.category == category && shouldShowInRawTrace($0)
                    }.count
                    Button {
                        selectedCategory = category
                        HapticManager.shared.light()
                    } label: {
                        HStack(spacing: 7) {
                            Text(category.localizedTitle)
                                .font(.subheadline.weight(.bold))
                            Text("\(count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .opacity(0.62)
                        }
                        .foregroundStyle(selected == category ? Color.black : Color.white.opacity(0.62))
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .background(selected == category ? category.tint : Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(String(count))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func shouldShowInRawTrace(_ event: AIAgentTraceEvent) -> Bool {
        switch event.metadata["recordType"] {
        case "local-coreml-inference", "local-tuning-result", "cached-tuning-result":
            return false
        default:
            return true
        }
    }

    private func eventRow(_ event: AIAgentTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(event.level.tint)
                    .frame(width: 7, height: 7)

                Text(event.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text(event.timestamp.agentTraceTimeText)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))

                Button {
                    UIPasteboard.general.string = event.detail
                    HapticManager.shared.success()
                } label: {
                    MonoSemanticIcon(
                        semantic: .copy,
                        fallback: .save,
                        size: 12,
                        color: .white.opacity(0.42)
                    )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "agent_trace_copy_event"))
            }

            if let stage = event.stage {
                Text(stage.localizedTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(stage.tint)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .background(stage.tint.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(event.detail)
                .font(effectiveEventFont(event))
                .foregroundStyle(.white.opacity(0.68))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !event.metadata.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(event.metadata.keys.sorted(), id: \.self) { key in
                        if let value = event.metadata[key] {
                            Text("\(key) = \(value)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.34))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.category.tint.opacity(0.78))
                .frame(width: 3)
                .padding(.vertical, 11)
        }
    }

    private func effectiveEventFont(_ event: AIAgentTraceEvent) -> Font {
        event.category == .conversation ? .caption.monospaced() : .caption
    }

    private func mergedMetadata(_ session: AIAgentTraceSession) -> [String: String] {
        session.events.reduce(into: [String: String]()) { result, event in
            for (key, value) in event.metadata where !value.isEmpty {
                result[key] = value
            }
        }
    }

    private func metadataValue(_ metadata: [String: String], keys: [String]) -> String? {
        keys.lazy.compactMap { metadata[$0] }.first { !$0.isEmpty }
    }

    private func metadataList(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        let normalized = rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "|", with: ",")
        return normalized
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            }
            .filter { !$0.isEmpty }
    }

    private func metadataAssignments(_ rawValue: String?) -> [String: String] {
        metadataList(rawValue).reduce(into: [String: String]()) { result, item in
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
            result[parts[0]] = parts[1]
        }
    }

    private func booleanText(_ value: String?) -> String {
        guard let value else { return unavailableText }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "enabled", "required", "applied", "reused":
            return String(localized: "agent_trace_yes")
        case "0", "false", "no", "disabled", "none":
            return String(localized: "agent_trace_no")
        default:
            return value
        }
    }

    private func localizedSource(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bundled": return String(localized: "audio_agent_source_bundled")
        case "cached", "cache": return String(localized: "audio_agent_source_cache")
        case "server", "remote": return String(localized: "audio_agent_source_server")
        case "device", "local": return String(localized: "audio_agent_source_device")
        default: return rawValue
        }
    }

    private func localizedSkillTitle(_ skillID: String) -> String {
        switch skillID {
        case MonoAudioAgentBuiltInSkill.measurementEvidence.rawValue:
            return String(localized: "audio_agent_skill_measurement")
        case MonoAudioAgentBuiltInSkill.deviceCoordination.rawValue:
            return String(localized: "audio_agent_skill_device")
        case MonoAudioAgentBuiltInSkill.headroomGuard.rawValue:
            return String(localized: "audio_agent_skill_headroom")
        case MonoAudioAgentBuiltInSkill.phaseGuard.rawValue:
            return String(localized: "audio_agent_skill_phase")
        case MonoAudioAgentBuiltInSkill.outputValidation.rawValue:
            return String(localized: "audio_agent_skill_validation")
        case MonoAudioAgentBuiltInSkill.artistReference.rawValue:
            return String(localized: "audio_agent_skill_artist")
        case MonoAudioAgentBuiltInSkill.vocalReference.rawValue:
            return String(localized: "audio_agent_skill_vocal")
        default:
            return skillID.replacingOccurrences(of: "custom.", with: "")
        }
    }
}

@MainActor
private struct AIAgentTraceModelRecordView: View {
    let event: AIAgentTraceEvent

    private var statusText: String {
        [event.metadata["modelSource"], event.metadata["provider"], event.metadata["model"]]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    DeveloperDiagnosticStatus(status: statusText)

                    if !event.metadata.isEmpty {
                        detailSection(title: String(localized: "agent_trace_model_record_metadata")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(event.metadata.keys.sorted(), id: \.self) { key in
                                    if let value = event.metadata[key] {
                                        Text("\(key) = \(value)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.white.opacity(0.52))
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    detailSection(title: String(localized: "agent_trace_model_record_payload")) {
                        Text(event.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.72))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FloatingBarBottomSpacer()
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                .padding(.top, 8)
                .iPadContentWidth(SettingsPageLayout.contentWidth)
            }
            .scrollIndicators(.hidden)
        }
        .developerDiagnosticPageChrome(title: event.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = event.detail
                    HapticManager.shared.success()
                } label: {
                    MonoSemanticIcon(
                        semantic: .copy,
                        fallback: .save,
                        size: 14,
                        color: .white.opacity(0.7)
                    )
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "agent_trace_copy_event"))
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.94))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 0.7)
        }
    }
}

private extension AIAgentTraceCategory {
    var localizedTitle: String {
        switch self {
        case .conversation: return String(localized: "agent_trace_conversation")
        case .reasoning: return String(localized: "agent_trace_reasoning")
        case .skill: return String(localized: "agent_trace_skill")
        }
    }

    var tint: Color {
        switch self {
        case .conversation: return .cyan
        case .reasoning: return .orange
        case .skill: return .purple
        }
    }
}

private extension AIAgentTraceStage {
    var monoGlyphSemantic: MonoGlyphSemantic {
        switch self {
        case .configuration: return .agentTraceStageConfiguration
        case .skills: return .agentTraceStageSkills
        case .measurement: return .agentTraceStageMeasurement
        case .model: return .agentTraceStageModel
        case .tool: return .agentTraceStageTool
        case .validation: return .agentTraceStageValidation
        case .compilation: return .agentTraceStageCompilation
        case .application: return .agentTraceStageApplication
        case .fallback: return .agentTraceStageFallback
        case .completion: return .agentTraceStageCompletion
        }
    }

    var localizedTitle: String {
        switch self {
        case .configuration: return String(localized: "agent_trace_stage_configuration")
        case .skills: return String(localized: "agent_trace_stage_skills")
        case .measurement: return String(localized: "agent_trace_stage_measurement")
        case .model: return String(localized: "agent_trace_stage_model")
        case .tool: return String(localized: "agent_trace_stage_tool")
        case .validation: return String(localized: "agent_trace_stage_validation")
        case .compilation: return String(localized: "agent_trace_stage_compilation")
        case .application: return String(localized: "agent_trace_stage_application")
        case .fallback: return String(localized: "agent_trace_stage_fallback")
        case .completion: return String(localized: "agent_trace_stage_completion")
        }
    }

    var tint: Color {
        switch self {
        case .configuration: return .cyan
        case .skills: return .purple
        case .measurement: return .blue
        case .model: return .indigo
        case .tool: return .orange
        case .validation: return .mint
        case .compilation: return .teal
        case .application: return .green
        case .fallback: return .orange
        case .completion: return .gray
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .configuration: return .settings
        case .skills: return .sparkle
        case .measurement: return .waveform
        case .model: return .logDebug
        case .tool: return .equalizer
        case .validation: return .checkmark
        case .compilation: return .layers
        case .application: return .audioWave
        case .fallback: return .warning
        case .completion: return .logSuccess
        }
    }
}

private extension AIAgentTraceStatus {
    var localizedTitle: String {
        switch self {
        case .running: return String(localized: "agent_trace_status_running")
        case .completed: return String(localized: "agent_trace_status_completed")
        case .failed: return String(localized: "agent_trace_status_failed")
        case .cancelled: return String(localized: "agent_trace_status_cancelled")
        }
    }

    var tint: Color {
        switch self {
        case .running: return .cyan
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

private extension AIAgentTraceLevel {
    var tint: Color {
        switch self {
        case .info: return .cyan
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private extension Date {
    var agentTraceDateText: String {
        formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
    }

    var agentTraceTimeText: String {
        formatted(.dateTime.hour().minute().second())
    }
}
