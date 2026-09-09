import Foundation
@preconcurrency import Combine

@MainActor
final class AIProviderConfigurationStore: ObservableObject {
    static let shared = AIProviderConfigurationStore()

    private enum Keys {
        static let wireProtocol = "ai.eq.provider.protocol"
        static let baseURL = "ai.eq.provider.base-url"
        static let model = "ai.eq.provider.model"
        static let modelDiscoveryURL = "ai.eq.provider.model-discovery-url"
        static let timeout = "ai.eq.provider.timeout"
        static let customHeaders = "ai.eq.provider.custom-headers"
        static let legacyAPIKey = "ai.eq.provider.api-key"
        static let dailyRequestLimit = "ai.eq.usage.daily-limit"
        static let hourlyRequestLimit = "ai.eq.usage.hourly-limit"
        static let minimumRequestInterval = "ai.eq.usage.minimum-interval"
        static let cachedRemoteConfiguration = "ai.eq.remote.configuration"
        /// Keychain 条目：云端分发的 API key 永不落 UserDefaults 明文。
        static let remoteAPIKey = "ai.eq.remote.api-key"
        static let remoteLastFetchedAt = "ai.eq.remote.last-fetched-at"
        static let distributionEnabled = "ai.eq.remote.distribution-enabled"
        static let resonanceEnabled = "ai.eq.remote.resonance-enabled"
        static let resonanceModelID = "ai.eq.remote.resonance-model-id"
        static let tokenAdminCredential = "ai.eq.remote.token-admin-credential"
    }

    @Published var wireProtocol: AIWireProtocol {
        didSet {
            saveIfReady()
            loadAPIKeyForSelectedProtocolIfReady()
        }
    }
    @Published var baseURL: String { didSet { saveIfReady() } }
    @Published var model: String { didSet { saveIfReady() } }
    @Published var modelDiscoveryURL: String { didSet { saveIfReady() } }
    @Published var timeout: Double { didSet { saveIfReady() } }
    @Published var customHeadersJSON: String { didSet { saveIfReady() } }
    @Published var apiKey: String { didSet { saveKeyIfReady() } }
    @Published var dailyRequestLimit: Int { didSet { saveIfReady() } }
    @Published var hourlyRequestLimit: Int { didSet { saveIfReady() } }
    @Published var minimumRequestInterval: Double { didSet { saveIfReady() } }
    @Published var distributionEnabled: Bool { didSet { saveIfReady() } }
    @Published var resonanceEnabled: Bool { didSet { saveIfReady() } }
    @Published var resonanceModelID: String { didSet { saveIfReady() } }
    @Published private(set) var publishedResonanceModels: [AudioTrainingModelInstallDescriptor] = []
    @Published private(set) var isLoadingResonanceModels = false
    @Published private(set) var resonanceModelsError: String?
    @Published var tokenAdminCredential: String { didSet { saveAdminCredentialIfReady() } }
    @Published private(set) var remoteConfiguration: AIRemoteAIConfiguration?
    @Published private(set) var publishedConfiguration: AIAdminProviderConfiguration?
    @Published private(set) var remoteLastFetchedAt: Date?
    @Published private(set) var remoteError: String?
    @Published private(set) var isRefreshingRemoteConfiguration = false
    @Published private(set) var isPublishingRemoteConfiguration = false

