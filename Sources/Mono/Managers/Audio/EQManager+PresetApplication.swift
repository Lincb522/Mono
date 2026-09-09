import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

extension EQManager {
    // MARK: - 应用预设

    var graphicBandFrequencies: [Float] { graphicEQMode.centerFrequencies }
    var graphicBandLabels: [String] { graphicEQMode.frequencyLabels }

    func builtInPreset(familyID: String, mode: GraphicEQMode) -> EQPreset? {
        builtInPresets.first {
            !$0.isCustom && $0.familyID == familyID && $0.presetType.graphicMode == mode
        }
    }

    func matchingBuiltInPreset(_ preset: EQPreset?, mode: GraphicEQMode) -> EQPreset? {
        guard let preset else { return nil }
        guard !preset.isCustom else { return preset }
        return builtInPreset(familyID: preset.familyID, mode: mode) ?? preset
    }

    func setGraphicEQMode(_ mode: GraphicEQMode) {
        guard mode != graphicEQMode else { return }
        stopLoudnessMatchedReferenceAudition()
        if isAIManagedPresetActive {
            restoreProcessingBeforeAI(reason: "manual-band-mode")
        }

        if graphicEQMode == .tenBand {
            tenBandCustomGains = GraphicEQMode.tenBand.normalizedGains(customGains)
        } else {
            thirtyTwoBandCustomGains = GraphicEQMode.thirtyTwoBand.normalizedGains(customGains)
        }

        isRestoring = true
        graphicEQMode = mode
        customGains = mode == .tenBand ? tenBandCustomGains : thirtyTwoBandCustomGains
        currentPreset = matchingBuiltInPreset(currentPreset, mode: mode)
        isRestoring = false

        if isEnabled {
            if let preset = currentPreset, preset.id != "custom" {
                applyPresetCurve(preset)
            } else {
                applyCustomGains()
            }
            applyProfessionalConfiguration()
            updateSafetyLimiter()
        } else {
            PlayerManager.shared.equalizer.setGraphicMode(mode, gainsDB: customGains)
        }
        saveState()
    }

    func applyPresetCurve(_ preset: EQPreset, mode: GraphicEQMode? = nil) {
        let targetMode = mode ?? graphicEQMode
        PlayerManager.shared.equalizer.setGraphicMode(
            targetMode,
            gainsDB: preset.gains(in: targetMode)
        )
    }
    
    func applyPreset(_ preset: EQPreset) {
        if isAIManagedPresetActive, !preset.id.hasPrefix("ai_") {
            restoreProcessingBeforeAI(reason: "manual-preset")
        }
        let resolvedPreset = matchingBuiltInPreset(preset, mode: graphicEQMode) ?? preset
        currentPreset = resolvedPreset
        if !isEnabled {
            isEnabled = true
        }
        if !resolvedPreset.isCustom {
            applyBuiltInProcessingProfile(resolvedPreset)
        }
        updateSafetyLimiter()
        saveAudioEffectsState()
    }
    
    func applyFlat() {
        if isAIManagedPresetActive {
            restoreProcessingBeforeAI(reason: "manual-flat")
        }
        currentPreset = builtInPreset(familyID: "flat", mode: graphicEQMode)
        if currentPreset == nil {
            PlayerManager.shared.equalizer.setGraphicMode(
                graphicEQMode,
                gainsDB: Array(repeating: 0, count: graphicEQMode.bandCount)
            )
            applyProfessionalConfiguration()
        }
        if let currentPreset {
            applyBuiltInProcessingProfile(currentPreset)
        }
        updateSafetyLimiter()
        saveAudioEffectsState()
    }

    func applyBuiltInProcessingProfile(_ preset: EQPreset) {
        let player = PlayerManager.shared
        let profile = preset.processingProfile
        let wasRestoring = isRestoring
        isRestoring = true
        monoEffectTuning = profile.effects
        isRestoring = wasRestoring
        player.audioEffects.applyMonoTuning(
            profile.effects,
            bassGain: profile.bassGain,
            trebleGain: profile.trebleGain,
            surroundLevel: preset.surroundLevel,
            reverbLevel: preset.reverbLevel,
            stereoWidth: preset.stereoWidth
        )
    }

    /// 切换歌曲时撤销上一首 AI 方案，恢复用户在开启 AI 调音前的处理链。
    func prepareForAIAnalysis(songIdentifier: String) {
        restoreProcessingBeforeAI(reason: "track-changed")
        beginSongAnalysis(identifier: songIdentifier)
        configureSmartAnalysis()
    }

