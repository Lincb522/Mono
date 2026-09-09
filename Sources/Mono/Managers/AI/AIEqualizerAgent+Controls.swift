import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

extension AIEqualizerAgent {
    func handleTuningServiceChanged() {
        cancelAnalysis()
        discardPendingManualEqualizerLearning()
        activeLearningSession = nil
        currentLearningFeedback = nil
        generationStartedAt = nil
        proposal = nil
        appliedProposalID = nil
        appliedSongIdentifier = nil
        phase = .idle
        EQManager.shared.restoreProcessingBeforeAI(reason: "tuning-service-changed")
        scheduleAutomaticAnalysis()
    }

    func selectTuningProfile(_ profile: AIEqualizerTuningProfile) {
        let selectionChanged = tuningProfile != profile
        let appliedProfileMatches = proposal?.resolvedTuningProfile == profile
            && isCurrentProposalApplied
        guard selectionChanged || !appliedProfileMatches else { return }
        if selectionChanged {
            tuningProfile = profile
        }

        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        tuningStartedAt = nil
        generationStartedAt = nil
        activeLearningSession = nil
        currentLearningFeedback = nil

        guard isAutomaticTuningActive,
              let song = PlayerManager.shared.currentSong else {
            if phase.isWorking { phase = .idle }
            return
        }

        let identifier = songIdentifier(song)
        samplingRetryCount[identifier] = nil

        EQManager.shared.prepareForAIAnalysis(songIdentifier: identifier)
        proposal = nil
        appliedProposalID = nil
        appliedSongIdentifier = nil
        samplingStage = .preparing
        generationStage = .preparing
        phase = .idle
        AppLogger.info(
            "[AIEqualizerAgent] Tuning profile selection requires analysis song=\(identifier) profile=\(profile.rawValue)",
            step: "ai-tuning.profile-analysis"
        )
        scheduleAutomaticAnalysis()
    }

