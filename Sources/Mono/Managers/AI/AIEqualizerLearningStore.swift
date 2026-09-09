import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

struct AIEqualizerActiveLearningSession {
    let proposal: AIEqualizerProposal
    let songTitle: String
    let songIdentifier: String
    let artist: String
    let outputIdentity: String
    let outputKind: String
    let genreHints: [String]
    let instrumentHints: [String]
    let startedAt: Date
    let trackDuration: TimeInterval
    var lastPosition: TimeInterval
    var listenedSeconds: TimeInterval
    var hasExplicitFeedback: Bool
}

struct AIEqualizerPendingManualAdjustment {
    let songTitle: String
    let songIdentifier: String
    let artist: String
    let outputIdentity: String
    let outputKind: String
    let graphicEQMode: GraphicEQMode
    let genreHints: [String]
    let instrumentHints: [String]
    let previousGains: [Float]
    var adjustedGains: [Float]
    let bassGain: Float
    let trebleGain: Float
    let surroundLevel: Float
    let reverbLevel: Float
    let stereoWidth: Float
    let processingIntensity: Float
    var changedAt: Date
}

struct AIEqualizerLearningEpisode: Codable, Sendable {
    let schemaVersion: Int
    let proposalID: UUID
    let songTitle: String?
    let songIdentifier: String
    let artist: String
    let outputIdentity: String
    let outputKind: String
    let graphicEQMode: GraphicEQMode
    let genreHints: [String]
    let instrumentHints: [String]
    let gains: [Float]
    let learnedBandAdjustments: [Float]?
    let bassGain: Float
    let trebleGain: Float
    let surroundLevel: Float
    let reverbLevel: Float
    let stereoWidth: Float
    let processingIntensity: Float
    let feedback: AIEqualizerLearningFeedback
    let listenedSeconds: TimeInterval
    let recordedAt: Date
}

struct AIEqualizerLearningArchive: Codable, Sendable {
    var schemaVersion: Int
    var revision: Int
    var episodes: [AIEqualizerLearningEpisode]
}

@MainActor
final class AIEqualizerLearningStore {
    nonisolated private static let writeQueue = DispatchQueue(
        label: "com.monologue.ai-learning-archive", qos: .utility
    )
    private static let schemaVersion = 1
    private static let fileName = "MonoAudioAgentLearning-v1.json"
    private static let maximumEntries = 320

    private let storageURL: URL?
    private var archive: AIEqualizerLearningArchive
    private var retentionDays = AIEqualizerLearningRetention.oneYear.days

    var revision: Int { archive.revision }
    var evidenceCount: Int { archive.episodes.count }
    var records: [AIEqualizerLearningRecord] {
        archive.episodes
            .sorted { $0.recordedAt > $1.recordedAt }
            .map { episode in
                AIEqualizerLearningRecord(
                    id: episode.proposalID,
                    songTitle: episode.songTitle,
                    songIdentifier: episode.songIdentifier,
                    artist: episode.artist,
                    outputIdentity: episode.outputIdentity,
                    outputKind: episode.outputKind,
                    graphicEQMode: episode.graphicEQMode,
                    genreHints: episode.genreHints,
                    instrumentHints: episode.instrumentHints,
                    gains: episode.gains,
                    learnedBandAdjustments: episode.learnedBandAdjustments ?? [],
                    bassGain: episode.bassGain,
                    trebleGain: episode.trebleGain,
                    surroundLevel: episode.surroundLevel,
                    reverbLevel: episode.reverbLevel,
                    stereoWidth: episode.stereoWidth,
                    processingIntensity: episode.processingIntensity,
                    feedback: episode.feedback,
                    listenedSeconds: episode.listenedSeconds,
                    recordedAt: episode.recordedAt
                )
            }
    }

    init() {
        storageURL = Self.makeStorageURL()
        if let storageURL,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(AIEqualizerLearningArchive.self, from: data),
           decoded.schemaVersion == Self.schemaVersion {
            archive = decoded
        } else {
            archive = AIEqualizerLearningArchive(
                schemaVersion: Self.schemaVersion,
                revision: 1,
                episodes: []
            )
        }
        removeExpiredEpisodes()
    }

    func feedback(for proposalID: UUID) -> AIEqualizerLearningFeedback? {
        archive.episodes
            .filter { $0.proposalID == proposalID }
            .max { $0.recordedAt < $1.recordedAt }?
            .feedback
    }

    func setRetentionDays(_ days: Int) {
        retentionDays = max(1, days)
        removeExpiredEpisodes()
    }

