import Foundation
@preconcurrency import Combine
import FFmpegSwiftSDK
import UIKit

extension AIEqualizerAgent {
    func scheduleAutomaticAnalysis() {
        guard isAutomaticTuningActive,
              let scheduledSong = PlayerManager.shared.currentSong,
              !scheduledSong.isAppleMusic else { return }
        let scheduledIdentifier = songIdentifier(scheduledSong)

        if appliedSongIdentifier == scheduledIdentifier,
           EQManager.shared.isAIManagedPresetActive {
            return
        }
        if activeAnalysisSongIdentifier == scheduledIdentifier, phase.isWorking {
            return
        }
        if scheduledAutomaticSongIdentifier == scheduledIdentifier,
           automaticTask != nil {
            return
        }

        automaticTask?.cancel()
        let scheduledRunID = UUID()
        scheduledAutomaticRunID = scheduledRunID
        scheduledAutomaticSongIdentifier = scheduledIdentifier
        AppLogger.debug(
            "[AIEqualizerAgent] Automatic analysis scheduled song=\(scheduledIdentifier)",
            step: "ai-tuning.scheduled"
        )
        automaticTask = Task { [weak self] in
            defer {
                if let self, self.scheduledAutomaticRunID == scheduledRunID {
                    self.automaticTask = nil
                    self.scheduledAutomaticRunID = nil
                    self.scheduledAutomaticSongIdentifier = nil
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch {
                return
            }
            guard let self, self.scheduledAutomaticRunID == scheduledRunID else { return }

            var isPlaybackReady = false
            for _ in 0..<400 {
                guard !Task.isCancelled,
                      self.isAutomaticTuningActive,
                      self.scheduledAutomaticRunID == scheduledRunID,
                      PlayerManager.shared.currentSong.map({ self.songIdentifier($0) }) == scheduledIdentifier else {
                    return
                }
                if PlayerManager.shared.isPlaying,
                   !PlayerManager.shared.isLoading,
                   PlayerManager.shared.streamPlayer.state == .playing {
                    isPlaybackReady = true
                    break
                }
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            guard isPlaybackReady else {
                AppLogger.warning(
                    "[AIEqualizerAgent] Automatic analysis skipped because playback was not ready song=\(scheduledIdentifier)",
                    step: "ai-tuning.waiting-playback"
                )
                return
            }
            AppLogger.info(
                "[AIEqualizerAgent] Playback ready for automatic analysis song=\(scheduledIdentifier)",
                step: "ai-tuning.playback-ready"
            )
            do {
                try await Task.sleep(for: .milliseconds(420))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.scheduledAutomaticRunID == scheduledRunID,
                  PlayerManager.shared.currentSong.map({ self.songIdentifier($0) }) == scheduledIdentifier,
                  PlayerManager.shared.isPlaying,
                  !PlayerManager.shared.isLoading else { return }
            await self.runAnalysis(trigger: .automatic)
        }
    }

    func runAnalysis(
        trigger: AIEqualizerAnalysisTrigger = .manual,
        forceRegeneration: Bool = false,
        preferInstalledModel: Bool = false
    ) async {
        guard tuningServiceStore.settings.isEnabled else {
            if trigger == .manual { phase = .failed(String(localized: "ai_tuning_service_disabled")) }
            return
        }
        guard let song = PlayerManager.shared.currentSong else {
            phase = .failed(AIEqualizerError.noSong.localizedDescription)
            return
        }
        guard !song.isAppleMusic else {
            phase = .failed(
                AIEqualizerError.protectedAudioUnsupported.localizedDescription
            )
            return
        }
        let identifier = songIdentifier(song)
        guard activeAnalysisSongIdentifier == nil else { return }
        let analysisRunID = UUID()
        activeAnalysisRunID = analysisRunID
        activeAnalysisSongIdentifier = identifier
        defer {
            if activeAnalysisRunID == analysisRunID {
                activeAnalysisRunID = nil
                activeAnalysisSongIdentifier = nil
                analysisTask = nil
                tuningStartedAt = nil
            }
        }

        generationStage = .preparing
        phase = .requesting
        let managedAgent = await AppAgentConfigurationStore.shared.agentConfiguration(.equalizer)
        guard !Task.isCancelled, activeAnalysisRunID == analysisRunID, isCurrentSong(song) else { return }
        if let managedAgent, !managedAgent.enabled {
            phase = .failed(AIEqualizerError.modelUnavailable.localizedDescription)
            return
        }
        let skillExecution = resolvedSkillExecutionContext(managedAgent: managedAgent)
        let currentAgentVersion = managedAgent?.promptVersion ?? AIEqualizerPrompt.version

        let requestedIntensity = tuningIntensity
        let requestedProfile = tuningProfile
        let graphicEQMode = EQManager.shared.graphicEQMode
        let deviceTuningTarget = AirPodsExperienceManager.currentAITuningTargetSnapshot()
        let deviceTrainingContext = EQManager.shared.aiEqualizerDeviceTrainingContext(
            deviceTuningTarget: deviceTuningTarget
        )
        let outputIdentity = currentOutputIdentity()
        let onDeviceModelIdentity: String?
        let modelPreparationStartedAt = Date()
        let requestContext: AIProviderRequestContext
        let selectedService = tuningServiceStore.settings.service
        let usesTrainingPreview = preferInstalledModel && AppConfig.DeveloperAccess.hasFullTools
        do {
            if usesTrainingPreview {
                await AudioTrainingOnDeviceModelStore.shared.clearDistributedAuthorization()
                guard let identity = await AudioTrainingOnDeviceModelStore.shared.activeIdentity() else {
                    throw AIResonanceDistributionError.modelUnavailable
                }
                onDeviceModelIdentity = identity
                requestContext = AIProviderRequestContext(
                    configuration: AIProviderConfiguration(
                        wireProtocol: .appleIntelligence, baseURL: "", model: identity,
                        modelDiscoveryURL: "", timeout: 120, customHeadersJSON: "{}"
                    ), apiKey: "", usageLimits: nil, persistsDiscoveredModel: false
                )
            } else if selectedService == .resonance {
                generationStage = .preparingModel
                onDeviceModelIdentity = try await AIResonanceUpdateStore.shared.prepareForTuning()
                try Task.checkCancellation()
                guard activeAnalysisRunID == analysisRunID, isCurrentSong(song) else { return }
                guard let model = AIResonanceUpdateStore.shared.tuningModel else {
                    throw AIResonanceDistributionError.modelUnavailable
                }
                requestContext = AIProviderRequestContext(
                    configuration: AIProviderConfiguration(
                        wireProtocol: .appleIntelligence, baseURL: "", model: onDeviceModelIdentity ?? "",
                        modelDiscoveryURL: "", timeout: 120, customHeadersJSON: "{}"
                    ), apiKey: "", usageLimits: nil, persistsDiscoveredModel: false,
                    requiredDistributedModelIdentity: model.distributionIdentity
                )
            } else {
                onDeviceModelIdentity = nil
                await AudioTrainingOnDeviceModelStore.shared.clearDistributedAuthorization()
                try Task.checkCancellation()
                guard activeAnalysisRunID == analysisRunID, isCurrentSong(song) else { return }
                requestContext = try await resolvedProviderRequestContext(service: selectedService)
            }
        } catch is CancellationError {
            return
        } catch {
            if activeAnalysisRunID == analysisRunID, isCurrentSong(song) {
                phase = .failed(error.localizedDescription)
            }
            return
        }
        let modelPreparationElapsed = Date().timeIntervalSince(modelPreparationStartedAt)
        let configuration = requestContext.configuration
        guard !Task.isCancelled, activeAnalysisRunID == analysisRunID, isCurrentSong(song) else { return }
        let runStartedAt = Date()
        tuningStartedAt = runStartedAt
        let samplingDuration = resolvedSamplingDuration(for: song)
        let samplingDurationText = String(format: "%.1f", samplingDuration)
        AppLogger.info(
            "[AIEqualizerAgent] Analysis prepared songID=\(song.id) mode=\(samplingMode.rawValue) intensity=\(requestedIntensity.rawValue) profile=\(requestedProfile.rawValue) eqBands=\(graphicEQMode.bandCount) target=\(samplingDurationText)s output=\(EQManager.shared.currentOutputName) protocol=\(configuration.wireProtocol.rawValue) model=\(configuration.resolvedModel)",
            step: "ai-tuning.prepare"
        )
        let audioVariant = audioVariantIdentity(for: song)
        let learningRevision = adaptiveLearningEnabled ? learningStore.revision : 0
        let reusableMeasuredFeatures: AIEqualizerAudioFeatures?
        if forceRegeneration {
            reusableMeasuredFeatures = nil
        } else {
            reusableMeasuredFeatures = measurementStore.value(
                songIdentifier: identifier,
                audioVariant: audioVariant,
                outputIdentity: outputIdentity,
                graphicEQMode: graphicEQMode
            )
            if let reusableMeasuredFeatures {
                measuredFeatures = reusableMeasuredFeatures
            }
        }
        let deviceTuningIdentity = deviceTuningTarget?.identifier ?? "device-baseline:none"
        let agentSkillContext = skillExecution.runtime.modelContext
        let traceID = AIAgentTraceStore.shared.begin(
            agentID: "equalizer",
            agentName: "AI 自动调音",
            subject: "\(song.name) · \(song.artistName)",
            provider: configuration.wireProtocol.rawValue,
            model: configuration.resolvedModel
        )
        if let identity = onDeviceModelIdentity {
            AIAgentTraceStore.shared.append(
                traceID,
                category: .conversation,
                stage: .configuration,
                title: "共鸣 · 模型准备",
                detail: "模型配置与本地安装已准备完成，可开始推理。\n模型标识 = \(identity)",
                durationSeconds: modelPreparationElapsed,
                metadata: [
                    "recordType": "local-coreml-preparation",
                    "modelSource": "on-device-coreml",
                    "provider": "Core ML",
                    "model": String(identity.split(separator: ":").first ?? ""),
                    "selection": usesTrainingPreview ? "training-preview" : selectedService.rawValue,
                    "preparationMilliseconds": String(format: "%.3f", modelPreparationElapsed * 1_000)
                ]
            )
        }
        AIAgentTraceStore.shared.append(
            traceID,
            category: .reasoning,
            stage: .configuration,
            title: "任务创建",
            detail: "已确认播放目标、输出设备、均衡器频段与调音模式，开始为当前歌曲准备测量和模型请求。",
            metadata: [
                "songID": String(song.id),
                "source": song.musicSource.rawValue,
                "agentVersion": currentAgentVersion,
                "knowledgeVersion": MonoAudioTuningKnowledge.version,
                "toolVersion": MonoAudioTuningTool.version,
                "provider": configuration.wireProtocol.rawValue,
                "model": configuration.resolvedModel,
                "profile": requestedProfile.rawValue,
                "intensity": requestedIntensity.rawValue,
                "eqBands": String(graphicEQMode.bandCount),
                "eqMode": graphicEQMode.rawValue,
                "output": EQManager.shared.currentOutputName,
                "audioVariant": audioVariant,
                "samplingMode": samplingMode.rawValue,
                "samplingSeconds": samplingDurationText,
                "deviceTuningIdentity": deviceTuningIdentity,
                "learningRevision": String(learningRevision)
            ]
        )
        let enabledCustomSkills = skillExecution.runtime.customSkills.filter(\.isEnabled)
        let skillStore = MonoAudioAgentSkillStore.shared
        let builtInSkillSources = MonoAudioAgentBuiltInSkill.allCases.map { skill in
            let source = skillStore.source(for: skill)?.rawValue ?? "bundled"
            return "\(skill.rawValue)=\(source)"
        }.joined(separator: ",")
        AIAgentTraceStore.shared.append(
            traceID,
            category: .skill,
            stage: .skills,
            title: "加载 Agent 技能",
            detail: agentSkillContext.isEmpty ? "本次没有启用额外技能。" : agentSkillContext,
            metadata: [
                "adaptiveLearning": adaptiveLearningEnabled ? "enabled" : "disabled",
                "configurationSource": MonoAudioAgentSkillStore.shared.configurationSource.rawValue,
                "runtimeFingerprint": skillExecution.runtime.fingerprint,
                "executionFingerprint": skillExecution.fingerprint,
                "revision": skillExecution.runtime.revision,
                "toolPolicyRevision": skillExecution.policy.revision ?? "bundled-v1",
                "toolName": skillExecution.policy.requiredToolName ?? "mono_audio_tuning",
                "invocationMode": skillExecution.policy.invocationMode ?? "required",
                "requireExactlyOnce": (skillExecution.policy.requireExactlyOnce ?? true) ? "true" : "false",
                "localValidationRequired": (skillExecution.policy.localValidationRequired ?? true) ? "true" : "false",
                "allowPromptFallback": (skillExecution.policy.allowPromptFallback ?? false) ? "true" : "false",
                "enabled": skillExecution.runtime.enabledSkillIDs.joined(separator: ","),
                "required": skillExecution.runtime.requiredSkillIDs.joined(separator: ","),
                "builtInSources": builtInSkillSources,
                "customCount": String(enabledCustomSkills.count),
                "customSkills": enabledCustomSkills.map(\.name).joined(separator: ","),
                "customSources": enabledCustomSkills.map(\.source.rawValue).joined(separator: ",")
            ]
        )
        let toolPolicyRevision = skillExecution.policy.revision ?? "bundled-v1"
        let cacheKey = "\(currentAgentVersion)|\(MonoAudioTuningTool.version)|mono-agent-v6|service:\(usesTrainingPreview ? "trainingPreview" : selectedService.rawValue)|provider:\(requestContext.cacheIdentity)|learning:\(learningRevision)|learningStrength:\(learningStrength.rawValue)|skillFingerprint:\(skillExecution.fingerprint)|skillRevision:\(skillExecution.runtime.revision)|toolPolicy:\(toolPolicyRevision)|trainedCoreML:\(onDeviceModelIdentity ?? "none")|\(graphicEQMode.rawValue)|\(song.musicSource.rawValue)|\(song.id)|\(audioVariant)|\(configuration.wireProtocol.rawValue)|\(configuration.resolvedModel)|\(outputIdentity)|\(deviceTuningIdentity)|\(samplingMode.rawValue)|\(Int(samplingDuration.rounded()))|\(requestedIntensity.rawValue)|\(requestedProfile.rawValue)"
        if !forceRegeneration,
           let cached = proposalCache.value(
               for: cacheKey,
               agentVersion: currentAgentVersion,
               skillFingerprint: skillExecution.fingerprint,
               skillRevision: skillExecution.runtime.revision
           ) {
            samplingRetryCount[identifier] = nil
            if proposalCache.shouldRecord(
                cached,
                songIdentifier: identifier,
                outputIdentity: outputIdentity
            ) {
                proposalCache.record(
                    cached,
                    songIdentifier: identifier,
                    outputIdentity: outputIdentity
                )
            }
            savedProposals = proposalCache.history(for: identifier)
            AppLogger.info(
                "[AIEqualizerAgent] Applied cached proposal song=\(identifier) output=\(outputIdentity)",
                step: "ai-tuning.cache-hit"
            )
            recordProfileName(cached.profileName)
            let didApply = apply(
                cached,
                expectedSongIdentifier: identifier,
                expectedOutputIdentity: outputIdentity
            )
            AIAgentTraceStore.shared.append(
                traceID,
                category: .reasoning,
                level: didApply ? .success : .warning,
                stage: .application,
                title: "复用已验证方案",
                detail: (didApply
                    ? "当前歌曲、音源版本、输出设备、调音模式和技能版本均与缓存一致，已直接写入播放 DSP。"
                    : "缓存方案本身有效，但播放目标或均衡器模式已变化，因此没有写入当前 DSP。")
                    + "\n\n"
                    + traceJSON(cached)
                    + (didApply ? "\n\nDSP 参数与 SDK 回读\n" + traceJSON(EQManager.shared.currentDSPDiagnosticSnapshot()) : ""),
                metadata: [
                    "recordType": "cached-tuning-result",
                    "modelSource": "validated-cache",
                    "provider": cached.provider.rawValue,
                    "model": cached.model,
                    "result": didApply ? "applied" : "skipped-context-changed",
                    "cacheReused": "true",
                    "proposalID": cached.id.uuidString,
                    "profile": cached.profileName,
                    "bands": String(cached.gains.count),
                    "preampDB": String(format: "%.2f", cached.preampDB),
                    "confidence": cached.confidenceDisplayText,
                    "knowledgeVersion": cached.skillCompliance?.knowledgeVersion ?? "",
                    "toolVersion": cached.skillCompliance?.toolVersion ?? "",
                    "checkedRuleCount": String(cached.skillCompliance?.checkedRuleCount ?? 0),
                    "warningCodes": cached.skillCompliance?.warningCodes.joined(separator: ",") ?? "",
                    "output": EQManager.shared.currentOutputName,
                    "eqMode": cached.graphicEQMode.rawValue
                ]
            )
            if didApply {
                proposal = cached
                AIAgentTraceStore.shared.finish(traceID, status: .completed)
            } else {
                AIAgentTraceStore.shared.finish(
                    traceID,
                    status: .cancelled,
                    message: String(localized: "agent_trace_dsp_context_changed")
                )
            }
            return
        }
        do {
            let samplingStartedAt = Date()
            let features: AIEqualizerAudioFeatures
            let samplingElapsed: TimeInterval
            if let reusableMeasuredFeatures {
                samplingStage = .finalizing
                phase = .sampling(progress: 1)
                features = reusableMeasuredFeatures
                samplingElapsed = 0
                AppLogger.info(
                    "[AIEqualizerAgent] Reused measured features song=\(identifier) variant=\(audioVariant) output=\(outputIdentity) mode=\(graphicEQMode.rawValue) frames=\(features.frameCount)",
                    step: "ai-tuning.measurement-reuse"
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    stage: .measurement,
                    title: "复用音频测量",
                    detail: "当前音频版本与输出环境已有可靠测量，直接用于本次调音。",
                    metadata: [
                        "frames": String(features.frameCount),
                        "sampleSeconds": String(format: "%.2f", features.sampleDuration)
                    ]
                )
            } else {
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    stage: .measurement,
                    title: "采集音频特征",
                    detail: "开始采样响度、频谱、峰值、动态与相位兼容性等可验证特征。",
                    metadata: ["targetSeconds": samplingDurationText]
                )
                samplingStage = .preparing
                phase = .sampling(progress: 0)
                features = try await sampler.sample(
                    song: song,
                    duration: samplingDuration,
                    graphicEQMode: graphicEQMode
                ) { [weak self] value, stage in
                    self?.samplingStage = stage
                    self?.phase = .sampling(progress: value)
                }
                samplingElapsed = Date().timeIntervalSince(samplingStartedAt)
            }
            try Task.checkCancellation()
            guard isCurrentSong(song), EQManager.shared.graphicEQMode == graphicEQMode else {
                throw AIEqualizerError.noSong
            }

            if reusableMeasuredFeatures == nil {
                measurementStore.set(
                    features,
                    songIdentifier: identifier,
                    audioVariant: audioVariant,
                    outputIdentity: outputIdentity
                )
                AppLogger.success(
                    "[AIEqualizerAgent] Measurement persisted song=\(identifier) variant=\(audioVariant) output=\(outputIdentity) mode=\(graphicEQMode.rawValue) frames=\(features.frameCount)",
                    step: "ai-tuning.measurement-saved"
                )
            }
            measuredFeatures = features
            AIAgentTraceStore.shared.append(
                traceID,
                category: .reasoning,
                level: .success,
                stage: .measurement,
                title: "测量完成",
                detail: "已生成模型可用的结构化音频证据，下一步提交调音请求。",
                durationSeconds: samplingElapsed,
                metadata: [
                    "frames": String(features.frameCount),
                    "sampleSeconds": String(format: "%.2f", features.sampleDuration),
                    "truePeakDBTP": String(format: "%.2f", features.estimatedTruePeakDBTP),
                    "phaseCorrelation": String(format: "%.3f", features.phaseCorrelation)
                ]
            )
            let learningContext = adaptiveLearningEnabled
                ? learningStore.context(
                    for: features,
                    outputIdentity: outputIdentity,
                    strengthScale: learningStrength.adjustmentScale
                )
                : nil
            let generation = try await generateValidatedOutputWithRetry(
                features: features,
                requestContext: requestContext,
                requestedIntensity: requestedIntensity,
                requestedProfile: requestedProfile,
                graphicEQMode: graphicEQMode,
                song: song,
                learningContext: learningContext,
                deviceTuningTarget: deviceTuningTarget,
                deviceTrainingContext: deviceTrainingContext,
                managedAgent: managedAgent,
                skillRuntime: skillExecution.runtime,
                toolPolicy: skillExecution.policy,
                onDeviceModelIdentity: onDeviceModelIdentity,
                traceID: traceID
            )
            try Task.checkCancellation()
            guard activeAnalysisRunID == analysisRunID, isCurrentSong(song) else {
                throw CancellationError()
            }
            let output = generation.output
            let generationElapsed = generation.elapsed
            let compilationStartedAt = Date()
            generationStage = .finalizing
            var result = try MonoAudioTuningTool.compileProposal(
                songID: song.id,
                output: output,
                features: features,
                provider: generation.provider,
                model: generation.model,
                agentVersion: currentAgentVersion,
                skillFingerprint: skillExecution.fingerprint,
                skillRevision: skillExecution.runtime.revision,
                executionMode: generation.executionMode,
                modelToolInvocationCount: generation.modelToolInvocationCount,
                skillRuntime: skillExecution.runtime,
                tuningIntensity: requestedIntensity,
                tuningProfile: requestedProfile,
                avoidingProfileNames: Set(recentProfileNames),
                learningContext: learningContext,
                applyLearningAdjustments: !generation.embedsLearningContext,
                deviceTuningTarget: deviceTuningTarget
            )
            // Keep both a neutral population target and a learned-personalized
            // target. Neither includes the output-device correction.
            let populationTrainingTarget = try? MonoAudioTuningTool.compileProposal(
                songID: song.id,
                output: generation.populationOutput ?? output,
                features: features,
                provider: generation.provider,
                model: generation.model,
                agentVersion: currentAgentVersion,
                skillFingerprint: skillExecution.fingerprint,
                skillRevision: skillExecution.runtime.revision,
                executionMode: generation.executionMode,
                modelToolInvocationCount: generation.modelToolInvocationCount,
                skillRuntime: skillExecution.runtime,
                tuningIntensity: requestedIntensity,
                tuningProfile: requestedProfile,
                avoidingProfileNames: Set(recentProfileNames),
                learningContext: nil,
                deviceTuningTarget: nil
            )
            let personalizedTrainingTarget = try? MonoAudioTuningTool.compileProposal(
                songID: song.id,
                output: output,
                features: features,
                provider: generation.provider,
                model: generation.model,
                agentVersion: currentAgentVersion,
                skillFingerprint: skillExecution.fingerprint,
                skillRevision: skillExecution.runtime.revision,
                executionMode: generation.executionMode,
                modelToolInvocationCount: generation.modelToolInvocationCount,
                skillRuntime: skillExecution.runtime,
                tuningIntensity: requestedIntensity,
                tuningProfile: requestedProfile,
                avoidingProfileNames: Set(recentProfileNames),
                learningContext: learningContext,
                applyLearningAdjustments: !generation.embedsLearningContext,
                deviceTuningTarget: nil
            )
            let compilationElapsed = Date().timeIntervalSince(compilationStartedAt)
            let compliance = result.skillCompliance
            AIAgentTraceStore.shared.append(
                traceID,
                category: .skill,
                level: .success,
                stage: .compilation,
                title: "本地调音编译器",
                detail: "模型方案已通过频段、增益、相位、动态与余量规则编译，生成可应用的播放参数。",
                durationSeconds: compilationElapsed,
                metadata: [
                    "toolVersion": MonoAudioTuningTool.version,
                    "knowledgeVersion": MonoAudioTuningKnowledge.version,
                    "skillFingerprint": skillExecution.fingerprint,
                    "skillRevision": skillExecution.runtime.revision,
                    "executionMode": generation.executionMode.rawValue,
                    "modelToolInvocationCount": String(generation.modelToolInvocationCount),
                    "enabledSkills": skillExecution.runtime.enabledSkillIDs.joined(separator: ","),
                    "requiredSkills": skillExecution.runtime.requiredSkillIDs.joined(separator: ","),
                    "profile": result.profileName,
                    "bands": String(result.gains.count),
                    "preampDB": String(format: "%.2f", result.preampDB),
                    "confidence": result.confidenceDisplayText,
                    "adaptiveLearningApplied": result.learningRevision == nil ? "false" : "true",
                    "learningRevision": String(result.learningRevision ?? 0),
                    "learningEvidence": String(result.learningEvidenceCount ?? 0),
                    "learningConfidence": String(format: "%.3f", result.learningConfidence ?? 0),
                    "maximumLearnedBandAdjustmentDB": String(
                        format: "%.3f",
                        learningContext?.bandAdjustments.map { abs($0) }.max() ?? 0
                    ),
                    "checkedRuleCount": String(compliance?.checkedRuleCount ?? 0),
                    "warningCodes": compliance?.warningCodes.joined(separator: ",") ?? "",
                    "localValidationApplied": (compliance?.localValidationApplied ?? false) ? "true" : "false"
                ]
            )
            let applicationStartedAt = Date()
            let didApply = apply(
                result,
                expectedSongIdentifier: identifier,
                expectedOutputIdentity: outputIdentity
            )
            let applyingElapsed = Date().timeIntervalSince(applicationStartedAt)
            let timing = AIEqualizerTiming(
                total: Date().timeIntervalSince(runStartedAt),
                sampling: samplingElapsed,
                samplingReused: reusableMeasuredFeatures != nil,
                generation: generationElapsed,
                applying: applyingElapsed,
                completedAt: Date()
            )
            result.timing = timing
            AIAgentTraceStore.shared.append(
                traceID,
                category: .skill,
                level: didApply ? .success : .warning,
                stage: .application,
                title: didApply ? "DSP 应用完成" : "DSP 未应用",
                detail: (didApply
                    ? "编译后的均衡、动态、空间与保护参数已提交到当前播放 DSP。"
                    : "生成与编译已经完成，但播放目标或均衡器模式发生变化，因此没有修改当前 DSP。")
                    + "\n\n"
                    + traceJSON(result)
                    + (didApply ? "\n\nDSP 参数与 SDK 回读\n" + traceJSON(EQManager.shared.currentDSPDiagnosticSnapshot()) : ""),
                durationSeconds: applyingElapsed,
                metadata: [
                    "recordType": "local-tuning-result",
                    "modelSource": "local-safety-compiler",
                    "provider": generation.provider.rawValue,
                    "model": generation.model,
                    "result": didApply ? "applied" : "skipped-context-changed",
                    "cacheReused": "false",
                    "proposalID": result.id.uuidString,
                    "output": EQManager.shared.currentOutputName,
                    "eqMode": result.graphicEQMode.rawValue,
                    "profile": result.profileName,
                    "bands": String(result.gains.count),
                    "preampDB": String(format: "%.2f", result.preampDB),
                    "limiter": result.effects.finalLimiterEnabled ? "enabled" : "disabled",
                    "limiterCeilingDB": String(format: "%.2f", result.effects.finalLimiterCeilingDB)
                ]
            )
            recordProfileName(result.profileName)
            proposalCache.set(result, for: cacheKey)
            if proposalCache.shouldRecord(
                result,
                songIdentifier: identifier,
                outputIdentity: outputIdentity
            ) {
                proposalCache.record(
                    result,
                    songIdentifier: identifier,
                    outputIdentity: outputIdentity
                )
            } else {
                AppLogger.info(
                    "[AIEqualizerAgent] Skipped history save because tuning change was below threshold song=\(identifier)",
                    step: "ai-tuning.saved-skip"
                )
            }
            proposalCache.recordTrainingSample(
                proposal: result,
                features: features,
                songIdentifier: identifier,
                deviceTuningTarget: deviceTuningTarget,
                deviceTrainingContext: deviceTrainingContext,
                populationTarget: populationTrainingTarget,
                learningContext: learningContext,
                personalizedTarget: personalizedTrainingTarget
            )
            savedProposals = proposalCache.history(for: identifier)
            samplingRetryCount[identifier] = nil
            AppLogger.success(
                "[AIEqualizerAgent] Analysis timing songID=\(song.id) total=\(String(format: "%.2f", timing.total))s sampling=\(String(format: "%.2f", timing.sampling))s generation=\(String(format: "%.2f", timing.generation))s applying=\(String(format: "%.2f", timing.applying))s intensity=\(requestedIntensity.rawValue)",
                step: "ai-tuning.timing"
            )
            if didApply {
                proposal = result
                AIAgentTraceStore.shared.finish(traceID, status: .completed)
            } else {
                AIAgentTraceStore.shared.finish(
                    traceID,
                    status: .cancelled,
                    message: String(localized: "agent_trace_dsp_context_changed")
                )
            }
        } catch is CancellationError {
            AIAgentTraceStore.shared.append(
                traceID,
                category: .reasoning,
                level: .warning,
                stage: .completion,
                title: "任务已取消",
                detail: "播放目标、输出环境或用户操作发生变化，本次尚未完成的 Agent 任务已停止。",
                durationSeconds: Date().timeIntervalSince(runStartedAt)
            )
            AIAgentTraceStore.shared.finish(traceID, status: .cancelled)
            guard activeAnalysisRunID == analysisRunID else { return }
            let elapsed = Date().timeIntervalSince(runStartedAt)
            AppLogger.info(
                "[AIEqualizerAgent] Analysis cancelled songID=\(song.id) phase=\(String(describing: phase)) elapsed=\(String(format: "%.2f", elapsed))s",
                step: "ai-tuning.cancelled"
            )
            if isCurrentSong(song) {
                if measuredFeatures == nil {
                    measuredFeatures = restoredMeasurement(
                        for: song,
                        graphicEQMode: graphicEQMode
                    )
                }
                phase = .idle
            }
        } catch {
            AIAgentTraceStore.shared.append(
                traceID,
                category: .reasoning,
                level: .error,
                stage: .completion,
                title: "任务失败",
                detail: error.localizedDescription,
                durationSeconds: Date().timeIntervalSince(runStartedAt),
                metadata: [
                    "failureStage": String(describing: phase),
                    "errorType": String(reflecting: type(of: error))
                ]
            )
            AIAgentTraceStore.shared.finish(
                traceID,
                status: .failed,
                message: error.localizedDescription
            )
            guard activeAnalysisRunID == analysisRunID else { return }
            let elapsed = Date().timeIntervalSince(runStartedAt)
            let failurePositionText = String(format: "%.1f", PlayerManager.shared.currentTime)
            let failureDurationText = String(format: "%.1f", PlayerManager.shared.duration)
            AppLogger.error(
                "[AIEqualizerAgent] Analysis failed songID=\(song.id) phase=\(String(describing: phase)) mode=\(samplingMode.rawValue) intensity=\(requestedIntensity.rawValue) elapsed=\(String(format: "%.2f", elapsed))s playerState=\(String(describing: PlayerManager.shared.streamPlayer.state)) appPlaying=\(PlayerManager.shared.isPlaying) loading=\(PlayerManager.shared.isLoading) position=\(failurePositionText)/\(failureDurationText) error=\(error.localizedDescription)",
                step: "ai-tuning.failed"
            )
            if isCurrentSong(song) {
                if measuredFeatures == nil {
                    measuredFeatures = restoredMeasurement(
                        for: song,
                        graphicEQMode: graphicEQMode
                    )
                }
                phase = .failed(error.localizedDescription)
                scheduleSamplingRetryIfNeeded(for: identifier, error: error, trigger: trigger)
            }
        }
    }

    func scheduleSamplingRetryIfNeeded(
        for identifier: String,
        error: Error,
        trigger: AIEqualizerAnalysisTrigger
    ) {
        guard tuningServiceStore.settings.isEnabled else { return }
        if trigger == .automatic, !isAutomaticTuningActive { return }
        guard let aiError = error as? AIEqualizerError else { return }
        switch aiError {
        case .sampleUnavailable, .playbackRequired:
            break
        default:
            return
        }

        let attempt = (samplingRetryCount[identifier] ?? 0) + 1
        guard attempt <= Self.maxSamplingRetryAttempts else {
            AppLogger.warning(
                "[AIEqualizerAgent] Sampling retries exhausted song=\(identifier) attempts=\(Self.maxSamplingRetryAttempts)",
                step: "ai-tuning.retry-exhausted"
            )
            return
        }
        samplingRetryCount[identifier] = attempt
        AppLogger.warning(
            "[AIEqualizerAgent] Sampling retry scheduled song=\(identifier) trigger=\(trigger.logName) attempt=\(attempt)/\(Self.maxSamplingRetryAttempts)",
            step: "ai-tuning.retry-scheduled"
        )
        automaticRetryTask?.cancel()
        automaticRetryTask = Task { [weak self] in
            defer {
                if let self,
                   self.samplingRetryCount[identifier] == attempt {
                    self.automaticRetryTask = nil
                }
            }
            do {
                try await Task.sleep(for: .seconds(Double(attempt * 2)))
            } catch {
                return
            }
            guard let self,
                  PlayerManager.shared.currentSong.map({ self.songIdentifier($0) }) == identifier else {
                return
            }
            if trigger == .automatic, !self.isAutomaticTuningActive { return }

            // Sampling must never force playback. Wait for the existing player to
            // become usable so a transient audio-route or decoder interruption can
            // recover without producing another false "no usable audio" result.
            for _ in 0..<120 {
                guard !Task.isCancelled,
                      PlayerManager.shared.currentSong.map({ self.songIdentifier($0) }) == identifier else {
                    return
                }
                if PlayerManager.shared.isPlaying,
                   !PlayerManager.shared.isLoading,
                   PlayerManager.shared.streamPlayer.state == .playing {
                    if trigger == .automatic {
                        self.scheduleAutomaticAnalysis()
                    } else {
                        self.analysisTask?.cancel()
                        self.analysisTask = Task { [weak self] in
                            await self?.runAnalysis(trigger: .manual, forceRegeneration: true)
                        }
                    }
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            AppLogger.warning(
                "[AIEqualizerAgent] Sampling retry timed out waiting for playback song=\(identifier) trigger=\(trigger.logName)",
                step: "ai-tuning.retry-wait-timeout"
            )
        }
    }

    func generateValidatedOutputWithRetry(
        features: AIEqualizerAudioFeatures,
        requestContext: AIProviderRequestContext,
        requestedIntensity: AIEqualizerTuningIntensity,
        requestedProfile: AIEqualizerTuningProfile,
        graphicEQMode: GraphicEQMode,
        song: Song,
        learningContext: AIEqualizerLearningContext?,
        deviceTuningTarget: AIEqualizerDeviceTuningTarget?,
        deviceTrainingContext: AIEqualizerDeviceTrainingContext,
        managedAgent: AppAgentConfiguration?,
        skillRuntime: MonoAudioAgentRuntimeSkillConfiguration,
        toolPolicy: AppAgentToolPolicyConfiguration,
        onDeviceModelIdentity: String?,
        traceID: UUID
    ) async throws -> (
        output: AIEqualizerModelOutput,
        populationOutput: AIEqualizerModelOutput?,
        embedsLearningContext: Bool,
        elapsed: TimeInterval,
        executionMode: AIEqualizerSkillCompliance.ExecutionMode,
        modelToolInvocationCount: Int,
        provider: AIWireProtocol,
        model: String
    ) {
        let configuration = requestContext.configuration
        let startedAt = Date()
        generationStartedAt = startedAt
        let requiredModelTool = MonoAudioTuningTool.requiredModelTool(for: graphicEQMode)
        guard toolPolicy.requiredToolName == requiredModelTool.name,
              toolPolicy.invocationMode?.lowercased() == "required",
              toolPolicy.requireExactlyOnce == true,
              toolPolicy.localValidationRequired == true,
              toolPolicy.allowPromptFallback == false else {
            let configuredToolName = toolPolicy.requiredToolName ?? "missing"
            let configuredInvocationMode = toolPolicy.invocationMode ?? "missing"
            AppLogger.error(
                "[AIEqualizerAgent] Resolved tool policy is not safe tool=\(configuredToolName) mode=\(configuredInvocationMode) once=\(toolPolicy.requireExactlyOnce ?? false) local=\(toolPolicy.localValidationRequired ?? false) fallback=\(toolPolicy.allowPromptFallback ?? false)",
                step: "ai-tuning.tool-policy-invalid"
            )
            throw AIEqualizerError.invalidResponse
        }
        let toolContext = MonoAudioTuningTool.prepareInvocation(
            features: features,
            tuningProfile: requestedProfile,
            deviceTuningTarget: deviceTuningTarget,
            skillRuntime: skillRuntime
        )
        if onDeviceModelIdentity != nil {
            do {
                if let expected = requestContext.requiredDistributedModelIdentity,
                   AIResonanceUpdateStore.shared.tuningModel?.distributionIdentity != expected {
                    throw AIResonanceDistributionError.modelUnavailable
                }
                generationStage = .generating
                phase = .requesting
                let prediction = try await AudioTrainingOnDeviceModelStore.shared.predict(
                    features: features,
                    deviceTuningTarget: deviceTuningTarget,
                    tuningIntensity: requestedIntensity,
                    tuningProfile: requestedProfile,
                    learningContext: learningContext,
                    deviceTrainingContext: deviceTrainingContext,
                    expectedModelIdentity: onDeviceModelIdentity
                )
                try Task.checkCancellation()
                if let expected = requestContext.requiredDistributedModelIdentity,
                   AIResonanceUpdateStore.shared.tuningModel?.distributionIdentity != expected {
                    throw AIResonanceDistributionError.modelUnavailable
                }
                guard isCurrentSong(song), EQManager.shared.graphicEQMode == graphicEQMode else {
                    throw AIEqualizerError.noSong
                }
                generationStage = .validating
                let review = MonoAudioTuningTool.review(
                    output: prediction.output,
                    features: features,
                    context: toolContext
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .conversation,
                    level: review.isAccepted ? .success : .error,
                    stage: .model,
                    title: "\(prediction.modelVersion.hasPrefix("mono-resonance-s2-") ? "共鸣 S2" : "共鸣 S1") · 本地推理",
                    detail: localModelTrace(
                        prediction: prediction,
                        review: review
                    ),
                    durationSeconds: prediction.inference.latencyMilliseconds / 1_000,
                    metadata: [
                        "recordType": "local-coreml-inference",
                        "modelSource": "on-device-coreml",
                        "provider": "Core ML",
                        "model": prediction.modelVersion,
                        "modelID": prediction.modelID,
                        "modelSHA256": prediction.modelSHA256,
                        "tuningProfile": requestedProfile.rawValue,
                        "confidence": prediction.output.confidenceCalibration?.displayText
                            ?? String(localized: "audio_training_confidence_uncalibrated"),
                        "featureSchemaVersion": String(prediction.featureSchemaVersion),
                        "targetSchemaVersion": String(prediction.targetSchemaVersion),
                        "eqMode": prediction.graphicEQMode.rawValue,
                        "inputCount": String(prediction.inference.input.count),
                        "outputCount": String(prediction.inference.rawOutput.count),
                        "computeMode": prediction.computeMode.rawValue,
                        "learningContextEmbedded": prediction.embedsLearningContext ? "true" : "false",
                        "deviceContextEmbedded": prediction.embedsDetailedDeviceContext ? "true" : "false",
                        "populationPass": prediction.populationInference == nil ? "false" : "true",
                        "trackCorrectionStrength": String(format: "%.2f", prediction.trackCorrectionStrength),
                        "fallbackOutputCount": String(prediction.fallbackOutputCount),
                        "validationAccepted": review.isAccepted ? "true" : "false"
                    ]
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .conversation,
                    level: prediction.output.confidenceCalibration == nil ? .warning : .success,
                    stage: .validation,
                    title: "共鸣 · 置信度校准",
                    detail: localModelCalibrationTrace(prediction: prediction),
                    metadata: [
                        "recordType": "local-coreml-confidence-calibration",
                        "modelSource": "on-device-coreml",
                        "provider": "Core ML",
                        "model": prediction.modelVersion,
                        "confidenceCalibrated": prediction.output.confidenceCalibration == nil ? "false" : "true",
                        "calibrationBranch": "\(graphicEQMode.rawValue):\(requestedProfile.rawValue)"
                    ]
                )
                guard review.isAccepted else {
                    throw AIEqualizerError.invalidResponse
                }
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .skill,
                    level: review.issues.isEmpty ? .success : .warning,
                    stage: .validation,
                    title: "Core ML · mono_audio_tuning",
                    detail: review.issues.isEmpty
                        ? "手机模型推理结果已通过本地调音工具校验。"
                        : review.issues.map { "\($0.code)：\($0.detail)" }.joined(separator: "\n"),
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    metadata: [
                        "model": prediction.modelVersion,
                        "inputCount": String(prediction.inference.input.count),
                        "outputCount": String(prediction.inference.rawOutput.count),
                        "localValidationRequired": "true"
                    ]
                )
                return (
                    prediction.output,
                    prediction.populationOutput,
                    prediction.embedsLearningContext,
                    Date().timeIntervalSince(startedAt),
                    .trainedCoreMLModel,
                    1,
                    .appleIntelligence,
                    prediction.modelVersion
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if requestContext.requiresTrainedModel { throw error }
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    level: .warning,
                    stage: .fallback,
                    title: "本地模型回退",
                    detail: error.localizedDescription,
                    metadata: [
                        "recordType": "local-coreml-fallback",
                        "modelSource": "on-device-coreml",
                        "model": onDeviceModelIdentity ?? "unknown",
                        "fallbackProvider": configuration.wireProtocol.rawValue,
                        "fallbackModel": configuration.resolvedModel,
                        "errorType": String(reflecting: type(of: error))
                    ]
                )
                AppLogger.warning(
                    "[AIEqualizerAgent] On-device trained model unavailable; using configured model error=\(error.localizedDescription)",
                    step: "local-model.inference-fallback",
                    category: .localModel,
                    event: "local-model.inference-fallback",
                    context: [
                        "model": onDeviceModelIdentity ?? "unknown",
                        "fallbackProvider": configuration.wireProtocol.rawValue,
                        "fallbackModel": configuration.resolvedModel
                    ]
                )
            }
        }
        let bundledUserPrompt = try AIEqualizerPrompt.userPrompt(
            features: features,
            tuningIntensity: requestedIntensity,
            tuningProfile: requestedProfile,
            avoidingProfileNames: recentProfileNames,
            learningContext: learningContext
        )
        let configuredUserPrompt = managedAgent?.userPrompt(fallback: bundledUserPrompt) ?? bundledUserPrompt
        let promptWithDeviceTarget = try AIEqualizerPrompt.appendingDeviceTuningTarget(
            deviceTuningTarget,
            to: configuredUserPrompt
        )
        let promptWithDeviceContext = try AIEqualizerPrompt.appendingDeviceTrainingContext(
            deviceTrainingContext,
            to: promptWithDeviceTarget
        )
        let userPrompt = AIEqualizerPrompt.appendingAgentSkillContext(
            skillRuntime.modelContext,
            to: promptWithDeviceContext
        )
        let bundledSystemPrompt = AIEqualizerPrompt.system(for: graphicEQMode)
        let configuredSystemPrompt = managedAgent?.systemPrompt(
            fallback: bundledSystemPrompt,
            secondaryFallback: graphicEQMode == .thirtyTwoBand ? bundledSystemPrompt : nil
        )
        let systemPrompt = AIEqualizerPrompt.managedSystemPrompt(
            for: graphicEQMode,
            configuredPrompt: configuredSystemPrompt
        )
        let maximumAttempts = managedAgent?.resolvedMaxAttempts(
            fallback: Self.maxGenerationRetryAttempts
        ) ?? Self.maxGenerationRetryAttempts
        let generationOptions = managedAgent?.generationOptions ?? .standard
        let minimumTimeout = max(120, managedAgent?.resolvedMinimumTimeoutSeconds ?? 0)

        AIAgentTraceStore.shared.append(
            traceID,
            category: .conversation,
            stage: .configuration,
            title: "System",
            detail: systemPrompt,
            metadata: [
                "recordType": "remote-model-input-system",
                "role": "system",
                "provider": configuration.wireProtocol.rawValue,
                "model": configuration.resolvedModel,
                "characters": String(systemPrompt.count)
            ]
        )
        AIAgentTraceStore.shared.append(
            traceID,
            category: .conversation,
            stage: .configuration,
            title: "User",
            detail: userPrompt,
            metadata: [
                "recordType": "remote-model-input-user",
                "role": "user",
                "provider": configuration.wireProtocol.rawValue,
                "model": configuration.resolvedModel,
                "characters": String(userPrompt.count)
            ]
        )
        AIAgentTraceStore.shared.append(
            traceID,
            category: .reasoning,
            stage: .configuration,
            title: "执行策略",
            detail: "根据测量可信度、峰值风险和相位兼容性确定本次可用处理边界。",
            metadata: [
                "evidence": toolContext.evidenceClass,
                "evidenceScore": String(format: "%.3f", toolContext.evidenceScore),
                "peakRisk": toolContext.peakRisk,
                "phaseRisk": toolContext.phaseRisk,
                "haasAllowed": toolContext.haasAllowed ? "true" : "false"
            ]
        )

        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()
            guard isCurrentSong(song), EQManager.shared.graphicEQMode == graphicEQMode else {
                throw AIEqualizerError.noSong
            }

            generationStage = .preparing
            phase = .requesting
            var reservation: Date?
            let attemptStartedAt = Date()
            do {
                // Custom providers do not consume the default service's quota.
                // Quota and frequency errors are not retried below.
                if let limits = requestContext.usageLimits {
                    reservation = try usageLimiter.reserveRequest(limits: limits)
                }
                generationStage = .generating
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    stage: .model,
                    title: "请求模型",
                    detail: "发送第 \(attempt) 次请求。模型只需返回一次完整结果，不增加额外往返。",
                    metadata: [
                        "recordType": "remote-model-request",
                        "attempt": "\(attempt)/\(maximumAttempts)",
                        "protocol": configuration.wireProtocol.rawValue,
                        "provider": configuration.wireProtocol.rawValue,
                        "model": configuration.resolvedModel,
                        "temperature": String(format: "%.3f", generationOptions.normalizedTemperature),
                        "maxOutputTokens": String(generationOptions.normalizedMaxOutputTokens),
                        "minimumTimeoutSeconds": String(format: "%.1f", minimumTimeout)
                    ]
                )
                let toolResponse = try await client.generateRequiringTool(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    tool: requiredModelTool,
                    configuration: configuration,
                    apiKey: requestContext.apiKey,
                    minimumTimeout: minimumTimeout,
                    options: generationOptions,
                    allowContentFallback: toolPolicy.allowPromptFallback ?? false,
                    requireExactlyOnce: toolPolicy.requireExactlyOnce ?? true
                )
                let response = toolResponse.arguments
                let modelToolInvocationCount = toolResponse.toolInvocationCount
                let executionMode: AIEqualizerSkillCompliance.ExecutionMode
                if configuration.wireProtocol == .appleIntelligence {
                    guard toolResponse.invocation == .toolCall,
                          toolResponse.toolInvocationCount == 1 else {
                        throw AIEqualizerError.invalidResponse
                    }
                    executionMode = .appleIntelligenceLocalCompiler
                } else {
                    executionMode = toolResponse.invocation == .toolCall
                        ? .requiredModelTool
                        : .modelPromptFallback
                }
                AppLogger.debug(
                    "[AIEqualizerAgent] Model completed mono_audio_tuning policy songID=\(song.id) attempt=\(attempt)/\(maximumAttempts) invocation=\(toolResponse.invocation.rawValue) count=\(toolResponse.toolInvocationCount)",
                    step: "ai-tuning.model-tool-called"
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .skill,
                    level: .success,
                    stage: .tool,
                    title: configuration.wireProtocol == .appleIntelligence
                        ? "Apple Intelligence · mono_audio_tuning"
                        : "mono_audio_tuning",
                    detail: response,
                    durationSeconds: Date().timeIntervalSince(attemptStartedAt),
                    metadata: [
                        "recordType": "remote-model-tool-invocation",
                        "caller": configuration.wireProtocol == .appleIntelligence
                            ? "foundation-models-tool"
                            : "model",
                        "toolName": requiredModelTool.name,
                        "provider": configuration.wireProtocol.rawValue,
                        "model": configuration.resolvedModel,
                        "invocationMode": toolPolicy.invocationMode ?? "required",
                        "requireExactlyOnce": (toolPolicy.requireExactlyOnce ?? true) ? "true" : "false",
                        "localValidationRequired": (toolPolicy.localValidationRequired ?? true) ? "true" : "false",
                        "allowPromptFallback": (toolPolicy.allowPromptFallback ?? false) ? "true" : "false",
                        "attempt": String(attempt),
                        "invocation": toolResponse.invocation.rawValue,
                        "invocationCount": String(toolResponse.toolInvocationCount),
                        "policyRevision": toolPolicy.revision ?? "bundled-v1",
                        "argumentsCharacters": String(response.count)
                    ]
                )
                try Task.checkCancellation()
                guard isCurrentSong(song), EQManager.shared.graphicEQMode == graphicEQMode else {
                    throw AIEqualizerError.noSong
                }
                AppLogger.debug(
                    "[AIEqualizerAgent] Model response received songID=\(song.id) attempt=\(attempt)/\(maximumAttempts) characters=\(response.count) expectedBands=\(graphicEQMode.bandCount)",
                    step: "ai-tuning.response-received"
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .conversation,
                    level: .success,
                    stage: .tool,
                    title: "Assistant · Tool Arguments",
                    detail: response,
                    metadata: [
                        "role": "assistant",
                        "provider": configuration.wireProtocol.rawValue,
                        "model": configuration.resolvedModel,
                        "attempt": String(attempt),
                        "characters": String(response.count)
                    ]
                )
                generationStage = .validating
                let validationStartedAt = Date()
                let output = try decodeModelOutput(from: response, expectedMode: graphicEQMode)
                let review = MonoAudioTuningTool.review(
                    output: output,
                    features: features,
                    context: toolContext
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .conversation,
                    level: review.isAccepted ? .success : .error,
                    stage: .validation,
                    title: "远端模型解码结果",
                    detail: traceJSON(output),
                    durationSeconds: Date().timeIntervalSince(validationStartedAt),
                    metadata: [
                        "recordType": "remote-model-output-decoded",
                        "provider": configuration.wireProtocol.rawValue,
                        "model": configuration.resolvedModel,
                        "attempt": String(attempt),
                        "eqMode": graphicEQMode.rawValue,
                        "bandCount": String(output.gains.count),
                        "validationAccepted": review.isAccepted ? "true" : "false",
                        "validationSummary": review.summary
                    ]
                )
                guard review.isAccepted else {
                    AIAgentTraceStore.shared.append(
                        traceID,
                        category: .skill,
                        level: .error,
                        stage: .validation,
                        title: "工具校验未通过",
                        detail: review.issues.map { "\($0.code)：\($0.detail)" }.joined(separator: "\n"),
                        durationSeconds: Date().timeIntervalSince(validationStartedAt),
                        metadata: ["summary": review.summary]
                    )
                    AppLogger.error(
                        "[AIEqualizerAgent] MonoAudioTuningTool rejected model output issues=\(review.summary)",
                        step: "ai-tuning.tool-rejected"
                    )
                    throw AIEqualizerError.invalidResponse
                }
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .skill,
                    level: review.issues.isEmpty ? .success : .warning,
                    stage: .validation,
                    title: "工具校验通过",
                    detail: review.issues.isEmpty
                        ? "返回结构、频段数量与数值范围均有效。"
                        : review.issues.map { "\($0.code)：\($0.detail)" }.joined(separator: "\n"),
                    durationSeconds: Date().timeIntervalSince(validationStartedAt),
                    metadata: ["summary": review.summary]
                )
                return (
                    output,
                    nil,
                    false,
                    Date().timeIntervalSince(startedAt),
                    executionMode,
                    modelToolInvocationCount,
                    configuration.wireProtocol,
                    configuration.resolvedModel
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let reservation, AIUsageLimiter.shouldRefundReservation(for: error) {
                    usageLimiter.releaseReservation(reservation)
                }
                let willRetry = attempt < maximumAttempts
                    && AIAgentRuntimePolicy.shouldRetry(error)
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    level: willRetry ? .warning : .error,
                    stage: .model,
                    title: "模型请求失败",
                    detail: error.localizedDescription,
                    durationSeconds: Date().timeIntervalSince(attemptStartedAt),
                    metadata: [
                        "recordType": "remote-model-failure",
                        "provider": configuration.wireProtocol.rawValue,
                        "model": configuration.resolvedModel,
                        "attempt": String(attempt),
                        "willRetry": willRetry ? "true" : "false",
                        "errorType": String(reflecting: type(of: error))
                    ]
                )
                guard willRetry else {
                    throw error
                }
                let delay = generationRetryDelay(
                    for: attempt,
                    minimumRequestInterval: requestContext.usageLimits?.minimumRequestInterval ?? 0
                )
                AppLogger.warning(
                    "[AIEqualizerAgent] Generation retry scheduled song=\(song.id) attempt=\(attempt + 1)/\(maximumAttempts) delay=\(String(format: "%.1f", delay))s error=\(error.localizedDescription)",
                    step: "ai-tuning.generation-retry"
                )
                AIAgentTraceStore.shared.append(
                    traceID,
                    category: .reasoning,
                    level: .warning,
                    stage: .model,
                    title: "准备重试",
                    detail: error.localizedDescription,
                    durationSeconds: Date().timeIntervalSince(attemptStartedAt),
                    metadata: [
                        "nextAttempt": String(attempt + 1),
                        "delaySeconds": String(format: "%.1f", delay)
                    ]
                )
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    throw CancellationError()
                }
            }
        }

        throw AIEqualizerError.invalidResponse
    }

