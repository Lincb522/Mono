import Foundation
import FFmpegSwiftSDK

enum AIWireProtocol: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleIntelligence
    case openAIResponses
    case openAIChat
    case anthropicMessages
    case googleGemini
    case azureOpenAI
    case ollama
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: return String(localized: "ai_protocol_apple")
        case .openAIResponses: return "OpenAI Responses"
        case .openAIChat: return "OpenAI Chat Completions"
        case .anthropicMessages: return "Anthropic Messages"
        case .googleGemini: return "Google Gemini"
        case .azureOpenAI: return "Azure OpenAI"
        case .ollama: return "Ollama"
        case .openAICompatible: return "OpenAI Compatible"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .appleIntelligence: return ""
        case .openAIResponses, .openAIChat: return "https://api.openai.com/v1"
        case .anthropicMessages: return "https://api.anthropic.com/v1"
        case .googleGemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .azureOpenAI: return ""
        case .ollama: return "http://localhost:11434"
        case .openAICompatible: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .appleIntelligence: return String(localized: "ai_model_on_device")
        case .openAIResponses, .openAIChat: return "gpt-5-mini"
        case .openAICompatible: return "gpt-5.6-sol"
        case .anthropicMessages: return "claude-sonnet-4-5"
        case .googleGemini: return "gemini-2.5-flash"
        case .azureOpenAI: return ""
        case .ollama: return "qwen3:8b"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .appleIntelligence, .ollama, .openAICompatible: return false
        default: return true
        }
    }

    var supportsCustomEndpoint: Bool { self != .appleIntelligence }
}

/// AI 服务端连接配置；空地址或模型名由所选协议提供默认值。
struct AIProviderConfiguration: Codable, Equatable, Sendable {
    var wireProtocol: AIWireProtocol
    var baseURL: String
    var model: String
    var modelDiscoveryURL: String
    var timeout: TimeInterval
    var customHeadersJSON: String

    var resolvedBaseURL: String {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? wireProtocol.defaultBaseURL : value
    }

    var resolvedModel: String {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? wireProtocol.defaultModel : value
    }
}

struct AIUsageLimits: Codable, Equatable, Sendable {
    var dailyRequestLimit: Int
    var hourlyRequestLimit: Int
    var minimumRequestInterval: TimeInterval
}

struct AIGenerationOptions: Equatable, Sendable {
    var temperature: Double
    var maxOutputTokens: Int

    static let standard = AIGenerationOptions(temperature: 0.1, maxOutputTokens: 4_096)

    var normalizedTemperature: Double { min(2, max(0, temperature)) }
    var normalizedMaxOutputTokens: Int { min(32_000, max(128, maxOutputTokens)) }
}

struct AIRemoteAIConfiguration: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var enabled: Bool
    var wireProtocol: AIWireProtocol
    /// 新版云端直接向 App 分发连接参数；可选保证兼容旧版配置响应与本地缓存。
    var baseURL: String?
    var model: String
    var modelDiscoveryURL: String?
    var timeout: TimeInterval
    var customHeadersJSON: String?
    var apiKey: String?
    var usageLimits: AIUsageLimits
    var revision: String
    var updatedAt: Date?
    var resonance: AIResonanceConfiguration? = nil
}

struct AIAdminProviderConfiguration: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var enabled: Bool
    var wireProtocol: AIWireProtocol
    var baseURL: String
    var model: String
    var modelDiscoveryURL: String
    var timeout: TimeInterval
    var customHeadersJSON: String
    var apiKey: String
    var usageLimits: AIUsageLimits
    var revision: String
    var updatedAt: Date?
    var resonance: AIResonanceConfiguration? = nil
}

struct AIAdminProviderConfigurationUpdate: Encodable, Sendable {
    var enabled: Bool
    var expectedRevision: String?
    var configuration: AIProviderConfiguration
    var apiKey: String
    var usageLimits: AIUsageLimits
    var resonance: AIResonanceConfigurationUpdate? = nil

    enum CodingKeys: String, CodingKey {
        case enabled
        case expectedRevision
        case configuration
        case apiKey
        case usageLimits
        case resonance
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(expectedRevision, forKey: .expectedRevision)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(usageLimits, forKey: .usageLimits)
        try container.encodeIfPresent(resonance, forKey: .resonance)
    }
}

struct AIUsageSnapshot: Equatable, Sendable {
    let usedToday: Int
    let usedThisHour: Int
    let lastRequestAt: Date?
}

struct AIEqualizerVocalReferenceFeatures: Codable, Equatable, Sendable {
    let confidence: Float
    let presence: Float
    let warmth: Float
    let brightness: Float
    let airiness: Float
    let dynamicExpression: Float
    let register: String
}

/// A bounded output-device correction applied locally after the Agent result
/// has passed validation. The Agent receives the same target as context and is
/// explicitly told not to duplicate this curve.
struct AIEqualizerDeviceTuningTarget: Codable, Equatable, Sendable {
    let identifier: String
    let displayName: String
    let fitDescription: String
    let referenceGainsDB: [Float]
    let spatialGuidance: String

    func gains(for mode: GraphicEQMode) -> [Float] {
        mode.resampledGains(referenceGainsDB, from: .tenBand)
    }
}

/// Numeric output-device evidence supplied to the training model. This
/// describes the baseline that Mono applies locally; it is never itself a
/// per-track correction target.
struct AIEqualizerDeviceAcousticFilterContext: Codable, Equatable, Sendable {
    let kind: String
    let frequencyHz: Float
    let gainDB: Float
    let q: Float
    let slopeDBPerOctave: Float
}

struct AIEqualizerDeviceTrainingContext: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let detailSchemaVersion: Int
    let identifier: String
    let outputKind: String
    let profileSource: String
    let calibrationEnabled: Bool
    let profileActive: Bool
    let profileIsCustom: Bool
    let outputSampleRate: Double
    let outputChannelCount: Int
    let outputLatencyMS: Double
    let ioBufferDurationMS: Double
    let routeDefaultGainsDB: [Float]
    let profileGainsDB: [Float]
    let referenceGainsDB: [Float]
    let effectiveGainsDB: [Float]
    let profilePreampDB: Float
    let acousticFilters: [AIEqualizerDeviceAcousticFilterContext]
    let fitDescription: String
    let spatialGuidance: String
}

/// 一次 AI 调音请求的音频测量、输出设备与当前处理状态快照。
struct AIEqualizerAudioFeatures: Codable, Equatable, Sendable {
    let songID: Int
    let title: String
    let artist: String
    let source: String
    let outputDevice: String
    let outputKind: String
    let sampleDuration: Double
    let sampleRate: Double
    let frameCount: Int
    let graphicEQMode: GraphicEQMode
    let bandFrequenciesHz: [Float]
    let bandEnergyDB: [Float]
    /// Per-band temporal variation and three chronological section profiles.
    /// These distinguish tracks that share a style without retaining raw audio.
    let bandEnergySpreadDB: [Float]?
    let sectionBandEnergyDB: [[Float]]?
    let spectralCentroidHz: Float
    let spectralRolloffHz: Float
    let spectralCentroidP10Hz: Float?
    let spectralCentroidP90Hz: Float?
    let spectralRolloffP10Hz: Float?
    let spectralRolloffP90Hz: Float?
    let rmsDBFS: Float
    let dynamicSpreadDB: Float
    let integratedLUFS: Float
    let shortTermLUFS: Float
    let momentaryLUFS: Float
    let loudnessRangeLU: Float
    let samplePeakDBFS: Float
    let estimatedTruePeakDBTP: Float
    let crestFactorDB: Float
    let dynamicRangeDR: Float
    let clippingRatio: Float
    let phaseCorrelation: Float
    let monoCompatibility: Float
    let measuredStereoWidth: Float
    let spectralFlatness: Float
    let spectralBandwidthHz: Float
    let spectralFlux: Float
    let spectralFluxP90: Float?
    let lowEnergyRatio: Float
    let midEnergyRatio: Float
    let highEnergyRatio: Float
    let estimatedBPM: Float
    let tempoConfidence: Float
    let tempoStability: Float
    let estimatedKey: String
    let keyConfidence: Float
    let dominantPitchHz: Float
    let melodyRangeSemitones: Float
    let melodicActivity: Float
    let melodyContourHz: [Float]
    let transientDensity: Float
    let chroma: [Float]
    let genreHints: [String]
    let instrumentHints: [String]
    /// Bounded continuous evidence, not mutually exclusive preset labels.
    let genreScores: [String: Float]?
    let instrumentScores: [String: Float]?
    let rmsP10DBFS: Float?
    let rmsP50DBFS: Float?
    let rmsP90DBFS: Float?
    let vocalReference: AIEqualizerVocalReferenceFeatures?
    let currentBassGain: Float
    let currentTrebleGain: Float
    let currentSurroundLevel: Float
    let currentReverbLevel: Float
    let currentStereoWidth: Float
    let professionalProcessingIntensity: Float
    let outputCalibrationEnabled: Bool
    let loudnessMatchingEnabled: Bool
    let smartSongCompensationEnabled: Bool
    let dynamicEQEnabled: Bool
    let multibandDynamicsEnabled: Bool
    let parametricEQEnabled: Bool
}

struct AIEqualizerToneConfiguration: Codable, Equatable, Sendable {
    let bassGain: Float
    let trebleGain: Float
}

struct AIEqualizerSpatialConfiguration: Codable, Equatable, Sendable {
    let surroundLevel: Float
    let reverbLevel: Float
    let stereoWidth: Float
}

