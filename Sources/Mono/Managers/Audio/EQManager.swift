// 均衡器管理器：预设管理、状态持久化、实时应用
// 所有预设参数基于专业音频工程标准

import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

@MainActor
class EQManager: ObservableObject {
    static let shared = EQManager()
    
    /// 恢复状态时跳过 didSet 副作用
    var isRestoring = false
    
    /// 当前前级补偿值 (dB)，由安全系统自动管理
    @Published var preampDB: Float = 0
    @Published var currentOutputKind: MonoAudioOutputKind = .other
    @Published var currentOutputName: String = ""
    @Published var adaptiveGains: [Float] = Array(repeating: 0, count: 10)
    @Published var isAuditioningReference = false
    var referenceEffectSnapshot: AudioEffectsState?
    @Published var trackLoudnessGainDB: Float = 0
    @Published var isHearingCorrectionEnabled = false
    @Published var hearingLeftGains: [Float] = Array(repeating: 0, count: 10)
    @Published var hearingRightGains: [Float] = Array(repeating: 0, count: 10)
    @Published var isEnvironmentCompensationEnabled = false
    @Published var environmentCompensationGains: [Float] = Array(repeating: 0, count: 10)

    /// 专业处理总强度。1.0 保留原始参数，默认略加强以便在移动设备上保持可感知。
    @Published var professionalProcessingIntensity: Float = 1.3 {
        didSet {
            // Restore/AI apply may write persisted values. Do not clamp by assigning
            // back from didSet while restoring; that can recursively re-enter the
            // @Published setter when the stored value is malformed.
            guard !isRestoring else { return }
            let clamped = Self.clampedProfessionalIntensity(professionalProcessingIntensity)
            if abs(clamped - professionalProcessingIntensity) > 0.001 {
                professionalProcessingIntensity = clamped
                return
            }
            applyProfessionalConfiguration()
            saveProfessionalState()
        }
    }

    @Published var isLoudnessMatchingEnabled = true {
        didSet { headroomSettingChanged() }
    }
    @Published var isOutputCalibrationEnabled = true {
        didSet { calibrationSettingChanged() }
    }
    @Published var isSmartSongCompensationEnabled = true {
        didSet {
            guard !isRestoring else { return }
            configureSmartAnalysis()
            if !isSmartSongCompensationEnabled {
                resetSmartCompensation()
            }
            saveProfessionalState()
        }
    }
    @Published var isDynamicEQEnabled = true {
        didSet { dynamicEQSettingChanged() }
    }
    @Published var isMultibandDynamicsEnabled = true {
        didSet { multibandSettingChanged() }
    }
    @Published var isParametricEQEnabled = false {
        didSet { parametricSettingChanged() }
    }
    @Published var parametricBands: [ParametricEQBand] = [] {
        didSet { parametricSettingChanged() }
    }
    @Published var dynamicEQBands: [DynamicEQBand] = DynamicEQBand.monoDefaults {
        didSet { dynamicEQSettingChanged() }
    }
    @Published var multibandConfiguration = MultibandDynamicsConfiguration(isEnabled: true) {
        didSet { multibandSettingChanged() }
    }
    @Published var monoEffectTuning = MonoEffectTuningConfiguration.neutral {
        didSet { monoEffectTuningChanged() }
    }
    var monoEnhanceConfiguration = MonoEnhanceConfiguration.neutral
    @Published var customPresetPreampDB: Float = 0 {
        didSet {
            // Keep this guard before the corrective assignment. The previous order
            // could recurse indefinitely while restoring an out-of-range value.
            guard !isRestoring else { return }
            let clamped = Self.clampedPreamp(customPresetPreampDB)
            if abs(clamped - customPresetPreampDB) > 0.001 {
                customPresetPreampDB = clamped
                return
            }
            headroomSettingChanged()
        }
    }
    @Published var presetPreampOverrides: [String: Float] = [:] {
        didSet { headroomSettingChanged() }
    }
    @Published var selectedHeadphoneProfileID: String = "off" {
        didSet { calibrationSettingChanged() }
    }
    @Published var headphoneProfiles: [MonoHeadphoneCorrectionProfile] = [] {
        didSet { calibrationSettingChanged() }
    }

