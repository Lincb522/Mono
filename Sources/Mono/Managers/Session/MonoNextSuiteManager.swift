import AVFoundation
@preconcurrency import Combine
@preconcurrency import CoreMotion
import Foundation

@MainActor
final class MonoNextSuiteManager: ObservableObject {
    static let shared = MonoNextSuiteManager()
    private static let retiredFeatures: Set<MonoNextFeature> = [
        .flow,
        .liveMaster,
        .soundTwin,
        .stems,
    ]

    @Published private(set) var enabledFeatures: Set<MonoNextFeature>
    @Published private(set) var currentDNA: MonoTrackDNA?
    @Published private(set) var spatialConfiguration: MonoSpatialLiveConfiguration
    @Published private(set) var recoverySnapshot: MonoRecoverySnapshot

    private let store: MonoNextSuiteStore
    private var cancellables = Set<AnyCancellable>()
    private var recoveryTimer: Timer?
    private var loadingStartedAt: Date?
    private var loadingSessionID: Int?
    private var lastAudibleDuration: TimeInterval = 0
    private var lastAudibleAdvanceAt = Date()
    private var lastRecoveryAt = Date.distantPast
    private var recoveryAttemptsInIncident = 0
    private var recoveryIncidentAudibleBaseline: TimeInterval = 0
    private var didLogRecoveryBudgetExhaustion = false
    private let maximumRecoveryAttemptsPerIncident = 2
    private var pendingRecoveryVerification: PendingRecoveryVerification?
    private var routeObserver: NSObjectProtocol?
    private var spatialCapabilityObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    private let headphoneMotionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MonoSpatial.headphone-motion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var headTrackingSessionID = 0
    private var headTrackingSessionStarted = false
    private var headTrackingRuntimeReady = false
    private var lastHeadTrackingRestartAt = Date.distantPast
    private var currentHeadTrackedPan: Float = 0
    private var spatialBase: SpatialBase?

    private init() {
        store = MonoNextSuiteStore()
        enabledFeatures = store.enabledFeatures.subtracting(Self.retiredFeatures)
        spatialConfiguration = store.spatialConfiguration
        recoverySnapshot = store.recoverySnapshot
        if enabledFeatures != store.enabledFeatures {
            store.setEnabledFeatures(enabledFeatures)
        }
        store.purgeRetiredFeatureData()
        try? FileManager.default.removeItem(at: Self.stemsDirectory)
        installObservers()
        startRecoveryHeartbeat()
        applySpatialConfigurationIfNeeded()
    }

    /// 耳机运动服务不能在 `App.init` 阶段启动。等待 App 进入 active 后，
    /// 再使用各系统均稳定支持的设备运动接口。
    func activateHeadTrackingRuntimeIfNeeded() {
        headTrackingRuntimeReady = true
        configureHeadTracking()
    }

    var isHeadTrackingAvailable: Bool {
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        return authorization != .denied
            && authorization != .restricted
            && headphoneMotionManager.isDeviceMotionAvailable
    }

    var isHeadTrackingActive: Bool {
        headTrackingSessionStarted && headphoneMotionManager.isDeviceMotionActive
    }

    func recenterHeadTracking() {
        guard isHeadTrackingAvailable else { return }
        configureHeadTracking(resetCalibration: true)
    }

