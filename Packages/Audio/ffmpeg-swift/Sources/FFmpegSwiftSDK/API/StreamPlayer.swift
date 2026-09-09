// StreamPlayer.swift
// FFmpegSwiftSDK
//
// Public API for streaming media playback. Orchestrates ConnectionManager,
// Demuxer, AudioDecoder, VideoDecoder, EQFilter, AudioRenderer, VideoRenderer,
// and AVSyncController into a unified playback pipeline.

import Foundation
import CFFmpeg
import AudioToolbox
import AVFoundation

// MARK: - PlaybackState

/// Represents the current state of the stream player.
public enum PlaybackState: Equatable {
    /// No playback session is active.
    case idle
    /// Connecting to the media source.
    case connecting
    /// Actively playing audio/video.
    case playing
    /// Playback is paused.
    case paused
    /// Playback has been stopped.
    case stopped
    /// An error occurred during playback.
    case error(FFmpegError)
}

/// Identifies why the most recent `.stopped` state was emitted.
///
/// A stopped player no longer has a live renderer clock, so the app layer must
/// not infer natural EOF from `currentTime` after receiving the callback.
public enum PlaybackStopReason: Equatable, Sendable {
    /// Playback was stopped explicitly by a caller.
    case explicit
    /// The decoder reached EOF and the renderer drained its audible tail.
    case endOfStream
}

// MARK: - StreamPlayerDelegate

/// Delegate protocol for receiving playback state changes, errors, and duration updates.
public protocol StreamPlayerDelegate: AnyObject {
    /// Called when the player's playback state changes.
    func player(_ player: StreamPlayer, didChangeState state: PlaybackState)
    /// Called when the player encounters an error.
    func player(_ player: StreamPlayer, didEncounterError error: FFmpegError)
    /// Called when the player updates the current playback duration/time.
    func player(_ player: StreamPlayer, didUpdateDuration duration: TimeInterval)
    /// Called with the exact input that produced the measured duration.
    ///
    /// The input identity prevents a delayed main-queue callback from applying
    /// an old pipeline's duration after a prepared-track handoff.
    func player(
        _ player: StreamPlayer,
        didUpdateDuration duration: TimeInterval,
        forPlaybackInput playbackInput: String
    )
    /// 无缝切歌：当前歌曲播放完毕，已自动切换到预加载的下一首
    func playerDidTransitionToNextTrack(_ player: StreamPlayer)
}

public extension StreamPlayerDelegate {
    func player(
        _ player: StreamPlayer,
        didUpdateDuration duration: TimeInterval,
        forPlaybackInput _: String
    ) {
        self.player(player, didUpdateDuration: duration)
    }
}

// MARK: - StreamPlayer

/// A streaming media player that connects to a URL, demuxes, decodes, and renders audio/video.
///
/// `StreamPlayer` provides a simple API for playback control: `play(url:)`, `pause()`,
/// `resume()`, and `stop()`. Internally it orchestrates the full pipeline:
/// `ConnectionManager → Demuxer → Decoder → EQFilter → Renderer`.
///
/// Demuxing and decoding run on a dedicated background `DispatchQueue` to avoid
/// blocking the main thread. State changes are communicated via `StreamPlayerDelegate`.
///
/// Usage:
/// ```swift
/// let player = StreamPlayer()
/// player.delegate = self
/// player.play(url: "rtmp://example.com/live/stream")
/// // ...
/// player.pause()
/// player.resume()
/// player.stop()
/// ```
public final class StreamPlayer {

    // MARK: - Public Properties

    /// Delegate for receiving state changes, errors, and duration updates.
    public weak var delegate: StreamPlayerDelegate?

    /// The current playback state.
    ///
    /// State is stored on `stateQueue`, while delegate delivery happens after the
    /// queue is released. This keeps public reads race-free and prevents delegates
    /// that call back into the player from deadlocking the state queue.
    public var state: PlaybackState {
        stateQueue.sync { storedState }
    }

    private var storedState: PlaybackState = .idle

    /// Why the latest `.stopped` state was emitted.
    public var lastStopReason: PlaybackStopReason {
        stateQueue.sync { storedLastStopReason }
    }
    private var storedLastStopReason: PlaybackStopReason = .explicit

    /// Final audible position captured before the renderer clock is cleared.
    ///
    /// `currentTime` normally becomes zero as part of renderer teardown. This
    /// snapshot remains available to delegate callbacks for progress and
    /// diagnostics after either EOF or an error.
    public var lastTerminalPlaybackTime: TimeInterval {
        stateQueue.sync { storedLastTerminalPlaybackTime }
    }
    private var storedLastTerminalPlaybackTime: TimeInterval = 0

    /// The current playback time in seconds.
    /// 实际播放位置 = 解码位置 - 缓冲队列中尚未播放的时长
    public var currentTime: TimeInterval {
        let deferredTransition = stateQueue.sync {
            (
                deadline: audibleTransitionDeadline,
                previousDuration: storedPreviousTrackActualDuration,
                transitionStartedAt: audibleTransitionStartedAt,
                displayStartTime: previousTrackDisplayStartTime
            )
        }
        if let deadline = deferredTransition.deadline,
           let previousDuration = deferredTransition.previousDuration,
           let transitionStartedAt = deferredTransition.transitionStartedAt,
           let displayStartTime = deferredTransition.displayStartTime,
           Date() < deadline {
            let elapsed = max(0, Date().timeIntervalSince(transitionStartedAt))
            return min(previousDuration, max(0, displayStartTime + elapsed))
        }

        if let renderedTime = audioRenderer.currentPresentationTime,
           renderedTime.isFinite,
           !renderedTime.isNaN {
            return max(0, renderedTime)
        }

        let decoded = stateQueue.sync { self.decodedTime }
        return max(0, decoded - audioRenderer.queuedDuration)
    }

    /// 解码线程更新的已解码时间（入队时间点，非实际播放时间点）
    private var decodedTime: TimeInterval = 0

    /// 无缝切歌时，上一首歌曲的实际解码时长（EOF 时的 decodedTime）
    public var previousTrackActualDuration: TimeInterval? {
        stateQueue.sync { storedPreviousTrackActualDuration }
    }
    private var storedPreviousTrackActualDuration: TimeInterval?

    /// Metadata about the currently playing stream, or `nil` if not connected.
    public var streamInfo: StreamInfo? {
        stateQueue.sync { storedStreamInfo }
    }
    private var storedStreamInfo: StreamInfo?

    /// The public audio equalizer for adjusting frequency band gains.
    public let equalizer: AudioEqualizer

    /// 音频效果控制器：音量、变速、响度标准化。
    public let audioEffects: AudioEffects

    /// 实时频谱分析器。设置 onSpectrum 回调并启用后，
    /// 每个 FFT 窗口会回调一次频率幅度数据。
    public let spectrumAnalyzer: SpectrumAnalyzer

    /// 独立的播放前分析器。其输入位于 EQ、音效和修复处理之前，供测量任务使用。
    public let analysisSpectrumAnalyzer: SpectrumAnalyzer

    /// 波形预览生成器。独立于播放 pipeline，可在后台生成波形数据。
    public let waveformGenerator: WaveformGenerator

    /// 元数据读取器。读取音频文件的 ID3 标签、专辑封面等。
    public let metadataReader: MetadataReader

    /// 歌词同步引擎。加载 LRC 歌词后，根据播放时间实时匹配当前行。
    ///
    /// ```swift
    /// player.lyricSyncer.load(lrcContent: lrcString)
    /// player.lyricSyncer.onSync = { lineIndex, line, wordIndex, progress in
    ///     // 更新 UI：高亮当前行
    /// }
    /// ```
    public let lyricSyncer: LyricSyncer

    /// 音频修复引擎。自动检测并修复削波、电流声、卡顿、爆音等问题。
    ///
    /// 推荐在播放开始时一键启用：
    /// ```swift
    /// player.audioRepair.enableAll()
    /// ```
    /// 也可按需单独启用：
    /// ```swift
    /// player.audioRepair.isDeclipEnabled = true
    /// player.audioRepair.isSoftLimiterEnabled = true
    /// ```
    public var audioRepair: AudioRepairEngine { repairEngine }
    
    /// 音频数据回调。在音频渲染线程调用，用于实时音频分析、识别等。
    /// 回调参数：PCM Float32 数据、帧数、声道数、采样率
    public var onAudioData: ((_ samples: UnsafePointer<Float>, _ frameCount: Int, _ channelCount: Int, _ sampleRate: Int) -> Void)? {
        didSet {
            audioRenderer.onAudioData = onAudioData
        }
    }

    /// The video display layer. Add this to your view's layer hierarchy to show video.
    ///
    /// Usage (UIKit):
    /// ```swift
    /// view.layer.addSublayer(player.videoDisplayLayer)
    /// player.videoDisplayLayer.frame = view.bounds
    /// ```
    public var videoDisplayLayer: AVSampleBufferDisplayLayer {
        return videoRenderer.sampleBufferDisplayLayer
    }

    /// 视频是否正在使用 VideoToolbox 硬件加速解码。
    /// 仅在播放视频流时有意义，无视频时返回 false。
    public var isVideoHardwareAccelerated: Bool {
        return stateQueue.sync { videoDecoder?.isHardwareAccelerated ?? false }
    }

    // MARK: - Internal Components

    /// The EQ filter used for audio processing.
    internal let eqFilter: EQFilter

    /// FFmpeg avfilter 音频滤镜图（loudnorm、atempo、volume）
    internal let audioFilterGraph: AudioFilterGraph

    /// 音频修复引擎
    internal let repairEngine: AudioRepairEngine

    /// The connection manager for establishing media connections.
    private var connectionManager: ConnectionManager?

    /// The demuxer for separating audio/video packets.
    private var demuxer: Demuxer?

    /// The audio decoder.
    private var audioDecoder: AudioDecoder?

    /// The video decoder.
    private var videoDecoder: VideoDecoder?

    /// The audio renderer.
    private let audioRenderer: AudioRenderer

    /// The video renderer.
    private let videoRenderer: VideoRenderer

    /// The A/V sync controller.
    private let syncController: AVSyncController

    // MARK: - Queues & State

    /// Dedicated background queue for demuxing and decoding.
    /// Decoding runs ahead into a multi-second PCM queue, so it does not need
    /// UI-event priority. Keeping it at userInteractive made long playback
    /// compete with system/UI work and accelerated thermal throttling.
    private let playbackQueue = DispatchQueue(
        label: "com.ffmpeg-sdk.playback",
        qos: .userInitiated
    )

    /// Video decode and presentation waits never block audio packet consumption.
    private let videoDecodeQueue = DispatchQueue(
        label: "com.ffmpeg-sdk.video-decode",
        qos: .userInitiated
    )
    private let videoPacketLock = NSLock()
    private var pendingVideoPacketCount = 0
    private let maxPendingVideoPackets = 12
    /// Invalidates compressed video packets queued before a seek or pipeline swap.
    private var videoPipelineEpoch: UInt64 = 0

    /// Serial queue for synchronizing state changes.
    private let stateQueue = DispatchQueue(label: "com.ffmpeg-sdk.player-state")

    private let resourceCleanupQueue = DispatchQueue(
        label: "com.ffmpeg-sdk.resource-cleanup", qos: .utility
    )

    /// Flag indicating whether the playback loop should continue.
    private var isPlaybackActive: Bool = false

    /// Monotonically increasing playback generation. Every `play` / `stop`
    /// invalidates older connection and decode jobs so rapid A → B → C switching
    /// cannot let an earlier queued pipeline become active again.
    private var playbackGeneration: UInt64 = 0

    /// The demuxer has reached EOF and the renderer is only draining the final
    /// audible tail. App-level watchdogs must not treat this quiet window as a
    /// stalled stream and rebuild the current track from the beginning.
    private var endOfStreamDrainActive = false

