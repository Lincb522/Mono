// AudioRepairEngine.swift
// FFmpegSwiftSDK
//
// 音频修复引擎：在所有音效处理之后、输出到硬件之前，
// 自动检测并修复各种音频问题。

import Foundation
import Accelerate

/// 音频修复引擎
public final class AudioRepairEngine {
    private struct Configuration: Equatable {
        var isDeclipEnabled = false
        var isDenoiseEnabled = false
        var isGapSmoothingEnabled = false
        var isOverlapRemovalEnabled = false
        var isPopRemovalEnabled = false
        var isSoftLimiterEnabled = false
        var isDitherEnabled = false
        var isFadeInProtectionEnabled = false
        var isLoudnessStabilizerEnabled = false
        var isReverbTailGuardEnabled = false
        var isPhaseContinuityEnabled = false
        var isFilterTransitionEnabled = false
        var isDCBlockerEnabled = false
        var clipThreshold: Float = 0.98
        var popSensitivity: Float = 0.3
        var limiterThreshold: Float = 0.95
        var fadeInSamples: Int = 256
        var loudnessSmoothing: Float = 0.15
        var loudnessJumpThreshold: Float = 12.0
        var filterTransitionMaxSamples: Int = 1024
        var reverbTailHistoryLength: Int = 4096
        var outputGainDB: Float = 0
        var perceptualMakeupDB: Float = 0
        var resetSerial: UInt64 = 0
        var statisticsResetSerial: UInt64 = 0

        var isActive: Bool {
            isDeclipEnabled || isDenoiseEnabled || isGapSmoothingEnabled
                || isOverlapRemovalEnabled || isPopRemovalEnabled || isSoftLimiterEnabled
                || isDitherEnabled || isFadeInProtectionEnabled || isLoudnessStabilizerEnabled
                || isReverbTailGuardEnabled || isPhaseContinuityEnabled || isFilterTransitionEnabled
                || isDCBlockerEnabled
                || abs(outputGainDB) > 0.001 || perceptualMakeupDB > 0.001
        }
    }

    private let configuration = RealtimeAudioConfiguration(Configuration())
    private let processor = AudioRepairProcessor()
    private var applied = Configuration()
    private let statisticsLock = NSLock()
    private var statistics = RepairStats()
    private var statisticsResetSerial: UInt64 = 0

    public init() {}

    public var isDeclipEnabled: Bool {
        get { configuration.read { $0.isDeclipEnabled } }
        set { configuration.update { $0.isDeclipEnabled = newValue } }
    }

    public var isDenoiseEnabled: Bool {
        get { configuration.read { $0.isDenoiseEnabled } }
        set { configuration.update { $0.isDenoiseEnabled = newValue } }
    }

    public var isGapSmoothingEnabled: Bool {
        get { configuration.read { $0.isGapSmoothingEnabled } }
        set { configuration.update { $0.isGapSmoothingEnabled = newValue } }
    }

    public var isOverlapRemovalEnabled: Bool {
        get { configuration.read { $0.isOverlapRemovalEnabled } }
        set { configuration.update { $0.isOverlapRemovalEnabled = newValue } }
    }

    public var isPopRemovalEnabled: Bool {
        get { configuration.read { $0.isPopRemovalEnabled } }
        set { configuration.update { $0.isPopRemovalEnabled = newValue } }
    }

    public var isSoftLimiterEnabled: Bool {
        get { configuration.read { $0.isSoftLimiterEnabled } }
        set { configuration.update { $0.isSoftLimiterEnabled = newValue } }
    }

    public var isDitherEnabled: Bool {
        get { configuration.read { $0.isDitherEnabled } }
        set { configuration.update { $0.isDitherEnabled = newValue } }
    }

    public var isFadeInProtectionEnabled: Bool {
        get { configuration.read { $0.isFadeInProtectionEnabled } }
        set { configuration.update { $0.isFadeInProtectionEnabled = newValue } }
    }

    public var isLoudnessStabilizerEnabled: Bool {
        get { configuration.read { $0.isLoudnessStabilizerEnabled } }
        set { configuration.update { $0.isLoudnessStabilizerEnabled = newValue } }
    }

    public var isReverbTailGuardEnabled: Bool {
        get { configuration.read { $0.isReverbTailGuardEnabled } }
        set { configuration.update { $0.isReverbTailGuardEnabled = newValue } }
    }

    public var isPhaseContinuityEnabled: Bool {
        get { configuration.read { $0.isPhaseContinuityEnabled } }
        set { configuration.update { $0.isPhaseContinuityEnabled = newValue } }
    }

    public var isFilterTransitionEnabled: Bool {
        get { configuration.read { $0.isFilterTransitionEnabled } }
        set { configuration.update { $0.isFilterTransitionEnabled = newValue } }
    }

    public var isDCBlockerEnabled: Bool {
        get { configuration.read { $0.isDCBlockerEnabled } }
        set { configuration.update { $0.isDCBlockerEnabled = newValue } }
    }

    public var clipThreshold: Float {
        get { configuration.read { $0.clipThreshold } }
        set { configuration.update { $0.clipThreshold = newValue } }
    }

    public var popSensitivity: Float {
        get { configuration.read { $0.popSensitivity } }
        set { configuration.update { $0.popSensitivity = newValue } }
    }

    public var limiterThreshold: Float {
        get { configuration.read { $0.limiterThreshold } }
        set { configuration.update { $0.limiterThreshold = newValue } }
    }

    public var fadeInSamples: Int {
        get { configuration.read { $0.fadeInSamples } }
        set { configuration.update { $0.fadeInSamples = newValue } }
    }

    public var loudnessSmoothing: Float {
        get { configuration.read { $0.loudnessSmoothing } }
        set { configuration.update { $0.loudnessSmoothing = newValue } }
    }

    public var loudnessJumpThreshold: Float {
        get { configuration.read { $0.loudnessJumpThreshold } }
        set { configuration.update { $0.loudnessJumpThreshold = newValue } }
    }

    public var filterTransitionMaxSamples: Int {
        get { configuration.read { $0.filterTransitionMaxSamples } }
        set { configuration.update { $0.filterTransitionMaxSamples = newValue } }
    }

    public var reverbTailHistoryLength: Int {
        get { configuration.read { $0.reverbTailHistoryLength } }
        set { configuration.update { $0.reverbTailHistoryLength = newValue } }
    }

    public var isActive: Bool { configuration.read { $0.isActive } }