    func isEnabled(_ feature: MonoNextFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    func setEnabled(_ feature: MonoNextFeature, enabled: Bool) {
        guard !Self.retiredFeatures.contains(feature) else {
            enabledFeatures.remove(feature)
            store.setEnabledFeatures(enabledFeatures)
            return
        }
        if feature == .spatialLive {
            var configuration = enabled ? spatialConfiguration : .init()
            if enabled, configuration.mode == .off {
                configuration.mode = .fixedStage
                configuration.stageWidth = 1.12
                configuration.stageDepth = 0.28
                configuration.ambience = 0.10
            }
            setSpatialConfiguration(configuration, enabled: enabled)
            return
        }
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
        store.setEnabledFeatures(enabledFeatures)

        if feature == .session, !enabled {
            MonoSessionManager.shared.leaveRoom()
        }
        if feature == .recovery, !enabled {
            recoveryAttemptsInIncident = 0
            recoveryIncidentAudibleBaseline = 0
            didLogRecoveryBudgetExhaustion = false
            pendingRecoveryVerification = nil
        }
    }

    func setSpatialConfiguration(
        _ configuration: MonoSpatialLiveConfiguration,
        enabled: Bool? = nil
    ) {
        var normalized = configuration
        normalized.stageWidth = min(1.8, max(0.7, normalized.stageWidth))
        normalized.stageDepth = min(1, max(0, normalized.stageDepth))
        normalized.centerFocus = min(1, max(0, normalized.centerFocus))
        normalized.ambience = min(0.6, max(0, normalized.ambience))
        // AirPods applies/restores one complete spatial state, without briefly
        // installing the generic preset between the feature and profile writes.
        if let enabled, enabled != isEnabled(.spatialLive) {
            if enabled {
                enabledFeatures.insert(.spatialLive)
            } else {
                enabledFeatures.remove(.spatialLive)
            }
            store.setEnabledFeatures(enabledFeatures)
        }
        if spatialConfiguration != normalized {
            spatialConfiguration = normalized
            store.setSpatialConfiguration(normalized)
        }
        applySpatialConfigurationIfNeeded()
        configureHeadTracking()
    }

    func resolvedSpatialForTuningProposal(
        _ proposal: AIEqualizerProposal
    ) -> AIEqualizerSpatialConfiguration {
        guard isEnabled(.spatialLive), spatialConfiguration.mode != .off else {
            return proposal.spatial
        }
        captureSpatialBase(proposal: proposal)
        guard let spatialBase else { return proposal.spatial }
        let resolved = resolvedSpatial(from: spatialBase)
        return AIEqualizerSpatialConfiguration(
            surroundLevel: resolved.surroundLevel,
            reverbLevel: resolved.reverbLevel,
            stereoWidth: resolved.stereoWidth
        )
    }

    func DNA(for song: Song) -> MonoTrackDNA? {
        store.dna(for: MonoTrackIdentity(song: song).storageKey)
    }

    func recordRecoveryEvent(_ kind: MonoRecoveryEventKind, detail: String) {
        guard isEnabled(.recovery), kind == .failure || kind == .recovered else { return }
        let player = PlayerManager.shared
        let event = MonoRecoveryEvent(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            songIdentity: player.currentSong.map(MonoTrackIdentity.init(song:)),
            position: max(0, player.currentTime),
            duration: max(0, player.duration),
            engineState: String(describing: player.streamPlayer.state),
            isLoading: player.isLoading,
            route: Self.currentRouteName,
            sessionID: player.playbackSessionId,
            detail: detail
        )
        recoverySnapshot = store.appendRecoveryEvent(event)
    }

    func resetRecoveryHistory() {
        recoverySnapshot = store.resetRecoveryHistory()
    }

    private func installObservers() {
        let player = PlayerManager.shared
        let agent = AIEqualizerAgent.shared

        player.$currentSong
            .removeDuplicates { lhs, rhs in
                guard let lhs, let rhs else { return lhs == nil && rhs == nil }
                return lhs.id == rhs.id && lhs.musicSource == rhs.musicSource
            }
            .sink { [weak self] song in
                guard let self else { return }
                self.currentDNA = song.flatMap { self.store.dna(for: MonoTrackIdentity(song: $0).storageKey) }
                self.loadingStartedAt = nil
                self.loadingSessionID = nil
                self.lastAudibleDuration = player.streamPlayer.totalAudiblePlaybackDuration
                self.lastAudibleAdvanceAt = Date()
                self.recoveryAttemptsInIncident = 0
                self.recoveryIncidentAudibleBaseline = self.lastAudibleDuration
                self.didLogRecoveryBudgetExhaustion = false
                self.pendingRecoveryVerification = nil
            }
            .store(in: &cancellables)

        agent.$measuredFeatures
            .compactMap { $0 }
            .sink { [weak self] features in
                guard let self,
                      let song = PlayerManager.shared.currentSong,
                      song.id == features.songID,
                      song.musicSource.rawValue == features.source else { return }
                let dna = MonoTrackDNA(song: song, features: features)
                self.store.setDNA(dna)
                self.currentDNA = dna
            }
            .store(in: &cancellables)

        player.$isLoading
            .removeDuplicates()
            .sink { [weak self] loading in
                guard let self else { return }
                self.loadingStartedAt = loading ? Date() : nil
                self.loadingSessionID = loading ? player.playbackSessionId : nil
            }
            .store(in: &cancellables)

        PlaybackTimePublisher.shared.$currentTime
            .sink { [weak self] position in
                self?.handlePlaybackPosition(position)
            }
            .store(in: &cancellables)

        agent.$proposal
            .compactMap { $0 }
            .sink { [weak self] proposal in
                self?.captureSpatialBase(proposal: proposal)
                self?.applySpatialConfigurationIfNeeded()
            }
            .store(in: &cancellables)

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySpatialConfigurationIfNeeded()
                self?.configureHeadTracking(resetCalibration: true)
            }
        }

        spatialCapabilityObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureHeadTracking(resetCalibration: true)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let detail = String(
                describing: notification.userInfo?[AVAudioSessionInterruptionTypeKey] ?? "interruption"
            )
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                AppLogger.debug("[MonoRecovery] interruption observed detail=\(detail)")
            }
        }
    }

    private func handlePlaybackPosition(_: Double) {
        let player = PlayerManager.shared
        refreshAudibleProgress(player: player, now: Date())
    }

    private func applySpatialConfigurationIfNeeded() {
        if EQManager.shared.isAuditioningReference {
            EQManager.shared.stopLoudnessMatchedReferenceAudition()
        }
        guard isEnabled(.spatialLive), spatialConfiguration.mode != .off else {
            restoreSpatialBaseIfNeeded()
            return
        }
        let player = PlayerManager.shared
        if spatialBase == nil { captureSpatialBase() }
        guard let spatialBase else { return }
        let resolved = resolvedSpatial(from: spatialBase)
        player.audioEffects.applyMonoTuning(
            EQManager.shared.isEnabled ? EQManager.shared.effectiveMonoEffectTuningForCurrentOutput() : .neutral,
            bassGain: player.audioEffects.bassGain,
            trebleGain: player.audioEffects.trebleGain,
            surroundLevel: resolved.surroundLevel,
            reverbLevel: resolved.reverbLevel,
            stereoWidth: resolved.stereoWidth
        )
        EQManager.shared.updateSafetyLimiter()
        AppLogger.debug(
            "[MonoSpatial] DSP committed mode=\(spatialConfiguration.mode.rawValue) requestedWidth=\(String(format: "%.3f", spatialConfiguration.stageWidth)) requestedDepth=\(String(format: "%.3f", spatialConfiguration.stageDepth)) committedSurround=\(String(format: "%.3f", player.audioEffects.surroundLevel)) committedReverb=\(String(format: "%.3f", player.audioEffects.reverbLevel)) committedWidth=\(String(format: "%.3f", player.audioEffects.stereoWidth))",
            step: "mono-spatial.dsp-commit",
            category: .audio,
            event: "mono-spatial.dsp-commit"
        )
    }

    private func resolvedSpatial(from base: SpatialBase) -> SpatialBase {
        let centerOffset = (0.5 - spatialConfiguration.centerFocus) * 0.14
        let width = min(
            1.85,
            max(0.7, base.stereoWidth * spatialConfiguration.stageWidth * (1 + centerOffset))
        )
        let surround = min(
            0.85,
            max(
                0,
                base.surroundLevel
                    + spatialConfiguration.stageDepth * 0.20
                    + (0.5 - spatialConfiguration.centerFocus) * 0.06
            )
        )
        let reverb = min(0.42, max(0, base.reverbLevel + spatialConfiguration.ambience * 0.18))
        return SpatialBase(
            surroundLevel: surround,
            reverbLevel: reverb,
            stereoWidth: width
        )
    }

    private func captureSpatialBase(proposal: AIEqualizerProposal? = nil) {
        let player = PlayerManager.shared
        let resolvedProposal = proposal ?? AIEqualizerAgent.shared.proposal
        spatialBase = SpatialBase(
            surroundLevel: resolvedProposal?.spatial.surroundLevel ?? player.audioEffects.surroundLevel,
            reverbLevel: resolvedProposal?.spatial.reverbLevel ?? player.audioEffects.reverbLevel,
            stereoWidth: resolvedProposal?.spatial.stereoWidth ?? player.audioEffects.stereoWidth
        )
    }

    private func restoreSpatialBaseIfNeeded() {
        if EQManager.shared.isAuditioningReference {
            EQManager.shared.stopLoudnessMatchedReferenceAudition()
        }
        let player = PlayerManager.shared
        player.streamPlayer.outputPan = 0
        guard let spatialBase else { return }
        player.audioEffects.applyMonoTuning(
            EQManager.shared.isEnabled ? EQManager.shared.effectiveMonoEffectTuningForCurrentOutput() : .neutral,
            bassGain: player.audioEffects.bassGain,
            trebleGain: player.audioEffects.trebleGain,
            surroundLevel: spatialBase.surroundLevel,
            reverbLevel: spatialBase.reverbLevel,
            stereoWidth: spatialBase.stereoWidth
        )
        EQManager.shared.updateSafetyLimiter()
        self.spatialBase = nil
    }

    private func configureHeadTracking(resetCalibration: Bool = false) {
        guard headTrackingRuntimeReady else { return }

        let wantsHeadTracking = isEnabled(.spatialLive)
            && spatialConfiguration.mode == .headTracked
        let route = AVAudioSession.sharedInstance().currentRoute
        let systemSpatialEnabled = route.outputs.contains { $0.isSpatialAudioEnabled }
        let authorization = CMHeadphoneMotionManager.authorizationStatus()
        let authorizationAllowsTracking = authorization != .denied
            && authorization != .restricted

        let shouldTrack = wantsHeadTracking
            // The port flag does not distinguish fixed from tracked system
            // spatial audio. Let either system mode own directional processing.
            && !systemSpatialEnabled
            && authorizationAllowsTracking
            && headphoneMotionManager.isDeviceMotionAvailable
        guard shouldTrack else {
            if headTrackingSessionStarted, systemSpatialEnabled {
                AppLogger.info(
                    "[MonoSpatial] Mono head tracking stopped because system spatial audio is enabled",
                    step: "mono-spatial.system-spatial"
                )
            }
            stopHeadTrackingMotion()
            return
        }

        if resetCalibration,
           headTrackingSessionStarted || headphoneMotionManager.isDeviceMotionActive {
            let now = Date()
            guard now.timeIntervalSince(lastHeadTrackingRestartAt) >= 0.25 else {
                return
            }
            lastHeadTrackingRestartAt = now
            stopHeadTrackingMotion()
        }
        guard !headTrackingSessionStarted,
              !headphoneMotionManager.isDeviceMotionActive else {
            return
        }

        headTrackingSessionID &+= 1
        let sessionID = headTrackingSessionID
        headTrackingSessionStarted = true
        let outputNames = route.outputs.map(\.portName).joined(separator: ",")
        AppLogger.info(
            "[MonoSpatial] Head tracking started output=\(outputNames) systemSpatial=\(systemSpatialEnabled)",
            step: "mono-spatial.tracking-start"
        )

        let handler = Self.makeHeadTrackingHandler(owner: self, sessionID: sessionID)
        headphoneMotionManager.startDeviceMotionUpdates(
            to: headphoneMotionQueue,
            withHandler: handler
        )
    }

    /// Core Motion 在自定义 OperationQueue 回调时不位于 MainActor。
    /// 回调必须由 nonisolated 工厂创建，否则 Swift 6 会继承调用点的
    /// MainActor 隔离并在第一帧运动数据到达时触发 dispatch_assert_queue。
    nonisolated private static func makeHeadTrackingHandler(
        owner: MonoNextSuiteManager,
        sessionID: Int
    ) -> @Sendable (CMDeviceMotion?, Error?) -> Void {
        let processor = MonoHeadTrackingMotionProcessor()
        return { [weak owner] motion, error in
            if let error {
                let detail = error.localizedDescription
                Task { @MainActor [weak owner] in
                    guard let owner, owner.headTrackingSessionID == sessionID else { return }
                    AppLogger.warning(
                        "[MonoSpatial] Headphone motion update failed error=\(detail)",
                        step: "mono-spatial.motion-error"
                    )
                    owner.stopHeadTrackingMotion()
                }
                return
            }
            guard let motion, let normalizedMotion = processor.process(motion) else { return }
            Task { @MainActor [weak owner] in
                owner?.applyHeadMotion(normalizedMotion, sessionID: sessionID)
            }
        }
    }

    private func stopHeadTrackingMotion() {
        headTrackingSessionID &+= 1
        headTrackingSessionStarted = false
        if headphoneMotionManager.isDeviceMotionActive {
            headphoneMotionManager.stopDeviceMotionUpdates()
        }
        currentHeadTrackedPan = 0
        PlayerManager.shared.streamPlayer.outputPan = 0
    }

    private func applyHeadMotion(_ normalizedMotion: Double, sessionID: Int) {
        guard sessionID == headTrackingSessionID,
              isEnabled(.spatialLive),
              spatialConfiguration.mode == .headTracked else {
            return
        }
        let depth = max(0.12, spatialConfiguration.stageDepth)
        let focus = 1 - spatialConfiguration.centerFocus * 0.62
        let target = Float(
            min(0.42, max(-0.42, -normalizedMotion * Double(depth * focus * 0.42)))
        )
        currentHeadTrackedPan = currentHeadTrackedPan * 0.78 + target * 0.22
        PlayerManager.shared.streamPlayer.outputPan = currentHeadTrackedPan
    }

    private func startRecoveryHeartbeat() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoveryHeartbeat()
            }
        }
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 检查长时间未完成的加载，并维护恢复动作的可闻输出验证。
    ///
    /// 每次事故受重试预算约束，防止无法恢复的音频环境触发无限重建。
    private func recoveryHeartbeat() {
        guard isEnabled(.recovery) else { return }
        let player = PlayerManager.shared
        guard player.currentSong != nil else { return }
        let now = Date()

        // 后台会节流 PlaybackTimePublisher；优先读取渲染器 PCM 计数，
        // 避免前台恢复或冷启动时把已经推进的音频误判为卡死。
        refreshAudibleProgress(player: player, now: now)
        guard now.timeIntervalSince(lastRecoveryAt) >= 18 else { return }

        if player.needsPlaybackRestoration
            || player.isSeeking
            || player.isUnderInterruption
            || player.wasPlayingBeforeInterruption {
            lastAudibleAdvanceAt = now
            return
        }

        // EOF 尾音排空期间状态仍为 playing，但输入已经自然结束。此时没有
        // 新 PCM 是正常现象，绝不能重建当前歌曲，否则会从头重播。
        if player.pendingPlaybackPresentationSong == nil,
           (player.streamPlayer.isDrainingEndOfStream
                || player.streamPlayer.isTrackTransitionNotificationDeferred) {
            lastAudibleAdvanceAt = now
            return
        }

        if player.pendingPlaybackPresentationSong == nil,
           isCurrentPlaybackNearNaturalEnd(player) {
            lastAudibleAdvanceAt = now
            return
        }

        guard recoveryAttemptsInIncident < maximumRecoveryAttemptsPerIncident else {
            if !didLogRecoveryBudgetExhaustion {
                didLogRecoveryBudgetExhaustion = true
                AppLogger.error(
                    "[MonoRecovery] incident retry budget exhausted; automatic rebuild stopped",
                    step: "mono-recovery.budget-exhausted"
                )
            }
            return
        }

        // 加载时间戳只属于一个播放代际；新请求替换旧请求后必须重新计时，
        // 否则旧超时会立即重建刚创建的新管线。
        if player.isLoading,
           loadingSessionID != player.playbackSessionId {
            loadingStartedAt = now
            loadingSessionID = player.playbackSessionId
            return
        }

        if let loadingStartedAt,
           loadingSessionID == player.playbackSessionId,
           now.timeIntervalSince(loadingStartedAt) >= 45 {
            performRecovery(reason: "loading-timeout")
            return
        }

    }

    /// 按当前故障状态选择最小恢复动作，并登记待验证结果。
    ///
    /// 恢复顺序为清除假加载、重激活音频会话、重建待切目标，最后才重载当前歌曲。
    private func performRecovery(reason: String) {
        let player = PlayerManager.shared

        if player.pendingPlaybackPresentationSong == nil,
           isCurrentPlaybackNearNaturalEnd(player) {
            lastAudibleAdvanceAt = Date()
            AppLogger.info(
                "[MonoRecovery] ignored near-end recovery reason=\(reason)",
                step: "mono-recovery.near-end-ignored"
            )
            return
        }

        lastRecoveryAt = Date()
        if let pending = pendingRecoveryVerification {
            recordRecoveryEvent(.failure, detail: "\(pending.action.rawValue):verification-timeout")
            pendingRecoveryVerification = nil
        }
        recoveryAttemptsInIncident += 1
        recoveryIncidentAudibleBaseline = player.streamPlayer.totalAudiblePlaybackDuration
        didLogRecoveryBudgetExhaustion = false

        let action: MonoRecoveryAction
        if player.streamPlayer.state == .playing,
           player.streamPlayer.isAudioOutputRunning,
           player.isLoading,
           player.pendingPlaybackPresentationSong == nil {
            player.isLoading = false
            player.refreshPlaybackSurfaceState()
            action = .clearLoadingState
        } else if !player.streamPlayer.isAudioOutputRunning,
                  player.currentSong != nil {
            Task { @MainActor in
                _ = await player.recoverUnavailableAudioOutput(reason: "Mono Recovery: \(reason)")
            }
            action = .reactivateAudioSession
        } else if let target = player.pendingPlaybackPresentationSong {
            player.loadAndPlay(
                song: target,
                startTime: safeRecoveryPosition(
                    player.pendingPlaybackPresentationStartTime,
                    song: target,
                    fallbackDuration: 0
                ),
                fadeInDuration: 0.65,
                fadeInReason: "Mono Recovery pending target"
            )
            action = .rebuildCurrentPipeline
        } else if let song = player.currentSong {
            player.loadAndPlay(
                song: song,
                startTime: safeRecoveryPosition(
                    player.currentTime,
                    song: song,
                    fallbackDuration: player.duration
                ),
                fadeInDuration: 0.7,
                fadeInReason: "Mono Recovery current track",
                preserveRetryBudget: true
            )
            action = .reloadCurrentTrack
        } else {
            action = .none
        }

        recoverySnapshot = store.recordRecoveryAction(action)
        if action == .none {
            recordRecoveryEvent(.failure, detail: "\(action.rawValue):\(reason)")
        } else if action == .clearLoadingState {
            recordRecoveryEvent(.recovered, detail: "\(action.rawValue):\(reason)")
        } else {
            pendingRecoveryVerification = PendingRecoveryVerification(
                action: action,
                reason: reason,
                audibleBaseline: player.streamPlayer.totalAudiblePlaybackDuration
            )
        }
        loadingStartedAt = player.isLoading ? Date() : nil
        loadingSessionID = player.isLoading ? player.playbackSessionId : nil
        lastAudibleDuration = player.streamPlayer.totalAudiblePlaybackDuration
        lastAudibleAdvanceAt = Date()
    }

    private func refreshAudibleProgress(player: PlayerManager, now: Date) {
        let audible = player.streamPlayer.totalAudiblePlaybackDuration
        guard audible > lastAudibleDuration + 0.02 else { return }

        lastAudibleDuration = audible
        lastAudibleAdvanceAt = now

        if let pending = pendingRecoveryVerification,
           audible >= pending.audibleBaseline + 0.75 {
            recordRecoveryEvent(
                .recovered,
                detail: "\(pending.action.rawValue):\(pending.reason)"
            )
            pendingRecoveryVerification = nil
        }

        if recoveryAttemptsInIncident > 0,
           audible >= recoveryIncidentAudibleBaseline + 10 {
            recoveryAttemptsInIncident = 0
            recoveryIncidentAudibleBaseline = audible
            didLogRecoveryBudgetExhaustion = false
        }
    }

    private struct PendingRecoveryVerification {
        let action: MonoRecoveryAction
        let reason: String
        let audibleBaseline: TimeInterval
    }

    private func isCurrentPlaybackNearNaturalEnd(_ player: PlayerManager) -> Bool {
        guard let song = player.currentSong else { return false }
        let expectedDuration = max(
            player.duration,
            Double(song.dt ?? 0) / 1_000
        )
        guard expectedDuration > 1 else { return false }
        let position = min(
            max(player.currentTime, player.streamPlayer.currentTime),
            expectedDuration
        )
        let endGuard = max(3, min(10, expectedDuration * 0.03))
        return position >= expectedDuration - endGuard
    }

    private func safeRecoveryPosition(
        _ requestedPosition: Double,
        song: Song,
        fallbackDuration: Double
    ) -> Double {
        let expectedDuration = max(
            fallbackDuration,
            Double(song.dt ?? 0) / 1_000
        )
        guard expectedDuration > 1 else { return max(0, requestedPosition) }
        return min(max(0, requestedPosition), max(0, expectedDuration - 1))
    }

    private static var currentRouteName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
    }

    private static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static var stemsDirectory: URL {
        applicationSupportURL.appendingPathComponent("MonoStems", isDirectory: true)
    }

}

