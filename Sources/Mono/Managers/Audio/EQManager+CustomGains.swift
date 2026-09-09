import Foundation
import Combine
import AVFoundation
import FFmpegSwiftSDK

extension EQManager {
    // MARK: - 自定义增益
    
    func setCustomGain(_ gain: Float, at index: Int, userInitiated: Bool = true) {
        guard customGains.indices.contains(index) else { return }
        let clampedGain = EQBandGain.clamped(gain)
        guard abs(customGains[index] - clampedGain) > 0.001 else { return }
        if userInitiated { stopLoudnessMatchedReferenceAudition() }
        let previousGains = customGains
        customGains[index] = clampedGain
        if isEnabled {
            PlayerManager.shared.equalizer.setGraphicGain(customGains[index], at: index)
            updateSafetyLimiter()
        }
        if userInitiated {
            userGraphicGainAdjustmentSubject.send(
                EQGraphicGainUserAdjustment(
                    graphicEQMode: graphicEQMode,
                    previousGains: previousGains,
                    adjustedGains: customGains,
                    changedAt: Date()
                )
            )
        }
    }
    
    func applyCustomGains() {
        PlayerManager.shared.equalizer.setGraphicMode(graphicEQMode, gainsDB: customGains)
        updateSafetyLimiter()
    }

}
