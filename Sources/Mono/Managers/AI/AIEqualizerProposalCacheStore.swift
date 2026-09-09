import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit


/// A malformed or obsolete persisted entry must not make sibling entries
/// undecodable. The durable proposal model supplies migration defaults; this
/// wrapper contains damage when an individual record is genuinely corrupt.
struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

@MainActor
final class AIEqualizerProposalCacheStore {
    nonisolated private static let trainingSampleFileName = "AIEqualizerTrainingSamples-v2.json"
    nonisolated private static let trainingSampleWriteQueue = DispatchQueue(
        label: "com.monologue.ai-training-sample-archive", qos: .utility
    )
    private static let maximumAge: TimeInterval = 45 * 24 * 60 * 60

    private var values: [String: AIEqualizerProposal]
    private var histories: [String: [AIEqualizerSavedProposal]]
    private var trainingSamples: [String: CloudAIEqualizerTrainingSample]

    init() {
        values = Self.restoreCachedProposals()
        histories = Self.restoreSavedProposalHistory()
        trainingSamples = Self.restoreTrainingSamples()
        removeExpiredEntries()
        pruneTrainingSamples()
        AITrainingSampleUploader.shared.attach(sampleSource: self)
    }

    func trainingSamples(withIDs ids: Set<String>) -> [String: CloudAIEqualizerTrainingSample] {
        var result: [String: CloudAIEqualizerTrainingSample] = [:]
        for id in ids {
            if let sample = trainingSamples[id] {
                result[id] = sample
            }
        }
        return result
    }

    /// Keeps the newest `limit` samples plus anything still waiting for upload;
    /// everything older has already reached the cloud and is not needed locally.
    func pruneUploadedTrainingSamples(keeping limit: Int, protecting pendingIDs: Set<String>) {
        guard trainingSamples.count > limit else { return }
        let ordered = trainingSamples.values.sorted {
            ($0.outcomeUpdatedAt ?? $0.capturedAt) > ($1.outcomeUpdatedAt ?? $1.capturedAt)
        }
        var keep = Set(ordered.prefix(limit).map { $0.id.uuidString.lowercased() })
        keep.formUnion(pendingIDs)
        let before = trainingSamples.count
        trainingSamples = trainingSamples.filter { keep.contains($0.key) }
        if trainingSamples.count != before {
            persistTrainingSamples()
        }
    }

    func value(
        for key: String,
        agentVersion: String,
        skillFingerprint: String,
        skillRevision: String,
        now: Date = Date()
    ) -> AIEqualizerProposal? {
        guard let value = values[key] else { return nil }
        guard now.timeIntervalSince(value.createdAt) <= Self.maximumAge else {
            values.removeValue(forKey: key)
            persist()
            return nil
        }
        guard value.agentVersion == agentVersion,
              value.skillFingerprint == skillFingerprint,
              value.skillRevision == skillRevision,
              Self.hasCurrentSkillCompliance(value) else {
            return nil
        }
        return value
    }

    func set(_ value: AIEqualizerProposal, for key: String) {
        values[key] = value
        removeExpiredEntries()
        persist()
    }

    func record(
        _ proposal: AIEqualizerProposal,
        songIdentifier: String,
        outputIdentity: String
    ) {
        let entry = AIEqualizerSavedProposal(
            proposal: proposal,
            songIdentifier: songIdentifier,
            outputIdentity: outputIdentity
        )
        var entries = histories[songIdentifier] ?? []
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        histories[songIdentifier] = entries.sorted {
            $0.proposal.createdAt > $1.proposal.createdAt
        }
        persistHistory()
    }

    func recordTrainingSample(
        proposal: AIEqualizerProposal,
        features: AIEqualizerAudioFeatures,
        songIdentifier: String,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?,
        deviceTrainingContext: AIEqualizerDeviceTrainingContext? = nil,
        populationTarget: AIEqualizerProposal? = nil,
        learningContext: AIEqualizerLearningContext? = nil,
        personalizedTarget: AIEqualizerProposal? = nil
    ) {
        guard Self.isSelfGenerated(proposal) || histories[songIdentifier, default: []].contains(where: {
            $0.proposal.id == proposal.id
        }) else {
            return
        }
        guard proposal.skillCompliance?.accepted == true,
              proposal.skillCompliance?.localValidationApplied == true else {
            return
        }
        // Retain the measurement locally so a later human edit can be paired
        // with what was heard. Unreviewed local predictions are not uploaded.
        let sample = CloudAIEqualizerTrainingSample(
            proposal: proposal,
            features: features,
            songIdentifier: songIdentifier,
            deviceTuningTarget: deviceTuningTarget,
            deviceTrainingContext: deviceTrainingContext,
            populationTarget: populationTarget,
            learningContext: learningContext,
            personalizedTarget: personalizedTarget
        )
        trainingSamples[proposal.id.uuidString.lowercased()] = sample
        pruneTrainingSamples()
        persistTrainingSamples()
        if Self.isUploadEligible(sample) {
            AITrainingSampleUploader.shared.enqueue(sampleID: proposal.id)
        }
    }

