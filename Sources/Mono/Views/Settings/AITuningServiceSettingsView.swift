import SwiftUI

@MainActor
struct AITuningServiceSettingsEntry: View {
    @ObservedObject private var store = AITuningServiceStore.shared

    var body: some View {
        SettingsSection(title: "AI") {
            SettingsRouteLinkRow(
                icon: .sparkle,
                title: String(localized: "ai_tuning_service_title"),
                value: store.settings.isEnabled ? store.settings.service.title : String(localized: "settings_off"),
                destination: .tuningService
            )
        }
    }
}

@MainActor
struct AITuningServiceSettingsView: View {
    @ObservedObject private var store = AITuningServiceStore.shared
    @ObservedObject private var providerStore = AIProviderConfigurationStore.shared
    @ObservedObject private var updates = AIResonanceUpdateStore.shared
    @State private var isModelReleaseExpanded = false
    @State private var refreshID = UUID()
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            ThemedSettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "ai_tuning_service_title"),
                        eyebrow: "AI",
                        icon: .sparkle
                    )
                    VStack(spacing: SettingsPageLayout.sectionSpacing) {
                        SettingsSection(title: String(localized: "ai_tuning_service_title")) {
                            SettingsToggleRow(
                                icon: .sparkle,
                                title: String(localized: "ai_tuning_service_enabled"),
                                subtitle: nil,
                                isOn: Binding(
                                    get: { store.settings.isEnabled },
                                    set: { store.update(isEnabled: $0) }
                                )
                            )
                        }
                        SettingsSection(title: String(localized: "ai_tuning_service_select")) {
                            ForEach(AITuningService.allCases) { service in
                                if service != .builtIn { Divider() }
                                serviceRow(service)
                            }
                        }
                        selectedServiceSettings
                        if !store.settings.isEnabled {
                            detailText(String(localized: "ai_tuning_service_disabled"))
                        }
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 24)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .task(id: refreshID) {
            isRefreshing = true
            defer { isRefreshing = false }
            await providerStore.refreshRemoteConfigurationIfNeeded(force: true)
            await updates.synchronize(remote: try? providerStore.distributedResonanceModel())
        }
    }

    private func serviceRow(_ service: AITuningService) -> some View {
        let selected = service == store.settings.service
        return Button {
            store.update(service: service)
        } label: {
            HStack(spacing: 12) {
                Text(service.title)
                    .font(.body)
                    .foregroundStyle(themedSettingsPrimaryColor())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if selected {
                    MonoIcon(icon: .checkmark, size: 16, color: themedSettingsPrimaryColor())
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var selectedServiceSettings: some View {
        switch store.settings.service {
        case .builtIn:
            SettingsSection(title: AITuningService.builtIn.title) {
                detailText(String(localized: "ai_tuning_service_builtin_detail"))
                    .padding(16)
            }
        case .custom:
            SettingsSection(title: AITuningService.custom.title) {
                SettingsRouteLinkRow(
                    icon: .sparkle,
                    title: String(localized: "ai_config_title"),
                    destination: .aiConfiguration
                )
            }
        case .resonance:
            SettingsSection(title: AITuningService.resonance.title) {
                VStack(alignment: .leading, spacing: 8) {
                    if let model = updates.tuningModel {
                        modelReleaseDisclosure(model)
                    } else {
                        detailText(String(localized: isRefreshing
                            ? "ai_tuning_service_model_loading" : "ai_resonance_model_unavailable"))
                    }
                    if updates.isUpdating {
                        ProgressView(String(localized: "ai_resonance_updating"))
                    }
                    if let error = updates.errorMessage {
                        detailText(error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                Divider()
                SettingsButtonRow(icon: .refresh, title: String(localized: "ai_tuning_service_model_refresh")) {
                    refreshID = UUID()
                }
                .disabled(isRefreshing)
            }
            SettingsSection(title: String(localized: "ai_resonance_availability_title")) {
                detailText(String(localized: "ai_resonance_availability_notice"))
                    .padding(16)
            }
        }
        if store.settings.service != .builtIn {
            SettingsSection(title: String(localized: "ai_resonance_training_title")) {
                detailText(String(localized: "ai_resonance_training_notice"))
                    .padding(16)
            }
        }
    }

    private func modelReleaseDisclosure(_ model: AudioTrainingModelInstallDescriptor) -> some View {
        DisclosureGroup(isExpanded: $isModelReleaseExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let release = model.release {
                    detailText(String(
                        format: String(localized: "ai_resonance_published_at"),
                        release.publicationDateText
                    ))
                    releaseInformation(release)
                } else {
                    detailText(String(localized: "audio_training_release_notes_empty"))
                }
            }
            .padding(.top, 8)
        } label: {
            Text(String(
                format: String(localized: "ai_lab_service_version_format"),
                AudioTrainingModelPresentation.versionText(model.version)
            ))
            .font(.body)
            .foregroundStyle(themedSettingsPrimaryColor())
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44, alignment: .leading)
        }
        .tint(themedSettingsPrimaryColor())
    }

    private func releaseInformation(_ release: AudioTrainingModelRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !release.summary.isEmpty {
                Text(String(localized: "audio_training_release_summary"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(themedSettingsPrimaryColor())
                detailText(release.summary)
            }
            Text(String(localized: "audio_training_release_changelog_short"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(themedSettingsPrimaryColor())
            detailText(release.changelog.isEmpty
                ? String(localized: "audio_training_release_notes_empty") : release.changelog)
        }
        .padding(.vertical, 8)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(themedSettingsSecondaryColor())
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