    func analyzeCurrentSong() {
        guard tuningServiceStore.settings.isEnabled else {
            phase = .failed(String(localized: "ai_tuning_service_disabled"))
            return
        }
        guard PlayerManager.shared.currentSong?.isAppleMusic != true else {
            phase = .failed(
                AIEqualizerError.protectedAudioUnsupported.localizedDescription
            )
            return
        }
        recordImplicitFeedbackIfNeeded(.regenerated)
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        samplingRetryCount.removeAll()
        measuredFeatures = nil
        proposal = nil
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        tuningStartedAt = nil
        if let song = PlayerManager.shared.currentSong {
            EQManager.shared.prepareForAIAnalysis(songIdentifier: songIdentifier(song))
        }
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(trigger: .manual, forceRegeneration: true)
        }
    }

    /// Invalidates only the active output-device result. Measurements remain
    /// reusable because the selected AirPods baseline is applied after spectral
    /// analysis, while proposal/cache identity changes with the selected model.
    func handleOutputTuningTargetChanged() {
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        tuningStartedAt = nil
        generationStartedAt = nil
        proposal = nil
        appliedProposalID = nil
        appliedSongIdentifier = nil
        phase = .idle

        guard isAutomaticTuningActive,
              PlayerManager.shared.currentSong != nil else { return }
        scheduleAutomaticAnalysis()
    }

    func cancelAnalysis() {
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        analysisTask = nil
        samplingRetryCount.removeAll()
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        tuningStartedAt = nil
        if phase.isWorking { phase = .idle }
        if measuredFeatures == nil,
           let song = PlayerManager.shared.currentSong {
            measuredFeatures = restoredMeasurement(for: song)
        }
    }

    func applyCurrentProposal() {
        guard let proposal else { return }
        apply(proposal, isManualAction: true)
    }

    func applySavedProposal(_ saved: AIEqualizerSavedProposal) {
        guard tuningServiceStore.settings.isEnabled else {
            phase = .failed(String(localized: "ai_tuning_service_disabled"))
            return
        }
        guard let song = PlayerManager.shared.currentSong,
              songIdentifier(song) == saved.songIdentifier else {
            rejectManualApply(reason: "song mismatch", saved: saved)
            return
        }
        let currentMode = EQManager.shared.graphicEQMode
        let adaptedProposal = saved.proposal.adapted(to: currentMode)
        let currentOutputIdentity = currentOutputIdentity()
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        tuningStartedAt = nil
        tuningIntensity = adaptedProposal.tuningIntensity ?? .smart
        tuningProfile = adaptedProposal.tuningProfile ?? .standard
        proposal = adaptedProposal
        apply(adaptedProposal, isManualAction: true)
        AppLogger.info(
            "[AIEqualizerAgent] Applied saved proposal song=\(saved.songIdentifier) proposal=\(saved.id.uuidString) savedOutput=\(saved.outputIdentity) currentOutput=\(currentOutputIdentity) savedMode=\(saved.proposal.graphicEQMode.rawValue) currentMode=\(currentMode.rawValue)",
            step: "ai-tuning.saved-apply"
        )
    }

    /// 手动应用被环境变化拦下时不能无声返回：用户点了按钮，必须看到结果。
    func rejectManualApply(reason: String, saved: AIEqualizerSavedProposal) {
        AppLogger.warning(
            "[AIEqualizerAgent] Manual apply rejected (\(reason)) proposal=\(saved.id.uuidString) song=\(saved.songIdentifier) output=\(saved.outputIdentity)",
            step: "ai-tuning.apply-skipped"
        )
        phase = .failed(String(localized: "ai_tuning_apply_context_changed"))
        HapticManager.shared.warning()
    }

    func deleteSavedProposal(_ saved: AIEqualizerSavedProposal) {
        guard let song = PlayerManager.shared.currentSong else { return }
        let identifier = songIdentifier(song)
        guard identifier == saved.songIdentifier else { return }
        proposalCache.delete(saved, for: identifier)
        savedProposals = proposalCache.history(for: identifier)
        AppLogger.info(
            "[AIEqualizerAgent] Deleted saved proposal song=\(identifier) proposal=\(saved.id.uuidString)",
            step: "ai-tuning.saved-delete"
        )
    }

    func deleteAllSavedProposalsForCurrentSong() {
        guard let song = PlayerManager.shared.currentSong else { return }
        let identifier = songIdentifier(song)
        proposalCache.deleteAll(for: identifier)
        savedProposals = []
        AppLogger.info(
            "[AIEqualizerAgent] Deleted all saved proposals song=\(identifier)",
            step: "ai-tuning.saved-delete-all"
        )
    }

    func deleteAllSavedProposals() {
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRunID = nil
        activeAnalysisSongIdentifier = nil
        scheduledAutomaticRunID = nil
        scheduledAutomaticSongIdentifier = nil
        tuningStartedAt = nil
        generationStartedAt = nil
        samplingRetryCount.removeAll()
        activeLearningSession = nil
        currentLearningFeedback = nil

        proposalCache.deleteAll()
        savedProposals = []
        proposal = nil
        appliedProposalID = nil
        appliedSongIdentifier = nil
        samplingStage = .preparing
        generationStage = .preparing
        phase = .idle
        EQManager.shared.restoreProcessingBeforeAI(reason: "all-proposals-deleted")

        HapticManager.shared.success()
        AppLogger.info(
            "[AIEqualizerAgent] Deleted all saved and cached proposals",
            step: "ai-tuning.saved-delete-all-global"
        )
    }

    func recordCurrentProposalFeedback(_ feedback: AIEqualizerLearningFeedback) {
        guard learnsFromExplicitFeedback else { return }
        guard feedback == .positive || feedback == .negative else { return }
        guard currentLearningFeedback != feedback else { return }
        recordFeedbackIfPossible(feedback)
    }

    func clearLearningHistory() {
        discardPendingManualEqualizerLearning()
        learningStore.clear()
        activeLearningSession = nil
        currentLearningFeedback = nil
        refreshLearningRecords()
        AppLogger.info(
            "[AIEqualizerAgent] Adaptive learning history cleared",
            step: "ai-tuning.learning-cleared"
        )
    }

    func deleteLearningRecord(id: UUID) {
        guard learningStore.delete(id: id) else { return }
        if proposal?.id == id {
            currentLearningFeedback = nil
        }
        refreshLearningRecords()
        AppLogger.info(
            "[AIEqualizerAgent] Adaptive learning record deleted",
            step: "ai-tuning.learning-record-deleted"
        )
    }

    func makeCloudSnapshot() -> CloudAIEqualizerSnapshot? {
        proposalCache.makeCloudSnapshot()
    }

    func restoreCloudSnapshot(_ snapshot: CloudAIEqualizerSnapshot) {
        proposalCache.mergeCloudSnapshot(snapshot)
        savedProposals = observedSongIdentifier.map { proposalCache.history(for: $0) } ?? []
    }

    func resetToFlat() {
        recordImplicitFeedbackIfNeeded(.reset)
        EQManager.shared.restoreProcessingBeforeAI(reason: "manual-reset")
        EQManager.shared.applyFlat()
        appliedProposalID = nil
        appliedSongIdentifier = nil
    }

    func testProviderConnection() async throws {
        let managedAgent = await AppAgentConfigurationStore.shared.agentConfiguration(.equalizer)
        if let managedAgent, !managedAgent.enabled { throw AIEqualizerError.modelUnavailable }
        let context = try await resolvedProviderRequestContext(usePublishedConfiguration: false)
        let bundledSystemPrompt = AIEqualizerPrompt.system(for: .tenBand)
        let configuredSystemPrompt = managedAgent?.systemPrompt(fallback: bundledSystemPrompt)
        let text = try await client.generate(
            systemPrompt: AIEqualizerPrompt.managedSystemPrompt(
                for: .tenBand,
                configuredPrompt: configuredSystemPrompt
            ),
            userPrompt: managedAgent?.userPrompt(fallback: AIEqualizerPrompt.connectivityTest)
                ?? AIEqualizerPrompt.connectivityTest,
            configuration: context.configuration,
            apiKey: context.apiKey,
            minimumTimeout: managedAgent?.resolvedMinimumTimeoutSeconds ?? 0,
            options: managedAgent?.generationOptions ?? .standard
        )
        _ = try decodeModelOutput(from: text, expectedMode: .tenBand)
    }

}
