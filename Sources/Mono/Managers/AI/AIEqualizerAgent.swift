import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

enum AIEqualizerAnalysisTrigger: Equatable {
    case manual
    case automatic

    var logName: String {
        switch self {
        case .manual: return "manual"
        case .automatic: return "automatic"
        }
    }
}

@MainActor
final class AIEqualizerAgent: ObservableObject {
    static let shared = AIEqualizerAgent()

    @Published var phase: AIEqualizerAgentPhase = .idle
    @Published var proposal: AIEqualizerProposal?
    @Published var savedProposals: [AIEqualizerSavedProposal] = []
    @Published var measuredFeatures: AIEqualizerAudioFeatures?
    @Published var appliedProposalID: UUID?
    @Published var samplingStage: AIEqualizerSamplingStage = .preparing
    @Published var generationStage: AIEqualizerGenerationStage = .preparing
    @Published var tuningStartedAt: Date?
    @Published var generationStartedAt: Date?
    @Published var currentLearningFeedback: AIEqualizerLearningFeedback?
    @Published var learningEvidenceCount = 0
    @Published var learningRecords: [AIEqualizerLearningRecord] = []
    @Published var adaptiveLearningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adaptiveLearningEnabled, forKey: Self.adaptiveLearningKey)
            if !adaptiveLearningEnabled {
                discardPendingManualEqualizerLearning()
                activeLearningSession = nil
                currentLearningFeedback = nil
            }
            AppLogger.info(
                "[AIEqualizerAgent] Adaptive learning enabled=\(adaptiveLearningEnabled)",
                step: "ai-tuning.learning-toggle"
            )
        }
    }
    @Published var learnsFromExplicitFeedback: Bool {
        didSet {
            UserDefaults.standard.set(
                learnsFromExplicitFeedback,
                forKey: Self.learnsFromExplicitFeedbackKey
            )
        }
    }
    @Published var learnsFromListeningBehavior: Bool {
        didSet {
            UserDefaults.standard.set(
                learnsFromListeningBehavior,
                forKey: Self.learnsFromListeningBehaviorKey
            )
        }
    }
    @Published var learnsFromAdjustmentActions: Bool {
        didSet {
            UserDefaults.standard.set(
                learnsFromAdjustmentActions,
                forKey: Self.learnsFromAdjustmentActionsKey
            )
            if !learnsFromAdjustmentActions {
                discardPendingManualEqualizerLearning()
            }
        }
    }
    @Published var learningStrength: AIEqualizerLearningStrength {
        didSet {
            UserDefaults.standard.set(learningStrength.rawValue, forKey: Self.learningStrengthKey)
        }
    }
    @Published var learningRetention: AIEqualizerLearningRetention {
        didSet {
            UserDefaults.standard.set(learningRetention.rawValue, forKey: Self.learningRetentionKey)
            learningStore.setRetentionDays(learningRetention.days)
            refreshLearningRecords()
        }
    }
    @Published var tuningIntensity: AIEqualizerTuningIntensity {
        didSet {
            UserDefaults.standard.set(tuningIntensity.rawValue, forKey: Self.tuningIntensityKey)
            AppLogger.info(
                "[AIEqualizerAgent] Tuning intensity changed value=\(tuningIntensity.rawValue)",
                step: "ai-tuning.intensity"
            )
        }
    }
    @Published var tuningProfile: AIEqualizerTuningProfile {
        didSet {
            UserDefaults.standard.set(tuningProfile.rawValue, forKey: Self.tuningProfileKey)
            AppLogger.info(
                "[AIEqualizerAgent] Tuning profile changed value=\(tuningProfile.rawValue)",
                step: "ai-tuning.profile"
            )
        }
    }
    @Published var samplingMode: AIEqualizerSamplingMode {
        didSet { UserDefaults.standard.set(samplingMode.rawValue, forKey: Self.samplingModeKey) }
    }
    @Published var customSamplingDuration: Double {
        didSet {
            let normalized = min(120, max(10, customSamplingDuration))
            UserDefaults.standard.set(normalized, forKey: Self.customSamplingDurationKey)
        }
    }
    @Published var showsPlayerTuningStatus: Bool {
        didSet {
            UserDefaults.standard.set(showsPlayerTuningStatus, forKey: Self.playerStatusKey)
        }
    }
    @Published var automaticConfigurationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticConfigurationEnabled, forKey: Self.autoKey)
            AppLogger.info(
                "[AIEqualizerAgent] Automatic tuning enabled=\(automaticConfigurationEnabled)",
                step: "ai-tuning.automation"
            )
            if automaticConfigurationEnabled {
                scheduleAutomaticAnalysis()
            } else {
                automaticTask?.cancel()
                analysisTask?.cancel()
                automaticRetryTask?.cancel()
                activeAnalysisRunID = nil
                activeAnalysisSongIdentifier = nil
                tuningStartedAt = nil
                scheduledAutomaticRunID = nil
                scheduledAutomaticSongIdentifier = nil
                if phase.isWorking { phase = .idle }
                EQManager.shared.restoreProcessingBeforeAI(reason: "automatic-disabled")
                appliedProposalID = nil
                appliedSongIdentifier = nil
                activeLearningSession = nil
                currentLearningFeedback = nil
            }
        }
    }

    static let autoKey = "ai.eq.agent.auto-configure"
    static let samplingModeKey = "ai.eq.agent.sampling-mode"
    static let tuningIntensityKey = "ai.eq.agent.tuning-intensity"
    static let tuningProfileKey = "ai.eq.agent.tuning-profile"
    static let customSamplingDurationKey = "ai.eq.agent.custom-sampling-duration"
    static let playerStatusKey = "ai.eq.agent.player-status"
    static let adaptiveLearningKey = "ai.eq.agent.adaptive-learning"
    static let learnsFromExplicitFeedbackKey = "ai.eq.agent.learning.explicit-feedback"
    static let learnsFromListeningBehaviorKey = "ai.eq.agent.learning.listening-behavior"
    static let learnsFromAdjustmentActionsKey = "ai.eq.agent.learning.adjustment-actions"
    static let learningStrengthKey = "ai.eq.agent.learning.strength"
    static let learningRetentionKey = "ai.eq.agent.learning.retention-days"
    static let recentProfileNamesKey = "ai.eq.agent.recent-profile-names.v1"
    static let maxSamplingRetryAttempts = 3
    static let maxGenerationRetryAttempts = 3
    let sampler = AIEqualizerFeatureSampler()
    let client = AIProviderClient()
    let tuningServiceStore = AITuningServiceStore.shared
    var isAutomaticTuningActive: Bool { tuningServiceStore.settings.isEnabled && automaticConfigurationEnabled }
    let providerStore = AIProviderConfigurationStore.shared
    let usageLimiter = AIUsageLimiter.shared
    var activePromptVersion: String {
        AppAgentConfigurationStore.cachedAgentConfiguration(.equalizer)?.promptVersion
            ?? AIEqualizerPrompt.version
    }
    var cancellables = Set<AnyCancellable>()
    var analysisTask: Task<Void, Never>?
    var automaticTask: Task<Void, Never>?
    var automaticRetryTask: Task<Void, Never>?
    let proposalCache = AIEqualizerProposalCacheStore()
    let measurementStore = AIEqualizerMeasurementStore()
    let learningStore = AIEqualizerLearningStore()
    var activeAnalysisRunID: UUID?
    var activeAnalysisSongIdentifier: String?
    var scheduledAutomaticRunID: UUID?
    var scheduledAutomaticSongIdentifier: String?
    var appliedSongIdentifier: String?
    var observedSongIdentifier: String?
    var samplingRetryCount: [String: Int] = [:]
    var recentProfileNames: [String] = []
    var discoveredProviderModels: [String: String] = [:]
    var activeLearningSession: AIEqualizerActiveLearningSession?
    var pendingManualEqualizerLearning: AIEqualizerPendingManualAdjustment?
    var manualEqualizerLearningTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        automaticConfigurationEnabled = defaults.bool(forKey: Self.autoKey)
        tuningIntensity = defaults.string(forKey: Self.tuningIntensityKey)
            .flatMap(AIEqualizerTuningIntensity.init(rawValue:)) ?? .smart
        tuningProfile = defaults.string(forKey: Self.tuningProfileKey)
            .flatMap(AIEqualizerTuningProfile.init(rawValue:)) ?? .standard
        samplingMode = defaults.string(forKey: Self.samplingModeKey)
            .flatMap(AIEqualizerSamplingMode.init(rawValue:)) ?? .smart
        let savedDuration = defaults.double(forKey: Self.customSamplingDurationKey)
        customSamplingDuration = savedDuration > 0 ? min(120, max(10, savedDuration)) : 36
        showsPlayerTuningStatus = defaults.object(forKey: Self.playerStatusKey) == nil
            ? true
            : defaults.bool(forKey: Self.playerStatusKey)
        adaptiveLearningEnabled = defaults.object(forKey: Self.adaptiveLearningKey) == nil
            ? true
            : defaults.bool(forKey: Self.adaptiveLearningKey)
        learnsFromExplicitFeedback = defaults.object(forKey: Self.learnsFromExplicitFeedbackKey) == nil
            ? true
            : defaults.bool(forKey: Self.learnsFromExplicitFeedbackKey)
        learnsFromListeningBehavior = defaults.object(forKey: Self.learnsFromListeningBehaviorKey) == nil
            ? true
            : defaults.bool(forKey: Self.learnsFromListeningBehaviorKey)
        learnsFromAdjustmentActions = defaults.object(forKey: Self.learnsFromAdjustmentActionsKey) == nil
            ? true
            : defaults.bool(forKey: Self.learnsFromAdjustmentActionsKey)
        learningStrength = defaults.string(forKey: Self.learningStrengthKey)
            .flatMap(AIEqualizerLearningStrength.init(rawValue:)) ?? .balanced
        learningRetention = AIEqualizerLearningRetention(
            rawValue: defaults.integer(forKey: Self.learningRetentionKey)
        ) ?? .oneYear
        learningStore.setRetentionDays(learningRetention.days)
        tuningServiceStore.changes
            .sink { [weak self] in self?.handleTuningServiceChanged() }
            .store(in: &cancellables)
        AIResonanceUpdateStore.shared.changes
            .sink { [weak self] in
                guard let self, self.tuningServiceStore.settings.service == .resonance else { return }
                self.handleTuningServiceChanged()
            }
            .store(in: &cancellables)
        AIPersonalProviderStore.shared.changes
            .sink { [weak self] in
                guard let self, self.tuningServiceStore.settings.service == .custom else { return }
                self.handleTuningServiceChanged()
            }
            .store(in: &cancellables)

        let player = PlayerManager.shared
        learningStore.hydrateSongMetadata(from: learningSongMetadata(in: player))
        learningEvidenceCount = learningStore.evidenceCount
        learningRecords = learningStore.records
        recentProfileNames = Array(
            (defaults.stringArray(forKey: Self.recentProfileNamesKey) ?? []).suffix(16)
        )
        if !isAutomaticTuningActive {
            EQManager.shared.restoreProcessingBeforeAI(reason: "agent-restored-disabled")
        }

        observedSongIdentifier = player.currentSong.map { "\($0.musicSource.rawValue):\($0.id)" }
        if let observedSongIdentifier {
            savedProposals = proposalCache.history(for: observedSongIdentifier)
        }
        if let song = player.currentSong {
            measuredFeatures = restoredMeasurement(for: song)
        }
        player.$currentSong
            .map { song in
                song.map { "\($0.musicSource.rawValue):\($0.id)" }
            }
            .removeDuplicates()
            .sink { [weak self] identifier in
                guard let self else { return }
                guard self.observedSongIdentifier != identifier else { return }
                self.flushPendingManualEqualizerLearning()
                self.finalizeRetainedLearningSession()
                self.observedSongIdentifier = identifier
                self.analysisTask?.cancel()
                self.automaticTask?.cancel()
                self.automaticRetryTask?.cancel()
                self.activeAnalysisRunID = nil
                self.activeAnalysisSongIdentifier = nil
                self.tuningStartedAt = nil
                self.scheduledAutomaticRunID = nil
                self.scheduledAutomaticSongIdentifier = nil
                if let identifier,
                   self.isAutomaticTuningActive,
                   PlayerManager.shared.currentSong?.isAppleMusic != true {
                    EQManager.shared.prepareForAIAnalysis(songIdentifier: identifier)
                } else {
                    EQManager.shared.restoreProcessingBeforeAI(
                        reason: identifier == nil ? "queue-cleared" : "automatic-inactive"
                    )
                }
                self.proposal = nil
                self.measuredFeatures = PlayerManager.shared.currentSong.flatMap {
                    self.restoredMeasurement(for: $0)
                }
                self.savedProposals = identifier.map { self.proposalCache.history(for: $0) } ?? []
                self.appliedProposalID = nil
                self.appliedSongIdentifier = nil
                self.currentLearningFeedback = nil
                self.samplingRetryCount.removeAll()
                self.samplingStage = .preparing
                self.generationStage = .preparing
                self.phase = .idle
                self.refreshLearningRecords()
            }
            .store(in: &cancellables)

        Publishers.Merge3(
            player.$context.map { _ in () },
            player.$history.map { _ in () },
            player.$podcastHistory.map { _ in () }
        )
        .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.refreshLearningRecords()
        }
        .store(in: &cancellables)

        PlaybackTimePublisher.shared.$currentTime
            .sink { [weak self] position in
                self?.updateLearningPlaybackPosition(position)
            }
            .store(in: &cancellables)

        EQManager.shared.userGraphicGainAdjustments
            .sink { [weak self] adjustment in
                self?.captureManualEqualizerAdjustment(adjustment)
            }
            .store(in: &cancellables)

        player.$currentPlayingURL
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self,
                      !self.phase.isWorking,
                      let song = PlayerManager.shared.currentSong,
                      let restored = self.restoredMeasurement(for: song) else { return }
                self.measuredFeatures = restored
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            player.$currentSong,
            player.$isPlaying.removeDuplicates(),
            player.$isLoading.removeDuplicates()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] readiness in
            let (song, isPlaying, isLoading) = readiness
            guard let self,
                  self.isAutomaticTuningActive,
                  song != nil,
                  isPlaying,
                  !isLoading else { return }
            self.scheduleAutomaticAnalysis()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            EQManager.shared.$currentOutputKind,
            EQManager.shared.$currentOutputName
        )
        .map { output in "\(output.0.rawValue):\(output.1)" }
        .removeDuplicates()
        .dropFirst()
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self,
                  let currentSong = PlayerManager.shared.currentSong else { return }
            self.flushPendingManualEqualizerLearning()
            guard self.isAutomaticTuningActive else {
                self.measuredFeatures = self.restoredMeasurement(for: currentSong)
                return
            }
            self.analysisTask?.cancel()
            self.automaticTask?.cancel()
            self.automaticRetryTask?.cancel()
            self.activeAnalysisRunID = nil
            self.activeAnalysisSongIdentifier = nil
            self.tuningStartedAt = nil
            self.scheduledAutomaticRunID = nil
            self.scheduledAutomaticSongIdentifier = nil
            self.finalizeRetainedLearningSession()
            EQManager.shared.restoreProcessingBeforeAI(reason: "output-changed")
            self.proposal = nil
            self.measuredFeatures = PlayerManager.shared.currentSong.flatMap {
                self.restoredMeasurement(for: $0)
            }
            self.appliedProposalID = nil
            self.appliedSongIdentifier = nil
            self.currentLearningFeedback = nil
            self.samplingRetryCount.removeAll()
            self.phase = .idle
            self.scheduleAutomaticAnalysis()
        }
        .store(in: &cancellables)

        EQManager.shared.$graphicEQMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                self.flushPendingManualEqualizerLearning()
                self.analysisTask?.cancel()
                self.automaticTask?.cancel()
                self.automaticRetryTask?.cancel()
                self.activeAnalysisRunID = nil
                self.activeAnalysisSongIdentifier = nil
                self.tuningStartedAt = nil
                self.scheduledAutomaticRunID = nil
                self.scheduledAutomaticSongIdentifier = nil
                self.finalizeRetainedLearningSession()
                self.proposal = nil
                self.measuredFeatures = PlayerManager.shared.currentSong.flatMap {
                    self.restoredMeasurement(for: $0, graphicEQMode: mode)
                }
                self.appliedProposalID = nil
                self.appliedSongIdentifier = nil
                self.currentLearningFeedback = nil
                self.samplingRetryCount.removeAll()
                self.phase = .idle
                AppLogger.info(
                    "[AIEqualizerAgent] Graphic EQ mode changed bands=\(mode.bandCount)",
                    step: "ai-tuning.eq-mode"
                )
                if self.isAutomaticTuningActive,
                   PlayerManager.shared.currentSong != nil {
                    self.scheduleAutomaticAnalysis()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        analysisTask?.cancel()
        automaticTask?.cancel()
        automaticRetryTask?.cancel()
        manualEqualizerLearningTask?.cancel()
    }

    var isCurrentProposalApplied: Bool {
        guard let proposal else { return false }
        return appliedProposalID == proposal.id
            && EQManager.shared.isActivelyApplyingAIProposal(proposal)
    }

    var applicableSavedProposals: [AIEqualizerSavedProposal] {
        guard let song = PlayerManager.shared.currentSong else { return [] }
        let identifier = songIdentifier(song)
        return savedProposals.filter {
            $0.songIdentifier == identifier
        }
    }

    var hasAnySavedProposals: Bool {
        proposalCache.hasStoredProposals
    }

}
