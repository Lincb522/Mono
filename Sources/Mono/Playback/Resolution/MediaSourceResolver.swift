// loadAndPlay 主管线：按歌曲来源（本地 / NCM / QQ / 汽水 / QMC 加密兜底）
// 解析播放地址、下载解密重媒体，并把最终输入装配进 Mono 播放内核。
// 跨界原则：呈现事务（pendingPlaybackPresentation*）与队列快照的提交/回滚
// 全部通过 PlayerManager 的现有内部方法完成，本类不自行拆散事务。

import Foundation
import Combine
import UIKit
import FFmpegSwiftSDK
import QQMusicKit

@MainActor
final class MediaSourceResolver {

    unowned let player: PlayerManager

    init(player: PlayerManager) {
        self.player = player
    }

    // MARK: - 状态

    /// 播放 URL 解析订阅（NCM / QQ / 汽水共用一个槽位）
    var playbackURLCancellable: AnyCancellable?
    /// 重媒体加载任务（汽水下载 / QMC 边下边解密）
    var activeMediaLoadTask: Task<Void, Never>?
    /// Whole-transaction watchdog. Individual provider attempts can each have
    /// their own timeout, so the user-facing load needs one absolute deadline.
    private var loadWatchdogTask: Task<Void, Never>?
    private(set) var activeLoadStartedAt: Date?
    private var activeLoadSessionId: Int?
    private var activeLoadExpectedInput: String?
    private var activeLoadSong: Song?
    private var activeLoadAutoPlay = true
    private static let playbackLoadTimeout: TimeInterval = 20
    private static let appleMusicAuthorizationTimeout: TimeInterval = 90

    // MARK: - 取消

    func cancelPlaybackURLResolution() {
        playbackURLCancellable?.cancel()
        playbackURLCancellable = nil
    }

    func cancelActiveMediaLoad() {
        activeMediaLoadTask?.cancel()
        activeMediaLoadTask = nil
    }

    func cancelLoadWatchdog() {
        loadWatchdogTask?.cancel()
        loadWatchdogTask = nil
        activeLoadStartedAt = nil
        activeLoadSessionId = nil
        activeLoadExpectedInput = nil
        activeLoadSong = nil
        activeLoadAutoPlay = true
    }

    var hasActiveLoad: Bool {
        activeLoadSessionId != nil
    }

    func stateCallbackBelongsToActiveLoad(
        sessionId: Int,
        engineInput: String?
    ) -> Bool {
        // MusicKit owns the committed playback state. FFmpeg may still deliver
        // stop/pause callbacks after its pipeline has been retired.
        guard let activeLoadSessionId else { return !player.appleMusicPlayback.isActive }
        guard activeLoadSessionId == sessionId,
              let activeLoadExpectedInput,
              activeLoadExpectedInput == engineInput else { return false }
        return true
    }

    @discardableResult
    func completeLoadIfCurrent(sessionId: Int, engineInput: String?) -> Bool {
        guard stateCallbackBelongsToActiveLoad(
            sessionId: sessionId,
            engineInput: engineInput
        ) else { return false }
        cancelLoadWatchdog()
        return true
    }

    func ensureLoadWatchdog(
        song: Song,
        sessionId: Int,
        engineInput: String?
    ) {
        if activeLoadSessionId == sessionId {
            return
        }
        armLoadWatchdog(song: song, sessionId: sessionId, autoPlay: true)
        activeLoadExpectedInput = engineInput
    }

    func registerExpectedEngineInput(_ input: String, sessionId: Int) {
        guard activeLoadSessionId == sessionId else { return }
        activeLoadExpectedInput = input
    }