    func hydrateSongMetadata(
        from metadataByIdentifier: [String: AIEqualizerLearningSongMetadata]
    ) {
        var changed = false

        archive.episodes = archive.episodes.map { episode in
            let existingTitle = episode.songTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard existingTitle.isEmpty,
                  let metadata = metadataByIdentifier[episode.songIdentifier],
                  !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return episode
            }
            changed = true
            return AIEqualizerLearningEpisode(
                schemaVersion: episode.schemaVersion,
                proposalID: episode.proposalID,
                songTitle: metadata.title,
                songIdentifier: episode.songIdentifier,
                artist: episode.artist.isEmpty ? metadata.artist : episode.artist,
                outputIdentity: episode.outputIdentity,
                outputKind: episode.outputKind,
                graphicEQMode: episode.graphicEQMode,
                genreHints: episode.genreHints,
                instrumentHints: episode.instrumentHints,
                gains: episode.gains,
                learnedBandAdjustments: episode.learnedBandAdjustments,
                bassGain: episode.bassGain,
                trebleGain: episode.trebleGain,
                surroundLevel: episode.surroundLevel,
                reverbLevel: episode.reverbLevel,
                stereoWidth: episode.stereoWidth,
                processingIntensity: episode.processingIntensity,
                feedback: episode.feedback,
                listenedSeconds: episode.listenedSeconds,
                recordedAt: episode.recordedAt
            )
        }