struct AIEqualizerCalibrationConfiguration: Codable, Equatable, Sendable {
    let outputCalibrationEnabled: Bool
    let loudnessMatchingEnabled: Bool
    let smartSongCompensationEnabled: Bool
}

struct AIEqualizerDynamicBandConfiguration: Codable, Equatable, Sendable {
    let frequency: Float
    let q: Float
    let thresholdDB: Float
    let ratio: Float
    let maxReductionDB: Float
    let attackMS: Float
    let releaseMS: Float
}

struct AIEqualizerDynamicEQConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let bands: [AIEqualizerDynamicBandConfiguration]
}

struct AIEqualizerMultibandConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let lowCrossoverHz: Float
    let highCrossoverHz: Float
    let thresholdsDB: [Float]
    let ratios: [Float]
    let maxReductionDB: [Float]
    let attackMS: Float
    let releaseMS: Float
}

struct AIEqualizerParametricBandConfiguration: Codable, Equatable, Sendable {
    let type: String
    let frequency: Float
    let gainDB: Float
    let q: Float
}

struct AIEqualizerParametricEQConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let bands: [AIEqualizerParametricBandConfiguration]
}

struct AIEqualizerProfessionalConfiguration: Codable, Equatable, Sendable {
    let processingIntensity: Float
    let dynamicEQ: AIEqualizerDynamicEQConfiguration
    let multiband: AIEqualizerMultibandConfiguration
    let parametricEQ: AIEqualizerParametricEQConfiguration
}

enum AIEqualizerTuningIntensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case smart
    case gentle
    case standard
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return String(localized: "ai_tuning_intensity_smart")
        case .gentle: return String(localized: "ai_tuning_intensity_gentle")
        case .standard: return String(localized: "ai_tuning_intensity_standard")
        case .strong: return String(localized: "ai_tuning_intensity_strong")
        }
    }

    var promptDirective: String {
        switch self {
        case .smart:
            return "Choose the intervention strength from the measurements. Prefer the least processing that produces a useful audible correction, and never exceed the global safety ranges."
        case .gentle:
            return "Use gentle intervention. Preserve the original tonal balance, dynamics, ambience, and transients. Prefer subtle corrections: graphic EQ within about ±4.5 dB, tone within ±3 dB, restrained spatial processing, and low professional-processing intensity."
        case .standard:
            return "Use standard intervention. Produce a clearly useful but balanced correction: graphic EQ within about ±6.5 dB, tone within ±5 dB, moderate spatial processing, and moderate professional-processing intensity."
        case .strong:
            return "Use strong intervention. The result may be clearly audible across tone, space, and dynamics, while still preserving headroom, phase safety, transient integrity, and the recording's identity. Do not use loudness as a substitute for quality."
        }
    }

    fileprivate var graphicGainRange: ClosedRange<Float> {
        switch self {
        case .gentle: return -4.5...4.5
        case .standard: return -6.5...6.5
        case .smart, .strong: return -9...9
        }
    }

    fileprivate var toneRange: ClosedRange<Float> {
        switch self {
        case .gentle: return -3...3
        case .standard: return -5...5
        case .smart, .strong: return -8...8
        }
    }

    fileprivate var surroundRange: ClosedRange<Float> {
        switch self {
        case .gentle: return 0...0.18
        case .standard: return 0...0.42
        case .smart, .strong: return 0...0.85
        }
    }

    fileprivate var reverbRange: ClosedRange<Float> {
        switch self {
        case .gentle: return 0...0.28
        case .standard: return 0...0.38
        case .smart, .strong: return 0...0.6
        }
    }

    fileprivate var stereoWidthRange: ClosedRange<Float> {
        switch self {
        case .gentle: return 0.86...1.14
        case .standard: return 0.76...1.38
        case .smart, .strong: return 0.65...1.75
        }
    }

    fileprivate var processingIntensityRange: ClosedRange<Float> {
        switch self {
        case .gentle: return 0.6...1.0
        case .standard: return 0.85...1.45
        case .strong: return 1.2...1.9
        case .smart: return 0.6...2.1
        }
    }

    fileprivate var defaultProcessingIntensity: Float {
        switch self {
        case .smart: return 1.3
        case .gentle: return 0.82
        case .standard: return 1.15
        case .strong: return 1.55
        }
    }

    fileprivate var dynamicRatioMaximum: Float {
        switch self {
        case .gentle: return 2.2
        case .standard: return 4
        case .smart, .strong: return 8
        }
    }

    fileprivate var dynamicReductionMaximum: Float {
        switch self {
        case .gentle: return 2.5
        case .standard: return 4.5
        case .smart, .strong: return 8
        }
    }

    fileprivate var enhancementGainMaximum: Float {
        switch self {
        case .gentle: return 3
        case .standard: return 5
        case .smart, .strong: return 8
        }
    }
}

enum AIEqualizerTuningProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case monoSpatialEnhancement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return String(localized: "ai_tuning_profile_standard")
        case .monoSpatialEnhancement: return String(localized: "ai_tuning_profile_mono_spatial")
        }
    }

    var promptDirective: String {
        switch self {
        case .standard:
            return "Use the default Mono tuning direction. The processed result must be clearly audible against bypass through purposeful frequency correction, bass and treble balance, vocal focus, transient definition, micro-dynamics, loudness continuity, and safe headroom. Preserve the original stereo image instead of sounding untreated, and avoid spatial widening reserved for the Mono spatial profile."
        case .monoSpatialEnhancement:
            return "Use a clearly audible Mono spatial enhancement direction without referencing Dolby or any licensed brand. It must be meaningfully different from the standard profile: widen the stage, add controlled surround energy and audible but restrained ambience, while keeping center vocals stable, bass focused, mono compatibility safe, and enough limiter headroom. Do not return standard-profile spatial values unless phase or mono measurements require protection."
        }
    }

    var outputCopyDirective: String {
        switch self {
        case .standard:
            return "The preset title must evoke tonal texture, rhythmic motion, weight, or light. Do not use horizon, distance, room, panorama, orbit, or stage imagery reserved for the spatial profile. The summary must explain frequency balance, bass and treble, transients, dynamics, or headroom, and must state that the original stereo image is preserved when relevant."
        case .monoSpatialEnhancement:
            return "The preset title must evoke distance, horizon, air, depth, panorama, orbit, or an enveloping scene. Do not use a purely tonal or texture-only title that could belong to the standard profile. The summary must explicitly explain the audible changes to stage width, surround, ambience or reverb, center-vocal stability, and mono compatibility."
        }
    }

    fileprivate var summaryFallback: String {
        switch self {
        case .standard: return String(localized: "ai_eq_summary_standard_fallback")
        case .monoSpatialEnhancement: return String(localized: "ai_eq_summary_spatial_fallback")
        }
    }

    fileprivate var summaryFocus: String {
        switch self {
        case .standard: return String(localized: "ai_eq_summary_standard_focus")
        case .monoSpatialEnhancement: return String(localized: "ai_eq_summary_spatial_focus")
        }
    }
}

struct AIEqualizerTiming: Codable, Equatable, Sendable {
    let total: TimeInterval
    let sampling: TimeInterval
    let samplingReused: Bool?
    let generation: TimeInterval
    let applying: TimeInterval
    let completedAt: Date
}

enum AIEqualizerLearningFeedback: String, Codable, Equatable, Sendable {
    case positive
    case negative
    case reset
    case regenerated
    case retained
    case manualEqualizer
}

enum AIEqualizerLearningStrength: String, CaseIterable, Codable, Identifiable, Sendable {
    case cautious
    case balanced
    case responsive

    var id: String { rawValue }

    var adjustmentScale: Float {
        switch self {
        case .cautious: return 0.65
        case .balanced: return 1
        case .responsive: return 1.3
        }
    }
}

enum AIEqualizerLearningRetention: Int, CaseIterable, Codable, Identifiable, Sendable {
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    var id: Int { rawValue }
    var days: Int { rawValue }
}

struct AIEqualizerLearningRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let songTitle: String?
    let songIdentifier: String
    let artist: String
    let outputIdentity: String
    let outputKind: String
    let graphicEQMode: GraphicEQMode
    let genreHints: [String]
    let instrumentHints: [String]
    let gains: [Float]
    let learnedBandAdjustments: [Float]
    let bassGain: Float
    let trebleGain: Float
    let surroundLevel: Float
    let reverbLevel: Float
    let stereoWidth: Float
    let processingIntensity: Float
    let feedback: AIEqualizerLearningFeedback
    let listenedSeconds: TimeInterval
    let recordedAt: Date
}

/// A compact, bounded policy produced from prior tuning outcomes. Raw audio is
/// never retained: only small parameter corrections and aggregate confidence
/// are allowed to influence a future proposal.
struct AIEqualizerLearningContext: Codable, Equatable, Sendable {
    let revision: Int
    let evidenceCount: Int
    let confidence: Float
    let bandAdjustments: [Float]
    let bassAdjustment: Float
    let trebleAdjustment: Float
    let surroundAdjustment: Float
    let reverbAdjustment: Float
    let stereoWidthAdjustment: Float
    let processingIntensityAdjustment: Float

    var isActive: Bool {
        evidenceCount > 0 && confidence >= 0.04
    }
}