private struct SpatialBase {
    let surroundLevel: Float
    let reverbLevel: Float
    let stereoWidth: Float
}

/// Converts absolute headphone attitude into a stable, centered motion signal.
///
/// The processor is confined to `headphoneMotionQueue`; keeping calibration
/// and filtering off the main actor prevents sensor delivery from competing
/// with SwiftUI animation work.
private final class MonoHeadTrackingMotionProcessor: @unchecked Sendable {
    private static let calibrationSampleCount = 12
    private static let deadZoneRadians = 2.2 * Double.pi / 180
    private static let recenterRangeRadians = 17 * Double.pi / 180
    private static let maximumSampleJumpRadians = 65 * Double.pi / 180
    private static let minimumEmissionInterval = 1.0 / 45.0

    private var calibrationYaw: [Double] = []
    private var calibrationRoll: [Double] = []
    private var neutralYaw: Double?
    private var neutralRoll: Double?
    private var filteredYaw = 0.0
    private var filteredRoll = 0.0
    private var previousYaw: Double?
    private var previousRoll: Double?
    private var previousTimestamp: TimeInterval?
    private var stationarySince: TimeInterval?
    private var lastEmissionTimestamp: TimeInterval?

    func process(_ motion: CMDeviceMotion) -> Double? {
        let yaw = motion.attitude.yaw
        let roll = motion.attitude.roll
        let timestamp = motion.timestamp
        guard yaw.isFinite, roll.isFinite, timestamp.isFinite else { return nil }

        if let previousYaw,
           let previousRoll,
           let previousTimestamp {
            let elapsed = timestamp - previousTimestamp
            let yawJump = abs(Self.angleDifference(yaw, previousYaw))
            let rollJump = abs(Self.angleDifference(roll, previousRoll))
            let rotationSpeed = Self.rotationMagnitude(motion.rotationRate)
            if elapsed > 0,
               elapsed < 0.08,
               rotationSpeed < 2,
               (yawJump > Self.maximumSampleJumpRadians
                    || rollJump > Self.maximumSampleJumpRadians) {
                return nil
            }
        }

        previousYaw = yaw
        previousRoll = roll

        guard let neutralYaw, let neutralRoll else {
            calibrationYaw.append(yaw)
            calibrationRoll.append(roll)
            previousTimestamp = timestamp
            guard calibrationYaw.count >= Self.calibrationSampleCount else { return nil }
            self.neutralYaw = Self.circularMean(calibrationYaw)
            self.neutralRoll = Self.circularMean(calibrationRoll)
            calibrationYaw.removeAll(keepingCapacity: false)
            calibrationRoll.removeAll(keepingCapacity: false)
            filteredYaw = 0
            filteredRoll = 0
            lastEmissionTimestamp = timestamp
            return 0
        }

        let elapsed = min(0.12, max(1.0 / 120.0, timestamp - (previousTimestamp ?? timestamp)))
        previousTimestamp = timestamp
        var relativeYaw = Self.angleDifference(yaw, neutralYaw)
        var relativeRoll = Self.angleDifference(roll, neutralRoll)

        let rotationSpeed = Self.rotationMagnitude(motion.rotationRate)
        let distanceFromCenter = hypot(relativeYaw, relativeRoll)
        if rotationSpeed < 0.075, distanceFromCenter < Self.recenterRangeRadians {
            if stationarySince == nil {
                stationarySince = timestamp
            } else if timestamp - (stationarySince ?? timestamp) >= 2.6 {
                self.neutralYaw = Self.interpolateAngle(neutralYaw, toward: yaw, fraction: 0.006)
                self.neutralRoll = Self.interpolateAngle(neutralRoll, toward: roll, fraction: 0.006)
                relativeYaw = Self.angleDifference(yaw, self.neutralYaw ?? neutralYaw)
                relativeRoll = Self.angleDifference(roll, self.neutralRoll ?? neutralRoll)
            }
        } else {
            stationarySince = nil
        }

        let smoothing = 1 - exp(-elapsed / 0.085)
        filteredYaw += (relativeYaw - filteredYaw) * smoothing
        filteredRoll += (relativeRoll - filteredRoll) * smoothing

        guard lastEmissionTimestamp.map({ timestamp - $0 >= Self.minimumEmissionInterval }) ?? true else {
            return nil
        }
        lastEmissionTimestamp = timestamp

        let yawSignal = Self.applyingDeadZone(filteredYaw)
        let rollSignal = Self.applyingDeadZone(filteredRoll)
        let combined = sin(yawSignal) * 0.84 + sin(rollSignal) * 0.16
        return min(1, max(-1, combined))
    }