    public func configureOutputSafety(
        limiterEnabled: Bool,
        ceilingDB: Float = -1,
        declipEnabled: Bool = false,
        clipThreshold: Float = 0.98,
        transitionProtectionEnabled: Bool = false,
        outputGainDB: Float = 0,
        perceptualMakeupDB: Float = 0
    ) {
        let ceiling = min(-0.05, max(-12, ceilingDB.isFinite ? ceilingDB : -1))
        let threshold = powf(10, ceiling / 20)
        configuration.update {
            $0.isSoftLimiterEnabled = limiterEnabled
            $0.isDCBlockerEnabled = limiterEnabled
            $0.limiterThreshold = threshold
            $0.isDeclipEnabled = declipEnabled
            $0.clipThreshold = min(0.999, max(0.5, clipThreshold))
            $0.isFilterTransitionEnabled = transitionProtectionEnabled
            $0.outputGainDB = Self.safeOutputGain(outputGainDB)
            $0.perceptualMakeupDB = Self.safeMakeup(perceptualMakeupDB, outputGain: $0.outputGainDB)
        }
    }

    public var outputGainDB: Float {
        get { configuration.read { $0.outputGainDB } }
        set {
            configuration.update {
                $0.outputGainDB = Self.safeOutputGain(newValue)
                $0.perceptualMakeupDB = Self.safeMakeup($0.perceptualMakeupDB, outputGain: $0.outputGainDB)
            }
        }
    }

    public var outputLimiterCeilingDB: Float {
        configuration.read { 20 * log10f(max($0.limiterThreshold, 0.000_001)) }
    }

    public var perceptualMakeupDB: Float { configuration.read { $0.perceptualMakeupDB } }

    public struct RepairStats {
        public var clippedSamplesRepaired: Int = 0
        public var popsRemoved: Int = 0
        public var gapsFilled: Int = 0
        public var overlapsFixed: Int = 0
        public var limiterActivations: Int = 0
        public var loudnessJumpsSmoothed: Int = 0
        public var reverbTailsFilled: Int = 0
        public var phaseFlipsFixed: Int = 0
        public var filterTransitions: Int = 0
        public var totalFramesProcessed: Int64 = 0
    }

    public var repairStats: RepairStats {
        let expectedSerial = configuration.read { $0.statisticsResetSerial }
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        return statisticsResetSerial == expectedSerial ? statistics : RepairStats()
    }

    public func resetStats() {
        configuration.update { $0.statisticsResetSerial &+= 1 }
    }

    public func enableAll() {
        configuration.update {
            $0.isDeclipEnabled = true
            $0.isDenoiseEnabled = true
            $0.isGapSmoothingEnabled = true
            $0.isOverlapRemovalEnabled = true
            $0.isPopRemovalEnabled = true
            $0.isSoftLimiterEnabled = true
            $0.isDitherEnabled = true
            $0.isFadeInProtectionEnabled = true
            $0.isLoudnessStabilizerEnabled = true
            $0.isReverbTailGuardEnabled = true
            $0.isPhaseContinuityEnabled = true
            $0.isFilterTransitionEnabled = true
            $0.isDCBlockerEnabled = true
        }
    }

    public func disableAll() {
        configuration.update {
            $0.isDeclipEnabled = false
            $0.isDenoiseEnabled = false
            $0.isGapSmoothingEnabled = false
            $0.isOverlapRemovalEnabled = false
            $0.isPopRemovalEnabled = false
            $0.isSoftLimiterEnabled = false
            $0.isDitherEnabled = false
            $0.isFadeInProtectionEnabled = false
            $0.isLoudnessStabilizerEnabled = false
            $0.isReverbTailGuardEnabled = false
            $0.isPhaseContinuityEnabled = false
            $0.isFilterTransitionEnabled = false
            $0.isDCBlockerEnabled = false
        }
    }

    public func reset() {
        configuration.update {
            $0.outputGainDB = 0
            $0.perceptualMakeupDB = 0
            $0.resetSerial &+= 1
        }
    }

    /// Called by one audio consumer; control setters may run concurrently.
    public func process(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int
    ) {
        if let next = configuration.takePending() {
            if next.resetSerial != applied.resetSerial { processor.reset() }
            if next.statisticsResetSerial != applied.statisticsResetSerial { processor.resetStats() }
            processor.isDeclipEnabled = next.isDeclipEnabled
            processor.isDenoiseEnabled = next.isDenoiseEnabled
            processor.isGapSmoothingEnabled = next.isGapSmoothingEnabled
            processor.isOverlapRemovalEnabled = next.isOverlapRemovalEnabled
            processor.isPopRemovalEnabled = next.isPopRemovalEnabled
            if !next.isSoftLimiterEnabled && applied.isSoftLimiterEnabled {
                processor.resetLimiter()
            }
            processor.isSoftLimiterEnabled = next.isSoftLimiterEnabled
            processor.isDitherEnabled = next.isDitherEnabled
            processor.isFadeInProtectionEnabled = next.isFadeInProtectionEnabled
            processor.isLoudnessStabilizerEnabled = next.isLoudnessStabilizerEnabled
            processor.isReverbTailGuardEnabled = next.isReverbTailGuardEnabled
            processor.isPhaseContinuityEnabled = next.isPhaseContinuityEnabled
            processor.isFilterTransitionEnabled = next.isFilterTransitionEnabled
            processor.isDCBlockerEnabled = next.isDCBlockerEnabled
            processor.clipThreshold = next.clipThreshold
            processor.popSensitivity = next.popSensitivity
            processor.limiterThreshold = next.limiterThreshold
            processor.fadeInSamples = next.fadeInSamples
            processor.loudnessSmoothing = next.loudnessSmoothing
            processor.loudnessJumpThreshold = next.loudnessJumpThreshold
            processor.filterTransitionMaxSamples = next.filterTransitionMaxSamples
            processor.reverbTailHistoryLength = next.reverbTailHistoryLength
            processor.outputGainDB = next.outputGainDB
            processor.setPerceptualMakeupTarget(next.perceptualMakeupDB)
            applied = next
        }
        // The final limiter must run even if a UI writer owns the mailbox.
        processor.process(data, frameCount: frameCount, channelCount: channelCount, sampleRate: sampleRate)
        if statisticsLock.try() {
            statistics = processor.repairStats
            statisticsResetSerial = applied.statisticsResetSerial
            statisticsLock.unlock()
        }
    }

    private static func safeOutputGain(_ value: Float) -> Float {
        min(9, max(-18, value.isFinite ? value : 0))
    }

    private static func safeMakeup(_ value: Float, outputGain: Float) -> Float {
        min(1.25, max(0, 9 - max(0, outputGain)), max(0, value.isFinite ? value : 0))
    }
}

// Only the audio consumer may access limiter envelopes, delay state and ramps.
private final class AudioRepairProcessor {

    // MARK: - 修复模块开关

