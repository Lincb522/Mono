import Foundation
@preconcurrency import Combine

enum AudioTrainingAdminError: LocalizedError {
    case fullAccessRequired
    case missingAdminCredential
    case invalidEndpoint
    case tuningTestFailed(String)
    case server(String, Int)

    var errorDescription: String? {
        switch self {
        case .fullAccessRequired:
            return String(localized: "audio_training_error_full_access")
        case .missingAdminCredential:
            return String(localized: "audio_training_error_missing_credential")
        case .invalidEndpoint:
            return String(localized: "audio_training_error_invalid_endpoint")
        case let .tuningTestFailed(message):
            return message.isEmpty
                ? String(localized: "audio_training_error_tuning_test")
                : message
        case let .server(message, _):
            return message
        }
    }
}

@MainActor
final class AudioTrainingAdminStore: ObservableObject {
    static let shared = AudioTrainingAdminStore()

    @Published private(set) var status: AudioTrainingStatusResponse?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isMutating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var publicationMessage: String?
    @Published private(set) var publicationError: String?
    @Published private(set) var downloadedModelFileName: String?
    @Published private(set) var activeInstalledModel: AudioTrainingInstalledModelStatus?
    @Published private(set) var previousInstalledModel: AudioTrainingInstalledModelStatus?
    @Published private(set) var onDeviceSettings = AudioTrainingOnDeviceSettings.standard
    @Published private(set) var modelTestResult: AudioTrainingModelTestResult?
    @Published private(set) var tuningTestResult: AudioTrainingTuningTestResult?
    @Published private(set) var isTestingModel = false
    @Published private(set) var isTestingTuning = false

    private var pollingTask: Task<Void, Never>?
    private var lastLoggedStatusSignature = ""

    private init() {}