    private static func applyingDeadZone(_ value: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > deadZoneRadians else { return 0 }
        return value.sign == .minus
            ? -(magnitude - deadZoneRadians)
            : magnitude - deadZoneRadians
    }

    private static func angleDifference(_ lhs: Double, _ rhs: Double) -> Double {
        atan2(sin(lhs - rhs), cos(lhs - rhs))
    }

    private static func interpolateAngle(
        _ current: Double,
        toward target: Double,
        fraction: Double
    ) -> Double {
        current + angleDifference(target, current) * fraction
    }

    private static func circularMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sine = values.reduce(0) { $0 + sin($1) }
        let cosine = values.reduce(0) { $0 + cos($1) }
        return atan2(sine / Double(values.count), cosine / Double(values.count))
    }

    private static func rotationMagnitude(_ rate: CMRotationRate) -> Double {
        sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
    }
}

@MainActor
private final class MonoNextSuiteStore {
    private struct Archive: Codable, Sendable {
        var schemaVersion = 1
        var enabledFeatures: Set<MonoNextFeature>
        var flowMode: MonoFlowMode
        var dna: [String: MonoTrackDNA]
        var soundTwinProfile: MonoSoundTwinProfile
        var soundTwinObservations: [MonoSoundTwinObservation]
        var spatialConfiguration: MonoSpatialLiveConfiguration
        var stems: [String: MonoStemsManifest]
        var recoverySnapshot: MonoRecoverySnapshot
    }