    /// The URL of the current playback session.
    private var currentURL: String?

    /// The exact input currently owned by the active decoder pipeline.
    /// App-layer presentation code uses this identity to reject stale state
    /// callbacks instead of advancing metadata from state alone.
    public var currentPlaybackInput: String? {
        stateQueue.sync { currentURL }
    }

    /// Seek 请求：播放循环会检查此值并在安全时刻执行 seek
    private var pendingSeekTime: TimeInterval? = nil
    /// 每次 seek 都递增。旧 seek 在预卷期间若被新目标取代，不能再 flush
    /// 音频队列或提交旧位置，尤其用于连续向后拖动。
    private var pendingSeekGeneration: UInt64 = 0
    private let seekLock = NSLock()

    /// A restored starting position and paused intent are consumed by the new
    /// pipeline before its first PCM is allowed to reach the output device.
    private var requiredInitialSeekPosition: TimeInterval?
    private var startsPausedGeneration: UInt64?

    /// seek 后的目标时间，用于抑制 seek 点之前的旧 PTS 更新 currentTime
    /// demuxer seek 到关键帧（通常在目标之前），解码出的前几个 packet PTS 会小于目标
    private var seekTargetTime: TimeInterval? = nil

    /// 音频流的 time_base，用于将 packet PTS 精确转换为秒
    private var audioTimeBase: AVRational = AVRational(num: 0, den: 1)

    /// 首个 audio packet 的 PTS（秒），用于消除容器/编码器起始偏移
    /// 很多音频文件第一个 packet PTS 不是 0（编码器延迟、容器头部偏移等）
    private var audioPTSOffset: TimeInterval? = nil

    /// 网络断流连续重连次数（成功读包后重置为 0）
    private var networkReconnectAttempts: Int = 0
    private let maxNetworkReconnectAttempts: Int = 3

    // MARK: - A-B 循环

    /// A-B 循环的 A 点（秒），nil = 未设置
    private var loopPointA: TimeInterval? = nil
    /// A-B 循环的 B 点（秒），nil = 未设置
    private var loopPointB: TimeInterval? = nil
    /// A-B 循环是否启用
    private var abLoopEnabled: Bool = false

    /// 交叉淡入淡出时长（秒）
    private var crossfadeDuration: Float = 0.0
    private var crossfadeOutgoingGainDB: Float = 0
    private var crossfadeIncomingGainDB: Float = 0

    // MARK: - Gapless Playback (预加载下一首)

    /// 预加载的下一首 pipeline 组件
    private var nextConnectionManager: ConnectionManager?
    private var nextDemuxer: Demuxer?
    private var nextAudioDecoder: AudioDecoder?
    private var nextStreamInfo: StreamInfo?
    private var nextAudioTimeBase: AVRational = AVRational(num: 0, den: 1)
    private var nextPrerollBatches: [DecodedAudioBatch] = []
    private var nextURL: String?
    /// 预加载是否就绪
    private var isNextReady: Bool = false
    /// 当前这一代 prepareNext 已确定失败（区别于“仍在装配中”）。
    private var nextPreparationFailed: Bool = false
    private var forceTransition: Bool = false
    /// 是否允许在 EOF 时自动切到已预加载的下一首。
    /// 关闭后仍然允许 prepareNext / switchToNext 用于音质切换等显式流程，
    /// 只是不会在当前歌曲自然结束时自动切到 next pipeline。
    private var automaticPreparedTrackTransitionEnabled: Bool = true
    /// 当前歌曲已切换到下一条 pipeline，但旧音频尾巴仍在输出中的截止时刻。
    /// 在此之前 currentTime 应保持在上一首结束位置，UI 也不应立刻切到下一首。
    private var audibleTransitionDeadline: Date?
    /// 延迟切换 UI 期间，旧歌曲尾声开始“继续走表”的起始时刻。
    private var audibleTransitionStartedAt: Date?
    /// 延迟切换 UI 期间，旧歌曲在切换当下的实际可听播放位置。
    private var previousTrackDisplayStartTime: TimeInterval?
    /// 延迟通知 app 层“已切到下一首”的任务。
    private var pendingTransitionNotificationWorkItem: DispatchWorkItem?
    /// Invalidates delayed transition callbacks that belong to an older switch.
    private var transitionNotificationGeneration: UInt64 = 0
    /// Generation of the current next-track preparation request. Results from an
    /// older request are discarded even when its network connection finishes late.
    private var nextPreparationGeneration: UInt64 = 0
    /// 暂停信号量，暂停时阻塞解码线程，resume 时唤醒
    private let pauseSemaphore = DispatchSemaphore(value: 0)
    private let prepareQueue = DispatchQueue(label: "com.ffmpeg-sdk.prepare-next", qos: .utility)

    // MARK: - Initialization

    /// Creates a new `StreamPlayer` with default components.
    public init() {
        self.eqFilter = EQFilter()
        self.audioFilterGraph = AudioFilterGraph()
        self.repairEngine = AudioRepairEngine()
        self.equalizer = AudioEqualizer(filter: eqFilter)
        self.audioEffects = AudioEffects(filterGraph: audioFilterGraph)
        self.spectrumAnalyzer = SpectrumAnalyzer()
        // Mono Audio Agent uses a dedicated, pre-effect analyzer. A 4096-sample
        // window resolves low one-third-octave bands and pitch fundamentals much
        // more reliably than the visualizer's 2048-sample window, while running
        // only when an analysis consumer is attached.
        self.analysisSpectrumAnalyzer = SpectrumAnalyzer(fftSize: 4096)
        self.waveformGenerator = WaveformGenerator()
        self.metadataReader = MetadataReader()
        self.lyricSyncer = LyricSyncer()
        self.audioRenderer = AudioRenderer()
        self.videoRenderer = VideoRenderer()
        self.syncController = AVSyncController()
        self.audioRenderer.setEQFilter(eqFilter)
        self.audioRenderer.setAudioFilterGraph(audioFilterGraph)
        self.audioRenderer.setSpectrumAnalyzer(spectrumAnalyzer)
        self.audioRenderer.setAnalysisSpectrumAnalyzer(analysisSpectrumAnalyzer)
        self.audioRenderer.setRepairEngine(repairEngine)
        // 设置 equalizer 的 audioEffects 引用，用于应用预设的环绕效果
        self.equalizer.audioEffects = self.audioEffects
    }

    deinit {
        stopInternal()
    }

    // MARK: - Playback Control

    /// Starts playback from the given URL.
    ///
    /// This method is non-blocking. It kicks off the connection and playback
    /// pipeline on a background queue. State changes are reported via the delegate.
    ///
    /// If a session is already active, it is stopped first before starting the new one.
    ///
    /// - Parameter url: The URL of the media source (RTMP, HLS, RTSP, etc.).
    public func play(
        url: String,
        decryptionKey: String? = nil,
        startTime: TimeInterval = 0,
        autoPlay: Bool = true
    ) {
        // Stop any existing session first
        stopInternal()

        // Allow video renderer to accept frames for the new session.
        videoRenderer.resetForNewSession()

        let generation = stateQueue.sync { () -> UInt64 in
            self.playbackGeneration &+= 1
            self.isPlaybackActive = true
            self.currentURL = url
            self.decodedTime = 0
            self.storedLastTerminalPlaybackTime = 0
            self.storedLastStopReason = .explicit
            self.storedStreamInfo = nil
            self.endOfStreamDrainActive = false
            self.requiredInitialSeekPosition = startTime > 0 ? startTime : nil
            self.startsPausedGeneration = autoPlay ? nil : self.playbackGeneration
            return self.playbackGeneration
        }

        // Transition to connecting
        transitionState(to: .connecting)

        // Start the pipeline on the background queue
        playbackQueue.async { [weak self] in
            self?.startPipeline(url: url, decryptionKey: decryptionKey, generation: generation)
        }
    }

    /// Pauses the current playback.
    ///
    /// Audio and video rendering are paused but the session remains active.
    /// Call `resume()` to continue playback.
    public func pause() {
        guard state == .playing else { return }
        _ = pauseAudioOutputImmediately()
    }

    /// Immediately silences the hardware output and converges a stale public
    /// state to `.paused`. Used for route loss where a fade must not leak audio
    /// onto the built-in speaker.
    @discardableResult
    public func pauseAudioOutputImmediately() -> Bool {
        let rendererPaused = audioRenderer.pause()
        if state == .playing {
            transitionState(to: .paused)
        }
        return rendererPaused || !audioRenderer.isOutputRunning
    }

    /// Resumes playback after a pause.
    ///
    /// Has no effect if the player is not in the `.paused` state.
    @discardableResult
    public func resume() -> Bool {
        guard state == .paused else { return false }
        let hasAudio = streamInfo?.hasAudio ?? true
        guard !hasAudio || audioRenderer.resume() else { return false }
        transitionState(to: .playing)
        pauseSemaphore.signal()
        return true
    }

    /// Stops playback and releases all resources.
    ///
    /// After calling `stop()`, the player returns to a state where `play(url:)`
    /// can be called again to start a new session.
    public func stop() {
        stopInternal(stopReason: .explicit)
        transitionState(to: .stopped)
    }

    /// Seeks to the specified time position in seconds.
    ///
    /// 将 seek 请求投递给播放循环，由播放循环在安全时刻执行，
    /// 避免与 demuxer 的 readNextPacket 产生线程竞争。
    ///
    /// - Parameter time: The target position in seconds.
    public func seek(to time: TimeInterval) {
        seekLock.lock()
        pendingSeekGeneration &+= 1
        pendingSeekTime = time
        seekLock.unlock()
        // A seek should not wait for the current demux read to finish. Use a
        // transient FFmpeg interrupt that is cleared before `av_seek_frame`, so
        // backward scrubbing remains responsive without rebuilding the stream.
        let currentState = state
        if currentState == .playing || currentState == .paused {
            let activeConnection = stateQueue.sync { self.connectionManager }
            activeConnection?.requestActiveIOWake()
        }
        if currentState == .paused {
            pauseSemaphore.signal()
        }
    }

    // MARK: - A-B 循环

    /// 设置 A-B 循环区间。设置后自动启用循环。
    ///
    /// 播放到 B 点时自动 seek 回 A 点，实现精确区间循环。
    /// 适用于练歌、学习乐器等场景。
    ///
    /// - Parameters:
    ///   - pointA: A 点时间（秒）
    ///   - pointB: B 点时间（秒），必须大于 A 点
    public func setABLoop(pointA: TimeInterval, pointB: TimeInterval) {
        guard pointB > pointA else { return }
        stateQueue.sync {
            self.loopPointA = pointA
            self.loopPointB = pointB
            self.abLoopEnabled = true
        }
    }

    /// 清除 A-B 循环，恢复正常播放。
    public func clearABLoop() {
        stateQueue.sync {
            self.loopPointA = nil
            self.loopPointB = nil
            self.abLoopEnabled = false
        }
    }

    /// A-B 循环是否启用。
    public var isABLoopEnabled: Bool {
        stateQueue.sync { abLoopEnabled }
    }

    /// 当前 A-B 循环的 A 点（秒），nil = 未设置。
    public var abLoopPointA: TimeInterval? {
        stateQueue.sync { loopPointA }
    }

    /// 当前 A-B 循环的 B 点（秒），nil = 未设置。
    public var abLoopPointB: TimeInterval? {
        stateQueue.sync { loopPointB }
    }

    // MARK: - 交叉淡入淡出

    /// 设置交叉淡入淡出时长。
    ///
    /// 当使用 prepareNext + 无缝切歌时，当前歌曲结尾会淡出，
    /// 下一首歌曲开头会淡入，两者重叠产生 DJ 混音效果。
    ///
    /// - Parameter duration: 交叉淡入淡出时长（秒），0 = 关闭。
    ///   典型值：3~8 秒。
    public func setCrossfadeDuration(_ duration: Float) {
        stateQueue.sync {
            self.crossfadeDuration = max(0, min(duration, 12))
        }
    }