struct AIEqualizerModelOutput: Codable, Equatable, Sendable {
    let profileName: String
    let gains: [Float]
    let preampDB: Float
    let tone: AIEqualizerToneConfiguration?
    let spatial: AIEqualizerSpatialConfiguration?
    let enhance: MonoEnhanceConfiguration?
    let calibration: AIEqualizerCalibrationConfiguration?
    let professional: AIEqualizerProfessionalConfiguration?
    let effects: MonoEffectTuningConfiguration?
    var confidence: Float
    var confidenceCalibration: AudioTrainingConfidenceEvidence? = nil
    let summary: String
    let artistStyleReference: String
    let vocalCharacterReference: String

    private enum CodingKeys: String, CodingKey {
        case profileName
        case gains
        case preampDB
        case tone
        case spatial
        case enhance
        case calibration
        case professional
        case effects
        case confidence
        case summary
        case artistStyleReference
        case vocalCharacterReference
    }

    init(
        profileName: String,
        gains: [Float],
        preampDB: Float,
        tone: AIEqualizerToneConfiguration?,
        spatial: AIEqualizerSpatialConfiguration?,
        enhance: MonoEnhanceConfiguration?,
        calibration: AIEqualizerCalibrationConfiguration?,
        professional: AIEqualizerProfessionalConfiguration?,
        effects: MonoEffectTuningConfiguration?,
        confidence: Float,
        summary: String,
        artistStyleReference: String = "",
        vocalCharacterReference: String = ""
    ) {
        self.profileName = profileName
        self.gains = gains
        self.preampDB = preampDB
        self.tone = tone
        self.spatial = spatial
        self.enhance = enhance
        self.calibration = calibration
        self.professional = professional
        self.effects = effects
        self.confidence = confidence
        self.summary = summary
        self.artistStyleReference = artistStyleReference
        self.vocalCharacterReference = vocalCharacterReference
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profileName = try values.decodeIfPresent(String.self, forKey: .profileName) ?? ""
        gains = try values.decode([Float].self, forKey: .gains)
        preampDB = try values.decodeIfPresent(Float.self, forKey: .preampDB) ?? 0

        // A partially emitted optional section should not invalidate the core EQ
        // curve. Proposal validation supplies safe defaults for that section.
        tone = try? values.decode(AIEqualizerToneConfiguration.self, forKey: .tone)
        spatial = try? values.decode(AIEqualizerSpatialConfiguration.self, forKey: .spatial)
        enhance = try? values.decode(MonoEnhanceConfiguration.self, forKey: .enhance)
        calibration = try? values.decode(AIEqualizerCalibrationConfiguration.self, forKey: .calibration)
        professional = try? values.decode(AIEqualizerProfessionalConfiguration.self, forKey: .professional)
        effects = try? values.decode(MonoEffectTuningConfiguration.self, forKey: .effects)

        confidence = try values.decodeIfPresent(Float.self, forKey: .confidence) ?? 0.65
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        artistStyleReference = try values.decodeIfPresent(String.self, forKey: .artistStyleReference) ?? ""
        vocalCharacterReference = try values.decodeIfPresent(String.self, forKey: .vocalCharacterReference) ?? ""
    }
}

/// Evidence that the enabled Agent skills and the mandatory local tuning tool
/// participated in a successful generation. This remains intentionally small
/// because every proposal is persisted locally and may also be cloud-synced.
struct AIEqualizerSkillCompliance: Codable, Equatable, Sendable {
    enum ExecutionMode: String, Codable, Equatable, Sendable {
        case requiredModelTool
        case modelPromptFallback
        case appleIntelligenceLocalCompiler
        case trainedCoreMLModel
    }

    let accepted: Bool
    let executionMode: ExecutionMode
    let knowledgeVersion: String
    let toolVersion: String
    let checkedRuleCount: Int
    let warningCodes: [String]
    let enabledSkillIDs: [String]
    let requiredSkillIDs: [String]
    let modelToolInvocationCount: Int
    let localValidationApplied: Bool
    let validatedAt: Date
}