        guard changed else { return }
        archive.revision += 1
        persist()
    }

    func record(
        feedback: AIEqualizerLearningFeedback,
        session: AIEqualizerActiveLearningSession,
        now: Date = Date()
    ) {
        archive.episodes.removeAll { $0.proposalID == session.proposal.id }
        archive.episodes.append(
            AIEqualizerLearningEpisode(
                schemaVersion: Self.schemaVersion,
                proposalID: session.proposal.id,
                songTitle: session.songTitle,
                songIdentifier: session.songIdentifier,
                artist: session.artist,
                outputIdentity: session.outputIdentity,
                outputKind: session.outputKind,
                graphicEQMode: session.proposal.graphicEQMode,
                genreHints: session.genreHints,
                instrumentHints: session.instrumentHints,
                gains: session.proposal.gains,
                learnedBandAdjustments: nil,
                bassGain: session.proposal.tone.bassGain,
                trebleGain: session.proposal.tone.trebleGain,
                surroundLevel: session.proposal.spatial.surroundLevel,
                reverbLevel: session.proposal.spatial.reverbLevel,
                stereoWidth: session.proposal.spatial.stereoWidth,
                processingIntensity: session.proposal.professional.processingIntensity,
                feedback: feedback,
                listenedSeconds: session.listenedSeconds,
                recordedAt: now
            )
        )
        archive.revision += 1
        removeExpiredEpisodes(now: now)
        if archive.episodes.count > Self.maximumEntries {
            archive.episodes = Array(
                archive.episodes
                    .sorted { $0.recordedAt > $1.recordedAt }
                    .prefix(Self.maximumEntries)
            )
        }
        persist()
    }

    func recordManualEqualizerAdjustment(
        _ adjustment: AIEqualizerPendingManualAdjustment
    ) -> Bool {
        let previous = adjustment.graphicEQMode.normalizedGains(adjustment.previousGains)
        let adjusted = adjustment.graphicEQMode.normalizedGains(adjustment.adjustedGains)
        let newOffsets = zip(adjusted, previous).map {
            min(Float(6), max(Float(-6), $0 - $1))
        }
        guard newOffsets.map({ abs($0) }).max() ?? 0 >= 0.08 else { return false }

        let mergeWindow: TimeInterval = 5 * 60
        let mergeIndex = archive.episodes.indices
            .filter { index in
                let episode = archive.episodes[index]
                return episode.feedback == .manualEqualizer
                    && episode.songIdentifier == adjustment.songIdentifier
                    && episode.outputIdentity == adjustment.outputIdentity
                    && episode.graphicEQMode == adjustment.graphicEQMode
                    && adjustment.changedAt.timeIntervalSince(episode.recordedAt) <= mergeWindow
            }
            .max { archive.episodes[$0].recordedAt < archive.episodes[$1].recordedAt }
        let recordID: UUID
        let learnedOffsets: [Float]
        if let mergeIndex {
            let previousEpisode = archive.episodes.remove(at: mergeIndex)
            let existingOffsets = adjustment.graphicEQMode.normalizedGains(
                previousEpisode.learnedBandAdjustments ?? []
            )
            learnedOffsets = zip(existingOffsets, newOffsets).map {
                min(Float(6), max(Float(-6), $0 + $1))
            }
            recordID = previousEpisode.proposalID
        } else {
            learnedOffsets = newOffsets
            recordID = UUID()
        }

        if learnedOffsets.map({ abs($0) }).max() ?? 0 < 0.08 {
            archive.revision += 1
            persist()
            return true
        }

        archive.episodes.append(
            AIEqualizerLearningEpisode(
                schemaVersion: Self.schemaVersion,
                proposalID: recordID,
                songTitle: adjustment.songTitle,
                songIdentifier: adjustment.songIdentifier,
                artist: adjustment.artist,
                outputIdentity: adjustment.outputIdentity,
                outputKind: adjustment.outputKind,
                graphicEQMode: adjustment.graphicEQMode,
                genreHints: adjustment.genreHints,
                instrumentHints: adjustment.instrumentHints,
                gains: adjusted,
                learnedBandAdjustments: learnedOffsets,
                bassGain: adjustment.bassGain,
                trebleGain: adjustment.trebleGain,
                surroundLevel: adjustment.surroundLevel,
                reverbLevel: adjustment.reverbLevel,
                stereoWidth: adjustment.stereoWidth,
                processingIntensity: adjustment.processingIntensity,
                feedback: .manualEqualizer,
                listenedSeconds: 0,
                recordedAt: adjustment.changedAt
            )
        )
        archive.revision += 1
        removeExpiredEpisodes(now: adjustment.changedAt)
        if archive.episodes.count > Self.maximumEntries {
            archive.episodes = Array(
                archive.episodes
                    .sorted { $0.recordedAt > $1.recordedAt }
                    .prefix(Self.maximumEntries)
            )
        }
        persist()
        return true
    }

    func clear() {
        archive.episodes.removeAll()
        archive.revision += 1
        persist()
    }

    func delete(id: UUID) -> Bool {
        let previousCount = archive.episodes.count
        archive.episodes.removeAll { $0.proposalID == id }
        guard archive.episodes.count != previousCount else { return false }
        archive.revision += 1
        persist()
        return true
    }

    func context(
        for features: AIEqualizerAudioFeatures,
        outputIdentity: String,
        strengthScale: Float,
        now: Date = Date()
    ) -> AIEqualizerLearningContext? {
        removeExpiredEpisodes(now: now)
        guard !archive.episodes.isEmpty else {
            return emptyContext(for: features.graphicEQMode)
        }

        let normalizedArtist = Self.normalizedToken(features.artist)
        let currentSongIdentifier = "\(features.source):\(features.songID)"
        let currentGenres = Set(features.genreHints.map(Self.normalizedToken).filter { !$0.isEmpty })
        let currentInstruments = Set(features.instrumentHints.map(Self.normalizedToken).filter { !$0.isEmpty })
        var bandSums = Array(repeating: Float(0), count: features.graphicEQMode.bandCount)
        var bassSum: Float = 0
        var trebleSum: Float = 0
        var surroundSum: Float = 0
        var reverbSum: Float = 0
        var widthSum: Float = 0
        var processingSum: Float = 0
        var normalizer: Float = 0
        var relevantEvidence = 0

        for episode in archive.episodes {
            let age = max(0, now.timeIntervalSince(episode.recordedAt))
            let recency = Float(exp(-age / (120 * 24 * 60 * 60)))
            let outputMatch: Float
            if episode.outputIdentity == outputIdentity {
                outputMatch = 1
            } else if episode.outputKind == features.outputKind {
                outputMatch = 0.62
            } else {
                outputMatch = 0.18
            }

            let episodeArtist = Self.normalizedToken(episode.artist)
            let artistMatch: Float = !normalizedArtist.isEmpty && episodeArtist == normalizedArtist
                ? 1.65
                : 1
            let episodeGenres = Set(episode.genreHints.map(Self.normalizedToken).filter { !$0.isEmpty })
            let genreOverlap = currentGenres.intersection(episodeGenres).count
            let genreMatch = 1 + min(0.5, Float(genreOverlap) * 0.22)
            let episodeInstruments = Set(episode.instrumentHints.map(Self.normalizedToken).filter { !$0.isEmpty })
            let instrumentOverlap = currentInstruments.intersection(episodeInstruments).count
            let instrumentMatch = 1 + min(0.35, Float(instrumentOverlap) * 0.12)
            let songMatch: Float = episode.songIdentifier == currentSongIdentifier ? 1.8 : 1
            let feedbackWeight = Self.feedbackWeight(episode.feedback)
            let weight = feedbackWeight * recency * outputMatch * artistMatch
                * genreMatch * instrumentMatch * songMatch
            guard abs(weight) >= 0.025 else { continue }

            let learnedCurve: [Float]
            if episode.feedback == .manualEqualizer {
                learnedCurve = features.graphicEQMode.resampledGains(
                    episode.learnedBandAdjustments ?? [],
                    from: episode.graphicEQMode
                )
            } else {
                learnedCurve = features.graphicEQMode.resampledGains(
                    episode.gains,
                    from: episode.graphicEQMode
                )
            }
            let average = learnedCurve.reduce(0, +) / Float(max(learnedCurve.count, 1))
            for index in bandSums.indices {
                bandSums[index] += (learnedCurve[index] - average) * weight
            }
            if episode.feedback != .manualEqualizer {
                bassSum += episode.bassGain * weight
                trebleSum += episode.trebleGain * weight
                surroundSum += episode.surroundLevel * weight
                reverbSum += episode.reverbLevel * weight
                widthSum += (episode.stereoWidth - 1) * weight
                processingSum += (episode.processingIntensity - 1) * weight
            }
            normalizer += abs(weight)
            relevantEvidence += 1
        }

        guard normalizer >= 0.12, relevantEvidence > 0 else {
            return emptyContext(for: features.graphicEQMode)
        }
        let confidence = min(Float(0.42), (1 - expf(-normalizer / 2.8)) * 0.42)
        let adaptation = min(0.36, (0.10 + confidence * 0.36) * strengthScale)
        func adjustment(_ sum: Float, limit: Float) -> Float {
            min(limit, max(-limit, (sum / normalizer) * adaptation))
        }

        return AIEqualizerLearningContext(
            revision: archive.revision,
            evidenceCount: relevantEvidence,
            confidence: confidence,
            bandAdjustments: bandSums.map { adjustment($0, limit: 1.25) },
            bassAdjustment: adjustment(bassSum, limit: 1),
            trebleAdjustment: adjustment(trebleSum, limit: 1),
            surroundAdjustment: adjustment(surroundSum, limit: 0.08),
            reverbAdjustment: adjustment(reverbSum, limit: 0.045),
            stereoWidthAdjustment: adjustment(widthSum, limit: 0.06),
            processingIntensityAdjustment: adjustment(processingSum, limit: 0.14)
        )
    }

    private func emptyContext(for mode: GraphicEQMode) -> AIEqualizerLearningContext {
        AIEqualizerLearningContext(
            revision: archive.revision,
            evidenceCount: 0,
            confidence: 0,
            bandAdjustments: Array(repeating: 0, count: mode.bandCount),
            bassAdjustment: 0,
            trebleAdjustment: 0,
            surroundAdjustment: 0,
            reverbAdjustment: 0,
            stereoWidthAdjustment: 0,
            processingIntensityAdjustment: 0
        )
    }

    private func removeExpiredEpisodes(now: Date = Date()) {
        let count = archive.episodes.count
        let maximumAge = TimeInterval(retentionDays) * 24 * 60 * 60
        archive.episodes.removeAll {
            $0.schemaVersion != Self.schemaVersion
                || now.timeIntervalSince($0.recordedAt) > maximumAge
        }
        if archive.episodes.count != count {
            archive.revision += 1
            persist()
        }
    }

    private func persist() {
        guard let storageURL else {
            AppLogger.error(
                "[AIEqualizerAgent] Learning persistence skipped because storage URL is unavailable",
                step: "ai-tuning.learning-save-failed"
            )
            return
        }
        let snapshot = archive
        Self.writeQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                AppLogger.error(
                    "[AIEqualizerAgent] Learning persistence failed evidence=\(snapshot.episodes.count) domain=\((error as NSError).domain) code=\((error as NSError).code)",
                    step: "ai-tuning.learning-save-failed"
                )
            }
        }
    }

    nonisolated static func waitForPendingWrites() {
        writeQueue.sync {}
    }

    private static func feedbackWeight(_ feedback: AIEqualizerLearningFeedback) -> Float {
        switch feedback {
        case .positive: return 1
        case .retained: return 0.28
        case .negative: return -0.72
        case .reset: return -0.48
        case .regenerated: return -0.24
        case .manualEqualizer: return 1.35
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func makeStorageURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent(
            "Mono",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(fileName, isDirectory: false)
        } catch {
            AppLogger.error(
                "[AIEqualizerAgent] Learning storage directory unavailable error=\(error.localizedDescription)",
                step: "ai-tuning.learning-storage-failed"
            )
            return nil
        }
    }
}
