import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

extension AIEqualizerAgent {
    func resolvedSkillExecutionContext(
        managedAgent: AppAgentConfiguration?
    ) -> (
        runtime: MonoAudioAgentRuntimeSkillConfiguration,
        policy: AppAgentToolPolicyConfiguration,
        fingerprint: String
    ) {
        let runtime = MonoAudioAgentSkillStore.shared.runtimeConfiguration(
            adaptiveLearningEnabled: adaptiveLearningEnabled,
            remoteConfiguration: managedAgent?.resolvedSkillConfiguration,
            remoteToolPolicy: managedAgent?.toolPolicy
        )
        let policy = (runtime.toolPolicy ?? .bundledSafeDefault).resolvedSafePolicy
        let fingerprint = MonoAudioTuningKnowledge.executionFingerprint(
            runtimeFingerprint: runtime.fingerprint,
            runtimeRevision: runtime.revision,
            toolPolicyRevision: policy.revision ?? "bundled-v1"
        )
        return (runtime, policy, fingerprint)
    }

    func restoredMeasurement(
        for song: Song,
        graphicEQMode: GraphicEQMode? = nil
    ) -> AIEqualizerAudioFeatures? {
        measurementStore.value(
            songIdentifier: songIdentifier(song),
            audioVariant: audioVariantIdentity(for: song),
            outputIdentity: currentOutputIdentity(),
            graphicEQMode: graphicEQMode ?? EQManager.shared.graphicEQMode
        )
    }

    func audioVariantIdentity(for song: Song) -> String {
        let player = PlayerManager.shared
        var components = [
            song.musicSource.rawValue,
            "duration:\(song.dt ?? 0)"
        ]
        if let qqMid = song.qqMid, !qqMid.isEmpty {
            components.append("qq:\(qqMid)")
        }
        if let trackID = song.qishuiTrackId {
            components.append("qishui:\(trackID)")
        }
        if let localURL = song.localFileURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path) {
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            components.append("local:\(localURL.lastPathComponent):\(size):\(Int(modified))")
        } else {
            let quality = (player.qualityInfoText ?? player.qualityButtonText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !quality.isEmpty {
                components.append("quality:\(quality)")
            }
            if let input = player.currentPlayingURL,
               let url = URL(string: input),
               !url.lastPathComponent.isEmpty {
                components.append("asset:\(String(url.lastPathComponent.prefix(120)))")
            }
        }
        return components
            .joined(separator: "|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    func isCurrentSong(_ song: Song) -> Bool {
        guard let current = PlayerManager.shared.currentSong else { return false }
        return current.id == song.id && current.musicSource == song.musicSource
    }

    func resolvedSamplingDuration(for song: Song) -> TimeInterval {
        let trackDuration = max(PlayerManager.shared.duration, Double(song.dt ?? 0) / 1_000)
        let requested: TimeInterval
        switch samplingMode {
        case .fast:
            requested = 15
        case .deep:
            requested = 60
        case .custom:
            requested = min(120, max(10, customSamplingDuration))
        case .smart:
            switch trackDuration {
            case 0..<75: requested = 18
            case 75..<180: requested = 28
            case 360...: requested = 45
            default: requested = 36
            }
        }

        let remaining = PlayerManager.shared.duration - PlayerManager.shared.currentTime
        let availableDuration = remaining > 0 ? min(requested, max(8, remaining - 2)) : requested
        return UIScreen.main.isCaptured
            ? min(20, availableDuration)
            : availableDuration
    }

    func resolvedProviderRequestContext(
        usePublishedConfiguration: Bool = true,
        service: AITuningService? = nil
    ) async throws -> AIProviderRequestContext {
        if usePublishedConfiguration, service == .builtIn {
            providerStore.refreshRemoteConfigurationInBackgroundIfNeeded()
        }
        var context = try service.map { try providerStore.tuningRequestContext(service: $0) }
            ?? providerStore.requestContext(usePublishedConfiguration: usePublishedConfiguration)
        let configuration = context.configuration
        let apiKey = context.apiKey
        if configuration.wireProtocol.requiresAPIKey,
           apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIEqualizerError.missingAPIKey
        }

        let configuredModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuredModel.isEmpty,
              configuration.wireProtocol != .appleIntelligence else {
            return context
        }

        let modelCacheKey = providerModelCacheKey(configuration: configuration, apiKey: apiKey)
        if let cachedModel = discoveredProviderModels[modelCacheKey] {
            context.configuration.model = cachedModel
            AppLogger.info(
                "[AIEqualizerAgent] Reused discovered provider model protocol=\(configuration.wireProtocol.rawValue) model=\(cachedModel)",
                step: "ai-tuning.model-cache"
            )
            if context.persistsDiscoveredModel, providerStore.configuration == configuration {
                providerStore.model = cachedModel
            }
            return context
        }

        let models = try await client.fetchModels(
            configuration: configuration,
            apiKey: apiKey
        )
        let preferred = configuration.wireProtocol.defaultModel
        guard let selected = models.contains(preferred) ? preferred : models.first else {
            throw AIEqualizerError.modelUnavailable
        }
        discoveredProviderModels[modelCacheKey] = selected
        AppLogger.info(
            "[AIEqualizerAgent] Cached discovered provider model protocol=\(configuration.wireProtocol.rawValue) model=\(selected)",
            step: "ai-tuning.model-cache"
        )
        context.configuration.model = selected
        if context.persistsDiscoveredModel, providerStore.configuration == configuration {
            providerStore.model = selected
        }
        return context
    }