/// AI 生成并经本地校验后的完整调音方案。
///
/// 同时携带图示均衡、空间、增强、校准、专业处理与效果参数，可缓存并重新应用。
struct AIEqualizerProposal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let songID: Int
    let profileName: String
    private(set) var graphicEQMode: GraphicEQMode
    private(set) var gains: [Float]
    let preampDB: Float
    let tone: AIEqualizerToneConfiguration
    let spatial: AIEqualizerSpatialConfiguration
    let enhance: MonoEnhanceConfiguration
    let calibration: AIEqualizerCalibrationConfiguration
    let professional: AIEqualizerProfessionalConfiguration
    let effects: MonoEffectTuningConfiguration
    let confidence: Float
    let confidenceCalibration: AudioTrainingConfidenceEvidence?
    let summary: String
    let artistStyleReference: String?
    let vocalCharacterReference: String?
    let provider: AIWireProtocol
    let model: String
    let agentVersion: String?
    /// The effective, merged skill identity (bundled rules + remote policy +
    /// local user skills). Missing values identify proposals from older builds
    /// and deliberately prevent automatic reuse after the skill pipeline ships.
    let skillFingerprint: String?
    let skillRevision: String?
    let skillCompliance: AIEqualizerSkillCompliance?
    let learningRevision: Int?
    let learningConfidence: Float?
    let learningEvidenceCount: Int?
    let createdAt: Date
    let tuningIntensity: AIEqualizerTuningIntensity?
    let tuningProfile: AIEqualizerTuningProfile?
    var timing: AIEqualizerTiming?

    var confidenceDisplayText: String {
        if skillCompliance?.executionMode == .trainedCoreMLModel
            || model.hasPrefix("mono-resonance-") || model.hasPrefix("mono-audio-") {
            if let evidence = confidenceCalibration, evidence.isValid,
               evidence.branch == "\(graphicEQMode.rawValue):\(resolvedTuningProfile.rawValue)" {
                return evidence.displayText
            }
            return String(localized: "audio_training_confidence_uncalibrated")
        }
        return "\(Int(confidence * 100))%"
    }

    var resolvedTuningProfile: AIEqualizerTuningProfile {
        tuningProfile ?? .standard
    }

    var profileSpecificSummary: String {
        let focus = resolvedTuningProfile.summaryFocus
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? resolvedTuningProfile.summaryFallback : trimmed
        guard !base.contains(focus) else { return base }
        return "\(base)\n\(focus)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case songID
        case profileName
        case graphicEQMode
        case gains
        case preampDB
        case tone
        case spatial
        case enhance
        case calibration
        case professional
        case effects
        case confidence
        case confidenceCalibration
        case summary
        case artistStyleReference
        case vocalCharacterReference
        case provider
        case model
        case agentVersion
        case skillFingerprint
        case skillRevision
        case skillCompliance
        case learningRevision
        case learningConfidence
        case learningEvidenceCount
        case createdAt
        case tuningIntensity
        case tuningProfile
        case timing
    }

    /// Persisted proposals predate several required sections (graphic-EQ mode,
    /// effects and learning metadata). Decode the durable EQ core first and use
    /// neutral defaults for sections an older app could not have written.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedGains = try values.decode([Float].self, forKey: .gains)
        let decodedMode = (try? values.decode(GraphicEQMode.self, forKey: .graphicEQMode))
            ?? (decodedGains.count > GraphicEQMode.tenBand.bandCount ? .thirtyTwoBand : .tenBand)
        let decodedIntensity = try? values.decode(
            AIEqualizerTuningIntensity.self,
            forKey: .tuningIntensity
        )
        let decodedTuningProfile = try? values.decode(
            AIEqualizerTuningProfile.self,
            forKey: .tuningProfile
        )

        id = (try? values.decode(UUID.self, forKey: .id)) ?? UUID()
        songID = try values.decode(Int.self, forKey: .songID)
        profileName = (try? values.decode(String.self, forKey: .profileName)) ?? "Mono AI"
        graphicEQMode = decodedMode
        gains = decodedMode.normalizedGains(decodedGains)
        preampDB = min(0, max(
            -18,
            (try? values.decode(Float.self, forKey: .preampDB)) ?? 0
        ))
        tone = (try? values.decode(AIEqualizerToneConfiguration.self, forKey: .tone))
            ?? AIEqualizerToneConfiguration(bassGain: 0, trebleGain: 0)
        spatial = (try? values.decode(AIEqualizerSpatialConfiguration.self, forKey: .spatial))
            ?? AIEqualizerSpatialConfiguration(surroundLevel: 0, reverbLevel: 0, stereoWidth: 1)
        enhance = (try? values.decode(MonoEnhanceConfiguration.self, forKey: .enhance))
            ?? Self.persistedEnhanceFallback(
                tuningProfile: decodedTuningProfile ?? .standard,
                tuningIntensity: decodedIntensity ?? .smart
            )
        calibration = (try? values.decode(AIEqualizerCalibrationConfiguration.self, forKey: .calibration))
            ?? AIEqualizerCalibrationConfiguration(
                outputCalibrationEnabled: false,
                loudnessMatchingEnabled: false,
                smartSongCompensationEnabled: false
            )
        professional = (try? values.decode(AIEqualizerProfessionalConfiguration.self, forKey: .professional))
            ?? Self.neutralProfessionalConfiguration
        effects = (try? values.decode(MonoEffectTuningConfiguration.self, forKey: .effects))
            ?? MonoEffectTuningConfiguration(finalLimiterEnabled: true)
        confidence = min(1, max(
            0,
            (try? values.decode(Float.self, forKey: .confidence)) ?? 0.65
        ))
        confidenceCalibration = try? values.decode(
            AudioTrainingConfidenceEvidence.self, forKey: .confidenceCalibration
        )
        summary = (try? values.decode(String.self, forKey: .summary)) ?? ""
        artistStyleReference = try? values.decode(String.self, forKey: .artistStyleReference)
        vocalCharacterReference = try? values.decode(String.self, forKey: .vocalCharacterReference)
        provider = (try? values.decode(AIWireProtocol.self, forKey: .provider)) ?? .openAICompatible
        model = (try? values.decode(String.self, forKey: .model)) ?? ""
        agentVersion = try? values.decode(String.self, forKey: .agentVersion)
        skillFingerprint = try? values.decode(String.self, forKey: .skillFingerprint)
        skillRevision = try? values.decode(String.self, forKey: .skillRevision)
        skillCompliance = try? values.decode(
            AIEqualizerSkillCompliance.self,
            forKey: .skillCompliance
        )
        learningRevision = try? values.decode(Int.self, forKey: .learningRevision)
        learningConfidence = try? values.decode(Float.self, forKey: .learningConfidence)
        learningEvidenceCount = try? values.decode(Int.self, forKey: .learningEvidenceCount)
        createdAt = (try? values.decode(Date.self, forKey: .createdAt)) ?? Date()
        tuningIntensity = decodedIntensity
        tuningProfile = decodedTuningProfile
        timing = try? values.decode(AIEqualizerTiming.self, forKey: .timing)
    }

    init(
        songID: Int,
        output: AIEqualizerModelOutput,
        features: AIEqualizerAudioFeatures,
        provider: AIWireProtocol,
        model: String,
        agentVersion: String,
        skillFingerprint: String,
        skillRevision: String,
        skillCompliance: AIEqualizerSkillCompliance,
        allowsArtistStyleReference: Bool,
        allowsVocalCharacterReference: Bool,
        tuningIntensity: AIEqualizerTuningIntensity = .smart,
        tuningProfile: AIEqualizerTuningProfile = .standard,
        avoidingProfileNames: Set<String> = [],
        learningContext: AIEqualizerLearningContext? = nil,
        applyLearningAdjustments: Bool = true,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget? = nil
    ) {
        let effectiveLearningContext = applyLearningAdjustments ? learningContext : nil
        let baseGains = Self.validatedGains(
            output.gains,
            mode: features.graphicEQMode,
            intensity: tuningIntensity
        )
        let learnedBandAdjustments = effectiveLearningContext?.isActive == true
            ? features.graphicEQMode.normalizedGains(
                effectiveLearningContext?.bandAdjustments ?? [],
                limit: 1.25
            )
            : Array(repeating: 0, count: features.graphicEQMode.bandCount)
        let deviceBandAdjustments = deviceTuningTarget?.gains(for: features.graphicEQMode)
            ?? Array(repeating: 0, count: features.graphicEQMode.bandCount)
        let normalized = Self.validatedGains(
            zip(zip(baseGains, learnedBandAdjustments), deviceBandAdjustments).map { pair in
                pair.0.0 + pair.0.1 + pair.1
            },
            mode: features.graphicEQMode,
            intensity: tuningIntensity
        )

        let baseTone = Self.validatedTone(output.tone, intensity: tuningIntensity)
        let resolvedTone = Self.validatedTone(
            AIEqualizerToneConfiguration(
                bassGain: baseTone.bassGain + (effectiveLearningContext?.bassAdjustment ?? 0),
                trebleGain: baseTone.trebleGain + (effectiveLearningContext?.trebleAdjustment ?? 0)
            ),
            intensity: tuningIntensity
        )
        let baseSpatial = Self.validatedSpatial(
            output.spatial,
            features: features,
            intensity: tuningIntensity,
            tuningProfile: tuningProfile
        )
        let resolvedSpatial = Self.validatedSpatial(
            AIEqualizerSpatialConfiguration(
                surroundLevel: baseSpatial.surroundLevel
                    + (effectiveLearningContext?.surroundAdjustment ?? 0),
                reverbLevel: baseSpatial.reverbLevel
                    + (effectiveLearningContext?.reverbAdjustment ?? 0),
                stereoWidth: baseSpatial.stereoWidth
                    + (effectiveLearningContext?.stereoWidthAdjustment ?? 0)
            ),
            features: features,
            intensity: tuningIntensity,
            tuningProfile: tuningProfile
        )
        let resolvedEnhance = Self.validatedEnhance(
            output.enhance,
            features: features,
            intensity: tuningIntensity,
            tuningProfile: tuningProfile
        )
        let baseProfessional = Self.validatedProfessional(
            output.professional,
            features: features,
            intensity: tuningIntensity
        )
        let resolvedProfessional = AIEqualizerProfessionalConfiguration(
            processingIntensity: min(
                tuningIntensity.processingIntensityRange.upperBound,
                max(
                    tuningIntensity.processingIntensityRange.lowerBound,
                    baseProfessional.processingIntensity
                        + (effectiveLearningContext?.processingIntensityAdjustment ?? 0)
                )
            ),
            dynamicEQ: baseProfessional.dynamicEQ,
            multiband: baseProfessional.multiband,
            parametricEQ: baseProfessional.parametricEQ
        )
        let resolvedEffects = Self.validatedEffects(
            output.effects,
            features: features,
            professional: resolvedProfessional,
            intensity: tuningIntensity,
            tuningProfile: tuningProfile
        )
        let graphicPeak = max(0, normalized.max() ?? 0)
        let tonePeak = max(0, max(resolvedTone.bassGain, resolvedTone.trebleGain)) * 0.55
        let spatialReserve = resolvedSpatial.surroundLevel * 1.2
            + resolvedSpatial.reverbLevel
            + max(0, resolvedSpatial.stereoWidth - 1) * 1.5
        let enhancementReserve = resolvedEffects.subboostGainDB * 0.45
            + resolvedEffects.virtualBassStrength * 0.25
            + resolvedEffects.exciterAmountDB * 0.18
            + max(0, resolvedEffects.compressorMakeupDB)
            + (resolvedEffects.haasEnabled ? 0.6 : 0)
        let parametricPeak = resolvedProfessional.parametricEQ.enabled
            ? max(0, resolvedProfessional.parametricEQ.bands.map(\.gainDB).max() ?? 0)
            : 0
        let truePeakReserve = max(0, features.estimatedTruePeakDBTP + 1)
        let clippingReserve = min(1.5, max(0, features.clippingRatio) * 6)
        let requiredHeadroom = -min(
            18,
            graphicPeak
                + tonePeak
                + parametricPeak
                + spatialReserve
                + enhancementReserve
                + resolvedEnhance.estimatedPeakBoostDB
                + truePeakReserve
                + clippingReserve
                + 0.75
        )

        id = UUID()
        self.songID = songID
        graphicEQMode = features.graphicEQMode
        profileName = Self.localizedProfileName(
            output.profileName,
            gains: normalized,
            spatial: resolvedSpatial,
            features: features,
            tuningProfile: tuningProfile,
            avoiding: avoidingProfileNames
        )
        gains = normalized
        preampDB = min(0, max(-18, min(output.preampDB, requiredHeadroom)))
        tone = resolvedTone
        spatial = resolvedSpatial
        enhance = resolvedEnhance
        calibration = output.calibration ?? AIEqualizerCalibrationConfiguration(
            outputCalibrationEnabled: true,
            loudnessMatchingEnabled: true,
            smartSongCompensationEnabled: true
        )
        professional = resolvedProfessional
        effects = resolvedEffects
        confidenceCalibration = skillCompliance.executionMode == .trainedCoreMLModel
            ? output.confidenceCalibration : nil
        confidence = confidenceCalibration?.isValid == true
            ? Float(confidenceCalibration?.coverage ?? 0) : min(1, max(0, output.confidence))
        let resolvedArtistReference = allowsArtistStyleReference
            ? Self.localizedReference(output.artistStyleReference)
            : nil
        let resolvedVocalReference = allowsVocalCharacterReference
            ? Self.localizedReference(output.vocalCharacterReference)
            : nil
        artistStyleReference = resolvedArtistReference
        vocalCharacterReference = resolvedVocalReference
        if skillCompliance.executionMode == .trainedCoreMLModel {
            // Describe only the track's contribution relative to the calibrated device baseline.
            let baseline = Self.validatedGains(
                deviceBandAdjustments,
                mode: features.graphicEQMode,
                intensity: tuningIntensity
            )
            let dynamicEQActive = resolvedProfessional.dynamicEQ.enabled
                && resolvedProfessional.dynamicEQ.bands.contains { $0.ratio > 1.01 && $0.maxReductionDB > 0.05 }
            let multibandActive = resolvedProfessional.multiband.enabled
                && zip(resolvedProfessional.multiband.ratios, resolvedProfessional.multiband.maxReductionDB)
                    .contains { $0 > 1.01 && $1 > 0.05 }
            let description = AudioTrainingProposalSummary.make(
                bandFrequenciesHz: features.bandFrequenciesHz,
                gains: zip(normalized, baseline).map { $0 - $1 },
                tone: (resolvedTone.bassGain, resolvedTone.trebleGain),
                enhancement: (resolvedEnhance.isEnabled, resolvedEnhance.vocalFocus,
                              resolvedEnhance.airAmount, resolvedEnhance.deEssAmount,
                              resolvedEnhance.transientAttack, resolvedEnhance.stageWidth),
                spatial: (resolvedSpatial.stereoWidth, resolvedSpatial.surroundLevel,
                          resolvedSpatial.reverbLevel),
                isSpatialProfile: tuningProfile == .monoSpatialEnhancement,
                protectsPeaks: resolvedEffects.finalLimiterEnabled
                    && min(output.preampDB, requiredHeadroom) < -1.5,
                controlsDynamics: (resolvedEffects.compressorEnabled && resolvedEffects.compressorRatio > 1.01)
                    || (resolvedProfessional.processingIntensity > 0
                        && (dynamicEQActive || multibandActive))
            )
            summary = "\(description)\n\(tuningProfile.summaryFocus)"
        } else {
            summary = Self.localizedSummary(output.summary, tuningProfile: tuningProfile)
        }
        self.provider = provider
        self.model = model
        self.agentVersion = agentVersion
        self.skillFingerprint = skillFingerprint
        self.skillRevision = skillRevision
        self.skillCompliance = skillCompliance
        learningRevision = learningContext?.revision
        learningConfidence = learningContext?.isActive == true ? learningContext?.confidence : nil
        learningEvidenceCount = learningContext?.isActive == true ? learningContext?.evidenceCount : nil
        createdAt = Date()
        self.tuningIntensity = tuningIntensity
        self.tuningProfile = tuningProfile
        timing = nil
    }

    /// Manual history restore follows the user's current graphic-EQ resolution.
    /// The saved curve is resampled in logarithmic frequency space rather than
    /// rejecting an otherwise valid proposal.
    func adapted(to mode: GraphicEQMode) -> AIEqualizerProposal {
        guard mode != graphicEQMode else { return self }
        var adapted = self
        adapted.gains = mode.resampledGains(gains, from: graphicEQMode)
        adapted.graphicEQMode = mode
        return adapted
    }

    private static var neutralProfessionalConfiguration: AIEqualizerProfessionalConfiguration {
        AIEqualizerProfessionalConfiguration(
            processingIntensity: 1,
            dynamicEQ: AIEqualizerDynamicEQConfiguration(enabled: false, bands: []),
            multiband: AIEqualizerMultibandConfiguration(
                enabled: false,
                lowCrossoverHz: 180,
                highCrossoverHz: 3_800,
                thresholdsDB: [-13, -11, -15],
                ratios: [1.45, 1.28, 1.5],
                maxReductionDB: [2.2, 1.5, 2],
                attackMS: 22,
                releaseMS: 210
            ),
            parametricEQ: AIEqualizerParametricEQConfiguration(enabled: false, bands: [])
        )
    }

    private static func persistedEnhanceFallback(
        tuningProfile: AIEqualizerTuningProfile,
        tuningIntensity: AIEqualizerTuningIntensity
    ) -> MonoEnhanceConfiguration {
        let scale: Float
        switch tuningIntensity {
        case .gentle: scale = 0.68
        case .standard: scale = 0.86
        case .smart: scale = 1
        case .strong: scale = 1.10
        }
        return MonoEnhanceConfiguration(
            isEnabled: true,
            transientAttack: 0.16 * scale,
            transientSustain: 0.10 * scale,
            vocalFocus: 0.16 * scale,
            airAmount: 0.10 * scale,
            deEssAmount: 0.22 * scale,
            lowFrequencyFocus: 0.32 * scale,
            stageWidth: (tuningProfile == .monoSpatialEnhancement ? 0.42 : 0.07) * scale,
            microDynamics: 0.16 * scale,
            lowLevelCompensation: 0.14 * scale
        )
    }

    private static func validatedGains(
        _ values: [Float],
        mode: GraphicEQMode,
        intensity: AIEqualizerTuningIntensity
    ) -> [Float] {
        var result = Array(values.prefix(mode.bandCount)).map { value -> Float in
            guard value.isFinite else { return 0 }
            return min(intensity.graphicGainRange.upperBound, max(intensity.graphicGainRange.lowerBound, value))
        }
        if result.count < mode.bandCount {
            result.append(contentsOf: repeatElement(Float(0), count: mode.bandCount - result.count))
        }
        let maximumAdjacentDelta: Float
        switch intensity {
        case .gentle:
            maximumAdjacentDelta = mode == .thirtyTwoBand ? 1.8 : 2.7
        case .standard:
            maximumAdjacentDelta = mode == .thirtyTwoBand ? 2.4 : 3.7
        case .smart, .strong:
            maximumAdjacentDelta = mode == .thirtyTwoBand ? 3 : 4.5
        }
        func smoothAdjacentDeltas() {
            for index in 1..<result.count {
                result[index] = min(
                    result[index - 1] + maximumAdjacentDelta,
                    max(result[index - 1] - maximumAdjacentDelta, result[index])
                )
            }
            guard result.count > 1 else { return }
            for index in stride(from: result.count - 2, through: 0, by: -1) {
                result[index] = min(
                    result[index + 1] + maximumAdjacentDelta,
                    max(result[index + 1] - maximumAdjacentDelta, result[index])
                )
            }
        }
        smoothAdjacentDeltas()

        // 模型经常给出 ±1 dB 内的“礼貌曲线”，在响度匹配下与原声几乎无法
        // 区分。保留曲线形状，把峰值提升到可闻门限；全零曲线视为刻意中性，
        // 不做放大。
        let audibilityFloor: Float
        switch intensity {
        case .gentle: audibilityFloor = 1.6
        case .standard: audibilityFloor = 2.0
        case .smart, .strong: audibilityFloor = 2.4
        }
        let peak = result.map(abs).max() ?? 0
        if peak >= 0.3, peak < audibilityFloor {
            let scale = min(2.2, audibilityFloor / peak)
            result = result.map {
                min(
                    intensity.graphicGainRange.upperBound,
                    max(intensity.graphicGainRange.lowerBound, $0 * scale)
                )
            }
            smoothAdjacentDeltas()
        }
        return result
    }

    private static func validatedTone(
        _ value: AIEqualizerToneConfiguration?,
        intensity: AIEqualizerTuningIntensity
    ) -> AIEqualizerToneConfiguration {
        AIEqualizerToneConfiguration(
            bassGain: clampedFinite(value?.bassGain, fallback: 0, range: intensity.toneRange),
            trebleGain: clampedFinite(value?.trebleGain, fallback: 0, range: intensity.toneRange)
        )
    }

    private static func validatedSpatial(
        _ value: AIEqualizerSpatialConfiguration?,
        features: AIEqualizerAudioFeatures,
        intensity: AIEqualizerTuningIntensity,
        tuningProfile: AIEqualizerTuningProfile
    ) -> AIEqualizerSpatialConfiguration {
        let isSpatialProfile = tuningProfile == .monoSpatialEnhancement
        let maximum: (surround: Float, reverb: Float, width: Float)
        let minimum: (surround: Float, reverb: Float, width: Float)
        switch (isSpatialProfile, features.outputKind) {
        // 内置扬声器的物理间距太小，slev 宽度类处理几乎不可闻；
        // 依赖更高的混响湿度与舞台展宽才能让空间档在外放时成立。
        case (true, "builtInSpeaker"):
            maximum = (0.48, 0.64, 1.30)
            minimum = (0.30, 0.40, 1.16)
        case (true, "bluetooth"):
            maximum = (0.62, 0.58, 1.42)
            minimum = (0.38, 0.34, 1.22)
        case (true, "wired"), (true, "usb"):
            maximum = (0.68, 0.62, 1.48)
            minimum = (0.42, 0.38, 1.26)
        case (true, "car"):
            maximum = (0.50, 0.54, 1.30)
            minimum = (0.30, 0.32, 1.16)
        case (true, "airPlay"):
            maximum = (0.52, 0.56, 1.34)
            minimum = (0.30, 0.32, 1.18)
        case (true, _):
            maximum = (0.58, 0.58, 1.38)
            minimum = (0.34, 0.34, 1.20)
        case (false, "builtInSpeaker"):
            maximum = (0.08, 0.035, 1.06)
            minimum = (0, 0, 1)
        case (false, "wired"), (false, "usb"):
            maximum = (0.14, 0.07, 1.12)
            minimum = (0, 0, 1)
        case (false, "bluetooth"):
            maximum = (0.13, 0.06, 1.10)
            minimum = (0, 0, 1)
        case (false, "car"):
            maximum = (0.10, 0.05, 1.08)
            minimum = (0, 0, 1)
        case (false, "airPlay"):
            maximum = (0.11, 0.05, 1.09)
            minimum = (0, 0, 1)
        case (false, _):
            maximum = (0.11, 0.05, 1.09)
            minimum = (0, 0, 1)
        }

        let phaseSafety: Float
        if features.phaseCorrelation < 0 || features.monoCompatibility < 0.45 {
            phaseSafety = 0.56
        } else if features.phaseCorrelation < 0.12 || features.monoCompatibility < 0.62 {
            phaseSafety = 0.78
        } else {
            phaseSafety = 1
        }
        let ambienceSafety: Float = features.spectralFlatness > 0.68 ? 0.72 : 1
        let surroundMaximum = min(
            isSpatialProfile ? 0.70 : intensity.surroundRange.upperBound,
            maximum.surround * phaseSafety
        )
        let reverbMaximum = min(
            isSpatialProfile ? 0.70 : intensity.reverbRange.upperBound,
            maximum.reverb * ambienceSafety
        )
        let widthMaximum = min(
            isSpatialProfile ? 1.48 : intensity.stereoWidthRange.upperBound,
            1 + (maximum.width - 1) * phaseSafety
        )
        let surroundMinimum = isSpatialProfile
            ? min(surroundMaximum, minimum.surround * phaseSafety)
            : 0
        let reverbMinimum = isSpatialProfile
            ? min(reverbMaximum, minimum.reverb * ambienceSafety)
            : 0
        let widthMinimum = isSpatialProfile
            ? min(widthMaximum, 1 + (minimum.width - 1) * phaseSafety)
            : 1

        let proposedSurround = clampedFinite(
            value?.surroundLevel,
            fallback: 0,
            range: 0...surroundMaximum
        )
        let proposedReverb = clampedFinite(
            value?.reverbLevel,
            fallback: 0,
            range: 0...reverbMaximum
        )
        let proposedWidth = clampedFinite(
            value?.stereoWidth,
            fallback: 1,
            range: min(1, intensity.stereoWidthRange.lowerBound)...widthMaximum
        )
        let fallback = spatialFallback(for: features, tuningProfile: tuningProfile)

        let resolvedSurround = proposedSurround <= 0.005
            ? min(surroundMaximum, fallback.surroundLevel)
            : proposedSurround
        let resolvedReverb = proposedReverb <= 0.005
            ? min(reverbMaximum, fallback.reverbLevel)
            : proposedReverb
        let resolvedWidth = abs(proposedWidth - 1) <= 0.005
            ? min(widthMaximum, max(1, fallback.stereoWidth))
            : proposedWidth

        return AIEqualizerSpatialConfiguration(
            surroundLevel: min(surroundMaximum, max(surroundMinimum, resolvedSurround)),
            reverbLevel: min(reverbMaximum, max(reverbMinimum, resolvedReverb)),
            stereoWidth: min(widthMaximum, max(widthMinimum, resolvedWidth))
        )
    }

    private static func validatedEnhance(
        _ value: MonoEnhanceConfiguration?,
        features: AIEqualizerAudioFeatures,
        intensity: AIEqualizerTuningIntensity,
        tuningProfile: AIEqualizerTuningProfile
    ) -> MonoEnhanceConfiguration {
        let fallback = monoEnhanceFallback(
            for: features,
            tuningProfile: tuningProfile
        )
        // `isEnabled = false` cannot bypass the complete Mono tuning stage.
        // Phase/peak hazards are handled per parameter below; disabling every
        // tonal and dynamics control made a valid AI proposal sound identical
        // to bypass whenever a provider was overly conservative.
        let source = value.flatMap {
            $0.isEnabled && $0.hasAudibleProcessing ? $0 : nil
        } ?? fallback

        let intensityScale: Float
        switch intensity {
        case .gentle: intensityScale = 0.64
        case .standard: intensityScale = 0.84
        case .smart: intensityScale = 1
        case .strong: intensityScale = 1.12
        }
        let phaseSafety: Float = features.phaseCorrelation < 0
            || features.monoCompatibility < 0.48 ? 0.48
            : (features.phaseCorrelation < 0.15 || features.monoCompatibility < 0.65 ? 0.76 : 1)
        let peakSafety: Float = features.clippingRatio > 0.000_5
            || features.estimatedTruePeakDBTP > -0.25 ? 0.58 : 1
        let spatialProfile = tuningProfile == .monoSpatialEnhancement

        return MonoEnhanceConfiguration(
            isEnabled: true,
            transientAttack: clampedFinite(
                source.transientAttack,
                fallback: fallback.transientAttack,
                range: 0...min(0.38, 0.32 * intensityScale * peakSafety)
            ),
            transientSustain: clampedFinite(
                source.transientSustain,
                fallback: fallback.transientSustain,
                range: 0...min(0.30, 0.24 * intensityScale)
            ),
            vocalFocus: clampedFinite(
                source.vocalFocus,
                fallback: fallback.vocalFocus,
                range: 0...min(0.48, 0.40 * intensityScale)
            ),
            airAmount: clampedFinite(
                source.airAmount,
                fallback: fallback.airAmount,
                range: 0...min(0.34, 0.28 * intensityScale * peakSafety)
            ),
            deEssAmount: clampedFinite(
                source.deEssAmount,
                fallback: fallback.deEssAmount,
                range: 0...min(0.72, 0.62 * intensityScale)
            ),
            lowFrequencyFocus: clampedFinite(
                source.lowFrequencyFocus,
                fallback: fallback.lowFrequencyFocus,
                range: 0...min(0.72, 0.62 * intensityScale)
            ),
            stageWidth: clampedFinite(
                source.stageWidth,
                fallback: fallback.stageWidth,
                range: 0...(spatialProfile
                    ? min(0.80, 0.74 * intensityScale * phaseSafety)
                    : min(0.20, 0.16 * intensityScale * phaseSafety))
            ),
            microDynamics: clampedFinite(
                source.microDynamics,
                fallback: fallback.microDynamics,
                range: 0...min(0.42, 0.34 * intensityScale * peakSafety)
            ),
            lowLevelCompensation: clampedFinite(
                source.lowLevelCompensation,
                fallback: fallback.lowLevelCompensation,
                range: 0...min(0.58, 0.48 * intensityScale)
            )
        )
    }

    private static func monoEnhanceFallback(
        for features: AIEqualizerAudioFeatures,
        tuningProfile: AIEqualizerTuningProfile
    ) -> MonoEnhanceConfiguration {
        let crestFactor = min(1, max(0, (features.crestFactorDB - 5) / 11))
        let transientActivity = min(1, max(0, features.transientDensity))
        let density = min(1, max(0, (features.spectralFlatness - 0.25) / 0.55))
        let vocalConfidence = features.vocalReference?.confidence ?? 0
        let vocalPresence = features.vocalReference?.presence ?? 0
        let vocalBrightness = max(
            features.vocalReference?.brightness ?? 0,
            features.vocalReference?.airiness ?? 0
        )
        let highDeficit = min(1, max(0, (0.24 - features.highEnergyRatio) / 0.18))
        let dynamicCompression = min(1, max(0, (9 - features.dynamicSpreadDB) / 7))
        let spatialProfile = tuningProfile == .monoSpatialEnhancement
        let deviceLowFocus: Float
        switch features.outputKind {
        case "builtInSpeaker": deviceLowFocus = 0.24
        case "car", "airPlay": deviceLowFocus = 0.34
        default: deviceLowFocus = 0.42
        }

        return MonoEnhanceConfiguration(
            isEnabled: true,
            transientAttack: 0.10 + crestFactor * 0.11 + transientActivity * 0.05,
            transientSustain: 0.07 + dynamicCompression * 0.10,
            vocalFocus: 0.10 + vocalConfidence * vocalPresence * 0.20,
            airAmount: 0.07 + highDeficit * 0.12,
            deEssAmount: 0.12 + vocalConfidence * vocalBrightness * 0.30,
            lowFrequencyFocus: deviceLowFocus + max(0, features.lowEnergyRatio - 0.34) * 0.35,
            stageWidth: spatialProfile ? 0.60 - density * 0.12 : 0.08,
            microDynamics: 0.10 + dynamicCompression * 0.16,
            lowLevelCompensation: features.outputKind == "builtInSpeaker" ? 0.20 : 0.14
        )
    }

    private static func validatedEffects(
        _ value: MonoEffectTuningConfiguration?,
        features: AIEqualizerAudioFeatures,
        professional: AIEqualizerProfessionalConfiguration,
        intensity: AIEqualizerTuningIntensity,
        tuningProfile: AIEqualizerTuningProfile
    ) -> MonoEffectTuningConfiguration {
        let usesSpatialHaas = tuningProfile == .monoSpatialEnhancement
            && features.phaseCorrelation >= 0.08
            && features.monoCompatibility >= 0.58
        let defaultHaasDelay: Float
        switch features.outputKind {
        case "builtInSpeaker": defaultHaasDelay = 8
        case "bluetooth": defaultHaasDelay = 9
        case "wired", "usb": defaultHaasDelay = 13
        case "car", "airPlay": defaultHaasDelay = 10
        default: defaultHaasDelay = 10
        }

        guard let value else {
            return MonoEffectTuningConfiguration(
                haasEnabled: usesSpatialHaas,
                haasDelayMS: defaultHaasDelay,
                finalLimiterEnabled: true
            )
        }

        return MonoEffectTuningConfiguration(
            // Offline-style loudnorm is not safe in Mono's realtime render
            // chain. Measured loudness matching and the final limiter cover it.
            loudnessNormalizationEnabled: false,
            targetLUFS: clampedFinite(value.targetLUFS, fallback: -14, range: -24 ... -9),
            targetLRA: clampedFinite(value.targetLRA, fallback: 9, range: 3...18),
            truePeakCeilingDB: clampedFinite(value.truePeakCeilingDB, fallback: -1, range: -3 ... -0.2),
            compressorEnabled: false,
            compressorThresholdDB: clampedFinite(value.compressorThresholdDB, fallback: -18, range: -36 ... -4),
            compressorRatio: clampedFinite(
                value.compressorRatio,
                fallback: 2,
                range: 1...min(6, intensity.dynamicRatioMaximum)
            ),
            compressorAttackMS: clampedFinite(value.compressorAttackMS, fallback: 18, range: 1...200),
            compressorReleaseMS: clampedFinite(value.compressorReleaseMS, fallback: 180, range: 30...1_200),
            compressorMakeupDB: clampedFinite(
                value.compressorMakeupDB,
                fallback: 0,
                range: -min(3, intensity.enhancementGainMaximum)...min(6, intensity.enhancementGainMaximum)
            ),
            subboostEnabled: false,
            subboostGainDB: clampedFinite(
                value.subboostGainDB,
                fallback: 0,
                range: 0...intensity.enhancementGainMaximum
            ),
            subboostCutoffHz: clampedFinite(value.subboostCutoffHz, fallback: 90, range: 40...180),
            bs2bEnabled: false,
            bs2bCutoffHz: min(1_500, max(400, value.bs2bCutoffHz)),
            bs2bFeed: min(100, max(10, value.bs2bFeed)),
            crossfeedEnabled: false,
            crossfeedStrength: clampedFinite(value.crossfeedStrength, fallback: 0.2, range: 0...0.55),
            haasEnabled: usesSpatialHaas,
            haasDelayMS: clampedFinite(
                value.haasDelayMS,
                fallback: defaultHaasDelay,
                range: 7...16
            ),
            virtualBassEnabled: false,
            virtualBassCutoffHz: clampedFinite(value.virtualBassCutoffHz, fallback: 180, range: 80...320),
            virtualBassStrength: clampedFinite(
                value.virtualBassStrength,
                fallback: 0,
                range: 0...min(6, intensity.enhancementGainMaximum)
            ),
            exciterEnabled: false,
            exciterAmountDB: clampedFinite(
                value.exciterAmountDB,
                fallback: 0,
                range: 0...min(6, intensity.enhancementGainMaximum)
            ),
            exciterFrequencyHz: clampedFinite(value.exciterFrequencyHz, fallback: 7_500, range: 3_000...14_000),
            softclipEnabled: false,
            softclipType: min(7, max(0, value.softclipType)),
            finalLimiterEnabled: value.finalLimiterEnabled,
            finalLimiterCeilingDB: clampedFinite(value.finalLimiterCeilingDB, fallback: -1, range: -3 ... -0.2)
        )
    }

    private static func spatialFallback(
        for features: AIEqualizerAudioFeatures,
        tuningProfile: AIEqualizerTuningProfile
    ) -> AIEqualizerSpatialConfiguration {
        let deviceBase: (surround: Float, reverb: Float, width: Float)
        switch features.outputKind {
        case "wired", "usb":
            deviceBase = (0.14, 0.045, 1.10)
        case "bluetooth":
            deviceBase = (0.12, 0.04, 1.08)
        case "car":
            deviceBase = (0.09, 0.025, 1.06)
        case "airPlay":
            deviceBase = (0.08, 0.025, 1.06)
        case "builtInSpeaker":
            deviceBase = (0.035, 0.012, 1.02)
        default:
            deviceBase = (0.07, 0.025, 1.05)
        }

        let dynamicFactor = min(1, max(0, (features.dynamicSpreadDB - 4) / 10))
        let brightnessFactor = min(1, max(0, (features.spectralCentroidHz - 1_400) / 2_800))
        let densityPenalty = min(1, max(0, (features.spectralFlatness - 0.42) / 0.38))
        var surround = deviceBase.surround + 0.035 * dynamicFactor + 0.018 * brightnessFactor
        var reverb = deviceBase.reverb + 0.025 * dynamicFactor - 0.018 * densityPenalty
        var width = deviceBase.width + 0.035 * dynamicFactor - 0.02 * densityPenalty
        let minimumReverb: Float = features.outputKind == "builtInSpeaker" ? 0.01 : 0.015
        if tuningProfile == .monoSpatialEnhancement {
            let deviceLimit: (surround: Float, reverb: Float, width: Float)
            let deviceMinimum: (surround: Float, reverb: Float, width: Float)
            switch features.outputKind {
            case "builtInSpeaker":
                deviceMinimum = (0.30, 0.40, 1.16)
                deviceLimit = (0.48, 0.64, 1.30)
            case "car":
                deviceMinimum = (0.30, 0.32, 1.16)
                deviceLimit = (0.50, 0.54, 1.30)
            case "airPlay":
                deviceMinimum = (0.30, 0.32, 1.18)
                deviceLimit = (0.52, 0.56, 1.34)
            case "bluetooth":
                deviceMinimum = (0.38, 0.34, 1.22)
                deviceLimit = (0.62, 0.58, 1.42)
            case "wired", "usb":
                deviceMinimum = (0.42, 0.38, 1.26)
                deviceLimit = (0.68, 0.62, 1.48)
            default:
                deviceMinimum = (0.34, 0.34, 1.20)
                deviceLimit = (0.58, 0.58, 1.38)
            }
            surround = min(
                deviceLimit.surround,
                max(deviceMinimum.surround, surround + 0.30 + 0.08 * dynamicFactor)
            )
            reverb = min(
                deviceLimit.reverb,
                max(deviceMinimum.reverb, reverb + 0.30 + 0.08 * dynamicFactor)
            )
            width = min(
                deviceLimit.width,
                max(deviceMinimum.width, width + 0.18 + 0.06 * dynamicFactor)
            )

            return AIEqualizerSpatialConfiguration(
                surroundLevel: surround,
                reverbLevel: reverb,
                stereoWidth: width
            )
        }

        return AIEqualizerSpatialConfiguration(
            surroundLevel: min(0.14, max(0, surround)),
            reverbLevel: min(0.07, max(minimumReverb, reverb)),
            stereoWidth: min(1.12, max(1, width))
        )
    }

    private static func localizedProfileName(
        _ value: String,
        gains: [Float],
        spatial: AIEqualizerSpatialConfiguration,
        features: AIEqualizerAudioFeatures,
        tuningProfile: AIEqualizerTuningProfile,
        avoiding recentNames: Set<String>
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidListeningProfileName(trimmed), !recentNames.contains(trimmed) {
            return trimmed
        }

        let edgeCount = max(2, min(6, gains.count / 4))
        let lowAverage = gains.prefix(edgeCount).reduce(0, +) / Float(edgeCount)
        let highAverage = gains.suffix(edgeCount).reduce(0, +) / Float(edgeCount)
        let preferredNames: [String]
        switch tuningProfile {
        case .standard:
            if lowAverage - highAverage > 0.8 {
                preferredNames = ["沉潮", "暗涌", "深湾", "玄浪", "厚土", "潜流", "暮鼓", "低吟"]
            } else if highAverage - lowAverage > 0.8 {
                preferredNames = ["清辉", "晨星", "霁光", "银弦", "晴岚", "星芒", "初霁", "月白"]
            } else if features.dynamicSpreadDB >= 11 {
                preferredNames = ["奔流", "跃浪", "疾风", "燃点", "潮汐", "飞驰", "破晓", "脉动"]
            } else if features.rmsDBFS <= -20 {
                preferredNames = ["轻雾", "微醺", "暮云", "静月", "薄暮", "余温", "绒夜", "夜雨"]
            } else if features.spectralFlatness >= 0.58 {
                preferredNames = ["墨影", "暗纹", "凝夜", "黑曜", "深墨", "静帧", "暮影", "素弦"]
            } else {
                preferredNames = ["和风", "素月", "晴川", "松间", "微光", "静流", "青岚", "凝露"]
            }
        case .monoSpatialEnhancement:
            if spatial.surroundLevel >= 0.16 || spatial.stereoWidth >= 1.12 {
                preferredNames = ["远岫", "长空", "云境", "旷野", "天际", "浮屿", "星野", "风岸"]
            } else if spatial.reverbLevel >= 0.07 {
                preferredNames = ["雾港", "回廊", "月湾", "暮野", "深巷", "静海", "星港", "浮光"]
            } else {
                preferredNames = ["微岚", "远汀", "薄云", "风廊", "晴空", "星径", "云隙", "潮岸"]
            }
        }

        return fallbackProfileName(
            preferredNames: preferredNames,
            features: features,
            tuningProfile: tuningProfile,
            avoiding: recentNames
        )
    }

    private static func fallbackProfileName(
        preferredNames: [String],
        features: AIEqualizerAudioFeatures,
        tuningProfile: AIEqualizerTuningProfile,
        avoiding recentNames: Set<String>
    ) -> String {
        let profileNames: [String]
        switch tuningProfile {
        case .standard:
            profileNames = [
                "沉潮", "暗涌", "清辉", "晨星", "霁光", "晴岚", "奔流", "潮汐",
                "破晓", "轻雾", "暮云", "静月", "墨影", "暗纹", "黑曜", "和风",
                "素月", "晴川", "松间", "静流", "青岚", "凝露", "素弦", "银弦"
            ]
        case .monoSpatialEnhancement:
            profileNames = [
                "远岫", "长空", "云境", "旷野", "天际", "浮屿", "星野", "风岸",
                "雾港", "回廊", "月湾", "暮野", "深巷", "静海", "星港", "浮光",
                "微岚", "远汀", "薄云", "风廊", "晴空", "星径", "云隙", "潮岸"
            ]
        }
        let allNames = preferredNames + profileNames.filter { !preferredNames.contains($0) }
        let seedText = "\(tuningProfile.rawValue)|\(features.source)|\(features.songID)|\(features.title)|\(features.artist)"
        let seed = seedText.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        let startIndex = Int(seed % UInt64(allNames.count))

        for offset in allNames.indices {
            let candidate = allNames[(startIndex + offset) % allNames.count]
            if !recentNames.contains(candidate) { return candidate }
        }
        return allNames[startIndex]
    }

    private static func isValidListeningProfileName(_ value: String) -> Bool {
        guard isPrimarilyChinese(value) else { return false }

        let hanCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                count += 1
            default:
                break
            }
        }
        guard (2...4).contains(hanCount),
              hanCount == value.unicodeScalars.count,
              value.count <= 4 else {
            return false
        }

        let forbiddenTerms = [
            "内置", "扬声器", "外放", "耳机", "蓝牙", "有线", "音箱", "音响",
            "车载", "汽车", "手机", "平板", "电脑", "设备", "输出", "连接",
            "USB", "AirPlay", "AirPods", "iPhone", "iPad", "Mac",
            "清晰", "通透", "平衡", "增强", "优化", "调音", "音效", "模式",
            "方案", "校准", "空间", "动态", "低频", "高频", "人声", "音色",
            "声场", "质感", "层次", "沉浸", "自然", "明亮", "饱满", "细腻", "顺滑"
        ]
        return !forbiddenTerms.contains { term in
            value.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func localizedSummary(
        _ value: String,
        tuningProfile: AIEqualizerTuningProfile
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = isPrimarilyChinese(trimmed) ? trimmed : tuningProfile.summaryFallback
        return "\(base)\n\(tuningProfile.summaryFocus)"
    }

    private static func localizedReference(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 48,
              isPrimarilyChinese(trimmed) else { return nil }
        return trimmed
    }

    private static func isPrimarilyChinese(_ value: String) -> Bool {
        let hanCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                count += 1
            default:
                break
            }
        }
        let latinCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                count += 1
            }
        }
        return hanCount >= 2 && latinCount <= max(2, hanCount / 2)
    }

    private static func validatedProfessional(
        _ value: AIEqualizerProfessionalConfiguration?,
        features: AIEqualizerAudioFeatures,
        intensity: AIEqualizerTuningIntensity
    ) -> AIEqualizerProfessionalConfiguration {
        let dynamicBandLimit = features.graphicEQMode == .thirtyTwoBand ? 3 : 4
        let parametricBandLimit = features.graphicEQMode == .thirtyTwoBand ? 3 : 6
        let dynamicSource = Array(value?.dynamicEQ.bands.prefix(dynamicBandLimit) ?? [])
        let dynamicBands = dynamicSource.map {
            AIEqualizerDynamicBandConfiguration(
                frequency: clampedFinite($0.frequency, fallback: 1_000, range: 20...20_000),
                q: clampedFinite($0.q, fallback: 1, range: 0.15...12),
                thresholdDB: clampedFinite($0.thresholdDB, fallback: -18, range: -60...0),
                ratio: clampedFinite(
                    $0.ratio,
                    fallback: 1.5,
                    range: 1...intensity.dynamicRatioMaximum
                ),
                maxReductionDB: clampedFinite(
                    $0.maxReductionDB,
                    fallback: 2,
                    range: 0...intensity.dynamicReductionMaximum
                ),
                attackMS: clampedFinite($0.attackMS, fallback: 20, range: 0.5...200),
                releaseMS: clampedFinite($0.releaseMS, fallback: 180, range: 15...1_000)
            )
        }

        let multibandSource = value?.multiband
        // Missing or empty professional output is neutral. Earlier versions
        // silently enabled a generic three-band dynamic EQ, which could add
        // processing without track-specific evidence.
        let dynamicEnabled = value?.dynamicEQ.enabled == true && !dynamicBands.isEmpty
        let multibandEnabled = (multibandSource?.enabled ?? false) && !dynamicEnabled
        let multiband = AIEqualizerMultibandConfiguration(
            enabled: multibandEnabled,
            lowCrossoverHz: clampedFinite(multibandSource?.lowCrossoverHz, fallback: 180, range: 60...600),
            highCrossoverHz: clampedFinite(multibandSource?.highCrossoverHz, fallback: 3_800, range: 1_200...10_000),
            thresholdsDB: normalizedTriplet(multibandSource?.thresholdsDB, fallback: [-13, -11, -15], range: -36 ... -4),
            ratios: normalizedTriplet(
                multibandSource?.ratios,
                fallback: [1.45, 1.28, 1.5],
                range: 1...min(6, intensity.dynamicRatioMaximum)
            ),
            maxReductionDB: normalizedTriplet(
                multibandSource?.maxReductionDB,
                fallback: [2.2, 1.5, 2],
                range: 0...intensity.dynamicReductionMaximum
            ),
            attackMS: clampedFinite(multibandSource?.attackMS, fallback: 22, range: 0.5...200),
            releaseMS: clampedFinite(multibandSource?.releaseMS, fallback: 210, range: 15...1_000)
        )

        let supportedTypes = Set(["peak", "lowShelf", "highShelf", "lowPass", "highPass", "notch"])
        let parametricSource = Array(value?.parametricEQ.bands.prefix(parametricBandLimit) ?? [])
        let parametricBands = parametricSource.map {
            AIEqualizerParametricBandConfiguration(
                type: supportedTypes.contains($0.type) ? $0.type : "peak",
                frequency: clampedFinite($0.frequency, fallback: 1_000, range: 20...20_000),
                gainDB: clampedFinite(
                    $0.gainDB,
                    fallback: 0,
                    range: -min(12, intensity.graphicGainRange.upperBound)...min(12, intensity.graphicGainRange.upperBound)
                ),
                q: clampedFinite($0.q, fallback: 1, range: 0.1...12)
            )
        }

        return AIEqualizerProfessionalConfiguration(
            processingIntensity: clampedFinite(
                value?.processingIntensity,
                fallback: intensity.defaultProcessingIntensity,
                range: intensity.processingIntensityRange
            ),
            dynamicEQ: AIEqualizerDynamicEQConfiguration(
                enabled: dynamicEnabled,
                bands: dynamicBands
            ),
            multiband: multiband,
            parametricEQ: AIEqualizerParametricEQConfiguration(
                enabled: (value?.parametricEQ.enabled ?? !parametricBands.isEmpty)
                    && !parametricBands.isEmpty,
                bands: parametricBands
            )
        )
    }

    private static func normalizedTriplet(
        _ values: [Float]?,
        fallback: [Float],
        range: ClosedRange<Float>
    ) -> [Float] {
        guard let values, values.count == 3 else { return fallback }
        return zip(values, fallback).map {
            clampedFinite($0.0, fallback: $0.1, range: range)
        }
    }

    private static func clampedFinite(
        _ value: Float?,
        fallback: Float,
        range: ClosedRange<Float>
    ) -> Float {
        guard let value, value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// A persisted AI tuning result. The cache key is intentionally separate from
/// this record: one song can keep multiple generations for comparison while
/// the cache still selects the best exact match for the current settings.
struct AIEqualizerSavedProposal: Identifiable, Codable, Equatable, Sendable {
    let proposal: AIEqualizerProposal
    let songIdentifier: String
    let outputIdentity: String

    var id: UUID { proposal.id }
}

enum AIEqualizerSamplingMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case fast
    case deep
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return String(localized: "ai_sampling_smart")
        case .fast: return String(localized: "ai_sampling_fast")
        case .deep: return String(localized: "ai_sampling_deep")
        case .custom: return String(localized: "ai_sampling_custom")
        }
    }
}