    private static let maximumDNAEntries = 4_096
    private static let maximumRecoveryEvents = 160
    private static let recoverySchemaVersion = 2
    private let storageURL: URL?
    private let persistenceQueue = DispatchQueue(
        label: "MonoNextSuite.persistence",
        qos: .utility
    )
    private var archive: Archive

    init() {
        storageURL = Self.makeStorageURL()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let shouldPersistRecoveryMigration: Bool
        if let storageURL,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? decoder.decode(Archive.self, from: data),
           decoded.schemaVersion == 1 {
            var migrated = decoded
            let normalizedRecovery = Self.normalizedRecoverySnapshot(
                decoded.recoverySnapshot
            )
            shouldPersistRecoveryMigration = normalizedRecovery != decoded.recoverySnapshot
            migrated.recoverySnapshot = normalizedRecovery
            archive = migrated
        } else {
            shouldPersistRecoveryMigration = false
            archive = Archive(
                enabledFeatures: [.dna, .recovery],
                flowMode: .seamless,
                dna: [:],
                soundTwinProfile: MonoSoundTwinProfile(),
                soundTwinObservations: [],
                spatialConfiguration: MonoSpatialLiveConfiguration(),
                stems: [:],
                recoverySnapshot: MonoRecoverySnapshot(
                    schemaVersion: Self.recoverySchemaVersion,
                    updatedAt: Date(),
                    events: [],
                    lastAction: .none,
                    consecutiveFailures: 0
                )
            )
        }
        if shouldPersistRecoveryMigration {
            persist()
        }
    }