    func shouldRecord(
        _ proposal: AIEqualizerProposal,
        songIdentifier: String,
        outputIdentity: String
    ) -> Bool {
        guard let previous = histories[songIdentifier]?
            .sorted(by: { $0.proposal.createdAt > $1.proposal.createdAt })
            .first(where: {
                $0.outputIdentity == outputIdentity
                    && $0.proposal.graphicEQMode == proposal.graphicEQMode
                    && ($0.proposal.tuningIntensity ?? .smart) == (proposal.tuningIntensity ?? .smart)
                    && ($0.proposal.tuningProfile ?? .standard) == (proposal.tuningProfile ?? .standard)
                    && $0.proposal.provider == proposal.provider
                    && $0.proposal.model == proposal.model
                    && $0.proposal.agentVersion == proposal.agentVersion
                    && $0.proposal.skillFingerprint == proposal.skillFingerprint
                    && $0.proposal.skillRevision == proposal.skillRevision
                    && Self.hasCurrentSkillCompliance($0.proposal)
            }) else {
            return true
        }
        return Self.hasMeaningfulDifference(proposal, previous.proposal)
    }

    func recordTrainingOutcome(
        proposalID: UUID,
        feedback: AIEqualizerLearningFeedback,
        listenedSeconds: TimeInterval,
        manualGainsDB: [Float]? = nil,
        now: Date = Date()
    ) {
        let key = proposalID.uuidString.lowercased()
        guard var sample = trainingSamples[key] else { return }
        if sample.feedback == .manualEqualizer, sample.manualGainsDB != nil,
           feedback == .positive || feedback == .retained {
            return
        }
        sample.feedback = feedback
        sample.listenedSeconds = max(0, listenedSeconds)
        sample.outcomeUpdatedAt = now
        // The listener's final curve is the label a manual edit actually
        // carries; the trainer uses it as a delta against the heard proposal.
        if feedback == .manualEqualizer,
           let manualGainsDB,
           manualGainsDB.count == sample.target.gains.count,
           manualGainsDB.allSatisfy(\.isFinite) {
            sample.manualGainsDB = manualGainsDB
        } else if feedback != .manualEqualizer && feedback != .negative
                    && feedback != .reset && feedback != .regenerated {
            sample.manualGainsDB = nil
        }
        trainingSamples[key] = sample
        persistTrainingSamples()
        if Self.isUploadEligible(sample) {
            AITrainingSampleUploader.shared.enqueue(sampleID: proposalID)
        }
    }

    static func isUploadEligible(_ sample: CloudAIEqualizerTrainingSample) -> Bool {
        guard isSelfGenerated(sample.target) else { return true }
        guard sample.feedback == .manualEqualizer || sample.feedback == .negative
                || sample.feedback == .reset || sample.feedback == .regenerated,
              let gains = sample.manualGainsDB,
              gains.count == sample.target.gains.count,
              gains.allSatisfy(\.isFinite),
              sample.target.gains.allSatisfy(\.isFinite) else { return false }
        return zip(gains, sample.target.gains).contains { abs($0 - $1) > 0.05 }
    }

    static func isSelfGenerated(_ proposal: AIEqualizerProposal) -> Bool {
        if proposal.model.hasPrefix("mono-resonance-") || proposal.model.hasPrefix("mono-audio-") {
            return true
        }
        switch proposal.skillCompliance?.executionMode {
        case .trainedCoreMLModel, .appleIntelligenceLocalCompiler:
            return true
        case .requiredModelTool, .modelPromptFallback, .none:
            return proposal.provider == .appleIntelligence
        }
    }

    func history(for songIdentifier: String, now: Date = Date()) -> [AIEqualizerSavedProposal] {
        removeExpiredEntries(now: now)
        return histories[songIdentifier, default: []]
            .sorted { $0.proposal.createdAt > $1.proposal.createdAt }
    }