    func generationRetryDelay(
        for attempt: Int,
        minimumRequestInterval: TimeInterval
    ) -> TimeInterval {
        AIAgentRuntimePolicy.retryDelay(
            after: attempt,
            minimumRequestInterval: minimumRequestInterval
        )
    }

    private func localModelTrace(
        prediction: AudioTrainingOnDevicePrediction,
        review: MonoAudioTuningTool.Review
    ) -> String {
        var sections = [
            "模型来源 = 手机端 Core ML",
            "模型版本 = \(prediction.modelVersion)",
            "模型 ID = \(prediction.modelID)",
            "模型 SHA-256 = \(prediction.modelSHA256)",
            "参数回退数量 = \(prediction.fallbackOutputCount)",
            "特征 schema = \(prediction.featureSchemaVersion)",
            "目标 schema = \(prediction.targetSchemaVersion)",
            "均衡器模式 = \(prediction.graphicEQMode.rawValue)",
            "计算策略 = \(prediction.computeMode.rawValue)",
            "模型内学习参数 = \(prediction.embedsLearningContext ? "是" : "否")",
            "模型内设备参数 = \(prediction.embedsDetailedDeviceContext ? "是" : "否")",
            "主推理耗时 = \(String(format: "%.3f", prediction.inference.latencyMilliseconds)) ms",
            "",
            tensorTrace(title: "完整模型输入", values: prediction.inference.input),
            "",
            tensorTrace(title: "完整模型原始输出", values: prediction.inference.rawOutput),
            "",
            "歌曲修正系数 = \(prediction.inference.trackCorrectionStrength)",
            tensorTrace(title: "群体先验输入", values: prediction.inference.priorInput),
            tensorTrace(title: "群体先验原始输出", values: prediction.inference.priorOutput),
            tensorTrace(title: "混合后输出", values: prediction.inference.blendedOutput),
            localModelCalibrationTrace(prediction: prediction),
            "",
            "模型解码输出",
            traceJSON(prediction.output)
        ]
        if let populationInference = prediction.populationInference,
           let populationOutput = prediction.populationOutput {
            sections.append(contentsOf: [
                "",
                "群体基线推理耗时 = \(String(format: "%.3f", populationInference.latencyMilliseconds)) ms",
                "",
                tensorTrace(title: "群体基线完整输入", values: populationInference.input),
                "",
                tensorTrace(title: "群体基线完整原始输出", values: populationInference.rawOutput),
                "",
                tensorTrace(title: "群体基线混合后输出", values: populationInference.blendedOutput),
                "",
                "群体基线解码输出",
                traceJSON(populationOutput)
            ])
        }
        sections.append(contentsOf: [
            "",
            "本地工具校验 = \(review.isAccepted ? "通过" : "未通过")",
            "校验摘要 = \(review.summary)",
            "校验问题 = \(review.issues.isEmpty ? "无" : review.issues.map { "\($0.code)：\($0.detail)" }.joined(separator: "；"))"
        ])
        return sections.joined(separator: "\n")
    }

