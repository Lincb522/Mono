import SwiftUI

@MainActor
struct AIProviderDeveloperSettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case passed
        case failed(String)
    }

    @ObservedObject private var store = AIProviderConfigurationStore.shared
    @ObservedObject private var usageLimiter = AIUsageLimiter.shared
    @State private var testState: TestState = .idle
    @State private var discoveredModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelDiscoveryError: String?
    @State private var modelDiscoveryRequestID = UUID()
    @State private var remoteActionMessage: String?
    @State private var showsCloudSecrets = false
    @State private var resonanceModelRefreshID = UUID()

    private let client = AIProviderClient()

    var body: some View {
        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                VStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                    DeveloperDiagnosticStatus(status: store.wireProtocol.title)
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)

                    VStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                        SettingsSection(title: String(localized: "ai_provider_remote_section")) {
                            SettingsToggleRow(
                                icon: .cloud,
                                title: String(localized: "ai_provider_remote_enabled"),
                                subtitle: nil,
                                isOn: $store.distributionEnabled
                            )

                            developerDivider

                            inputRow(
                                title: String(localized: "ai_provider_remote_admin_token"),
                                text: $store.tokenAdminCredential,
                                secure: true,
                                prompt: "Token Admin"
                            )

                            developerDivider

                            SettingsInfoRow(
                                icon: remoteStatusIcon,
                                title: String(localized: "ai_provider_remote_status"),
                                value: remoteStatusText
                            )

                            developerDivider

                            SettingsButtonRow(
                                icon: .refresh,
                                title: String(localized: "ai_provider_remote_fetch"),
                                action: fetchPublishedConfiguration
                            )
                            .disabled(isRemoteActionRunning)

                            developerDivider

                            SettingsButtonRow(
                                icon: .save,
                                title: String(localized: "ai_provider_remote_publish"),
                                action: publishConfiguration
                            )
                            .disabled(isRemoteActionRunning || store.tokenAdminCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        resonanceConfigurationSection

                        cloudConfigurationSection

                        SettingsSection(title: String(localized: "ai_provider_protocol_section")) {
                            providerRow

                            if store.wireProtocol.supportsCustomEndpoint {
                                developerDivider
                                inputRow(
                                    title: String(localized: "ai_provider_endpoint"),
                                    text: $store.baseURL,
                                    secure: false,
                                    prompt: store.wireProtocol.defaultBaseURL
                                )
                            }

                            developerDivider
                            modelRow

                            if store.wireProtocol != .appleIntelligence {
                                developerDivider
                                inputRow(
                                    title: "API Key",
                                    text: $store.apiKey,
                                    secure: true,
                                    prompt: "sk-…"
                                )
                            }
                        }

                        if store.wireProtocol.supportsCustomEndpoint {
                            SettingsSection(title: String(localized: "ai_provider_request_section")) {
                                timeoutRow
                                developerDivider
                                inputRow(
                                    title: String(localized: "ai_provider_headers"),
                                    text: $store.customHeadersJSON,
                                    secure: false,
                                    prompt: "{\"Header\":\"Value\"}"
                                )

                                developerDivider
                                inputRow(
                                    title: String(localized: "ai_provider_model_list_endpoint"),
                                    text: $store.modelDiscoveryURL,
                                    secure: false,
                                    prompt: String(localized: "ai_provider_automatic")
                                )
                            }
                        }

                        SettingsSection(title: String(localized: "ai_usage_limits_section")) {
                            integerLimitRow(
                                title: String(localized: "ai_usage_daily_limit"),
                                value: $store.dailyRequestLimit,
                                range: 0...10_000
                            )

                            developerDivider

                            integerLimitRow(
                                title: String(localized: "ai_usage_hourly_limit"),
                                value: $store.hourlyRequestLimit,
                                range: 0...1_000
                            )

                            developerDivider

                            intervalLimitRow

                            developerDivider

                            usageStatusRow

                            developerDivider

                            SettingsButtonRow(
                                icon: .trash,
                                title: String(localized: "ai_usage_reset"),
                                action: usageLimiter.reset
                            )
                        }

                        SettingsSection(title: String(localized: "ai_provider_connection_section")) {
                            SettingsInfoRow(
                                icon: testStateIcon,
                                title: String(localized: "ai_provider_connection_status"),
                                value: testStateText
                            )

                            developerDivider

                            SettingsButtonRow(
                                icon: .refresh,
                                title: String(localized: "ai_provider_test"),
                                action: testConnection
                            )
                            .disabled(testState == .testing)

                            developerDivider

                            SettingsButtonRow(
                                icon: .refresh,
                                title: String(localized: "ai_provider_reset"),
                                action: resetConfiguration
                            )
                        }

                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
        }
        .developerDiagnosticPageChrome(title: String(localized: "ai_provider_settings_title"))
        .onAppear {
            usageLimiter.refresh()
        }
        .task(id: modelDiscoveryFingerprint) {
            await fetchModels(automatic: true)
        }
        .task(id: resonanceModelRefreshID) {
            await store.fetchPublishedResonanceModels()
        }
    }

    private var resonanceConfigurationSection: some View {
        SettingsSection(title: String(localized: "ai_resonance_section")) {
            SettingsToggleRow(
                icon: .waveform,
                title: String(localized: "ai_resonance_enabled"),
                subtitle: String(localized: "ai_resonance_distribution_description"),
                isOn: $store.resonanceEnabled
            )
            developerDivider
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "ai_resonance_cloud_model"))
                    .font(.rounded(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                ForEach(store.publishedResonanceModels) { model in
                    resonanceModelRow(model)
                }
                if !store.resonanceModelID.isEmpty,
                   !store.publishedResonanceModels.contains(where: { $0.id == store.resonanceModelID }) {
                    Text(String(localized: "ai_resonance_selected_model_unavailable"))
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = store.resonanceModelsError {
                    Text(error).font(.callout).foregroundStyle(.red)
                } else if !store.isLoadingResonanceModels, store.publishedResonanceModels.isEmpty {
                    Text(String(localized: "ai_resonance_no_published_models"))
                        .font(.callout).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            developerDivider
            SettingsButtonRow(
                icon: .refresh,
                title: String(localized: store.isLoadingResonanceModels
                              ? "ai_resonance_loading_models" : "ai_resonance_refresh_models")
            ) {
                resonanceModelRefreshID = UUID()
            }
            .disabled(store.isLoadingResonanceModels)
        }
    }

    private func resonanceModelRow(_ model: AudioTrainingModelInstallDescriptor) -> some View {
        let selected = store.resonanceModelID == model.id
        let publishedSelection = store.publishedConfiguration?.resonance?.model?.id
            ?? store.remoteConfiguration?.resonance?.model?.id
        return Button {
            store.resonanceModelID = model.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                    if let release = model.release {
                        Text(String(format: String(localized: "ai_resonance_published_at"), release.publicationDateText))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                        if !release.summary.isEmpty {
                            Text(release.summary)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    if publishedSelection == model.id {
                        Text(String(localized: "ai_resonance_cloud_selected_model"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    MonoIcon(icon: .checkmark, size: 16, color: .cyan)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var providerRow: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: .sparkle)
            Text(String(localized: "ai_provider_protocol"))
                .font(.rounded(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Menu {
                Picker("", selection: providerSelection) {
                    ForEach(AIWireProtocol.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(store.wireProtocol.title)
                        .lineLimit(1)
                    MonoIcon(icon: .chevronDown, size: 10, color: .white.opacity(0.46))
                }
                .font(.rounded(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.46))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var providerSelection: Binding<AIWireProtocol> {
        Binding(
            get: { store.wireProtocol },
            set: { value in
                store.wireProtocol = value
                store.useProtocolDefaults()
                discoveredModels = []
                modelDiscoveryError = nil
                testState = .idle
            }
        )
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(String(localized: "ai_provider_model"))
                    .font(.rounded(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.46))
                Spacer()
                if isLoadingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        MonoIcon(icon: .refresh, size: 13, color: .white.opacity(0.46))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField(store.wireProtocol.defaultModel, text: $store.model)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !discoveredModels.isEmpty {
                    Menu {
                        ForEach(discoveredModels, id: \.self) { model in
                            Button(model) { store.model = model }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("\(discoveredModels.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            MonoIcon(icon: .chevronDown, size: 10, color: .white.opacity(0.46))
                        }
                        .foregroundColor(.white.opacity(0.46))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            if let modelDiscoveryError {
                Text(modelDiscoveryError)
                    .font(.rounded(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else if !discoveredModels.isEmpty {
                Text(String(format: String(localized: "ai_provider_models_loaded"), discoveredModels.count))
                    .font(.rounded(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.46))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func inputRow(
        title: String,
        text: Binding<String>,
        secure: Bool,
        prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.rounded(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.46))

            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var timeoutRow: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: .clock)
            Text(String(localized: "ai_provider_timeout"))
                .font(.rounded(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Stepper(value: $store.timeout, in: 10...120, step: 5) {
                Text("\(Int(store.timeout))s")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
                    .frame(minWidth: 42, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func integerLimitRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.rounded(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Stepper(value: value, in: range) {
                Text(value.wrappedValue == 0
                     ? String(localized: "ai_usage_unlimited")
                     : "\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var intervalLimitRow: some View {
        HStack(spacing: 12) {
            Text(String(localized: "ai_usage_minimum_interval"))
                .font(.rounded(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Stepper(value: $store.minimumRequestInterval, in: 0...3_600, step: 5) {
                Text(store.minimumRequestInterval == 0
                     ? String(localized: "ai_usage_unlimited")
                     : "\(Int(store.minimumRequestInterval))s")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
                    .frame(minWidth: 54, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var usageStatusRow: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: .chart)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "ai_usage_current"))
                    .font(.rounded(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(String(
                    format: String(localized: "ai_usage_current_format"),
                    usageLimiter.snapshot.usedToday,
                    usageLimiter.snapshot.usedThisHour
                ))
                .font(.rounded(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.46))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var modelDiscoveryFingerprint: String {
        [
            store.wireProtocol.rawValue,
            store.baseURL,
            store.modelDiscoveryURL,
            String(store.apiKey.hashValue)
        ].joined(separator: "|")
    }

    private func fetchModels(automatic: Bool = false) async {
        if automatic {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }

        let normalizedKey = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if automatic, store.wireProtocol.requiresAPIKey, normalizedKey.isEmpty {
            discoveredModels = []
            modelDiscoveryError = nil
            return
        }

        let requestID = UUID()
        modelDiscoveryRequestID = requestID
        isLoadingModels = true
        modelDiscoveryError = nil
        defer {
            if modelDiscoveryRequestID == requestID {
                isLoadingModels = false
            }
        }

        do {
            let values = try await client.fetchModels(
                configuration: store.configuration,
                apiKey: store.apiKey
            )
            guard !Task.isCancelled, modelDiscoveryRequestID == requestID else { return }
            discoveredModels = values
            let current = store.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || (!values.isEmpty && !values.contains(current)) {
                let preferred = store.wireProtocol.defaultModel
                store.model = values.contains(preferred) ? preferred : (values.first ?? preferred)
            }
        } catch {
            guard !Task.isCancelled, modelDiscoveryRequestID == requestID else { return }
            discoveredModels = []
            modelDiscoveryError = error.localizedDescription
        }
    }

    private var developerDivider: some View {
        Divider().padding(.leading, 58)
    }

    private var cloudConfigurationSection: some View {
        SettingsSection(title: String(localized: "ai_provider_cloud_content_section")) {
            SettingsInfoRow(
                icon: remoteStatusIcon,
                title: String(localized: "ai_provider_remote_status"),
                value: cloudConfigurationStatus
            )

            if !cloudConfigurationFields.isEmpty {
                ForEach(cloudConfigurationFields) { field in
                    developerDivider
                    cloudConfigurationRow(field)
                }
            }
        }
    }

    private var cloudConfigurationStatus: String {
        if store.isPublishingRemoteConfiguration {
            return String(localized: "ai_provider_remote_publishing")
        }
        if store.isRefreshingRemoteConfiguration {
            return String(localized: "ai_provider_remote_fetching")
        }
        if store.publishedConfiguration?.enabled == true || store.remoteConfiguration?.enabled == true {
            return String(localized: "ai_provider_remote_active")
        }
        if store.publishedConfiguration != nil || store.remoteConfiguration != nil {
            return String(localized: "ai_provider_remote_disabled")
        }
        return String(localized: "ai_provider_cloud_not_loaded")
    }

    private var cloudConfigurationFields: [AIProviderCloudField] {
        if let value = store.publishedConfiguration {
            return [
                AIProviderCloudField(
                    id: "revision",
                    title: String(localized: "ai_provider_cloud_revision"),
                    value: displayRevision(value.revision)
                ),
                AIProviderCloudField(
                    id: "updatedAt",
                    title: String(localized: "ai_provider_cloud_updated_at"),
                    value: displayDate(value.updatedAt)
                ),
                AIProviderCloudField(
                    id: "resonance",
                    title: String(localized: "ai_resonance_section"),
                    value: value.resonance?.enabled == true
                        ? (value.resonance?.model?.version ?? "—")
                        : String(localized: "ai_provider_remote_disabled"),
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "protocol",
                    title: String(localized: "ai_provider_protocol"),
                    value: value.wireProtocol.title
                ),
                AIProviderCloudField(
                    id: "endpoint",
                    title: String(localized: "ai_provider_endpoint"),
                    value: displayValue(value.baseURL),
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "model",
                    title: String(localized: "ai_provider_model"),
                    value: displayValue(value.model),
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "modelEndpoint",
                    title: String(localized: "ai_provider_model_list_endpoint"),
                    value: displayValue(value.modelDiscoveryURL),
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "timeout",
                    title: String(localized: "ai_provider_timeout"),
                    value: "\(Int(value.timeout))s"
                ),
                AIProviderCloudField(
                    id: "headers",
                    title: String(localized: "ai_provider_headers"),
                    value: displayValue(value.customHeadersJSON),
                    isSensitive: !value.customHeadersJSON.isEmpty,
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "apiKey",
                    title: "API Key",
                    value: displayValue(value.apiKey),
                    isSensitive: !value.apiKey.isEmpty,
                    usesExpandedLayout: true
                ),
                AIProviderCloudField(
                    id: "dailyLimit",
                    title: String(localized: "ai_usage_daily_limit"),
                    value: displayLimit(value.usageLimits.dailyRequestLimit)
                ),
                AIProviderCloudField(
                    id: "hourlyLimit",
                    title: String(localized: "ai_usage_hourly_limit"),
                    value: displayLimit(value.usageLimits.hourlyRequestLimit)
                ),
                AIProviderCloudField(
                    id: "interval",
                    title: String(localized: "ai_usage_minimum_interval"),
                    value: value.usageLimits.minimumRequestInterval == 0
                        ? String(localized: "ai_usage_unlimited")
                        : "\(Int(value.usageLimits.minimumRequestInterval))s"
                )
            ]
        }

        guard let value = store.remoteConfiguration else { return [] }
        return [
            AIProviderCloudField(
                id: "revision",
                title: String(localized: "ai_provider_cloud_revision"),
                value: displayRevision(value.revision)
            ),
            AIProviderCloudField(
                id: "updatedAt",
                title: String(localized: "ai_provider_cloud_updated_at"),
                value: displayDate(value.updatedAt)
            ),
            AIProviderCloudField(
                id: "resonance",
                title: String(localized: "ai_resonance_section"),
                value: value.resonance?.enabled == true
                    ? (value.resonance?.model?.version ?? "—")
                    : String(localized: "ai_provider_remote_disabled"),
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "protocol",
                title: String(localized: "ai_provider_protocol"),
                value: value.wireProtocol.title
            ),
            AIProviderCloudField(
                id: "endpoint",
                title: String(localized: "ai_provider_endpoint"),
                value: displayValue(value.baseURL ?? ""),
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "model",
                title: String(localized: "ai_provider_model"),
                value: displayValue(value.model),
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "modelEndpoint",
                title: String(localized: "ai_provider_model_list_endpoint"),
                value: displayValue(value.modelDiscoveryURL ?? ""),
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "timeout",
                title: String(localized: "ai_provider_timeout"),
                value: "\(Int(value.timeout))s"
            ),
            AIProviderCloudField(
                id: "headers",
                title: String(localized: "ai_provider_headers"),
                value: displayValue(value.customHeadersJSON ?? ""),
                isSensitive: !(value.customHeadersJSON ?? "").isEmpty,
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "apiKey",
                title: "API Key",
                value: displayValue(value.apiKey ?? ""),
                isSensitive: !(value.apiKey ?? "").isEmpty,
                usesExpandedLayout: true
            ),
            AIProviderCloudField(
                id: "dailyLimit",
                title: String(localized: "ai_usage_daily_limit"),
                value: displayLimit(value.usageLimits.dailyRequestLimit)
            ),
            AIProviderCloudField(
                id: "hourlyLimit",
                title: String(localized: "ai_usage_hourly_limit"),
                value: displayLimit(value.usageLimits.hourlyRequestLimit)
            ),
            AIProviderCloudField(
                id: "interval",
                title: String(localized: "ai_usage_minimum_interval"),
                value: value.usageLimits.minimumRequestInterval == 0
                    ? String(localized: "ai_usage_unlimited")
                    : "\(Int(value.usageLimits.minimumRequestInterval))s"
            )
        ]
    }

    @ViewBuilder
    private func cloudConfigurationRow(_ field: AIProviderCloudField) -> some View {
        let displayedValue = field.isSensitive && !showsCloudSecrets
            ? maskedCloudValue(field.value)
            : field.value

        if field.usesExpandedLayout {
            VStack(alignment: .leading, spacing: 8) {
                cloudFieldHeader(field)
                Text(displayedValue)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(field.title)
                    .font(.rounded(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer(minLength: 16)
                Text(displayedValue)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    private func cloudFieldHeader(_ field: AIProviderCloudField) -> some View {
        HStack(spacing: 12) {
            Text(field.title)
                .font(.rounded(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.46))
            Spacer()
            if field.isSensitive {
                Button {
                    showsCloudSecrets.toggle()
                } label: {
                    Text(String(localized: showsCloudSecrets
                                ? "ai_provider_cloud_hide"
                                : "ai_provider_cloud_show"))
                        .font(.rounded(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func displayRevision(_ value: String) -> String {
        value == "unpublished" ? String(localized: "ai_provider_remote_not_published") : displayValue(value)
    }

    private func displayDate(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }

    private func displayLimit(_ value: Int) -> String {
        value == 0 ? String(localized: "ai_usage_unlimited") : "\(value)"
    }

    private func displayValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }

    private func maskedCloudValue(_ value: String) -> String {
        guard value != "—" else { return value }
        return String(repeating: "•", count: min(24, max(8, value.count)))
    }

    private var isRemoteActionRunning: Bool {
        store.isRefreshingRemoteConfiguration || store.isPublishingRemoteConfiguration
    }

    private var remoteStatusIcon: MonoIcon.IconType {
        if store.remoteError != nil { return .warning }
        if store.remoteConfiguration?.enabled == true { return .checkmark }
        return .cloud
    }

    private var remoteStatusText: String {
        if store.isPublishingRemoteConfiguration {
            return String(localized: "ai_provider_remote_publishing")
        }
        if store.isRefreshingRemoteConfiguration {
            return String(localized: "ai_provider_remote_fetching")
        }
        if let remoteActionMessage { return remoteActionMessage }
        if let error = store.remoteError, !error.isEmpty { return error }
        guard let remote = store.remoteConfiguration else {
            return String(localized: "ai_provider_remote_not_published")
        }
        return remote.enabled
            ? String(localized: "ai_provider_remote_active")
            : String(localized: "ai_provider_remote_disabled")
    }

    private func fetchPublishedConfiguration() {
        remoteActionMessage = nil
        Task {
            do {
                try await store.fetchPublishedConfiguration()
                remoteActionMessage = store.distributionEnabled
                    ? String(localized: "ai_provider_remote_active")
                    : String(localized: "ai_provider_remote_disabled")
                HapticManager.shared.success()
            } catch {
                remoteActionMessage = error.localizedDescription
                HapticManager.shared.error()
            }
        }
    }

    private func publishConfiguration() {
        remoteActionMessage = nil
        Task {
            do {
                try await store.publishDraftConfiguration()
                remoteActionMessage = String(localized: "ai_provider_remote_published")
                HapticManager.shared.success()
            } catch {
                remoteActionMessage = error.localizedDescription
                HapticManager.shared.error()
            }
        }
    }

    private var testStateIcon: MonoIcon.IconType {
        switch testState {
        case .passed: return .checkmark
        case .failed: return .warning
        default: return .logNetwork
        }
    }

    private var testStateText: String {
        switch testState {
        case .idle: return String(localized: "ai_provider_not_tested")
        case .testing: return String(localized: "ai_provider_testing")
        case .passed: return String(localized: "ai_provider_connected")
        case let .failed(message): return message
        }
    }

    private func testConnection() {
        testState = .testing
        Task {
            do {
                try await AIEqualizerAgent.shared.testProviderConnection()
                testState = .passed
                HapticManager.shared.success()
            } catch {
                testState = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    private func resetConfiguration() {
        store.resetDeveloperOverride()
        testState = .idle
    }
}

private struct AIProviderCloudField: Identifiable {
    let id: String
    let title: String
    let value: String
    var isSensitive = false
    var usesExpandedLayout = false
}
