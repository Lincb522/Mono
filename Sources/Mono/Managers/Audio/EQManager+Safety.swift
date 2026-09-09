import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

extension EQManager {
    // MARK: - 安全增益管理（前级补偿 + 限幅器）
    
    /// 根据当前 EQ 增益峰值和旋钮状态，自动调整前级补偿并启用安全限幅器
    func updateSafetyLimiter() {
        let effects = PlayerManager.shared.audioEffects
        let repair = PlayerManager.shared.audioRepair
        guard isEnabled else {
            disableSafetyMeasures()
            return
        }

        // The legacy FFmpeg limiter sits before Mono's realtime EQ. Keep it
        // disabled so final peak protection is owned by the post-EQ repair stage.
        effects.setLimiterEnabled(false)

        // A/B 参考声保持完整旁路；只保留切换时计算出的等响前级。
        if isAuditioningReference {
            if isSafetyLimiterActive {
                repair.configureOutputSafety(
                    limiterEnabled: false,
                    transitionProtectionEnabled: false
                )
                isSafetyLimiterActive = false
            }
            return
        }
        
        let userGains: [Float]
        if let preset = currentPreset, preset.id != "custom" {
            userGains = preset.gains(in: graphicEQMode)
        } else {
            userGains = customGains
        }
        var gains = Array(repeating: Float(0), count: graphicEQMode.bandCount)
        let calibrationSourceMode: GraphicEQMode = effectiveCalibrationGains.count == GraphicEQMode.thirtyTwoBand.bandCount
            ? .thirtyTwoBand
            : .tenBand
        let calibration = graphicEQMode.resampledGains(effectiveCalibrationGains, from: calibrationSourceMode)
        let activeAdaptive = graphicEQMode.resampledGains(effectiveAdaptiveGains, from: .tenBand)
        let activeHearingLeft = isHearingCorrectionEnabled
            ? graphicEQMode.resampledGains(hearingLeftGains, from: .tenBand)
            : Array(repeating: 0, count: graphicEQMode.bandCount)
        let activeHearingRight = isHearingCorrectionEnabled
            ? graphicEQMode.resampledGains(hearingRightGains, from: .tenBand)
            : Array(repeating: 0, count: graphicEQMode.bandCount)
        for index in gains.indices {
            let user = index < userGains.count ? userGains[index] : 0
            let device = index < calibration.count ? calibration[index] : 0
            let adaptive = index < activeAdaptive.count ? activeAdaptive[index] : 0
            let hearing = max(
                activeHearingLeft.indices.contains(index) ? activeHearingLeft[index] : 0,
                activeHearingRight.indices.contains(index) ? activeHearingRight[index] : 0
            )
            gains[index] = user + device + adaptive + hearing
        }
        
        let bassKnob = max(effects.bassGain, 0)
        let trebleKnob = max(effects.trebleGain, 0)
        let curvePeakBoost = Self.estimatedCurvePeakBoostDB(for: gains, mode: graphicEQMode)
        let parametricPeakBoost = isParametricEQEnabled
            ? Self.estimatedParametricPeakBoostDB(for: parametricBands)
            : 0
        let toneControlBoost = max(bassKnob, trebleKnob)
        // 使用效果器当前值，兼容用户在任何预设上手动叠加环绕或混响。
        let spatialHeadroom = effects.estimatedSpatialPeakBoostDB
        let effectiveTuning = effectiveMonoEffectTuningForCurrentOutput()
        let enhancementHeadroom = (effectiveTuning.subboostEnabled ? effectiveTuning.subboostGainDB * 0.45 : 0)
            + (effectiveTuning.virtualBassEnabled ? effectiveTuning.virtualBassStrength * 0.25 : 0)
            + (effectiveTuning.exciterEnabled ? effectiveTuning.exciterAmountDB * 0.18 : 0)
            + (effectiveTuning.compressorEnabled ? max(0, effectiveTuning.compressorMakeupDB) : 0)
            + monoEnhanceConfiguration.estimatedPeakBoostDB
        let peakGain = curvePeakBoost
            + parametricPeakBoost
            + toneControlBoost
            + spatialHeadroom
            + enhancementHeadroom
        
        // The AI trim includes the final ceiling as well as the estimated
        // cascade peak. Bluetooth retains additional inter-sample headroom.
        let safetyMargin: Float = currentOutputKind == .bluetooth ? 0.75 : 0.35
        let routeSafeCeiling: Float = currentOutputKind == .bluetooth ? -1.5 : -1
        let limiterCeiling = effectiveTuning.finalLimiterEnabled
            ? min(effectiveTuning.finalLimiterCeilingDB, routeSafeCeiling)
            : routeSafeCeiling
        let aiManaged = isAIManagedPresetActive
        let safetyTrim: Float = peakGain > 0.1
            ? -(peakGain + safetyMargin) + (aiManaged ? limiterCeiling : 0)
            : 0
        let presetTrim: Float
        if currentPreset?.id == "custom" || currentPreset == nil {
            presetTrim = customPresetPreampDB
        } else if let id = currentPreset?.id, let override = presetPreampOverrides[id] {
            presetTrim = override
        } else {
            presetTrim = currentPreset?.preampDB ?? safetyTrim
        }
        let perceivedBoost = zip(gains, Self.loudnessWeights(for: graphicEQMode))
            .reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let automaticLoudnessTrim = -max(perceivedBoost, 0)
        let loudnessTrim = isLoudnessMatchingEnabled
            ? (currentPreset?.loudnessCompensationDB ?? automaticLoudnessTrim)
            : 0
        let deviceTrim = resolvedHeadphoneProfile?.preampDB ?? 0
        let trackTrim = min(0, trackLoudnessGainDB)
        let newPreamp = max(-18, min(safetyTrim, presetTrim, loudnessTrim, deviceTrim, trackTrim))
        
        if abs(newPreamp - preampDB) > 0.05 {
            preampDB = newPreamp
            PlayerManager.shared.equalizer.setPreampDB(newPreamp)
        }
        
        // 限幅器只处理瞬态余量，不再替代前级补偿持续压扁动态。
        let shouldLimit = effectiveTuning.finalLimiterEnabled
            || peakGain > 0.1
            || abs(trackLoudnessGainDB) > 0.05

        // Positive track normalization may use unused headroom, but must not
        // cancel the AI safety trim and make the limiter do sustained compression.
        let makeupCeiling: Float = currentOutputKind == .bluetooth ? 6 : 9
        let availableOutputHeadroom = aiManaged
            ? max(0, safetyTrim - newPreamp)
            : makeupCeiling
        let combinedOutputGain = min(
            makeupCeiling,
            availableOutputHeadroom,
            max(0, trackLoudnessGainDB)
        )
        repair.configureOutputSafety(
            limiterEnabled: shouldLimit,
            ceilingDB: limiterCeiling,
            transitionProtectionEnabled: false,
            outputGainDB: combinedOutputGain,
            perceptualMakeupDB: 0
        )
        isSafetyLimiterActive = shouldLimit
    }

