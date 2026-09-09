import CoreML
import CryptoKit
import Foundation
import FFmpegSwiftSDK

enum AudioTrainingOnDeviceModelError: LocalizedError {
    case fullAccessRequired
    case integrityCheckFailed
    case invalidModel
    case unsupportedSchema
    case noActiveModel
    case noRollbackModel
    case modelDisabled
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .fullAccessRequired:
            return String(localized: "audio_training_error_full_access")
        case .integrityCheckFailed:
            return String(localized: "audio_training_error_integrity")
        case .invalidModel:
            return String(localized: "audio_training_error_invalid_model")
        case .unsupportedSchema:
            return String(localized: "audio_training_error_unsupported_schema")
        case .noActiveModel:
            return String(localized: "audio_training_error_no_active_model")
        case .noRollbackModel:
            return String(localized: "audio_training_error_no_rollback_model")
        case .modelDisabled:
            return String(localized: "audio_training_error_model_disabled")
        case .storageUnavailable:
            return String(localized: "audio_training_error_storage")
        }
    }
}

struct AudioTrainingOnDevicePrediction: Sendable {
    let output: AIEqualizerModelOutput
    let populationOutput: AIEqualizerModelOutput?
    let modelVersion: String
    let featureSchemaVersion: Int
    let targetSchemaVersion: Int
    let graphicEQMode: GraphicEQMode
    let computeMode: AudioTrainingComputeMode
    let embedsLearningContext: Bool
    let embedsDetailedDeviceContext: Bool
    /// 0…1 share of the model's track-specific correction that was applied on
    /// top of the population prior for this band/profile branch.
    let trackCorrectionStrength: Float
    /// Outputs whose raw prediction left its valid range and were replaced by
    /// the compiler default.
    let fallbackOutputCount: Int
    let inference: AudioTrainingInferenceTrace
    let populationInference: AudioTrainingInferenceTrace?
    let confidenceCalibration: AudioTrainingConfidenceCalibration?
    let modelID: String
    let modelSHA256: String
}

