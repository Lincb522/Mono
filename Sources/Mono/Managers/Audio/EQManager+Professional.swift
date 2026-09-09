import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

extension EQManager {
    // MARK: - Mono 专业校准

    func aiEqualizerDeviceTrainingContext(
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?
    ) -> AIEqualizerDeviceTrainingContext {
        let session = AVAudioSession.sharedInstance()
        let profile = resolvedHeadphoneProfile
        let routeDefault = currentOutputKind.defaultCalibration
        let profileMode: GraphicEQMode = profile?.gains.count == GraphicEQMode.thirtyTwoBand.bandCount
            ? .thirtyTwoBand
            : .tenBand
        let profileGains = profile.map {
            GraphicEQMode.thirtyTwoBand.resampledGains($0.gains, from: profileMode)
        } ?? Array(repeating: 0, count: GraphicEQMode.thirtyTwoBand.bandCount)
        let routeGains = GraphicEQMode.thirtyTwoBand.resampledGains(
            isOutputCalibrationEnabled ? routeDefault : Array(repeating: 0, count: routeDefault.count),
            from: .tenBand
        )
        let selectedCalibration = zip(routeGains, profileGains).map {
            min(6, max(-6, $0 + $1))
        }
        let referenceGains = deviceTuningTarget?.referenceGainsDB ?? []
        let reference32 = referenceGains.isEmpty
            ? Array(repeating: 0, count: GraphicEQMode.thirtyTwoBand.bandCount)
            : GraphicEQMode.thirtyTwoBand.resampledGains(referenceGains, from: .tenBand)
        let effectiveGains = zip(selectedCalibration, reference32).map {
            min(9, max(-9, $0 + $1))
        }
        let profileSource: String
        if profile != nil, deviceTuningTarget != nil {
            profileSource = "mixed"
        } else if deviceTuningTarget != nil {
            profileSource = "airPods"
        } else if profile?.sourceName?.caseInsensitiveCompare("OPRA") == .orderedSame {
            profileSource = "opra"
        } else if profile?.isCustom == true {
            profileSource = "custom"
        } else if profile != nil {
            profileSource = "profile"
        } else if isOutputCalibrationEnabled && routeDefault.contains(where: { abs($0) > 0.001 }) {
            profileSource = "routeDefault"
        } else {
            profileSource = "none"
        }
        let acousticFilters = (profile?.acousticFilters ?? []).prefix(12).map {
            AIEqualizerDeviceAcousticFilterContext(
                kind: $0.kind.rawValue,
                frequencyHz: $0.frequency,
                gainDB: $0.gainDB,
                q: $0.q,
                slopeDBPerOctave: $0.slope ?? 0
            )
        }
        let identityParts = [
            "route:\(currentOutputKind.rawValue)",
            profile.map { "profile:\($0.id)" },
            deviceTuningTarget.map { "target:\($0.identifier)" }
        ].compactMap { $0 }
        return AIEqualizerDeviceTrainingContext(
            detailSchemaVersion: AIEqualizerDeviceTrainingContext.currentSchemaVersion,
            identifier: identityParts.joined(separator: "|"),
            outputKind: currentOutputKind.rawValue,
            profileSource: profileSource,
            calibrationEnabled: isOutputCalibrationEnabled,
            profileActive: profile != nil,
            profileIsCustom: profile?.isCustom == true,
            outputSampleRate: session.sampleRate,
            outputChannelCount: session.outputNumberOfChannels,
            outputLatencyMS: session.outputLatency * 1_000,
            ioBufferDurationMS: session.ioBufferDuration * 1_000,
            routeDefaultGainsDB: routeDefault,
            profileGainsDB: profileGains,
            referenceGainsDB: referenceGains,
            effectiveGainsDB: effectiveGains,
            profilePreampDB: profile?.preampDB ?? 0,
            acousticFilters: acousticFilters,
            fitDescription: deviceTuningTarget?.fitDescription ?? "",
            spatialGuidance: deviceTuningTarget?.spatialGuidance ?? ""
        )
    }