    func delete(_ entry: AIEqualizerSavedProposal, for songIdentifier: String) {
        histories[songIdentifier]?.removeAll { $0.id == entry.id }
        if histories[songIdentifier]?.isEmpty == true {
            histories.removeValue(forKey: songIdentifier)
        }
        values = values.filter { $0.value.id != entry.id }
        trainingSamples.removeValue(forKey: entry.id.uuidString.lowercased())
        AITrainingSampleUploader.shared.forget(sampleIDs: [entry.id])
        persist()
        persistHistory()
        persistTrainingSamples()
    }

    func deleteAll(for songIdentifier: String) {
        let ids = Set(histories[songIdentifier, default: []].map(\.id))
        histories.removeValue(forKey: songIdentifier)
        values = values.filter { !ids.contains($0.value.id) }
        trainingSamples = trainingSamples.filter { !ids.contains($0.value.id) }
        AITrainingSampleUploader.shared.forget(sampleIDs: Array(ids))
        persist()
        persistHistory()
        persistTrainingSamples()
    }

    var hasStoredProposals: Bool {
        !values.isEmpty || !histories.isEmpty
    }

    func deleteAll() {
        values.removeAll()
        histories.removeAll()
        trainingSamples.removeAll()
        AITrainingSampleUploader.shared.forgetAll()
        persist()
        persistHistory()
        persistTrainingSamples()
    }

    /// Protocol v6: complete samples travel through the dedicated training
    /// intake, so the snapshot only carries proposals. Samples embedded by older
    /// clients are preserved server-side and still merged on restore.
    func makeCloudSnapshot() -> CloudAIEqualizerSnapshot? {
        removeExpiredEntries()
        guard !values.isEmpty || !histories.isEmpty else { return nil }
        return CloudAIEqualizerSnapshot(
            cachedProposals: values,
            savedProposals: histories,
            trainingSamples: nil
        )
    }

    func mergeCloudSnapshot(_ snapshot: CloudAIEqualizerSnapshot) {
        for (key, proposal) in snapshot.cachedProposals {
            if let local = values[key], local.createdAt >= proposal.createdAt {
                continue
            }
            values[key] = proposal
        }

        for (songIdentifier, remoteEntries) in snapshot.savedProposals {
            let localEntries = histories[songIdentifier, default: []]
            let merged = Dictionary(
                (localEntries + remoteEntries).map { ($0.id, $0) },
                uniquingKeysWith: { current, candidate in
                    current.proposal.createdAt >= candidate.proposal.createdAt ? current : candidate
                }
            )
            histories[songIdentifier] = merged.values.sorted {
                $0.proposal.createdAt > $1.proposal.createdAt
            }
        }

        for (key, sample) in snapshot.trainingSamples ?? [:] {
            guard Self.isSupportedTrainingSampleVersion(sample.schemaVersion) else {
                continue
            }
            let normalizedKey = sample.id.uuidString.lowercased()
            let local = trainingSamples[normalizedKey] ?? trainingSamples[key]
            let remoteFreshness = sample.outcomeUpdatedAt ?? sample.capturedAt
            let localFreshness = local.map { $0.outcomeUpdatedAt ?? $0.capturedAt }
            if let localFreshness, localFreshness >= remoteFreshness {
                continue
            }
            trainingSamples[normalizedKey] = sample
        }

        removeExpiredEntries()
        pruneTrainingSamples()
        persist()
        persistHistory()
        persistTrainingSamples()
    }

    private func pruneTrainingSamples() {
        trainingSamples = trainingSamples.filter {
            Self.isSupportedTrainingSampleVersion($0.value.schemaVersion)
                && $0.value.target.id == $0.value.id
        }
        let pendingReview = trainingSamples.values.filter {
            Self.isSelfGenerated($0.target) && !Self.isUploadEligible($0)
        }.sorted { $0.capturedAt > $1.capturedAt }
        for sample in pendingReview.dropFirst(200) {
            trainingSamples.removeValue(forKey: sample.id.uuidString.lowercased())
        }
    }

    private static func isSupportedTrainingSampleVersion(_ version: Int) -> Bool {
        (1...CloudAIEqualizerTrainingSample.currentSchemaVersion).contains(version)
    }

    private func removeExpiredEntries(now: Date = Date()) {
        let originalValueCount = values.count
        values = values.filter { now.timeIntervalSince($0.value.createdAt) <= Self.maximumAge }
        if values.count != originalValueCount {
            persist()
        }
    }