    var enabledFeatures: Set<MonoNextFeature> { archive.enabledFeatures }
    var flowMode: MonoFlowMode { archive.flowMode }
    var spatialConfiguration: MonoSpatialLiveConfiguration { archive.spatialConfiguration }
    var recoverySnapshot: MonoRecoverySnapshot { archive.recoverySnapshot }

    func dna(for key: String) -> MonoTrackDNA? { archive.dna[key] }
    func setDNA(_ dna: MonoTrackDNA) {
        archive.dna[dna.id] = dna
        if archive.dna.count > Self.maximumDNAEntries {
            archive.dna = Dictionary(
                uniqueKeysWithValues: archive.dna.values
                    .sorted { $0.capturedAt > $1.capturedAt }
                    .prefix(Self.maximumDNAEntries)
                    .map { ($0.id, $0) }
            )
        }
        persist()
    }

    func setEnabledFeatures(_ features: Set<MonoNextFeature>) {
        archive.enabledFeatures = features
        persist()
    }

    func setFlowMode(_ mode: MonoFlowMode) {
        archive.flowMode = mode
        persist()
    }

    func setSpatialConfiguration(_ configuration: MonoSpatialLiveConfiguration) {
        archive.spatialConfiguration = configuration
        persist()
    }

    func purgeRetiredFeatureData() {
        guard !archive.soundTwinObservations.isEmpty
                || archive.soundTwinProfile != MonoSoundTwinProfile()
                || !archive.stems.isEmpty else {
            return
        }
        archive.soundTwinProfile = MonoSoundTwinProfile()
        archive.soundTwinObservations = []
        archive.stems = [:]
        persist()
    }

