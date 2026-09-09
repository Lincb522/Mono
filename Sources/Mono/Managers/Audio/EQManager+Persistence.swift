import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

extension EQManager {
    // MARK: - 持久化
    
    struct EQState: Codable {
        let isEnabled: Bool
        let currentPresetId: String?
        let transientPreset: EQPreset?
        let customGains: [Float]
        let customPresets: [EQPreset]
        let graphicEQMode: GraphicEQMode?
        let tenBandCustomGains: [Float]?
        let thirtyTwoBandCustomGains: [Float]?
    }
    
    /// 音效旋钮状态（独立于 EQ）
    struct AudioEffectsState: Codable {
        let bassGain: Float
        let trebleGain: Float
        let surroundLevel: Float
        let reverbLevel: Float
        let stereoWidth: Float?
    }

    struct ProfessionalState: Codable {
        /// 可选字段用于兼容没有处理强度的旧版专业模式状态。
        let professionalProcessingIntensity: Float?
        let isLoudnessMatchingEnabled: Bool
        let isOutputCalibrationEnabled: Bool
        let isSmartSongCompensationEnabled: Bool
        let isDynamicEQEnabled: Bool
        let isMultibandDynamicsEnabled: Bool
        let isParametricEQEnabled: Bool
        let parametricBands: [ParametricEQBand]
        let dynamicEQBands: [DynamicEQBand]
        let multibandConfiguration: MultibandDynamicsConfiguration
        let monoEffectTuning: MonoEffectTuningConfiguration?
        let monoEnhanceConfiguration: MonoEnhanceConfiguration?
        let customPresetPreampDB: Float
        let selectedHeadphoneProfileID: String
        let headphoneProfiles: [MonoHeadphoneCorrectionProfile]
        let presetPreampOverrides: [String: Float]
        let isHearingCorrectionEnabled: Bool?
        let hearingLeftGains: [Float]?
        let hearingRightGains: [Float]?
        let isEnvironmentCompensationEnabled: Bool?
        let environmentCompensationGains: [Float]?
    }

    struct AIProcessingSnapshot: Codable {
        let isEnabled: Bool
        let currentPreset: EQPreset?
        let customGains: [Float]
        let graphicEQMode: GraphicEQMode?
        let tenBandCustomGains: [Float]?
        let thirtyTwoBandCustomGains: [Float]?
        let customPresetPreampDB: Float
        let professionalProcessingIntensity: Float
        let isLoudnessMatchingEnabled: Bool
        let isOutputCalibrationEnabled: Bool
        let isSmartSongCompensationEnabled: Bool
        let isDynamicEQEnabled: Bool
        let dynamicEQBands: [DynamicEQBand]
        let isMultibandDynamicsEnabled: Bool
        let multibandConfiguration: MultibandDynamicsConfiguration
        let isParametricEQEnabled: Bool
        let parametricBands: [ParametricEQBand]
        let monoEffectTuning: MonoEffectTuningConfiguration?
        let monoEnhanceConfiguration: MonoEnhanceConfiguration?
        let bassGain: Float
        let trebleGain: Float
        let surroundLevel: Float
        let reverbLevel: Float
        let stereoWidth: Float
    }
    
    static let eqStateKey = "mono_eq_state_v5"
    static let audioEffectsStateKey = "mono_audio_effects_state"
    static let professionalStateKey = "mono_eq_professional_state_v1"
    static let aiProcessingSnapshotKey = "mono_eq_ai_processing_snapshot_v1"