enum AIEqualizerSamplingStage: String, Equatable, Sendable {
    case preparing
    case waitingForAudio
    case collectingSpectrum
    case measuringDynamics
    case organizingFeatures
    case finalizing

    var title: String {
        switch self {
        case .preparing: return String(localized: "ai_sampling_stage_preparing")
        case .waitingForAudio: return String(localized: "ai_sampling_stage_waiting")
        case .collectingSpectrum: return String(localized: "ai_sampling_stage_spectrum")
        case .measuringDynamics: return String(localized: "ai_sampling_stage_dynamics")
        case .organizingFeatures: return String(localized: "ai_sampling_stage_features")
        case .finalizing: return String(localized: "ai_sampling_stage_finalizing")
        }
    }
}

enum AIEqualizerGenerationStage: String, Equatable, Sendable {
    case preparing
    case preparingModel
    case generating
    case validating
    case finalizing

    var title: String {
        switch self {
        case .preparing: return String(localized: "ai_generation_stage_preparing")
        case .preparingModel: return String(localized: "ai_resonance_preparing_model")
        case .generating: return String(localized: "ai_generation_stage_generating")
        case .validating: return String(localized: "ai_generation_stage_validating")
        case .finalizing: return String(localized: "ai_generation_stage_finalizing")
        }
    }
}