    private var isReady = false
    private var isLoadingAPIKey = false
    private var isLoadingAdminCredential = false
    private var remoteRefreshTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        let builtInProtocol = Self.builtInProtocol
        let selectedProtocol = defaults.string(forKey: Keys.wireProtocol)
            .flatMap(AIWireProtocol.init(rawValue:)) ?? builtInProtocol
        let initialBaseURL = defaults.object(forKey: Keys.baseURL) as? String
            ?? Self.defaultBaseURL(for: selectedProtocol)
        let storedModel = defaults.object(forKey: Keys.model) as? String
            ?? Self.defaultModel(for: selectedProtocol)
        let initialModel = Self.normalizedModel(
            storedModel,
            wireProtocol: selectedProtocol,
            baseURL: initialBaseURL
        )
        let initialModelDiscoveryURL = defaults.object(forKey: Keys.modelDiscoveryURL) as? String ?? ""
        let savedTimeout = defaults.double(forKey: Keys.timeout)
        let initialTimeout = savedTimeout > 0 ? savedTimeout : 45
        let initialCustomHeaders = defaults.object(forKey: Keys.customHeaders) as? String ?? ""
        let providerKey = KeychainHelper.loadString(key: Self.apiKeyStorageKey(for: selectedProtocol))
        let hasExplicitKeyOverride = defaults.bool(forKey: Self.apiKeyOverrideStorageKey(for: selectedProtocol))
        let initialKey = providerKey
            ?? KeychainHelper.loadString(key: Keys.legacyAPIKey)
            ?? (hasExplicitKeyOverride ? nil : Self.bundledAPIKey(for: selectedProtocol))
            ?? ""
        let initialRemoteConfiguration = Self.loadCachedRemoteConfiguration(defaults: defaults)
        let initialAdminCredential = KeychainHelper.loadString(key: Keys.tokenAdminCredential) ?? ""

        wireProtocol = selectedProtocol
        baseURL = initialBaseURL
        model = initialModel
        modelDiscoveryURL = initialModelDiscoveryURL
        timeout = initialTimeout
        customHeadersJSON = initialCustomHeaders
        apiKey = initialKey
        dailyRequestLimit = defaults.object(forKey: Keys.dailyRequestLimit) as? Int ?? 50
        hourlyRequestLimit = defaults.object(forKey: Keys.hourlyRequestLimit) as? Int ?? 20
        minimumRequestInterval = defaults.object(forKey: Keys.minimumRequestInterval) as? Double ?? 15
        distributionEnabled = defaults.object(forKey: Keys.distributionEnabled) as? Bool
            ?? initialRemoteConfiguration?.enabled
            ?? true
        resonanceEnabled = defaults.object(forKey: Keys.resonanceEnabled) as? Bool
            ?? initialRemoteConfiguration?.resonance?.enabled ?? false
        resonanceModelID = defaults.string(forKey: Keys.resonanceModelID)
            ?? initialRemoteConfiguration?.resonance?.model?.id ?? ""
        tokenAdminCredential = initialAdminCredential
        remoteConfiguration = initialRemoteConfiguration
        publishedConfiguration = nil
        remoteLastFetchedAt = defaults.object(forKey: Keys.remoteLastFetchedAt) as? Date
        remoteError = nil
        isReady = true