    func providerModelCacheKey(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) -> String {
        [
            configuration.wireProtocol.rawValue,
            configuration.resolvedBaseURL,
            configuration.modelDiscoveryURL,
            String(apiKey.hashValue)
        ].joined(separator: "|")
    }

    func decodeModelOutput(
        from rawText: String,
        expectedMode: GraphicEQMode
    ) throws -> AIEqualizerModelOutput {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let containsClosingBrace = text.lastIndex(of: "}") != nil
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first <= last {
            text = String(text[first...last])
        }

        guard let data = text.data(using: .utf8) else {
            AppLogger.error(
                "[AIEqualizerAgent] Model response is not UTF-8 characters=\(text.count)",
                step: "ai-tuning.response-invalid"
            )
            throw AIEqualizerError.invalidResponse
        }

        let output: AIEqualizerModelOutput
        do {
            output = try JSONDecoder().decode(AIEqualizerModelOutput.self, from: data)
        } catch {
            let preview = Self.responsePreview(text)
            AppLogger.error(
                "[AIEqualizerAgent] Model JSON decode failed characters=\(text.count) closingBrace=\(containsClosingBrace) expectedBands=\(expectedMode.bandCount) decoding=\(Self.decodingErrorDescription(error)) response=\(preview)",
                step: "ai-tuning.response-invalid"
            )
            throw AIEqualizerError.invalidResponse
        }

        guard output.gains.count == expectedMode.bandCount else {
            AppLogger.error(
                "[AIEqualizerAgent] Model returned wrong EQ band count expected=\(expectedMode.bandCount) actual=\(output.gains.count)",
                step: "ai-tuning.response-invalid"
            )
            throw AIEqualizerError.invalidResponse
        }
        guard output.gains.allSatisfy({ $0.isFinite }),
              output.preampDB.isFinite,
              output.confidence.isFinite else {
            AppLogger.error(
                "[AIEqualizerAgent] Model returned non-finite tuning parameters bands=\(output.gains.count) preamp=\(output.preampDB) confidence=\(output.confidence)",
                step: "ai-tuning.response-invalid"
            )
            throw AIEqualizerError.invalidResponse
        }
        return output
    }

    static func responsePreview(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        guard compact.count > 1_200 else { return compact }
        return "\(compact.prefix(800)) … \(compact.suffix(400))"
    }

    static func decodingErrorDescription(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case let .keyNotFound(key, context):
            return "missing key \(key.stringValue) at \(codingPath(context.codingPath))"
        case let .typeMismatch(type, context):
            return "type mismatch \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "missing value \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "corrupted data at \(codingPath(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "<root>" : value
    }
}