enum AIEqualizerAgentPhase: Equatable, Sendable {
    case idle
    case sampling(progress: Double)
    case requesting
    case ready
    case applying
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .sampling, .requesting, .applying: return true
        default: return false
        }
    }
}

enum AIEqualizerError: LocalizedError {
    case noSong
    case playbackRequired
    case sampleUnavailable
    case protectedAudioUnsupported
    case invalidEndpoint
    case missingAPIKey
    case modelUnavailable
    case invalidResponse
    case dailyLimitReached(Int)
    case hourlyLimitReached(Int)
    case requestFrequencyLimited(Int)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .noSong: return String(localized: "ai_error_no_song")
        case .playbackRequired: return String(localized: "ai_error_playback_required")
        case .sampleUnavailable: return String(localized: "ai_error_sample_unavailable")
        case .protectedAudioUnsupported:
            return String(localized: "ai_error_protected_audio_unsupported")
        case .invalidEndpoint: return String(localized: "ai_error_invalid_endpoint")
        case .missingAPIKey: return String(localized: "ai_error_missing_key")
        case .modelUnavailable: return String(localized: "ai_error_model_unavailable")
        case .invalidResponse: return String(localized: "ai_error_invalid_response")
        case let .dailyLimitReached(limit):
            return String(format: String(localized: "ai_error_daily_limit"), limit)
        case let .hourlyLimitReached(limit):
            return String(format: String(localized: "ai_error_hourly_limit"), limit)
        case let .requestFrequencyLimited(seconds):
            return String(format: String(localized: "ai_error_frequency_limit"), seconds)
        case let .httpStatus(code, message):
            return message.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(message)"
        }
    }
}