    var isBusy: Bool {
        isRefreshing || isMutating || isTestingModel || isTestingTuning
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await request(
                path: "/_admin/api/audio-training",
                method: "GET",
                body: Optional<Data>.none,
                as: AudioTrainingStatusResponse.self
            )
            status = response
            logStatusChange(response)
            errorMessage = nil
            updatePollingState()
        } catch {
            errorMessage = error.localizedDescription
            stopPolling()
            AppLogger.failure(
                error,
                message: "[ModelTraining] Status refresh failed",
                step: "model-training.refresh-failed",
                category: .modelTraining,
                event: "model-training.refresh-failed"
            )
        }
        await refreshInstalledModelStatus()
    }

    func updateSettings(_ update: AudioTrainingSettingsUpdate) async {
        await mutate(action: "settings-update", context: [
            "epochs": String(update.epochs),
            "hiddenUnits": String(update.hiddenUnits),
            "learningRate": String(update.learningRate),
            "validationPercent": String(update.validationPercent),
            "minimumSamples": String(update.minimumSamples),
            "priorWeight": String(update.priorWeight),
            "weightDecay": String(update.weightDecay),
            "earlyStoppingPatience": String(update.earlyStoppingPatience),
            "intentUnits": String(update.intentUnits),
            "targetMode": update.targetMode.rawValue
        ]) {
            let encoder = JSONEncoder()
            let body = try encoder.encode(update)
            _ = try await request(
                path: "/_admin/api/audio-training/settings",
                method: "PUT",
                body: body,
                as: AudioTrainingSettingsResponse.self
            )
        }
    }

    func startTraining() async {
        await mutate(action: "start", context: [
            "trainableSamples": String(status?.dataset.trainableSamples ?? 0),
            "tenBandSamples": String(status?.dataset.tenBandSamples ?? 0),
            "thirtyTwoBandSamples": String(status?.dataset.thirtyTwoBandSamples ?? 0),
            "standardProfileSamples": String(status?.dataset.standardProfileSamples ?? 0),
            "spatialProfileSamples": String(status?.dataset.spatialProfileSamples ?? 0),
            "tenBandStandardSamples": String(
                status?.dataset.branchSamples?["tenBand:standard"] ?? 0
            ),
            "tenBandSpatialSamples": String(
                status?.dataset.branchSamples?["tenBand:monoSpatialEnhancement"] ?? 0
            ),
            "thirtyTwoBandStandardSamples": String(
                status?.dataset.branchSamples?["thirtyTwoBand:standard"] ?? 0
            ),
            "thirtyTwoBandSpatialSamples": String(
                status?.dataset.branchSamples?["thirtyTwoBand:monoSpatialEnhancement"] ?? 0
            )
        ]) {
            _ = try await request(
                path: "/_admin/api/audio-training/jobs",
                method: "POST",
                body: Data("{}".utf8),
                as: AudioTrainingJobResponse.self
            )
        }
    }

    func cancelTraining() async {
        guard let jobID = status?.currentJob?.id else { return }
        await mutate(action: "cancel", context: ["jobID": jobID]) {
            _ = try await request(
                path: "/_admin/api/audio-training/jobs/\(jobID)/cancel",
                method: "POST",
                body: Data("{}".utf8),
                as: AudioTrainingJobResponse.self
            )
        }
    }

    func publishModel(id modelID: String) async {
        guard !isMutating else { return }
        publicationMessage = nil
        publicationError = nil
        var published = false
        await mutate(action: "publish", context: ["modelID": modelID]) {
            struct Publication: Encodable {
                let confirmed = true
            }
            let body = try JSONEncoder().encode(Publication())
            let response = try await request(
                path: "/_admin/api/audio-training/models/\(modelID)/publish",
                method: "POST",
                body: body,
                as: AudioTrainingModelResponse.self
            )
            guard response.model.id == modelID, response.model.release?.generatedAutomatically == true else {
                throw AudioTrainingAdminError.server(String(localized: "audio_training_publication_upgrade_required"), 409)
            }
            published = true
            publicationMessage = String(format: String(localized: "audio_training_publication_success"), response.model.displayName)
        }
        if published {
            await AIProviderConfigurationStore.shared.fetchPublishedResonanceModels()
            publicationError = AIProviderConfigurationStore.shared.resonanceModelsError
        } else {
            publicationError = errorMessage
        }
    }

    func downloadCurrentModel() async {
        guard let model = status?.currentModel else { return }
        await mutate(action: "download-install", context: [
            "modelID": model.id,
            "version": model.version
        ]) {
            let (data, response) = try await requestPayload(
                path: "/_admin/api/audio-training/models/\(model.id)/coreml",
                method: "GET",
                body: nil
            )
            guard let sha256 = response.value(forHTTPHeaderField: "X-Mono-Model-SHA256"),
                  !sha256.isEmpty,
                  Int(response.value(forHTTPHeaderField: "X-Mono-Feature-Schema") ?? "")
                    == model.featureSchemaVersion,
                  Int(response.value(forHTTPHeaderField: "X-Mono-Target-Schema") ?? "")
                    == model.targetSchemaVersion else {
                throw URLError(.cannotParseResponse)
            }
            let descriptor = AudioTrainingModelInstallDescriptor(
                id: model.id,
                version: model.version,
                sha256: sha256,
                byteCount: data.count,
                featureSchemaVersion: model.featureSchemaVersion,
                targetSchemaVersion: model.targetSchemaVersion,
                completeSampleCount: Self.completeSampleCount(model),
                legacySampleCount: Self.legacySampleCount(model),
                learningConditionedSampleCount: Self.learningConditionedSampleCount(model),
                deviceConditionedSampleCount: Self.deviceConditionedSampleCount(model),
                completeAccountCount: model.metrics.completeAccountCount ?? 0,
                completeBranchSampleCounts: Self.completeBranchSampleCounts(model),
                completeBranchAccountCounts: model.metrics.completeBranchAccounts ?? [:],
                qualityWarnings: model.metrics.qualityWarnings ?? [],
                createdAt: model.createdAt,
                fileName: model.fileName,
                release: model.release
            )
            let installed = try await AudioTrainingOnDeviceModelStore.shared.install(
                modelData: data,
                descriptor: descriptor
            )
            activeInstalledModel = installed
            downloadedModelFileName = installed.sourceModelRelativePath
        }
    }

    func rollbackModel() async {
        await mutate(action: "rollback") {
            activeInstalledModel = try await AudioTrainingOnDeviceModelStore.shared.rollback()
        }
    }

    func deactivateModel() async {
        await mutate(action: "deactivate") {
            try await AudioTrainingOnDeviceModelStore.shared.deactivate()
            activeInstalledModel = nil
        }
    }

    func updateOnDeviceSettings(_ value: AudioTrainingOnDeviceSettings) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            onDeviceSettings = try await AudioTrainingOnDeviceModelStore.shared.updateSettings(value)
            modelTestResult = nil
            tuningTestResult = nil
            errorMessage = nil
            AppLogger.success(
                "[LocalModel] Runtime settings saved enabled=\(onDeviceSettings.isEnabled) compute=\(onDeviceSettings.computeMode.rawValue)",
                step: "local-model.runtime-settings-saved",
                category: .localModel,
                event: "local-model.runtime-settings-saved"
            )
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.failure(
                error,
                message: "[LocalModel] Runtime settings save failed",
                step: "local-model.runtime-settings-failed",
                category: .localModel,
                event: "local-model.runtime-settings-failed"
            )
        }
    }

    func runModelTest() async {
        guard !isTestingModel, !isMutating, !isTestingTuning else { return }
        isTestingModel = true
        modelTestResult = nil
        defer { isTestingModel = false }
        AppLogger.info(
            "[LocalModel] Self-test requested",
            step: "local-model.self-test-requested",
            category: .localModel,
            event: "local-model.self-test-requested"
        )
        do {
            modelTestResult = try await AudioTrainingOnDeviceModelStore.shared.testActiveModel()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.failure(
                error,
                message: "[LocalModel] Self-test failed",
                step: "local-model.self-test-failed",
                category: .localModel,
                event: "local-model.self-test-failed"
            )
        }
    }

    func runTuningTest() async {
        guard !isTestingTuning, !isMutating, !isTestingModel else { return }
        isTestingTuning = true
        tuningTestResult = nil
        defer { isTestingTuning = false }
        AppLogger.info(
            "[LocalModel] Current-track tuning test requested",
            step: "local-model.tuning-test-requested",
            category: .localModel,
            event: "local-model.tuning-test-requested"
        )
        do {
            let mode = EQManager.shared.graphicEQMode
            guard let active = try await AudioTrainingOnDeviceModelStore.shared.activeStatus()
            else {
                throw AudioTrainingOnDeviceModelError.noActiveModel
            }
            guard await AudioTrainingOnDeviceModelStore.shared.activeIdentity() != nil else {
                throw AudioTrainingOnDeviceModelError.modelDisabled
            }
            let agent = AIEqualizerAgent.shared
            guard !agent.phase.isWorking else {
                throw AudioTrainingAdminError.tuningTestFailed(
                    String(localized: "audio_training_error_tuning_test_busy")
                )
            }
            let previousProposalID = agent.proposal?.id
            let wallClockStartedAt = Date()
            let startedAt = ProcessInfo.processInfo.systemUptime
            await agent.runAnalysis(trigger: .manual, forceRegeneration: true, preferInstalledModel: true)
            if case let .failed(message) = agent.phase {
                throw AudioTrainingAdminError.tuningTestFailed(message)
            }
            guard let proposal = agent.proposal,
                  proposal.id != previousProposalID,
                  proposal.model == active.version,
                  proposal.skillCompliance?.accepted == true,
                  proposal.skillCompliance?.localValidationApplied == true,
                  proposal.skillCompliance?.executionMode == .trainedCoreMLModel,
                  agent.isCurrentProposalApplied else {
                throw AudioTrainingAdminError.tuningTestFailed(
                    String(localized: "audio_training_error_tuning_test")
                )
            }
            guard let features = agent.measuredFeatures,
                  features.frameCount > 0,
                  features.sampleDuration > 0,
                  let timing = proposal.timing,
                  timing.samplingReused == false,
                  timing.sampling > 0,
                  let inference = try await AudioTrainingOnDeviceModelStore.shared
                    .lastInferenceTrace(),
                  inference.version == active.version,
                  inference.capturedAt >= wallClockStartedAt,
                  inference.input.count == AudioTrainingOnDeviceModelStore.inputWidth(
                      forFeatureSchemaVersion: active.featureSchemaVersion,
                      graphicEQMode: mode
                  ),
                  inference.rawOutput.count == AudioTrainingOnDeviceModelStore.outputWidth(
                    forFeatureSchemaVersion: active.featureSchemaVersion
                  ) else {
                throw AudioTrainingAdminError.tuningTestFailed(
                    String(localized: "audio_training_error_tuning_test_sampling")
                )
            }
            let isTrackConditioned = inference.trackCorrectionStrength > 0
            let modelOutputStrength = Double(inference.trackCorrectionStrength)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let appliedDSPData = try encoder.encode(EQManager.shared.currentDSPDiagnosticSnapshot())
            tuningTestResult = AudioTrainingTuningTestResult(
                version: active.version,
                profileName: proposal.profileName,
                bandCount: proposal.gains.count,
                preampDB: proposal.preampDB,
                elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
                warningCodes: proposal.skillCompliance?.warningCodes ?? [],
                completeSampleCount: active.completeSampleCount,
                legacySampleCount: active.legacySampleCount,
                deviceConditionedSampleCount: active.deviceConditionedSampleCount ?? 0,
                isTrackConditioned: isTrackConditioned,
                modelOutputStrength: modelOutputStrength,
                samplingElapsedMilliseconds: timing.sampling * 1_000,
                generationElapsedMilliseconds: timing.generation * 1_000,
                applyingElapsedMilliseconds: timing.applying * 1_000,
                samplingReused: timing.samplingReused ?? false,
                sampleDuration: features.sampleDuration,
                sampleRate: features.sampleRate,
                frameCount: features.frameCount,
                inference: inference,
                finalProposal: proposal,
                appliedDSPJSON: String(decoding: appliedDSPData, as: UTF8.self)
            )
            errorMessage = nil
            AppLogger.success(
                "[LocalModel] Current-track tuning test completed version=\(active.version) profile=\(proposal.resolvedTuningProfile.rawValue) bands=\(proposal.gains.count) input=\(inference.input.count) output=\(inference.rawOutput.count)",
                step: "local-model.tuning-test-completed",
                category: .localModel,
                event: "local-model.tuning-test-completed"
            )
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.failure(
                error,
                message: "[LocalModel] Current-track tuning test failed",
                step: "local-model.tuning-test-failed",
                category: .localModel,
                event: "local-model.tuning-test-failed"
            )
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func mutate(
        action: String,
        context: [String: String] = [:],
        _ operation: () async throws -> Void
    ) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let event = "model-training.\(action)"
        AppLogger.info(
            "[ModelTraining] Operation started action=\(action)",
            step: event,
            category: .modelTraining,
            event: event,
            context: context
        )
        do {
            try await operation()
            errorMessage = nil
            AppLogger.success(
                "[ModelTraining] Operation completed action=\(action)",
                step: event,
                category: .modelTraining,
                event: event,
                context: context
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.failure(
                error,
                message: "[ModelTraining] Operation failed action=\(action)",
                step: "\(event)-failed",
                category: .modelTraining,
                event: "\(event)-failed",
                context: context
            )
        }
    }

    private func logStatusChange(_ response: AudioTrainingStatusResponse) {
        let job = response.currentJob
        let dataset = response.dataset
        let progressPercent = Int(((job?.progress ?? 0) * 100).rounded())
        let signature = [
            job?.id ?? "none",
            job?.state ?? "idle",
            String(job?.epoch ?? 0),
            String(progressPercent),
            response.currentModel?.id ?? "none",
            dataset.datasetFingerprint ?? "none"
        ].joined(separator: "|")
        guard signature != lastLoggedStatusSignature else { return }
        lastLoggedStatusSignature = signature
        AppLogger.info(
            "[ModelTraining] Status state=\(job?.state ?? "idle") progress=\(progressPercent)% epoch=\(job?.epoch ?? 0)/\(job?.totalEpochs ?? 0) trainable=\(dataset.trainableSamples ?? 0) complete=\(dataset.completeSamples) legacy=\(dataset.legacyPlans) bands=\(dataset.tenBandSamples)/\(dataset.thirtyTwoBandSamples) profiles=\(dataset.standardProfileSamples ?? 0)/\(dataset.spatialProfileSamples ?? 0) model=\(response.currentModel?.version ?? "none")",
            step: "model-training.status",
            category: .modelTraining,
            event: "model-training.status",
            context: [
                "jobID": job?.id ?? "",
                "modelID": response.currentModel?.id ?? "",
                "datasetFingerprint": dataset.datasetFingerprint ?? "",
                "tenBandStandardSamples": String(
                    dataset.branchSamples?["tenBand:standard"] ?? 0
                ),
                "tenBandSpatialSamples": String(
                    dataset.branchSamples?["tenBand:monoSpatialEnhancement"] ?? 0
                ),
                "thirtyTwoBandStandardSamples": String(
                    dataset.branchSamples?["thirtyTwoBand:standard"] ?? 0
                ),
                "thirtyTwoBandSpatialSamples": String(
                    dataset.branchSamples?["thirtyTwoBand:monoSpatialEnhancement"] ?? 0
                )
            ]
        )
    }

    private func updatePollingState() {
        guard status?.currentJob?.isActive == true,
              AppConfig.DeveloperAccess.hasFullTools else {
            stopPolling()
            return
        }
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                guard self.status?.currentJob?.isActive == true else { return }
            }
        }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        as responseType: Response.Type
    ) async throws -> Response {
        let data = try await requestData(path: path, method: method, body: body)
        return try JSONDecoder().decode(responseType, from: data)
    }

    private func requestData(
        path: String,
        method: String,
        body: Data?
    ) async throws -> Data {
        let (data, _) = try await requestPayload(path: path, method: method, body: body)
        return data
    }

    private func requestPayload(
        path: String,
        method: String,
        body: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingAdminError.fullAccessRequired
        }
        let credential = AIProviderConfigurationStore.shared.tokenAdminCredential
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            throw AudioTrainingAdminError.missingAdminCredential
        }
        guard let url = Self.tokenAdminURL(path: path) else {
            throw AudioTrainingAdminError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(credential, forHTTPHeaderField: "X-Admin-Token")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.serverError(from: data, statusCode: http.statusCode)
        }
        return (data, http)
    }

    private func refreshInstalledModelStatus() async {
        activeInstalledModel = try? await AudioTrainingOnDeviceModelStore.shared.activeStatus()
        previousInstalledModel = try? await AudioTrainingOnDeviceModelStore.shared.previousStatus()
        downloadedModelFileName = activeInstalledModel?.sourceModelRelativePath
        if let value = try? await AudioTrainingOnDeviceModelStore.shared.settings() {
            onDeviceSettings = value
        }
    }

    private static func completeSampleCount(_ model: AudioTrainingModelStatus) -> Int {
        (model.metrics.completeTrainingSamples ?? 0)
            + (model.metrics.completeValidationSamples ?? 0)
    }

    private static func legacySampleCount(_ model: AudioTrainingModelStatus) -> Int {
        (model.metrics.legacyTrainingSamples ?? 0)
            + (model.metrics.legacyValidationSamples ?? 0)
    }

    private static func learningConditionedSampleCount(
        _ model: AudioTrainingModelStatus
    ) -> Int {
        (model.metrics.learningConditionedTrainingSamples ?? 0)
            + (model.metrics.learningConditionedValidationSamples ?? 0)
    }

    private static func deviceConditionedSampleCount(
        _ model: AudioTrainingModelStatus
    ) -> Int {
        (model.metrics.deviceConditionedTrainingSamples ?? 0)
            + (model.metrics.deviceConditionedValidationSamples ?? 0)
    }

    private static func completeBranchSampleCounts(
        _ model: AudioTrainingModelStatus
    ) -> [String: Int] {
        let training = model.metrics.completeBranchTrainingSamples ?? [:]
        let validation = model.metrics.completeBranchValidationSamples ?? [:]
        var result: [String: Int] = [:]
        for key in Set(training.keys).union(validation.keys) {
            result[key] = (training[key] ?? 0) + (validation[key] ?? 0)
        }
        return result
    }

    private static func tokenAdminURL(path: String) -> URL? {
        guard var components = URLComponents(
            string: SecureConfig.apiBaseURL(for: .primary)
        ) else {
            return nil
        }
        let currentPath = components.path
        components.path = currentPath.hasSuffix("/")
            ? "\(currentPath)\(path.dropFirst())"
            : "\(currentPath)\(path)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func serverError(from data: Data, statusCode: Int) -> Error {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String,
           !message.isEmpty {
            return AudioTrainingAdminError.server(message, statusCode)
        }
        return AudioTrainingAdminError.server(
            String(localized: "audio_training_error_server"),
            statusCode
        )
    }
}
