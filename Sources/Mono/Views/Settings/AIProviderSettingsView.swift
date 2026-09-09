import SwiftUI

@MainActor
struct AIProviderSettingsView: View {
    @ObservedObject private var store = AIPersonalProviderStore.shared
    @State private var draft = AIPersonalProviderSettings()
    @State private var hasLoaded = false
    @State private var message: String?
    @State private var isError = false
    @State private var connectionTestID: UUID?
    @State private var isTesting = false

    var body: some View {
        ZStack {
            ThemedSettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "ai_config_title"),
                        eyebrow: "AI",
                        icon: .sparkle
                    )

                    VStack(spacing: SettingsPageLayout.sectionSpacing) {
                        SettingsSection(title: String(localized: "ai_config_service")) {
                            SettingsToggleRow(
                                icon: .sparkle,
                                title: String(localized: "ai_tuning_service_other_ai"),
                                subtitle: nil,
                                isOn: $draft.isEnabled
                            )
                        }
                        configurationSection
                        SettingsSection(title: String(localized: "ai_resonance_training_title")) {
                            Text(String(localized: "ai_resonance_training_notice"))
                                .font(.callout)
                                .foregroundStyle(themedSettingsSecondaryColor())
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        SettingsSection(title: String(localized: "ai_provider_connection_section")) {
                            SettingsButtonRow(
                                icon: .refresh,
                                title: String(localized: isTesting ? "ai_provider_testing" : "ai_provider_test")
                            ) {
                                message = nil
                                isTesting = true
                                connectionTestID = UUID()
                            }
                            .disabled(isTesting)
                            Divider()
                            SettingsButtonRow(icon: .save, title: String(localized: "common_save")) {
                                save()
                            }
                            .disabled(isTesting)
                        }
                        if let message {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(isError ? Color.red : themedSettingsSecondaryColor())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 24)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .onAppear {
            guard !hasLoaded else { return }
            draft = store.settings
            hasLoaded = true
        }
        .onChange(of: draft) { _, _ in
            connectionTestID = nil
            isTesting = false
            message = nil
        }
        .task(id: connectionTestID) {
            guard let requestID = connectionTestID else { return }
            await testConnection(requestID: requestID)
        }
    }

    private var configurationSection: some View {
        SettingsSection(title: String(localized: "ai_provider_protocol_section")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "ai_provider_protocol"))
                    .font(.callout)
                    .foregroundStyle(themedSettingsSecondaryColor())
                Picker(String(localized: "ai_provider_protocol"), selection: $draft.configuration.wireProtocol) {
                    ForEach(AIWireProtocol.allCases.filter(\.supportsCustomEndpoint)) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(themedSettingsPrimaryColor())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            inputRow(title: String(localized: "ai_provider_endpoint"), text: $draft.configuration.baseURL, keyboard: .URL)
            Divider()
            inputRow(title: "API Key", text: $draft.apiKey, secure: true)
            Divider()
            inputRow(title: String(localized: "ai_provider_model"), text: $draft.configuration.model)
        }
    }

    private func inputRow(
        title: String,
        text: Binding<String>,
        secure: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(themedSettingsSecondaryColor())
            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(.body.monospaced())
            .foregroundStyle(themedSettingsPrimaryColor())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .frame(minHeight: 44)
            .accessibilityLabel(title)
        }
        .padding(16)
    }

    private func save() {
        do {
            if AITuningServiceStore.shared.settings.service == .custom {
                var tuningDraft = draft
                tuningDraft.isEnabled = true
                _ = try tuningDraft.validated()
            }
            try store.save(draft)
            isError = false
            message = String(localized: "ai_config_saved")
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    private func testConnection(requestID: UUID) async {
        defer {
            if connectionTestID == requestID { isTesting = false }
        }
        do {
            var testDraft = draft
            testDraft.isEnabled = true
            let settings = try testDraft.validated()
            let text = try await AIProviderClient().generate(
                systemPrompt: "Reply with OK.",
                userPrompt: "OK",
                configuration: settings.configuration,
                apiKey: settings.apiKey,
                options: AIGenerationOptions(temperature: 0, maxOutputTokens: 128)
            )
            try Task.checkCancellation()
            guard connectionTestID == requestID else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIEqualizerError.invalidResponse
            }
            isError = false
            message = String(localized: "ai_provider_connected")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, connectionTestID == requestID else { return }
            isError = true
            message = error.localizedDescription
        }
    }
}