    /// Sets short-lived loudness trims used only inside the next prepared-track
    /// overlap. Both trims converge to unity at the new track boundary.
    public func setCrossfadeGainTrims(outgoingDB: Float, incomingDB: Float) {
        stateQueue.sync {
            crossfadeOutgoingGainDB = min(3, max(-6, outgoingDB))
            crossfadeIncomingGainDB = min(3, max(-6, incomingDB))
        }
    }

    /// 当前交叉淡入淡出时长（秒）。
    public var currentCrossfadeDuration: Float {
        stateQueue.sync { crossfadeDuration }
    }

    /// 预加载下一首歌曲，实现无缝切歌（gapless playback）。
    ///
    /// 在后台队列连接并初始化下一首的 demuxer + decoder，
    /// 当前歌曲 EOF 时直接切换 pipeline，AudioRenderer 不中断。
    ///
    /// - Parameters:
    ///   - url: 下一首歌曲的 URL
    ///   - decryptionKey: 加密音源（如汽水音乐）的解密密钥，明文源传 nil
    ///   - fastStart: 手动切歌场景传 true——用更小的预卷门槛换更快开声。
    ///     自然 EOF 无缝衔接请保持 false，维持最保守的连续播放余量。
    public func prepareNext(url: String, decryptionKey: String? = nil, fastStart: Bool = false) {
        // 取消之前的预加载
        cancelNextPreparation()

        let generation = stateQueue.sync { () -> UInt64 in
            self.nextPreparationGeneration &+= 1
            self.nextURL = url
            self.isNextReady = false
            self.nextPreparationFailed = false
            return self.nextPreparationGeneration
        }

        prepareQueue.async { [weak self] in
            self?.performNextPreparation(
                url: url,
                decryptionKey: decryptionKey,
                generation: generation,
                fastStart: fastStart
            )
        }
    }

    /// 下一首管线是否已装配完成（demuxer + decoder 就绪，EOF 可直接切换）。
    /// 上层可据此在临近结尾时判断预加载是否失败并重试。
    public var isNextTrackReady: Bool {
        stateQueue.sync { isNextReady }
    }

    /// 最近一次 prepareNext 是否已确定失败（连接被拒、流信息解析失败、
    /// 预卷不足等）。上层轮询等待时据此立即回退普通装载，而不是傻等超时。
    /// 新一轮 prepareNext / cancelNextPreparation 会重置该标记。
    public var hasNextPreparationFailed: Bool {
        stateQueue.sync { nextPreparationFailed }
    }

    /// `true` while the engine has already installed the prepared pipeline but
    /// the previous track's audible tail is still playing. App-layer recovery
    /// may use this to avoid advancing metadata before the sound actually turns.
    public var isTrackTransitionNotificationDeferred: Bool {
        stateQueue.sync {
            guard let deadline = audibleTransitionDeadline else { return false }
            return Date() < deadline
        }
    }

    /// 立即切换到预加载的下一首（用于音质切换等场景）。
    /// 不等 EOF，主动触发切换，可指定 seek 位置。
    /// - Parameter seekTo: 切换后 seek 到的位置（秒），nil 表示从头播放
    public func switchToNext(seekTo: TimeInterval? = nil) {
        guard stateQueue.sync(execute: { self.isNextReady }) else { return }
        // 投递 seek 请求，transitionToNextTrack 后播放循环会处理
        if let time = seekTo {
            seekLock.lock()
            pendingSeekGeneration &+= 1
            pendingSeekTime = time
            seekLock.unlock()
        }
        // 设置标志让播放循环在下次迭代时触发切换
        let activeConnection = stateQueue.sync { () -> ConnectionManager? in
            self.forceTransition = true
            return self.connectionManager
        }
        // `av_read_frame` may be waiting inside the old input. Merely setting
        // `forceTransition` leaves the request stranded until that read returns,
        // which can make a manual track switch remain in loading indefinitely.
        // Wake the old input now; the playback loop consumes `forceTransition`
        // before treating the interruption as a playback failure.
        activeConnection?.interruptActiveIO()
        pauseSemaphore.signal()
    }

    /// 取消预加载
    public func cancelNextPreparation() {
        let cancelled = stateQueue.sync { () -> RetiredResources in
            let resources = RetiredResources(
                connection: nextConnectionManager,
                demuxer: nextDemuxer,
                audioDecoder: nextAudioDecoder,
                preroll: nextPrerollBatches
            )
            nextPreparationGeneration &+= 1
            nextConnectionManager = nil
            nextDemuxer = nil
            nextAudioDecoder = nil
            nextStreamInfo = nil
            nextAudioTimeBase = AVRational(num: 0, den: 1)
            nextPrerollBatches = []
            nextURL = nil
            isNextReady = false
            nextPreparationFailed = false
            forceTransition = false
            return resources
        }
        retireResources(cancelled)
    }

    /// 处理音频路由变化（蓝牙连接/断开）。
    ///
    /// 当蓝牙设备连接或断开导致硬件采样率变化时，安全重建音频引擎，
    /// 避免 `AVAudioSourceNode` 格式不匹配导致的闪退。
    @discardableResult
    public func handleAudioRouteChange() -> Bool {
        let stateBeforeRebuild = state
        let hasAudio = streamInfo?.hasAudio ?? true
        guard hasAudio else { return true }

        let ready = audioRenderer.handleRouteChange()
        // Route changes can require a running engine to negotiate the new output
        // format. Preserve the public paused contract after that negotiation.
        if ready, stateBeforeRebuild == .paused {
            audioRenderer.pause()
        }
        return ready
    }

    /// PlaybackState may remain `.playing` after iOS invalidates AVAudioEngine.
    /// Expose the renderer truth so app/UI recovery does not trust a stale enum.
    public var isAudioOutputRunning: Bool {
        let hasAudio = streamInfo?.hasAudio ?? true
        return !hasAudio || audioRenderer.isOutputRunning
    }

    /// Renderer evidence captured without touching the decode or realtime callback paths.
    public var audioOutputDiagnostics: AudioOutputDiagnostics {
        audioRenderer.outputDiagnostics()
    }

    /// `true` after the input reached its natural end and while the renderer is
    /// finishing the queued tail or waiting for the final underrun callback.
    public var isDrainingEndOfStream: Bool {
        stateQueue.sync { endOfStreamDrainActive }
    }

    /// Mono 引擎实际交给音频设备的累计声音时长。
    ///
    /// 该计数只随真实 PCM 输出增长，连接、加载、暂停、缓冲、断流和
    /// 补零阶段均不会增长，供上层统计真实收听时长。
    public var totalAudiblePlaybackDuration: TimeInterval {
        audioRenderer.totalAudibleOutputDuration
    }

    /// 渲染混音台输出音量（0.0~1.0），与 `audioEffects.setVolume`（滤镜图增益）互相独立。
    ///
    /// 修改立即生效且不重建滤镜图，适合上层做暂停/恢复淡入淡出、
    /// 睡眠定时器长淡出等瞬态音量包络。目标值会跨播放引擎重建保留，
    /// 由上层在停止、失败或包络完成时显式恢复。
    public var outputVolume: Float {
        get { audioRenderer.outputVolume }
        set { audioRenderer.outputVolume = newValue }
    }

    /// Temporary volume multiplier used for system/game voice ducking.
    /// This is composed with `outputVolume`, so other fades remain intact.
    public var duckingVolume: Float {
        get { audioRenderer.duckingVolume }
        set { audioRenderer.duckingVolume = newValue }
    }

    /// Real-time output pan used by head-tracked spatial playback. This is
    /// handled by AVAudioEngine and never rebuilds the FFmpeg processing graph.
    public var outputPan: Float {
        get { audioRenderer.outputPan }
        set { audioRenderer.outputPan = newValue }
    }

    /// 控制 EOF 时是否允许自动切到已预加载的下一首。
    /// 该开关不会影响显式的 `switchToNext()`，因此不会破坏音质切换流程。
    public func setAutomaticPreparedTrackTransitionEnabled(_ enabled: Bool) {
        stateQueue.sync {
            self.automaticPreparedTrackTransitionEnabled = enabled
        }
    }

    /// 在播放循环中安全执行 seek（仅在 playbackQueue 上调用）
    /// 尝试先预解目标位置的一小段音频，再切换到新位置，尽量缩短 seek 后的静音。
    @discardableResult
    private func processPendingSeek(demuxer: Demuxer) -> Bool {
        seekLock.lock()
        guard let seekTime = pendingSeekTime else {
            seekLock.unlock()
            return true
        }
        let seekGeneration = pendingSeekGeneration
        pendingSeekTime = nil
        seekLock.unlock()

        // The one-shot interrupt may still be armed when the read completed
        // naturally. Clear it before seeking on the same format context.
        let activeConnection = stateQueue.sync { self.connectionManager }
        activeConnection?.clearActiveIOWake()

        do {
            try demuxer.seek(to: seekTime)

            // seek 后清空解码器内部状态，避免旧位置残帧混入新位置
            let videoDecoderToFlush = stateQueue.sync { () -> VideoDecoder? in
                self.audioDecoder?.flush()
                self.videoPipelineEpoch &+= 1
                self.decodedTime = seekTime
                self.seekTargetTime = seekTime
                self.endOfStreamDrainActive = false
                // seek 后让音频 PTS 偏移重新按目标位置计算。
                // 对冷启动恢复播放，新的解码流第一帧 PTS 往往就是 seek 目标附近；
                // 如果沿用“首帧归零”的逻辑，会让外部 currentTime 从 0 重新开始，
                // 导致 app 层永远认为还没 seek 到目标位置。
                self.audioPTSOffset = nil
                return self.videoDecoder
            }
            // Video decoding now owns a separate serial queue; flush its codec
            // on that same queue so seek cannot race avcodec_receive_frame.
            videoDecodeQueue.sync {
                videoDecoderToFlush?.flush()
            }

            syncController.reset()
            repairEngine.reset()
            lyricSyncer.reset()

            let prerollBatches = prepareSeekAudioPreroll(demuxer: demuxer)

            // 预卷可能耗时数百毫秒；期间用户再次拖动时，旧目标只能丢弃，
            // 不能清空当前队列并短暂提交到过期位置。
            seekLock.lock()
            let wasSuperseded = pendingSeekGeneration != seekGeneration
            seekLock.unlock()
            if wasSuperseded {
                for batch in prerollBatches {
                    for buffer in batch.buffers {
                        buffer.data.deallocate()
                    }
                }
                return false
            }

            // 真正切到新位置前再清空旧队列，尽量让旧位置尾音覆盖 seek 准备期。
            audioRenderer.flushQueue()

            if !prerollBatches.isEmpty {
                for batch in prerollBatches {
                    handleDecodedAudioBuffers(
                        batch.buffers,
                        packetPTS: batch.packetPTS,
                        timeBase: batch.timeBase,
                        enqueueToRenderer: true
                    )
                }
                let prerollDuration = prerollBatches.reduce(0) { partial, batch in
                    partial + batch.buffers.reduce(0) { $0 + $1.duration }
                }
                print(
                    "[StreamPlayer] 🎯 seek preroll ready: target=\(String(format: "%.3f", seekTime))s, " +
                    "batches=\(prerollBatches.count), buffered=\(String(format: "%.3f", prerollDuration))s"
                )
            } else {
                print(
                    "[StreamPlayer] 🎯 seek preroll unavailable, fall back to direct refill: " +
                    "target=\(String(format: "%.3f", seekTime))s"
                )
            }
            return true
        } catch {
            print("[StreamPlayer] ⚠️ seek failed: target=\(String(format: "%.3f", seekTime))s, error=\(error)")
            return false
        }
    }

