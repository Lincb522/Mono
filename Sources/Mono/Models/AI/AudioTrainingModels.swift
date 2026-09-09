import Foundation

struct AudioTrainingDatasetStatus: Codable, Equatable, Sendable {
    var snapshotCount: Int
    var contributingAccounts: Int
    var completeSamples: Int
    var styleConditionedSamples: Int?
    var temporallyConditionedSamples: Int?
    var learningConditionedSamples: Int?
    var deviceConditionedSamples: Int?
    var distinctTracks: Int?
    var feedbackConfirmedSamples: Int?
    var excludedOutcomeSamples: Int?
    var trainableSamples: Int?
    var totalPlans: Int
    var legacyPlans: Int
    var invalidSamples: Int
    var tenBandSamples: Int
    var thirtyTwoBandSamples: Int
    var standardProfileSamples: Int?
    var spatialProfileSamples: Int?
    var branchSamples: [String: Int]?
    var completeBranchSamples: [String: Int]?
    var completeAccounts: Int?
    var manualCorrectedSamples: Int?
    var selfGeneratedSamples: Int?
    var selfGeneratedPlans: Int?
    var targetMode: String?
    var datasetFingerprint: String?
}

enum AudioTrainingTargetMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Learn the learning-free population target; personal preference stays a
    /// local residual on the device.
    case population
    /// Learn the Agent-personalised target with the learning context as input.
    case personalized
    /// Learn population and contextual personal targets as paired observations.
    case joint

    var id: String { rawValue }
}

struct AudioTrainingSettings: Codable, Equatable, Sendable {
    var epochs: Int
    var hiddenUnits: Int
    var learningRate: Double
    var validationPercent: Int
    var minimumSamples: Int
    var priorWeight: Double?
    var weightDecay: Double?
    var earlyStoppingPatience: Int?
    var intentUnits: Int?
    var targetMode: AudioTrainingTargetMode?
    var batchSize: Int?
    var updatedAt: String?
}

struct AudioTrainingSettingsUpdate: Encodable, Sendable {
    var epochs: Int
    var hiddenUnits: Int
    var learningRate: Double
    var validationPercent: Int
    var minimumSamples: Int
    var priorWeight: Double
    var weightDecay: Double
    var earlyStoppingPatience: Int
    var intentUnits: Int
    var targetMode: AudioTrainingTargetMode
}

struct AudioTrainingJobStatus: Codable, Equatable, Sendable {
    var id: String
    var state: String
    var progress: Double
    var epoch: Int
    var totalEpochs: Int
    var sampleCount: Int
    var trainingCount: Int
    var validationCount: Int
    var trainingLoss: Double?
    var validationLoss: Double?
    var datasetFingerprint: String?
    var errorMessage: String?
    var modelId: String?
    var createdBy: String?
    var createdAt: String
    var startedAt: String?
    var finishedAt: String?
    var updatedAt: String
    var isActive: Bool
}

struct AudioTrainingModelStatus: Codable, Equatable, Sendable {
    struct ReleasePreview: Codable, Equatable, Sendable {
        var summary: String
        var notes: String
    }