actor AudioTrainingOnDeviceModelStore {
    static let shared = AudioTrainingOnDeviceModelStore()

    private static let currentDirectoryName = "current"
    private static let previousDirectoryName = "previous"
    private static let compiledModelName = "AudioTuning.mlmodelc"
    private static let manifestName = "manifest.json"
    private static let settingsKey = "audio.training.on-device.settings.v1"
    private static let settingsRevisionKey = "audio.training.on-device.settings-revision"
    private static let currentSettingsRevision = 2
    private static let minimumEmbeddedLearningSamples = 8
    private static let minimumDetailedDeviceSamples = 8

    static func inputWidth(
        forFeatureSchemaVersion version: Int,
        graphicEQMode _: GraphicEQMode = .tenBand
    ) -> Int? {
        featureNames(forFeatureSchemaVersion: version)?.count
    }

    static func outputWidth(forFeatureSchemaVersion version: Int) -> Int {
        targetNames(forFeatureSchemaVersion: version).count
    }

    private var loadedModel: MLModel?
    private var loadedIdentity: String?
    private var loadedInputMean: [Float]?
    private var loadedConfidenceCalibration: AudioTrainingConfidenceCalibration?
    private var latestInferenceTrace: AudioTrainingInferenceTrace?
    private var onDeviceSettings: AudioTrainingOnDeviceSettings
    private var distributedModel: AudioTrainingModelInstallDescriptor?
    private var distributionPreparation: (id: UUID, identity: String, task: Task<String, Error>)?
    private var isInstalling = false

    private init() {
        let defaults = UserDefaults.standard
        var resolvedSettings: AudioTrainingOnDeviceSettings
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AudioTrainingOnDeviceSettings.self, from: data) {
            resolvedSettings = decoded.normalized
        } else {
            resolvedSettings = .standard
        }
        if defaults.integer(forKey: Self.settingsRevisionKey) < Self.currentSettingsRevision {
            // v1 attenuated the learned EQ/tone to 20% while leaving the model's
            // full preamp cut in place. Migrate that inconsistent mix to the
            // complete learned population prior; the local compiler still owns
            // headroom, phase and limiter safety.
            resolvedSettings.legacyPriorStrength = AudioTrainingOnDeviceSettings
                .standard
                .legacyPriorStrength
            if let data = try? JSONEncoder().encode(resolvedSettings.normalized) {
                defaults.set(data, forKey: Self.settingsKey)
            }
            defaults.set(Self.currentSettingsRevision, forKey: Self.settingsRevisionKey)
        }
        onDeviceSettings = resolvedSettings.normalized
    }

    func settings() throws -> AudioTrainingOnDeviceSettings {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        return onDeviceSettings
    }

    func updateSettings(
        _ value: AudioTrainingOnDeviceSettings
    ) throws -> AudioTrainingOnDeviceSettings {
        guard !isInstalling else { throw AIResonanceDistributionError.installationInProgress }
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        let normalized = value.normalized
        if normalized.computeMode != onDeviceSettings.computeMode {
            loadedModel = nil
            loadedIdentity = nil
            loadedInputMean = nil
        }
        onDeviceSettings = normalized
        latestInferenceTrace = nil
        try persistSettings()
        AppLogger.info(
            "[LocalModel] Settings updated enabled=\(normalized.isEnabled) compute=\(normalized.computeMode.rawValue) prior=\(String(format: "%.2f", normalized.legacyPriorStrength)) advancedMinimum=\(normalized.advancedStageMinimumSamples)",
            step: "local-model.settings",
            category: .localModel,
            event: "local-model.settings"
        )
        return normalized
    }

    func activeStatus() throws -> AudioTrainingInstalledModelStatus? {
        let directory = try rootDirectory().appendingPathComponent(
            Self.currentDirectoryName,
            isDirectory: true
        )
        return try readManifestIfPresent(in: directory)
    }

    func previousStatus() throws -> AudioTrainingInstalledModelStatus? {
        guard AppConfig.DeveloperAccess.hasFullTools else { return nil }
        let directory = try rootDirectory().appendingPathComponent(
            Self.previousDirectoryName,
            isDirectory: true
        )
        return try readManifestIfPresent(in: directory)
    }

    func activeIdentity() -> String? {
        guard onDeviceSettings.isEnabled else { return nil }
        do {
            guard let status = try activeStatus(), canUse(status) else { return nil }
            let identity = status.identity
            return "\(identity):\(onDeviceSettings.computeMode.rawValue):\(onDeviceSettings.legacyPriorStrength):\(onDeviceSettings.advancedStageMinimumSamples):\(AudioTrainingProposalSummary.revision)"
        } catch {
            return nil
        }
    }

    func clearDistributedAuthorization() {
        distributedModel = nil
        distributionPreparation?.task.cancel()
    }

    func prepareDistributedModel(
        _ descriptor: AudioTrainingModelInstallDescriptor,
        request: URLRequest? = nil,
        bundledModelURL: URL? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        try descriptor.validateDistribution()
        distributedModel = descriptor
        let key = descriptor.distributionIdentity
        if let previous = distributionPreparation, previous.identity != key {
            previous.task.cancel()
        }
        if let status = try? activeStatus(), matches(status, descriptor) {
            do {
                _ = try loadActiveModel(status: status, root: rootDirectory())
                if !onDeviceSettings.isEnabled {
                    onDeviceSettings.isEnabled = true
                    try persistSettings()
                }
                guard let identity = activeIdentity() else { throw AIResonanceDistributionError.modelUnavailable }
                return identity
            } catch {
                loadedModel = nil
                loadedIdentity = nil
                loadedInputMean = nil
                AppLogger.warning(
                    "[LocalModel] Installed model unavailable; downloading the selected version again",
                    step: "local-model.reinstall-required", category: .localModel,
                    event: "local-model.reinstall-required"
                )
            }
        }
        if let preparation = distributionPreparation,
           preparation.identity == key, !preparation.task.isCancelled {
            return try await withTaskCancellationHandler {
                try await preparation.task.value
            } onCancel: { preparation.task.cancel() }
        }
        if let previous = distributionPreparation {
            previous.task.cancel()
            _ = await previous.task.result
            try Task.checkCancellation()
            guard distributedModel?.distributionIdentity == key else { throw CancellationError() }
            if let current = distributionPreparation, current.id != previous.id {
                return try await prepareDistributedModel(descriptor, request: request, bundledModelURL: bundledModelURL)
            }
        }
        let preparationID = UUID()
        let task = Task {
            let data: Data
            if let bundledModelURL {
                data = try Data(contentsOf: bundledModelURL, options: .mappedIfSafe)
            } else if let request {
                data = try await AudioTrainingModelDownloader.download(descriptor, request: request)
            } else {
                throw AIResonanceDistributionError.modelUnavailable
            }
            try Task.checkCancellation()
            guard self.distributedModel?.distributionIdentity == key else { throw CancellationError() }
            _ = try await self.installValidated(modelData: data, descriptor: descriptor)
            try Task.checkCancellation()
            guard self.distributedModel?.distributionIdentity == key,
                  let identity = self.activeIdentity() else { throw CancellationError() }
            return identity
        }
        distributionPreparation = (preparationID, key, task)
        defer {
            if distributionPreparation?.id == preparationID { distributionPreparation = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private func matches(
        _ status: AudioTrainingInstalledModelStatus,
        _ descriptor: AudioTrainingModelInstallDescriptor
    ) -> Bool {
        status.id == descriptor.id && status.version == descriptor.version
            && status.sha256.lowercased() == descriptor.sha256.lowercased()
            && status.featureSchemaVersion == descriptor.featureSchemaVersion
            && status.targetSchemaVersion == descriptor.targetSchemaVersion
    }

    private func canUse(_ status: AudioTrainingInstalledModelStatus) -> Bool {
        AppConfig.DeveloperAccess.hasFullTools || distributedModel.map { matches(status, $0) } == true
    }

    func install(
        modelData: Data,
        descriptor: AudioTrainingModelInstallDescriptor
    ) async throws -> AudioTrainingInstalledModelStatus {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        return try await installValidated(modelData: modelData, descriptor: descriptor)
    }

    private func installValidated(
        modelData: Data,
        descriptor: AudioTrainingModelInstallDescriptor
    ) async throws -> AudioTrainingInstalledModelStatus {
        guard !isInstalling else { throw AIResonanceDistributionError.installationInProgress }
        isInstalling = true
        defer { isInstalling = false }
        AppLogger.info(
            "[LocalModel] Install started version=\(descriptor.version) bytes=\(modelData.count) featureSchema=\(descriptor.featureSchemaVersion) targetSchema=\(descriptor.targetSchemaVersion)",
            step: "local-model.install-started",
            category: .localModel,
            event: "local-model.install-started"
        )
        guard descriptor.byteCount == modelData.count,
              let inputWidth = Self.inputWidth(
                  forFeatureSchemaVersion: descriptor.featureSchemaVersion
              ),
              (1...4).contains(descriptor.targetSchemaVersion),
              (descriptor.featureSchemaVersion < 6 && descriptor.targetSchemaVersion <= 3)
                || (descriptor.featureSchemaVersion == 6 && descriptor.targetSchemaVersion == 3)
                || (descriptor.featureSchemaVersion == 7 && descriptor.targetSchemaVersion == 4) else {
            throw AudioTrainingOnDeviceModelError.unsupportedSchema
        }
        let digest = Self.sha256(modelData)
        guard digest.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
            throw AudioTrainingOnDeviceModelError.integrityCheckFailed
        }

        let root = try rootDirectory()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var excludedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excludedRoot.setResourceValues(values)

        let candidate = root.appendingPathComponent(
            "candidate-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        do {
            let sourceModelFileName = descriptor.downloadFileName
            let source = candidate.appendingPathComponent(sourceModelFileName)
            try modelData.write(to: source, options: [.atomic, .completeFileProtection])
            let compiledTemporary = try await MLModel.compileModel(at: source)
            defer { try? fileManager.removeItem(at: compiledTemporary) }
            try Task.checkCancellation()
            let compiled = candidate.appendingPathComponent(Self.compiledModelName, isDirectory: true)
            try fileManager.moveItem(at: compiledTemporary, to: compiled)

            let status = AudioTrainingInstalledModelStatus(
                id: descriptor.id,
                version: descriptor.version,
                sha256: digest,
                byteCount: descriptor.byteCount,
                featureSchemaVersion: descriptor.featureSchemaVersion,
                targetSchemaVersion: descriptor.targetSchemaVersion,
                completeSampleCount: descriptor.completeSampleCount,
                legacySampleCount: descriptor.legacySampleCount,
                learningConditionedSampleCount: descriptor.learningConditionedSampleCount,
                deviceConditionedSampleCount: descriptor.deviceConditionedSampleCount,
                completeAccountCount: descriptor.completeAccountCount,
                completeBranchSampleCounts: descriptor.completeBranchSampleCounts.isEmpty
                    ? nil
                    : descriptor.completeBranchSampleCounts,
                completeBranchAccountCounts: descriptor.completeBranchAccountCounts.isEmpty
                    ? nil
                    : descriptor.completeBranchAccountCounts,
                qualityWarnings: descriptor.qualityWarnings.isEmpty ? nil : descriptor.qualityWarnings,
                installedAt: Date(),
                sourceModelFileName: sourceModelFileName
            )
            let model = try loadAndValidateModel(at: compiled, status: status)
            _ = try predictionValues(
                model: model,
                features: Array(repeating: 0, count: inputWidth),
                expectedInputWidth: inputWidth,
                expectedOutputWidth: Self.targetNames(
                    forFeatureSchemaVersion: descriptor.featureSchemaVersion
                ).count
            )
            try writeManifest(status, in: candidate)
            try Task.checkCancellation()
            try activateCandidate(candidate, root: root)
            onDeviceSettings.isEnabled = true
            try persistSettings()
            loadedModel = nil
            loadedIdentity = nil
            loadedInputMean = nil
            latestInferenceTrace = nil
            _ = try loadActiveModel(status: status, root: root)
            AppLogger.success(
                "[LocalModel] Installed and activated version=\(status.version) source=\(status.sourceModelRelativePath ?? "none") bytes=\(status.byteCount) completeSamples=\(status.completeSampleCount) deviceSamples=\(status.deviceConditionedSampleCount ?? 0)",
                step: "local-model.installed",
                category: .localModel,
                event: "local-model.installed"
            )
            return status
        } catch {
            try? fileManager.removeItem(at: candidate)
            AppLogger.failure(
                error,
                message: "[LocalModel] Install failed version=\(descriptor.version)",
                step: "local-model.install-failed",
                category: .localModel,
                event: "local-model.install-failed"
            )
            throw error
        }
    }

    func rollback() throws -> AudioTrainingInstalledModelStatus {
        guard !isInstalling else { throw AIResonanceDistributionError.installationInProgress }
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        let root = try rootDirectory()
        let fileManager = FileManager.default
        let current = root.appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
        let previous = root.appendingPathComponent(Self.previousDirectoryName, isDirectory: true)
        guard let status = try readManifestIfPresent(in: previous) else {
            throw AudioTrainingOnDeviceModelError.noRollbackModel
        }
        let previousModelURL = previous.appendingPathComponent(Self.compiledModelName, isDirectory: true)
        _ = try loadAndValidateModel(at: previousModelURL, status: status)

        let swap = root.appendingPathComponent("rollback-swap-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: current.path) {
            try fileManager.moveItem(at: current, to: swap)
        }
        do {
            try fileManager.moveItem(at: previous, to: current)
            if fileManager.fileExists(atPath: swap.path) {
                try fileManager.moveItem(at: swap, to: previous)
            }
        } catch {
            if !fileManager.fileExists(atPath: current.path),
               fileManager.fileExists(atPath: swap.path) {
                try? fileManager.moveItem(at: swap, to: current)
            }
            throw error
        }
        loadedModel = nil
        loadedIdentity = nil
        loadedInputMean = nil
        latestInferenceTrace = nil
        onDeviceSettings.isEnabled = true
        try persistSettings()
        _ = try loadActiveModel(status: status, root: root)
        AppLogger.success(
            "[LocalModel] Rollback activated version=\(status.version)",
            step: "local-model.rollback",
            category: .localModel,
            event: "local-model.rollback"
        )
        return status
    }

    func deactivate() throws {
        guard !isInstalling else { throw AIResonanceDistributionError.installationInProgress }
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        let root = try rootDirectory()
        let fileManager = FileManager.default
        let current = root.appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: current.path) else {
            throw AudioTrainingOnDeviceModelError.noActiveModel
        }
        let previous = root.appendingPathComponent(Self.previousDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: previous.path) {
            try fileManager.removeItem(at: previous)
        }
        try fileManager.moveItem(at: current, to: previous)
        loadedModel = nil
        loadedIdentity = nil
        loadedInputMean = nil
        latestInferenceTrace = nil
        onDeviceSettings.isEnabled = false
        try persistSettings()
        AppLogger.info(
            "[LocalModel] Active model deactivated and retained as rollback candidate",
            step: "local-model.deactivated",
            category: .localModel,
            event: "local-model.deactivated"
        )
    }

    func predict(
        features: AIEqualizerAudioFeatures,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?,
        tuningIntensity: AIEqualizerTuningIntensity,
        tuningProfile: AIEqualizerTuningProfile,
        learningContext: AIEqualizerLearningContext?,
        deviceTrainingContext: AIEqualizerDeviceTrainingContext,
        expectedModelIdentity: String? = nil
    ) throws -> AudioTrainingOnDevicePrediction {
        if let expectedModelIdentity, activeIdentity() != expectedModelIdentity {
            throw AIResonanceDistributionError.modelUnavailable
        }
        guard onDeviceSettings.isEnabled else {
            throw AudioTrainingOnDeviceModelError.modelDisabled
        }
        let mode = features.graphicEQMode
        let root = try rootDirectory()
        let current = root.appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
        guard let status = try readManifestIfPresent(in: current) else {
            throw AudioTrainingOnDeviceModelError.noActiveModel
        }
        guard canUse(status) else { throw AudioTrainingOnDeviceModelError.fullAccessRequired }
        guard status.featureSchemaVersion >= 6 || mode == .tenBand else {
            throw AudioTrainingOnDeviceModelError.unsupportedSchema
        }
        AppLogger.debug(
            "[LocalModel] Inference started version=\(status.version) mode=\(mode.rawValue) profile=\(tuningProfile.rawValue) intensity=\(tuningIntensity.rawValue)",
            step: "local-model.inference-started",
            category: .localModel,
            event: "local-model.inference-started"
        )
        let model = try loadActiveModel(status: status, root: root)
        guard let inputWidth = Self.inputWidth(
            forFeatureSchemaVersion: status.featureSchemaVersion,
            graphicEQMode: mode
        ) else {
            throw AudioTrainingOnDeviceModelError.unsupportedSchema
        }
        let embedsLearningContext = status.featureSchemaVersion >= 4
            && (status.learningConditionedSampleCount ?? 0) >= Self.minimumEmbeddedLearningSamples
        let embedsDetailedDeviceContext = status.featureSchemaVersion >= 5
            && (status.deviceConditionedSampleCount ?? 0) >= Self.minimumDetailedDeviceSamples
        let input = Self.featureVector(
            features,
            deviceTuningTarget: deviceTuningTarget,
            tuningIntensity: tuningIntensity,
            tuningProfile: tuningProfile,
            learningContext: embedsLearningContext ? learningContext : nil,
            deviceTrainingContext: embedsDetailedDeviceContext ? deviceTrainingContext : nil,
            featureSchemaVersion: status.featureSchemaVersion,
            graphicEQMode: mode
        )
        let outputWidth = Self.targetNames(forFeatureSchemaVersion: status.featureSchemaVersion).count
        let startedAt = ProcessInfo.processInfo.systemUptime
        let rawValues = try predictionValues(
            model: model,
            features: input,
            expectedInputWidth: inputWidth,
            expectedOutputWidth: outputWidth
        )
        // Blend the track-specific correction into the population prior in
        // proportion to how well this branch is covered by complete samples
        // from independent accounts. A branch the model has barely seen plays
        // the prior; a well-covered branch plays the full prediction.
        let branchKey = "\(mode.rawValue):\(tuningProfile.rawValue)"
        let trackCorrectionStrength = status.trackCorrectionStrength(forBranch: branchKey)
        var values = rawValues
        var priorInputValues: [Float] = []
        var priorOutputValues: [Float] = []
        if trackCorrectionStrength < 1,
           let priorInput = Self.priorConditioningVector(
               mean: loadedInputMean,
               featureSchemaVersion: status.featureSchemaVersion,
               graphicEQMode: mode,
               tuningProfile: tuningProfile,
               tuningIntensity: tuningIntensity
           ) {
            let priorValues = try predictionValues(
                model: model,
                features: priorInput,
                expectedInputWidth: inputWidth,
                expectedOutputWidth: outputWidth
            )
            values = zip(priorValues, rawValues).map { prior, full in
                prior + (full - prior) * trackCorrectionStrength
            }
            priorInputValues = priorInput
            priorOutputValues = priorValues
        }
        let inference = Self.inferenceTrace(
            version: status.version,
            input: input,
            output: rawValues,
            featureSchemaVersion: status.featureSchemaVersion,
            latencyMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
            priorInput: priorInputValues,
            priorOutput: priorOutputValues,
            blendedOutput: values,
            trackCorrectionStrength: trackCorrectionStrength
        )
        latestInferenceTrace = inference
        let decoded = Self.modelOutput(
            values,
            status: status,
            features: features,
            deviceTuningTarget: deviceTuningTarget,
            tuningProfile: tuningProfile,
            settings: onDeviceSettings
        )
        var output = decoded.output
        let fallbackOutputCount = decoded.fallbackCount
        if trackCorrectionStrength == 1 || !priorOutputValues.isEmpty {
            output.confidenceCalibration = loadedConfidenceCalibration?.evidence(
                for: branchKey, trackCorrectionStrength: trackCorrectionStrength
            )
        }
        output.confidence = Float(output.confidenceCalibration?.coverage ?? 0)
        let populationOutput: AIEqualizerModelOutput?
        let populationInference: AudioTrainingInferenceTrace?
        if embedsLearningContext, learningContext?.isActive == true {
            let populationInput = Self.featureVector(
                features,
                deviceTuningTarget: deviceTuningTarget,
                tuningIntensity: tuningIntensity,
                tuningProfile: tuningProfile,
                learningContext: nil,
                deviceTrainingContext: embedsDetailedDeviceContext ? deviceTrainingContext : nil,
                featureSchemaVersion: status.featureSchemaVersion,
                graphicEQMode: mode
            )
            let populationStartedAt = ProcessInfo.processInfo.systemUptime
            let populationValues = try predictionValues(
                model: model,
                features: populationInput,
                expectedInputWidth: inputWidth,
                expectedOutputWidth: Self.targetNames(
                    forFeatureSchemaVersion: status.featureSchemaVersion
                ).count
            )
            let populationBlended = priorOutputValues.isEmpty ? populationValues
                : zip(priorOutputValues, populationValues).map { prior, full in
                    prior + (full - prior) * trackCorrectionStrength
                }
            populationInference = Self.inferenceTrace(
                version: status.version,
                input: populationInput,
                output: populationValues,
                featureSchemaVersion: status.featureSchemaVersion,
                latencyMilliseconds: (
                    ProcessInfo.processInfo.systemUptime - populationStartedAt
                ) * 1_000,
                priorInput: priorInputValues,
                priorOutput: priorOutputValues,
                blendedOutput: populationBlended,
                trackCorrectionStrength: trackCorrectionStrength
            )
            populationOutput = Self.modelOutput(
                populationBlended,
                status: status,
                features: features,
                deviceTuningTarget: deviceTuningTarget,
                tuningProfile: tuningProfile,
                settings: onDeviceSettings
            ).output
        } else {
            populationOutput = nil
            populationInference = nil
        }
        AppLogger.success(
            "[LocalModel] Inference completed version=\(status.version) mode=\(mode.rawValue) profile=\(tuningProfile.rawValue) input=\(inference.input.count) output=\(inference.rawOutput.count) latencyMS=\(String(format: "%.3f", inference.latencyMilliseconds)) learning=\(embedsLearningContext) device=\(embedsDetailedDeviceContext) populationPass=\(populationInference != nil) trackCorrection=\(String(format: "%.2f", trackCorrectionStrength)) fallbackOutputs=\(fallbackOutputCount)",
            step: "local-model.inference-completed",
            category: .localModel,
            event: "local-model.inference-completed"
        )
        if fallbackOutputCount > 0 {
            AppLogger.warning(
                "[LocalModel] \(fallbackOutputCount) model outputs left their valid range and used compiler defaults version=\(status.version) branch=\(branchKey)",
                step: "local-model.inference-fallback-outputs",
                category: .localModel,
                event: "local-model.inference-fallback-outputs"
            )
        }
        return AudioTrainingOnDevicePrediction(
            output: output,
            populationOutput: populationOutput,
            modelVersion: status.version,
            featureSchemaVersion: status.featureSchemaVersion,
            targetSchemaVersion: status.targetSchemaVersion,
            graphicEQMode: mode,
            computeMode: onDeviceSettings.computeMode,
            embedsLearningContext: embedsLearningContext,
            embedsDetailedDeviceContext: embedsDetailedDeviceContext,
            trackCorrectionStrength: trackCorrectionStrength,
            fallbackOutputCount: fallbackOutputCount,
            inference: inference,
            populationInference: populationInference,
            confidenceCalibration: loadedConfidenceCalibration,
            modelID: status.id,
            modelSHA256: status.sha256
        )
    }

    /// Mirrors the trainer's legacy conditioning input: population mean for every
    /// measurement, inactive band branch and learning context zeroed, and the
    /// requested mode/profile/intensity one-hots set.
    private static func priorConditioningVector(
        mean: [Float]?,
        featureSchemaVersion: Int,
        graphicEQMode: GraphicEQMode,
        tuningProfile: AIEqualizerTuningProfile,
        tuningIntensity: AIEqualizerTuningIntensity
    ) -> [Float]? {
        guard featureSchemaVersion >= 6,
              let mean,
              let names = featureNames(forFeatureSchemaVersion: featureSchemaVersion),
              names.count == mean.count else {
            return nil
        }
        let inactivePrefix = graphicEQMode == .thirtyTwoBand ? "tenBand." : "thirtyTwoBand."
        var raw = mean
        for (index, name) in names.enumerated() {
            if name.hasPrefix(inactivePrefix) || name.hasPrefix("learning.") {
                raw[index] = 0
            } else if name == "graphicEQMode.thirtyTwoBand" {
                raw[index] = graphicEQMode == .thirtyTwoBand ? 1 : 0
            } else if name.hasPrefix("tuningProfile.") {
                raw[index] = name == "tuningProfile.\(tuningProfile.rawValue)" ? 1 : 0
            } else if name.hasPrefix("tuningIntensity.") {
                raw[index] = name == "tuningIntensity.\(tuningIntensity.rawValue)" ? 1 : 0
            }
        }
        return raw
    }

    func lastInferenceTrace() throws -> AudioTrainingInferenceTrace? {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        return latestInferenceTrace
    }

    func testActiveModel() throws -> AudioTrainingModelTestResult {
        guard AppConfig.DeveloperAccess.hasFullTools else {
            throw AudioTrainingOnDeviceModelError.fullAccessRequired
        }
        let root = try rootDirectory()
        let current = root.appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
        guard let status = try readManifestIfPresent(in: current) else {
            throw AudioTrainingOnDeviceModelError.noActiveModel
        }
        let model = try loadActiveModel(status: status, root: root)
        AppLogger.info(
            "[LocalModel] Self-test started version=\(status.version) featureSchema=\(status.featureSchemaVersion) targetSchema=\(status.targetSchemaVersion)",
            step: "local-model.self-test-started",
            category: .localModel,
            event: "local-model.self-test-started"
        )
        guard let featureNames = Self.featureNames(
            forFeatureSchemaVersion: status.featureSchemaVersion
        ) else {
            throw AudioTrainingOnDeviceModelError.unsupportedSchema
        }
        let inputWidth = featureNames.count
        let zero = Array(repeating: Float(0), count: inputWidth)
        let ramp = (0..<inputWidth).map { index in
            Float(index) / Float(inputWidth - 1) * 2 - 1
        }
        let alternating = (0..<inputWidth).map { $0.isMultiple(of: 2) ? Float(1) : -1 }
        var vectors = [zero, ramp, alternating, zero]
        var identifiers = ["zero", "ramp", "alternating", "zero-repeat"]
        if status.featureSchemaVersion >= 6,
           let modeIndex = featureNames.firstIndex(of: "graphicEQMode.thirtyTwoBand") {
            var tenBand = zero
            var thirtyTwoBand = zero
            thirtyTwoBand[modeIndex] = 1
            for (index, name) in featureNames.enumerated() {
                if name.hasPrefix("tenBand.bandEnergyDB.") {
                    tenBand[index] = -18 + Float(index % 10) * 0.5
                } else if name.hasPrefix("thirtyTwoBand.bandEnergyDB.") {
                    thirtyTwoBand[index] = -24 + Float(index % 32) * 0.35
                }
            }
            vectors.append(contentsOf: [tenBand, thirtyTwoBand])
            identifiers.append(contentsOf: ["mode-10-band", "mode-32-band"])
        }
        var tenBandTuningProfileCaseIndices: (first: Int, second: Int)?
        var thirtyTwoBandTuningProfileCaseIndices: (first: Int, second: Int)?
        if status.featureSchemaVersion >= 2,
           let standardIndex = featureNames.firstIndex(of: "tuningProfile.standard"),
           let spatialIndex = featureNames.firstIndex(of: "tuningProfile.monoSpatialEnhancement") {
            var tenBandStandard = zero
            var tenBandSpatial = zero
            tenBandStandard[standardIndex] = 1
            tenBandSpatial[spatialIndex] = 1
            tenBandTuningProfileCaseIndices = (vectors.count, vectors.count + 1)
            vectors.append(contentsOf: [tenBandStandard, tenBandSpatial])
            identifiers.append(contentsOf: ["profile-10-standard", "profile-10-spatial"])

            if status.featureSchemaVersion >= 6,
               let modeIndex = featureNames.firstIndex(of: "graphicEQMode.thirtyTwoBand") {
                var thirtyTwoBandStandard = tenBandStandard
                var thirtyTwoBandSpatial = tenBandSpatial
                thirtyTwoBandStandard[modeIndex] = 1
                thirtyTwoBandSpatial[modeIndex] = 1
                thirtyTwoBandTuningProfileCaseIndices = (vectors.count, vectors.count + 1)
                vectors.append(contentsOf: [thirtyTwoBandStandard, thirtyTwoBandSpatial])
                identifiers.append(contentsOf: ["profile-32-standard", "profile-32-spatial"])
            }
        }
        var styleCaseIndices: (first: Int, second: Int)?
        let genrePrefix = status.featureSchemaVersion >= 3 ? "genreScore" : "genreHint"
        if status.featureSchemaVersion >= 2,
           let rockIndex = featureNames.firstIndex(of: "\(genrePrefix).rock"),
           let balladIndex = featureNames.firstIndex(of: "\(genrePrefix).ballad") {
            var rock = zero
            var ballad = zero
            rock[rockIndex] = 1
            ballad[balladIndex] = 1
            styleCaseIndices = (vectors.count, vectors.count + 1)
            vectors.append(contentsOf: [rock, ballad])
            identifiers.append(contentsOf: ["style-rock", "style-ballad"])
        }
        var trackCaseIndices: (first: Int, second: Int)?
        if status.featureSchemaVersion >= 3,
           let rockIndex = featureNames.firstIndex(of: "genreScore.rock") {
            var firstTrack = zero
            var secondTrack = zero
            firstTrack[rockIndex] = 0.8
            secondTrack[rockIndex] = 0.8
            for (index, name) in featureNames.enumerated() {
                if name.contains("bandEnergySpreadDB.") {
                    firstTrack[index] = 2
                    secondTrack[index] = 10
                } else if name.contains("sectionBandEnergyDB.") {
                    firstTrack[index] = name.contains(".0.") ? -4 : -18
                    secondTrack[index] = name.contains(".2.") ? -3 : -22
                }
            }
            trackCaseIndices = (vectors.count, vectors.count + 1)
            vectors.append(contentsOf: [firstTrack, secondTrack])
            identifiers.append(contentsOf: ["track-rock-a", "track-rock-b"])
        }
        var learningCaseIndices: (first: Int, second: Int)?
        if status.featureSchemaVersion >= 4,
           (status.learningConditionedSampleCount ?? 0) >= Self.minimumEmbeddedLearningSamples,
           let activeIndex = featureNames.firstIndex(of: "learning.active"),
           let confidenceIndex = featureNames.firstIndex(of: "learning.confidence"),
           let evidenceIndex = featureNames.firstIndex(of: "learning.evidenceCount") {
            var warm = zero
            var cool = zero
            warm[activeIndex] = 1
            cool[activeIndex] = 1
            warm[confidenceIndex] = 0.35
            cool[confidenceIndex] = 0.35
            warm[evidenceIndex] = 12
            cool[evidenceIndex] = 12
            for (index, name) in featureNames.enumerated() {
                if name.contains("learning.bandAdjustments.") {
                    warm[index] = 1
                    cool[index] = -1
                } else if name == "learning.bassAdjustment" {
                    warm[index] = 0.8
                    cool[index] = -0.8
                }
            }
            learningCaseIndices = (vectors.count, vectors.count + 1)
            vectors.append(contentsOf: [warm, cool])
            identifiers.append(contentsOf: ["learning-warm", "learning-cool"])
        }
        var deviceCaseIndices: (first: Int, second: Int)?
        if status.featureSchemaVersion >= 5,
           (status.deviceConditionedSampleCount ?? 0) >= Self.minimumDetailedDeviceSamples,
           let activeIndex = featureNames.firstIndex(of: "device.detailActive"),
           let opraIndex = featureNames.firstIndex(of: "device.profileSource.opra"),
           let customIndex = featureNames.firstIndex(of: "device.profileSource.custom") {
            var opra = zero
            var custom = zero
            opra[activeIndex] = 1
            custom[activeIndex] = 1
            opra[opraIndex] = 1
            custom[customIndex] = 1
            for (index, name) in featureNames.enumerated() {
                if name.hasPrefix("device.effectiveGainsDB.") {
                    opra[index] = index.isMultiple(of: 2) ? 2 : -1
                    custom[index] = index.isMultiple(of: 2) ? -2 : 1
                } else if name == "device.profilePreampDB" {
                    opra[index] = -4
                    custom[index] = -1
                }
            }
            deviceCaseIndices = (vectors.count, vectors.count + 1)
            vectors.append(contentsOf: [opra, custom])
            identifiers.append(contentsOf: ["device-opra", "device-custom"])
        }
        var outputs: [[Float]] = []
        var testCases: [AudioTrainingModelTestCaseResult] = []
        for (index, vector) in vectors.enumerated() {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let output = try predictionValues(
                model: model,
                features: vector,
                expectedInputWidth: inputWidth,
                expectedOutputWidth: Self.targetNames(
                    forFeatureSchemaVersion: status.featureSchemaVersion
                ).count
            )
            let elapsedMilliseconds = (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000
            outputs.append(output)
            testCases.append(
                AudioTrainingModelTestCaseResult(
                    id: identifiers[index],
                    input: Self.tensorValues(names: featureNames, values: vector),
                    rawOutput: Self.tensorValues(
                        names: Self.targetNames(
                            forFeatureSchemaVersion: status.featureSchemaVersion
                        ),
                        values: output
                    ),
                    latencyMilliseconds: elapsedMilliseconds
                )
            )
        }
        let flattened = outputs.flatMap { $0 }
        guard let minimum = flattened.min(), let maximum = flattened.max() else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        let deterministic = zip(outputs[0], outputs[3]).allSatisfy {
            abs($0.0 - $0.1) <= 0.000_001
        }
        guard deterministic else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        let responseDelta = outputs[1...2].flatMap { output in
            zip(outputs[0], output).map { abs($0 - $1) }
        }.max() ?? 0
        let styleResponseDelta: Float
        if let indices = styleCaseIndices {
            styleResponseDelta = zip(outputs[indices.first], outputs[indices.second])
                .map { abs($0 - $1) }
                .max() ?? 0
        } else {
            styleResponseDelta = 0
        }
        let trackResponseDelta: Float
        if let indices = trackCaseIndices {
            trackResponseDelta = zip(outputs[indices.first], outputs[indices.second])
                .map { abs($0 - $1) }
                .max() ?? 0
        } else {
            trackResponseDelta = 0
        }
        let learningResponseDelta: Float
        if let indices = learningCaseIndices {
            learningResponseDelta = zip(outputs[indices.first], outputs[indices.second])
                .map { abs($0 - $1) }
                .max() ?? 0
        } else {
            learningResponseDelta = 0
        }
        let deviceResponseDelta: Float
        if let indices = deviceCaseIndices {
            deviceResponseDelta = zip(outputs[indices.first], outputs[indices.second])
                .map { abs($0 - $1) }
                .max() ?? 0
        } else {
            deviceResponseDelta = 0
        }
        let modelTargetNames = Self.targetNames(
            forFeatureSchemaVersion: status.featureSchemaVersion
        )
        let profileTargetIndices = modelTargetNames.enumerated().compactMap { index, name in
            name.hasPrefix("spatial.")
                || name == "enhance.stageWidth"
                || name == "effects.haasDelayMS"
                || name == "effects.haasEnabled"
                ? index
                : nil
        }
        func tuningProfileResponseDelta(
            _ indices: (first: Int, second: Int)?
        ) -> Float {
            guard let indices else { return 0 }
            return profileTargetIndices.map { outputIndex in
                abs(outputs[indices.first][outputIndex] - outputs[indices.second][outputIndex])
            }.max() ?? 0
        }
        let tenBandTuningProfileResponseDelta = tuningProfileResponseDelta(
            tenBandTuningProfileCaseIndices
        )
        let thirtyTwoBandTuningProfileResponseDelta = tuningProfileResponseDelta(
            thirtyTwoBandTuningProfileCaseIndices
        )
        let tuningProfileResponseDelta = max(
            tenBandTuningProfileResponseDelta,
            thirtyTwoBandTuningProfileResponseDelta
        )
        let targetIndices = Dictionary(uniqueKeysWithValues: modelTargetNames.enumerated().map {
            ($0.element, $0.offset)
        })
        func tuningProfileContractSatisfied(
            _ indices: (first: Int, second: Int)?
        ) -> Bool {
            guard let indices,
                  let surroundIndex = targetIndices["spatial.surroundLevel"],
                  let stereoWidthIndex = targetIndices["spatial.stereoWidth"],
                  let stageWidthIndex = targetIndices["enhance.stageWidth"] else {
                return false
            }
            let standard = outputs[indices.first]
            let spatial = outputs[indices.second]
            return spatial[surroundIndex] - standard[surroundIndex] >= 0.02
                && spatial[stereoWidthIndex] - standard[stereoWidthIndex] >= 0.03
                && spatial[stageWidthIndex] - standard[stageWidthIndex] >= 0.02
        }
        let tuningProfileSensitive = tuningProfileContractSatisfied(
            tenBandTuningProfileCaseIndices
        ) && (status.featureSchemaVersion < 6
            || tuningProfileContractSatisfied(thirtyTwoBandTuningProfileCaseIndices))
        let result = AudioTrainingModelTestResult(
            version: status.version,
            testCaseCount: vectors.count,
            averageLatencyMilliseconds: testCases.reduce(0) {
                $0 + $1.latencyMilliseconds
            } / Double(testCases.count),
            outputMinimum: minimum,
            outputMaximum: maximum,
            isDeterministic: deterministic,
            isInputSensitive: responseDelta > 0.000_001,
            maximumInputResponseDelta: responseDelta,
            isStyleSensitive: styleResponseDelta > 0.000_001,
            maximumStyleResponseDelta: styleResponseDelta,
            isTrackSensitive: trackResponseDelta > 0.000_001,
            maximumTrackResponseDelta: trackResponseDelta,
            isLearningSensitive: learningResponseDelta > 0.000_001,
            maximumLearningResponseDelta: learningResponseDelta,
            isDeviceSensitive: deviceResponseDelta > 0.000_001,
            maximumDeviceResponseDelta: deviceResponseDelta,
            isTuningProfileSensitive: tuningProfileSensitive,
            maximumTuningProfileResponseDelta: tuningProfileResponseDelta,
            tenBandTuningProfileResponseDelta: tenBandTuningProfileResponseDelta,
            thirtyTwoBandTuningProfileResponseDelta: thirtyTwoBandTuningProfileResponseDelta,
            testCases: testCases
        )
        let resultMessage = "[LocalModel] Self-test completed version=\(status.version) cases=\(result.testCaseCount) deterministic=\(result.isDeterministic) inputSensitive=\(result.isInputSensitive) styleSensitive=\(result.isStyleSensitive) trackSensitive=\(result.isTrackSensitive) profileContract=\(result.isTuningProfileSensitive) profile10Delta=\(result.tenBandTuningProfileResponseDelta) profile32Delta=\(result.thirtyTwoBandTuningProfileResponseDelta) learningSensitive=\(result.isLearningSensitive) deviceSensitive=\(result.isDeviceSensitive)"
        if result.isTuningProfileSensitive {
            AppLogger.success(
                resultMessage,
                step: "local-model.self-test-completed",
                category: .localModel,
                event: "local-model.self-test-completed"
            )
        } else {
            AppLogger.warning(
                resultMessage,
                step: "local-model.self-test-profile-failed",
                category: .localModel,
                event: "local-model.self-test-profile-failed"
            )
        }
        return result
    }

    private func activateCandidate(_ candidate: URL, root: URL) throws {
        let fileManager = FileManager.default
        let current = root.appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
        let previous = root.appendingPathComponent(Self.previousDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: previous.path) {
            try fileManager.removeItem(at: previous)
        }
        if fileManager.fileExists(atPath: current.path) {
            try fileManager.moveItem(at: current, to: previous)
        }
        do {
            try fileManager.moveItem(at: candidate, to: current)
        } catch {
            if !fileManager.fileExists(atPath: current.path),
               fileManager.fileExists(atPath: previous.path) {
                try? fileManager.moveItem(at: previous, to: current)
            }
            throw error
        }
    }

    private func loadActiveModel(
        status: AudioTrainingInstalledModelStatus,
        root: URL
    ) throws -> MLModel {
        if loadedIdentity == status.identity, let loadedModel {
            return loadedModel
        }
        let modelURL = root
            .appendingPathComponent(Self.currentDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.compiledModelName, isDirectory: true)
        let model = try loadAndValidateModel(at: modelURL, status: status)
        loadedModel = model
        loadedIdentity = status.identity
        let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        loadedConfidenceCalibration = metadata?["mono.confidence_calibration"]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(AudioTrainingConfidenceCalibration.self, from: $0) }
        let inputMean = Self.floatArray(metadata?["mono.input_mean"])
        loadedInputMean = inputMean?.count == Self.inputWidth(
            forFeatureSchemaVersion: status.featureSchemaVersion
        ) ? inputMean : nil
        AppLogger.info(
            "[LocalModel] Loaded version=\(status.version) compute=\(onDeviceSettings.computeMode.rawValue) input=\(Self.inputWidth(forFeatureSchemaVersion: status.featureSchemaVersion) ?? 0) output=\(Self.targetNames(forFeatureSchemaVersion: status.featureSchemaVersion).count) priorBlend=\(loadedInputMean != nil)",
            step: "local-model.loaded",
            category: .localModel,
            event: "local-model.loaded"
        )
        return model
    }

    private func loadAndValidateModel(
        at url: URL,
        status: AudioTrainingInstalledModelStatus
    ) throws -> MLModel {
        guard let featureNames = Self.featureNames(
            forFeatureSchemaVersion: status.featureSchemaVersion
        ) else {
            throw AudioTrainingOnDeviceModelError.unsupportedSchema
        }
        let inputWidth = featureNames.count
        let targetNames = Self.targetNames(
            forFeatureSchemaVersion: status.featureSchemaVersion
        )
        let configuration = MLModelConfiguration()
        switch onDeviceSettings.computeMode {
        case .all:
            configuration.computeUnits = .all
        case .cpuAndGPU:
            configuration.computeUnits = .cpuAndGPU
        case .cpuOnly:
            configuration.computeUnits = .cpuOnly
        }
        let model = try MLModel(contentsOf: url, configuration: configuration)
        guard let input = model.modelDescription.inputDescriptionsByName["features"],
              input.type == .multiArray,
              input.multiArrayConstraint?.shape.map(\.intValue) == [inputWidth],
              let output = model.modelDescription.outputDescriptionsByName["tuning"],
              output.type == .multiArray,
              output.multiArrayConstraint?.shape.map(\.intValue) == [targetNames.count],
              let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
              metadata["mono.model_id"] == status.id,
              metadata["mono.model_version"] == status.version,
              Int(metadata["mono.feature_schema_version"] ?? "") == status.featureSchemaVersion,
              Int(metadata["mono.target_schema_version"] ?? "") == status.targetSchemaVersion,
              status.featureSchemaVersion < 6
                || Self.stringArray(metadata["mono.graphic_eq_modes"])
                    == [GraphicEQMode.tenBand.rawValue, GraphicEQMode.thirtyTwoBand.rawValue],
              Self.stringArray(metadata["mono.feature_names"]) == featureNames,
              Self.stringArray(metadata["mono.target_names"]) == targetNames else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        return model
    }

    private func predictionValues(
        model: MLModel,
        features: [Float],
        expectedInputWidth: Int,
        expectedOutputWidth: Int
    ) throws -> [Float] {
        guard features.count == expectedInputWidth, features.allSatisfy(\.isFinite) else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        let input = try MLMultiArray(
            shape: [NSNumber(value: expectedInputWidth)],
            dataType: .float32
        )
        for (index, value) in features.enumerated() {
            input[index] = NSNumber(value: value)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["features": input])
        let result = try model.prediction(from: provider)
        guard let output = result.featureValue(for: "tuning")?.multiArrayValue,
              output.count == expectedOutputWidth else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        let values = (0..<output.count).map { output[$0].floatValue }
        guard values.allSatisfy(\.isFinite) else {
            throw AudioTrainingOnDeviceModelError.invalidModel
        }
        return values
    }

    private func rootDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw AudioTrainingOnDeviceModelError.storageUnavailable
        }
        let root = documents.appendingPathComponent("MonoAudioTrainingModels", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path),
           let applicationSupport = fileManager.urls(
               for: .applicationSupportDirectory,
               in: .userDomainMask
           ).first {
            let legacyRoot = applicationSupport.appendingPathComponent(
                "MonoAudioTrainingModels",
                isDirectory: true
            )
            if fileManager.fileExists(atPath: legacyRoot.path) {
                try fileManager.moveItem(at: legacyRoot, to: root)
            }
        }
        return root
    }

    private func readManifestIfPresent(
        in directory: URL
    ) throws -> AudioTrainingInstalledModelStatus? {
        let fileManager = FileManager.default
        let modelURL = directory.appendingPathComponent(Self.compiledModelName, isDirectory: true)
        let manifestURL = directory.appendingPathComponent(Self.manifestName)
        guard fileManager.fileExists(atPath: modelURL.path),
              fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(
            AudioTrainingInstalledModelStatus.self,
            from: Data(contentsOf: manifestURL)
        )
        if let sourceModelFileName = status.sourceModelFileName {
            guard sourceModelFileName == URL(fileURLWithPath: sourceModelFileName).lastPathComponent
            else {
                throw AudioTrainingOnDeviceModelError.invalidModel
            }
            let sourceURL = directory.appendingPathComponent(sourceModelFileName)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AudioTrainingOnDeviceModelError.storageUnavailable
            }
            let sourceData = try Data(contentsOf: sourceURL)
            guard sourceData.count == status.byteCount,
                  Self.sha256(sourceData).caseInsensitiveCompare(status.sha256) == .orderedSame else {
                throw AudioTrainingOnDeviceModelError.integrityCheckFailed
            }
        }
        return status
    }

    private func writeManifest(
        _ status: AudioTrainingInstalledModelStatus,
        in directory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        try data.write(
            to: directory.appendingPathComponent(Self.manifestName),
            options: [.atomic, .completeFileProtection]
        )
    }

    private func persistSettings() throws {
        let data = try JSONEncoder().encode(onDeviceSettings)
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private static func featureVector(
        _ features: AIEqualizerAudioFeatures,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?,
        tuningIntensity: AIEqualizerTuningIntensity,
        tuningProfile: AIEqualizerTuningProfile,
        learningContext: AIEqualizerLearningContext?,
        deviceTrainingContext: AIEqualizerDeviceTrainingContext?,
        featureSchemaVersion: Int,
        graphicEQMode: GraphicEQMode
    ) -> [Float] {
        let usesDualBandBranches = featureSchemaVersion >= 6
        let bandCount = usesDualBandBranches ? graphicEQMode.bandCount : 10
        var result = usesDualBandBranches
            ? modeBandBranches(graphicEQMode, values: features.bandEnergyDB)
            : linearResample(features.bandEnergyDB, count: 10)
        result.append(contentsOf: [
            Float(features.sampleDuration), Float(features.sampleRate), Float(features.frameCount),
            features.spectralCentroidHz, features.spectralRolloffHz, features.rmsDBFS,
            features.dynamicSpreadDB, features.integratedLUFS, features.shortTermLUFS,
            features.momentaryLUFS, features.loudnessRangeLU, features.samplePeakDBFS,
            features.estimatedTruePeakDBTP, features.crestFactorDB, features.dynamicRangeDR,
            features.clippingRatio, features.phaseCorrelation, features.monoCompatibility,
            features.measuredStereoWidth, features.spectralFlatness, features.spectralBandwidthHz,
            features.spectralFlux, features.lowEnergyRatio, features.midEnergyRatio,
            features.highEnergyRatio, features.estimatedBPM, features.tempoConfidence,
            features.tempoStability, features.keyConfidence, features.dominantPitchHz,
            features.melodyRangeSemitones, features.melodicActivity, features.transientDensity,
            features.currentBassGain, features.currentTrebleGain, features.currentSurroundLevel,
            features.currentReverbLevel, features.currentStereoWidth,
            features.professionalProcessingIntensity
        ])
        result.append(contentsOf: fixed(features.chroma, count: 12))
        let vocal = features.vocalReference
        result.append(contentsOf: [
            vocal?.confidence ?? 0, vocal?.presence ?? 0, vocal?.warmth ?? 0,
            vocal?.brightness ?? 0, vocal?.airiness ?? 0, vocal?.dynamicExpression ?? 0
        ])
        result.append(contentsOf: [
            features.outputCalibrationEnabled, features.loudnessMatchingEnabled,
            features.smartSongCompensationEnabled, features.dynamicEQEnabled,
            features.multibandDynamicsEnabled, features.parametricEQEnabled
        ].map { $0 ? 1 : 0 })
        if usesDualBandBranches {
            result.append(contentsOf: modeBandBranches(
                graphicEQMode,
                values: deviceTuningTarget?.referenceGainsDB ?? []
            ))
        } else {
            result.append(contentsOf: linearResample(
                deviceTuningTarget?.referenceGainsDB ?? [],
                count: 10
            ))
        }
        result.append(features.graphicEQMode == .thirtyTwoBand ? 1 : 0)
        if featureSchemaVersion == 2 {
            result.append(contentsOf: multiHotVector(
                features.genreHints,
                values: genreFeatureValues
            ))
            result.append(contentsOf: multiHotVector(
                features.instrumentHints,
                values: instrumentFeatureValues
            ))
            result.append(contentsOf: oneHotVector(
                features.outputKind,
                values: outputKindFeatureValues,
                fallback: "other"
            ))
            result.append(contentsOf: oneHotVector(
                tuningIntensity.rawValue,
                values: tuningIntensityFeatureValues,
                fallback: AIEqualizerTuningIntensity.smart.rawValue
            ))
            result.append(contentsOf: oneHotVector(
                tuningProfile.rawValue,
                values: tuningProfileFeatureValues,
                fallback: AIEqualizerTuningProfile.standard.rawValue
            ))
        } else if featureSchemaVersion >= 3 {
            result.append(contentsOf: confidenceVector(
                features.genreScores,
                hints: features.genreHints,
                values: genreFeatureValues
            ))
            result.append(contentsOf: confidenceVector(
                features.instrumentScores,
                hints: features.instrumentHints,
                values: instrumentFeatureValues
            ))
            result.append(contentsOf: oneHotVector(
                features.outputKind,
                values: outputKindFeatureValues,
                fallback: "other"
            ))
            result.append(contentsOf: oneHotVector(
                tuningIntensity.rawValue,
                values: tuningIntensityFeatureValues,
                fallback: AIEqualizerTuningIntensity.smart.rawValue
            ))
            result.append(contentsOf: oneHotVector(
                tuningProfile.rawValue,
                values: tuningProfileFeatureValues,
                fallback: AIEqualizerTuningProfile.standard.rawValue
            ))
            let sections = sectionProfiles(
                features.sectionBandEnergyDB,
                fallback: features.bandEnergyDB,
                bandCount: bandCount
            )
            if usesDualBandBranches {
                result.append(contentsOf: modeBandBranches(
                    graphicEQMode,
                    values: features.bandEnergySpreadDB ?? []
                ))
                result.append(contentsOf: modeSectionBranches(
                    graphicEQMode,
                    sections: sections
                ))
            } else {
                result.append(contentsOf: linearResample(
                    features.bandEnergySpreadDB ?? [],
                    count: 10
                ))
                result.append(contentsOf: sections.flatMap { $0 })
            }
            result.append(contentsOf: [
                features.spectralCentroidP10Hz ?? features.spectralCentroidHz,
                features.spectralCentroidP90Hz ?? features.spectralCentroidHz,
                features.spectralRolloffP10Hz ?? features.spectralRolloffHz,
                features.spectralRolloffP90Hz ?? features.spectralRolloffHz,
                features.spectralFluxP90 ?? features.spectralFlux,
                features.rmsP10DBFS ?? features.rmsDBFS - features.dynamicSpreadDB / 2,
                features.rmsP50DBFS ?? features.rmsDBFS,
                features.rmsP90DBFS ?? features.rmsDBFS + features.dynamicSpreadDB / 2
            ])
            if featureSchemaVersion >= 4 {
                result.append(contentsOf: learningVector(
                    learningContext,
                    mode: graphicEQMode,
                    usesDualBandBranches: usesDualBandBranches
                ))
            }
            if featureSchemaVersion >= 5 {
                result.append(contentsOf: deviceContextVector(deviceTrainingContext))
            }
        }
        return result.map { $0.isFinite ? $0 : 0 }
    }

    private static func modelOutput(
        _ values: [Float],
        status: AudioTrainingInstalledModelStatus,
        features: AIEqualizerAudioFeatures,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?,
        tuningProfile: AIEqualizerTuningProfile,
        settings: AudioTrainingOnDeviceSettings
    ) -> (output: AIEqualizerModelOutput, fallbackCount: Int) {
        let mode = features.graphicEQMode
        let bandCount = mode.bandCount
        let gainOffset = status.featureSchemaVersion >= 6 && mode == .thirtyTwoBand ? 10 : 0
        let sharedOffset = status.featureSchemaVersion >= 6 ? 42 : 10
        func value(_ sharedIndex: Int) -> Float {
            values[sharedOffset + sharedIndex]
        }
        var fallbackCount = 0
        func bounded(
            _ value: Float,
            _ minimum: Float,
            _ maximum: Float,
            fallback: Float
        ) -> Float {
            guard value.isFinite, value >= minimum, value <= maximum else {
                fallbackCount += 1
                return fallback
            }
            return value
        }
        let supervised = status.completeSampleCount > 0
        // A supervised model already learned the requested intensity as an
        // explicit input. Scaling its result again from the sample count would
        // erase song/style differences; confidence and advanced-stage gating
        // continue to disclose and contain limited coverage.
        let strength: Float
        if !supervised {
            strength = Float(settings.legacyPriorStrength)
        } else if status.featureSchemaVersion >= 2 {
            strength = 1
        } else {
            strength = min(1, max(0.35, Float(status.completeSampleCount) / 128))
        }
        var gains = Array(values[gainOffset..<(gainOffset + bandCount)]).map {
            clamp($0 * strength, -9, 9)
        }
        if status.targetSchemaVersion == 1, supervised {
            let baseline = linearResample(
                deviceTuningTarget?.referenceGainsDB ?? [],
                count: bandCount
            )
            gains = zip(gains, baseline).map { clamp($0 - $1, -9, 9) }
        }
        let spatialWidth = 1 + (bounded(value(5), 0.65, 1.75, fallback: 1) - 1) * strength
        let canUseLearnedStages = supervised
            && status.completeSampleCount(forBranch: "\(mode.rawValue):\(tuningProfile.rawValue)")
                >= settings.advancedStageMinimumSamples
        let usesDetailedOutputs = status.featureSchemaVersion >= 7
        let detailed = usesDetailedOutputs
            ? Dictionary(uniqueKeysWithValues: zip(Self.professionalTargetNames, values.dropFirst(92)))
            : [:]
        func detail(_ name: String, _ minimum: Float, _ maximum: Float, _ fallback: Float) -> Float {
            bounded(detailed["professional." + name] ?? fallback, minimum, maximum, fallback: fallback)
        }
        var dynamicBands: [AIEqualizerDynamicBandConfiguration] = []
        var parametricBands: [AIEqualizerParametricBandConfiguration] = []
        if usesDetailedOutputs && canUseLearnedStages {
            for slot in 0..<(mode == .thirtyTwoBand ? 3 : 4) {
                let key = "dynamicEQ.bands.\(slot)."
                guard boolean(detailed["professional." + key + "active"] ?? 0),
                      let frequency = detailed["professional." + key + "frequency"],
                      frequency.isFinite, (20...20_000).contains(frequency) else { continue }
                dynamicBands.append(AIEqualizerDynamicBandConfiguration(
                    frequency: frequency, q: detail(key + "q", 0.15, 12, 1),
                    thresholdDB: detail(key + "thresholdDB", -60, 0, -18),
                    ratio: detail(key + "ratio", 1, 8, 1),
                    maxReductionDB: detail(key + "maxReductionDB", 0, 12, 0),
                    attackMS: detail(key + "attackMS", 0.5, 200, 20),
                    releaseMS: detail(key + "releaseMS", 15, 1_000, 180)
                ))
            }
            for slot in 0..<(mode == .thirtyTwoBand ? 3 : 6) {
                let key = "parametricEQ.bands.\(slot)."
                guard boolean(detailed["professional." + key + "active"] ?? 0),
                      let frequency = detailed["professional." + key + "frequency"],
                      frequency.isFinite, (20...20_000).contains(frequency) else { continue }
                let type = Self.parametricTypes.max {
                    (detailed["professional." + key + "type." + $0] ?? 0)
                        < (detailed["professional." + key + "type." + $1] ?? 0)
                } ?? "peak"
                parametricBands.append(AIEqualizerParametricBandConfiguration(
                    type: type, frequency: frequency,
                    gainDB: detail(key + "gainDB", -12, 12, 0),
                    q: detail(key + "q", 0.1, 12, 1)
                ))
            }
        }

        let enhance = MonoEnhanceConfiguration(
            isEnabled: canUseLearnedStages && boolean(value(15)),
            transientAttack: unit(value(6) * strength),
            transientSustain: unit(value(7) * strength),
            vocalFocus: unit(value(8) * strength),
            airAmount: unit(value(9) * strength),
            deEssAmount: unit(value(10) * strength),
            lowFrequencyFocus: unit(value(11) * strength),
            stageWidth: unit(value(12) * strength),
            microDynamics: unit(value(13) * strength),
            lowLevelCompensation: unit(value(14) * strength)
        )
        let multibandEnabled = canUseLearnedStages && boolean(value(21))
        let dynamicEnabled = !dynamicBands.isEmpty && boolean(value(20))
            && (!multibandEnabled || value(20) >= value(21))
        let professional = AIEqualizerProfessionalConfiguration(
            processingIntensity: bounded(value(19) * strength, 0, 2.1, fallback: 0),
            dynamicEQ: AIEqualizerDynamicEQConfiguration(enabled: dynamicEnabled, bands: dynamicBands),
            multiband: AIEqualizerMultibandConfiguration(
                enabled: multibandEnabled && !dynamicEnabled,
                lowCrossoverHz: detail("multiband.lowCrossoverHz", 60, 600, 180),
                highCrossoverHz: detail("multiband.highCrossoverHz", 1_200, 10_000, 3_800),
                thresholdsDB: (0..<3).map { detail("multiband.thresholdsDB.\($0)", -36, -4, [-13, -11, -15][$0]) },
                ratios: (0..<3).map { detail("multiband.ratios.\($0)", 1, 6, [1.45, 1.28, 1.5][$0]) },
                maxReductionDB: (0..<3).map { detail("multiband.maxReductionDB.\($0)", 0, 12, [2.2, 1.8, 2.4][$0]) },
                attackMS: detail("multiband.attackMS", 0.5, 200, 24),
                releaseMS: detail("multiband.releaseMS", 15, 1_000, 190)
            ),
            parametricEQ: AIEqualizerParametricEQConfiguration(
                enabled: !parametricBands.isEmpty && boolean(value(22)), bands: parametricBands
            )
        )
        let haasEnabled = canUseLearnedStages
            && tuningProfile == .monoSpatialEnhancement
            && boolean(value(45))
        let effects = MonoEffectTuningConfiguration(
            loudnessNormalizationEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(40)),
            targetLUFS: bounded(value(23), -30, -8, fallback: -14),
            targetLRA: bounded(value(24), 1, 20, fallback: 9),
            truePeakCeilingDB: bounded(value(25), -6, -0.5, fallback: -1),
            compressorEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(41)),
            compressorThresholdDB: bounded(value(26), -60, -2, fallback: -18),
            compressorRatio: bounded(value(27), 1, 8, fallback: 2),
            compressorAttackMS: bounded(value(28), 1, 500, fallback: 18),
            compressorReleaseMS: bounded(value(29), 10, 2_000, fallback: 180),
            compressorMakeupDB: bounded(value(30), -6, 6, fallback: 0),
            subboostEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(42)),
            subboostGainDB: bounded(value(31), -6, 6, fallback: 0),
            subboostCutoffHz: bounded(value(32), 30, 220, fallback: 90),
            bs2bEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(43)),
            crossfeedEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(44)),
            crossfeedStrength: unit(value(33)),
            haasEnabled: haasEnabled,
            haasDelayMS: bounded(value(34), 1, 30, fallback: 12),
            virtualBassEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(46)),
            virtualBassCutoffHz: bounded(value(35), 40, 320, fallback: 180),
            virtualBassStrength: unit(value(36)),
            exciterEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(47)),
            exciterAmountDB: bounded(value(37), 0, 6, fallback: 0),
            exciterFrequencyHz: bounded(value(38), 2_000, 16_000, fallback: 7_500),
            softclipEnabled: usesDetailedOutputs && canUseLearnedStages && boolean(value(48)),
            finalLimiterEnabled: true,
            finalLimiterCeilingDB: bounded(value(39), -6, -0.8, fallback: -1)
        )
        let output = AIEqualizerModelOutput(
            profileName: String(localized: "audio_training_generated_profile_name"),
            gains: gains,
            preampDB: bounded(value(0) * strength, -18, 0, fallback: 0),
            tone: AIEqualizerToneConfiguration(
                bassGain: clamp(value(1) * strength, -8, 8),
                trebleGain: clamp(value(2) * strength, -8, 8)
            ),
            spatial: AIEqualizerSpatialConfiguration(
                surroundLevel: unit(value(3) * strength),
                reverbLevel: unit(value(4) * strength),
                stereoWidth: spatialWidth
            ),
            enhance: enhance,
            calibration: AIEqualizerCalibrationConfiguration(
                outputCalibrationEnabled: canUseLearnedStages && boolean(value(16)),
                loudnessMatchingEnabled: canUseLearnedStages && boolean(value(17)),
                smartSongCompensationEnabled: canUseLearnedStages && boolean(value(18))
            ),
            professional: professional,
            effects: effects,
            // The adapter attaches held-out coverage from the model metadata.
            // Legacy artifacts without this evidence keep the zero placeholder.
            confidence: 0,
            // Listening copy is composed from the final validated proposal.
            summary: ""
        )
        return (output, fallbackCount)
    }

    private static func fixed(_ values: [Float], count: Int) -> [Float] {
        var result = Array(values.prefix(count))
        if result.count < count {
            result.append(contentsOf: Array(repeating: 0, count: count - result.count))
        }
        return result
    }

    private static func linearResample(_ values: [Float], count: Int) -> [Float] {
        let source = values.map { $0.isFinite ? $0 : 0 }
        guard !source.isEmpty else { return Array(repeating: 0, count: count) }
        guard source.count != count else { return source }
        guard source.count > 1 else { return Array(repeating: source[0], count: count) }
        return (0..<count).map { index in
            let position = Float(index * (source.count - 1)) / Float(max(1, count - 1))
            let lower = Int(position.rounded(.down))
            let upper = min(source.count - 1, lower + 1)
            let fraction = position - Float(lower)
            return source[lower] + (source[upper] - source[lower]) * fraction
        }
    }

    private static func modeBandBranches(
        _ mode: GraphicEQMode,
        values: [Float]
    ) -> [Float] {
        if mode == .thirtyTwoBand {
            return Array(repeating: 0, count: 10) + linearResample(values, count: 32)
        }
        return linearResample(values, count: 10) + Array(repeating: 0, count: 32)
    }

    private static func modeSectionBranches(
        _ mode: GraphicEQMode,
        sections: [[Float]]
    ) -> [Float] {
        let active = sections.flatMap { $0 }
        if mode == .thirtyTwoBand {
            return Array(repeating: 0, count: trackSectionCount * 10) + active
        }
        return active + Array(repeating: 0, count: trackSectionCount * 32)
    }

    private static func stringArray(_ value: String?) -> [String]? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private static func floatArray(_ value: String?) -> [Float]? {
        guard let value, let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Double].self, from: data),
              decoded.allSatisfy(\.isFinite) else {
            return nil
        }
        return decoded.map(Float.init)
    }

    static func inferenceTrace(
        version: String,
        input: [Float],
        output: [Float],
        featureSchemaVersion: Int,
        latencyMilliseconds: Double,
        priorInput: [Float] = [],
        priorOutput: [Float] = [],
        blendedOutput: [Float]? = nil,
        trackCorrectionStrength: Float = 1
    ) -> AudioTrainingInferenceTrace {
        let names = featureNames(forFeatureSchemaVersion: featureSchemaVersion) ?? []
        return AudioTrainingInferenceTrace(
            version: version,
            input: tensorValues(names: names, values: input),
            rawOutput: tensorValues(
                names: targetNames(forFeatureSchemaVersion: featureSchemaVersion),
                values: output
            ),
            latencyMilliseconds: latencyMilliseconds,
            capturedAt: Date(),
            priorInput: tensorValues(names: names, values: priorInput),
            priorOutput: tensorValues(
                names: targetNames(forFeatureSchemaVersion: featureSchemaVersion), values: priorOutput
            ),
            blendedOutput: tensorValues(
                names: targetNames(forFeatureSchemaVersion: featureSchemaVersion),
                values: blendedOutput ?? output
            ),
            trackCorrectionStrength: trackCorrectionStrength
        )
    }

    private static func tensorValues(
        names: [String],
        values: [Float]
    ) -> [AudioTrainingTensorValue] {
        zip(names, values).enumerated().map { index, item in
            AudioTrainingTensorValue(index: index, name: item.0, value: item.1)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func boolean(_ value: Float) -> Bool {
        value.isFinite && value >= 0.5
    }

    private static func unit(_ value: Float) -> Float {
        clamp(value, 0, 1)
    }

    private static func multiHotVector(_ raw: [String], values: [String]) -> [Float] {
        let selected = Set(raw.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        return values.map { selected.contains($0.lowercased()) ? 1 : 0 }
    }

    private static func confidenceVector(
        _ scores: [String: Float]?,
        hints: [String],
        values: [String]
    ) -> [Float] {
        guard let scores else { return multiHotVector(hints, values: values) }
        return values.map { clamp(scores[$0] ?? 0, 0, 1) }
    }

    private static func learningVector(
        _ context: AIEqualizerLearningContext?,
        mode: GraphicEQMode,
        usesDualBandBranches: Bool
    ) -> [Float] {
        let bandFeatureCount = usesDualBandBranches ? 42 : trackBandCount
        guard let context, context.isActive else {
            return Array(repeating: 0, count: 3 + bandFeatureCount + 6)
        }
        let bandAdjustments = mode.normalizedGains(context.bandAdjustments, limit: 1.25)
        return [
            1,
            clamp(context.confidence, 0, 1),
            min(10_000, Float(max(0, context.evidenceCount)))
        ] + (usesDualBandBranches
            ? modeBandBranches(mode, values: bandAdjustments)
            : linearResample(bandAdjustments, count: trackBandCount)) + [
            context.bassAdjustment,
            context.trebleAdjustment,
            context.surroundAdjustment,
            context.reverbAdjustment,
            context.stereoWidthAdjustment,
            context.processingIntensityAdjustment
        ].map { $0.isFinite ? $0 : 0 }
    }

    private static func deviceContextVector(
        _ context: AIEqualizerDeviceTrainingContext?
    ) -> [Float] {
        guard let context,
              context.detailSchemaVersion >= 1,
              !context.effectiveGainsDB.isEmpty else {
            return Array(repeating: 0, count: detailedDeviceFeatureNames.count)
        }
        let rawFilters = Array(context.acousticFilters.prefix(deviceFilterSlotCount))
        let filters = (0..<deviceFilterSlotCount).flatMap { slot -> [Float] in
            guard rawFilters.indices.contains(slot) else {
                return Array(repeating: 0, count: 1 + deviceFilterKindFeatureValues.count + 4)
            }
            let filter = rawFilters[slot]
            return [1]
                + oneHotVector(
                    filter.kind,
                    values: deviceFilterKindFeatureValues,
                    fallback: ""
                )
                + [
                    clamp(filter.frequencyHz, 10, 96_000),
                    clamp(filter.gainDB, -24, 24),
                    clamp(filter.q, 0.05, 100),
                    clamp(filter.slopeDBPerOctave, 0, 96)
                ]
        }
        return [
            1,
            context.calibrationEnabled ? 1 : 0,
            context.profileActive ? 1 : 0,
            context.profileIsCustom ? 1 : 0,
            clamp(Float(context.outputSampleRate), 8_000, 384_000),
            clamp(Float(context.outputChannelCount), 1, 32),
            clamp(Float(context.outputLatencyMS), 0, 5_000),
            clamp(Float(context.ioBufferDurationMS), 0, 1_000),
            clamp(context.profilePreampDB, -18, 0),
            min(Float(deviceFilterSlotCount), Float(rawFilters.count))
        ] + oneHotVector(
            context.profileSource,
            values: deviceProfileSourceFeatureValues,
            fallback: "none"
        ) + linearResample(
            context.routeDefaultGainsDB,
            count: trackBandCount
        ).map { clamp($0, -18, 18) }
            + linearResample(
                context.profileGainsDB,
                count: deviceCurveBandCount
            ).map { clamp($0, -18, 18) }
            + linearResample(
                context.effectiveGainsDB,
                count: deviceCurveBandCount
            ).map { clamp($0, -18, 18) }
            + filters
    }

    private static func sectionProfiles(
        _ sections: [[Float]]?,
        fallback: [Float],
        bandCount: Int
    ) -> [[Float]] {
        var result = (sections ?? []).prefix(trackSectionCount).map {
            linearResample($0, count: bandCount)
        }
        let fallbackProfile = linearResample(fallback, count: bandCount)
        while result.count < trackSectionCount {
            result.append(fallbackProfile)
        }
        return Array(result)
    }

    private static func oneHotVector(
        _ raw: String,
        values: [String],
        fallback: String
    ) -> [Float] {
        let selected = values.contains(raw) ? raw : fallback
        return values.map { $0 == selected ? 1 : 0 }
    }

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        guard value.isFinite else { return minimum }
        return min(maximum, max(minimum, value))
    }

    private static func bounded(
        _ value: Float,
        _ minimum: Float,
        _ maximum: Float,
        fallback: Float
    ) -> Float {
        guard value.isFinite, value >= minimum, value <= maximum else { return fallback }
        return value
    }

    private static let legacyFeatureNames = [
        "bandEnergyDB.0", "bandEnergyDB.1", "bandEnergyDB.2", "bandEnergyDB.3",
        "bandEnergyDB.4", "bandEnergyDB.5", "bandEnergyDB.6", "bandEnergyDB.7",
        "bandEnergyDB.8", "bandEnergyDB.9", "sampleDuration", "sampleRate", "frameCount",
        "spectralCentroidHz", "spectralRolloffHz", "rmsDBFS", "dynamicSpreadDB",
        "integratedLUFS", "shortTermLUFS", "momentaryLUFS", "loudnessRangeLU",
        "samplePeakDBFS", "estimatedTruePeakDBTP", "crestFactorDB", "dynamicRangeDR",
        "clippingRatio", "phaseCorrelation", "monoCompatibility", "measuredStereoWidth",
        "spectralFlatness", "spectralBandwidthHz", "spectralFlux", "lowEnergyRatio",
        "midEnergyRatio", "highEnergyRatio", "estimatedBPM", "tempoConfidence",
        "tempoStability", "keyConfidence", "dominantPitchHz", "melodyRangeSemitones",
        "melodicActivity", "transientDensity", "currentBassGain", "currentTrebleGain",
        "currentSurroundLevel", "currentReverbLevel", "currentStereoWidth",
        "professionalProcessingIntensity", "chroma.0", "chroma.1", "chroma.2", "chroma.3",
        "chroma.4", "chroma.5", "chroma.6", "chroma.7", "chroma.8", "chroma.9",
        "chroma.10", "chroma.11", "vocalReference.confidence", "vocalReference.presence",
        "vocalReference.warmth", "vocalReference.brightness", "vocalReference.airiness",
        "vocalReference.dynamicExpression", "outputCalibrationEnabled",
        "loudnessMatchingEnabled", "smartSongCompensationEnabled", "dynamicEQEnabled",
        "multibandDynamicsEnabled", "parametricEQEnabled", "deviceReferenceGainsDB.0",
        "deviceReferenceGainsDB.1", "deviceReferenceGainsDB.2", "deviceReferenceGainsDB.3",
        "deviceReferenceGainsDB.4", "deviceReferenceGainsDB.5", "deviceReferenceGainsDB.6",
        "deviceReferenceGainsDB.7", "deviceReferenceGainsDB.8", "deviceReferenceGainsDB.9",
        "graphicEQMode.thirtyTwoBand"
    ]

    private static let genreFeatureValues = [
        "electronic", "hiphop", "rock", "acoustic", "ballad", "pop"
    ]

    private static let instrumentFeatureValues = [
        "drums", "bass", "vocals", "synth", "guitar", "piano", "strings"
    ]

    private static let outputKindFeatureValues = [
        "builtInSpeaker", "wired", "bluetooth", "car", "airPlay", "usb", "other"
    ]

    private static let tuningIntensityFeatureValues = [
        "smart", "gentle", "standard", "strong"
    ]

    private static let tuningProfileFeatureValues = [
        "standard", "monoSpatialEnhancement"
    ]

    private static let deviceProfileSourceFeatureValues = [
        "none", "routeDefault", "airPods", "opra", "custom", "profile", "mixed"
    ]

    private static let deviceFilterKindFeatureValues = [
        "peak_dip", "low_shelf", "high_shelf", "low_pass",
        "high_pass", "band_pass", "band_stop"
    ]

    private static let trackSectionCount = 3
    private static let trackBandCount = 10
    private static let deviceCurveBandCount = 32
    private static let deviceFilterSlotCount = 12

    private static let routeAndIntentFeatureNames =
        outputKindFeatureValues.map { "outputKind.\($0)" }
        + tuningIntensityFeatureValues.map { "tuningIntensity.\($0)" }
        + tuningProfileFeatureValues.map { "tuningProfile.\($0)" }

    private static let styleConditionedFeatureNamesV2 =
        genreFeatureValues.map { "genreHint.\($0)" }
        + instrumentFeatureValues.map { "instrumentHint.\($0)" }
        + routeAndIntentFeatureNames

    private static func temporalTrackFeatureNames(for bandCount: Int) -> [String] {
        (0..<bandCount).map { "bandEnergySpreadDB.\($0)" }
        + (0..<(trackSectionCount * bandCount)).map {
            "sectionBandEnergyDB.\($0 / bandCount).\($0 % bandCount)"
        }
        + [
            "spectralCentroidP10Hz", "spectralCentroidP90Hz",
            "spectralRolloffP10Hz", "spectralRolloffP90Hz",
            "spectralFluxP90", "rmsP10DBFS", "rmsP50DBFS", "rmsP90DBFS"
        ]
    }

    private static func trackConditionedFeatureNames(for bandCount: Int) -> [String] {
        genreFeatureValues.map { "genreScore.\($0)" }
        + instrumentFeatureValues.map { "instrumentScore.\($0)" }
        + routeAndIntentFeatureNames
        + temporalTrackFeatureNames(for: bandCount)
    }

    private static func learningConditionedFeatureNames(for bandCount: Int) -> [String] {
        [
        "learning.active", "learning.confidence", "learning.evidenceCount"
        ] + (0..<bandCount).map { "learning.bandAdjustments.\($0)" }
        + [
            "learning.bassAdjustment", "learning.trebleAdjustment",
            "learning.surroundAdjustment", "learning.reverbAdjustment",
            "learning.stereoWidthAdjustment", "learning.processingIntensityAdjustment"
        ]
    }

    private static let detailedDeviceFeatureNames = [
        "device.detailActive", "device.calibrationEnabled",
        "device.profileActive", "device.profileIsCustom",
        "device.outputSampleRate", "device.outputChannelCount",
        "device.outputLatencyMS", "device.ioBufferDurationMS",
        "device.profilePreampDB", "device.filterCount"
    ] + deviceProfileSourceFeatureValues.map { "device.profileSource.\($0)" }
        + (0..<trackBandCount).map { "device.routeDefaultGainsDB.\($0)" }
        + (0..<deviceCurveBandCount).map { "device.profileGainsDB.\($0)" }
        + (0..<deviceCurveBandCount).map { "device.effectiveGainsDB.\($0)" }
        + (0..<deviceFilterSlotCount).flatMap { slot in
            ["device.filter.\(slot).active"]
                + deviceFilterKindFeatureValues.map { "device.filter.\(slot).kind.\($0)" }
                + [
                    "device.filter.\(slot).frequencyHz",
                    "device.filter.\(slot).gainDB",
                    "device.filter.\(slot).q",
                    "device.filter.\(slot).slopeDBPerOctave"
                ]
        }

    private static func bandBranchFeatureNames(_ name: String) -> [String] {
        (0..<10).map { "tenBand.\(name).\($0)" }
            + (0..<32).map { "thirtyTwoBand.\(name).\($0)" }
    }

    private static func featureNames(forFeatureSchemaVersion version: Int) -> [String]? {
        switch version {
        case 1:
            return legacyFeatureNames
        case 2:
            return legacyFeatureNames + styleConditionedFeatureNamesV2
        case 3:
            return legacyFeatureNames + trackConditionedFeatureNames(for: trackBandCount)
        case 4:
            return legacyFeatureNames + trackConditionedFeatureNames(for: trackBandCount)
                + learningConditionedFeatureNames(for: trackBandCount)
        case 5:
            return legacyFeatureNames + trackConditionedFeatureNames(for: trackBandCount)
                + learningConditionedFeatureNames(for: trackBandCount) + detailedDeviceFeatureNames
        case 6, 7:
            let modeLegacyFeatureNames = bandBranchFeatureNames("bandEnergyDB")
                + Array(legacyFeatureNames[10..<73])
                + bandBranchFeatureNames("deviceReferenceGainsDB")
                + ["graphicEQMode.thirtyTwoBand"]
            let dualTemporalNames = bandBranchFeatureNames("bandEnergySpreadDB")
                + [GraphicEQMode.tenBand, .thirtyTwoBand].flatMap { mode in
                    (0..<(trackSectionCount * mode.bandCount)).map {
                        "\(mode.rawValue).sectionBandEnergyDB.\($0 / mode.bandCount).\($0 % mode.bandCount)"
                    }
                }
                + [
                    "spectralCentroidP10Hz", "spectralCentroidP90Hz",
                    "spectralRolloffP10Hz", "spectralRolloffP90Hz",
                    "spectralFluxP90", "rmsP10DBFS", "rmsP50DBFS", "rmsP90DBFS"
                ]
            let dualTrackNames = genreFeatureValues.map { "genreScore.\($0)" }
                + instrumentFeatureValues.map { "instrumentScore.\($0)" }
                + routeAndIntentFeatureNames + dualTemporalNames
            let dualLearningNames = [
                "learning.active", "learning.confidence", "learning.evidenceCount"
            ] + bandBranchFeatureNames("learning.bandAdjustments") + [
                "learning.bassAdjustment", "learning.trebleAdjustment",
                "learning.surroundAdjustment", "learning.reverbAdjustment",
                "learning.stereoWidthAdjustment", "learning.processingIntensityAdjustment"
            ]
            return modeLegacyFeatureNames + dualTrackNames
                + dualLearningNames + detailedDeviceFeatureNames
        default:
            return nil
        }
    }

    private static let legacyTargetNames = [
        "gains.0", "gains.1", "gains.2", "gains.3", "gains.4", "gains.5", "gains.6",
        "gains.7", "gains.8", "gains.9", "preampDB", "tone.bassGain", "tone.trebleGain",
        "spatial.surroundLevel", "spatial.reverbLevel", "spatial.stereoWidth",
        "enhance.transientAttack", "enhance.transientSustain", "enhance.vocalFocus",
        "enhance.airAmount", "enhance.deEssAmount", "enhance.lowFrequencyFocus",
        "enhance.stageWidth", "enhance.microDynamics", "enhance.lowLevelCompensation",
        "enhance.isEnabled", "calibration.outputCalibrationEnabled",
        "calibration.loudnessMatchingEnabled", "calibration.smartSongCompensationEnabled",
        "professional.processingIntensity", "professional.dynamicEQ.enabled",
        "professional.multiband.enabled", "professional.parametricEQ.enabled",
        "effects.targetLUFS", "effects.targetLRA", "effects.truePeakCeilingDB",
        "effects.compressorThresholdDB", "effects.compressorRatio", "effects.compressorAttackMS",
        "effects.compressorReleaseMS", "effects.compressorMakeupDB", "effects.subboostGainDB",
        "effects.subboostCutoffHz", "effects.crossfeedStrength", "effects.haasDelayMS",
        "effects.virtualBassCutoffHz", "effects.virtualBassStrength", "effects.exciterAmountDB",
        "effects.exciterFrequencyHz", "effects.finalLimiterCeilingDB",
        "effects.loudnessNormalizationEnabled", "effects.compressorEnabled",
        "effects.subboostEnabled", "effects.bs2bEnabled", "effects.crossfeedEnabled",
        "effects.haasEnabled", "effects.virtualBassEnabled", "effects.exciterEnabled",
        "effects.softclipEnabled", "effects.finalLimiterEnabled"
    ]

    private static func targetNames(forFeatureSchemaVersion version: Int) -> [String] {
        guard version >= 6 else { return legacyTargetNames }
        let shared = (0..<10).map { "tenBand.gains.\($0)" }
            + (0..<32).map { "thirtyTwoBand.gains.\($0)" }
            + Array(legacyTargetNames.dropFirst(10))
        return version >= 7 ? shared + professionalTargetNames : shared
    }

    private static let dynamicBandFields = [
        "frequency", "q", "thresholdDB", "ratio", "maxReductionDB", "attackMS", "releaseMS"
    ]
    private static let parametricTypes = ["peak", "lowShelf", "highShelf", "lowPass", "highPass", "notch"]
    private static let professionalTargetNames: [String] = {
        var result: [String] = []
        for slot in 0..<4 {
            let prefix = "professional.dynamicEQ.bands.\(slot)."
            result.append(prefix + "active")
            result.append(contentsOf: dynamicBandFields.map { prefix + $0 })
        }
        for slot in 0..<6 {
            let prefix = "professional.parametricEQ.bands.\(slot)."
            result.append(prefix + "active")
            result.append(contentsOf: parametricTypes.map { prefix + "type." + $0 })
            result.append(contentsOf: ["frequency", "gainDB", "q"].map { prefix + $0 })
        }
        result.append(contentsOf: ["lowCrossoverHz", "highCrossoverHz", "attackMS", "releaseMS"].map {
            "professional.multiband." + $0
        })
        for field in ["thresholdsDB", "ratios", "maxReductionDB"] {
            result.append(contentsOf: (0..<3).map { "professional.multiband.\(field).\($0)" })
        }
        return result
    }()
}