    /// 关闭 AI 或切换歌曲时恢复 AI 覆盖前的完整用户处理链。
    func restoreProcessingBeforeAI(reason: String) {
        guard preAIProcessingSnapshot != nil || isAIManagedPresetActive else { return }
        stopLoudnessMatchedReferenceAudition()

        let previousPreset = currentPreset?.name ?? "none"
        let snapshot = preAIProcessingSnapshot ?? neutralAIProcessingSnapshot()
        isRestoring = true
        isEnabled = snapshot.isEnabled
        let restoredMode = snapshot.graphicEQMode
            ?? (snapshot.customGains.count == GraphicEQMode.thirtyTwoBand.bandCount ? .thirtyTwoBand : .tenBand)
        graphicEQMode = restoredMode
        currentPreset = matchingBuiltInPreset(snapshot.currentPreset, mode: restoredMode)
        tenBandCustomGains = GraphicEQMode.tenBand.normalizedGains(
            snapshot.tenBandCustomGains ?? (restoredMode == .tenBand ? snapshot.customGains : [])
        )
        thirtyTwoBandCustomGains = GraphicEQMode.thirtyTwoBand.normalizedGains(
            snapshot.thirtyTwoBandCustomGains ?? (restoredMode == .thirtyTwoBand ? snapshot.customGains : [])
        )
        customGains = restoredMode == .tenBand ? tenBandCustomGains : thirtyTwoBandCustomGains
        customPresetPreampDB = snapshot.customPresetPreampDB
        professionalProcessingIntensity = snapshot.professionalProcessingIntensity
        isLoudnessMatchingEnabled = snapshot.isLoudnessMatchingEnabled
        isOutputCalibrationEnabled = snapshot.isOutputCalibrationEnabled
        isSmartSongCompensationEnabled = snapshot.isSmartSongCompensationEnabled
        isDynamicEQEnabled = snapshot.isDynamicEQEnabled
        dynamicEQBands = snapshot.dynamicEQBands
        isMultibandDynamicsEnabled = snapshot.isMultibandDynamicsEnabled
        multibandConfiguration = snapshot.multibandConfiguration
        isParametricEQEnabled = snapshot.isParametricEQEnabled
        parametricBands = snapshot.parametricBands
        monoEffectTuning = snapshot.monoEffectTuning ?? .neutral
        monoEnhanceConfiguration = snapshot.monoEnhanceConfiguration ?? .neutral
        adaptiveGains = Array(repeating: 0, count: 10)
        committedAdaptiveGains = adaptiveGains
        lastSmartDSPCommit = Date()
        isRestoring = false

        let player = PlayerManager.shared
        player.equalizer.reset()
        player.equalizer.setProcessingEnabled(snapshot.isEnabled)
        if snapshot.isEnabled {
            if let preset = snapshot.currentPreset, preset.id != "custom" {
                applyPresetCurve(preset, mode: restoredMode)
            } else {
                player.equalizer.setGraphicMode(restoredMode, gainsDB: customGains)
            }
        } else {
            player.equalizer.setGraphicMode(restoredMode, gainsDB: customGains)
        }
        player.audioEffects.applyMonoTuning(
            effectiveMonoEffectTuningForCurrentOutput(),
            bassGain: snapshot.bassGain,
            trebleGain: snapshot.trebleGain,
            surroundLevel: snapshot.surroundLevel,
            reverbLevel: snapshot.reverbLevel,
            stereoWidth: snapshot.stereoWidth
        )

        applyProfessionalConfiguration()
        applyMonoEffectTuning()
        configureSmartAnalysis()
        updateSafetyLimiter()
        preAIProcessingSnapshot = nil
        UserDefaults.standard.removeObject(forKey: Self.aiProcessingSnapshotKey)
        saveState()
        saveProfessionalState()
        saveAudioEffectsState()

        AppLogger.info(
            "[EQManager] Restored processing before AI preset=\(previousPreset) reason=\(reason)",
            step: "ai-tuning.restore"
        )
    }