    func handleAudioRouteChanged() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
        currentOutputName = output?.portName ?? String(localized: "eq_current_device")
        currentOutputUID = output?.uid ?? "unknown-output"
        currentOutputKind = Self.outputKind(for: output?.portType)
        applyProfessionalConfiguration()
        if isEnabled { applyMonoEffectTuning() }
        updateSafetyLimiter()
        let presetName = currentPreset?.name ?? "none"
        let limiterCeiling = PlayerManager.shared.audioRepair.outputLimiterCeilingDB
        AppLogger.info(
            "[EQManager] Output route kind=\(currentOutputKind.rawValue) port=\(output?.portType.rawValue ?? "none") name=\(currentOutputName) preset=\(presetName) enabled=\(isEnabled) preamp=\(String(format: "%.2f", preampDB))dB limiter=\(isSafetyLimiterActive) ceiling=\(String(format: "%.2f", limiterCeiling))dBFS",
            step: "audio-output.route-safety"
        )
    }

    func addParametricBand() {
        guard parametricBands.count < 12 else { return }
        parametricBands.append(
            ParametricEQBand(
                type: .peak,
                frequency: parametricBands.isEmpty ? 1_000 : min((parametricBands.last?.frequency ?? 500) * 1.6, 16_000),
                gainDB: 0,
                q: 1
            )
        )
    }

    func toggleLoudnessMatchedReference() {
        guard isEnabled else { return }
        isAuditioningReference.toggle()
        if isAuditioningReference {
            let player = PlayerManager.shared
            let effects = player.audioEffects
            referenceEffectSnapshot = AudioEffectsState(
                bassGain: effects.bassGain,
                trebleGain: effects.trebleGain,
                surroundLevel: effects.surroundLevel,
                reverbLevel: effects.reverbLevel,
                stereoWidth: effects.stereoWidth
            )
            let outputCompensation = player.audioRepair.outputGainDB
                + player.audioRepair.perceptualMakeupDB
            let sourceGains = currentPreset?.id == "custom" || currentPreset == nil
                ? customGains
                : (currentPreset?.gains(in: graphicEQMode) ?? customGains)
            let perceivedCurveGain = zip(sourceGains, Self.loudnessWeights(for: graphicEQMode))
                .reduce(Float(0)) { $0 + $1.0 * $1.1 }
            PlayerManager.shared.equalizer.setGraphicMode(
                graphicEQMode,
                gainsDB: Array(repeating: 0, count: graphicEQMode.bandCount)
            )
            // 参考声必须旁路完整专业链路，否则动态处理仍留在 B 声中，A/B 差异会被掩盖。
            applyProfessionalConfiguration()
            applyMonoEffectTuning()
            PlayerManager.shared.equalizer.setPreampDB(
                min(0, max(-18, preampDB + outputCompensation + perceivedCurveGain))
            )
        } else {
            if let preset = currentPreset, preset.id != "custom" {
                applyPresetCurve(preset)
            } else {
                PlayerManager.shared.equalizer.setGraphicMode(graphicEQMode, gainsDB: customGains)
            }
            applyProfessionalConfiguration()
            applyMonoEffectTuning()
            // 参考声只改了 DSP 的目标前级，不会同步 Published 值；返回 A 声时必须显式恢复。
            PlayerManager.shared.equalizer.setPreampDB(preampDB)
            updateSafetyLimiter()
        }
    }

    func stopLoudnessMatchedReferenceAudition() {
        guard isAuditioningReference else { return }
        toggleLoudnessMatchedReference()
    }

    func removeParametricBand(id: UUID) {
        parametricBands.removeAll { $0.id == id }
    }

    func createHeadphoneProfileForCurrentOutput() {
        let normalizedName = currentOutputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = MonoHeadphoneCorrectionProfile(
            id: "headphone_\(UUID().uuidString)",
            name: normalizedName.isEmpty ? String(localized: "eq_custom_headphone") : normalizedName,
            matchedDeviceName: normalizedName,
            matchedDeviceUID: currentOutputUID,
            gains: Array(repeating: 0, count: 10),
            isCustom: true
        )
        headphoneProfiles.append(profile)
        selectedHeadphoneProfileID = profile.id
    }

    func deleteHeadphoneProfile(id: String) {
        headphoneProfiles.removeAll { $0.id == id }
        if selectedHeadphoneProfileID == id {
            selectedHeadphoneProfileID = "off"
        }
    }

    func setHeadphoneCorrectionGain(_ gain: Float, at index: Int) {
        guard index >= 0, index < 10,
              let profileIndex = headphoneProfiles.firstIndex(where: { $0.id == selectedHeadphoneProfileID })
        else { return }
        headphoneProfiles[profileIndex].gains[index] = min(max(gain, -6), 6)
    }

    func installAcousticProfile(_ profile: MonoAcousticProfile) {
        let preservesAutomaticSelection = selectedHeadphoneProfileID == "auto"
        let id = "opra:\(profile.id)"
        let installed = MonoHeadphoneCorrectionProfile(
            id: id,
            name: profile.displayName,
            matchedDeviceName: currentOutputName,
            matchedDeviceUID: currentOutputUID,
            gains: profile.graphicGains(mode: .thirtyTwoBand),
            isCustom: false,
            sourceName: "OPRA",
            sourceURL: profile.attributionURL?.absoluteString,
            author: profile.author,
            details: profile.details,
            preampDB: profile.preampDB,
            acousticFilters: profile.filters
        )
        if let index = headphoneProfiles.firstIndex(where: { $0.id == id }) {
            headphoneProfiles[index] = installed
        } else {
            headphoneProfiles.append(installed)
        }
        selectedHeadphoneProfileID = preservesAutomaticSelection ? "auto" : id
        if !isEnabled { isEnabled = true }
        applyProfessionalConfiguration()
        updateSafetyLimiter()
    }

    var isAutomaticOutputProfileSelectionEnabled: Bool {
        selectedHeadphoneProfileID == "auto"
    }

    var activeOutputProfileName: String? {
        resolvedHeadphoneProfile?.name
    }

    func setAutomaticOutputProfileSelectionEnabled(_ enabled: Bool) {
        selectedHeadphoneProfileID = enabled ? "auto" : "off"
        if enabled, !isEnabled { isEnabled = true }
        applyProfessionalConfiguration()
        updateSafetyLimiter()
    }

    var currentPresetPreampDB: Float {
        if let id = currentPreset?.id, let override = presetPreampOverrides[id] {
            return override
        }
        if currentPreset?.id == "custom" || currentPreset == nil {
            return customPresetPreampDB
        }
        return currentPreset?.preampDB ?? 0
    }

    func setCurrentPresetPreampDB(_ value: Float) {
        let clamped = min(max(value, -18), 0)
        if let id = currentPreset?.id, id != "custom" {
            presetPreampOverrides[id] = clamped
        } else {
            customPresetPreampDB = clamped
        }
    }

    func setTrackLoudnessGainDB(_ gainDB: Float) {
        let clamped = min(6, max(-12, gainDB.isFinite ? gainDB : 0))
        guard abs(clamped - trackLoudnessGainDB) > 0.02 else { return }
        trackLoudnessGainDB = clamped
        updateSafetyLimiter()
    }

    func installHearingCorrection(left: [Float], right: [Float], enabled: Bool = true) {
        hearingLeftGains = GraphicEQMode.tenBand.normalizedGains(left).map { min(6, max(-6, $0)) }
        hearingRightGains = GraphicEQMode.tenBand.normalizedGains(right).map { min(6, max(-6, $0)) }
        isHearingCorrectionEnabled = enabled
        if enabled, !isEnabled { isEnabled = true }
        applyHearingCorrection()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func setHearingCorrectionEnabled(_ enabled: Bool) {
        guard enabled != isHearingCorrectionEnabled else { return }
        isHearingCorrectionEnabled = enabled
        if enabled, !isEnabled { isEnabled = true }
        applyHearingCorrection()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func clearHearingCorrection() {
        isHearingCorrectionEnabled = false
        hearingLeftGains = Array(repeating: 0, count: 10)
        hearingRightGains = Array(repeating: 0, count: 10)
        applyHearingCorrection()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func installEnvironmentCompensation(_ gains: [Float], enabled: Bool = true) {
        environmentCompensationGains = GraphicEQMode.tenBand.normalizedGains(gains).map {
            min(0, max(-3, $0))
        }
        isEnvironmentCompensationEnabled = enabled
        if enabled, !isEnabled { isEnabled = true }
        applyCombinedAdaptiveGains()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func setEnvironmentCompensationEnabled(_ enabled: Bool) {
        guard enabled != isEnvironmentCompensationEnabled else { return }
        isEnvironmentCompensationEnabled = enabled
        if enabled, !isEnabled { isEnabled = true }
        applyCombinedAdaptiveGains()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func clearEnvironmentCompensation() {
        isEnvironmentCompensationEnabled = false
        environmentCompensationGains = Array(repeating: 0, count: 10)
        applyCombinedAdaptiveGains()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func beginSongAnalysis(identifier: String?) {
        guard smartSongIdentifier != identifier else { return }
        smartSongIdentifier = identifier
        smartSpectrumAverage = Array(repeating: 0, count: 10)
        smartSpectrumFrames = 0
        lastSmartUpdate = .distantPast
        adaptiveGains = Array(repeating: 0, count: 10)
        committedAdaptiveGains = adaptiveGains
        lastSmartDSPCommit = Date()
        applyCombinedAdaptiveGains()
    }

    func headroomSettingChanged() {
        guard !isRestoring else { return }
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func calibrationSettingChanged() {
        guard !isRestoring else { return }
        applyProfessionalConfiguration()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func parametricSettingChanged() {
        guard !isRestoring else { return }
        applyProfessionalConfiguration()
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func dynamicEQSettingChanged() {
        guard !isRestoring else { return }
        applyProfessionalConfiguration()
        saveProfessionalState()
    }

    func multibandSettingChanged() {
        guard !isRestoring else { return }
        applyProfessionalConfiguration()
        saveProfessionalState()
    }

    func monoEffectTuningChanged() {
        guard !isRestoring else { return }
        if isEnabled { applyMonoEffectTuning() }
        updateSafetyLimiter()
        saveProfessionalState()
    }

    func applyMonoEffectTuning() {
        let player = PlayerManager.shared
        let configuration = isAuditioningReference
            ? .neutral
            : effectiveMonoEffectTuningForCurrentOutput()
        if isAuditioningReference {
            player.audioEffects.applyMonoTuning(
                configuration,
                bassGain: 0,
                trebleGain: 0,
                surroundLevel: 0,
                reverbLevel: 0,
                stereoWidth: 1
            )
        } else if let snapshot = referenceEffectSnapshot {
            player.audioEffects.applyMonoTuning(
                configuration,
                bassGain: snapshot.bassGain,
                trebleGain: snapshot.trebleGain,
                surroundLevel: snapshot.surroundLevel,
                reverbLevel: snapshot.reverbLevel,
                stereoWidth: snapshot.stereoWidth ?? 1
            )
            referenceEffectSnapshot = nil
        } else {
            player.audioEffects.applyMonoTuning(configuration)
        }
        let preservesAILevel = isAIManagedPresetActive && !isAuditioningReference
        player.audioRepair.configureOutputSafety(
            limiterEnabled: isEnabled && configuration.finalLimiterEnabled,
            ceilingDB: configuration.finalLimiterCeilingDB,
            transitionProtectionEnabled: false,
            outputGainDB: preservesAILevel ? player.audioRepair.outputGainDB : 0,
            perceptualMakeupDB: preservesAILevel ? player.audioRepair.perceptualMakeupDB : 0
        )
        isSafetyLimiterActive = isEnabled && configuration.finalLimiterEnabled
    }

    func effectiveMonoEffectTuningForCurrentOutput() -> MonoEffectTuningConfiguration {
        var configuration = monoEffectTuning.realtimePlaybackSafe
        if isAIManagedPresetActive && monoEffectTuning.haasEnabled {
            configuration.haasEnabled = true
            configuration.haasDelayMS = min(16, max(7, monoEffectTuning.haasDelayMS))
        }
        switch currentOutputKind {
        case .bluetooth:
            // Bluetooth retains Haas only for a phase-validated spatial
            // proposal, with a shorter delay and stricter output ceiling.
            configuration.haasDelayMS = min(configuration.haasDelayMS, 10)
            configuration.exciterAmountDB = min(configuration.exciterAmountDB, 0.3)
            configuration.compressorMakeupDB = min(configuration.compressorMakeupDB, 0.3)
            configuration.finalLimiterCeilingDB = min(
                configuration.finalLimiterCeilingDB,
                -1.5
            )
        case .wired, .usb:
            break
        default:
            configuration.bs2bEnabled = false
            configuration.crossfeedEnabled = false
            if configuration.haasEnabled {
                configuration.haasDelayMS = min(configuration.haasDelayMS, 11)
            }
        }
        return configuration
    }

    func applyProfessionalConfiguration() {
        let equalizer = PlayerManager.shared.equalizer
        let bypassProfessionalChain = isAuditioningReference
        let zeroGains = Array(repeating: Float(0), count: 10)
        let aiManaged = isAIManagedPresetActive
        let dynamicLimit = graphicEQMode == .thirtyTwoBand ? 3 : 4
        let parametricLimit = graphicEQMode == .thirtyTwoBand ? 3 : 6
        let dynamicEnabled = !bypassProfessionalChain && isDynamicEQEnabled
        let multibandEnabled = !bypassProfessionalChain
            && isMultibandDynamicsEnabled
            && (!aiManaged || !dynamicEnabled)

        equalizer.setCalibrationGains(bypassProfessionalChain ? zeroGains : effectiveCalibrationGains)
        applyHearingCorrection(bypass: bypassProfessionalChain)
        equalizer.setAdaptiveGains(bypassProfessionalChain ? zeroGains : effectiveAdaptiveGains)
        equalizer.setParametricBands(
            !bypassProfessionalChain && isParametricEQEnabled
                ? Array(parametricBands.prefix(aiManaged ? parametricLimit : parametricBands.count))
                : []
        )
        equalizer.setDynamicEQ(
            enabled: dynamicEnabled,
            bands: Array(effectiveDynamicEQBands.prefix(aiManaged ? dynamicLimit : dynamicEQBands.count))
        )
        var dynamics = effectiveMultibandConfiguration
        dynamics.isEnabled = multibandEnabled
        equalizer.setMultibandDynamics(dynamics)
        equalizer.setMonoEnhance(
            bypassProfessionalChain ? .neutral : monoEnhanceConfiguration
        )
    }

    func applyHearingCorrection(bypass: Bool = false) {
        let zero = Array(repeating: Float(0), count: GraphicEQMode.tenBand.bandCount)
        let shouldApply = isHearingCorrectionEnabled && !bypass
        PlayerManager.shared.equalizer.setHearingCorrection(
            left: shouldApply ? hearingLeftGains : zero,
            right: shouldApply ? hearingRightGains : zero
        )
    }

    var effectiveDynamicEQBands: [DynamicEQBand] {
        let amount = professionalProcessingIntensity
        return dynamicEQBands.map { source in
            var band = source
            band.thresholdDB = max(-60, source.thresholdDB - 4 * (amount - 1))
            band.ratio = min(10, 1 + (source.ratio - 1) * amount)
            band.maxReductionDB = min(12, source.maxReductionDB * amount)
            return band
        }
    }

    var effectiveMultibandConfiguration: MultibandDynamicsConfiguration {
        let amount = professionalProcessingIntensity
        var configuration = multibandConfiguration
        configuration.thresholdsDB = configuration.thresholdsDB.map {
            max(-60, $0 - 3 * (amount - 1))
        }
        configuration.ratios = configuration.ratios.map {
            min(6, 1 + ($0 - 1) * amount)
        }
        configuration.maxReductionDB = configuration.maxReductionDB.map {
            min(8, $0 * amount)
        }
        return configuration
    }

    var effectiveCalibrationGains: [Float] {
        let profile = resolvedHeadphoneProfile
        let targetMode: GraphicEQMode = profile?.gains.count == GraphicEQMode.thirtyTwoBand.bandCount
            ? .thirtyTwoBand
            : .tenBand
        var gains = isOutputCalibrationEnabled
            ? targetMode.resampledGains(currentOutputKind.defaultCalibration, from: .tenBand)
            : Array(repeating: 0, count: targetMode.bandCount)
        guard let profile else { return gains }
        for index in 0..<min(gains.count, profile.gains.count) {
            gains[index] = min(max(gains[index] + profile.gains[index], -6), 6)
        }
        return gains
    }

    var resolvedHeadphoneProfile: MonoHeadphoneCorrectionProfile? {
        if selectedHeadphoneProfileID == "off" { return nil }
        if selectedHeadphoneProfileID == "auto" {
            let routeName = currentOutputName.lowercased()
            return headphoneProfiles.first {
                let match = $0.matchedDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return (!$0.matchedDeviceUID.isEmpty && $0.matchedDeviceUID == currentOutputUID)
                    || (!match.isEmpty && routeName.contains(match))
            }
        }
        return headphoneProfiles.first { $0.id == selectedHeadphoneProfileID }
    }

    func configureSmartAnalysis() {
        // 必须用 pre-effect 分析器：可视化用的 spectrumAnalyzer 取自 mixer tap，
        // 读到的是 EQ/效果器处理后的频谱。用它做补偿会把自己的修正当成
        // 素材缺陷继续修，和 AI 托管曲线形成反馈回路。
        let analyzer = PlayerManager.shared.streamPlayer.analysisSpectrumAnalyzer
        guard isEnabled, isSmartSongCompensationEnabled else {
            analyzer.onCalibrationSpectrum = nil
            analyzer.isCalibrationEnabled = false
            return
        }
        analyzer.onCalibrationSpectrum = { [weak self] magnitudes, sampleRate, rms in
            Task { @MainActor [weak self] in
                self?.processSmartSpectrum(magnitudes, sampleRate: sampleRate, rms: rms)
            }
        }
        analyzer.isCalibrationEnabled = true
    }

    func processSmartSpectrum(_ magnitudes: [Float], sampleRate: Double, rms: Float) {
        guard isEnabled, isSmartSongCompensationEnabled, !isAuditioningReference,
              rms > 0.004, magnitudes.count > 32 else { return }

        let songID = PlayerManager.shared.currentSong.map { "\($0.musicSource.rawValue):\($0.id)" }
        if songID != smartSongIdentifier {
            beginSongAnalysis(identifier: songID)
        }
        guard Date().timeIntervalSince(lastSmartUpdate) >= 1.0 else { return }
        lastSmartUpdate = Date()

        let frequencies = EQBand.allCases.map { Double($0.centerFrequency) }
        let binWidth = sampleRate / Double(magnitudes.count * 2)
        var measured = Array(repeating: Float(-100), count: 10)
        for (index, frequency) in frequencies.enumerated() {
            let lower = frequency / sqrt(2)
            let upper = frequency * sqrt(2)
            let lowerBin = max(1, Int(lower / binWidth))
            let upperBin = min(magnitudes.count - 1, max(lowerBin, Int(upper / binWidth)))
            guard upperBin >= lowerBin else { continue }
            var energy: Float = 0
            for bin in lowerBin...upperBin {
                energy += magnitudes[bin] * magnitudes[bin]
            }
            measured[index] = 10 * log10f(max(energy / Float(upperBin - lowerBin + 1), 0.000_000_000_1))
        }

        if smartSpectrumFrames == 0 {
            smartSpectrumAverage = measured
        } else {
            for index in 0..<10 {
                smartSpectrumAverage[index] = smartSpectrumAverage[index] * 0.88 + measured[index] * 0.12
            }
        }
        smartSpectrumFrames += 1
        guard smartSpectrumFrames >= 4 else { return }

        let intensity = professionalProcessingIntensity
        var requested = Array(repeating: Float(0), count: 10)
        for index in 1..<9 {
            let neighborhood = (smartSpectrumAverage[index - 1] + smartSpectrumAverage[index + 1]) * 0.5
            let localDeviation = smartSpectrumAverage[index] - neighborhood
            requested[index] = min(max(-localDeviation * 0.2 * intensity, -1.5), min(1.2, 0.9 * intensity))
        }
        let subBassExcess = smartSpectrumAverage[0] - smartSpectrumAverage[1]
        requested[0] = subBassExcess > 5 ? max(-1.5, -(subBassExcess - 5) * 0.18 * intensity) : 0
        let airDeviation = smartSpectrumAverage[9] - smartSpectrumAverage[8]
        requested[9] = airDeviation > 4 ? max(-1.5, -(airDeviation - 4) * 0.16 * intensity) : 0

        // Never turn spectral analysis into an automatic loudness boost.
        let positiveMean = requested.reduce(0, +) / Float(requested.count)
        if positiveMean > 0 {
            requested = requested.map { min(max($0 - positiveMean, -1.5), 0.8) }
        }
        for index in 0..<10 {
            adaptiveGains[index] = adaptiveGains[index] * 0.72 + requested[index] * 0.28
        }

        // The analyzer may produce a frame every second. Committing arrays and
        // output-safety state on every frame needlessly collides with the three
        // locks used by the realtime DSP path. Coalesce changes below the
        // inaudible 0.025 dB threshold, while forcing a refresh every 3 seconds
        // so slow spectral movement is still followed accurately.
        let maximumCommittedDelta = zip(adaptiveGains, committedAdaptiveGains)
            .map { pair in abs(pair.0 - pair.1) }
            .max() ?? 0
        let now = Date()
        guard maximumCommittedDelta >= 0.025
                || now.timeIntervalSince(lastSmartDSPCommit) >= 3 else {
            return
        }
        committedAdaptiveGains = adaptiveGains
        lastSmartDSPCommit = now
        applyCombinedAdaptiveGains()
        updateSafetyLimiter()
    }

    func resetSmartCompensation() {
        smartSpectrumAverage = Array(repeating: 0, count: 10)
        smartSpectrumFrames = 0
        adaptiveGains = Array(repeating: 0, count: 10)
        committedAdaptiveGains = adaptiveGains
        lastSmartDSPCommit = Date()
        applyCombinedAdaptiveGains()
        updateSafetyLimiter()
    }

    func applyCombinedAdaptiveGains() {
        let zeroGains = Array(repeating: Float(0), count: 10)
        PlayerManager.shared.equalizer.setAdaptiveGains(
            isAuditioningReference ? zeroGains : effectiveAdaptiveGains
        )
    }

    var effectiveAdaptiveGains: [Float] {
        let smart = isSmartSongCompensationEnabled
            ? GraphicEQMode.tenBand.normalizedGains(adaptiveGains)
            : Array(repeating: 0, count: 10)
        let environment = isEnvironmentCompensationEnabled
            ? GraphicEQMode.tenBand.normalizedGains(environmentCompensationGains)
            : Array(repeating: 0, count: 10)
        return zip(smart, environment).map { min(2, max(-4.5, $0 + $1)) }
    }

    static func outputKind(for port: AVAudioSession.Port?) -> MonoAudioOutputKind {
        switch port {
        case .builtInSpeaker, .builtInReceiver: return .builtInSpeaker
        case .headphones, .headsetMic, .lineOut: return .wired
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
        case .carAudio: return .car
        case .airPlay: return .airPlay
        case .usbAudio, .displayPort: return .usb
        default: return .other
        }
    }

}