    func appendRecoveryEvent(_ event: MonoRecoveryEvent) -> MonoRecoverySnapshot {
        var events = archive.recoverySnapshot.events
        if let last = events.last,
           last.kind == event.kind,
           last.songIdentity == event.songIdentity,
           last.sessionID == event.sessionID,
           last.detail == event.detail,
           event.timestamp.timeIntervalSince(last.timestamp) < 30 {
            return archive.recoverySnapshot
        }
        events.append(event)
        events = Array(events.suffix(Self.maximumRecoveryEvents))
        let failures = event.kind == .failure
            ? archive.recoverySnapshot.consecutiveFailures + 1
            : (event.kind == .recovered ? 0 : archive.recoverySnapshot.consecutiveFailures)
        archive.recoverySnapshot = MonoRecoverySnapshot(
            schemaVersion: Self.recoverySchemaVersion,
            updatedAt: Date(),
            events: events,
            lastAction: archive.recoverySnapshot.lastAction,
            consecutiveFailures: failures
        )
        persist()
        return archive.recoverySnapshot
    }

    func recordRecoveryAction(_ action: MonoRecoveryAction) -> MonoRecoverySnapshot {
        archive.recoverySnapshot = MonoRecoverySnapshot(
            schemaVersion: Self.recoverySchemaVersion,
            updatedAt: Date(),
            events: archive.recoverySnapshot.events,
            lastAction: action,
            consecutiveFailures: archive.recoverySnapshot.consecutiveFailures
        )
        persist()
        return archive.recoverySnapshot
    }

    func resetRecoveryHistory() -> MonoRecoverySnapshot {
        archive.recoverySnapshot = MonoRecoverySnapshot(
            schemaVersion: Self.recoverySchemaVersion,
            updatedAt: Date(),
            events: [],
            lastAction: .none,
            consecutiveFailures: 0
        )
        persist()
        return archive.recoverySnapshot
    }

    /// v1 recorded every ordinary player state as a recovery event and wrote a
    /// failure/recovered pair for one action. Keep only real recovery outcomes
    /// and collapse each old pair into a single record.
    private static func normalizedRecoverySnapshot(
        _ snapshot: MonoRecoverySnapshot
    ) -> MonoRecoverySnapshot {
        var events: [MonoRecoveryEvent] = []
        events.reserveCapacity(snapshot.events.count)

        for event in snapshot.events {
            guard event.kind == .failure || event.kind == .recovered else { continue }

            if event.kind == .recovered,
               let last = events.last,
               last.kind == .failure,
               last.songIdentity == event.songIdentity,
               last.sessionID == event.sessionID,
               event.timestamp.timeIntervalSince(last.timestamp) <= 10 {
                events.removeLast()
            }

            if let last = events.last,
               last.kind == event.kind,
               last.songIdentity == event.songIdentity,
               last.sessionID == event.sessionID,
               last.detail == event.detail,
               event.timestamp.timeIntervalSince(last.timestamp) < 30 {
                continue
            }
            events.append(event)
        }

        events = Array(events.suffix(maximumRecoveryEvents))
        let consecutiveFailures = events.reversed().prefix { event in
            event.kind == .failure
        }.count
        return MonoRecoverySnapshot(
            schemaVersion: recoverySchemaVersion,
            updatedAt: snapshot.updatedAt,
            events: events,
            lastAction: snapshot.lastAction,
            consecutiveFailures: consecutiveFailures
        )
    }

    private func persist() {
        guard let storageURL else { return }
        let snapshot = archive
        persistenceQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                AppLogger.error(
                    "[MonoNextSuite] Persistence failed error=\(error.localizedDescription)",
                    step: "mono-next.persistence"
                )
            }
        }
    }

    private static func makeStorageURL() -> URL? {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let suiteDirectory = directory.appendingPathComponent("MonoNextSuite", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: suiteDirectory,
            withIntermediateDirectories: true
        )
        return suiteDirectory.appendingPathComponent("MonoNextSuite-v1.json")
    }
}