        if providerKey == nil, !initialKey.isEmpty {
            KeychainHelper.save(key: Self.apiKeyStorageKey(for: selectedProtocol), value: initialKey)
        }
    }

    var configuration: AIProviderConfiguration {
        AIProviderConfiguration(
            wireProtocol: wireProtocol,
            baseURL: baseURL,
            model: Self.normalizedModel(
                model,
                wireProtocol: wireProtocol,
                baseURL: baseURL
            ),
            modelDiscoveryURL: modelDiscoveryURL,
            timeout: min(120, max(10, timeout)),
            customHeadersJSON: customHeadersJSON
        )
    }

    func requestContext(usePublishedConfiguration: Bool = true) throws -> AIProviderRequestContext {
        if !usePublishedConfiguration {
            return AIProviderRequestContext(
                configuration: configuration,
                apiKey: apiKey,
                usageLimits: draftUsageLimits,
                persistsDiscoveredModel: true
            )
        }
        return try AIProviderRequestContext.resolve(personal: AIPersonalProviderStore.shared.settings) {
            builtInRequestContext()
        }
    }

    private func builtInRequestContext() -> AIProviderRequestContext {
        AIProviderRequestContext(
            configuration: requestConfiguration,
            apiKey: requestAPIKey,
            usageLimits: usageLimits,
            persistsDiscoveredModel: !isUsingRemoteConfiguration
        )
    }

    func tuningRequestContext(service: AITuningService) throws -> AIProviderRequestContext {
        switch service {
        case .builtIn:
            return builtInRequestContext()
        case .custom:
            var personal = AIPersonalProviderStore.shared.settings
            personal.isEnabled = true
            return try AIProviderRequestContext.resolve(personal: personal) { builtInRequestContext() }
        case .resonance:
            // Resonance requires a verified local model and cannot silently use a cloud provider.
            throw AIResonanceDistributionError.modelUnavailable
        }
    }

    var requestConfiguration: AIProviderConfiguration {
        guard let remote = activeRemoteConfiguration else { return configuration }
        let local = configuration
        let usesMatchingLocalProtocol = local.wireProtocol == remote.wireProtocol
        let remoteBaseURL = remote.baseURL
            ?? (usesMatchingLocalProtocol ? local.baseURL : Self.defaultBaseURL(for: remote.wireProtocol))
        return AIProviderConfiguration(
            wireProtocol: remote.wireProtocol,
            baseURL: remoteBaseURL,
            model: Self.normalizedModel(
                remote.model,
                wireProtocol: remote.wireProtocol,
                baseURL: remoteBaseURL
            ),
            modelDiscoveryURL: remote.modelDiscoveryURL
                ?? (usesMatchingLocalProtocol ? local.modelDiscoveryURL : ""),
            timeout: remote.timeout,
            customHeadersJSON: remote.customHeadersJSON
                ?? (usesMatchingLocalProtocol ? local.customHeadersJSON : "")
        )
    }

    var requestAPIKey: String {
        guard let remote = activeRemoteConfiguration else { return apiKey }
        if remote.wireProtocol == .appleIntelligence { return "" }
        if let remoteAPIKey = remote.apiKey { return remoteAPIKey }
        return remote.wireProtocol == wireProtocol
            ? apiKey
            : (Self.bundledAPIKey(for: remote.wireProtocol) ?? "")
    }

    var usageLimits: AIUsageLimits {
        if let remote = activeRemoteConfiguration {
            return remote.usageLimits
        }
        return draftUsageLimits
    }

    var draftUsageLimits: AIUsageLimits {
        AIUsageLimits(
            dailyRequestLimit: min(10_000, max(0, dailyRequestLimit)),
            hourlyRequestLimit: min(1_000, max(0, hourlyRequestLimit)),
            minimumRequestInterval: min(3_600, max(0, minimumRequestInterval))
        )
    }

    var displayModel: String { configuration.resolvedModel }

    var isUsingRemoteConfiguration: Bool {
        activeRemoteConfiguration != nil
    }

    var remoteRevision: String? {
        remoteConfiguration?.revision
    }

    func distributedResonanceModel() throws -> AudioTrainingModelInstallDescriptor? {
        guard let selection = activeRemoteConfiguration?.resonance,
              selection.enabled else { return nil }
        guard let model = selection.model else { throw AIResonanceDistributionError.modelUnavailable }
        try model.validateDistribution()
        return model
    }

    func resonanceDownloadRequest(for model: AudioTrainingModelInstallDescriptor) throws -> URLRequest {
        try model.validateDistribution()
        guard let token = SecureConfig.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { throw AIResonanceDistributionError.modelUnavailable }
        guard let url = Self.tokenAdminURL(path: "/_admin/api/public/audio-training/models/\(model.id)/coreml") else {
            throw AIProviderRemoteConfigurationError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.setValue(DeviceIdentifier.uuid, forHTTPHeaderField: "X-Device-ID")
        return request
    }

    /// AI 请求优先使用现有云端快照或本地配置，配置更新在后台完成，
    /// 避免分发服务短暂不可达时阻塞真正的模型请求。
    func refreshRemoteConfigurationInBackgroundIfNeeded(force: Bool = false) {
        Task { [weak self] in
            await self?.refreshRemoteConfigurationIfNeeded(force: force)
        }
    }

    func refreshRemoteConfigurationIfNeeded(force: Bool = false) async {
        if let remoteRefreshTask {
            await remoteRefreshTask.value
            return
        }
        let task = Task { await self.performRemoteConfigurationRefresh(force: force) }
        remoteRefreshTask = task
        await task.value
        remoteRefreshTask = nil
    }

    private func performRemoteConfigurationRefresh(force: Bool) async {
        guard let token = SecureConfig.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return
        }
        if !force,
           let remoteLastFetchedAt,
           Date().timeIntervalSince(remoteLastFetchedAt) < 15 * 60 {
            return
        }
        guard !isRefreshingRemoteConfiguration else { return }
        guard let url = Self.tokenAdminURL(path: "/_admin/api/public/ai/config") else {
            remoteError = String(localized: "ai_provider_remote_invalid_endpoint")
            return
        }

        isRefreshingRemoteConfiguration = true
        remoteError = nil
        defer { isRefreshingRemoteConfiguration = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        request.setValue(DeviceIdentifier.uuid, forHTTPHeaderField: "X-Device-ID")
        if let revision = remoteConfiguration?.revision, !revision.isEmpty {
            request.setValue(remoteConfigurationETag ?? "\"\(revision)\"", forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 304 {
                persistRemoteFetchDate(Date())
                return
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    remoteConfiguration = nil
                    persistRemoteConfiguration(nil)
                }
                throw Self.remoteError(from: data, statusCode: http.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(AIRemoteAIConfiguration.self, from: data)
            remoteConfiguration = value
            remoteConfigurationETag = http.value(forHTTPHeaderField: "ETag")
            persistRemoteConfiguration(value)
            persistRemoteFetchDate(Date())
        } catch {
            remoteError = error.localizedDescription
            AppLogger.warning("[AIProviderRemote] 配置拉取失败: \(error.localizedDescription)")
        }
    }

    func fetchPublishedConfiguration() async throws {
        let value = try await performAdminConfigurationRequest(method: "GET", body: nil)
        publishedConfiguration = value
        applyAdminConfiguration(value)
        updateCachedRemoteConfiguration(from: value)
    }

    func publishDraftConfiguration() async throws {
        if resonanceEnabled, resonanceModelID.isEmpty {
            throw AIResonanceDistributionError.modelUnavailable
        }
        let expectedRevision: String?
        if let revision = remoteConfiguration?.revision, revision != "unpublished" {
            expectedRevision = revision
        } else {
            expectedRevision = nil
        }
        let update = AIAdminProviderConfigurationUpdate(
            enabled: distributionEnabled,
            expectedRevision: expectedRevision,
            configuration: configuration,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            usageLimits: draftUsageLimits,
            resonance: AIResonanceConfigurationUpdate(enabled: resonanceEnabled, modelID: resonanceModelID)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(update)
        let value = try await performAdminConfigurationRequest(method: "PUT", body: body)
        publishedConfiguration = value
        applyAdminConfiguration(value)
        updateCachedRemoteConfiguration(from: value)
    }

    func useProtocolDefaults() {
        baseURL = Self.defaultBaseURL(for: wireProtocol)
        model = Self.defaultModel(for: wireProtocol)
        modelDiscoveryURL = ""
        customHeadersJSON = ""
    }

    func resetDeveloperOverride() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.wireProtocol)
        defaults.removeObject(forKey: Keys.baseURL)
        defaults.removeObject(forKey: Keys.model)
        defaults.removeObject(forKey: Keys.modelDiscoveryURL)
        defaults.removeObject(forKey: Keys.timeout)
        defaults.removeObject(forKey: Keys.customHeaders)
        defaults.removeObject(forKey: Keys.dailyRequestLimit)
        defaults.removeObject(forKey: Keys.hourlyRequestLimit)
        defaults.removeObject(forKey: Keys.minimumRequestInterval)
        for item in AIWireProtocol.allCases {
            KeychainHelper.delete(key: Self.apiKeyStorageKey(for: item))
            defaults.removeObject(forKey: Self.apiKeyOverrideStorageKey(for: item))
        }
        KeychainHelper.delete(key: Keys.legacyAPIKey)

        let builtInProtocol = Self.builtInProtocol
        wireProtocol = builtInProtocol
        baseURL = Self.defaultBaseURL(for: builtInProtocol)
        model = Self.defaultModel(for: builtInProtocol)
        modelDiscoveryURL = ""
        timeout = 45
        customHeadersJSON = ""
        isLoadingAPIKey = true
        apiKey = Self.bundledAPIKey(for: builtInProtocol) ?? ""
        isLoadingAPIKey = false
        if !apiKey.isEmpty {
            KeychainHelper.save(key: Self.apiKeyStorageKey(for: builtInProtocol), value: apiKey)
        }
        dailyRequestLimit = 50
        hourlyRequestLimit = 20
        minimumRequestInterval = 15
        distributionEnabled = true
        resonanceEnabled = false
        resonanceModelID = ""
    }

    private func saveIfReady() {
        guard isReady else { return }
        let defaults = UserDefaults.standard
        defaults.set(wireProtocol.rawValue, forKey: Keys.wireProtocol)
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(model, forKey: Keys.model)
        defaults.set(modelDiscoveryURL, forKey: Keys.modelDiscoveryURL)
        defaults.set(min(120, max(10, timeout)), forKey: Keys.timeout)
        defaults.set(customHeadersJSON, forKey: Keys.customHeaders)
        defaults.set(min(10_000, max(0, dailyRequestLimit)), forKey: Keys.dailyRequestLimit)
        defaults.set(min(1_000, max(0, hourlyRequestLimit)), forKey: Keys.hourlyRequestLimit)
        defaults.set(min(3_600, max(0, minimumRequestInterval)), forKey: Keys.minimumRequestInterval)
        defaults.set(distributionEnabled, forKey: Keys.distributionEnabled)
        defaults.set(resonanceEnabled, forKey: Keys.resonanceEnabled)
        defaults.set(resonanceModelID, forKey: Keys.resonanceModelID)
    }

    private var activeRemoteConfiguration: AIRemoteAIConfiguration? {
        guard let remoteConfiguration,
              remoteConfiguration.enabled,
              OnlineAccessManager.shared.canUseOnlineFeatures,
              !(SecureConfig.apiToken ?? "").isEmpty else {
            return nil
        }
        return remoteConfiguration
    }

    private func performAdminConfigurationRequest(
        method: String,
        body: Data?
    ) async throws -> AIAdminProviderConfiguration {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingAdminError.fullAccessRequired
        }
        let credential = tokenAdminCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            throw AIProviderRemoteConfigurationError.missingAdminCredential
        }
        guard let url = Self.tokenAdminURL(path: "/_admin/api/ai/config") else {
            throw AIProviderRemoteConfigurationError.invalidEndpoint
        }

        isPublishingRemoteConfiguration = method == "PUT"
        isRefreshingRemoteConfiguration = method == "GET"
        remoteError = nil
        defer {
            isPublishingRemoteConfiguration = false
            isRefreshingRemoteConfiguration = false
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(credential, forHTTPHeaderField: "X-Admin-Token")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else {
                throw Self.remoteError(from: data, statusCode: http.statusCode)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AIAdminProviderConfiguration.self, from: data)
        } catch {
            remoteError = error.localizedDescription
            throw error
        }
    }

    private func applyAdminConfiguration(_ value: AIAdminProviderConfiguration) {
        wireProtocol = value.wireProtocol
        baseURL = value.baseURL
        model = Self.normalizedModel(
            value.model,
            wireProtocol: value.wireProtocol,
            baseURL: value.baseURL
        )
        modelDiscoveryURL = value.modelDiscoveryURL
        timeout = value.timeout
        customHeadersJSON = value.customHeadersJSON
        apiKey = value.apiKey
        dailyRequestLimit = value.usageLimits.dailyRequestLimit
        hourlyRequestLimit = value.usageLimits.hourlyRequestLimit
        minimumRequestInterval = value.usageLimits.minimumRequestInterval
        distributionEnabled = value.enabled
        resonanceEnabled = value.resonance?.enabled ?? false
        resonanceModelID = value.resonance?.model?.id ?? ""
    }

    private func updateCachedRemoteConfiguration(from value: AIAdminProviderConfiguration) {
        let remote = AIRemoteAIConfiguration(
            schemaVersion: value.schemaVersion,
            enabled: value.enabled,
            wireProtocol: value.wireProtocol,
            baseURL: value.baseURL,
            model: value.model,
            modelDiscoveryURL: value.modelDiscoveryURL,
            timeout: value.timeout,
            customHeadersJSON: value.customHeadersJSON,
            apiKey: value.apiKey,
            usageLimits: value.usageLimits,
            revision: value.revision,
            updatedAt: value.updatedAt,
            resonance: value.resonance
        )
        remoteConfiguration = remote
        remoteConfigurationETag = nil
        persistRemoteConfiguration(remote)
        persistRemoteFetchDate(Date())
    }

    private var resonanceModelRequestID = UUID()
    private var remoteConfigurationETag: String?

    func fetchPublishedResonanceModels() async {
        guard AppConfig.DeveloperAccess.hasFullTools else { return }
        let requestID = UUID()
        resonanceModelRequestID = requestID
        isLoadingResonanceModels = true
        resonanceModelsError = nil
        defer {
            if resonanceModelRequestID == requestID { isLoadingResonanceModels = false }
        }
        do {
            let credential = tokenAdminCredential.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !credential.isEmpty else { throw AIProviderRemoteConfigurationError.missingAdminCredential }
            guard let url = Self.tokenAdminURL(path: "/_admin/api/audio-training/models") else {
                throw AIProviderRemoteConfigurationError.invalidEndpoint
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(credential, forHTTPHeaderField: "X-Admin-Token")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else {
                throw Self.remoteError(from: data, statusCode: http.statusCode)
            }
            let list = try JSONDecoder().decode(AIResonanceModelList.self, from: data)
            for model in list.models { try model.validateDistribution() }
            guard resonanceModelRequestID == requestID else { return }
            publishedResonanceModels = list.models
            resonanceModelsError = nil
        } catch is CancellationError {
            return
        } catch {
            guard resonanceModelRequestID == requestID else { return }
            resonanceModelsError = error.localizedDescription
        }
    }

    private func saveAdminCredentialIfReady() {
        guard isReady, !isLoadingAdminCredential else { return }
        let normalized = tokenAdminCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            KeychainHelper.delete(key: Keys.tokenAdminCredential)
        } else {
            KeychainHelper.save(key: Keys.tokenAdminCredential, value: normalized)
        }
    }

    private func persistRemoteConfiguration(_ value: AIRemoteAIConfiguration?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let value {
            // key 单独进 Keychain，UserDefaults 只保留脱敏配置。
            if let remoteKey = value.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !remoteKey.isEmpty {
                KeychainHelper.save(key: Keys.remoteAPIKey, value: remoteKey)
            } else {
                KeychainHelper.delete(key: Keys.remoteAPIKey)
            }
            var sanitized = value
            sanitized.apiKey = nil
            if let data = try? encoder.encode(sanitized) {
                UserDefaults.standard.set(data, forKey: Keys.cachedRemoteConfiguration)
            }
        } else {
            KeychainHelper.delete(key: Keys.remoteAPIKey)
            UserDefaults.standard.removeObject(forKey: Keys.cachedRemoteConfiguration)
        }
    }

    private func persistRemoteFetchDate(_ date: Date) {
        remoteLastFetchedAt = date
        UserDefaults.standard.set(date, forKey: Keys.remoteLastFetchedAt)
    }

    private func saveKeyIfReady() {
        guard isReady, !isLoadingAPIKey else { return }
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storageKey = Self.apiKeyStorageKey(for: wireProtocol)
        UserDefaults.standard.set(true, forKey: Self.apiKeyOverrideStorageKey(for: wireProtocol))
        if normalized.isEmpty {
            KeychainHelper.delete(key: storageKey)
        } else {
            KeychainHelper.save(key: storageKey, value: normalized)
        }
    }

    private func loadAPIKeyForSelectedProtocolIfReady() {
        guard isReady else { return }
        let hasExplicitOverride = UserDefaults.standard.bool(
            forKey: Self.apiKeyOverrideStorageKey(for: wireProtocol)
        )
        isLoadingAPIKey = true
        apiKey = KeychainHelper.loadString(key: Self.apiKeyStorageKey(for: wireProtocol))
            ?? (hasExplicitOverride ? nil : Self.bundledAPIKey(for: wireProtocol))
            ?? ""
        isLoadingAPIKey = false
    }

    private static func apiKeyStorageKey(for wireProtocol: AIWireProtocol) -> String {
        "ai.eq.provider.api-key.\(wireProtocol.rawValue)"
    }

    private static func loadCachedRemoteConfiguration(defaults: UserDefaults) -> AIRemoteAIConfiguration? {
        guard let data = defaults.data(forKey: Keys.cachedRemoteConfiguration) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var value = try? decoder.decode(AIRemoteAIConfiguration.self, from: data) else { return nil }
        if let plaintextKey = value.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plaintextKey.isEmpty {
            // 旧版本把 key 明文留在 UserDefaults：迁入 Keychain 并重写脱敏副本。
            KeychainHelper.save(key: Keys.remoteAPIKey, value: plaintextKey)
            var sanitized = value
            sanitized.apiKey = nil
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let sanitizedData = try? encoder.encode(sanitized) {
                defaults.set(sanitizedData, forKey: Keys.cachedRemoteConfiguration)
            }
        } else {
            value.apiKey = KeychainHelper.loadString(key: Keys.remoteAPIKey)
        }
        return value
    }

    private static func tokenAdminURL(path: String) -> URL? {
        guard var components = URLComponents(string: SecureConfig.apiBaseURL(for: .primary)) else { return nil }
        let currentPath = components.path
        components.path = currentPath.hasSuffix("/")
            ? "\(currentPath)\(path.dropFirst())"
            : "\(currentPath)\(path)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func remoteError(from data: Data, statusCode: Int) -> Error {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String,
           !message.isEmpty {
            return AIProviderRemoteConfigurationError.server(message, statusCode)
        }
        return AIProviderRemoteConfigurationError.httpStatus(statusCode)
    }

    private static func apiKeyOverrideStorageKey(for wireProtocol: AIWireProtocol) -> String {
        "ai.eq.provider.api-key-overridden.\(wireProtocol.rawValue)"
    }

    private static var builtInProtocol: AIWireProtocol {
        bundleString("AI_PROVIDER_PROTOCOL")
            .flatMap(AIWireProtocol.init(rawValue:)) ?? .appleIntelligence
    }

    private static func defaultBaseURL(for wireProtocol: AIWireProtocol) -> String {
        guard wireProtocol == builtInProtocol else { return wireProtocol.defaultBaseURL }
        return bundleString("AI_PROVIDER_BASE_URL") ?? wireProtocol.defaultBaseURL
    }

    private static func defaultModel(for wireProtocol: AIWireProtocol) -> String {
        guard wireProtocol == builtInProtocol else { return wireProtocol.defaultModel }
        return bundleString("AI_PROVIDER_MODEL") ?? ""
    }

    private static func normalizedModel(
        _ model: String,
        wireProtocol: AIWireProtocol,
        baseURL: String
    ) -> String {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wireProtocol == .openAICompatible,
              URLComponents(string: baseURL)?.host?.lowercased() == "dengdeng.ganiran.com",
              normalized.isEmpty || normalized == "gpt-5-mini" else {
            return model
        }
        return bundleString("AI_PROVIDER_MODEL") ?? AIWireProtocol.openAICompatible.defaultModel
    }

    private static func bundledAPIKey(for wireProtocol: AIWireProtocol) -> String? {
        guard wireProtocol == builtInProtocol else { return nil }
        return bundleString("AI_PROVIDER_API_KEY")
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.hasPrefix("$(") else { return nil }
        return normalized
    }
}

private enum AIProviderRemoteConfigurationError: LocalizedError {
    case missingAdminCredential
    case invalidEndpoint
    case httpStatus(Int)
    case server(String, Int)

    var errorDescription: String? {
        switch self {
        case .missingAdminCredential:
            return String(localized: "ai_provider_remote_missing_admin_token")
        case .invalidEndpoint:
            return String(localized: "ai_provider_remote_invalid_endpoint")
        case let .httpStatus(code):
            return String(format: String(localized: "ai_provider_remote_http_error_format"), code)
        case let .server(message, _):
            return message
        }
    }
}
