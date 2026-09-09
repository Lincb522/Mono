import SwiftUI
import UIKit

private extension MonoAudioAgentBuiltInSkill {
    var monoGlyphSemantic: MonoGlyphSemantic {
        switch self {
        case .measurementEvidence: return .agentSkillMeasurement
        case .deviceCoordination: return .agentSkillDeviceCoordination
        case .headroomGuard: return .agentSkillHeadroomGuard
        case .phaseGuard: return .agentSkillPhaseGuard
        case .outputValidation: return .agentSkillOutputValidation
        case .artistReference: return .agentSkillArtistReference
        case .vocalReference: return .agentSkillVocalReference
        }
    }
}

@MainActor
struct MonoAudioAgentSettingsView: View {
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var agent = AIEqualizerAgent.shared
    @StateObject private var skills = MonoAudioAgentSkillStore.shared
    @StateObject private var coverColors = CoverColorExtractor()

    private var accent: Color {
        normalizedAudioAgentAccent(coverColors.dominantColor)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MonoSoundCenterLayout(size: proxy.size)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    statusHeader(layout: layout)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: layout.isCompactHeight ? 18 : 24) {
                            behaviorSection(layout: layout)
                            builtInSkillsSection(layout: layout)
                            customSkillsSection(layout: layout)
                            runtimeSection(layout: layout)
                        }
                        .padding(.horizontal, layout.horizontalInset)
                        .padding(.top, layout.isCompactHeight ? 10 : 14)
                        .padding(.bottom, layout.isCompactHeight ? 24 : 36)
                        .frame(width: layout.workspaceMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: layout.contentMaxWidth, height: proxy.size.height, alignment: .top)
                .clipped()

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background { backdrop }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        .onAppear(perform: refreshAccent)
        .onChange(of: player.currentSong?.id) { _, _ in refreshAccent() }
        .task {
            await skills.refreshRemoteConfiguration()
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)
            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.16)
                    .blur(radius: 70)
                    .saturation(0.72)
                    .opacity(0.22)
                    .clipped()
            }
            Color.black.opacity(0.58)
        }
        .ignoresSafeArea()
    }

    private func statusHeader(layout: MonoSoundCenterLayout) -> some View {
        HStack(spacing: layout.isCompactWidth ? 10 : 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: layout.isCompactHeight ? 10 : 12,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.06))

                MonoIcon(
                    icon: .sparkle,
                    size: layout.isCompactHeight ? 19 : 22,
                    color: accent
                )
                .monoIconArtwork(MonoGlyphSemantic.audioAgent.rawValue)
            }
            .frame(width: layout.coverSize, height: layout.coverSize)
            .overlay {
                RoundedRectangle(
                    cornerRadius: layout.isCompactHeight ? 10 : 12,
                    style: .continuous
                )
                .stroke(accent.opacity(0.3), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: layout.isCompactHeight ? 2 : 4) {
                Text(agentStatusText)
                    .font(.system(
                        size: layout.isCompactHeight ? 15.5 : 17,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Circle()
                    .fill(agent.isAutomaticTuningActive ? accent : .white.opacity(0.28))
                    .frame(width: 6, height: 6)
                Text(agent.isAutomaticTuningActive
                     ? String(localized: "audio_agent_active")
                     : String(localized: "settings_off"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.28))
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            )
        }
        .padding(.horizontal, layout.horizontalInset)
        .padding(.top, layout.isCompactHeight ? 3 : 6)
        .padding(.bottom, layout.isCompactHeight ? 7 : 10)
        .frame(width: layout.contentMaxWidth)
        .background(Color.black.opacity(0.14))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private func behaviorSection(layout: MonoSoundCenterLayout) -> some View {
        settingsSection(title: String(localized: "audio_agent_behavior"), layout: layout) {
            toggleRow(
                icon: .sparkle,
                artwork: .agentAutoTuning,
                title: String(localized: "ai_auto_tuning"),
                detail: String(localized: "audio_agent_auto_detail"),
                isOn: Binding(
                    get: { agent.isAutomaticTuningActive },
                    set: { agent.automaticConfigurationEnabled = $0 }
                ),
                layout: layout
            )
            .disabled(!agent.tuningServiceStore.settings.isEnabled)
            rowDivider
            NavigationLink {
                MonoAudioAdaptiveLearningView(accent: accent)
            } label: {
                navigationRow(
                    icon: .history,
                    artwork: .agentAdaptiveLearning,
                    title: String(localized: "ai_learning_title"),
                    detail: String(localized: "audio_agent_learning_detail"),
                    value: learningStatusText,
                    layout: layout
                )
            }
            .buttonStyle(.plain)
            rowDivider
            toggleRow(
                icon: .info,
                artwork: .agentPlayerStatus,
                title: String(localized: "audio_agent_player_status"),
                detail: String(localized: "audio_agent_player_status_detail"),
                isOn: $agent.showsPlayerTuningStatus,
                layout: layout
            )
        }
    }

    private func builtInSkillsSection(layout: MonoSoundCenterLayout) -> some View {
        settingsSection(title: String(localized: "audio_agent_builtin_skills"), layout: layout) {
            ForEach(Array(MonoAudioAgentBuiltInSkill.allCases.enumerated()), id: \.element.id) { index, skill in
                builtInSkillRow(skill, layout: layout)
                if index < MonoAudioAgentBuiltInSkill.allCases.count - 1 {
                    rowDivider
                }
            }
        }
    }

    private func customSkillsSection(layout: MonoSoundCenterLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "audio_agent_custom_skills"))
                    .font(.system(
                        size: layout.isCompactHeight ? 10.5 : 11.5,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                Text("\(skills.enabledCustomSkillCount)/\(MonoAudioAgentSkillStore.maximumEnabledCustomSkillCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 0) {
                if skills.resolvedCustomSkills.isEmpty {
                    HStack(spacing: 12) {
                        MonoSemanticIcon(semantic: .agentCustomSkill, fallback: .equalizer, size: 18, color: accent)
                        Text(String(localized: "audio_agent_custom_empty"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(Array(skills.resolvedCustomSkills.enumerated()), id: \.element.id) { index, skill in
                        resolvedCustomSkillRow(skill, layout: layout)
                        if index < skills.resolvedCustomSkills.count - 1 { rowDivider }
                    }
                    rowDivider
                }

                NavigationLink {
                    MonoAudioCustomSkillEditorView(skill: nil, accent: accent)
                } label: {
                    HStack(spacing: 12) {
                        MonoSemanticIcon(semantic: .agentAddCustomSkill, fallback: .add, size: 17, color: accent)
                        Text(String(localized: "audio_agent_add_custom_skill"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        MonoIcon(icon: .chevronRight, size: 12, color: .white.opacity(0.34))
                    }
                    .frame(minHeight: layout.isCompactHeight ? 48 : 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(skills.customSkills.count >= MonoAudioAgentSkillStore.maximumCustomSkillCount)
                .opacity(skills.customSkills.count >= MonoAudioAgentSkillStore.maximumCustomSkillCount ? 0.4 : 1)
            }
            .padding(.horizontal, layout.isCompactWidth ? 12 : 14)
            .background(sectionSurface)
        }
    }

    private func runtimeSection(layout: MonoSoundCenterLayout) -> some View {
        settingsSection(title: String(localized: "audio_agent_runtime"), layout: layout) {
            valueRow(
                title: String(localized: "audio_agent_knowledge"),
                value: MonoAudioTuningKnowledge.version,
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_tool"),
                value: MonoAudioTuningTool.version,
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_model_context"),
                value: String(localized: "audio_agent_context_compact"),
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_skill_source"),
                value: configurationSourceText,
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_sync_status"),
                value: syncStatusText,
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_skill_revision"),
                value: skills.skillRevision,
                layout: layout
            )
            rowDivider
            valueRow(
                title: String(localized: "audio_agent_skill_fingerprint"),
                value: String(skills.skillFingerprint.prefix(12)),
                layout: layout
            )
        }
    }

    private func builtInSkillRow(
        _ skill: MonoAudioAgentBuiltInSkill,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(
                icon: skill.isRequired ? .lock : .equalizer,
                size: 17,
                color: skill.isRequired ? .white.opacity(0.52) : accent
            )
            .monoIconArtwork(skill.monoGlyphSemantic.rawValue)
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: String.LocalizationValue(skill.titleKey)))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text(String(localized: String.LocalizationValue(skill.detailKey)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if skill.isRequired {
                Text(String(localized: "audio_agent_required"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.24))
                            .overlay {
                                Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                    )
            } else {
                Toggle(String(localized: String.LocalizationValue(skill.titleKey)), isOn: Binding(
                    get: { skills.isEnabled(skill) },
                    set: { skills.setEnabled($0, for: skill) }
                ))
                .labelsHidden()
                .tint(accent)
            }
        }
        .padding(.vertical, layout.isCompactHeight ? 11 : 13)
    }

    @ViewBuilder
    private func resolvedCustomSkillRow(
        _ skill: MonoAudioResolvedCustomSkill,
        layout: MonoSoundCenterLayout
    ) -> some View {
        if let localID = skill.localID,
           let localSkill = skills.customSkills.first(where: { $0.id == localID }) {
            HStack(spacing: 12) {
                NavigationLink {
                    MonoAudioCustomSkillEditorView(skill: localSkill, accent: accent)
                } label: {
                    HStack(spacing: 12) {
                        MonoSemanticIcon(semantic: .agentEditCustomSkill, fallback: .equalizer, size: 17, color: accent)
                            .frame(width: 22)
                        skillDescription(skill, sourceKey: "audio_agent_source_device")
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle(skill.name, isOn: Binding(
                    get: { skill.isEnabled },
                    set: { skills.setCustomSkillEnabled($0, id: localID) }
                ))
                .labelsHidden()
                .tint(accent)
            }
            .padding(.vertical, layout.isCompactHeight ? 11 : 13)
        } else {
            HStack(spacing: 12) {
                MonoSemanticIcon(semantic: .agentManagedSkill, fallback: .lock, size: 17, color: accent)
                    .frame(width: 22)
                skillDescription(skill, sourceKey: "audio_agent_source_server")
                Spacer(minLength: 8)
                Text(skill.isEnabled
                     ? String(localized: "audio_agent_active")
                     : String(localized: "settings_off"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(skill.isEnabled ? 0.62 : 0.34))
            }
            .padding(.vertical, layout.isCompactHeight ? 11 : 13)
        }
    }

    private func skillDescription(
        _ skill: MonoAudioResolvedCustomSkill,
        sourceKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(String(localized: String.LocalizationValue(sourceKey)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(skill.instruction)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(2)
            if skill.isLimited {
                Text(String(localized: "audio_agent_skill_limit_reached"))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.72))
            }
        }
    }

    private func toggleRow(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon: icon, size: 17, color: accent)
                .monoIconArtwork(artwork?.rawValue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Toggle(title, isOn: isOn).labelsHidden().tint(accent)
        }
        .padding(.vertical, layout.isCompactHeight ? 11 : 13)
    }

    private func valueRow(
        title: String,
        value: String,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minHeight: layout.isCompactHeight ? 44 : 48)
    }

    private func navigationRow(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        detail: String,
        value: String,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon: icon, size: 17, color: accent)
                .monoIconArtwork(artwork?.rawValue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            MonoIcon(icon: .chevronRight, size: 11, color: .white.opacity(0.3))
        }
        .padding(.vertical, layout.isCompactHeight ? 11 : 13)
        .contentShape(Rectangle())
    }

    private func settingsSection<Content: View>(
        title: String,
        layout: MonoSoundCenterLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(
                    size: layout.isCompactHeight ? 10.5 : 11.5,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(.white.opacity(0.62))
            VStack(spacing: 0) { content() }
                .padding(.horizontal, layout.isCompactWidth ? 12 : 14)
                .background(sectionSurface)
        }
    }

    private var sectionSurface: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 34)
    }

    private var agentStatusText: String {
        if agent.phase.isWorking { return String(localized: "mono_audio_tuning") }
        if let name = agent.proposal?.profileName { return name }
        return String(localized: "audio_agent_ready")
    }

    private var configurationSourceText: String {
        switch skills.configurationSource {
        case .bundled: return String(localized: "audio_agent_source_bundled")
        case .cached: return String(localized: "audio_agent_source_cache")
        case .server: return String(localized: "audio_agent_source_server")
        }
    }

    private var syncStatusText: String {
        switch skills.configurationSource {
        case .bundled: return String(localized: "audio_agent_sync_local")
        case .cached: return String(localized: "audio_agent_sync_cached")
        case .server: return String(localized: "audio_agent_sync_current")
        }
    }

    private var learningStatusText: String {
        guard agent.adaptiveLearningEnabled else { return String(localized: "settings_off") }
        return String(
            format: String(localized: "audio_agent_learning_count_value"),
            agent.learningEvidenceCount
        )
    }

    private func refreshAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(220).absoluteString)
    }
}

@MainActor
private struct MonoAudioCustomSkillEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var skills = MonoAudioAgentSkillStore.shared
    private let skillID: UUID?
    private let accent: Color
    @State private var name: String
    @State private var instruction: String
    @State private var isEnabled: Bool
    @State private var showsDeleteConfirmation = false

    init(skill: MonoAudioCustomSkill?, accent: Color) {
        skillID = skill?.id
        self.accent = accent
        _name = State(initialValue: skill?.name ?? "")
        _instruction = State(initialValue: skill?.instruction ?? "")
        _isEnabled = State(initialValue: skill?.isEnabled ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "101114"),
            dark: .white
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MonoSoundCenterLayout(size: proxy.size)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.isCompactHeight ? 18 : 24) {
                        editorField(
                            title: String(localized: "audio_agent_skill_name"),
                            layout: layout
                        ) {
                            TextField(
                                String(localized: "audio_agent_skill_name_placeholder"),
                                text: $name
                            )
                            .textInputAutocapitalization(.never)
                            .monoTextInputBehavior()
                            .onChange(of: name) { _, value in
                                name = String(value.prefix(MonoAudioAgentSkillStore.maximumNameLength))
                            }
                        }

                        editorField(
                            title: String(localized: "audio_agent_skill_instruction"),
                            layout: layout
                        ) {
                            TextEditor(text: $instruction)
                                .scrollContentBackground(.hidden)
                                .monoTextInputBehavior()
                                .frame(minHeight: 150)
                                .onChange(of: instruction) { _, value in
                                    instruction = String(
                                        value.prefix(MonoAudioAgentSkillStore.maximumInstructionLength)
                                    )
                                }
                        }

                        HStack(spacing: 12) {
                            MonoSemanticIcon(semantic: .agentEditCustomSkill, fallback: .equalizer, size: 17, color: accent)
                                .frame(width: 22)
                            Text(String(localized: "audio_agent_skill_enabled"))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Toggle(String(localized: "audio_agent_skill_enabled"), isOn: $isEnabled)
                                .labelsHidden()
                                .tint(accent)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: layout.isCompactHeight ? 48 : 52)
                        .background(editorSurface)

                        Button {
                            guard skills.saveCustomSkill(
                                id: skillID,
                                name: name,
                                instruction: instruction,
                                isEnabled: isEnabled
                            ) != nil else { return }
                            dismiss()
                        } label: {
                            Text(String(localized: "save"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(accentForeground)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    accent.opacity(canSave ? 0.88 : 0.32),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)

                        if let skillID {
                            Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                                Text(String(localized: "audio_agent_delete_skill"))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .alert(
                                String(localized: "audio_agent_delete_skill_title"),
                                isPresented: $showsDeleteConfirmation
                            ) {
                                Button(String(localized: "cancel"), role: .cancel) {}
                                Button(String(localized: "delete"), role: .destructive) {
                                    skills.deleteCustomSkill(id: skillID)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, layout.horizontalInset)
                    .padding(.top, layout.isCompactHeight ? 10 : 14)
                    .padding(.bottom, layout.isCompactHeight ? 24 : 36)
                    .frame(width: layout.workspaceMaxWidth)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(width: layout.contentMaxWidth)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background { editorBackdrop }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
    }

    private func editorField<Content: View>(
        title: String,
        layout: MonoSoundCenterLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(
                    size: layout.isCompactHeight ? 10.5 : 11.5,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(.white.opacity(0.62))
            content()
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(13)
                .background(editorSurface)
        }
    }

    private var editorSurface: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private var editorBackdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)

            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.16)
                    .blur(radius: 70)
                    .saturation(0.72)
                    .opacity(0.22)
                    .clipped()
            }

            Color.black.opacity(0.58)
        }
        .ignoresSafeArea()
    }
}

private func normalizedAudioAgentAccent(_ color: Color) -> Color {
    let resolved = UIColor(color)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 1
    guard resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
        return Color(red: 0.48, green: 0.7, blue: 1)
    }
    return Color(
        hue: Double(hue),
        saturation: Double(saturation < 0.08 ? 0.18 : min(0.72, saturation)),
        brightness: Double(max(0.82, brightness)),
        opacity: Double(alpha)
    )
}