    private static func hasMeaningfulDifference(
        _ current: AIEqualizerProposal,
        _ previous: AIEqualizerProposal
    ) -> Bool {
        guard current.graphicEQMode == previous.graphicEQMode else { return true }

        let bandDeltas = zip(current.gains, previous.gains).map { abs($0 - $1) }
        let changedBandCount = bandDeltas.filter { $0 >= 0.35 }.count
        if (bandDeltas.max() ?? 0) >= 0.55 || changedBandCount >= 2 {
            return true
        }

        if abs(current.preampDB - previous.preampDB) >= 0.4
            || abs(current.tone.bassGain - previous.tone.bassGain) >= 0.4
            || abs(current.tone.trebleGain - previous.tone.trebleGain) >= 0.4
            || abs(current.spatial.surroundLevel - previous.spatial.surroundLevel) >= 0.06
            || abs(current.spatial.reverbLevel - previous.spatial.reverbLevel) >= 0.06
            || abs(current.spatial.stereoWidth - previous.spatial.stereoWidth) >= 0.05
            || abs(current.professional.processingIntensity - previous.professional.processingIntensity) >= 0.06 {
            return true
        }

        let enhanceDeltas = [
            abs(current.enhance.transientAttack - previous.enhance.transientAttack),
            abs(current.enhance.transientSustain - previous.enhance.transientSustain),
            abs(current.enhance.vocalFocus - previous.enhance.vocalFocus),
            abs(current.enhance.airAmount - previous.enhance.airAmount),
            abs(current.enhance.deEssAmount - previous.enhance.deEssAmount),
            abs(current.enhance.lowFrequencyFocus - previous.enhance.lowFrequencyFocus),
            abs(current.enhance.stageWidth - previous.enhance.stageWidth),
            abs(current.enhance.microDynamics - previous.enhance.microDynamics),
            abs(current.enhance.lowLevelCompensation - previous.enhance.lowLevelCompensation)
        ]
        if current.enhance.isEnabled != previous.enhance.isEnabled
            || (enhanceDeltas.max() ?? 0) >= 0.05
            || current.calibration != previous.calibration
            || current.professional.dynamicEQ.enabled != previous.professional.dynamicEQ.enabled
            || current.professional.multiband.enabled != previous.professional.multiband.enabled
            || current.professional.parametricEQ.enabled != previous.professional.parametricEQ.enabled {
            return true
        }

        let currentEffects = current.effects
        let previousEffects = previous.effects
        if currentEffects.loudnessNormalizationEnabled != previousEffects.loudnessNormalizationEnabled
            || currentEffects.compressorEnabled != previousEffects.compressorEnabled
            || currentEffects.subboostEnabled != previousEffects.subboostEnabled
            || currentEffects.virtualBassEnabled != previousEffects.virtualBassEnabled
            || currentEffects.bs2bEnabled != previousEffects.bs2bEnabled
            || currentEffects.crossfeedEnabled != previousEffects.crossfeedEnabled
            || currentEffects.haasEnabled != previousEffects.haasEnabled
            || currentEffects.exciterEnabled != previousEffects.exciterEnabled
            || currentEffects.softclipEnabled != previousEffects.softclipEnabled
            || currentEffects.finalLimiterEnabled != previousEffects.finalLimiterEnabled {
            return true
        }

        return abs(currentEffects.subboostGainDB - previousEffects.subboostGainDB) >= 0.5
            || abs(currentEffects.exciterAmountDB - previousEffects.exciterAmountDB) >= 0.5
            || abs(currentEffects.finalLimiterCeilingDB - previousEffects.finalLimiterCeilingDB) >= 0.5
    }

    private static func hasCurrentSkillCompliance(
        _ proposal: AIEqualizerProposal
    ) -> Bool {
        guard let compliance = proposal.skillCompliance,
              compliance.accepted,
              compliance.knowledgeVersion == MonoAudioTuningKnowledge.version,
              compliance.toolVersion == MonoAudioTuningTool.version,
              compliance.checkedRuleCount >= MonoAudioTuningKnowledge.enforcedRuleCount,
              compliance.localValidationApplied,
              Set(compliance.requiredSkillIDs).isSubset(of: Set(compliance.enabledSkillIDs)) else {
            return false
        }
        switch compliance.executionMode {
        case .requiredModelTool:
            return proposal.provider != .appleIntelligence
                && compliance.modelToolInvocationCount == 1
        case .modelPromptFallback:
            return proposal.provider != .appleIntelligence
                && compliance.modelToolInvocationCount == 0
        case .appleIntelligenceLocalCompiler:
            return proposal.provider == .appleIntelligence
                && compliance.modelToolInvocationCount == 1
        case .trainedCoreMLModel:
            return proposal.provider == .appleIntelligence
                && compliance.modelToolInvocationCount == 1
        }
    }