    private struct DecodedAudioBatch {
        let packetPTS: Int64
        let timeBase: AVRational
        let buffers: [AudioBuffer]
    }

    /// Removed from stateQueue before transfer to resourceCleanupQueue. Decoder
    /// references are retained only for lifetime management, never decoding here.
    private final class RetiredResources: @unchecked Sendable {
        private var connection: ConnectionManager?
        private var demuxer: Demuxer?
        private var audioDecoder: AudioDecoder?
        private var videoDecoder: VideoDecoder?
        private var preroll: [DecodedAudioBatch]

        init(
            connection: ConnectionManager?,
            demuxer: Demuxer?,
            audioDecoder: AudioDecoder?,
            videoDecoder: VideoDecoder? = nil,
            preroll: [DecodedAudioBatch] = []
        ) {
            self.connection = connection
            self.demuxer = demuxer
            self.audioDecoder = audioDecoder
            self.videoDecoder = videoDecoder
            self.preroll = preroll
        }

        func interruptIO() {
            connection?.interruptActiveIO()
        }

        /// Only the cleanup queue may access this bundle after submission.
        func release() {
            connection?.disconnect()
            connection = nil
            demuxer = nil
            audioDecoder = nil
            videoDecoder = nil
            for batch in preroll {
                for buffer in batch.buffers {
                    buffer.data.deallocate()
                }
            }
            preroll = []
        }
    }

    private func retireResources(_ resources: RetiredResources) {
        // Wake blocked reads immediately; closing inputs and freeing preroll
        // buffers must not hold the player state lock or the caller's UI thread.
        resources.interruptIO()
        resourceCleanupQueue.async {
            resources.release()
        }
    }

    private func prepareSeekAudioPreroll(demuxer: Demuxer) -> [DecodedAudioBatch] {
        guard stateQueue.sync(execute: { self.audioDecoder != nil }) else { return [] }

        let maxPrerollDuration: TimeInterval = 0.22
        let maxPreparationTime: TimeInterval = 0.45
        let maxPackets = 48
        let timeBase = stateQueue.sync { self.audioTimeBase }

        var prerollBatches: [DecodedAudioBatch] = []
        var prerollDuration: TimeInterval = 0
        let start = Date()

        for _ in 0..<maxPackets {
            if prerollDuration >= maxPrerollDuration {
                break
            }
            if Date().timeIntervalSince(start) > maxPreparationTime {
                break
            }

            let packet: Demuxer.PacketType?
            do {
                packet = try demuxer.readNextPacket()
            } catch {
                break
            }

            guard let packet else { break }

            switch packet {
            case .audio(let pkt):
                let packetPTS = pkt.pointee.pts
                defer {
                    releasePacket(pkt)
                }

                guard let decoder = stateQueue.sync(execute: { self.audioDecoder }) else {
                    continue
                }

                do {
                    let audioBuffers = try decoder.decodeAll(packet: pkt)
                    var validBuffers: [AudioBuffer] = []
                    validBuffers.reserveCapacity(audioBuffers.count)
                    for buffer in audioBuffers {
                        if buffer.frameCount > 0 && buffer.duration > 0 {
                            validBuffers.append(buffer)
                        } else {
                            buffer.data.deallocate()
                        }
                    }
                    guard !validBuffers.isEmpty else { continue }

                    prerollDuration += validBuffers.reduce(0) { $0 + $1.duration }
                    prerollBatches.append(
                        DecodedAudioBatch(
                            packetPTS: packetPTS,
                            timeBase: timeBase,
                            buffers: validBuffers
                        )
                    )
                } catch {
                    continue
                }

            case .video(let pkt):
                releasePacket(pkt)
            }
        }

        return prerollBatches
    }

    private func decodeNextTrackPreroll(
        demuxer: Demuxer,
        decoder: AudioDecoder,
        timeBase: AVRational,
        generation: UInt64,
        targetDuration: TimeInterval,
        maxPackets: Int
    ) -> [DecodedAudioBatch] {
        var duration: TimeInterval = 0
        var batches: [DecodedAudioBatch] = []

        for _ in 0..<maxPackets {
            let valid = stateQueue.sync {
                nextPreparationGeneration == generation
            }
            guard valid, duration < targetDuration else { break }

            let packet: Demuxer.PacketType?
            do {
                packet = try demuxer.readNextPacket()
            } catch {
                break
            }
            guard let packet else { break }

            switch packet {
            case .audio(let pkt):
                let packetPTS = pkt.pointee.pts
                defer { releasePacket(pkt) }
                guard let decodedBuffers = try? decoder.decodeAll(packet: pkt),
                      !decodedBuffers.isEmpty else { continue }
                var buffers: [AudioBuffer] = []
                buffers.reserveCapacity(decodedBuffers.count)
                for buffer in decodedBuffers {
                    if buffer.frameCount > 0 && buffer.duration > 0 {
                        buffers.append(buffer)
                    } else {
                        buffer.data.deallocate()
                    }
                }
                guard !buffers.isEmpty else { continue }
                duration += buffers.reduce(0) { $0 + $1.duration }
                batches.append(
                    DecodedAudioBatch(
                        packetPTS: packetPTS,
                        timeBase: timeBase,
                        buffers: buffers
                    )
                )
            case .video(let pkt):
                releasePacket(pkt)
            }
        }

        return batches
    }

    private func releaseDecodedAudioBatches(_ batches: [DecodedAudioBatch]) {
        for batch in batches {
            for buffer in batch.buffers {
                buffer.data.deallocate()
            }
        }
    }

    // MARK: - Pipeline

    /// Starts the full playback pipeline: connect → demux → decode → render.
    ///
    /// This method runs on the playback queue and blocks until playback ends
    /// (either by reaching EOF, encountering an unrecoverable error, or being stopped).
    private func startPipeline(
        url: String,
        decryptionKey: String? = nil,
        generation: UInt64
    ) {
        guard isActive(generation: generation) else { return }

        let manager = ConnectionManager()
        manager.decryptionKey = decryptionKey
        stateQueue.sync { self.connectionManager = manager }

        // Step 1: Connect
        let formatContext: FFmpegFormatContext
        do {
            // Use a semaphore to bridge async connect to the sync playback queue
            var connectResult: Result<FFmpegFormatContext, Error>?
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                do {
                    let ctx = try await manager.connect(url: url)
                    connectResult = .success(ctx)
                } catch {
                    connectResult = .failure(error)
                }
                semaphore.signal()
            }

            semaphore.wait()

            switch connectResult! {
            case .success(let ctx):
                formatContext = ctx
            case .failure(let error):
                throw error
            }
        } catch {
            guard isActive(generation: generation) else {
                manager.disconnect()
                return
            }
            handleUnrecoverableError(error, generation: generation)
            return
        }

        // Check if we were stopped during connection
        guard isActive(generation: generation) else {
            manager.disconnect()
            return
        }

        // Step 2: Demux - find streams
        let demuxer = Demuxer(formatContext: formatContext, url: url)
        stateQueue.sync { self.demuxer = demuxer }

        let info: StreamInfo
        do {
            info = try demuxer.findStreams()
            stateQueue.sync { self.storedStreamInfo = info }
        } catch {
            guard isActive(generation: generation) else {
                manager.disconnect()
                return
            }
            handleUnrecoverableError(error, generation: generation)
            return
        }

        guard isActive(generation: generation) else { return }

        // Step 3: 先启动 AudioRenderer，获取硬件实际采样率
        // iOS 设备请求高采样率（如 192kHz）后，硬件可能给出不同的实际值
        var hwSampleRate: Int? = nil
        if info.hasAudio, let sampleRate = info.sampleRate {
            do {
                // Mono's internal music bus is always stereo. SwrContext handles
                // mono/stereo/surround conversion before PCM reaches the renderer.
                let format = makeAudioFormat(sampleRate: sampleRate, channelCount: 2)
                try audioRenderer.start(format: format)
                // Hold hardware output until a small PCM runway is ready.
                audioRenderer.pause()
                hwSampleRate = audioRenderer.actualSampleRate
            } catch {
                guard isActive(generation: generation) else { return }
                handleUnrecoverableError(error, generation: generation)
                return
            }
        }

        guard isActive(generation: generation) else { return }

        // Step 4: 初始化解码器，用硬件实际采样率作为 SwrContext 输出目标
        // 如果硬件采样率与源不同，SwrContext 会自动重采样
        do {
            try initializeDecoders(
                formatContext: formatContext,
                demuxer: demuxer,
                streamInfo: info,
                targetSampleRate: hwSampleRate,
                targetChannelCount: 2
            )
        } catch {
            guard isActive(generation: generation) else { return }
            handleUnrecoverableError(error, generation: generation)
            return
        }

        guard isActive(generation: generation) else { return }

        // Resume positions are applied while the renderer is still paused. This
        // prevents cold/warm restoration from briefly outputting the beginning
        // of the file and makes a failed initial seek a real load failure rather
        // than a false clock/audio split.
        let initialSeek = stateQueue.sync { () -> TimeInterval? in
            guard playbackGeneration == generation else { return nil }
            let position = requiredInitialSeekPosition
            requiredInitialSeekPosition = nil
            return position
        }
        if let initialSeek, initialSeek > 0 {
            seekLock.lock()
            pendingSeekGeneration &+= 1
            pendingSeekTime = initialSeek
            seekLock.unlock()
            guard processPendingSeek(demuxer: demuxer) else {
                handleUnrecoverableError(
                    FFmpegError.connectionFailed(
                        code: -1,
                        message: "Unable to seek to initial playback position"
                    ),
                    generation: generation
                )
                return
            }
        }

        if info.hasAudio,
           !info.hasVideo,
           let decoder = stateQueue.sync(execute: { self.audioDecoder }) {
            let timeBase = stateQueue.sync { self.audioTimeBase }
            let isNetworkStream = url.hasPrefix("http://") || url.hasPrefix("https://")
            let prefilledDuration = prefillAudioBuffer(
                demuxer: demuxer,
                decoder: decoder,
                timeBase: timeBase,
                generation: generation,
                // 首播必须先攒够连续 PCM 再放行硬件输出，避免刚唱一小段
                // 就因首轮网络抖动进入 underrun。
                targetDuration: isNetworkStream ? 0.85 : 0.20,
                maxPackets: isNetworkStream ? 96 : 24
            )
            // 网络首播若只取得极短 PCM 就放行硬件，最容易出现“唱一下—停住—
            // 再继续”。本地短音频不受此门槛限制。
            if isNetworkStream, prefilledDuration < 0.32 {
                print(
                    "[StreamPlayer] ⚠️ initial buffer below minimum: " +
                    "\(String(format: "%.3f", prefilledDuration))s"
                )
                handleUnrecoverableError(
                    FFmpegError.networkDisconnected,
                    generation: generation
                )
                return
            }
        }

        guard isActive(generation: generation) else { return }
        let startsPaused = stateQueue.sync {
            startsPausedGeneration == generation
        }
        if startsPaused {
            transitionState(to: .paused)
        } else {
            guard audioRenderer.resume() else {
                handleUnrecoverableError(
                    FFmpegError.resourceAllocationFailed(resource: "AVAudioEngine.resume"),
                    generation: generation
                )
                return
            }

            // Transition to playing
            transitionState(to: .playing)
        }