    private func armLoadWatchdog(song: Song, sessionId: Int, autoPlay: Bool) {
        cancelLoadWatchdog()
        activeLoadStartedAt = Date()
        activeLoadSessionId = sessionId
        activeLoadExpectedInput = nil
        activeLoadSong = song
        activeLoadAutoPlay = autoPlay
        let timeout = resolvedLoadTimeout(for: song)
        loadWatchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(timeout * 1_000_000_000)
                )
            } catch {
                return
            }
            guard let self,
                  player.playbackSessionId == sessionId,
                  activeLoadSessionId == sessionId else { return }

            AppLogger.error(
                "[PlaybackLoad] 事务超时 \(Int(timeout))s target=\(song.name) session=\(sessionId)",
                step: "playback.load.timeout"
            )
            expireActiveLoad(
                song: song,
                sessionId: sessionId,
                autoPlay: autoPlay,
                error: APIService.PlaybackError.networkError
            )
        }
    }

    private func resolvedLoadTimeout(for song: Song) -> TimeInterval {
        let foregroundTimeout = song.isAppleMusic
            ? Self.appleMusicAuthorizationTimeout
            : Self.playbackLoadTimeout
        guard player.isAppInBackground
                || UIApplication.shared.applicationState != .active else {
            return foregroundTimeout
        }
        let remaining = UIApplication.shared.backgroundTimeRemaining
        guard remaining.isFinite,
              remaining < Double.greatestFiniteMagnitude else {
            return foregroundTimeout
        }
        return min(foregroundTimeout, max(3, remaining - 2))
    }

    private func expireActiveLoad(
        song: Song,
        sessionId: Int,
        autoPlay: Bool,
        error: Error
    ) {
        guard player.playbackSessionId == sessionId,
              activeLoadSessionId == sessionId else { return }
        let expectedInput = activeLoadExpectedInput
        cancelPlaybackURLResolution()
        cancelActiveMediaLoad()
        player.manualSwitchPreparationTask?.cancel()
        player.manualSwitchPreparationTask = nil
        player.manualPreparedSwitchSessionId = nil
        player.streamPlayer.cancelNextPreparation()

        if let expectedInput,
           player.streamPlayer.currentPlaybackInput == expectedInput {
            switch player.streamPlayer.state {
            case .connecting, .playing, .paused:
                player.suppressStopHandlingUntil = Date().addingTimeInterval(1)
                player.streamPlayer.stop()
            case .idle, .stopped, .error:
                break
            }
        }

        settlePlaybackLoadFailure(
            song: song,
            sessionId: sessionId,
            autoPlay: autoPlay,
            error: error
        )
    }

    @discardableResult
    func handleBackgroundExecutionExpiring() -> Bool {
        guard let song = activeLoadSong,
              let sessionId = activeLoadSessionId else { return false }
        // There is no execution time left for another silent attempt.
        player.networkDisconnectRetryCount = max(
            player.networkDisconnectRetryCount,
            1
        )
        expireActiveLoad(
            song: song,
            sessionId: sessionId,
            autoPlay: activeLoadAutoPlay,
            error: APIService.PlaybackError.networkError
        )
        return true
    }

    /// deinit 清理
    func cancelAll() {
        cancelPlaybackURLResolution()
        cancelActiveMediaLoad()
        cancelLoadWatchdog()
    }

    // MARK: - loadAndPlay 主入口

    func loadAndPlay(
        song: Song,
        autoPlay: Bool = true,
        startTime: Double = 0,
        fadeInDuration: TimeInterval? = nil,
        fadeInReason: String = "",
        preserveRetryBudget: Bool = false,
        historyMutation: PlayerManager.PlaybackHistoryMutation = .automatic
    ) {
        if player.reconcileAlreadyActiveGaplessTarget(song, reason: "load-and-play") {
            player.preresolvedHistoryInput = nil
            return
        }

        let retriesPendingTarget = player.matchesPlaybackTarget(
            player.pendingPlaybackPresentationSong,
            expected: song
        )
        let inheritedQueueCommitSnapshot =
            (preserveRetryBudget || retriesPendingTarget)
            ? player.pendingPlaybackQueueCommitSnapshot
            : nil
        let isNewSong = !player.matchesPlaybackTarget(player.currentSong, expected: song)
        if autoPlay, let fadeInDuration {
            player.sleepAndFade.requestPlaybackStartFade(
                songID: song.id,
                duration: fadeInDuration,
                reason: fadeInReason
            )
        } else {
            // 每次 loadAndPlay 都明确决定是否需要淡入，不能让同一首歌曲
            // 上一次未消费的请求泄漏到音质切换或普通切歌。
            player.clearPlaybackStartFade(restoreVolume: true)
        }
        // 一次性快速通道：进函数即消费，绝不泄漏到下一次加载
        let preresolvedHistoryInput = player.preresolvedHistoryInput
        player.preresolvedHistoryInput = nil
        let preresolvedInput = preresolvedHistoryInput.map {
            (input: $0.input, decryptionKey: $0.decryptionKey)
        } ?? player.preresolvedRestorationInput
        player.preresolvedRestorationInput = nil

        // 后台切歌保活：URL 解析是网络请求，音频停止输出后系统随时可能挂起 App，
        // 申请短时后台任务护住「取 URL → 开播」的空窗期（前台调用时无副作用）。
        player.beginTransitionKeepAlive(reason: "loadAndPlay: \(song.name)")

        if let current = player.currentSong,
           !player.matchesPlaybackTarget(current, expected: song),
           player.pendingPlaybackPresentationSong == nil {
            if historyMutation == .automatic {
                player.pushSongToBackStack(current)
                if player.matchesPlaybackTarget(player.playbackForwardStack.last, expected: song) {
                    player.playbackForwardStack.removeLast()
                } else {
                    player.playbackForwardStack.removeAll()
                }
            }
        }

        // 先建立新会话边界，再取消旧会话的全部异步工作。任何已经排进
        // 主线程队列的旧回调都会因为 session 不匹配而失效。
        player.invalidateInFlightPlaybackWork(reason: "loadAndPlay: \(song.name)")
        player.isHandlingPlaybackFinish = false

        // 播放入口直接消费并维护启动预热缓存：当前曲写入 L1/L2，随后把真实
        // 播放队列中的下一批歌曲放进缓存，避免 OptimizedCacheManager 只预热不使用。
        OptimizedCacheManager.shared.cacheSong(song)
        OptimizedCacheManager.shared.prefetchUpcomingSongs(
            queue: player.currentContextList,
            currentIndex: player.currentIndexInContext
        )
        // 让上一会话遗留的淡出包络失效（其收尾会挂起引擎，不能命中新会话）
        // 先收敛旧包络的中间音量。需要启动淡入的管线会在真正装配前
        // 再明确写入 0；其余加载始终从正常混音台音量开始。
        player.cancelPlaybackFade(restoreVolume: true)
        player.lastPausedAt = nil
        player.pendingRestoreTime = nil
        player.needsPlaybackRestoration = false
        player.shouldAutoResumeAfterRestore = false
        // 恢复窗口已关闭：丢弃上次会话的快速续播资产
        player.restoredPlaybackAsset = nil

        player.isLoading = true
        // 新歌回到全局策略；当前歌曲的手动切换仅在本曲生命周期内有效。
        if isNewSong {
            player.hasManualNeteaseQualityOverride = false
            player.hasManualKugouQualityOverride = false
            player.hasManualQQQualityOverride = false
            player.soundQuality = PlayerManager.initialNeteasePlaybackQuality()
            player.kugouSoundQuality = PlayerManager.initialKugouPlaybackQuality()
            player.qqMusicQuality = PlayerManager.initialQQPlaybackQuality()
        }
        let shouldDeferPresentation = isNewSong
            && (player.currentSong != nil || song.isAppleMusic)
        if shouldDeferPresentation {
            player.deferPendingPlaybackQueueMutationUntilCommit()
            player.pendingPlaybackPresentationSong = song
            player.pendingPlaybackPresentationSessionId = player.playbackSessionId
            player.pendingPlaybackPresentationInput = nil
            player.pendingPlaybackPresentationDecryptionKey = nil
            player.pendingPlaybackPresentationStartTime = max(0, startTime)
            player.pendingPlaybackPresentationResolvedQuality = nil
            player.pendingPlaybackPresentationDuration = nil
            if let inheritedQueueCommitSnapshot {
                // Internal URL/stream retries must retain the user's original
                // target queue instead of snapshotting the audible old queue.
                player.pendingPlaybackQueueCommitSnapshot = inheritedQueueCommitSnapshot
            }
        } else {
            // 重新加载当前可闻歌曲不应误提交上一笔尚未完成的目标队列。
            player.rollbackPendingPlaybackQueueMutationIfNeeded()
            player.clearPendingPlaybackPresentation()
            player.publishPlaybackPresentation(song: song, startTime: startTime)
        }
        player.isCurrentPlaybackUsingLocalFile = false
        if !shouldDeferPresentation {
            player.streamInfo = nil
        }
        // 重试预算属于一次播放事务。只有新的用户请求才重置，内部断流、
        // 音质降级重连必须沿用原预算，保证最终一定收敛。
        if !preserveRetryBudget {
            player.qualitySwitchRecoveryAttempts = 0
            player.networkDisconnectRetryCount = 0
        }
        armLoadWatchdog(
            song: song,
            sessionId: player.playbackSessionId,
            autoPlay: autoPlay
        )

        if song.isAppleMusic {
            loadAndPlayAppleMusic(
                song: song,
                autoPlay: autoPlay,
                startTime: startTime,
                sessionId: player.playbackSessionId
            )
            return
        }

        // 优先使用本地已下载文件
        if let localURL = player.localPlaybackURL(for: song) {
            AppLogger.info("使用本地文件播放: \(song.name)")
            player.isCurrentPlaybackUsingLocalFile = true
            startPlayback(url: localURL, autoPlay: autoPlay, startTime: startTime)
            return
        }
        DownloadManager.shared.enqueueRestoredDownloadIfNeeded(for: song)

        // 冷启动快速续播（小组件/锁屏唤醒）：上次会话已解析的播放输入仍然
        // 新鲜（网络地址在有效期内）或仍然存在（本地缓存文件）时，
        // 跳过整个「取 URL」API 往返直接开播。若地址实际已失效，
        // 播放内核报错后会走静默刷新 URL 重试，用户无感回退到完整取址。
        if let pre = preresolvedInput {
            let url = pre.input.hasPrefix("http")
                ? URL(string: pre.input)
                : URL(fileURLWithPath: pre.input)
            if let url {
                if let resolvedQuality = preresolvedHistoryInput?.resolvedQuality {
                    if player.pendingPlaybackPresentationSessionId == player.playbackSessionId,
                       player.matchesPlaybackTarget(player.pendingPlaybackPresentationSong, expected: song) {
                        player.pendingPlaybackPresentationResolvedQuality = resolvedQuality
                    } else {
                        player.applyResolvedPlaybackQuality(resolvedQuality, for: song)
                    }
                }
                AppLogger.info("快速播放：复用已解析输入 \(song.name)")
                startPlayback(
                    url: url,
                    autoPlay: autoPlay,
                    startTime: startTime,
                    decryptionKey: pre.decryptionKey,
                    preserveRecentInputAge: preresolvedHistoryInput != nil
                )
                return
            }
        }

        // 根据歌曲来源获取播放 URL
        if song.isKugou {
            loadAndPlayKugouSong(song: song, autoPlay: autoPlay, startTime: startTime)
        } else if song.isQishui, let trackId = song.qishuiTrackId {
            loadAndPlayQishuiSong(trackId: trackId, song: song, autoPlay: autoPlay, startTime: startTime)
        } else if song.isQQMusic, let mid = song.qqMid {
            loadAndPlayQQSong(mid: mid, song: song, autoPlay: autoPlay, startTime: startTime)
        } else {
            loadAndPlayNeteaseSong(song: song, autoPlay: autoPlay, startTime: startTime)
        }
    }

    private func loadAndPlayAppleMusic(
        song: Song,
        autoPlay: Bool,
        startTime: Double,
        sessionId: Int
    ) {
        activeMediaLoadTask?.cancel()
        activeMediaLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                guard player.playbackSessionId == sessionId else {
                    throw CancellationError()
                }
                try await player.appleMusicPlayback.start(
                    song: song,
                    autoPlay: autoPlay,
                    startTime: startTime,
                    sessionID: sessionId
                )
                try Task.checkCancellation()
                guard player.playbackSessionId == sessionId else { return }

                cancelLoadWatchdog()
                activeMediaLoadTask = nil
                player.commitAppleMusicPlaybackPresentation(
                    song: song,
                    startTime: startTime,
                    autoPlay: autoPlay,
                    sessionId: sessionId
                )
                player.endTransitionKeepAlive()
            } catch is CancellationError {
                activeMediaLoadTask = nil
            } catch {
                activeMediaLoadTask = nil
                AppLogger.error(
                    "[AppleMusic] 播放失败 target=\(song.name) error=\(error.localizedDescription)",
                    step: "apple-music.playback",
                    context: [
                        "errorDomain": (error as NSError).domain,
                        "errorCode": String((error as NSError).code),
                        "playbackSession": String(sessionId)
                    ]
                )
                settlePlaybackLoadFailure(
                    song: song,
                    sessionId: sessionId,
                    autoPlay: autoPlay,
                    error: error
                )
            }
        }
    }

    /// 统一收口取址、下载和会话激活失败。失败事务必须释放 loading、后台保活
    /// 和待展示目标，否则 EOF 会一直等待一首永远不会提交的歌曲。
    private func settlePlaybackLoadFailure(
        song: Song,
        sessionId: Int,
        autoPlay: Bool,
        error: Error
    ) {
        guard player.playbackSessionId == sessionId else { return }
        cancelLoadWatchdog()
        player.endTransitionKeepAlive()
        let applicationIsInactive = player.isAppInBackground
            || UIApplication.shared.applicationState != .active
        if autoPlay, applicationIsInactive {
            settleInactivePlaybackLoadFailure(
                song: song,
                sessionId: sessionId,
                error: error
            )
            return
        }
        if autoPlay {
            player.showPlaybackError(song: song, error: error)
            return
        }

        _ = player.discardPendingPlaybackPresentationIfNeeded(
            song: song,
            sessionId: sessionId
        )
        player.isPlaying = player.streamPlayer.state == .playing
            && player.streamPlayer.isAudioOutputRunning
        player.isLoading = false
        player.refreshPlaybackSurfaceState()
        player.saveState()
    }

    private func settleInactivePlaybackLoadFailure(
        song: Song,
        sessionId: Int,
        error: Error
    ) {
        let retryable = isRetryableLoadFailure(error)
        if retryable, player.networkDisconnectRetryCount < 1 {
            player.networkDisconnectRetryCount += 1
            let targetsPendingSong = player.matchesPlaybackTarget(
                player.pendingPlaybackPresentationSong,
                expected: song
            )
            let resumeTime = targetsPendingSong
                ? player.pendingPlaybackPresentationStartTime
                : player.currentTime
            PlaybackURLCache.shared.invalidate(song: song)
            AppLogger.warning(
                "[PlaybackLoad] 后台加载失败，静默重试 target=\(song.name) attempt=\(player.networkDisconnectRetryCount)",
                step: "playback.load.background-retry"
            )
            player.loadAndPlay(
                song: song,
                startTime: max(0, resumeTime),
                fadeInDuration: 0.8,
                fadeInReason: "background load retry",
                preserveRetryBudget: true
            )
            return
        }

        let preservedAudibleSong = player.discardPendingPlaybackPresentationIfNeeded(
            song: song,
            sessionId: sessionId
        ) && player.streamPlayer.state == .playing
            && player.streamPlayer.isAudioOutputRunning
        player.isPlaying = preservedAudibleSong
        player.isLoading = false
        player.clearPlaybackStartFade(restoreVolume: true)
        player.refreshPlaybackSurfaceState()
        player.saveState()
        PlaybackURLCache.shared.invalidate(song: song)
        AppLogger.error(
            "[PlaybackLoad] 后台加载最终失败 target=\(song.name) error=\(error.localizedDescription)",
            step: "playback.load.background-failed"
        )

        guard shouldSkipAfterInactiveFailure(error), !preservedAudibleSong else {
            return
        }
        if player.upcomingPlaybackSong() != nil {
            player.next(userInitiated: false)
        } else {
            player.stopAfterQueueExhausted()
        }
    }

    private func isRetryableLoadFailure(_ error: Error) -> Bool {
        if let playbackError = error as? APIService.PlaybackError {
            switch playbackError {
            case .networkError, .unknown:
                return true
            case .unavailable, .tokenRequired, .tokenExpired:
                return false
            }
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return true
    }

    private func shouldSkipAfterInactiveFailure(_ error: Error) -> Bool {
        guard let playbackError = error as? APIService.PlaybackError else {
            return true
        }
        switch playbackError {
        case .networkError, .unknown, .unavailable:
            return true
        case .tokenRequired, .tokenExpired:
            return false
        }
    }

    // MARK: - NCM 管线

    /// 加载并播放ncm歌曲（按当前播放策略解析音质）
    private func loadAndPlayNeteaseSong(song: Song, autoPlay: Bool, startTime: Double) {
        let sessionId = player.playbackSessionId
        playbackURLCancellable?.cancel()
        let isPodcast = player.playbackTargetSource.isPodcast
        let modelReportedLevel = player.modelReportedNeteaseQuality(for: song)?.rawValue
        let shouldAutoSelectHighest = SettingsManager.shared.preferHighestPlaybackQuality
            && !player.hasManualNeteaseQualityOverride
        let requestedQuality: SoundQuality? = shouldAutoSelectHighest ? nil : player.soundQuality
        let urlCacheKey = PlaybackURLCache.neteaseKey(
            id: song.id,
            level: requestedQuality?.rawValue,
            isPodcast: isPodcast
        )

        // 快速通道：短时间内已解析过同一地址（重播 / 来回切歌 / 阶段 A 预取），
        // 直接跳过整个 API 往返
        let cachedNeteaseResult = PlaybackURLCache.shared.fresh(forKey: urlCacheKey)
        if let cached = cachedNeteaseResult {
            AppLogger.info("[URLCache] NCM 命中缓存地址，秒开: \(song.name)")
            handleNeteaseSongUrlResult(
                cached, song: song, autoPlay: autoPlay, startTime: startTime,
                sessionId: sessionId, prefetchedLevel: modelReportedLevel
            )
            return
        }

        Task { @MainActor in
            self.playbackURLCancellable = APIService.shared.fetchSongUrl(
                id: song.id,
                level: requestedQuality?.rawValue,
                prefetchedLevel: modelReportedLevel
            )
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    guard self.player.playbackSessionId == sessionId else { return }
                    if case .failure(let error) = completion {
                        AppLogger.error("获取 NCM 播放 URL 失败: \(error)")
                        if (error as? APIService.PlaybackError) == .unavailable {
                            // 标记为无版权，UI 层据此显示灰色；不再自动跳下一首
                            UnavailableSongsManager.shared.markUnavailable(song: song)
                            AppLogger.info("NCM歌曲无版权，标记灰色: \(song.name)")
                        } else {
                            UnavailableSongsManager.shared.markTransient(song: song)
                        }
                        self.settlePlaybackLoadFailure(
                            song: song,
                            sessionId: sessionId,
                            autoPlay: autoPlay,
                            error: error
                        )
                    }
                }, receiveValue: { [weak self] result in
                    guard let self else { return }
                    guard self.player.playbackSessionId == sessionId else { return }
                    PlaybackURLCache.shared.store(result, forKey: urlCacheKey)
                    self.handleNeteaseSongUrlResult(
                        result, song: song, autoPlay: autoPlay, startTime: startTime,
                        sessionId: sessionId, prefetchedLevel: modelReportedLevel
                    )
                })
        }
    }

    /// NCM 取址成功后的统一处理（网络解析与缓存命中共用）
    private func handleNeteaseSongUrlResult(
        _ result: APIService.SongUrlResult,
        song: Song,
        autoPlay: Bool,
        startTime: Double,
        sessionId: Int,
        prefetchedLevel: String?
    ) {
        guard player.playbackSessionId == sessionId else { return }
        guard let url = URL(string: result.url), !result.url.isEmpty else {
            let error = NSError(
                domain: "PlaybackURL",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "播放地址为空或格式无效"]
            )
            AppLogger.error("NCM 返回无效播放地址: \(song.name)")
            settlePlaybackLoadFailure(
                song: song,
                sessionId: sessionId,
                autoPlay: autoPlay,
                error: error
            )
            return
        }
        // 成功拿到 URL，清掉之前的失败标记
        UnavailableSongsManager.shared.clear(song: song)
        let resolvedQuality = result.actualNeteaseQuality
            ?? prefetchedLevel.flatMap(SoundQuality.init(rawValue:))
        if let resolvedQuality {
            if player.pendingPlaybackPresentationSessionId == sessionId,
               player.matchesPlaybackTarget(player.pendingPlaybackPresentationSong, expected: song) {
                player.pendingPlaybackPresentationResolvedQuality = .netease(
                    songId: song.id,
                    quality: resolvedQuality
                )
            } else {
                player.soundQuality = resolvedQuality
            }
        }

        startPlayback(url: url, autoPlay: autoPlay, startTime: startTime)
    }

    // MARK: - 开播装配（所有来源汇聚点）

    func startPlayback(
        url: URL,
        autoPlay: Bool = true,
        startTime: Double = 0,
        decryptionKey: String? = nil,
        preserveRecentInputAge: Bool = false
    ) {
        player.isLoading = true
        player.scheduleDecryptedAudioCacheCleanup()
        let defersPresentation = player.pendingPlaybackPresentationSessionId == player.playbackSessionId
        let input = url.playerInputString
        if let song = player.pendingPlaybackPresentationSong ?? player.currentSong {
            player.rememberRecentPlaybackInput(
                input,
                decryptionKey: decryptionKey,
                for: song,
                preserveResolvedAt: preserveRecentInputAge
            )
        }
        registerExpectedEngineInput(input, sessionId: player.playbackSessionId)
        if defersPresentation {
            player.pendingPlaybackPresentationInput = input
            player.pendingPlaybackPresentationDecryptionKey = decryptionKey
        }
        player.continuity.cancelScheduledMediaPrefetch()
        player.disarmContinuityEngine()

        if startTime <= 0, !defersPresentation {
            player.currentTime = 0
            if player.duration <= 0, let metaMs = player.currentSong?.dt, metaMs > 0 {
                player.duration = Double(metaMs) / 1000.0
            }
        }

        // 保存当前播放 URL（用于音频分析等功能）
        if !defersPresentation {
            player.currentPlayingURL = input
            // 记录解析时刻：网络地址从此开始老化，恢复播放时超龄会重新取址
            player.playbackURLResolvedAt = Date()
            // 记录解密密钥：单曲循环无缝回绕装配同源管线时需要
            player.currentPlayingDecryptionKey = decryptionKey
        }

        AppLogger.network("开始播放 (FFmpeg): \(url.playerInputString)\(decryptionKey != nil ? " [encrypted]" : "")")

        AppLogger.info("startPlayback session=\(player.playbackSessionId), url=\(url.lastPathComponent)")

        if autoPlay,
           player.sleepAndFade.playbackStartFadeSongID
            == (player.pendingPlaybackPresentationSong ?? player.currentSong)?.id {
            // 先静音装配，等内核真正进入 playing 后再启动包络；网络等待和 seek
            // 都不会提前消耗淡入时长，也不会改动用户的系统音量。
            player.streamPlayer.outputVolume = 0.0
        }

        player.playbackStartedAt = Date()

        // 真正开播前按当前策略激活音频会话（懒激活）：
        // 冷启动 setupAudioSession 只预声明 category、未 setActive。
        // autoPlay=false 只装配暂停管线，不能因为会话恢复/预加载抢占
        // 其他 App 的音频；用户之后主动播放时由 playPlayback 再激活。
        // `.automatic` 也只在实际开播时按最新主音频提示决议 options。
        let activationSessionId = player.playbackSessionId
        Task { @MainActor [weak self] in
            guard let self else { return }
            if autoPlay {
                guard await player.activateAudioSessionForPlaybackChecked(
                    reason: "loadAndPlay start"
                ) else {
                    let song = player.pendingPlaybackPresentationSong ?? player.currentSong
                    let error = NSError(
                        domain: "AudioSession",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "音频输出暂时不可用"]
                    )
                    if let song {
                        settlePlaybackLoadFailure(
                            song: song,
                            sessionId: activationSessionId,
                            autoPlay: false,
                            error: error
                        )
                    } else {
                        player.isLoading = false
                        player.endTransitionKeepAlive()
                        player.refreshPlaybackSurfaceState()
                    }
                    return
                }
            }

            // URL resolution can be superseded while session activation is in
            // flight. Never attach a stale source to the newer playback session.
            guard player.playbackSessionId == activationSessionId else { return }

            // 从 MusicKit 切回 Mono 时，等新管线已经完成取址并即将启动才交出
            // Apple Music 输出，避免在网络解析阶段提前停掉仍在播放的歌曲。
            player.appleMusicPlayback.stopForMonoHandoff()

        // 未命中开播后的预热结果时，不立即 stop 旧管线。先把目标歌曲装进
        // Mono next 通道并完成 preroll，真正 ready 后再丢弃旧尾音热切。
        // fastStart 用更小的预卷门槛尽早开声；装配一旦确定失败立即回退
        // 普通 play 路径（不再傻等超时），最长兜底等待 2 秒。
        if defersPresentation,
           autoPlay,
           startTime <= 0,
           player.streamPlayer.state == .playing {
            let sessionId = player.playbackSessionId
            if player.streamPlayer.currentPlaybackInput == input {
                AppLogger.info(
                    "[ManualSwitch] 目标歌曲已由无缝管线接管，复用现有 transition: \(player.pendingPlaybackPresentationSong?.name ?? "unknown")",
                    step: "playback.manual-switch.already-active"
                )
                player.manualPreparedSwitchSessionId = sessionId
                if player.streamPlayer.isTrackTransitionNotificationDeferred {
                    return
                }
                player.completeManualPreparedSwitch(
                    sessionId: sessionId,
                    engineInput: input
                )
                return
            }
            player.manualPreparedSwitchSessionId = sessionId
            player.streamPlayer.prepareNext(url: input, decryptionKey: decryptionKey, fastStart: true)
            player.manualSwitchPreparationTask?.cancel()
            player.manualSwitchPreparationTask = Task { @MainActor [weak player] in
                guard let player else { return }
                let fallbackToColdLoad: (_ reason: String) -> Void = { [weak player] reason in
                    guard let player else { return }
                    guard player.playbackSessionId == sessionId,
                          player.manualPreparedSwitchSessionId == sessionId else { return }
                    AppLogger.warning(
                        "[ManualSwitch] \(reason)，回退独立管线 target=\(player.pendingPlaybackPresentationSong?.name ?? "unknown")",
                        step: "playback.manual-switch.cold-fallback"
                    )
                    player.streamPlayer.cancelNextPreparation()
                    player.manualPreparedSwitchSessionId = nil
                    player.manualSwitchPreparationTask = nil
                    player.streamPlayer.play(url: input, decryptionKey: decryptionKey)
                }
                for _ in 0..<80 {
                    do {
                        try await Task.sleep(nanoseconds: 25_000_000)
                    } catch {
                        return
                    }
                    guard player.playbackSessionId == sessionId,
                          player.manualPreparedSwitchSessionId == sessionId else { return }
                    if player.streamPlayer.isNextTrackReady {
                        player.streamPlayer.switchToNext()

                        // `switchToNext` is a request to the playback loop, not
                        // proof that ownership changed. Keep watching the actual
                        // engine input; if the handoff is not consumed promptly,
                        // rebuild only the latest target instead of leaving the
                        // whole player in a permanent loading state.
                        for _ in 0..<30 {
                            do {
                                try await Task.sleep(nanoseconds: 25_000_000)
                            } catch {
                                return
                            }
                            guard player.playbackSessionId == sessionId,
                                  player.manualPreparedSwitchSessionId == sessionId else { return }
                            if player.streamPlayer.currentPlaybackInput == input,
                               !player.streamPlayer.isTrackTransitionNotificationDeferred {
                                player.completeManualPreparedSwitch(
                                    sessionId: sessionId,
                                    engineInput: input
                                )
                                return
                            }
                        }
                        fallbackToColdLoad("预装管线交接未完成")
                        return
                    }
                    if player.streamPlayer.hasNextPreparationFailed {
                        fallbackToColdLoad("目标管线预热失败")
                        return
                    }
                    switch player.streamPlayer.state {
                    case .idle, .stopped, .error:
                        fallbackToColdLoad("旧管线已结束")
                        return
                    case .connecting, .playing, .paused:
                        break
                    }
                }

                guard player.playbackSessionId == sessionId,
                      player.manualPreparedSwitchSessionId == sessionId else { return }
                fallbackToColdLoad("目标管线预热超时")
            }
            return
        }

        // 续播位置与暂停意图直接交给 Mono 管线，首段 PCM 预填充前
        // 就完成 seek，避免先播开头再跳转，也不再依赖延时 pause。
        if startTime > 0 {
            if !defersPresentation {
                player.currentTime = startTime
                LyricViewModel.shared.updateCurrentTime(startTime)
            }
            player.isSeeking = true
            player.seekTargetTime = startTime
            player.seekStartedAt = Date()
        }

        player.streamPlayer.play(
            url: url.playerInputString,
            decryptionKey: decryptionKey,
            startTime: max(0, startTime),
            autoPlay: autoPlay
        )

            if !defersPresentation {
                player.updateNowPlayingInfo()
                player.updateNowPlayingArtwork(for: player.currentSong)
            }
        }
    }

    // MARK: - 酷狗管线

    private func loadAndPlayKugouSong(song: Song, autoPlay: Bool, startTime: Double) {
        let sessionId = player.playbackSessionId
        playbackURLCancellable?.cancel()
        let requestedQuality = player.kugouSoundQuality
        let cacheKey = PlaybackURLCache.kugouKey(
            hash: song.kugouHash ?? String(song.id),
            quality: requestedQuality.rawValue
        )
        let startResolvedPlayback: (KCMPlaybackURLResult) -> Void = { [weak self] result in
            guard let self, self.player.playbackSessionId == sessionId else { return }
            let resolvedQuality = PlayerManager.ResolvedPlaybackQuality.kugou(
                hash: song.kugouHash ?? String(song.id),
                quality: result.quality
            )
            if self.player.pendingPlaybackPresentationSessionId == sessionId,
               self.player.matchesPlaybackTarget(self.player.pendingPlaybackPresentationSong, expected: song) {
                self.player.pendingPlaybackPresentationResolvedQuality = resolvedQuality
            } else {
                self.player.applyResolvedPlaybackQuality(resolvedQuality, for: song)
            }
            UnavailableSongsManager.shared.clear(song: song)
            self.startPlayback(url: result.url, autoPlay: autoPlay, startTime: startTime)
        }

        if let cached = PlaybackURLCache.shared.freshKugou(forKey: cacheKey) {
            AppLogger.info("[URLCache] KCM 命中缓存地址，秒开: \(song.name)")
            startResolvedPlayback(cached)
            return
        }

        playbackURLCancellable = APIService.shared.fetchKugouSongURL(
            song: song,
            quality: requestedQuality
        )
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self, self.player.playbackSessionId == sessionId else { return }
                if case .failure(let error) = completion {
                    AppLogger.error("[Kugou] 获取播放 URL 失败: \(error.localizedDescription)")
                    self.settlePlaybackLoadFailure(
                        song: song,
                        sessionId: sessionId,
                        autoPlay: autoPlay,
                        error: error
                    )
                }
            }, receiveValue: { [weak self] result in
                guard let self, self.player.playbackSessionId == sessionId else { return }
                PlaybackURLCache.shared.storeKugou(result, forKey: cacheKey)
                startResolvedPlayback(result)
            })
    }

    // MARK: - QQ 管线

    /// 加载并播放 qcm歌曲（按当前播放策略解析音质）
    private func loadAndPlayQQSong(mid: String, song: Song, autoPlay: Bool, startTime: Double) {
        let sessionId = player.playbackSessionId
        playbackURLCancellable?.cancel()
        let modelReportedQuality = song.qqMaxQuality
        let shouldAutoSelectHighest = SettingsManager.shared.preferHighestPlaybackQuality
            && !player.hasManualQQQualityOverride
        let requestedQuality: QQMusicQuality? = shouldAutoSelectHighest ? nil : player.qqMusicQuality
        let urlCacheKey = PlaybackURLCache.qqKey(mid: mid, quality: requestedQuality?.rawValue)

        // 快速通道：命中短时地址缓存直接开播（跳过 API 往返）
        let cachedQQResult = PlaybackURLCache.shared.fresh(forKey: urlCacheKey)
        if let cached = cachedQQResult {
            AppLogger.info("[URLCache] QQ 命中缓存地址，秒开: \(song.name)")
            handleQQSongUrlResult(
                cached, song: song, autoPlay: autoPlay, startTime: startTime,
                sessionId: sessionId
            )
            return
        }

        Task { @MainActor in
            self.playbackURLCancellable = APIService.shared.fetchQQSongUrl(
                mid: mid,
                quality: requestedQuality,
                prefetchedQuality: modelReportedQuality
            )
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    guard self.player.playbackSessionId == sessionId else { return }
                    if case .failure(let error) = completion {
                        AppLogger.error("[QQMusic] 获取播放 URL 失败: \(error)")
                        // 标记失败：unavailable 走无版权，其他走 transient
                        if (error as? APIService.PlaybackError) == .unavailable {
                            UnavailableSongsManager.shared.markUnavailable(song: song)
                            AppLogger.info("[QQMusic] 数字专辑未购/无版权，标记灰色: \(song.name)")
                        } else {
                            UnavailableSongsManager.shared.markTransient(song: song)
                        }
                        self.settlePlaybackLoadFailure(
                            song: song,
                            sessionId: sessionId,
                            autoPlay: autoPlay,
                            error: error
                        )
                    }
                }, receiveValue: { [weak self] result in
                    guard let self else { return }
                    guard self.player.playbackSessionId == sessionId else { return }
                    PlaybackURLCache.shared.store(result, forKey: urlCacheKey)
                    self.handleQQSongUrlResult(
                        result, song: song, autoPlay: autoPlay, startTime: startTime,
                        sessionId: sessionId
                    )
                })
        }
    }

    /// QQ 取址成功后的统一处理（网络解析与缓存命中共用）
    private func handleQQSongUrlResult(
        _ result: APIService.SongUrlResult,
        song: Song,
        autoPlay: Bool,
        startTime: Double,
        sessionId: Int
    ) {
        guard player.playbackSessionId == sessionId else { return }
        guard let url = URL(string: result.url), !result.url.isEmpty else {
            let error = NSError(
                domain: "PlaybackURL",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "播放地址为空或格式无效"]
            )
            AppLogger.error("QQ 音乐返回无效播放地址: \(song.name)")
            settlePlaybackLoadFailure(
                song: song,
                sessionId: sessionId,
                autoPlay: autoPlay,
                error: error
            )
            return
        }
        // 成功 → 清掉之前的失败标记
        UnavailableSongsManager.shared.clear(song: song)
        if let actual = result.actualQQQuality {
            if player.pendingPlaybackPresentationSessionId == sessionId,
               player.matchesPlaybackTarget(player.pendingPlaybackPresentationSong, expected: song) {
                player.pendingPlaybackPresentationResolvedQuality = .qq(mid: song.qqMid ?? "", quality: actual)
            } else {
                player.qqMusicQuality = actual
            }
        }

        if result.requiresQMCDecryption, let ekey = result.qmcEkey {
            if SettingsManager.shared.qmcDecryptEnabled {
                AppLogger.info("[QQMusic] Cookie 封控兜底，开始本地解密: \(song.name)")
                downloadDecryptAndPlay(
                    url: url, ekey: ekey, song: song,
                    autoPlay: autoPlay, startTime: startTime,
                    sessionId: sessionId
                )
            } else {
                settlePlaybackLoadFailure(
                    song: song,
                    sessionId: sessionId,
                    autoPlay: autoPlay,
                    error: APIService.PlaybackError.unavailable
                )
            }
        } else {
            AppLogger.info("[QQMusic] 普通直链开始播放: \(song.name)")
            startPlayback(url: url, autoPlay: autoPlay, startTime: startTime)
        }
    }

    // MARK: - 汽水音乐管线

    private func loadAndPlayQishuiSong(trackId: Int, song: Song, autoPlay: Bool, startTime: Double) {
        let sessionId = player.playbackSessionId
        playbackURLCancellable?.cancel()

        AppLogger.info("[Qishui] 获取播放信息: \(song.name) (trackId=\(trackId))")
        let shouldAutoSelectHighest = SettingsManager.shared.preferHighestPlaybackQuality
        let requestedQuality = shouldAutoSelectHighest ? "lossless" : player.qishuiSelectedQuality

        Task { @MainActor in
            self.playbackURLCancellable = APIService.shared.fetchQishuiSongUrl(trackId: trackId, quality: requestedQuality)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    guard let self, self.player.playbackSessionId == sessionId else { return }
                    if case .failure(let error) = completion {
                        AppLogger.error("[Qishui] 获取播放 URL 失败: \(error)")
                        self.settlePlaybackLoadFailure(
                            song: song,
                            sessionId: sessionId,
                            autoPlay: autoPlay,
                            error: error
                        )
                    }
                }, receiveValue: { [weak self] result in
                    guard let self else { return }
                    guard self.player.playbackSessionId == sessionId else { return }
                    guard !result.url.isEmpty else {
                        let error = NSError(
                            domain: "PlaybackURL",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "汽水音乐播放地址为空"]
                        )
                        AppLogger.error("[Qishui] 返回空播放地址: \(song.name)")
                        self.settlePlaybackLoadFailure(
                            song: song,
                            sessionId: sessionId,
                            autoPlay: autoPlay,
                            error: error
                        )
                        return
                    }

                    if self.player.pendingPlaybackPresentationSessionId == sessionId,
                       self.player.matchesPlaybackTarget(self.player.pendingPlaybackPresentationSong, expected: song) {
                        self.player.pendingPlaybackPresentationResolvedQuality = .qishui(
                            trackId: trackId,
                            quality: result.quality
                        )
                    } else {
                        self.player.qishuiSelectedQuality = result.quality
                    }
                    self.downloadAndPlayQishuiAudio(
                        cdnUrl: result.url,
                        decryptionKey: result.decryptionKey,
                        trackId: trackId,
                        song: song,
                        quality: result.quality,
                        sessionId: sessionId,
                        autoPlay: autoPlay,
                        startTime: startTime
                    )
                })
        }
    }

    private func downloadAndPlayQishuiAudio(
        cdnUrl: String,
        decryptionKey: String?,
        trackId: Int,
        song: Song,
        quality: String,
        sessionId: Int,
        autoPlay: Bool,
        startTime: Double
    ) {
        let ext = decryptionKey != nil ? "enc.mp4" : "m4a"
        let cacheFile = DecryptedAudioCacheGovernor.qishuiCacheDir
            .appendingPathComponent("\(trackId)_\(quality).\(ext)")

        if FileManager.default.fileExists(atPath: cacheFile.path) {
            AppLogger.info("[Qishui] 使用缓存: \(cacheFile.lastPathComponent)")
            DecryptedAudioCacheGovernor.touchCacheFile(at: cacheFile)
            startPlayback(url: cacheFile, autoPlay: autoPlay, startTime: startTime, decryptionKey: decryptionKey)
            return
        }

        guard let url = URL(string: cdnUrl) else {
            AppLogger.error("[Qishui] 无效的 CDN URL")
            let error = NSError(
                domain: "PlaybackURL",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "汽水音乐 CDN 地址无效"]
            )
            settlePlaybackLoadFailure(
                song: song,
                sessionId: sessionId,
                autoPlay: autoPlay,
                error: error
            )
            return
        }

        activeMediaLoadTask?.cancel()
        activeMediaLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.player.playbackSessionId == sessionId {
                    self.activeMediaLoadTask = nil
                }
            }

            do {
                var request = URLRequest(url: url)
                request.setValue("https://www.qishui.com", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                request.networkServiceType = .responsiveData

                let downloadStart = CFAbsoluteTimeGetCurrent()
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                let elapsed = CFAbsoluteTimeGetCurrent() - downloadStart

                try Task.checkCancellation()
                guard self.player.playbackSessionId == sessionId else { return }

                let httpResponse = response as? HTTPURLResponse
                guard httpResponse?.statusCode == 200 else {
                    let code = httpResponse?.statusCode ?? -1
                    throw NSError(domain: "QishuiPlayback", code: code, userInfo: [
                        NSLocalizedDescriptionKey: "CDN 下载失败 HTTP \(code)"
                    ])
                }

                if FileManager.default.fileExists(atPath: cacheFile.path) {
                    try? FileManager.default.removeItem(at: temporaryURL)
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: cacheFile)
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
                let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard fileSize > 0 else {
                    throw NSError(domain: "QishuiPlayback", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "CDN 下载文件为空"
                    ])
                }
                AppLogger.info("[Qishui] 下载完成 (\(fileSize / 1024)KB, \(String(format: "%.1f", elapsed))s), key=\(decryptionKey?.prefix(8) ?? "none")")

                try Task.checkCancellation()
                guard self.player.playbackSessionId == sessionId else { return }
                self.startPlayback(url: cacheFile, autoPlay: autoPlay, startTime: startTime, decryptionKey: decryptionKey)
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.error("[Qishui] 下载失败: \(error.localizedDescription)")
                guard self.player.playbackSessionId == sessionId else { return }
                self.settlePlaybackLoadFailure(
                    song: song,
                    sessionId: sessionId,
                    autoPlay: autoPlay,
                    error: error
                )
            }
        }
    }

    // MARK: - QMC 解密播放

    /// 下载加密文件 → QMC 解密 → 保存临时文件 → 播放（带缓存）
    private func downloadDecryptAndPlay(
        url: URL, ekey: String, song: Song,
        autoPlay: Bool, startTime: Double, sessionId: Int
    ) {
        activeMediaLoadTask?.cancel()
        activeMediaLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.player.playbackSessionId == sessionId {
                    self.activeMediaLoadTask = nil
                }
            }

            do {
                try Task.checkCancellation()
                let ext = url.pathExtension.contains("mflac") ? "flac"
                         : url.pathExtension.contains("mgg") ? "ogg"
                         : "flac"
                let cachedFile = DecryptedAudioCacheGovernor.qmcCacheURL(for: song, extension: ext)

                if FileManager.default.fileExists(atPath: cachedFile.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: cachedFile.path),
                   let size = attrs[.size] as? Int, size > 1024 {
                    AppLogger.success("[QMC] 命中缓存，跳过下载解密: \(cachedFile.lastPathComponent) (\(size / 1024)KB)")
                    try Task.checkCancellation()
                    guard self.player.playbackSessionId == sessionId else { return }
                    DecryptedAudioCacheGovernor.touchCacheFile(at: cachedFile)
                    self.startPlayback(url: cachedFile, autoPlay: autoPlay, startTime: startTime)
                    return
                }

                let decryptor = try QMCDecryptor.create(ekey: ekey)

                // 边下边解密：分块到达即按偏移解密落盘，省掉整段串行解密时间
                AppLogger.info("[QMC] 开始流式下载解密...")
                let downloadStart = CFAbsoluteTimeGetCurrent()
                let downloader = QMCStreamDownloader(decryptor: decryptor, destination: cachedFile)
                let byteCount = try await downloader.download(from: url, priority: URLSessionTask.highPriority)
                let downloadTime = CFAbsoluteTimeGetCurrent() - downloadStart

                guard self.player.playbackSessionId == sessionId else { return }

                AppLogger.success("[QMC] 下载+解密完成 (\(byteCount / 1024)KB，耗时 \(String(format: "%.1f", downloadTime))s): \(cachedFile.lastPathComponent)")

                await MainActor.run {
                    guard self.player.playbackSessionId == sessionId else { return }
                    self.startPlayback(url: cachedFile, autoPlay: autoPlay, startTime: startTime)
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.error("[QMC] 解密播放失败: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.player.playbackSessionId == sessionId else { return }
                    self.settlePlaybackLoadFailure(
                        song: song,
                        sessionId: sessionId,
                        autoPlay: autoPlay,
                        error: error
                    )
                }
            }
        }
    }
}

// MARK: - PlayerManager facade（112 个外部调用点保持不变）

extension PlayerManager {

    func loadAndPlay(
        song: Song,
        autoPlay: Bool = true,
        startTime: Double = 0,
        fadeInDuration: TimeInterval? = nil,
        fadeInReason: String = "",
        preserveRetryBudget: Bool = false,
        historyMutation: PlaybackHistoryMutation = .automatic
    ) {
        mediaResolver.loadAndPlay(
            song: song,
            autoPlay: autoPlay,
            startTime: startTime,
            fadeInDuration: fadeInDuration,
            fadeInReason: fadeInReason,
            preserveRetryBudget: preserveRetryBudget,
            historyMutation: historyMutation
        )
    }
}