    var isDeclipEnabled: Bool = false
    var isDenoiseEnabled: Bool = false
    var isGapSmoothingEnabled: Bool = false
    var isOverlapRemovalEnabled: Bool = false
    var isPopRemovalEnabled: Bool = false
    var isSoftLimiterEnabled: Bool = false
    var isDitherEnabled: Bool = false
    var isFadeInProtectionEnabled: Bool = false
    var isLoudnessStabilizerEnabled: Bool = false
    var isReverbTailGuardEnabled: Bool = false
    var isPhaseContinuityEnabled: Bool = false
    var isFilterTransitionEnabled: Bool = false
    var isDCBlockerEnabled: Bool = false

    var isActive: Bool {
        return isDeclipEnabled || isDenoiseEnabled || isGapSmoothingEnabled ||
               isOverlapRemovalEnabled || isPopRemovalEnabled || isSoftLimiterEnabled ||
               isDitherEnabled || isFadeInProtectionEnabled ||
               isLoudnessStabilizerEnabled || isReverbTailGuardEnabled ||
               isPhaseContinuityEnabled || isFilterTransitionEnabled ||
               isDCBlockerEnabled ||
               abs(outputGainDB) > 0.001 ||
               abs(outputGainCurrentLinear - 1) > 0.000_1 ||
               abs(perceptualMakeupDBStorage) > 0.001 ||
               abs(perceptualMakeupCurrentLinear - 1) > 0.000_1
    }

    // MARK: - 可调参数

    var clipThreshold: Float = 0.98
    var popSensitivity: Float = 0.3
    var limiterThreshold: Float = 0.95
    var fadeInSamples: Int = 256
    var loudnessSmoothing: Float = 0.15
    var loudnessJumpThreshold: Float = 12.0  // 12dB，只有非常剧烈的变化才触发
    var filterTransitionMaxSamples: Int = 1024
    var reverbTailHistoryLength: Int = 4096

    /// Post-processing gain applied after FFmpeg/EQ and before the final limiter.
    /// Mono uses this only to restore the level lost to AI safety preamp.
    var outputGainDB: Float {
        get { outputGainDBStorage }
        set {
            setOutputGainTarget(newValue)
            setPerceptualMakeupTarget(perceptualMakeupDBStorage)
        }
    }

    // MARK: - 内部状态

    private var dcFilterState: [DCBlockerState] = []
    private var ultrasonicFilterState: [Float] = []
    private var previousTail: [Float] = []
    private let tailLength: Int = 64
    private var lastSamples: [Float] = []
    private var fadeInCounter: Int = 0
    private var fadeInActive: Bool = true
    private var ditherState: Float = 0
    private var frameCount: Int64 = 0

    // 响度突变抑制状态
    private var rmsEnvelope: Float = 0
    private var loudnessGain: Float = 1.0
    private var previousRMS: Float = 0
    private var loudnessSmoothRemaining: Int = 0
    private var loudnessSmoothStartGain: Float = 1.0

    // 混响尾音保护状态
    private var reverbHistory: [Float] = []
    private var reverbHistoryWritePos: Int = 0
    private var reverbHistoryChannels: Int = 0
    private var reverbTailActive: Bool = false
    private var reverbTailRemaining: Int = 0

    // 相位连续性状态
    private var previousPhaseDirection: [Float] = []
    // 实时回调复用的斜率 scratch，避免每个 block 重新分配
    private var phaseDirectionScratch: [Float] = []

    // 滤镜重建过渡状态
    private var transitionBuffer: [Float] = []
    private var transitionRemaining: Int = 0
    private var transitionLength: Int = 0
    private var prevFrameRMS: Float = 0
    private var stableFrameCount: Int = 0
    private var outputGainDBStorage: Float = 0
    private var outputGainCurrentLinear: Float = 1
    private var outputGainStartLinear: Float = 1
    private var outputGainTargetLinear: Float = 1
    private var outputGainRampProcessedFrames = 0
    private var outputGainRampTotalFrames = 0
    private var outputGainRampPending = false
    private var perceptualMakeupDBStorage: Float = 0
    private var perceptualMakeupCurrentLinear: Float = 1
    private var perceptualMakeupStartLinear: Float = 1
    private var perceptualMakeupTargetLinear: Float = 1
    private var perceptualMakeupRampProcessedFrames = 0
    private var perceptualMakeupRampTotalFrames = 0
    private var perceptualMakeupRampPending = false
    // Float accumulation can stall a per-sample release before it reaches unity.
    private var truePeakLimiterGain: Double = 1
    private var truePeakHistory: [Float] = []

    private var stats = RepairStats()

    private struct DCBlockerState {
        var xPrev: Float = 0
        var yPrev: Float = 0
    }

    // MARK: - 修复统计

    typealias RepairStats = AudioRepairEngine.RepairStats

    var repairStats: RepairStats { stats }

    func resetStats() { stats = RepairStats() }

    // MARK: - 初始化

    init() {
        // Music playback is normally stereo. Pre-size the state used by the
        // final output guard so enabling an AI plan cannot allocate Arrays from
        // the first hardware callback.
        dcFilterState = Array(repeating: DCBlockerState(), count: 2)
        ultrasonicFilterState = Array(repeating: 0, count: 2)
        truePeakHistory = Array(repeating: 0, count: 2)
        lastSamples = Array(repeating: 0, count: 2)
        previousTail.reserveCapacity(tailLength * 8)
    }

    func resetLimiter() {
        truePeakLimiterGain = 1
        for index in truePeakHistory.indices { truePeakHistory[index] = 0 }
    }

    func reset() {
        for index in dcFilterState.indices { dcFilterState[index] = DCBlockerState() }
        for index in ultrasonicFilterState.indices { ultrasonicFilterState[index] = 0 }
        previousTail.removeAll()
        for index in lastSamples.indices { lastSamples[index] = 0 }
        fadeInCounter = 0
        fadeInActive = true
        ditherState = 0
        frameCount = 0
        rmsEnvelope = 0
        loudnessGain = 1.0
        previousRMS = 0
        loudnessSmoothRemaining = 0
        loudnessSmoothStartGain = 1.0
        reverbHistory.removeAll()
        reverbHistoryWritePos = 0
        reverbHistoryChannels = 0
        reverbTailActive = false
        reverbTailRemaining = 0
        previousPhaseDirection.removeAll()
        transitionBuffer.removeAll()
        transitionRemaining = 0
        transitionLength = 0
        prevFrameRMS = 0
        stableFrameCount = 0
        outputGainDBStorage = 0
        outputGainCurrentLinear = 1
        outputGainStartLinear = 1
        outputGainTargetLinear = 1
        outputGainRampProcessedFrames = 0
        outputGainRampTotalFrames = 0
        outputGainRampPending = false
        perceptualMakeupDBStorage = 0
        perceptualMakeupCurrentLinear = 1
        perceptualMakeupStartLinear = 1
        perceptualMakeupTargetLinear = 1
        perceptualMakeupRampProcessedFrames = 0
        perceptualMakeupRampTotalFrames = 0
        perceptualMakeupRampPending = false
        truePeakLimiterGain = 1
        for index in truePeakHistory.indices { truePeakHistory[index] = 0 }
    }

