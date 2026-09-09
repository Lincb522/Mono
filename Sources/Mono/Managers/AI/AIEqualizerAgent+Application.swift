import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

extension AIEqualizerAgent {
    @discardableResult
    func apply(
        _ proposal: AIEqualizerProposal,
        expectedSongIdentifier: String? = nil,
        expectedOutputIdentity: String? = nil,
        isManualAction: Bool = false
    ) -> Bool {
        guard tuningServiceStore.settings.isEnabled else {
            if isManualAction { phase = .failed(String(localized: "ai_tuning_service_disabled")) }
            return false
        }
        let currentSong = PlayerManager.shared.currentSong
        let currentSongID = currentSong?.id
        let currentSongIdentifier = currentSong.map(songIdentifier)
        let currentMode = EQManager.shared.graphicEQMode
        let currentOutputIdentity = currentOutputIdentity()
        let songMatches = expectedSongIdentifier.map { $0 == currentSongIdentifier }
            ?? (currentSongID == proposal.songID)
        let outputMatches = expectedOutputIdentity.map { $0 == currentOutputIdentity } ?? true
        guard songMatches,
              outputMatches,
              currentMode == proposal.graphicEQMode else {
            // 静默丢弃会让 UI 停在“已生成/已应用”的假象上，DSP 却没动。
            // 手动操作给出明确失败反馈；自动流程至少留痕并收敛工作状态。
            AppLogger.warning(
                "[AIEqualizerAgent] Apply skipped currentSong=\(currentSongIdentifier ?? currentSongID.map { String($0) } ?? "none") expectedSong=\(expectedSongIdentifier ?? String(proposal.songID)) currentOutput=\(currentOutputIdentity) expectedOutput=\(expectedOutputIdentity ?? "any") currentMode=\(currentMode.rawValue) proposalMode=\(proposal.graphicEQMode.rawValue) manual=\(isManualAction)",
                step: "ai-tuning.apply-skipped"
            )
            if isManualAction {
                phase = .failed(String(localized: "ai_tuning_apply_context_changed"))
                HapticManager.shared.warning()
            } else if phase.isWorking {
                phase = .idle
            }
            return false
        }
        phase = .applying
        let manager = EQManager.shared
        let resolvedSpatial = MonoNextSuiteManager.shared.resolvedSpatialForTuningProposal(proposal)
        manager.applyAIConfiguration(proposal, spatialOverride: resolvedSpatial)
        let effects = proposal.effects
        let professional = proposal.professional
        let enhance = proposal.enhance
        let appliedAudioEffects = PlayerManager.shared.audioEffects
        let outputGainDB = PlayerManager.shared.audioRepair.outputGainDB
        let perceptualMakeupDB = PlayerManager.shared.audioRepair.perceptualMakeupDB
        AppLogger.success(
            "[AIEqualizerAgent] Applied songID=\(proposal.songID) profile=\(proposal.profileName) tuningProfile=\(proposal.resolvedTuningProfile.rawValue) bands=\(proposal.graphicEQMode.bandCount) preamp=\(String(format: "%.2f", proposal.preampDB))dB surround=\(String(format: "%.3f", appliedAudioEffects.surroundLevel)) reverb=\(String(format: "%.3f", appliedAudioEffects.reverbLevel)) width=\(String(format: "%.3f", appliedAudioEffects.stereoWidth)) outputGain=\(String(format: "%.2f", outputGainDB))dB perceptualMakeup=\(String(format: "%.2f", perceptualMakeupDB))dB nativeEnhance=\(enhance.isEnabled) transient=\(String(format: "%.3f", enhance.transientAttack)) vocal=\(String(format: "%.3f", enhance.vocalFocus)) air=\(String(format: "%.3f", enhance.airAmount)) stage=\(String(format: "%.3f", enhance.stageWidth)) micro=\(String(format: "%.3f", enhance.microDynamics)) dynamicEQ=\(professional.dynamicEQ.enabled ? professional.dynamicEQ.bands.count : 0) multiband=\(professional.multiband.enabled) parametricEQ=\(professional.parametricEQ.enabled ? professional.parametricEQ.bands.count : 0) loudnorm=\(effects.loudnessNormalizationEnabled) compressor=\(effects.compressorEnabled) subboost=\(effects.subboostEnabled) virtualBass=\(effects.virtualBassEnabled) bs2b=\(effects.bs2bEnabled) crossfeed=\(effects.crossfeedEnabled) haas=\(effects.haasEnabled) exciter=\(effects.exciterEnabled) softclip=\(effects.softclipEnabled) limiter=\(effects.finalLimiterEnabled) ceiling=\(String(format: "%.2f", effects.finalLimiterCeilingDB))dBFS",
            step: "ai-tuning.applied"
        )
        appliedProposalID = proposal.id
        appliedSongIdentifier = PlayerManager.shared.currentSong.map { songIdentifier($0) }
        beginLearningSession(for: proposal)
        phase = .ready
        HapticManager.shared.success()
        return true
    }

}