    /// 将 AI 生成的完整 Mono 处理方案一次性写入引擎，避免逐项触发重复重建 DSP 链。
    func applyAIConfiguration(
        _ proposal: AIEqualizerProposal,
        spatialOverride: AIEqualizerSpatialConfiguration? = nil
    ) {
        stopLoudnessMatchedReferenceAudition()
        captureProcessingBeforeAIIfNeeded()

        let professional = proposal.professional
        // The proposal already includes route, phase and intensity validation.
        // Reapplying floors here would undo those limits and change its voicing.
        let resolvedSpatial = spatialOverride ?? proposal.spatial
        let dynamicBands = professional.dynamicEQ.bands.map {
            DynamicEQBand(
                frequency: $0.frequency,
                q: $0.q,
                thresholdDB: $0.thresholdDB,
                ratio: $0.ratio,
                maxReductionDB: $0.maxReductionDB,
                attackMS: $0.attackMS,
                releaseMS: $0.releaseMS
            )
        }
        let parametricBands = professional.parametricEQ.bands.compactMap { band -> ParametricEQBand? in
            guard let type = ParametricEQFilterType(rawValue: band.type) else { return nil }
            return ParametricEQBand(
                type: type,
                frequency: band.frequency,
                gainDB: band.gainDB,
                q: band.q
            )
        }
        let multiband = professional.multiband
        let multibandConfiguration = MultibandDynamicsConfiguration(
            isEnabled: multiband.enabled,
            lowCrossoverHz: multiband.lowCrossoverHz,
            highCrossoverHz: multiband.highCrossoverHz,
            thresholdsDB: multiband.thresholdsDB,
            ratios: multiband.ratios,
            maxReductionDB: multiband.maxReductionDB,
            attackMS: multiband.attackMS,
            releaseMS: multiband.releaseMS
        )
        let resolvedEnhance = proposal.enhance
        let generatedPreset = EQPreset(
            id: "ai_\(proposal.songID)",
            name: proposal.profileName,
            category: .custom,
            description: proposal.profileSpecificSummary,
            gains: proposal.gains,
            isCustom: true,
            presetType: proposal.graphicEQMode == .tenBand ? .standard10 : .graphic32,
            preampDB: proposal.preampDB
        )

        isRestoring = true
        graphicEQMode = proposal.graphicEQMode
        customGains = proposal.gains
        if proposal.graphicEQMode == .tenBand {
            tenBandCustomGains = proposal.gains
        } else {
            thirtyTwoBandCustomGains = proposal.gains
        }
        customPresetPreampDB = proposal.preampDB
        currentPreset = generatedPreset
        professionalProcessingIntensity = professional.processingIntensity
        isOutputCalibrationEnabled = proposal.calibration.outputCalibrationEnabled
        isLoudnessMatchingEnabled = proposal.calibration.loudnessMatchingEnabled
        isSmartSongCompensationEnabled = proposal.calibration.smartSongCompensationEnabled
        isDynamicEQEnabled = professional.dynamicEQ.enabled
        dynamicEQBands = dynamicBands.isEmpty ? DynamicEQBand.monoDefaults : dynamicBands
        isMultibandDynamicsEnabled = multiband.enabled
        self.multibandConfiguration = multibandConfiguration
        isParametricEQEnabled = professional.parametricEQ.enabled && !parametricBands.isEmpty
        self.parametricBands = parametricBands
        monoEffectTuning = proposal.effects
        monoEnhanceConfiguration = resolvedEnhance
        isEnabled = true
        isRestoring = false

        let player = PlayerManager.shared
        player.equalizer.setProcessingEnabled(true)
        applyPresetCurve(generatedPreset, mode: proposal.graphicEQMode)
        let effectiveEffects = effectiveMonoEffectTuningForCurrentOutput()
        player.audioEffects.applyMonoTuning(
            effectiveEffects,
            bassGain: proposal.tone.bassGain,
            trebleGain: proposal.tone.trebleGain,
            surroundLevel: resolvedSpatial.surroundLevel,
            reverbLevel: resolvedSpatial.reverbLevel,
            stereoWidth: resolvedSpatial.stereoWidth
        )
        player.audioRepair.configureOutputSafety(
            limiterEnabled: effectiveEffects.finalLimiterEnabled,
            ceilingDB: effectiveEffects.finalLimiterCeilingDB,
            transitionProtectionEnabled: false,
            outputGainDB: player.audioRepair.outputGainDB,
            perceptualMakeupDB: player.audioRepair.perceptualMakeupDB
        )
        isSafetyLimiterActive = effectiveEffects.finalLimiterEnabled

        beginSongAnalysis(identifier: player.currentSong.map { "\($0.musicSource.rawValue):\($0.id)" })
        applyProfessionalConfiguration()
        configureSmartAnalysis()
        updateSafetyLimiter()
        let committedGains = player.equalizer.graphicGains
        let committedEnhance = player.equalizer.monoEnhanceConfiguration
        let maximumCurveDelta = zip(
            proposal.graphicEQMode.normalizedGains(proposal.gains),
            committedGains
        ).map { abs($0 - $1) }.max() ?? .infinity
        let committedPresetID = currentPreset?.id ?? "none"
        let curveDeltaText = String(format: "%.4f", maximumCurveDelta)
        let attackText = String(format: "%.3f", committedEnhance.transientAttack)
        let vocalText = String(format: "%.3f", committedEnhance.vocalFocus)
        let airText = String(format: "%.3f", committedEnhance.airAmount)
        let stageText = String(format: "%.3f", committedEnhance.stageWidth)
        let surroundText = String(format: "%.3f", player.audioEffects.surroundLevel)
        let reverbText = String(format: "%.3f", player.audioEffects.reverbLevel)
        let widthText = String(format: "%.3f", player.audioEffects.stereoWidth)
        AppLogger.info(
            "[EQManager] AI DSP commit enabled=\(player.equalizer.isProcessingEnabled) preset=\(committedPresetID) mode=\(graphicEQMode.rawValue) curveDelta=\(curveDeltaText) enhance=\(committedEnhance.hasAudibleProcessing) attack=\(attackText) vocal=\(vocalText) air=\(airText) stage=\(stageText) surround=\(surroundText) reverb=\(reverbText) width=\(widthText)",
            step: "ai-tuning.dsp-commit"
        )
        saveState()
        saveProfessionalState()
        saveAudioEffectsState()
    }
    
}