    func captureProcessingBeforeAIIfNeeded() {
        guard preAIProcessingSnapshot == nil, !isAIManagedPresetActive else { return }
        let snapshot = currentAIProcessingSnapshot()
        preAIProcessingSnapshot = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.aiProcessingSnapshotKey)
        }
    }

    func currentAIProcessingSnapshot() -> AIProcessingSnapshot {
        let effects = PlayerManager.shared.audioEffects
        return AIProcessingSnapshot(
            isEnabled: isEnabled,
            currentPreset: currentPreset,
            customGains: customGains,
            graphicEQMode: graphicEQMode,
            tenBandCustomGains: tenBandCustomGains,
            thirtyTwoBandCustomGains: thirtyTwoBandCustomGains,
            customPresetPreampDB: customPresetPreampDB,
            professionalProcessingIntensity: professionalProcessingIntensity,
            isLoudnessMatchingEnabled: isLoudnessMatchingEnabled,
            isOutputCalibrationEnabled: isOutputCalibrationEnabled,
            isSmartSongCompensationEnabled: isSmartSongCompensationEnabled,
            isDynamicEQEnabled: isDynamicEQEnabled,
            dynamicEQBands: dynamicEQBands,
            isMultibandDynamicsEnabled: isMultibandDynamicsEnabled,
            multibandConfiguration: multibandConfiguration,
            isParametricEQEnabled: isParametricEQEnabled,
            parametricBands: parametricBands,
            monoEffectTuning: monoEffectTuning,
            monoEnhanceConfiguration: monoEnhanceConfiguration,
            bassGain: effects.bassGain,
            trebleGain: effects.trebleGain,
            surroundLevel: effects.surroundLevel,
            reverbLevel: effects.reverbLevel,
            stereoWidth: effects.stereoWidth
        )
    }

    struct DSPDiagnosticSnapshot: Encodable {
        let configured: AIProcessingSnapshot
        let sdkGraphicMode: String
        let sdkGraphicGains: [Float]
        let sdkProcessingEnabled: Bool
        let sdkEnhance: MonoEnhanceConfiguration
        let outputGainDB: Float
        let perceptualMakeupDB: Float
    }

    func currentDSPDiagnosticSnapshot() -> DSPDiagnosticSnapshot {
        let player = PlayerManager.shared
        return DSPDiagnosticSnapshot(
            configured: currentAIProcessingSnapshot(),
            sdkGraphicMode: player.equalizer.graphicMode.rawValue,
            sdkGraphicGains: player.equalizer.graphicGains,
            sdkProcessingEnabled: player.equalizer.isProcessingEnabled,
            sdkEnhance: player.equalizer.monoEnhanceConfiguration,
            outputGainDB: player.audioRepair.outputGainDB,
            perceptualMakeupDB: player.audioRepair.perceptualMakeupDB
        )
    }

    func restoreAIProcessingSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.aiProcessingSnapshotKey),
              let snapshot = try? JSONDecoder().decode(AIProcessingSnapshot.self, from: data) else {
            return
        }
        preAIProcessingSnapshot = snapshot
    }

    func neutralAIProcessingSnapshot() -> AIProcessingSnapshot {
        AIProcessingSnapshot(
            isEnabled: true,
            currentPreset: builtInPreset(familyID: "flat", mode: .tenBand),
            customGains: Array(repeating: 0, count: 10),
            graphicEQMode: .tenBand,
            tenBandCustomGains: Array(repeating: 0, count: GraphicEQMode.tenBand.bandCount),
            thirtyTwoBandCustomGains: Array(repeating: 0, count: GraphicEQMode.thirtyTwoBand.bandCount),
            customPresetPreampDB: 0,
            professionalProcessingIntensity: 1,
            isLoudnessMatchingEnabled: false,
            isOutputCalibrationEnabled: false,
            isSmartSongCompensationEnabled: false,
            isDynamicEQEnabled: false,
            dynamicEQBands: DynamicEQBand.monoDefaults,
            isMultibandDynamicsEnabled: false,
            multibandConfiguration: MultibandDynamicsConfiguration(isEnabled: false),
            isParametricEQEnabled: false,
            parametricBands: [],
            monoEffectTuning: .neutral,
            monoEnhanceConfiguration: .neutral,
            bassGain: 0,
            trebleGain: 0,
            surroundLevel: 0,
            reverbLevel: 0,
            stereoWidth: 1
        )
    }
    
    func saveState() {
        let isTransientPreset = currentPreset?.id == "custom"
            || currentPreset?.id.hasPrefix("ai_") == true
        let state = EQState(
            isEnabled: isEnabled,
            currentPresetId: currentPreset?.id,
            transientPreset: isTransientPreset ? currentPreset : nil,
            customGains: customGains,
            customPresets: customPresets,
            graphicEQMode: graphicEQMode,
            tenBandCustomGains: tenBandCustomGains,
            thirtyTwoBandCustomGains: thirtyTwoBandCustomGains
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.eqStateKey)
        }
    }

    func saveProfessionalState() {
        guard !isRestoring else { return }
        let state = ProfessionalState(
            professionalProcessingIntensity: professionalProcessingIntensity,
            isLoudnessMatchingEnabled: isLoudnessMatchingEnabled,
            isOutputCalibrationEnabled: isOutputCalibrationEnabled,
            isSmartSongCompensationEnabled: isSmartSongCompensationEnabled,
            isDynamicEQEnabled: isDynamicEQEnabled,
            isMultibandDynamicsEnabled: isMultibandDynamicsEnabled,
            isParametricEQEnabled: isParametricEQEnabled,
            parametricBands: parametricBands,
            dynamicEQBands: dynamicEQBands,
            multibandConfiguration: multibandConfiguration,
            monoEffectTuning: monoEffectTuning,
            monoEnhanceConfiguration: monoEnhanceConfiguration,
            customPresetPreampDB: customPresetPreampDB,
            selectedHeadphoneProfileID: selectedHeadphoneProfileID,
            headphoneProfiles: headphoneProfiles,
            presetPreampOverrides: presetPreampOverrides,
            isHearingCorrectionEnabled: isHearingCorrectionEnabled,
            hearingLeftGains: hearingLeftGains,
            hearingRightGains: hearingRightGains,
            isEnvironmentCompensationEnabled: isEnvironmentCompensationEnabled,
            environmentCompensationGains: environmentCompensationGains
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.professionalStateKey)
        }
    }

    func restoreProfessionalState() {
        guard let data = UserDefaults.standard.data(forKey: Self.professionalStateKey),
              let state = try? JSONDecoder().decode(ProfessionalState.self, from: data)
        else { return }
        professionalProcessingIntensity = Self.clampedProfessionalIntensity(
            state.professionalProcessingIntensity ?? 1.3
        )
        isLoudnessMatchingEnabled = state.isLoudnessMatchingEnabled
        isOutputCalibrationEnabled = state.isOutputCalibrationEnabled
        isSmartSongCompensationEnabled = state.isSmartSongCompensationEnabled
        isDynamicEQEnabled = state.isDynamicEQEnabled
        isMultibandDynamicsEnabled = state.isMultibandDynamicsEnabled
        isParametricEQEnabled = state.isParametricEQEnabled
        parametricBands = state.parametricBands
        dynamicEQBands = state.dynamicEQBands
        multibandConfiguration = state.multibandConfiguration
        monoEffectTuning = state.monoEffectTuning ?? .neutral
        monoEnhanceConfiguration = state.monoEnhanceConfiguration ?? .neutral
        customPresetPreampDB = Self.clampedPreamp(state.customPresetPreampDB)
        selectedHeadphoneProfileID = state.selectedHeadphoneProfileID
        headphoneProfiles = state.headphoneProfiles
        presetPreampOverrides = state.presetPreampOverrides
        isHearingCorrectionEnabled = state.isHearingCorrectionEnabled ?? false
        hearingLeftGains = GraphicEQMode.tenBand.normalizedGains(
            state.hearingLeftGains ?? Array(repeating: 0, count: 10)
        )
        hearingRightGains = GraphicEQMode.tenBand.normalizedGains(
            state.hearingRightGains ?? Array(repeating: 0, count: 10)
        )
        isEnvironmentCompensationEnabled = state.isEnvironmentCompensationEnabled ?? false
        environmentCompensationGains = GraphicEQMode.tenBand.normalizedGains(
            state.environmentCompensationGains ?? Array(repeating: 0, count: 10)
        ).map { min(0, max(-3, $0)) }
    }
    
    /// 保存音效旋钮状态（低音/高音/环绕/混响，独立于 EQ）
    func saveAudioEffectsState() {
        let effects = PlayerManager.shared.audioEffects
        let state = referenceEffectSnapshot ?? AudioEffectsState(
            bassGain: effects.bassGain,
            trebleGain: effects.trebleGain,
            surroundLevel: effects.surroundLevel,
            reverbLevel: effects.reverbLevel,
            stereoWidth: effects.stereoWidth
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.audioEffectsStateKey)
        }
    }
    
    func restoreAudioEffectsState() {
        guard let data = UserDefaults.standard.data(forKey: Self.audioEffectsStateKey),
              let state = try? JSONDecoder().decode(AudioEffectsState.self, from: data) else {
            // 兼容：尝试从旧的缓存系统迁移
            if let state = OptimizedCacheManager.shared.getObject(forKey: "audio_effects_state", type: AudioEffectsState.self) {
                let effects = PlayerManager.shared.audioEffects
                effects.applyMonoTuning(
                    monoEffectTuning,
                    bassGain: state.bassGain,
                    trebleGain: state.trebleGain,
                    surroundLevel: state.surroundLevel,
                    reverbLevel: state.reverbLevel,
                    stereoWidth: state.stereoWidth ?? 1
                )
                saveAudioEffectsState()
            }
            return
        }
        let effects = PlayerManager.shared.audioEffects
        effects.applyMonoTuning(
            monoEffectTuning,
            bassGain: state.bassGain,
            trebleGain: state.trebleGain,
            surroundLevel: state.surroundLevel,
            reverbLevel: state.reverbLevel,
            stereoWidth: state.stereoWidth ?? 1
        )
    }
    
    func restoreState() {
        restoreAudioEffectsState()
        
        // v5: 从 UserDefaults 恢复
        if let data = UserDefaults.standard.data(forKey: Self.eqStateKey),
           let state = try? JSONDecoder().decode(EQState.self, from: data) {
            self.customPresets = state.customPresets
            let restoredMode = state.graphicEQMode
                ?? (state.customGains.count == GraphicEQMode.thirtyTwoBand.bandCount ? .thirtyTwoBand : .tenBand)
            self.graphicEQMode = restoredMode
            self.tenBandCustomGains = GraphicEQMode.tenBand.normalizedGains(
                state.tenBandCustomGains ?? (restoredMode == .tenBand ? state.customGains : [])
            )
            self.thirtyTwoBandCustomGains = GraphicEQMode.thirtyTwoBand.normalizedGains(
                state.thirtyTwoBandCustomGains ?? (restoredMode == .thirtyTwoBand ? state.customGains : [])
            )
            self.customGains = restoredMode == .tenBand ? tenBandCustomGains : thirtyTwoBandCustomGains
            self.isEnabled = state.isEnabled
            if let presetId = state.currentPresetId {
                self.currentPreset = allPresets.first { $0.id == presetId }
                    ?? (state.transientPreset?.id == presetId ? state.transientPreset : nil)
            }
            self.currentPreset = matchingBuiltInPreset(currentPreset, mode: restoredMode)
            if isEnabled {
                if let preset = currentPreset {
                    applyPresetCurve(preset)
                } else {
                    applyCustomGains()
                }
            } else {
                PlayerManager.shared.equalizer.setGraphicMode(graphicEQMode, gainsDB: customGains)
            }
            updateSafetyLimiter()
            return
        }
        
        // 兼容：从旧的缓存系统迁移（v4 及更早版本）
        if let state = OptimizedCacheManager.shared.getObject(forKey: "eq_state_v4", type: EQState.self) {
            self.customPresets = state.customPresets
            let restoredMode = state.graphicEQMode
                ?? (state.customGains.count == GraphicEQMode.thirtyTwoBand.bandCount ? .thirtyTwoBand : .tenBand)
            self.graphicEQMode = restoredMode
            self.tenBandCustomGains = GraphicEQMode.tenBand.normalizedGains(
                state.tenBandCustomGains ?? (restoredMode == .tenBand ? state.customGains : [])
            )
            self.thirtyTwoBandCustomGains = GraphicEQMode.thirtyTwoBand.normalizedGains(
                state.thirtyTwoBandCustomGains ?? (restoredMode == .thirtyTwoBand ? state.customGains : [])
            )
            self.customGains = restoredMode == .tenBand ? tenBandCustomGains : thirtyTwoBandCustomGains
            self.isEnabled = state.isEnabled
            if let presetId = state.currentPresetId {
                self.currentPreset = allPresets.first { $0.id == presetId }
                    ?? (state.transientPreset?.id == presetId ? state.transientPreset : nil)
            }
            self.currentPreset = matchingBuiltInPreset(currentPreset, mode: restoredMode)
            if isEnabled {
                if let preset = currentPreset {
                    applyPresetCurve(preset)
                } else {
                    applyCustomGains()
                }
            } else {
                PlayerManager.shared.equalizer.setGraphicMode(graphicEQMode, gainsDB: customGains)
            }
            updateSafetyLimiter()
            saveState()
            return
        }
        
        struct LegacyEQState: Codable {
            let isEnabled: Bool
            let currentPresetId: String?
            let customGains: [Float]
            let customPresets: [EQPreset]
            let eqMode: String?
            let superEQGains: [Float]?
            let currentSuperEQPresetId: String?
        }
        for key in ["eq_state_v3", "eq_state_v2", "eq_state_v1"] {
            if let state = OptimizedCacheManager.shared.getObject(forKey: key, type: LegacyEQState.self) {
                self.customPresets = state.customPresets.filter { $0.presetType == .standard10 }
                self.graphicEQMode = .tenBand
                self.tenBandCustomGains = GraphicEQMode.tenBand.normalizedGains(state.customGains)
                self.thirtyTwoBandCustomGains = Array(repeating: 0, count: GraphicEQMode.thirtyTwoBand.bandCount)
                self.customGains = tenBandCustomGains
                self.isEnabled = state.isEnabled
                if let presetId = state.currentPresetId {
                    self.currentPreset = allPresets.first { $0.id == presetId }
                }
                if isEnabled, let preset = currentPreset {
                    applyPresetCurve(preset)
                }
                updateSafetyLimiter()
                saveState()
                return
            }
        }
    }
}