    // MARK: - 核心处理

    func process(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int
    ) {
        guard isActive, frameCount > 0, channelCount > 0 else { return }

        let totalSamples = frameCount * channelCount

        ensureStateSize(channelCount: channelCount)
        self.frameCount += Int64(frameCount)

        // 修复流水线（顺序很重要）

        if isFadeInProtectionEnabled {
            applyFadeInProtection(data, totalSamples: totalSamples, channelCount: channelCount)
        }
        if isFilterTransitionEnabled {
            applyFilterTransition(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isLoudnessStabilizerEnabled {
            applyLoudnessStabilizer(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isDCBlockerEnabled || isDenoiseEnabled {
            applyDCBlocker(
                data,
                frameCount: frameCount,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
        }
        if isPhaseContinuityEnabled {
            applyPhaseContinuity(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isPopRemovalEnabled {
            applyPopRemoval(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isGapSmoothingEnabled {
            applyGapSmoothing(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isReverbTailGuardEnabled {
            applyReverbTailGuard(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isOverlapRemovalEnabled {
            applyOverlapRemoval(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isDeclipEnabled {
            applyDeclip(data, frameCount: frameCount, channelCount: channelCount)
        }
        if isDenoiseEnabled {
            applyUltrasonicFilter(data, frameCount: frameCount, channelCount: channelCount, sampleRate: sampleRate)
        }
        applyOutputGain(
            data,
            frameCount: frameCount,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
        if isSoftLimiterEnabled {
            applySoftLimiter(
                data,
                frameCount: frameCount,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
        }
        if isDitherEnabled {
            applyDither(data, totalSamples: totalSamples)
        }
        if isReverbTailGuardEnabled {
            updateReverbHistory(data, frameCount: frameCount, channelCount: channelCount)
        }

        // The normal AI output guard only needs gain, DC protection and the
        // limiter. Preserve a PCM tail solely for modules that actually read
        // it instead of copying 64 frames on every hardware callback forever.
        if isGapSmoothingEnabled
            || isOverlapRemovalEnabled
            || isFilterTransitionEnabled
            || isPhaseContinuityEnabled {
            saveTail(data, frameCount: frameCount, channelCount: channelCount)
        }
        stats.totalFramesProcessed += Int64(frameCount)
    }

    private func applyOutputGain(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int
    ) {
        let rampFrames = max(1, Int(Double(sampleRate) * 0.32))
        if outputGainRampPending {
            outputGainStartLinear = outputGainCurrentLinear
            outputGainRampProcessedFrames = 0
            outputGainRampTotalFrames = rampFrames
            outputGainRampPending = false
        }
        if perceptualMakeupRampPending {
            perceptualMakeupStartLinear = perceptualMakeupCurrentLinear
            perceptualMakeupRampProcessedFrames = 0
            perceptualMakeupRampTotalFrames = rampFrames
            perceptualMakeupRampPending = false
        }

        let outputIsRamping =
            outputGainRampProcessedFrames < outputGainRampTotalFrames
        let makeupIsRamping =
            perceptualMakeupRampProcessedFrames < perceptualMakeupRampTotalFrames

        if outputIsRamping || makeupIsRamping {
            for frame in 0..<frameCount {
                let outputLinear = interpolatedGain(
                    start: outputGainStartLinear,
                    target: outputGainTargetLinear,
                    processedFrames: outputGainRampProcessedFrames + frame + 1,
                    totalFrames: outputGainRampTotalFrames
                )
                let makeupLinear = interpolatedGain(
                    start: perceptualMakeupStartLinear,
                    target: perceptualMakeupTargetLinear,
                    processedFrames: perceptualMakeupRampProcessedFrames + frame + 1,
                    totalFrames: perceptualMakeupRampTotalFrames
                )
                let combinedGain = outputLinear * makeupLinear
                let baseIndex = frame * channelCount
                for channel in 0..<channelCount {
                    data[baseIndex + channel] *= combinedGain
                }
            }

            if outputIsRamping {
                outputGainRampProcessedFrames = min(
                    outputGainRampTotalFrames,
                    outputGainRampProcessedFrames + frameCount
                )
                outputGainCurrentLinear = interpolatedGain(
                    start: outputGainStartLinear,
                    target: outputGainTargetLinear,
                    processedFrames: outputGainRampProcessedFrames,
                    totalFrames: outputGainRampTotalFrames
                )
            } else {
                outputGainCurrentLinear = outputGainTargetLinear
            }

            if makeupIsRamping {
                perceptualMakeupRampProcessedFrames = min(
                    perceptualMakeupRampTotalFrames,
                    perceptualMakeupRampProcessedFrames + frameCount
                )
                perceptualMakeupCurrentLinear = interpolatedGain(
                    start: perceptualMakeupStartLinear,
                    target: perceptualMakeupTargetLinear,
                    processedFrames: perceptualMakeupRampProcessedFrames,
                    totalFrames: perceptualMakeupRampTotalFrames
                )
            } else {
                perceptualMakeupCurrentLinear = perceptualMakeupTargetLinear
            }
            return
        }

        outputGainCurrentLinear = outputGainTargetLinear
        perceptualMakeupCurrentLinear = perceptualMakeupTargetLinear
        let combinedGain = outputGainCurrentLinear * perceptualMakeupCurrentLinear
        guard abs(combinedGain - 1) > 0.000_1 else { return }
        let totalSamples = frameCount * channelCount
        for index in 0..<totalSamples {
            data[index] *= combinedGain
        }
    }

    private func interpolatedGain(
        start: Float,
        target: Float,
        processedFrames: Int,
        totalFrames: Int
    ) -> Float {
        guard totalFrames > 0 else { return target }
        let progress = min(1, max(0, Float(processedFrames) / Float(totalFrames)))
        let eased = progress * progress * (3 - 2 * progress)
        return start + (target - start) * eased
    }

    private func setOutputGainTarget(_ value: Float) {
        let safeValue = min(9, max(-18, value.isFinite ? value : 0))
        guard abs(safeValue - outputGainDBStorage) > 0.005 else { return }
        outputGainDBStorage = safeValue
        outputGainTargetLinear = powf(10, safeValue / 20)
        outputGainRampPending = true
    }

    func setPerceptualMakeupTarget(_ value: Float) {
        let remainingPositiveGain = max(0, 9 - max(0, outputGainDBStorage))
        let safeValue = min(
            1.25,
            min(remainingPositiveGain, max(0, value.isFinite ? value : 0))
        )
        guard abs(safeValue - perceptualMakeupDBStorage) > 0.005 else { return }
        perceptualMakeupDBStorage = safeValue
        perceptualMakeupTargetLinear = powf(10, safeValue / 20)
        perceptualMakeupRampPending = true
    }

    // MARK: - 状态管理

    private func ensureStateSize(channelCount: Int) {
        if dcFilterState.count != channelCount {
            dcFilterState = Array(repeating: DCBlockerState(), count: channelCount)
        }
        if ultrasonicFilterState.count != channelCount {
            ultrasonicFilterState = Array(repeating: 0, count: channelCount)
        }
        if truePeakHistory.count != channelCount {
            truePeakHistory = Array(repeating: 0, count: channelCount)
            truePeakLimiterGain = 1
        }
        if lastSamples.count != channelCount {
            lastSamples = Array(repeating: 0, count: channelCount)
        }
    }

    private func saveTail(_ data: UnsafeMutablePointer<Float>, frameCount: Int, channelCount: Int) {
        let samplesToSave = min(tailLength, frameCount) * channelCount
        let startIdx = (frameCount - min(tailLength, frameCount)) * channelCount
        // 复用已有容量，避免实时回调里每个 block 都重新分配数组存储
        previousTail.removeAll(keepingCapacity: true)
        previousTail.append(
            contentsOf: UnsafeBufferPointer(start: data + startIdx, count: samplesToSave)
        )
    }

    // MARK: - 1. 淡入保护

    private func applyFadeInProtection(
        _ data: UnsafeMutablePointer<Float>,
        totalSamples: Int,
        channelCount: Int
    ) {
        guard fadeInActive else { return }
        let totalFrames = totalSamples / channelCount
        for frame in 0..<totalFrames {
            if fadeInCounter >= fadeInSamples {
                fadeInActive = false
                break
            }
            let t = Float(fadeInCounter) / Float(fadeInSamples)
            let gain = t * t * (3.0 - 2.0 * t)
            for ch in 0..<channelCount {
                data[frame * channelCount + ch] *= gain
            }
            fadeInCounter += 1
        }
    }

    // MARK: - 2. DC 偏移消除

    private func applyDCBlocker(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int
    ) {
        // A 5 Hz pole removes offset while remaining effectively transparent
        // across the audible band at every supported source sample rate.
        let R = expf(-2 * Float.pi * 5 / Float(max(sampleRate, 1)))
        for ch in 0..<channelCount {
            var xPrev = dcFilterState[ch].xPrev
            var yPrev = dcFilterState[ch].yPrev
            for frame in 0..<frameCount {
                let idx = frame * channelCount + ch
                let x = data[idx]
                let y = x - xPrev + R * yPrev
                data[idx] = y
                xPrev = x
                yPrev = y
            }
            dcFilterState[ch].xPrev = xPrev
            dcFilterState[ch].yPrev = yPrev
        }
    }

    // MARK: - 3. 爆音检测与修复

    private func applyPopRemoval(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        for ch in 0..<channelCount {
            var prev = lastSamples[ch]
            for frame in 0..<frameCount {
                let idx = frame * channelCount + ch
                let current = data[idx]
                let diff = abs(current - prev)
                if diff > popSensitivity {
                    if frame > 0 && frame < frameCount - 1 {
                        let prevSample = data[(frame - 1) * channelCount + ch]
                        let nextSample = data[(frame + 1) * channelCount + ch]
                        data[idx] = median3(prevSample, current, nextSample)
                    } else if frame == 0 {
                        data[idx] = prev * 0.7 + current * 0.3
                    }
                    stats.popsRemoved += 1
                }
                prev = data[idx]
            }
            lastSamples[ch] = prev
        }
    }

    private func median3(_ a: Float, _ b: Float, _ c: Float) -> Float {
        if a > b {
            if b > c { return b }
            else if a > c { return c }
            else { return a }
        } else {
            if a > c { return a }
            else if b > c { return c }
            else { return b }
        }
    }

    // MARK: - 4. 卡顿平滑

    private func applyGapSmoothing(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        let checkSamples = min(32, frameCount)
        var maxAbs: Float = 0
        for i in 0..<(checkSamples * channelCount) {
            maxAbs = max(maxAbs, abs(data[i]))
        }
        let silenceThreshold: Float = 0.0001
        if maxAbs < silenceThreshold && !previousTail.isEmpty {
            let tailFrames = previousTail.count / channelCount
            let fadeFrames = min(tailFrames, min(32, frameCount))
            for frame in 0..<fadeFrames {
                let fadeOut = Float(fadeFrames - frame) / Float(fadeFrames)
                let tailFrame = tailFrames - fadeFrames + frame
                for ch in 0..<channelCount {
                    let tailIdx = tailFrame * channelCount + ch
                    let dataIdx = frame * channelCount + ch
                    if tailIdx < previousTail.count {
                        data[dataIdx] = previousTail[tailIdx] * fadeOut * 0.5
                    }
                }
            }
            stats.gapsFilled += 1
        }
    }

    // MARK: - 5. 重叠消除

    /// 检测真正的帧重叠（相同数据被发送两次）
    /// 只有当前帧开头与上一帧尾部几乎完全相同时才触发
    private func applyOverlapRemoval(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        guard !previousTail.isEmpty else { return }
        let tailFrames = previousTail.count / channelCount
        let compareFrames = min(16, min(tailFrames, frameCount))
        
        // 计算差异而非相关性 - 真正的重叠意味着数据几乎完全相同
        var totalDiff: Float = 0
        var totalEnergy: Float = 0
        for frame in 0..<compareFrames {
            for ch in 0..<channelCount {
                let tailIdx = (tailFrames - compareFrames + frame) * channelCount + ch
                let dataIdx = frame * channelCount + ch
                if tailIdx < previousTail.count {
                    let a = previousTail[tailIdx]
                    let b = data[dataIdx]
                    totalDiff += abs(a - b)
                    totalEnergy += abs(a) + abs(b)
                }
            }
        }
        
        // 只有当差异极小（< 1%）才认为是真正的重叠
        let normalizedDiff = totalEnergy > 0.001 ? totalDiff / totalEnergy : 1.0
        if normalizedDiff < 0.01 && totalEnergy > 0.01 {
            let fadeFrames = min(16, frameCount)
            for frame in 0..<fadeFrames {
                let fadeIn = Float(frame) / Float(fadeFrames)
                for ch in 0..<channelCount {
                    let idx = frame * channelCount + ch
                    data[idx] *= fadeIn
                }
            }
            stats.overlapsFixed += 1
        }
    }

    // MARK: - 6. 削波修复

    private func applyDeclip(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        for ch in 0..<channelCount {
            var clipStart = -1
            for frame in 0..<frameCount {
                let idx = frame * channelCount + ch
                let sample = data[idx]
                let isClipped = abs(sample) >= clipThreshold
                if isClipped && clipStart < 0 {
                    clipStart = frame
                } else if !isClipped && clipStart >= 0 {
                    repairClippedRegion(data, ch: ch, channelCount: channelCount,
                        start: clipStart, end: frame, totalFrames: frameCount)
                    clipStart = -1
                }
            }
            if clipStart >= 0 {
                repairClippedRegion(data, ch: ch, channelCount: channelCount,
                    start: clipStart, end: frameCount, totalFrames: frameCount)
            }
        }
    }

    private func repairClippedRegion(
        _ data: UnsafeMutablePointer<Float>,
        ch: Int, channelCount: Int,
        start: Int, end: Int, totalFrames: Int
    ) {
        let clipLength = end - start
        guard clipLength > 0 && clipLength < 512 else { return }
        stats.clippedSamplesRepaired += clipLength
        let preIdx = max(0, start - 1)
        let postIdx = min(totalFrames - 1, end)
        let preValue = data[preIdx * channelCount + ch]
        let postValue = data[postIdx * channelCount + ch]
        let preSlope: Float = start >= 2
            ? data[preIdx * channelCount + ch] - data[(preIdx - 1) * channelCount + ch] : 0
        let postSlope: Float = end < totalFrames - 1
            ? data[(postIdx + 1) * channelCount + ch] - data[postIdx * channelCount + ch] : 0
        for i in 0..<clipLength {
            let t = Float(i + 1) / Float(clipLength + 1)
            let interpolated = hermiteInterpolate(preValue, postValue, preSlope, postSlope, t)
            let idx = (start + i) * channelCount + ch
            let originalSign: Float = data[idx] >= 0 ? 1.0 : -1.0
            let repaired = abs(interpolated) * originalSign
            data[idx] = max(-0.98, min(0.98, repaired))
        }
    }

    private func hermiteInterpolate(
        _ y0: Float, _ y1: Float, _ m0: Float, _ m1: Float, _ t: Float
    ) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
             + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1
    }

    // MARK: - 7. 超高频噪声滤除

    private func applyUltrasonicFilter(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int, sampleRate: Int
    ) {
        guard sampleRate > 44100 else { return }
        let cutoff: Float = 20000.0
        let rc = 1.0 / (2.0 * Float.pi * cutoff)
        let dt = 1.0 / Float(sampleRate)
        let alpha = dt / (rc + dt)
        for ch in 0..<channelCount {
            var prev = ultrasonicFilterState[ch]
            for frame in 0..<frameCount {
                let idx = frame * channelCount + ch
                let filtered = prev + alpha * (data[idx] - prev)
                data[idx] = filtered
                prev = filtered
            }
            ultrasonicFilterState[ch] = prev
        }
    }

    // MARK: - 8. 软限幅

    private func applySoftLimiter(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int
    ) {
        let threshold = limiterThreshold
        let totalSamples = frameCount * channelCount
        var samplePeak: Float = 0
        vDSP_maxmgv(data, 1, &samplePeak, vDSP_Length(totalSamples))
        var estimatedTruePeak = samplePeak

        // Four evaluation points per source interval catch inter-sample peaks
        // that a sample-only limiter misses. Catmull-Rom interpolation keeps the
        // detector allocation-free in the realtime callback. A Catmull-Rom
        // sample is bounded by 1.25x the largest control sample at these three
        // evaluation points. Blocks below threshold / 1.25 therefore cannot
        // contain a missed over-threshold inter-sample peak and take the exact
        // fast path without changing limiter output.
        let requiresTruePeakScan = samplePeak > threshold * 0.8
        for channel in 0..<channelCount {
            if requiresTruePeakScan {
                let previous = truePeakHistory[channel]
                for frame in 0..<frameCount {
                    let p0 = frame > 0
                        ? data[(frame - 1) * channelCount + channel]
                        : previous
                    let p1 = data[frame * channelCount + channel]
                    let p2 = frame + 1 < frameCount
                        ? data[(frame + 1) * channelCount + channel]
                        : p1
                    let p3 = frame + 2 < frameCount
                        ? data[(frame + 2) * channelCount + channel]
                        : p2
                    if frame + 1 < frameCount {
                        let controlPeak = max(
                            abs(p0),
                            max(abs(p1), max(abs(p2), abs(p3)))
                        )
                        guard controlPeak > threshold * 0.8 else { continue }
                        let quarterPeak = abs(catmullRom(p0, p1, p2, p3, 0.25))
                        let halfPeak = abs(catmullRom(p0, p1, p2, p3, 0.5))
                        let threeQuarterPeak = abs(catmullRom(p0, p1, p2, p3, 0.75))
                        estimatedTruePeak = max(
                            estimatedTruePeak,
                            max(quarterPeak, max(halfPeak, threeQuarterPeak))
                        )
                    }
                }
            }
            truePeakHistory[channel] = data[(frameCount - 1) * channelCount + channel]
        }

        let requestedGain = estimatedTruePeak > threshold
            ? threshold / max(estimatedTruePeak, 0.000_001)
            : 1
        let blockStartGain = truePeakLimiterGain
        let targetGain = Double(requestedGain)
        if targetGain < 1 || blockStartGain < 1 {
            let isAttacking = targetGain < blockStartGain
            let attackFrames = min(32, frameCount)
            // Advance the 120 ms release at the sample clock, not once per
            // callback. The retained gain is the last gain actually rendered.
            let releaseDecay = isAttacking ? 0 : exp(-1 / (Double(max(sampleRate, 1)) * 0.12))
            var gain = blockStartGain
            for frame in 0..<frameCount {
                if isAttacking {
                    if frame < attackFrames {
                        let progress = Double(frame + 1) / Double(attackFrames)
                        let eased = progress * progress * (3 - 2 * progress)
                        gain = blockStartGain + (targetGain - blockStartGain) * eased
                    } else {
                        gain = targetGain
                    }
                } else {
                    gain = targetGain + (gain - targetGain) * releaseDecay
                }
                let linearGain = Float(gain)
                let baseIndex = frame * channelCount
                for channel in 0..<channelCount {
                    data[baseIndex + channel] *= linearGain
                }
            }
            // Take the unity fast path only once Float32 output is already unity.
            truePeakLimiterGain = Float(gain) == 1 ? 1 : gain
        }

        // Begin a narrow soft knee just below the requested ceiling. The old
        // curve could still approach 0 dBFS, so its "ceiling" was not a real
        // output ceiling after positive EQ or harmonic enhancement.
        let kneeStart = threshold * 0.95
        let kneeWidth = max(0.000_001, threshold - kneeStart)
        var activated = requestedGain < 0.999_9
        if samplePeak > kneeStart || truePeakLimiterGain < 0.999_9 {
            for i in 0..<totalSamples {
                let sample = data[i]
                let absSample = abs(sample)
                if absSample > kneeStart {
                    let sign: Float = sample >= 0 ? 1.0 : -1.0
                    let excess = (absSample - kneeStart) / kneeWidth
                    let compressed = kneeStart + kneeWidth * tanhf(excess)
                    data[i] = sign * compressed
                    activated = true
                }
            }
        }
        if activated { stats.limiterActivations += 1 }
    }

    @inline(__always)
    private func catmullRom(
        _ p0: Float,
        _ p1: Float,
        _ p2: Float,
        _ p3: Float,
        _ t: Float
    ) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            2 * p1
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }

    // MARK: - 9. 抖动

    private func applyDither(
        _ data: UnsafeMutablePointer<Float>, totalSamples: Int
    ) {
        let ditherAmplitude: Float = 2.0 / 32768.0
        for i in 0..<totalSamples {
            ditherState = ditherState * 1664525 + 1013904223
            let r1 = ditherState / Float(UInt32.max) - 0.5
            ditherState = ditherState * 1664525 + 1013904223
            let r2 = ditherState / Float(UInt32.max) - 0.5
            data[i] += (r1 + r2) * ditherAmplitude
        }
    }

    // MARK: - 10. 滤镜重建过渡

    private func applyFilterTransition(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int
    ) {
        let totalSamples = frameCount * channelCount

        // 正在进行过渡交叉淡化
        if transitionRemaining > 0 && !transitionBuffer.isEmpty {
            let samplesToFade = min(transitionRemaining, frameCount)
            let bufferFrames = transitionBuffer.count / max(channelCount, 1)
            for frame in 0..<samplesToFade {
                let t = Float(transitionLength - transitionRemaining + frame) / Float(transitionLength)
                let newWeight = t * t * (3.0 - 2.0 * t)
                let oldWeight = 1.0 - newWeight
                for ch in 0..<channelCount {
                    let idx = frame * channelCount + ch
                    let bufFrame = bufferFrames - transitionRemaining + frame
                    if bufFrame >= 0 && bufFrame < bufferFrames {
                        let bufIdx = bufFrame * channelCount + ch
                        if bufIdx < transitionBuffer.count {
                            data[idx] = data[idx] * newWeight + transitionBuffer[bufIdx] * oldWeight
                        }
                    }
                }
            }
            transitionRemaining -= samplesToFade
            if transitionRemaining <= 0 { transitionBuffer.removeAll() }
            return
        }

        // 计算当前帧 RMS
        var sumSq: Float = 0
        let checkSamples = min(64 * channelCount, totalSamples)
        for i in 0..<checkSamples { sumSq += data[i] * data[i] }
        let currentRMS = sqrtf(sumSq / Float(max(checkSamples, 1)))

        // 检测 RMS 突变 - 只有非常剧烈的变化才触发（>12dB = 4倍）
        // 并且需要连续稳定至少 10 帧后才检测，避免正常音乐动态被误判
        if prevFrameRMS > 0.01 && currentRMS > 0.01 && stableFrameCount > 10 {
            let rmsRatio = currentRMS / prevFrameRMS
            // 只有 RMS 变化超过 4 倍（12dB）才认为是滤镜重建
            if rmsRatio > 4.0 || rmsRatio < 0.25 {
                if !previousTail.isEmpty && previousTail.count >= channelCount {
                    var maxJump: Float = 0
                    let tailFrames = previousTail.count / channelCount
                    for ch in 0..<channelCount {
                        let lastTailIdx = (tailFrames - 1) * channelCount + ch
                        if lastTailIdx < previousTail.count {
                            maxJump = max(maxJump, abs(data[ch] - previousTail[lastTailIdx]))
                        }
                    }
                    // 波形跳变阈值也提高到 0.3
                    if maxJump > 0.3 {
                        let jumpFactor = min(maxJump / 0.5, 1.0)
                        let fadeSamples = Int(Float(filterTransitionMaxSamples) * (0.3 + 0.7 * jumpFactor))
                        let tailFrameCount = previousTail.count / channelCount
                        // 只能交叉淡化真实保存下来的尾帧。旧实现最多申请
                        // 1024 帧、却只有 64 帧历史，其余位置为零，等同于
                        // 人为插入一次约 20ms 的音量凹陷。
                        let actualFade = min(fadeSamples, frameCount, tailFrameCount)
                        guard actualFade > 0 else { return }
                        transitionBuffer.removeAll(keepingCapacity: true)
                        transitionBuffer.append(
                            contentsOf: previousTail.suffix(actualFade * channelCount)
                        )
                        transitionLength = actualFade
                        transitionRemaining = actualFade
                        stableFrameCount = 0
                        stats.filterTransitions += 1

                        let samplesToFade = min(transitionRemaining, frameCount)
                        for frame in 0..<samplesToFade {
                            let t = Float(frame) / Float(transitionLength)
                            let newWeight = t * t * (3.0 - 2.0 * t)
                            let oldWeight = 1.0 - newWeight
                            for ch in 0..<channelCount {
                                let idx = frame * channelCount + ch
                                let bufIdx = frame * channelCount + ch
                                if bufIdx < transitionBuffer.count {
                                    data[idx] = data[idx] * newWeight + transitionBuffer[bufIdx] * oldWeight
                                }
                            }
                        }
                        transitionRemaining -= samplesToFade
                        if transitionRemaining <= 0 { transitionBuffer.removeAll() }
                    }
                }
            }
        }
        prevFrameRMS = currentRMS
        stableFrameCount += 1
    }

    // MARK: - 11. 响度突变抑制

    private func applyLoudnessStabilizer(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int
    ) {
        let totalSamples = frameCount * channelCount
        var sumSq: Float = 0
        for i in 0..<totalSamples { sumSq += data[i] * data[i] }
        let currentRMS = sqrtf(sumSq / Float(max(totalSamples, 1)))

        if rmsEnvelope < 0.0001 {
            rmsEnvelope = currentRMS
        } else {
            rmsEnvelope = rmsEnvelope * (1.0 - loudnessSmoothing) + currentRMS * loudnessSmoothing
        }

        if loudnessSmoothRemaining > 0 {
            let totalSmoothFrames = 2048
            let progress = Float(totalSmoothFrames - loudnessSmoothRemaining) / Float(totalSmoothFrames)
            let t = progress * progress * (3.0 - 2.0 * progress)
            let currentGain = loudnessSmoothStartGain + (1.0 - loudnessSmoothStartGain) * t
            for i in 0..<totalSamples { data[i] *= currentGain }
            loudnessSmoothRemaining -= frameCount
            if loudnessSmoothRemaining <= 0 {
                loudnessGain = 1.0
                loudnessSmoothRemaining = 0
            }
        } else if previousRMS > 0.001 && currentRMS > 0.001 {
            let rmsDB = 20.0 * log10f(currentRMS / previousRMS)
            if abs(rmsDB) > loudnessJumpThreshold {
                let compensationGain = previousRMS / currentRMS
                let clampedGain = max(0.25, min(4.0, compensationGain))
                for i in 0..<totalSamples { data[i] *= clampedGain }
                loudnessSmoothStartGain = clampedGain
                loudnessSmoothRemaining = 2048
                loudnessGain = clampedGain
                stats.loudnessJumpsSmoothed += 1
            }
        }
        previousRMS = currentRMS
    }

    // MARK: - 12. 混响尾音保护

    private func applyReverbTailGuard(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int
    ) {
        if reverbTailActive && reverbTailRemaining > 0 && !reverbHistory.isEmpty {
            let historyFrames = reverbHistory.count / max(reverbHistoryChannels, 1)
            guard reverbHistoryChannels == channelCount else {
                reverbTailActive = false
                return
            }
            let framesToFill = min(reverbTailRemaining, frameCount)
            let tailTotalFrames = min(2048, historyFrames)
            for frame in 0..<framesToFill {
                let progress = Float(tailTotalFrames - reverbTailRemaining + frame) / Float(tailTotalFrames)
                let decay = expf(-3.0 * progress)
                for ch in 0..<channelCount {
                    let histFrame = (reverbHistoryWritePos - reverbTailRemaining + frame + historyFrames) % historyFrames
                    let histIdx = histFrame * channelCount + ch
                    if histIdx >= 0 && histIdx < reverbHistory.count {
                        let dataIdx = frame * channelCount + ch
                        data[dataIdx] += reverbHistory[histIdx] * decay * 0.5
                    }
                }
            }
            reverbTailRemaining -= framesToFill
            if reverbTailRemaining <= 0 { reverbTailActive = false }
            stats.reverbTailsFilled += 1
            return
        }

        guard !reverbHistory.isEmpty && reverbHistoryChannels == channelCount else { return }
        let totalSamples = frameCount * channelCount
        let historyFrames = reverbHistory.count / channelCount

        let checkSamples = min(32 * channelCount, totalSamples)
        var currentEnergy: Float = 0
        for i in 0..<checkSamples { currentEnergy += data[i] * data[i] }
        currentEnergy = sqrtf(currentEnergy / Float(max(checkSamples, 1)))

        let histCheckFrames = min(32, historyFrames)
        var histEnergy: Float = 0
        for frame in 0..<histCheckFrames {
            let histFrame = (reverbHistoryWritePos - histCheckFrames + frame + historyFrames) % historyFrames
            for ch in 0..<channelCount {
                let idx = histFrame * channelCount + ch
                if idx < reverbHistory.count { histEnergy += reverbHistory[idx] * reverbHistory[idx] }
            }
        }
        histEnergy = sqrtf(histEnergy / Float(max(histCheckFrames * channelCount, 1)))

        // 只有当能量突然下降到 5% 以下才认为是混响断裂
        // 0.3 (30%) 太敏感，正常音乐动态会误触发
        if histEnergy > 0.05 && currentEnergy < histEnergy * 0.05 {
            reverbTailActive = true
            reverbTailRemaining = min(2048, historyFrames)
        }
    }

    private func updateReverbHistory(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int
    ) {
        let targetSize = reverbTailHistoryLength * channelCount
        if reverbHistory.count != targetSize || reverbHistoryChannels != channelCount {
            reverbHistory = Array(repeating: 0, count: targetSize)
            reverbHistoryWritePos = 0
            reverbHistoryChannels = channelCount
        }
        let historyFrames = reverbTailHistoryLength
        for frame in 0..<frameCount {
            let writeFrame = (reverbHistoryWritePos + frame) % historyFrames
            for ch in 0..<channelCount {
                let srcIdx = frame * channelCount + ch
                let dstIdx = writeFrame * channelCount + ch
                if dstIdx < reverbHistory.count { reverbHistory[dstIdx] = data[srcIdx] }
            }
        }
        reverbHistoryWritePos = (reverbHistoryWritePos + frameCount) % historyFrames
    }

    // MARK: - 13. 相位连续性修复

    private func applyPhaseContinuity(
        _ data: UnsafeMutablePointer<Float>,
        frameCount: Int, channelCount: Int
    ) {
        guard frameCount >= 4 else { return }

        phaseDirectionScratch.removeAll(keepingCapacity: true)
        for ch in 0..<channelCount {
            var slope: Float = 0
            for frame in 1..<min(4, frameCount) {
                slope += data[frame * channelCount + ch] - data[(frame - 1) * channelCount + ch]
            }
            phaseDirectionScratch.append(slope)
        }
        let currentDirection = phaseDirectionScratch

        if !previousPhaseDirection.isEmpty && previousPhaseDirection.count == channelCount {
            var flippedChannels = 0
            var totalChecked = 0
            for ch in 0..<channelCount {
                let prev = previousPhaseDirection[ch]
                let curr = currentDirection[ch]
                // 提高斜率阈值到 0.1，避免低能量信号的噪声干扰
                if abs(prev) > 0.1 && abs(curr) > 0.1 {
                    totalChecked += 1
                    if prev * curr < 0 { flippedChannels += 1 }
                }
            }

            if totalChecked > 0 && flippedChannels == totalChecked {
                if !previousTail.isEmpty && previousTail.count >= channelCount {
                    let tailFrames = previousTail.count / channelCount
                    var amplitudeMatch = true
                    for ch in 0..<channelCount {
                        let lastTailIdx = (tailFrames - 1) * channelCount + ch
                        if lastTailIdx < previousTail.count {
                            let prevAmp = abs(previousTail[lastTailIdx])
                            let currAmp = abs(data[ch])
                            if prevAmp > 0.01 && abs(currAmp - prevAmp) / prevAmp > 0.5 {
                                amplitudeMatch = false
                                break
                            }
                        }
                    }
                    if amplitudeMatch {
                        let fadeFrames = min(64, frameCount)
                        let tailFrameCount = previousTail.count / channelCount
                        for frame in 0..<fadeFrames {
                            let t = Float(frame) / Float(fadeFrames)
                            let newWeight = t * t * (3.0 - 2.0 * t)
                            let oldWeight = 1.0 - newWeight
                            for ch in 0..<channelCount {
                                let idx = frame * channelCount + ch
                                let lastIdx = (tailFrameCount - 1) * channelCount + ch
                                if lastIdx < previousTail.count {
                                    data[idx] = data[idx] * newWeight + previousTail[lastIdx] * oldWeight
                                }
                            }
                        }
                        stats.phaseFlipsFixed += 1
                    }
                }
            }
        }
        // 两块存储交替复用，稳态下不触发分配
        swap(&previousPhaseDirection, &phaseDirectionScratch)
    }
}