    var currentOutputUID: String = ""
    var smartSpectrumAverage = Array(repeating: Float(0), count: 10)
    var smartSpectrumFrames = 0
    var smartSongIdentifier: String?
    var lastSmartUpdate = Date.distantPast
    var lastSmartDSPCommit = Date.distantPast
    var committedAdaptiveGains = Array(repeating: Float(0), count: 10)
    var isSafetyLimiterActive = false
    var preAIProcessingSnapshot: AIProcessingSnapshot?
    let userGraphicGainAdjustmentSubject = PassthroughSubject<
        EQGraphicGainUserAdjustment,
        Never
    >()

    var userGraphicGainAdjustments: AnyPublisher<EQGraphicGainUserAdjustment, Never> {
        userGraphicGainAdjustmentSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Published
    
    @Published var isEnabled: Bool = false {
        didSet {
            guard !isRestoring else { return }
            if !isEnabled {
                isAuditioningReference = false
                referenceEffectSnapshot = nil
                PlayerManager.shared.equalizer.setProcessingEnabled(false)
                PlayerManager.shared.equalizer.reset()
                PlayerManager.shared.audioEffects.applyMonoTuning(
                    .neutral,
                    bassGain: 0,
                    trebleGain: 0,
                    surroundLevel: 0,
                    reverbLevel: 0,
                    stereoWidth: 1
                )
                PlayerManager.shared.setPitch(0)
                disableSafetyMeasures()
                saveAudioEffectsState()
            } else {
                PlayerManager.shared.equalizer.setProcessingEnabled(true)
                if let preset = currentPreset {
                    applyPresetCurve(preset)
                } else if customGains.contains(where: { abs($0) > 0.001 }) {
                    applyCustomGains()
                } else {
                    PlayerManager.shared.equalizer.setGraphicMode(graphicEQMode, gainsDB: customGains)
                }
                applyProfessionalConfiguration()
                applyMonoEffectTuning()
                updateSafetyLimiter()
            }
            configureSmartAnalysis()
            saveState()
        }
    }
    
    @Published var currentPreset: EQPreset? = nil {
        didSet {
            guard !isRestoring else { return }
            stopLoudnessMatchedReferenceAudition()
            if isEnabled, let preset = currentPreset {
                applyPresetCurve(preset)
                applyProfessionalConfiguration()
                updateSafetyLimiter()
            }
            saveState()
        }
    }

    /// 10 段为默认规格；32 段是用户主动选择的精细图示均衡器。
    @Published var graphicEQMode: GraphicEQMode = .tenBand
    var tenBandCustomGains = Array(repeating: Float(0), count: GraphicEQMode.tenBand.bandCount)
    var thirtyTwoBandCustomGains = Array(repeating: Float(0), count: GraphicEQMode.thirtyTwoBand.bandCount)
    
    @Published var customGains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            guard !isRestoring else { return }
            if graphicEQMode == .tenBand {
                tenBandCustomGains = graphicEQMode.normalizedGains(customGains)
            } else {
                thirtyTwoBandCustomGains = graphicEQMode.normalizedGains(customGains)
            }
            if isEnabled && currentPreset?.id == "custom" {
                applyCustomGains()
            }
        }
    }
    
    @Published var customPresets: [EQPreset] = []
    
    // MARK: - 内置预设
    //
    // 预设参数说明：
    // 10 段频率: 31Hz, 62Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    // 增益范围: -12dB ~ +12dB
    //
    // 参数设计依据：
    // - 低频 (31-125Hz): 控制低音体感和温暖度
    // - 中低频 (250-500Hz): 控制浑浊感和饱满度，过多会闷
    // - 中频 (1-2kHz): 人声基频和乐器主体
    // - 中高频 (4kHz): 临场感和齿音区域
    // - 高频 (8-16kHz): 空气感和亮度
    
    let builtInPresets: [EQPreset] = EQManager.loadBuiltInPresets()
    
    /// 10 段与 32 段使用两份独立资源，避免运行时把内置预设临时插值。
    static func loadBuiltInPresets() -> [EQPreset] {
        let tenBand = loadPresetResource(named: "eq_presets", fallback: embeddedFallbackPresets)
        let thirtyTwoBand = loadPresetResource(named: "eq_presets_32", fallback: embeddedFallback32Presets)
        return tenBand + thirtyTwoBand
    }

    static func loadPresetResource(named resourceName: String, fallback: [EQPreset]) -> [EQPreset] {
        var candidateURLs: [URL?] = [
            Bundle.main.url(forResource: resourceName, withExtension: "json"),
            Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources")
        ]
#if SWIFT_PACKAGE
        candidateURLs.append(Bundle.module.url(forResource: resourceName, withExtension: "json"))
        candidateURLs.append(Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources"))
#endif
        guard let url = candidateURLs.compactMap({ $0 }).first else {
            AppLogger.warning("[EQManager] Bundle 中未找到 \(resourceName).json")
            return fallback
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let data = FileManager.default.contents(atPath: url.path),
              !data.isEmpty else {
            AppLogger.warning("[EQManager] \(resourceName).json 不存在或为空")
            return fallback
        }
        do {
            let presets = try JSONDecoder().decode([EQPreset].self, from: data)
            AppLogger.debug("[EQManager] 从 \(resourceName).json 加载了 \(presets.count) 个内置预设")
            return presets
        } catch {
            AppLogger.warning("[EQManager] \(resourceName).json 解码失败: \(error)")
            return fallback
        }
    }
    
    /// 内嵌兜底预设（当 JSON 文件无法加载时使用）
    static let embeddedFallbackPresets: [EQPreset] = [
        EQPreset(id: "flat", name: String(localized: "平坦"), category: .flat, description: String(localized: "基准监听曲线，不做任何染色，适合对比和校准听感"), gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preampDB: 0),
        EQPreset(id: "pop", name: String(localized: "流行"), category: .genre, description: String(localized: "低频结实、主唱清楚、高频通透，中频不过度后退"), gains: [0.8, 1.3, 0.8, -0.4, -0.7, -0.2, 0.8, 1.1, 0.8, 0.6], preampDB: -1.7, loudnessCompensationDB: -0.3),
        EQPreset(id: "rock", name: String(localized: "摇滚"), category: .genre, description: String(localized: "收紧浑浊区，强化军鼓、吉他边缘与鼓组冲击"), gains: [0.5, 1.2, 1.0, -0.5, -1.0, 0.2, 1.2, 1.5, 0.7, 0.0], preampDB: -1.9, loudnessCompensationDB: -0.3),
        EQPreset(id: "vocal_enhance", name: String(localized: "人声增强"), category: .vocal, description: String(localized: "削减低频遮挡，集中提升 1-4kHz 咬字与存在感"), gains: [-2.0, -1.5, -0.7, -0.4, 0.0, 0.8, 1.6, 1.2, 0.0, -0.5], preampDB: -2.0, loudnessCompensationDB: -0.2),
        EQPreset(id: "bass_boost", name: String(localized: "低音增强"), category: .scene, description: String(localized: "以 62Hz 为核心增加下潜和鼓点重量，同时控制中低频发轰"), gains: [2.4, 2.8, 1.8, 0.3, -0.6, -0.5, -0.3, -0.3, -0.2, -0.2], preampDB: -3.2, loudnessCompensationDB: -0.1),
    ]

    static let embeddedFallback32Presets: [EQPreset] = [
        EQPreset(id: "flat_32", familyID: "flat", name: String(localized: "平坦"), category: .flat, description: String(localized: "基准监听曲线，不做任何染色，适合对比和校准听感"), gains: Array(repeating: 0, count: 32), presetType: .graphic32, preampDB: 0),
        EQPreset(id: "pop_32", familyID: "pop", name: String(localized: "流行"), category: .genre, description: String(localized: "低频结实、主唱清楚、高频通透，中频不过度后退"), gains: [0.55, 0.55, 0.5, 0.45, 0.55, 0.9, 1.15, 0.9, 0.75, 0.8, 0.45, -0.05, -0.3, -0.3, -0.45, -0.6, -0.4, -0.2, -0.15, 0.05, 0.45, 0.75, 0.65, 0.8, 1.1, 0.85, 0.75, 0.85, 0.55, 0.35, 0.5, 0.8], presetType: .graphic32, preampDB: -2, loudnessCompensationDB: -0.3),
        EQPreset(id: "rock_32", familyID: "rock", name: String(localized: "摇滚"), category: .genre, description: String(localized: "收紧浑浊区，强化军鼓、吉他边缘与鼓组冲击"), gains: [0.35, 0.35, 0.35, 0.35, 0.45, 0.8, 1.1, 0.9, 0.8, 0.95, 0.5, -0.05, -0.35, -0.4, -0.6, -0.8, -0.45, -0.05, 0.2, 0.35, 0.75, 1.15, 0.95, 1.1, 1.45, 1.05, 0.8, 0.8, 0.5, 0.2, 0.1, 0], presetType: .graphic32, preampDB: -2.3, loudnessCompensationDB: -0.3),
        EQPreset(id: "vocal_enhance_32", familyID: "vocal_enhance", name: String(localized: "人声增强"), category: .vocal, description: String(localized: "削减低频遮挡，集中提升 1-4kHz 咬字与存在感"), gains: [-1.35, -1.35, -1.15, -0.9, -0.8, -1.05, -1.35, -1.05, -0.8, -0.8, -0.6, -0.4, -0.4, -0.25, -0.05, 0.05, 0.2, 0.5, 0.8, 0.8, 1.1, 1.5, 1.15, 1, 1.2, 0.75, 0.3, 0.15, 0.05, -0.05, -0.35, -0.65], presetType: .graphic32, preampDB: -2.5, loudnessCompensationDB: -0.2),
        EQPreset(id: "bass_boost_32", familyID: "bass_boost", name: String(localized: "低音增强"), category: .scene, description: String(localized: "以 62Hz 为核心增加下潜和鼓点重量，同时控制中低频发轰"), gains: [1.65, 1.65, 1.5, 1.25, 1.25, 1.95, 2.55, 2, 1.7, 1.9, 1.25, 0.6, 0.45, 0.15, -0.2, -0.5, -0.4, -0.4, -0.45, -0.35, -0.3, -0.3, -0.25, -0.25, -0.3, -0.25, -0.2, -0.2, -0.15, -0.1, -0.15, -0.25], presetType: .graphic32, preampDB: -3.9, loudnessCompensationDB: -0.2),
    ]
    
    // MARK: - Init

    static func clampedProfessionalIntensity(_ value: Float) -> Float {
        guard value.isFinite else { return 1.3 }
        return min(max(value, 0.6), 2.1)
    }

    static func clampedPreamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -18), 0)
    }
    
    private init() {
        isRestoring = true
        restoreState()
        restoreProfessionalState()
        restoreAIProcessingSnapshot()
        isRestoring = false
        handleAudioRouteChanged()
        PlayerManager.shared.equalizer.setProcessingEnabled(isEnabled)
        applyProfessionalConfiguration()
        applyMonoEffectTuning()
        configureSmartAnalysis()
        updateSafetyLimiter()
    }
    
    // MARK: - 所有预设（内置 + 自定义）
    
    var allPresets: [EQPreset] {
        builtInPresets + customPresets
    }

    var isAIManagedPresetActive: Bool {
        currentPreset?.id.hasPrefix("ai_") == true
    }

    func isActivelyApplyingAIProposal(_ proposal: AIEqualizerProposal) -> Bool {
        guard isEnabled,
              isAIManagedPresetActive,
              currentPreset?.id == "ai_\(proposal.songID)",
              graphicEQMode == proposal.graphicEQMode else {
            return false
        }
        let equalizer = PlayerManager.shared.equalizer
        guard equalizer.isProcessingEnabled,
              equalizer.monoEnhanceConfiguration.hasAudibleProcessing else {
            return false
        }
        let expected = proposal.graphicEQMode.normalizedGains(proposal.gains)
        let applied = equalizer.graphicGains
        guard expected.count == applied.count else { return false }
        return zip(expected, applied).allSatisfy { abs($0 - $1) < 0.02 }
    }
    
    func presets(for category: EQPresetCategory) -> [EQPreset] {
        if category == .custom {
            return customPresets
        }
        return builtInPresets.filter {
            $0.category == category && $0.presetType.graphicMode == graphicEQMode
        }
    }
    
}