    static let tenBandLoudnessWeights: [Float] = [0.02, 0.055, 0.105, 0.145, 0.17, 0.17, 0.145, 0.105, 0.06, 0.025]

    static func loudnessWeights(for mode: GraphicEQMode) -> [Float] {
        let resampled = mode.resampledGains(tenBandLoudnessWeights, from: .tenBand)
        let total = max(resampled.reduce(0, +), 0.000_001)
        return resampled.map { $0 / total }
    }

    /// 估算当前图示 EQ 级联后的实际最大正增益。首尾频段使用与
    /// Mono 实时处理相同的 shelf 形状，其余频段使用 peaking。
    /// 使用与 Mono EQFilter 相同的 RBJ 系数，在 20 Hz～近 Nyquist 之间按对数采样。
    static func estimatedCurvePeakBoostDB(
        for gains: [Float],
        mode: GraphicEQMode,
        sampleRate: Float = 48_000
    ) -> Float {
        let frequencies = mode.centerFrequencies
        let qValues = mode.qValues
        guard !gains.isEmpty, gains.contains(where: { abs($0) > 0.001 }) else {
            return 0
        }

        let upperFrequency = min(20_000, sampleRate * 0.45)
        let ratio = upperFrequency / 20
        let sampleCount = 192
        var peakDB: Float = 0

        for point in 0 ..< sampleCount {
            let progress = Float(point) / Float(sampleCount - 1)
            let frequency = 20 * powf(ratio, progress)
            let omega = 2 * Float.pi * frequency / sampleRate
            var responseDB: Float = 0

            for index in frequencies.indices where index < gains.count {
                let gain = gains[index]
                guard abs(gain) > 0.001 else { continue }
                if mode == .tenBand, index == frequencies.startIndex {
                    responseDB += shelfResponseDB(gainDB: gain, frequency: frequencies[index], sampleRate: sampleRate, omega: omega, isHigh: false)
                } else if mode == .tenBand, index == frequencies.index(before: frequencies.endIndex) {
                    responseDB += shelfResponseDB(gainDB: gain, frequency: frequencies[index], sampleRate: sampleRate, omega: omega, isHigh: true)
                } else {
                    responseDB += peakingResponseDB(
                        gainDB: gain,
                        centerFrequency: frequencies[index],
                        q: qValues[index],
                        sampleRate: sampleRate,
                        omega: omega
                    )
                }
            }
            peakDB = max(peakDB, responseDB)
        }
        return max(0, peakDB)
    }