    private static func restoreCachedProposals() -> [String: AIEqualizerProposal] {
        do {
            guard let decoded = try PreferenceDataArchive.shared.load(
                [String: LossyDecodable<AIEqualizerProposal>].self,
                for: .equalizerProposals
            ) else { return [:] }
            let restored = decoded.compactMapValues(\.value)
            if restored.count != decoded.count {
                AppLogger.warning(
                    "[AIEqualizerAgent] Skipped \(decoded.count - restored.count) corrupt cached proposals while preserving \(restored.count)",
                    step: "ai-tuning.proposal-restore"
                )
            }
            return restored
        } catch {
            AppLogger.error(
                "[AIEqualizerAgent] Cached proposal archive could not be decoded; original data was left untouched error=\(error.localizedDescription)",
                step: "ai-tuning.proposal-restore-failed"
            )
            return [:]
        }
    }

    private static func restoreSavedProposalHistory() -> [String: [AIEqualizerSavedProposal]] {
        do {
            guard let decoded = try PreferenceDataArchive.shared.load(
                [String: [LossyDecodable<AIEqualizerSavedProposal>]].self,
                for: .equalizerProposalHistory
            ) else { return [:] }
            var skippedCount = 0
            let restored = decoded.reduce(
                into: [String: [AIEqualizerSavedProposal]]()
            ) { result, item in
                let entries = item.value.compactMap(\.value)
                skippedCount += item.value.count - entries.count
                if !entries.isEmpty {
                    result[item.key] = entries
                }
            }
            if skippedCount > 0 {
                let restoredCount = restored.values.reduce(0) { $0 + $1.count }
                AppLogger.warning(
                    "[AIEqualizerAgent] Skipped \(skippedCount) corrupt saved proposals while preserving \(restoredCount)",
                    step: "ai-tuning.proposal-history-restore"
                )
            }
            return restored
        } catch {
            AppLogger.error(
                "[AIEqualizerAgent] Saved proposal archive could not be decoded; original data was left untouched error=\(error.localizedDescription)",
                step: "ai-tuning.proposal-history-restore-failed"
            )
            return [:]
        }
    }

    private static func restoreTrainingSamples() -> [String: CloudAIEqualizerTrainingSample] {
        guard let storageURL = trainingSampleStorageURL,
              let data = try? Data(contentsOf: storageURL) else {
            return [:]
        }
        do {
            let decoded = try JSONDecoder().decode(
                [String: LossyDecodable<CloudAIEqualizerTrainingSample>].self,
                from: data
            )
            return decoded.compactMapValues(\.value)
        } catch {
            AppLogger.error(
                "[AIEqualizerAgent] Training sample archive could not be decoded; original data was left untouched error=\(error.localizedDescription)",
                step: "ai-tuning.training-sample-restore-failed"
            )
            return [:]
        }
    }

    private func persist() {
        PreferenceDataArchive.shared.save(encoding: values, for: .equalizerProposals)
    }

    private func persistHistory() {
        PreferenceDataArchive.shared.save(encoding: histories, for: .equalizerProposalHistory)
    }

    private func persistTrainingSamples() {
        let snapshot = trainingSamples
        Self.trainingSampleWriteQueue.async {
            guard let storageURL = Self.trainingSampleStorageURL else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                AppLogger.error(
                    "[AIEqualizerAgent] Training sample persistence failed entries=\(snapshot.count) domain=\((error as NSError).domain) code=\((error as NSError).code)",
                    step: "ai-tuning.training-sample-save-failed"
                )
            }
        }
    }

    nonisolated static func waitForPendingTrainingSampleWrites() {
        trainingSampleWriteQueue.sync {}
    }

    nonisolated private static var trainingSampleStorageURL: URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = applicationSupport.appendingPathComponent("Mono", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(trainingSampleFileName, isDirectory: false)
        } catch {
            AppLogger.error(
                "[AIEqualizerAgent] Training sample storage directory unavailable error=\(error.localizedDescription)",
                step: "ai-tuning.training-sample-storage-failed"
            )
            return nil
        }
    }
}