    private func localModelCalibrationTrace(prediction: AudioTrainingOnDevicePrediction) -> String {
        var sections = [
            "校准范围 = 模型预测的图示 EQ，与独立歌曲的参考参数比较；不含后续设备补偿、个人修正和其他 DSP 参数。",
            "统计单位 = 独立歌曲；同歌的频段与成对上下文取最大误差。",
            "适用条件 = 新歌曲与校准歌曲在同一分支内可交换；置信水平不是主观音质的成功概率。"
        ]
        if let evidence = prediction.output.confidenceCalibration {
            sections.append(contentsOf: [
                "校准结果 = \(evidence.displayText)",
                "分支 = \(evidence.branch)",
                "独立校准歌曲 = \(evidence.tracks)",
                "分位次序 = \(evidence.quantileRank)",
                "方法 = \(evidence.method)"
            ])
        } else {
            sections.append("校准结果 = 不可用；模型缺少有效独立校准结果，或当前分支与校准时的混合系数不一致。")
        }
        if let calibration = prediction.confidenceCalibration {
            sections.append("模型携带的完整校准记录")
            sections.append(traceJSON(calibration))
        } else {
            sections.append("模型文件没有携带置信度校准记录，需要使用新校准流程重新训练。")
        }
        return sections.joined(separator: "\n")
    }

    private func tensorTrace(
        title: String,
        values: [AudioTrainingTensorValue]
    ) -> String {
        (["\(title)（\(values.count) 项）"] + values.map { item in
            "[\(item.index)] \(item.name) = \(String(format: "%.9g", Double(item.value)))"
        }).joined(separator: "\n")
    }

    private func traceJSON<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "无法序列化详细记录"
        }
        return text
    }

}