        // Notify duration if available
        if let duration = info.duration {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      self.isActive(generation: generation) else { return }
                self.delegate?.player(
                    self,
                    didUpdateDuration: duration,
                    forPlaybackInput: url
                )
            }
        }

        // Step 5: Run the demux/decode loop
        syncController.reset()
        runPlaybackLoop(demuxer: demuxer, generation: generation)
    }

    /// Initializes audio and video decoders based on the discovered streams.
    private func initializeDecoders(
        formatContext: FFmpegFormatContext,
        demuxer: Demuxer,
        streamInfo: StreamInfo,
        targetSampleRate: Int? = nil,
        targetChannelCount: Int? = nil
    ) throws {
        // Initialize audio decoder
        if streamInfo.hasAudio, demuxer.currentAudioStreamIndex >= 0 {
            let streamIndex = Int(demuxer.currentAudioStreamIndex)
            if let stream = formatContext.stream(at: streamIndex),
               let codecpar = stream.pointee.codecpar {
                let codecID = codecpar.pointee.codec_id
                // 保存音频流的 time_base，用于 PTS → 秒 的精确转换
                stateQueue.sync { self.audioTimeBase = stream.pointee.time_base }
                do {
                    let decoder = try AudioDecoder(
                        codecParameters: codecpar,
                        codecID: codecID,
                        targetSampleRate: targetSampleRate,
                        targetChannelCount: targetChannelCount
                    )
                    stateQueue.sync { self.audioDecoder = decoder }
                } catch {
                    // Audio decoder init failure is unrecoverable if we only have audio
                    if !streamInfo.hasVideo { throw error }
                    // If we have video too, we can continue without audio
                }
            }
        }

        // Initialize video decoder
        if streamInfo.hasVideo, demuxer.currentVideoStreamIndex >= 0 {
            let streamIndex = Int(demuxer.currentVideoStreamIndex)
            if let stream = formatContext.stream(at: streamIndex),
               let codecpar = stream.pointee.codecpar {
                let codecID = codecpar.pointee.codec_id
                let timeBase = stream.pointee.time_base
                do {
                    let decoder = try VideoDecoder(
                        codecParameters: codecpar,
                        codecID: codecID,
                        timeBase: timeBase
                    )
                    stateQueue.sync { self.videoDecoder = decoder }
                } catch {
                    // Video decoder init failure is unrecoverable if we only have video
                    if !streamInfo.hasAudio { throw error }
                }
            }
        }
    }

    /// The main demux/decode loop. Reads packets, decodes them, and sends
    /// the output to the appropriate renderer.
    ///
    /// Individual frame decoding errors are caught and skipped (recoverable).
    /// Unrecoverable errors (resource allocation failures, connection loss,
    /// unsupported formats) stop the loop and trigger auto-stop via delegate.
    /// Network disconnection errors are detected and propagated through the
    /// ConnectionManager delegate before notifying the app layer.
    ///
    /// Backpressure: When the audio renderer's buffer queue exceeds the max
    /// threshold, the loop sleeps briefly to let the renderer catch up. This
    /// prevents unbounded memory growth and ensures we don't race past EOF
    /// before audio finishes playing.
    private func runPlaybackLoop(demuxer initialDemuxer: Demuxer, generation: UInt64) {
        while isActive(generation: generation) {
            // 优先处理强制切换（音质切换），确保 pendingSeekTime 作用在新 demuxer 上
            // 强制切换会紧接着 flushQueue 丢弃旧曲缓冲尾巴，音频立即切到新曲，
            // 因此 UI 通知也必须立即发出（不能按尾巴时长延迟，否则界面滞后于听感）
            if consumeForcedPreparedTrackTransition() {
                continue
            }

            // 获取当前 demuxer（可能刚被 transition 替换）
            guard let currentDemuxer = stateQueue.sync(execute: { self.demuxer }) else { return }

            // 检查并处理 pending seek（线程安全，在 playbackQueue 上执行）
            processPendingSeek(demuxer: currentDemuxer)

            if state == .paused {
                pauseSemaphore.wait()
                continue
            }

            // 缓存满后不要让高优先级解码线程整首歌每 10ms 空转一次。
            // 等队列回落到低水位再批量补齐，保留原有抗断流余量，同时
            // 给热降频后的系统与音频回调留下连续的空闲时间。
            if audioRenderer.queuedBufferCount > AudioRenderer.maxQueuedBuffers {
                while isActive(generation: generation)
                    && audioRenderer.queuedBufferCount
                        > AudioRenderer.backpressureResumeQueuedBuffers {
                    Thread.sleep(forTimeInterval: 0.04)
                }
            }
            guard isActive(generation: generation) else { return }

            let packet: Demuxer.PacketType?
            do {
                packet = try currentDemuxer.readNextPacket()
            } catch Demuxer.ReadInterruption.transientWake {
                // A seek wakes av_read_frame through AVIOInterruptCB. The wake
                // can arrive just after the playback loop consumed that seek,
                // so always clear the one-shot flag and retry instead of
                // publishing AVERROR_EXIT as a fatal playback error.
                let activeConnection = stateQueue.sync { self.connectionManager }
                activeConnection?.clearActiveIOWake()
                guard isActive(generation: generation) else { return }
                _ = consumeForcedPreparedTrackTransition()
                continue
            } catch Demuxer.ReadInterruption.cancelled {
                guard isActive(generation: generation) else { return }
                if consumeForcedPreparedTrackTransition() {
                    continue
                }
                handleUnrecoverableError(
                    FFmpegError.operationInterrupted,
                    generation: generation
                )
                return
            } catch let error as FFmpegError where error == .networkDisconnected {
                if consumeForcedPreparedTrackTransition() {
                    continue
                }
                if hasPendingSeekRequest {
                    continue
                }
                if attemptReconnect(generation: generation) {
                    continue
                }
                handleNetworkDisconnection(generation: generation)
                return
            } catch let error as FFmpegError where error.isUnrecoverable {
                if consumeForcedPreparedTrackTransition() {
                    continue
                }
                if hasPendingSeekRequest {
                    continue
                }
                handleUnrecoverableError(error, generation: generation)
                return
            } catch {
                if consumeForcedPreparedTrackTransition() {
                    continue
                }
                if hasPendingSeekRequest {
                    continue
                }
                handleUnrecoverableError(error, generation: generation)
                return
            }

            guard let packet = packet else {
                guard isActive(generation: generation) else { return }
                // A forced handoff may interrupt the old demuxer as EOF instead
                // of throwing. Consume it before the natural-EOF drain path so
                // the prepared track cannot be mistaken for an ended session.
                if consumeForcedPreparedTrackTransition() {
                    continue
                }
                if hasPendingSeekRequest {
                    continue
                }
                stateQueue.sync {
                    guard self.isPlaybackActive,
                          self.playbackGeneration == generation else { return }
                    self.endOfStreamDrainActive = true
                }
                // EOF reached — drain decoder to get remaining buffered frames
                drainDecoderAtEOF(generation: generation)
                audioRenderer.markInputEnded()
                let underrunSerialAtEOF = audioRenderer.currentUnderrunSerial()
                let queuedTailAtEOF = audioRenderer.queuedDuration

                // 尝试无缝切换到预加载的下一首
                let shouldAutoTransitionToPreparedTrack = stateQueue.sync {
                    self.automaticPreparedTrackTransitionEnabled
                }
                if shouldAutoTransitionToPreparedTrack && transitionToNextTrack() {
                    continue
                }
                // 没有预加载的下一首，正常结束
                waitForRendererDrain(generation: generation)
                waitForRendererUnderrun(
                    after: underrunSerialAtEOF,
                    maxWait: max(3.0, min(queuedTailAtEOF + 3.0, 15.0)),
                    generation: generation
                )
                if stopInternal(
                    expectedGeneration: generation,
                    stopReason: .endOfStream
                ) {
                    transitionState(to: .stopped)
                }
                return
            }

            guard isActive(generation: generation) else {
                switch packet {
                case .audio(let pkt), .video(let pkt):
                    releasePacket(pkt)
                }
                return
            }

            switch packet {
            case .audio(let pkt):
                if let unrecoverableError = processAudioPacket(pkt) {
                    handleUnrecoverableError(unrecoverableError, generation: generation)
                    return
                }
            case .video(let pkt):
                enqueueVideoPacket(pkt, generation: generation)
            }
        }
    }

    /// Atomically consumes a manual/quality prepared-track switch request.
    /// Returns true only after the prepared pipeline has taken ownership.
    private func consumeForcedPreparedTrackTransition() -> Bool {
        let shouldTransition = stateQueue.sync { () -> Bool in
            guard forceTransition else { return false }
            forceTransition = false
            return true
        }
        guard shouldTransition else { return false }
        return transitionToNextTrack(discardsAudibleTail: true)
    }

    private var hasPendingSeekRequest: Bool {
        seekLock.lock()
        let pending = pendingSeekTime != nil
        seekLock.unlock()
        return pending
    }

    /// Waits for the audio renderer to finish playing all queued buffers.
    ///
    /// EOF 时使用长超时，确保尾音完整播放；网络断流平滑收尾时可传入更短的超时窗口。
    private func waitForRendererDrain(
        maxWait: TimeInterval? = nil,
        requireActive: Bool = true,
        generation: UInt64? = nil
    ) {
        let bufferedSeconds = audioRenderer.queuedDuration
        let resolvedMaxWait = maxWait ?? max(15.0, min(bufferedSeconds + 5.0, 20.0))
        let start = Date()
        while audioRenderer.queuedBufferCount > 0 {
            if requireActive,
               let generation,
               !isActive(generation: generation) {
                break
            }
            if Date().timeIntervalSince(start) > resolvedMaxWait {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Waits until the renderer has actually requested silence after EOF.
    /// This is more conservative than checking the queue alone, because
    /// AVAudioEngine may have already pulled some PCM ahead of audible output.
    private func waitForRendererUnderrun(
        after serial: UInt64,
        maxWait: TimeInterval,
        requireActive: Bool = true,
        generation: UInt64? = nil
    ) {
        let start = Date()
        while !audioRenderer.hasObservedUnderrun(since: serial) {
            if requireActive,
               let generation,
               !isActive(generation: generation) {
                break
            }
            if Date().timeIntervalSince(start) > maxWait {
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    // MARK: - Decoder Drain at EOF

    /// Drains the audio decoder at EOF to flush any remaining buffered frames into the renderer.
    private func drainDecoderAtEOF(generation: UInt64) {
        guard let decoder = stateQueue.sync(execute: { self.audioDecoder }) else { return }

        let remaining = decoder.drain()
        for buffer in remaining {
            guard isActive(generation: generation) else {
                buffer.data.deallocate()
                continue
            }
            guard buffer.frameCount > 0, buffer.duration > 0 else {
                buffer.data.deallocate()
                continue
            }
            let pts = stateQueue.sync { self.decodedTime }
            audioRenderer.enqueue(buffer, presentationTime: pts)
            let endPts = pts + buffer.duration
            stateQueue.sync { self.decodedTime = endPts }
            syncController.updateAudioClock(endPts)
        }
    }

    // MARK: - Gapless: 预加载与切换

    /// 标记当前这一代预加载确定失败。旧一代的迟到失败不覆盖新请求。
    private func markNextPreparationFailed(generation: UInt64) {
        stateQueue.sync {
            guard self.nextPreparationGeneration == generation else { return }
            self.nextPreparationFailed = true
        }
    }

    /// 在后台执行下一首的预加载：连接 → demux → 初始化 decoder
    private func performNextPreparation(
        url: String,
        decryptionKey: String? = nil,
        generation: UInt64,
        fastStart: Bool = false
    ) {
        let manager = ConnectionManager()
        manager.decryptionKey = decryptionKey

        let registered = stateQueue.sync { () -> Bool in
            guard self.nextPreparationGeneration == generation,
                  self.nextURL == url else {
                return false
            }
            self.nextConnectionManager = manager
            return true
        }
        guard registered else { return }

        // Step 1: 连接
        let formatContext: FFmpegFormatContext
        do {
            var connectResult: Result<FFmpegFormatContext, Error>?
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let ctx = try await manager.connect(url: url)
                    connectResult = .success(ctx)
                } catch {
                    connectResult = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()

            switch connectResult! {
            case .success(let ctx): formatContext = ctx
            case .failure:
                manager.disconnect()
                markNextPreparationFailed(generation: generation)
                return // 预加载失败，上层可立即回退
            }
        }

        // 检查是否已被取消
        let stillValid = stateQueue.sync {
            self.nextPreparationGeneration == generation && self.nextURL == url
        }
        guard stillValid else {
            manager.disconnect()
            return
        }

        // Step 2: Demux - 查找流
        let demuxer = Demuxer(formatContext: formatContext, url: url)
        let info: StreamInfo
        do {
            info = try demuxer.findStreams()
        } catch {
            manager.disconnect()
            markNextPreparationFailed(generation: generation)
            return
        }

        guard stateQueue.sync(execute: {
            self.nextPreparationGeneration == generation && self.nextURL == url
        }) else {
            manager.disconnect()
            return
        }

        // Step 3: 初始化 audio decoder
        // 使用当前 AudioRenderer 的采样率作为目标，避免需要重启 AudioUnit
        var decoder: AudioDecoder?
        var nextTimeBase = AVRational(num: 0, den: 1)
        if info.hasAudio, demuxer.currentAudioStreamIndex >= 0 {
            let streamIndex = Int(demuxer.currentAudioStreamIndex)
            if let stream = formatContext.stream(at: streamIndex),
               let codecpar = stream.pointee.codecpar {
                let codecID = codecpar.pointee.codec_id
                nextTimeBase = stream.pointee.time_base
                // 用当前 renderer 的实际采样率，这样不需要重启 AudioUnit
                let targetRate = audioRenderer.actualSampleRate > 0 ? audioRenderer.actualSampleRate : nil
                decoder = try? AudioDecoder(
                    codecParameters: codecpar,
                    codecID: codecID,
                    targetSampleRate: targetRate,
                    targetChannelCount: audioRenderer.actualChannelCount
                )
            }
        }

        guard let decoder else {
            manager.disconnect()
            markNextPreparationFailed(generation: generation)
            return
        }

        let isNetworkStream = url.hasPrefix("http://") || url.hasPrefix("https://")
        // fastStart（手动点歌）用更小的预卷目标提前开声：连接已建立后管线
        // 会持续读包补水，0.5 秒起播余量在正常网络下不会造成二次停顿。
        // 自然 EOF 无缝衔接维持保守档，优先保证不断流。
        let targetPrerollDuration: TimeInterval
        let normalMinimumReadyDuration: TimeInterval
        if isNetworkStream {
            targetPrerollDuration = fastStart ? 0.60 : 1.25
            normalMinimumReadyDuration = fastStart ? 0.50 : 0.85
        } else {
            targetPrerollDuration = 0.45
            normalMinimumReadyDuration = 0.18
        }
        let prerollBatches = decodeNextTrackPreroll(
            demuxer: demuxer,
            decoder: decoder,
            timeBase: nextTimeBase,
            generation: generation,
            targetDuration: targetPrerollDuration,
            maxPackets: isNetworkStream ? 160 : 64
        )

        let preparedDuration = prerollBatches.reduce(0) { total, batch in
            total + batch.buffers.reduce(0) { $0 + $1.duration }
        }
        let minimumReadyDuration: TimeInterval
        if let duration = info.duration, duration > 0 {
            minimumReadyDuration = min(
                normalMinimumReadyDuration,
                max(0.05, duration * 0.8)
            )
        } else {
            minimumReadyDuration = normalMinimumReadyDuration
        }

        guard stateQueue.sync(execute: {
            self.nextPreparationGeneration == generation && self.nextURL == url
        }) else {
            releaseDecodedAudioBatches(prerollBatches)
            manager.disconnect()
            return
        }

        // “已就绪”必须代表可以连续播放一段，而不只是连接和解码器创建成功。
        // 否则切换后会先播掉极短的预卷 PCM，再等待网络继续读包，听起来就是
        // “播一下、停一下、再继续”。
        guard !info.hasAudio || preparedDuration >= minimumReadyDuration else {
            releaseDecodedAudioBatches(prerollBatches)
            manager.disconnect()
            markNextPreparationFailed(generation: generation)
            return
        }

        // 保存预加载结果
        let stored = stateQueue.sync { () -> Bool in
            guard self.nextPreparationGeneration == generation,
                  self.nextURL == url else {
                return false
            }
            self.nextConnectionManager = manager
            self.nextDemuxer = demuxer
            self.nextAudioDecoder = decoder
            self.nextStreamInfo = info
            self.nextAudioTimeBase = nextTimeBase
            self.nextPrerollBatches = prerollBatches
            self.isNextReady = true
            return true
        }
        if !stored {
            releaseDecodedAudioBatches(prerollBatches)
            manager.disconnect()
        }
    }

    /// 无缝切换到预加载的下一首。
    /// 在 playbackQueue 上调用（EOF 时），不停止 AudioRenderer。
    /// 如果新流的采样率或声道数与当前不同，会重启 AudioRenderer 以匹配新格式。
    /// - Parameter discardsAudibleTail: 调用方随后会 flush 掉旧曲的缓冲尾巴
    ///   （强制切换场景）。此时听感立即切换，UI 通知也立即发出。
    /// - Returns: true 表示切换成功，播放循环应继续；false 表示没有预加载
    private func transitionToNextTrack(discardsAudibleTail: Bool = false) -> Bool {
        // 切 UI 的时机要和“用户还能听到上一首”的时机保持一致。
        // 自然 EOF：尾巴会播完，按尾巴时长延迟通知；
        // 强制切换：尾巴将被丢弃，视为 0。
        let queuedTailDuration = audioRenderer.queuedDuration
        let remainingAudibleTail: TimeInterval
        if discardsAudibleTail {
            remainingAudibleTail = 0
        } else if queuedTailDuration.isFinite && !queuedTailDuration.isNaN {
            remainingAudibleTail = max(0, queuedTailDuration)
        } else {
            remainingAudibleTail = 0
        }

        // 原子性地取出预加载的组件
        let (nextDemuxer, nextDecoder, nextInfo, nextTimeBase, nextConnMgr, nextPreroll) = stateQueue.sync {
            () -> (Demuxer?, AudioDecoder?, StreamInfo?, AVRational, ConnectionManager?, [DecodedAudioBatch]) in
            guard isNextReady else {
                return (nil, nil, nil, AVRational(num: 0, den: 1), nil, [])
            }

            let d = self.nextDemuxer
            let dec = self.nextAudioDecoder
            let info = self.nextStreamInfo
            let tb = self.nextAudioTimeBase
            let cm = self.nextConnectionManager
            let preroll = self.nextPrerollBatches

            // 清空预加载状态
            self.nextDemuxer = nil
            self.nextAudioDecoder = nil
            self.nextStreamInfo = nil
            self.nextAudioTimeBase = AVRational(num: 0, den: 1)
            self.nextConnectionManager = nil
            self.nextPrerollBatches = []
            self.nextURL = nil
            self.isNextReady = false
            self.nextPreparationGeneration &+= 1

            return (d, dec, info, tb, cm, preroll)
        }

        guard let demuxer = nextDemuxer, let decoder = nextDecoder, let info = nextInfo else {
            releaseDecodedAudioBatches(nextPreroll)
            return false
        }

        audioRenderer.markInputActive()
        if discardsAudibleTail {
            audioRenderer.flushQueue()
        }

        // 检查新 decoder 的输出格式是否与当前 AudioRenderer 匹配
        let newSampleRate = decoder.outputSampleRate
        let newChannelCount = decoder.outputChannelCount
        let currentRendererRate = audioRenderer.actualSampleRate
        let currentRendererChannels = audioRenderer.actualChannelCount
        let needsRendererRestart =
            newSampleRate != currentRendererRate ||
            newChannelCount != currentRendererChannels

        seekLock.lock()
        let hasPendingSeek = pendingSeekTime != nil
        seekLock.unlock()

        let crossfadeConfiguration = stateQueue.sync {
            (
                duration: TimeInterval(self.crossfadeDuration),
                outgoingGainDB: self.crossfadeOutgoingGainDB,
                incomingGainDB: self.crossfadeIncomingGainDB
            )
        }
        let configuredCrossfade = crossfadeConfiguration.duration
        let didStartCrossfade = !discardsAudibleTail
            && !hasPendingSeek
            && !needsRendererRestart
            && !nextPreroll.isEmpty
            && audioRenderer.beginCrossfade(
                duration: configuredCrossfade,
                outgoingGainDB: crossfadeConfiguration.outgoingGainDB,
                incomingGainDB: crossfadeConfiguration.incomingGainDB
            )
        let overlapDuration = didStartCrossfade
            ? min(configuredCrossfade, remainingAudibleTail)
            : 0
        let uiTransitionDelay = max(0, remainingAudibleTail - overlapDuration * 0.5)

        // 如果采样率或声道数变了，需要重启 AudioRenderer
        if needsRendererRestart {
            // 先清空旧缓冲区
            audioRenderer.flushQueue()
            // 停止旧的 AudioRenderer
            audioRenderer.stop()
            // 用新格式重启
            let format = makeAudioFormat(sampleRate: newSampleRate, channelCount: newChannelCount)
            do {
                try audioRenderer.start(format: format)
            } catch {
                // 新格式无法启动时不能继续提交下一首。先尽量恢复旧 renderer，
                // 然后把失败交还应用层走独立管线，避免 UI 已切歌但实际无声。
                let oldFormat = makeAudioFormat(
                    sampleRate: currentRendererRate,
                    channelCount: currentRendererChannels
                )
                try? audioRenderer.start(format: oldFormat)
                nextConnMgr?.disconnect()
                releaseDecodedAudioBatches(nextPreroll)
                print("[StreamPlayer] ⚠️ next renderer restart failed: \(error)")
                return false
            }
        }

        // 释放旧的 pipeline 组件（但不停止 AudioRenderer）
        stateQueue.sync {
            // 断开旧的连接管理器
            self.connectionManager?.disconnect()
            self.audioDecoder = nil
            self.videoDecoder = nil
            self.videoPipelineEpoch &+= 1
            self.demuxer = demuxer
            self.audioDecoder = decoder
            self.connectionManager = nextConnMgr
            self.storedStreamInfo = info
            self.audioTimeBase = nextTimeBase
            self.audioPTSOffset = nil  // 新歌曲重新计算 PTS 偏移
            self.currentURL = info.url
            self.endOfStreamDrainActive = false
            // 如果有 pendingSeekTime（音质切换），保持当前时间不变
            // 否则是正常切歌，重置为 0
            if !hasPendingSeek {
                self.storedPreviousTrackActualDuration = self.decodedTime
                self.decodedTime = 0
                if needsRendererRestart {
                    self.audibleTransitionDeadline = nil
                    self.audibleTransitionStartedAt = nil
                    self.previousTrackDisplayStartTime = nil
                } else {
                    let now = Date()
                    self.audibleTransitionDeadline = now.addingTimeInterval(uiTransitionDelay)
                    self.audibleTransitionStartedAt = now
                    self.previousTrackDisplayStartTime = max(
                        0,
                        (self.storedPreviousTrackActualDuration ?? 0) - uiTransitionDelay
                    )
                }
            } else {
                self.audibleTransitionDeadline = nil
                self.audibleTransitionStartedAt = nil
                self.previousTrackDisplayStartTime = nil
            }
        }

        // Decoder and network I/O for these buffers completed during preparation.
        // Enqueueing them behind the old tail removes the first-packet gap.
        for batch in nextPreroll {
            handleDecodedAudioBuffers(
                batch.buffers,
                packetPTS: batch.packetPTS,
                timeBase: batch.timeBase,
                enqueueToRenderer: true
            )
        }

        // 重置同步控制器
        syncController.reset()

        // 注意：这里不再发送 didUpdateDuration，因为在无缝切歌场景下，
        // didUpdateDuration 会先于 playerDidTransitionToNextTrack 到达主线程，
        // 导致当前歌曲的进度条总时长被下一首的 duration 覆盖。
        // duration 已保存在 streamInfo 中，app 层在切歌完成后可从 streamInfo.duration 获取。

        // 通知 app 层已切换到下一首。
        // 对普通无缝切歌，需等待旧音频尾巴真正播完后再切 UI；
        // 对音质切换（pendingSeekTime != nil），则立即通知。
        let shouldDelayTransition = !hasPendingSeek && !needsRendererRestart
        let transitionDelay: TimeInterval = shouldDelayTransition ? uiTransitionDelay : 0
        let playbackGeneration = stateQueue.sync { self.playbackGeneration }
        let notificationGeneration = stateQueue.sync { () -> UInt64 in
            pendingTransitionNotificationWorkItem?.cancel()
            transitionNotificationGeneration &+= 1
            return transitionNotificationGeneration
        }
        let notifyWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let shouldNotify = self.stateQueue.sync { () -> Bool in
                guard self.isPlaybackActive,
                      self.playbackGeneration == playbackGeneration,
                      self.transitionNotificationGeneration == notificationGeneration else {
                    return false
                }
                self.audibleTransitionDeadline = nil
                self.audibleTransitionStartedAt = nil
                self.previousTrackDisplayStartTime = nil
                self.pendingTransitionNotificationWorkItem = nil
                return true
            }
            guard shouldNotify else { return }
            self.delegate?.playerDidTransitionToNextTrack(self)
        }
        stateQueue.sync {
            if transitionNotificationGeneration == notificationGeneration {
                pendingTransitionNotificationWorkItem = notifyWorkItem
            }
        }
        if transitionDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDelay, execute: notifyWorkItem)
        } else {
            DispatchQueue.main.async(execute: notifyWorkItem)
        }

        return true
    }
    private func releasePacket(_ pkt: UnsafeMutablePointer<AVPacket>) {
        var packet: UnsafeMutablePointer<AVPacket>? = pkt
        av_packet_unref(pkt)
        av_packet_free(&packet)
    }

    private func handleDecodedAudioBuffers(
        _ audioBuffers: [AudioBuffer],
        packetPTS: Int64,
        timeBase: AVRational,
        enqueueToRenderer: Bool
    ) {
        var packetBufferOffset: TimeInterval = 0

        for audioBuffer in audioBuffers {
            guard audioBuffer.frameCount > 0, audioBuffer.duration > 0 else {
                audioBuffer.data.deallocate()
                continue
            }
            let pts: TimeInterval
            let nopts = Int64(bitPattern: UInt64(0x8000000000000000)) // AV_NOPTS_VALUE
            if packetPTS != nopts && packetPTS >= 0 && timeBase.den > 0 {
                let basePTS = Double(packetPTS) * Double(timeBase.num) / Double(timeBase.den)
                let rawPTS = basePTS + packetBufferOffset
                let ptsOffset: TimeInterval = stateQueue.sync {
                    if self.audioPTSOffset == nil {
                        if let target = self.seekTargetTime {
                            self.audioPTSOffset = rawPTS - target
                        } else {
                            self.audioPTSOffset = rawPTS
                        }
                    }
                    return self.audioPTSOffset ?? 0
                }
                pts = rawPTS - ptsOffset
            } else {
                pts = stateQueue.sync { self.decodedTime }
            }
            packetBufferOffset += audioBuffer.duration

            if enqueueToRenderer {
                audioRenderer.enqueue(audioBuffer, presentationTime: pts)
            }

            syncController.updateAudioClock(pts)

            stateQueue.sync {
                let endPts = pts + audioBuffer.duration

                if let target = self.seekTargetTime {
                    if pts >= target {
                        self.seekTargetTime = nil
                        self.decodedTime = endPts
                    }
                } else {
                    self.decodedTime = endPts
                }
            }

            lyricSyncer.update(time: pts)

            let shouldSeekToA: TimeInterval? = stateQueue.sync {
                if self.abLoopEnabled,
                   let a = self.loopPointA,
                   let b = self.loopPointB,
                   pts >= b {
                    return a
                }
                return nil
            }
            if let a = shouldSeekToA {
                seekLock.lock()
                pendingSeekGeneration &+= 1
                pendingSeekTime = a
                seekLock.unlock()
            }
        }
    }

    ///
    /// 使用 packet PTS + audioTimeBase 精确计算播放时间，避免 duration 累加漂移。
    /// 可恢复错误（单帧解码失败）会被跳过，不可恢复错误会触发自动停止。
    ///
    /// - Returns: An unrecoverable `FFmpegError` if one occurred, or `nil` on success/skip.
    @discardableResult
    private func processAudioPacket(_ pkt: UnsafeMutablePointer<AVPacket>) -> FFmpegError? {
        // 在 defer 之前读取 PTS，因为 av_packet_unref 会清除它
        let packetPTS = pkt.pointee.pts
        let timeBase = stateQueue.sync { self.audioTimeBase }

        defer { releasePacket(pkt) }

        guard let decoder = stateQueue.sync(execute: { self.audioDecoder }) else { return nil }

        do {
            let audioBuffers = try decoder.decodeAll(packet: pkt)
            handleDecodedAudioBuffers(
                audioBuffers,
                packetPTS: packetPTS,
                timeBase: timeBase,
                enqueueToRenderer: true
            )
            return nil
        } catch let error as FFmpegError where error.isUnrecoverable {
            return error
        } catch {
            return nil
        }
    }

    /// Processes a single video packet: decode → sync → render.
    ///
    /// Recoverable errors (individual frame decoding failures) are caught and
    /// skipped. Unrecoverable errors (resource allocation failures, etc.) are
    /// propagated to trigger an automatic stop.
    /// Frames that are too far behind audio are dropped per A/V sync logic.
    ///
    /// - Returns: An unrecoverable `FFmpegError` if one occurred, or `nil` on success/skip.
    private func enqueueVideoPacket(
        _ pkt: UnsafeMutablePointer<AVPacket>,
        generation: UInt64
    ) {
        let epoch = stateQueue.sync { videoPipelineEpoch }
        videoPacketLock.lock()
        guard pendingVideoPacketCount < maxPendingVideoPackets else {
            videoPacketLock.unlock()
            releasePacket(pkt)
            return
        }
        pendingVideoPacketCount += 1
        videoPacketLock.unlock()

        videoDecodeQueue.async { [weak self] in
            guard let self else {
                var packet: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_unref(pkt)
                av_packet_free(&packet)
                return
            }
            defer {
                self.videoPacketLock.lock()
                self.pendingVideoPacketCount = max(0, self.pendingVideoPacketCount - 1)
                self.videoPacketLock.unlock()
            }

            if let error = self.processVideoPacket(
                pkt,
                generation: generation,
                epoch: epoch
            ) {
                self.handleUnrecoverableError(error, generation: generation)
            }
        }
    }

    @discardableResult
    private func processVideoPacket(
        _ pkt: UnsafeMutablePointer<AVPacket>,
        generation: UInt64,
        epoch: UInt64
    ) -> FFmpegError? {
        defer {
            var packet: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_unref(pkt)
            av_packet_free(&packet)
        }

        guard let decoder = stateQueue.sync(execute: { () -> VideoDecoder? in
            guard isPlaybackActive,
                  playbackGeneration == generation,
                  videoPipelineEpoch == epoch else { return nil }
            return videoDecoder
        }) else { return nil }

        do {
            let frame = try decoder.decode(packet: pkt)

            // Check A/V sync
            let action = syncController.syncAction(for: frame.pts)

            switch action {
            case .display(let delay):
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
                guard isCurrentVideoDecoder(
                    decoder,
                    generation: generation,
                    epoch: epoch
                ) else { return nil }
                videoRenderer.render(frame)
                syncController.updateVideoClock(frame.pts)

            case .drop:
                // Frame is too far behind audio - skip it
                break

            case .repeatPrevious(let delay):
                // Video is ahead of audio - wait then display
                Thread.sleep(forTimeInterval: delay)
                guard isCurrentVideoDecoder(
                    decoder,
                    generation: generation,
                    epoch: epoch
                ) else { return nil }
                videoRenderer.render(frame)
                syncController.updateVideoClock(frame.pts)
            }
            return nil
        } catch let error as FFmpegError where error.isUnrecoverable {
            // Unrecoverable error — propagate to trigger auto-stop
            return error
        } catch {
            // Recoverable error (e.g., single frame decode failure) — skip and continue
            return nil
        }
    }

    // MARK: - Helpers

    /// Checks whether the playback loop still belongs to the active session.
    private func isActive(generation: UInt64) -> Bool {
        stateQueue.sync {
            isPlaybackActive && playbackGeneration == generation
        }
    }

    private func isCurrentVideoDecoder(
        _ decoder: VideoDecoder,
        generation: UInt64,
        epoch: UInt64
    ) -> Bool {
        stateQueue.sync {
            isPlaybackActive
                && playbackGeneration == generation
                && videoPipelineEpoch == epoch
                && videoDecoder === decoder
        }
    }

    /// Transitions the player state and notifies the delegate.
    private func transitionState(to newState: PlaybackState) {
        let shouldNotify = stateQueue.sync { () -> Bool in
            guard storedState != newState else { return false }
            storedState = newState
            return true
        }
        guard shouldNotify else { return }
        delegate?.player(self, didChangeState: newState)
    }

    /// Handles an unrecoverable error by stopping playback and notifying the delegate.
    private func handleUnrecoverableError(_ error: Error, generation: UInt64) {
        guard isActive(generation: generation) else { return }

        let ffError: FFmpegError
        if let fe = error as? FFmpegError {
            ffError = fe
        } else {
            ffError = .connectionFailed(code: -1, message: error.localizedDescription)
        }

        guard stopInternal(expectedGeneration: generation) else { return }
        transitionState(to: .error(ffError))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.player(self, didEncounterError: ffError)
        }
    }

    // MARK: - Network Reconnection

    /// 在播放循环中无感断点续播：断开旧连接 → 立即重建 pipeline → seek 到断点 → 预填充缓冲。
    /// AudioRenderer 在整个过程中保持运行，利用已有缓冲覆盖重连耗时，实现无缝衔接。
    /// - Returns: true 表示重连成功，播放循环可继续；false 表示放弃。
    private func attemptReconnect(generation: UInt64) -> Bool {
        networkReconnectAttempts += 1
        guard networkReconnectAttempts <= maxNetworkReconnectAttempts else {
            print("[StreamPlayer] ❌ reconnect attempts exhausted (\(maxNetworkReconnectAttempts))")
            return false
        }

        let url = stateQueue.sync { self.currentURL }
        guard let url, !url.isEmpty else { return false }
        guard isActive(generation: generation) else { return false }

        let recoveryClock = stateQueue.sync {
            (
                decodedTime: self.decodedTime,
                duration: self.storedStreamInfo?.duration
            )
        }
        let rawResumePosition = max(0, recoveryClock.decodedTime)
        if let duration = recoveryClock.duration,
           duration > 1 {
            let endGuard = max(2, min(8, duration * 0.03))
            if rawResumePosition >= duration - endGuard {
                print(
                    "[StreamPlayer] ⏹️ skip reconnect near natural EOF: " +
                    "position=\(String(format: "%.1f", rawResumePosition))s, " +
                    "duration=\(String(format: "%.1f", duration))s"
                )
                return false
            }
        }
        let resumePosition: TimeInterval
        if let duration = recoveryClock.duration, duration > 1 {
            resumePosition = min(rawResumePosition, max(0, duration - 1))
        } else {
            resumePosition = rawResumePosition
        }
        let bufferedSeconds = audioRenderer.queuedDuration

        print(
            "[StreamPlayer] 🔄 network disconnected, seamless reconnect \(networkReconnectAttempts)/\(maxNetworkReconnectAttempts), " +
            "resume=\(String(format: "%.1f", resumePosition))s, buffer=\(String(format: "%.2f", bufferedSeconds))s"
        )

        // 非首次重连才短暂等待，首次立即尝试（缓冲区正在消耗，不能浪费时间）
        if networkReconnectAttempts > 1 {
            let delay: TimeInterval = networkReconnectAttempts == 2 ? 0.3 : 1.0
            Thread.sleep(forTimeInterval: delay)
        }

        guard isActive(generation: generation) else { return false }

        // 断开旧连接（保留 AudioRenderer 继续播放缓冲区中的音频）
        stateQueue.sync {
            self.connectionManager?.disconnect()
            self.connectionManager = nil
            self.audioDecoder = nil
            self.videoDecoder = nil
            self.videoPipelineEpoch &+= 1
            self.demuxer = nil
        }

        // 重新连接
        let newManager = ConnectionManager()
        let formatContext: FFmpegFormatContext
        do {
            var connectResult: Result<FFmpegFormatContext, Error>?
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let ctx = try await newManager.connect(url: url)
                    connectResult = .success(ctx)
                } catch {
                    connectResult = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()

            switch connectResult! {
            case .success(let ctx): formatContext = ctx
            case .failure(let error): throw error
            }
        } catch {
            print("[StreamPlayer] ⚠️ reconnect attempt \(networkReconnectAttempts) connect failed: \(error)")
            newManager.disconnect()
            return attemptReconnect(generation: generation)
        }

        guard isActive(generation: generation) else {
            newManager.disconnect()
            return false
        }

        // 重建 demuxer + decoder
        let newDemuxer = Demuxer(formatContext: formatContext, url: url)
        let info: StreamInfo
        do {
            info = try newDemuxer.findStreams()
        } catch {
            print("[StreamPlayer] ❌ reconnect findStreams failed: \(error)")
            newManager.disconnect()
            return false
        }

        guard info.hasAudio, newDemuxer.currentAudioStreamIndex >= 0 else {
            print("[StreamPlayer] ❌ reconnect: no audio stream")
            newManager.disconnect()
            return false
        }

        let streamIndex = Int(newDemuxer.currentAudioStreamIndex)
        guard let stream = formatContext.stream(at: streamIndex),
              let codecpar = stream.pointee.codecpar else {
            newManager.disconnect()
            return false
        }

        let targetRate = audioRenderer.actualSampleRate > 0 ? audioRenderer.actualSampleRate : nil
        let newDecoder: AudioDecoder
        do {
            newDecoder = try AudioDecoder(
                codecParameters: codecpar,
                codecID: codecpar.pointee.codec_id,
                targetSampleRate: targetRate,
                targetChannelCount: audioRenderer.actualChannelCount
            )
        } catch {
            print("[StreamPlayer] ❌ reconnect decoder init failed: \(error)")
            newManager.disconnect()
            return false
        }

        // Seek 到断点位置
        do {
            try newDemuxer.seek(to: resumePosition)
        } catch {
            print("[StreamPlayer] ⚠️ reconnect seek failed: \(error)")
            // Continuing after a failed non-zero seek starts the new pipeline
            // at the beginning while the public clock remains at the old
            // position. Abort so the app can resolve the interruption instead.
            if resumePosition > 0.5 {
                newManager.disconnect()
                return false
            }
        }

        // 原子替换 pipeline 组件
        let newTimeBase = stream.pointee.time_base
        let installed = stateQueue.sync { () -> Bool in
            guard self.isPlaybackActive,
                  self.playbackGeneration == generation else {
                return false
            }
            self.connectionManager = newManager
            self.demuxer = newDemuxer
            self.audioDecoder = newDecoder
            self.videoDecoder = nil
            self.storedStreamInfo = info
            self.audioTimeBase = newTimeBase
            self.audioPTSOffset = nil
            self.seekTargetTime = resumePosition
            return true
        }
        guard installed else {
            newManager.disconnect()
            return false
        }

        syncController.reset()
        repairEngine.reset()
        audioRenderer.markInputActive()

        // 预填充缓冲区：在恢复播放循环前先解码一批 packet 喂给 AudioRenderer，
        // 确保重连后缓冲区有充足数据，避免断音。
        let prefilledDuration = prefillAudioBuffer(
            demuxer: newDemuxer,
            decoder: newDecoder,
            timeBase: newTimeBase,
            generation: generation
        )

        let postReconnectBuffer = audioRenderer.queuedDuration
        print(
            "[StreamPlayer] ✅ seamless reconnect succeeded, prefilled=\(String(format: "%.2f", prefilledDuration))s, " +
            "total buffer=\(String(format: "%.2f", postReconnectBuffer))s"
        )
        return true
    }

    /// 重连后预填充 AudioRenderer 缓冲区，尽量补满以保证无缝。
    /// - Returns: 预填充的音频时长（秒）
    private func prefillAudioBuffer(
        demuxer: Demuxer,
        decoder: AudioDecoder,
        timeBase: AVRational,
        generation: UInt64,
        targetDuration: TimeInterval = 1.0,
        maxPackets: Int = 64
    ) -> TimeInterval {
        var totalDuration: TimeInterval = 0

        for _ in 0..<maxPackets {
            if totalDuration >= targetDuration { break }
            guard isActive(generation: generation) else { break }

            let packet: Demuxer.PacketType?
            do {
                packet = try demuxer.readNextPacket()
            } catch {
                break
            }
            guard let packet else { break }

            guard isActive(generation: generation) else {
                switch packet {
                case .audio(let pkt), .video(let pkt):
                    releasePacket(pkt)
                }
                break
            }

            switch packet {
            case .audio(let pkt):
                let packetPTS = pkt.pointee.pts
                defer { releasePacket(pkt) }
                do {
                    let buffers = try decoder.decodeAll(packet: pkt)
                    let batchDuration = buffers.reduce(0) { $0 + $1.duration }
                    handleDecodedAudioBuffers(
                        buffers,
                        packetPTS: packetPTS,
                        timeBase: timeBase,
                        enqueueToRenderer: true
                    )
                    totalDuration += batchDuration
                } catch {
                    continue
                }
            case .video(let pkt):
                releasePacket(pkt)
            }
        }

        return totalDuration
    }

    /// Handles a network disconnection detected during the demux/decode loop.
    ///
    /// Updates the ConnectionManager state to reflect the disconnection,
    /// stops playback, transitions to the error state, and notifies the
    /// app layer via the StreamPlayerDelegate.
    private func handleNetworkDisconnection(generation: UInt64) {
        guard isActive(generation: generation) else { return }
        let error = FFmpegError.networkDisconnected

        // Notify the ConnectionManager about the disconnection so its delegate
        // (if any) also receives the state change.
        let manager = stateQueue.sync { connectionManager }
        if let manager {
            manager.delegate?.connectionManager(manager, didFailWith: error)
        }

        guard stopInternal(
            rendererStopStrategy: .gracefulNetworkDisconnect,
            expectedGeneration: generation
        ) else { return }
        transitionState(to: .error(error))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.player(self, didEncounterError: error)
        }
    }

    /// Stops playback and cleans up all resources without changing state.
    @discardableResult
    private func stopInternal(
        rendererStopStrategy: RendererStopStrategy = .immediate,
        expectedGeneration: UInt64? = nil,
        stopReason: PlaybackStopReason? = nil
    ) -> Bool {
        // Renderer teardown clears both its presentation clock and decodedTime.
        // Capture the last audible position before changing either one.
        let terminalPlaybackTime = currentTime
        let shouldStop = stateQueue.sync { () -> Bool in
            if let expectedGeneration,
               playbackGeneration != expectedGeneration {
                return false
            }
            if isPlaybackActive,
               terminalPlaybackTime.isFinite,
               !terminalPlaybackTime.isNaN {
                storedLastTerminalPlaybackTime = max(0, terminalPlaybackTime)
            }
            if let stopReason {
                storedLastStopReason = stopReason
            }
            playbackGeneration &+= 1
            isPlaybackActive = false
            endOfStreamDrainActive = false
            pendingTransitionNotificationWorkItem?.cancel()
            pendingTransitionNotificationWorkItem = nil
            transitionNotificationGeneration &+= 1
            audibleTransitionDeadline = nil
            audibleTransitionStartedAt = nil
            previousTrackDisplayStartTime = nil
            storedPreviousTrackActualDuration = nil
            requiredInitialSeekPosition = nil
            startsPausedGeneration = nil
            return true
        }
        guard shouldStop else { return false }

        cancelNextPreparation()
        networkReconnectAttempts = 0
        pauseSemaphore.signal()

        seekLock.lock()
        pendingSeekGeneration &+= 1
        pendingSeekTime = nil
        seekLock.unlock()
        
        // 清除 seek 目标时间
        stateQueue.sync {
            seekTargetTime = nil
        }

        stopAudioRenderer(using: rendererStopStrategy)
        videoRenderer.clear()

        // Reset sync controller
        syncController.reset()

        let retired = stateQueue.sync { () -> RetiredResources in
            let resources = RetiredResources(
                connection: connectionManager,
                demuxer: demuxer,
                audioDecoder: audioDecoder,
                videoDecoder: videoDecoder
            )
            audioDecoder = nil
            videoDecoder = nil
            demuxer = nil
            connectionManager = nil
            audioTimeBase = AVRational(num: 0, den: 1)
            audioPTSOffset = nil
            decodedTime = 0
            return resources
        }
        retireResources(retired)
        return true
    }

    private enum RendererStopStrategy {
        case immediate
        case gracefulNetworkDisconnect
    }

    private func stopAudioRenderer(using strategy: RendererStopStrategy) {
        switch strategy {
        case .immediate:
            audioRenderer.stop()
        case .gracefulNetworkDisconnect:
            gracefullyStopAudioRendererAfterNetworkDisconnection()
        }
    }

    private func gracefullyStopAudioRendererAfterNetworkDisconnection() {
        let initialQueuedBufferCount = audioRenderer.queuedBufferCount
        let initialQueuedDuration = audioRenderer.queuedDuration
        let drainWindow = min(0.75, max(0.15, initialQueuedDuration + 0.05))

        if initialQueuedBufferCount > 0 {
            print(
                "[StreamPlayer] 🌐 network disconnected, drain queued audio first: " +
                "buffers=\(initialQueuedBufferCount), duration=\(String(format: "%.3f", initialQueuedDuration))s, " +
                "window=\(String(format: "%.3f", drainWindow))s"
            )
            waitForRendererDrain(maxWait: drainWindow, requireActive: false)
        } else {
            print("[StreamPlayer] 🌐 network disconnected with empty renderer queue, fade out tail directly")
        }

        let remainingQueuedBufferCount = audioRenderer.queuedBufferCount
        let remainingQueuedDuration = audioRenderer.queuedDuration
        if remainingQueuedBufferCount > 0 {
            print(
                "[StreamPlayer] 🌐 renderer still has queued audio after short drain, " +
                "forcing graceful fade-out: buffers=\(remainingQueuedBufferCount), " +
                "duration=\(String(format: "%.3f", remainingQueuedDuration))s"
            )
        } else {
            print("[StreamPlayer] 🌐 renderer drained, scheduling graceful stop fade-out")
        }

        audioRenderer.gracefulStop(flushRemainingAudio: true)
    }

    /// Creates an `AudioStreamBasicDescription` for Float32 interleaved PCM.
    private func makeAudioFormat(sampleRate: Int, channelCount: Int) -> AudioStreamBasicDescription {
        return AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channelCount * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channelCount * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
    }
}