    static func peakingResponseDB(
        gainDB: Float,
        centerFrequency: Float,
        q: Float,
        sampleRate: Float,
        omega: Float
    ) -> Float {
        let amplitude = powf(10, gainDB / 40)
        let centerOmega = 2 * Float.pi * centerFrequency / sampleRate
        let alpha = sinf(centerOmega) / (2 * q)
        let a0 = 1 + alpha / amplitude

        let b0 = (1 + alpha * amplitude) / a0
        let b1 = (-2 * cosf(centerOmega)) / a0
        let b2 = (1 - alpha * amplitude) / a0
        let a1 = (-2 * cosf(centerOmega)) / a0
        let a2 = (1 - alpha / amplitude) / a0

        return biquadResponseDB(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2, omega: omega)
    }

    static func shelfResponseDB(
        gainDB: Float,
        frequency: Float,
        sampleRate: Float,
        omega: Float,
        isHigh: Bool
    ) -> Float {
        let amplitude = powf(10, gainDB / 40)
        let centerOmega = 2 * Float.pi * min(frequency, sampleRate * 0.475) / sampleRate
        let cosine = cosf(centerOmega)
        let alpha = sinf(centerOmega) * sqrtf(2) / 2
        let beta = 2 * sqrtf(amplitude) * alpha
        let raw: (Float, Float, Float, Float, Float, Float)
        if isHigh {
            raw = (
                amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta),
                -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta),
                (amplitude + 1) - (amplitude - 1) * cosine + beta,
                2 * ((amplitude - 1) - (amplitude + 1) * cosine),
                (amplitude + 1) - (amplitude - 1) * cosine - beta
            )
        } else {
            raw = (
                amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta),
                2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
                amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta),
                (amplitude + 1) + (amplitude - 1) * cosine + beta,
                -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                (amplitude + 1) + (amplitude - 1) * cosine - beta
            )
        }
        let a0 = abs(raw.3) < 0.000_001 ? 1 : raw.3
        return biquadResponseDB(
            b0: raw.0 / a0,
            b1: raw.1 / a0,
            b2: raw.2 / a0,
            a1: raw.4 / a0,
            a2: raw.5 / a0,
            omega: omega
        )
    }

    static func estimatedParametricPeakBoostDB(
        for bands: [ParametricEQBand],
        sampleRate: Float = 48_000
    ) -> Float {
        // Pass and notch filters never add headroom. For boosts, the sum of
        // positive gains is conservative and stable while users drag Q/Fc.
        return bands.reduce(Float(0)) { result, band in
            guard band.isEnabled else { return result }
            switch band.type {
            case .peak, .lowShelf, .highShelf:
                return result + max(band.gainDB, 0)
            case .lowPass, .highPass, .notch:
                return result
            }
        }
    }

    static func biquadResponseDB(
        b0: Float, b1: Float, b2: Float, a1: Float, a2: Float, omega: Float
    ) -> Float {
        let cos1 = cosf(omega)
        let sin1 = sinf(omega)
        let cos2 = cosf(2 * omega)
        let sin2 = sinf(2 * omega)
        let numeratorReal = b0 + b1 * cos1 + b2 * cos2
        let numeratorImaginary = -(b1 * sin1 + b2 * sin2)
        let denominatorReal = 1 + a1 * cos1 + a2 * cos2
        let denominatorImaginary = -(a1 * sin1 + a2 * sin2)
        let numeratorPower = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
        let denominatorPower = max(
            denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary,
            0.000_000_1
        )
        return 10 * log10f(max(numeratorPower / denominatorPower, 0.000_000_1))
    }
    
    func disableSafetyMeasures() {
        let player = PlayerManager.shared
        if preampDB != 0 {
            preampDB = 0
            player.equalizer.setPreampDB(0)
        }
        // Spatial Live can run while the EQ is bypassed. Its final safety
        // stays in the repair stage without re-enabling the user's EQ curve.
        let spatialHeadroom = player.audioEffects.estimatedSpatialPeakBoostDB
        let needsSpatialSafety = spatialHeadroom > 0.1 && !isAuditioningReference
        let bluetooth = currentOutputKind == .bluetooth
        let ceiling: Float = bluetooth ? -1.5 : -1
        let margin: Float = bluetooth ? 0.75 : 0.35
        player.audioRepair.configureOutputSafety(
            limiterEnabled: needsSpatialSafety,
            ceilingDB: ceiling,
            transitionProtectionEnabled: false,
            outputGainDB: needsSpatialSafety ? max(-18, -spatialHeadroom - margin + ceiling) : 0,
            perceptualMakeupDB: 0
        )
        isSafetyLimiterActive = needsSpatialSafety
        player.audioEffects.setLimiterEnabled(false)
    }
    
}