    struct Metrics: Codable, Equatable, Sendable {
        struct BranchValidation: Codable, Equatable, Sendable {
            var samples: Int
            var tracks: Int?
            var eqMAEDB: Double?
            var priorEQMAEDB: Double?
            var improvesPrior: Bool?
            var trackEQMAEP90DB: Double?
            var targetFamilyMSE: [String: Double]?
        }
        var confidenceCalibration: AudioTrainingConfidenceCalibration?
        var branchValidation: [String: BranchValidation]?
        var conditionValidation: [String: BranchValidation]?
        var architecture: String?
        var selectionValidationTracks: Int?
        var selectionSource: String?
        var preferenceTrainingPairs: Int?
        var preferenceValidationPairs: Int?
        var preferenceTrainingAccuracy: Double?
        var preferenceValidationAccuracy: Double?
        var initialTrainingLoss: Double?
        var initialValidationLoss: Double?
        var trainingLoss: Double?
        var validationLoss: Double?
        var trainingLossImprovement: Double?
        var validationLossImprovement: Double?
        var optimizationSteps: Int?
        var trainingSamples: Int?
        var validationSamples: Int?
        var tenBandTrainingSamples: Int?
        var thirtyTwoBandTrainingSamples: Int?
        var tenBandValidationSamples: Int?
        var thirtyTwoBandValidationSamples: Int?
        var standardProfileTrainingSamples: Int?
        var spatialProfileTrainingSamples: Int?
        var standardProfileValidationSamples: Int?
        var spatialProfileValidationSamples: Int?
        var tenBandStandardTrainingSamples: Int?
        var tenBandSpatialTrainingSamples: Int?
        var thirtyTwoBandStandardTrainingSamples: Int?
        var thirtyTwoBandSpatialTrainingSamples: Int?
        var tenBandStandardValidationSamples: Int?
        var tenBandSpatialValidationSamples: Int?
        var thirtyTwoBandStandardValidationSamples: Int?
        var thirtyTwoBandSpatialValidationSamples: Int?
        var completeTrainingSamples: Int?
        var styleConditionedTrainingSamples: Int?
        var temporallyConditionedTrainingSamples: Int?
        var learningConditionedTrainingSamples: Int?
        var deviceConditionedTrainingSamples: Int?
        var distinctTrainingTracks: Int?
        var feedbackConfirmedTrainingSamples: Int?
        var legacyTrainingSamples: Int?
        var completeValidationSamples: Int?
        var styleConditionedValidationSamples: Int?
        var temporallyConditionedValidationSamples: Int?
        var learningConditionedValidationSamples: Int?
        var deviceConditionedValidationSamples: Int?
        var distinctValidationTracks: Int?
        var feedbackConfirmedValidationSamples: Int?
        var legacyValidationSamples: Int?
        var legacyPriorWeight: Double?
        var legacyPerSampleWeight: Double?
        var minimumTrackSampleWeight: Double?
        var supervisedTrainingLoss: Double?
        var legacyTrainingLoss: Double?
        var bestEpoch: Int?
        var epochsRun: Int?
        var earlyStopped: Bool?
        var targetMode: AudioTrainingTargetMode?
        var intentUnits: Int?
        var weightDecay: Double?
        var supervisedTotalWeight: Double?
        var legacyTotalWeight: Double?
        var completeAccountCount: Int?
        var legacyAccountCount: Int?
        var selfGeneratedSamplesExcluded: Int?
        var selfGeneratedPlansExcluded: Int?
        var manualCorrectedTrainingSamples: Int?
        var completeBranchTrainingSamples: [String: Int]?
        var completeBranchValidationSamples: [String: Int]?
        var completeBranchAccounts: [String: Int]?
        var qualityWarnings: [String]?
    }

    var id: String
    var version: String
    var featureSchemaVersion: Int
    var targetSchemaVersion: Int
    var metrics: Metrics
    var datasetFingerprint: String
    var sampleCount: Int
    var createdBy: String?
    var createdAt: String
    var coreMLArtifact: AudioTrainingCoreMLArtifactStatus?
    var fileName: String? = nil
    var release: AudioTrainingModelRelease? = nil
    var releasePreview: ReleasePreview? = nil

    var displayName: String { AudioTrainingModelPresentation.name(version: version, createdAt: createdAt) }
}

struct AudioTrainingCoreMLArtifactStatus: Codable, Equatable, Sendable {
    var format: String
    var sha256: String
    var byteCount: Int
    var createdAt: String
}

struct AudioTrainingInstalledModelStatus: Codable, Equatable, Sendable {
    var id: String
    var version: String
    var sha256: String
    var byteCount: Int
    var featureSchemaVersion: Int
    var targetSchemaVersion: Int
    var completeSampleCount: Int
    var legacySampleCount: Int
    var learningConditionedSampleCount: Int? = nil
    var deviceConditionedSampleCount: Int? = nil
    var completeAccountCount: Int? = nil
    var completeBranchSampleCounts: [String: Int]? = nil
    var completeBranchAccountCounts: [String: Int]? = nil
    var qualityWarnings: [String]? = nil
    var installedAt: Date
    var sourceModelFileName: String? = nil

    var identity: String {
        "\(version):\(sha256.prefix(12))"
    }

    var sourceModelRelativePath: String? {
        sourceModelFileName.map { "MonoAudioTrainingModels/current/\($0)" }
    }

    /// Complete samples the model saw for one band/profile branch. Models
    /// installed before branch counts were recorded report their total.
    func completeSampleCount(forBranch branch: String) -> Int {
        guard let completeBranchSampleCounts else { return completeSampleCount }
        return completeBranchSampleCounts[branch] ?? 0
    }

    func trackCorrectionStrength(forBranch branch: String) -> Float {
        guard completeSampleCount > 0 else { return 0 }
        guard completeBranchSampleCounts != nil else { return 1 }
        let samples = completeSampleCount(forBranch: branch)
        guard samples > 0 else { return 0 }
        // Preserve installed legacy behaviour until a download supplies the
        // per-branch metadata. New manifests must not use global coverage.
        let accounts = completeBranchAccountCounts.map { $0[branch] ?? 0 }
            ?? completeAccountCount ?? 1
        let accountFactor: Float = accounts < 2 ? 0.6 : (accounts == 2 ? 0.8 : 1)
        return min(1, Float(samples) / 64) * accountFactor
    }
}


enum AudioTrainingComputeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case all
    case cpuAndGPU
    case cpuOnly

    var id: String { rawValue }
}

struct AudioTrainingOnDeviceSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var computeMode: AudioTrainingComputeMode
    var legacyPriorStrength: Double
    var advancedStageMinimumSamples: Int

    static let standard = AudioTrainingOnDeviceSettings(
        isEnabled: true,
        computeMode: .all,
        legacyPriorStrength: 1,
        advancedStageMinimumSamples: 32
    )

    var normalized: AudioTrainingOnDeviceSettings {
        AudioTrainingOnDeviceSettings(
            isEnabled: isEnabled,
            computeMode: computeMode,
            legacyPriorStrength: min(1, max(0, legacyPriorStrength)),
            advancedStageMinimumSamples: min(512, max(16, advancedStageMinimumSamples))
        )
    }
}

struct AudioTrainingTensorValue: Identifiable, Equatable, Sendable {
    var id: Int { index }
    var index: Int
    var name: String
    var value: Float
}

struct AudioTrainingInferenceTrace: Equatable, Sendable {
    var version: String
    var input: [AudioTrainingTensorValue]
    var rawOutput: [AudioTrainingTensorValue]
    var latencyMilliseconds: Double
    var capturedAt: Date
    var priorInput: [AudioTrainingTensorValue] = []
    var priorOutput: [AudioTrainingTensorValue] = []
    var blendedOutput: [AudioTrainingTensorValue] = []
    var trackCorrectionStrength: Float = 1
}

struct AudioTrainingModelTestCaseResult: Identifiable, Equatable, Sendable {
    var id: String
    var input: [AudioTrainingTensorValue]
    var rawOutput: [AudioTrainingTensorValue]
    var latencyMilliseconds: Double
}

struct AudioTrainingModelTestResult: Equatable, Sendable {
    var version: String
    var testCaseCount: Int
    var averageLatencyMilliseconds: Double
    var outputMinimum: Float
    var outputMaximum: Float
    var isDeterministic: Bool
    var isInputSensitive: Bool
    var maximumInputResponseDelta: Float
    var isStyleSensitive: Bool
    var maximumStyleResponseDelta: Float
    var isTrackSensitive: Bool
    var maximumTrackResponseDelta: Float
    var isLearningSensitive: Bool
    var maximumLearningResponseDelta: Float
    var isDeviceSensitive: Bool
    var maximumDeviceResponseDelta: Float
    var isTuningProfileSensitive: Bool
    var maximumTuningProfileResponseDelta: Float
    var tenBandTuningProfileResponseDelta: Float
    var thirtyTwoBandTuningProfileResponseDelta: Float
    var testCases: [AudioTrainingModelTestCaseResult]
}

struct AudioTrainingTuningTestResult: Equatable, Sendable {
    var version: String
    var profileName: String
    var bandCount: Int
    var preampDB: Float
    var elapsedMilliseconds: Double
    var warningCodes: [String]
    var completeSampleCount: Int
    var legacySampleCount: Int
    var deviceConditionedSampleCount: Int
    var isTrackConditioned: Bool
    var modelOutputStrength: Double
    var samplingElapsedMilliseconds: Double
    var generationElapsedMilliseconds: Double
    var applyingElapsedMilliseconds: Double
    var samplingReused: Bool
    var sampleDuration: Double
    var sampleRate: Double
    var frameCount: Int
    var inference: AudioTrainingInferenceTrace
    var finalProposal: AIEqualizerProposal
    var appliedDSPJSON: String = ""
}

struct AudioTrainingStatusResponse: Decodable, Sendable {
    var ok: Bool
    var settings: AudioTrainingSettings
    var dataset: AudioTrainingDatasetStatus
    var currentJob: AudioTrainingJobStatus?
    var currentModel: AudioTrainingModelStatus?
    var publishedModel: AudioTrainingModelStatus? = nil
}

struct AudioTrainingSettingsResponse: Decodable, Sendable {
    var ok: Bool
    var settings: AudioTrainingSettings
}

struct AudioTrainingJobResponse: Decodable, Sendable {
    var ok: Bool
    var job: AudioTrainingJobStatus
}

struct AudioTrainingModelResponse: Decodable, Sendable {
    var ok: Bool
    var model: AudioTrainingModelStatus
}
