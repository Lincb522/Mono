// AudioFilterGraph.swift
// FFmpegSwiftSDK
//
// 封装 FFmpeg avfilter 图，提供完整的音频效果处理能力。
// 支持 50+ 种音频滤镜，涵盖音量、动态、频率、空间、时间、特效等。
//
// 滤镜链: abuffer → [各种滤镜] → aformat → abuffersink

import Foundation
import CFFmpeg

/// FFmpeg avfilter 音频滤镜图，支持实时参数调整。
///
/// 内部维护一个 AVFilterGraph，按需重建滤镜链。
/// Control writes and prepared graph exchange use a short lock. Active DSP
/// state belongs only to the audio consumer; a busy exchange never bypasses it.
final class AudioFilterGraph: @unchecked Sendable {

    // MARK: - 属性

    private let lock = NSLock()
    private let rebuildQueue = DispatchQueue(
        label: "FFmpegSwiftSDK.AudioFilterGraph.rebuild",
        qos: .userInitiated
    )
    private var rebuildScheduled = false

    // ==================== 基础音量控制 ====================

    /// 音量增益（dB），0 = 不变
    private(set) var volumeDB: Float = 0.0
    
    // ==================== 动态处理 ====================
    
    /// 响度标准化（EBU R128）
    private(set) var loudnormEnabled: Bool = false
    private(set) var loudnormTarget: Float = -14.0  // LUFS
    private(set) var loudnormLRA: Float = 7.0      // LRA（响度范围），降低到 7 更保守
    private(set) var loudnormTP: Float = -1.0       // True Peak
    
    /// 动态压缩（夜间模式）
    private(set) var compressorEnabled: Bool = false
    private(set) var compressorThreshold: Float = -20.0  // dB
    private(set) var compressorRatio: Float = 4.0        // 压缩比
    private(set) var compressorAttack: Float = 5.0       // ms
    private(set) var compressorRelease: Float = 50.0     // ms
    private(set) var compressorMakeup: Float = 2.0       // dB
    
    /// 限幅器
    private(set) var limiterEnabled: Bool = false
    private(set) var limiterLimit: Float = -1.0  // dBFS
    
    /// 噪声门
    private(set) var gateEnabled: Bool = false
    private(set) var gateThreshold: Float = -40.0  // dB
    
    /// 自动增益（动态标准化）
    private(set) var autoGainEnabled: Bool = false
    
    // ==================== 速度与音调 ====================
    
    /// 播放速度倍率，1.0 = 原速
    private(set) var tempo: Float = 1.0
    
    /// 变调（半音数），范围 [-12, +12]
    private(set) var pitchSemitones: Float = 0.0
    
    // ==================== 均衡器与频率 ====================
    
    /// 低音增益（dB）
    private(set) var bassGain: Float = 0.0
    
    /// 高音增益（dB）
    private(set) var trebleGain: Float = 0.0
    
    /// 超低音增强
    private(set) var subboostEnabled: Bool = false
    private(set) var subboostGain: Float = 6.0      // dB
    private(set) var subboostCutoff: Float = 100.0  // Hz
    
    /// 带通滤波
    private(set) var bandpassEnabled: Bool = false
    private(set) var bandpassFrequency: Float = 1000.0  // Hz
    private(set) var bandpassWidth: Float = 2000.0      // Hz
    
    /// 带阻滤波
    private(set) var bandrejectEnabled: Bool = false
    private(set) var bandrejectFrequency: Float = 1000.0  // Hz
    private(set) var bandrejectWidth: Float = 200.0       // Hz
    
    // ==================== 空间效果 ====================
    
    /// 环绕增强（0~1）
    private(set) var surroundLevel: Float = 0.0
    
    /// 混响强度（0~1）
    private(set) var reverbLevel: Float = 0.0
    
    /// 立体声宽度（0~2），1.0 = 原始
    private(set) var stereoWidth: Float = 1.0
    
    /// 声道平衡（-1 = 全左，0 = 居中，+1 = 全右）
    private(set) var channelBalance: Float = 0.0
    
    /// 单声道模式
    private(set) var monoEnabled: Bool = false
    
    /// 声道交换
    private(set) var channelSwapEnabled: Bool = false
    
    // ==================== 时间效果 ====================
    
    /// 淡入时长（秒）
    private(set) var fadeInDuration: Float = 0.0
    
    /// 淡出时长（秒）
    private(set) var fadeOutDuration: Float = 0.0
    private(set) var fadeOutStartTime: Float = 0.0
    
    /// 延迟（毫秒）
    private(set) var delayMs: Float = 0.0
    
    // ==================== 特殊效果 ====================
    
    /// 人声消除强度（0~1）
    private(set) var vocalRemovalLevel: Float = 0.0
    
    /// 合唱效果
    private(set) var chorusEnabled: Bool = false
    private(set) var chorusDepth: Float = 0.5
    
    /// 镶边效果
    private(set) var flangerEnabled: Bool = false
    private(set) var flangerDepth: Float = 0.5
    
    /// 颤音效果（音量）
    private(set) var tremoloEnabled: Bool = false
    private(set) var tremoloFrequency: Float = 5.0  // Hz
    private(set) var tremoloDepth: Float = 0.5
    
    /// 颤抖效果（音调）
    private(set) var vibratoEnabled: Bool = false
    private(set) var vibratoFrequency: Float = 5.0  // Hz
    private(set) var vibratoDepth: Float = 0.5
    
    /// 失真效果（Lo-Fi）
    private(set) var crusherEnabled: Bool = false
    private(set) var crusherBits: Float = 8.0       // 位深
    private(set) var crusherSamples: Float = 4.0    // 采样率降低因子
    
    /// 电话效果
    private(set) var telephoneEnabled: Bool = false
    
    /// 水下效果
    private(set) var underwaterEnabled: Bool = false
    
    /// 收音机效果
    private(set) var radioEnabled: Bool = false
    
    // ==================== 新增：音频修复滤镜 ====================
    
    /// FFT 降噪（afftdn）
    private(set) var fftDenoiseEnabled: Bool = false
    private(set) var fftDenoiseAmount: Float = 10.0  // 降噪量（dB）
    
    /// 去除脉冲噪声（adeclick）
    private(set) var declickEnabled: Bool = false
    
    /// 去除削波失真（adeclip）
    private(set) var declipEnabled: Bool = false
    
    // ==================== 新增：动态处理滤镜 ====================
    
    /// 动态音频标准化（dynaudnorm）- 比 loudnorm 更适合实时
    private(set) var dynaudnormEnabled: Bool = false
    private(set) var dynaudnormFrameLen: Int = 500      // 帧长度（ms）
    private(set) var dynaudnormGaussSize: Int = 31      // 高斯窗口大小
    private(set) var dynaudnormPeak: Float = 0.95       // 目标峰值
    
    /// 语音标准化（speechnorm）
    private(set) var speechnormEnabled: Bool = false
    
    /// 压缩/扩展（compand）- 更灵活的动态控制
    private(set) var compandEnabled: Bool = false
    
    // ==================== 新增：空间音效滤镜 ====================
    
    /// Bauer 立体声转双耳（bs2b）- 改善耳机听感
    private(set) var bs2bEnabled: Bool = false
    private(set) var bs2bFcut: Int = 700       // 截止频率
    private(set) var bs2bFeed: Int = 50        // 馈送量（0.1dB 单位）
    
    /// 耳机交叉馈送（crossfeed）
    private(set) var crossfeedEnabled: Bool = false
    private(set) var crossfeedStrength: Float = 0.3
    
    /// Haas 效果（haas）- 增加空间感
    private(set) var haasEnabled: Bool = false
    private(set) var haasDelay: Float = 20.0   // 延迟（ms）
    
    /// 虚拟低音（virtualbass）
    private(set) var virtualbassEnabled: Bool = false
    private(set) var virtualbassCutoff: Float = 250.0
    private(set) var virtualbassStrength: Float = 3.0
    
    // ==================== 新增：音色处理滤镜 ====================
    
    /// 激励器（aexciter）- 增加高频泛音
    private(set) var exciterEnabled: Bool = false
    private(set) var exciterAmount: Float = 3.0   // 激励量（dB）
    private(set) var exciterFreq: Float = 7500.0  // 起始频率
    
    /// 软削波（asoftclip）- 温暖的失真
    private(set) var softclipEnabled: Bool = false
    private(set) var softclipType: Int = 0        // 0=tanh, 1=atan, 2=cubic, 3=exp, 4=alg, 5=quintic, 6=sin, 7=erf
    
    /// 对话增强（dialoguenhance）
    private(set) var dialogueEnhanceEnabled: Bool = false
    private(set) var dialogueEnhanceOriginal: Float = 1.0
    private(set) var dialogueEnhanceEnhance: Float = 1.0
    
    // ==================== 内部状态 ====================
    
    private var processedSamples: Int64 = 0
    private var sampleRate: Int = 0
    private var channelCount: Int = 0
    private var filterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private var bufferSrcCtx: UnsafeMutablePointer<AVFilterContext>?
    private var bufferSinkCtx: UnsafeMutablePointer<AVFilterContext>?
    private var activeGraphSampleRate: Int = 0
    private var activeGraphChannelCount: Int = 0
    private var pendingFilterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private var pendingBufferSrcCtx: UnsafeMutablePointer<AVFilterContext>?
    private var pendingBufferSinkCtx: UnsafeMutablePointer<AVFilterContext>?
    /// Consumer-owned until transferred to retirementMailbox at a block boundary.
    private var retiredFilterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private struct PreparedGraph {
        let graph: UnsafeMutablePointer<AVFilterGraph>
        let source: UnsafeMutablePointer<AVFilterContext>
        let sink: UnsafeMutablePointer<AVFilterContext>
        let sampleRate: Int
        let channelCount: Int
        let hasEffects: Bool
    }

    // These mailbox fields are protected by lock; only the rebuild queue frees
    // replaced prepared graphs and pointers handed back by the audio consumer.
    private var preparedGraph: PreparedGraph?
    private var retirementMailbox: UnsafeMutablePointer<AVFilterGraph>?
    private var publishedRenderSampleRate = 0
    private var publishedRenderChannelCount = 0
    private var publishedRenderActive = false
    private var sampleCountResetPending = false

    // Active/pending graphs, transition counters and AVFrames are consumer-owned.
    private var activeGraphHasEffects = false
    private var pendingGraphSampleRate = 0
    private var pendingGraphChannelCount = 0
    private var pendingGraphHasEffects = false
    private var needsRebuild: Bool = true
    
    // 首次建图仍由干声平滑接入。参数变化时替换图在后台独立构建，
    // 交接采用“旧湿声 → 干声 → 新湿声”，避免一个回调并跑两套图。
    private var effectFadeOutFramesRemaining: Int = 0
    private var effectFadeInFramesRemaining: Int = 0
    private var rebuildWaitingForFadeOut: Bool = false
    private let effectTransitionDurationFrames: Int = 1_024
    private var transitionInputScratch: UnsafeMutablePointer<Float>? =
        .allocate(capacity: 16_384)
    private var transitionInputCapacity: Int = 16_384
    
    private var cachedInputFrame: UnsafeMutablePointer<AVFrame>?
    private var cachedOutputFrame: UnsafeMutablePointer<AVFrame>?
    // 输入帧 PCM 缓冲池：实时回调里复用，稳态零 malloc/free
    private var inputFramePool: OpaquePointer?
    private var inputFramePoolBufferSize: Int = 0
    // 输出兜底缓冲（滤镜改变样本数时使用），跨回调复用，由本类持有并释放
    private var outputScratch: UnsafeMutablePointer<Float>?
    private var outputScratchCapacity: Int = 0

    /// 是否有任何滤镜处于激活状态
    var isActive: Bool {
        guard lock.try() else { return true }
        defer { lock.unlock() }
        return checkAnyFilterActive() || needsRebuild || rebuildScheduled
            || preparedGraph != nil || publishedRenderActive
    }

    private func checkAnyFilterActive() -> Bool {
        return volumeDB != 0.0 ||
               loudnormEnabled ||
               compressorEnabled ||
               limiterEnabled ||
               gateEnabled ||
               autoGainEnabled ||
               tempo != 1.0 ||
               pitchSemitones != 0.0 ||
               bassGain != 0.0 ||
               trebleGain != 0.0 ||
               subboostEnabled ||
               bandpassEnabled ||
               bandrejectEnabled ||
               surroundLevel > 0.0 ||
               reverbLevel > 0.0 ||
               stereoWidth != 1.0 ||
               channelBalance != 0.0 ||
               monoEnabled ||
               channelSwapEnabled ||
               fadeInDuration > 0.0 ||
               fadeOutDuration > 0.0 ||
               delayMs > 0.0 ||
               vocalRemovalLevel > 0.0 ||
               chorusEnabled ||
               flangerEnabled ||
               tremoloEnabled ||
               vibratoEnabled ||
               crusherEnabled ||
               telephoneEnabled ||
               underwaterEnabled ||
               radioEnabled ||
               fftDenoiseEnabled ||
               declickEnabled ||
               declipEnabled ||
               dynaudnormEnabled ||
               speechnormEnabled ||
               compandEnabled ||
               bs2bEnabled ||
               crossfeedEnabled ||
               haasEnabled ||
               virtualbassEnabled ||
               exciterEnabled ||
               softclipEnabled ||
               dialogueEnhanceEnabled
    }

    /// Applies the parameters used by Mono Audio Agent under one lock so the
    /// render thread never observes a partially committed tuning plan.
    func applyMonoTuning(
        _ configuration: MonoEffectTuningConfiguration,
        bassGain requestedBassGain: Float? = nil,
        trebleGain requestedTrebleGain: Float? = nil,
        surroundLevel requestedSurroundLevel: Float? = nil,
        reverbLevel requestedReverbLevel: Float? = nil,
        stereoWidth requestedStereoWidth: Float? = nil
    ) {
        // 入参换算全部在锁外完成，写侧临界区只留纯赋值和比较，
        // 把与实时线程 process() 的碰撞窗口压到微秒级。
        let nextBassGain = requestedBassGain.map { min(12, max(-12, $0)) }
        let nextTrebleGain = requestedTrebleGain.map { min(12, max(-12, $0)) }
        let nextSurroundLevel = requestedSurroundLevel.map { min(1, max(0, $0)) }
        let nextReverbLevel = requestedReverbLevel.map { min(1, max(0, $0)) }
        let nextStereoWidth = requestedStereoWidth.map { min(2, max(0, $0)) }
        let nextLoudnormTarget = min(-5, max(-30, configuration.targetLUFS))
        let nextLoudnormLRA = min(20, max(1, configuration.targetLRA))
        let nextLoudnormTP = min(-0.05, max(-6, configuration.truePeakCeilingDB))
        let nextCompressorThreshold = min(0, max(-60, configuration.compressorThresholdDB))
        let nextCompressorRatio = min(20, max(1, configuration.compressorRatio))
        let nextCompressorAttack = min(2_000, max(0.1, configuration.compressorAttackMS))
        let nextCompressorRelease = min(5_000, max(10, configuration.compressorReleaseMS))
        let nextCompressorMakeup = min(12, max(-12, configuration.compressorMakeupDB))
        let nextSubboostGain = min(12, max(0, configuration.subboostGainDB))
        let nextSubboostCutoff = min(250, max(35, configuration.subboostCutoffHz))
        let nextBS2BCutoff = min(2_000, max(300, configuration.bs2bCutoffHz))
        let nextBS2BFeed = min(150, max(0, configuration.bs2bFeed))
        let nextCrossfeedStrength = min(1, max(0, configuration.crossfeedStrength))
        let nextHaasDelay = min(40, max(0, configuration.haasDelayMS))
        let nextVirtualBassCutoff = min(500, max(60, configuration.virtualBassCutoffHz))
        let nextVirtualBassStrength = min(10, max(0, configuration.virtualBassStrength))
        let nextExciterAmount = min(10, max(0, configuration.exciterAmountDB))
        let nextExciterFrequency = min(16_000, max(2_000, configuration.exciterFrequencyHz))
        let nextSoftclipType = min(7, max(0, configuration.softclipType))
        @inline(__always)
        func materiallyChanged(_ lhs: Float, _ rhs: Float) -> Bool {
            abs(lhs - rhs) > 0.0005
        }
        @inline(__always)
        func materiallyChanged(_ lhs: Int, _ rhs: Int) -> Bool {
            lhs != rhs
        }

        lock.lock()
        let toneOrSpatialChanged =
            (nextBassGain.map { materiallyChanged($0, bassGain) } ?? false)
            || (nextTrebleGain.map { materiallyChanged($0, trebleGain) } ?? false)
            || (nextSurroundLevel.map { materiallyChanged($0, surroundLevel) } ?? false)
            || (nextReverbLevel.map { materiallyChanged($0, reverbLevel) } ?? false)
            || (nextStereoWidth.map { materiallyChanged($0, stereoWidth) } ?? false)
        let loudnessChanged =
            configuration.loudnessNormalizationEnabled != loudnormEnabled
            || (configuration.loudnessNormalizationEnabled
                && (materiallyChanged(nextLoudnormTarget, loudnormTarget)
                    || materiallyChanged(nextLoudnormLRA, loudnormLRA)
                    || materiallyChanged(nextLoudnormTP, loudnormTP)))
        let compressorChanged =
            configuration.compressorEnabled != compressorEnabled
            || (configuration.compressorEnabled
                && (materiallyChanged(nextCompressorThreshold, compressorThreshold)
                    || materiallyChanged(nextCompressorRatio, compressorRatio)
                    || materiallyChanged(nextCompressorAttack, compressorAttack)
                    || materiallyChanged(nextCompressorRelease, compressorRelease)
                    || materiallyChanged(nextCompressorMakeup, compressorMakeup)))
        let bassEnhancementChanged =
            configuration.subboostEnabled != subboostEnabled
            || (configuration.subboostEnabled
                && (materiallyChanged(nextSubboostGain, subboostGain)
                    || materiallyChanged(nextSubboostCutoff, subboostCutoff)))
            || configuration.virtualBassEnabled != virtualbassEnabled
            || (configuration.virtualBassEnabled
                && (materiallyChanged(nextVirtualBassCutoff, virtualbassCutoff)
                    || materiallyChanged(nextVirtualBassStrength, virtualbassStrength)))
        let headphoneSpatialChanged =
            configuration.bs2bEnabled != bs2bEnabled
            || (configuration.bs2bEnabled
                && (materiallyChanged(nextBS2BCutoff, bs2bFcut)
                    || materiallyChanged(nextBS2BFeed, bs2bFeed)))
            || configuration.crossfeedEnabled != crossfeedEnabled
            || (configuration.crossfeedEnabled
                && materiallyChanged(nextCrossfeedStrength, crossfeedStrength))
            || configuration.haasEnabled != haasEnabled
            || (configuration.haasEnabled && materiallyChanged(nextHaasDelay, haasDelay))
        let colorationChanged =
            configuration.exciterEnabled != exciterEnabled
            || (configuration.exciterEnabled
                && (materiallyChanged(nextExciterAmount, exciterAmount)
                    || materiallyChanged(nextExciterFrequency, exciterFreq)))
            || configuration.softclipEnabled != softclipEnabled
            || (configuration.softclipEnabled && nextSoftclipType != softclipType)
        let graphChanged = toneOrSpatialChanged
            || loudnessChanged
            || compressorChanged
            || bassEnhancementChanged
            || headphoneSpatialChanged
            || colorationChanged

        if let nextBassGain { bassGain = nextBassGain }
        if let nextTrebleGain { trebleGain = nextTrebleGain }
        if let nextSurroundLevel { surroundLevel = nextSurroundLevel }
        if let nextReverbLevel { reverbLevel = nextReverbLevel }
        if let nextStereoWidth { stereoWidth = nextStereoWidth }
        loudnormEnabled = configuration.loudnessNormalizationEnabled
        loudnormTarget = nextLoudnormTarget
        loudnormLRA = nextLoudnormLRA
        loudnormTP = nextLoudnormTP
        compressorEnabled = configuration.compressorEnabled
        compressorThreshold = nextCompressorThreshold
        compressorRatio = nextCompressorRatio
        compressorAttack = nextCompressorAttack
        compressorRelease = nextCompressorRelease
        compressorMakeup = nextCompressorMakeup
        subboostEnabled = configuration.subboostEnabled
        subboostGain = nextSubboostGain
        subboostCutoff = nextSubboostCutoff
        bs2bEnabled = configuration.bs2bEnabled
        bs2bFcut = nextBS2BCutoff
        bs2bFeed = nextBS2BFeed
        crossfeedEnabled = configuration.crossfeedEnabled
        crossfeedStrength = nextCrossfeedStrength
        haasEnabled = configuration.haasEnabled
        haasDelay = nextHaasDelay
        virtualbassEnabled = configuration.virtualBassEnabled
        virtualbassCutoff = nextVirtualBassCutoff
        virtualbassStrength = nextVirtualBassStrength
        exciterEnabled = configuration.exciterEnabled
        exciterAmount = nextExciterAmount
        exciterFreq = nextExciterFrequency
        softclipEnabled = configuration.softclipEnabled
        softclipType = nextSoftclipType
        if graphChanged {
            needsRebuild = true
            // This API is called from the control side. Queue graph work here
            // so the next hardware callback does not allocate a Dispatch work
            // item before it can render audio.
            scheduleGraphRebuildUnsafe()
        }
        lock.unlock()
    }

    // MARK: - 初始化

    init() {
        // AVFrame allocation is not realtime-safe. Allocate the reusable frame
        // shells when the graph object is created instead of on the first
        // hardware callback after an effect becomes active.
        cachedInputFrame = av_frame_alloc()
        cachedOutputFrame = av_frame_alloc()
    }

    deinit {
        destroyGraph()
        if cachedInputFrame != nil { av_frame_free(&cachedInputFrame) }
        if cachedOutputFrame != nil { av_frame_free(&cachedOutputFrame) }
        av_buffer_pool_uninit(&inputFramePool)
        outputScratch?.deallocate()
        outputScratch = nil
        outputScratchCapacity = 0
        transitionInputScratch?.deallocate()
        transitionInputScratch = nil
        transitionInputCapacity = 0
    }


    // MARK: - 基础音量控制

    /// 设置音量增益（dB）。0 = 不变，正值增大，负值减小。
    func setVolume(_ db: Float) {
        lock.lock()
        if volumeDB != db {
            volumeDB = db
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 动态处理

    /// 启用/禁用响度标准化（EBU R128）
    func setLoudnormEnabled(_ enabled: Bool) {
        lock.lock()
        if loudnormEnabled != enabled {
            loudnormEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置 loudnorm 参数
    func setLoudnormParams(targetLUFS: Float = -14.0, lra: Float = 11.0, truePeak: Float = -1.0) {
        lock.lock()
        loudnormTarget = targetLUFS
        loudnormLRA = lra
        loudnormTP = truePeak
        if loudnormEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用动态压缩（夜间模式）
    func setCompressorEnabled(_ enabled: Bool) {
        lock.lock()
        if compressorEnabled != enabled {
            compressorEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置动态压缩参数
    func setCompressorParams(threshold: Float = -20.0, ratio: Float = 4.0, attack: Float = 5.0, release: Float = 50.0, makeup: Float = 2.0) {
        lock.lock()
        compressorThreshold = threshold
        compressorRatio = ratio
        compressorAttack = attack
        compressorRelease = release
        compressorMakeup = makeup
        if compressorEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用限幅器
    func setLimiterEnabled(_ enabled: Bool) {
        lock.lock()
        if limiterEnabled != enabled {
            limiterEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置限幅器阈值（dBFS）
    func setLimiterLimit(_ limit: Float) {
        lock.lock()
        limiterLimit = limit
        if limiterEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用噪声门
    func setGateEnabled(_ enabled: Bool) {
        lock.lock()
        if gateEnabled != enabled {
            gateEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置噪声门阈值（dB）
    func setGateThreshold(_ threshold: Float) {
        lock.lock()
        gateThreshold = threshold
        if gateEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用自动增益
    func setAutoGainEnabled(_ enabled: Bool) {
        lock.lock()
        if autoGainEnabled != enabled {
            autoGainEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 速度与音调

    /// 设置播放速度倍率。范围 [0.5, 4.0]，1.0 = 原速。
    func setTempo(_ rate: Float) {
        let clamped = min(max(rate, 0.5), 4.0)
        lock.lock()
        if tempo != clamped {
            tempo = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置变调（半音数）。范围 [-12, +12]。
    func setPitchSemitones(_ semitones: Float) {
        let clamped = min(max(semitones, -12), 12)
        lock.lock()
        if pitchSemitones != clamped {
            pitchSemitones = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 均衡器与频率

    /// 设置低音增益（dB）。范围 [-12, +12]。
    func setBassGain(_ db: Float) {
        let clamped = min(max(db, -12), 12)
        lock.lock()
        if bassGain != clamped {
            bassGain = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置高音增益（dB）。范围 [-12, +12]。
    func setTrebleGain(_ db: Float) {
        let clamped = min(max(db, -12), 12)
        lock.lock()
        if trebleGain != clamped {
            trebleGain = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用超低音增强
    func setSubboostEnabled(_ enabled: Bool) {
        lock.lock()
        if subboostEnabled != enabled {
            subboostEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置超低音增强参数
    func setSubboostParams(gain: Float = 6.0, cutoff: Float = 100.0) {
        lock.lock()
        subboostGain = gain
        subboostCutoff = cutoff
        if subboostEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用带通滤波
    func setBandpassEnabled(_ enabled: Bool) {
        lock.lock()
        if bandpassEnabled != enabled {
            bandpassEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置带通滤波参数
    func setBandpassParams(frequency: Float, width: Float) {
        lock.lock()
        bandpassFrequency = frequency
        bandpassWidth = width
        if bandpassEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用带阻滤波
    func setBandrejectEnabled(_ enabled: Bool) {
        lock.lock()
        if bandrejectEnabled != enabled {
            bandrejectEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置带阻滤波参数
    func setBandrejectParams(frequency: Float, width: Float) {
        lock.lock()
        bandrejectFrequency = frequency
        bandrejectWidth = width
        if bandrejectEnabled { needsRebuild = true }
        lock.unlock()
    }

    // MARK: - 空间效果

    /// 设置环绕强度（0~1）
    func setSurroundLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        lock.lock()
        if surroundLevel != clamped {
            surroundLevel = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置混响强度（0~1）
    func setReverbLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        lock.lock()
        if reverbLevel != clamped {
            reverbLevel = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置立体声宽度（0~2），1.0 = 原始
    func setStereoWidth(_ width: Float) {
        let clamped = min(max(width, 0), 2)
        lock.lock()
        if stereoWidth != clamped {
            stereoWidth = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置声道平衡（-1 = 全左，0 = 居中，+1 = 全右）
    func setChannelBalance(_ balance: Float) {
        let clamped = min(max(balance, -1), 1)
        lock.lock()
        if channelBalance != clamped {
            channelBalance = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用单声道模式
    func setMonoEnabled(_ enabled: Bool) {
        lock.lock()
        if monoEnabled != enabled {
            monoEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用声道交换
    func setChannelSwapEnabled(_ enabled: Bool) {
        lock.lock()
        if channelSwapEnabled != enabled {
            channelSwapEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 时间效果

    /// 设置淡入时长（秒）
    func setFadeIn(duration: Float) {
        lock.lock()
        if fadeInDuration != duration {
            fadeInDuration = max(duration, 0)
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置淡出效果
    func setFadeOut(duration: Float, startTime: Float) {
        lock.lock()
        if fadeOutDuration != duration || fadeOutStartTime != startTime {
            fadeOutDuration = max(duration, 0)
            fadeOutStartTime = max(startTime, 0)
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置延迟（毫秒）
    func setDelay(_ ms: Float) {
        let clamped = max(ms, 0)
        lock.lock()
        if delayMs != clamped {
            delayMs = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 特殊效果

    /// 设置人声消除强度（0~1）
    func setVocalRemoval(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        lock.lock()
        if vocalRemovalLevel != clamped {
            vocalRemovalLevel = clamped
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用合唱效果
    func setChorusEnabled(_ enabled: Bool) {
        lock.lock()
        if chorusEnabled != enabled {
            chorusEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置合唱深度（0~1）
    func setChorusDepth(_ depth: Float) {
        let clamped = min(max(depth, 0), 1)
        lock.lock()
        if chorusDepth != clamped {
            chorusDepth = clamped
            if chorusEnabled { needsRebuild = true }
        }
        lock.unlock()
    }

    /// 启用/禁用镶边效果
    func setFlangerEnabled(_ enabled: Bool) {
        lock.lock()
        if flangerEnabled != enabled {
            flangerEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置镶边深度（0~1）
    func setFlangerDepth(_ depth: Float) {
        let clamped = min(max(depth, 0), 1)
        lock.lock()
        if flangerDepth != clamped {
            flangerDepth = clamped
            if flangerEnabled { needsRebuild = true }
        }
        lock.unlock()
    }

    /// 启用/禁用颤音效果
    func setTremoloEnabled(_ enabled: Bool) {
        lock.lock()
        if tremoloEnabled != enabled {
            tremoloEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置颤音参数
    func setTremoloParams(frequency: Float = 5.0, depth: Float = 0.5) {
        lock.lock()
        tremoloFrequency = frequency
        tremoloDepth = min(max(depth, 0), 1)
        if tremoloEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用颤抖效果
    func setVibratoEnabled(_ enabled: Bool) {
        lock.lock()
        if vibratoEnabled != enabled {
            vibratoEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置颤抖参数
    func setVibratoParams(frequency: Float = 5.0, depth: Float = 0.5) {
        lock.lock()
        vibratoFrequency = frequency
        vibratoDepth = min(max(depth, 0), 1)
        if vibratoEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用失真效果（Lo-Fi）
    func setCrusherEnabled(_ enabled: Bool) {
        lock.lock()
        if crusherEnabled != enabled {
            crusherEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置失真参数
    func setCrusherParams(bits: Float = 8.0, samples: Float = 4.0) {
        lock.lock()
        crusherBits = min(max(bits, 1), 16)
        crusherSamples = min(max(samples, 1), 16)
        if crusherEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用电话效果
    func setTelephoneEnabled(_ enabled: Bool) {
        lock.lock()
        if telephoneEnabled != enabled {
            telephoneEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用水下效果
    func setUnderwaterEnabled(_ enabled: Bool) {
        lock.lock()
        if underwaterEnabled != enabled {
            underwaterEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用收音机效果
    func setRadioEnabled(_ enabled: Bool) {
        lock.lock()
        if radioEnabled != enabled {
            radioEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 新增：音频修复滤镜

    /// 启用/禁用 FFT 降噪
    func setFFTDenoiseEnabled(_ enabled: Bool) {
        lock.lock()
        if fftDenoiseEnabled != enabled {
            fftDenoiseEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置 FFT 降噪参数
    func setFFTDenoiseAmount(_ amount: Float) {
        lock.lock()
        fftDenoiseAmount = max(0, min(100, amount))
        if fftDenoiseEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用去除脉冲噪声
    func setDeclickEnabled(_ enabled: Bool) {
        lock.lock()
        if declickEnabled != enabled {
            declickEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用去除削波失真
    func setDeclipEnabled(_ enabled: Bool) {
        lock.lock()
        if declipEnabled != enabled {
            declipEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 新增：动态处理滤镜

    /// 启用/禁用动态音频标准化
    func setDynaudnormEnabled(_ enabled: Bool) {
        lock.lock()
        if dynaudnormEnabled != enabled {
            dynaudnormEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置动态音频标准化参数
    func setDynaudnormParams(frameLen: Int = 500, gaussSize: Int = 31, peak: Float = 0.95) {
        lock.lock()
        dynaudnormFrameLen = frameLen
        dynaudnormGaussSize = gaussSize
        dynaudnormPeak = peak
        if dynaudnormEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用语音标准化
    func setSpeechnormEnabled(_ enabled: Bool) {
        lock.lock()
        if speechnormEnabled != enabled {
            speechnormEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 启用/禁用压缩/扩展
    func setCompandEnabled(_ enabled: Bool) {
        lock.lock()
        if compandEnabled != enabled {
            compandEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    // MARK: - 新增：空间音效滤镜

    /// 启用/禁用 Bauer 立体声转双耳
    func setBS2BEnabled(_ enabled: Bool) {
        lock.lock()
        if bs2bEnabled != enabled {
            bs2bEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置 BS2B 参数
    func setBS2BParams(fcut: Int = 700, feed: Int = 50) {
        lock.lock()
        bs2bFcut = fcut
        bs2bFeed = feed
        if bs2bEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用耳机交叉馈送
    func setCrossfeedEnabled(_ enabled: Bool) {
        lock.lock()
        if crossfeedEnabled != enabled {
            crossfeedEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置交叉馈送强度
    func setCrossfeedStrength(_ strength: Float) {
        lock.lock()
        crossfeedStrength = max(0, min(1, strength))
        if crossfeedEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用 Haas 效果
    func setHaasEnabled(_ enabled: Bool) {
        lock.lock()
        if haasEnabled != enabled {
            haasEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置 Haas 延迟（ms）
    func setHaasDelay(_ delay: Float) {
        lock.lock()
        haasDelay = max(0, min(40, delay))
        if haasEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用虚拟低音
    func setVirtualbassEnabled(_ enabled: Bool) {
        lock.lock()
        if virtualbassEnabled != enabled {
            virtualbassEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置虚拟低音参数
    func setVirtualbassParams(cutoff: Float = 250.0, strength: Float = 3.0) {
        lock.lock()
        virtualbassCutoff = cutoff
        virtualbassStrength = strength
        if virtualbassEnabled { needsRebuild = true }
        lock.unlock()
    }

    // MARK: - 新增：音色处理滤镜

    /// 启用/禁用激励器
    func setExciterEnabled(_ enabled: Bool) {
        lock.lock()
        if exciterEnabled != enabled {
            exciterEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置激励器参数
    func setExciterParams(amount: Float = 3.0, freq: Float = 7500.0) {
        lock.lock()
        exciterAmount = amount
        exciterFreq = freq
        if exciterEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用软削波
    func setSoftclipEnabled(_ enabled: Bool) {
        lock.lock()
        if softclipEnabled != enabled {
            softclipEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置软削波类型（0=tanh, 1=atan, 2=cubic, 3=exp, 4=alg, 5=quintic, 6=sin, 7=erf）
    func setSoftclipType(_ type: Int) {
        lock.lock()
        softclipType = max(0, min(7, type))
        if softclipEnabled { needsRebuild = true }
        lock.unlock()
    }

    /// 启用/禁用对话增强
    func setDialogueEnhanceEnabled(_ enabled: Bool) {
        lock.lock()
        if dialogueEnhanceEnabled != enabled {
            dialogueEnhanceEnabled = enabled
            needsRebuild = true
        }
        lock.unlock()
    }

    /// 设置对话增强参数
    func setDialogueEnhanceParams(original: Float = 1.0, enhance: Float = 1.0) {
        lock.lock()
        dialogueEnhanceOriginal = original
        dialogueEnhanceEnhance = enhance
        if dialogueEnhanceEnabled { needsRebuild = true }
        lock.unlock()
    }

    // MARK: - 重置

    /// 重置已处理采样计数
    func resetProcessedSamples() {
        lock.lock()
        sampleCountResetPending = true
        lock.unlock()
    }

    /// 重置所有滤镜到默认值
    func reset() {
        lock.lock()
        // 基础
        volumeDB = 0.0
        // 动态
        loudnormEnabled = false
        loudnormTarget = -14.0
        loudnormLRA = 7.0
        loudnormTP = -1.0
        compressorEnabled = false
        compressorThreshold = -20.0
        compressorRatio = 4.0
        compressorAttack = 5.0
        compressorRelease = 50.0
        compressorMakeup = 2.0
        limiterEnabled = false
        limiterLimit = -1.0
        gateEnabled = false
        gateThreshold = -40.0
        autoGainEnabled = false
        // 速度音调
        tempo = 1.0
        pitchSemitones = 0.0
        // 频率
        bassGain = 0.0
        trebleGain = 0.0
        subboostEnabled = false
        subboostGain = 6.0
        subboostCutoff = 100.0
        bandpassEnabled = false
        bandpassFrequency = 1000.0
        bandpassWidth = 2000.0
        bandrejectEnabled = false
        bandrejectFrequency = 1000.0
        bandrejectWidth = 200.0
        // 空间
        surroundLevel = 0.0
        reverbLevel = 0.0
        stereoWidth = 1.0
        channelBalance = 0.0
        monoEnabled = false
        channelSwapEnabled = false
        // 时间
        fadeInDuration = 0.0
        fadeOutDuration = 0.0
        fadeOutStartTime = 0.0
        delayMs = 0.0
        // 特效
        vocalRemovalLevel = 0.0
        chorusEnabled = false
        chorusDepth = 0.5
        flangerEnabled = false
        flangerDepth = 0.5
        tremoloEnabled = false
        tremoloFrequency = 5.0
        tremoloDepth = 0.5
        vibratoEnabled = false
        vibratoFrequency = 5.0
        vibratoDepth = 0.5
        crusherEnabled = false
        crusherBits = 8.0
        crusherSamples = 4.0
        telephoneEnabled = false
        underwaterEnabled = false
        radioEnabled = false
        // 新增：音频修复滤镜
        fftDenoiseEnabled = false
        fftDenoiseAmount = 10.0
        declickEnabled = false
        declipEnabled = false
        // 新增：动态处理滤镜
        dynaudnormEnabled = false
        dynaudnormFrameLen = 500
        dynaudnormGaussSize = 31
        dynaudnormPeak = 0.95
        speechnormEnabled = false
        compandEnabled = false
        // 新增：空间音效滤镜
        bs2bEnabled = false
        bs2bFcut = 700
        bs2bFeed = 50
        crossfeedEnabled = false
        crossfeedStrength = 0.3
        haasEnabled = false
        haasDelay = 20.0
        virtualbassEnabled = false
        virtualbassCutoff = 250.0
        virtualbassStrength = 3.0
        // 新增：音色处理滤镜
        exciterEnabled = false
        exciterAmount = 3.0
        exciterFreq = 7500.0
        softclipEnabled = false
        softclipType = 0
        dialogueEnhanceEnabled = false
        dialogueEnhanceOriginal = 1.0
        dialogueEnhanceEnhance = 1.0
        // 状态
        sampleCountResetPending = true
        needsRebuild = true
        scheduleGraphRebuildUnsafe()
        lock.unlock()
    }


    // MARK: - 处理

    /// 处理一个音频 buffer，返回滤镜处理后的结果。
    /// 如果没有激活的滤镜，直接返回原 buffer（零拷贝）。
    /// 
    /// 避免音效切换产生电流声或卡音：
    /// 1. 参数变化期间继续使用旧滤镜图
    /// 2. 替换图在后台独立构建，不占用实时处理锁
    /// 3. 新图就绪后经由干声桥接，避免同一回调运行两套完整滤镜图
    /// 4. 控制锁忙时只延后交接，继续运行音频线程持有的图
    func process(_ buffer: AudioBuffer) -> AudioBuffer {
        synchronizePreparedGraph(for: buffer)
        if let pending = pendingFilterGraph,
           (pendingGraphSampleRate != buffer.sampleRate || pendingGraphChannelCount != buffer.channelCount),
           retiredFilterGraph == nil {
            retiredFilterGraph = pending
            pendingFilterGraph = nil
            pendingBufferSrcCtx = nil
            pendingBufferSinkCtx = nil
            effectFadeOutFramesRemaining = 0
            rebuildWaitingForFadeOut = false
        }
        if pendingFilterGraph != nil,
           (effectFadeOutFramesRemaining == 0
                || activeGraphSampleRate != buffer.sampleRate
                || activeGraphChannelCount != buffer.channelCount) {
            promotePendingGraphUnsafe(fadeIn: true)
        }
        guard activeGraphSampleRate == buffer.sampleRate,
              activeGraphChannelCount == buffer.channelCount,
              activeGraphHasEffects || effectFadeOutFramesRemaining > 0 || effectFadeInFramesRemaining > 0,
              let srcCtx = bufferSrcCtx, let sinkCtx = bufferSinkCtx else {
            return buffer
        }
        processedSamples += Int64(buffer.frameCount)

        let inputSampleCount = buffer.frameCount * buffer.channelCount
        let transitionInput: UnsafeMutablePointer<Float>?
        if (effectFadeOutFramesRemaining > 0
                || effectFadeInFramesRemaining > 0),
           let scratch = ensureTransitionInputCapacityUnsafe(inputSampleCount) {
            scratch.update(from: buffer.data, count: inputSampleCount)
            transitionInput = scratch
        } else {
            transitionInput = nil
        }

        if cachedInputFrame == nil { cachedInputFrame = av_frame_alloc() }
        guard let frame = cachedInputFrame else {
            return buffer
        }
        av_frame_unref(frame)

        frame.pointee.format = AV_SAMPLE_FMT_FLT.rawValue
        frame.pointee.sample_rate = Int32(buffer.sampleRate)
        frame.pointee.nb_samples = Int32(buffer.frameCount)
        av_channel_layout_default(&frame.pointee.ch_layout, Int32(buffer.channelCount))

        let totalBytes = buffer.frameCount * buffer.channelCount * MemoryLayout<Float>.size
        guard attachPooledInputBufferUnsafe(to: frame, byteCount: totalBytes) else {
            return buffer
        }
        if let dst = frame.pointee.data.0 {
            memcpy(dst, buffer.data, totalBytes)
        }

        let addRet = av_buffersrc_add_frame(srcCtx, frame)

        guard addRet >= 0 else {
            return buffer
        }

        if cachedOutputFrame == nil { cachedOutputFrame = av_frame_alloc() }
        guard let outFrame = cachedOutputFrame else {
            return buffer
        }
        av_frame_unref(outFrame)

        let getResult = av_buffersink_get_frame(sinkCtx, outFrame)

        guard getResult >= 0 else {
            return buffer
        }

        let outFrameCount = Int(outFrame.pointee.nb_samples)
        let outChannels = Int(outFrame.pointee.ch_layout.nb_channels)
        let outSamples = outFrameCount * outChannels
        let inputCapacity = buffer.frameCount * buffer.channelCount
        // 绝大多数实时滤镜保持采样数和声道数不变，直接复用渲染回调已经
        // 提供的 PCM 缓冲。样本数变化（如 atempo）时使用本类持有的持久
        // scratch，跨回调复用——调用方不得释放返回的 data 指针，且必须在
        // 下一次 process 前用完（下次调用会覆写 scratch）。
        let outData: UnsafeMutablePointer<Float>
        if outSamples == inputCapacity && outChannels == buffer.channelCount {
            outData = buffer.data
        } else {
            if outSamples > outputScratchCapacity, let stale = outputScratch {
                stale.deallocate()
                outputScratch = nil
                outputScratchCapacity = 0
            }
            if outputScratch == nil {
                let capacity = max(outSamples, 8192)
                outputScratch = .allocate(capacity: capacity)
                outputScratchCapacity = capacity
            }
            outData = outputScratch!
        }

        if let src = outFrame.pointee.data.0 {
            memcpy(outData, src, outSamples * MemoryLayout<Float>.size)
        }

        let outRate = Int(outFrame.pointee.sample_rate)

        if effectFadeOutFramesRemaining > 0, let transitionInput {
            applyEffectTransitionUnsafe(
                wetData: outData,
                dryData: transitionInput,
                wetFrameCount: outFrameCount,
                dryFrameCount: buffer.frameCount,
                wetChannelCount: outChannels,
                dryChannelCount: buffer.channelCount,
                fadingIn: false
            )
            if effectFadeOutFramesRemaining == 0, rebuildWaitingForFadeOut {
                promotePendingGraphUnsafe(fadeIn: true)
            }
        } else if effectFadeInFramesRemaining > 0, let transitionInput {
            applyEffectTransitionUnsafe(
                wetData: outData,
                dryData: transitionInput,
                wetFrameCount: outFrameCount,
                dryFrameCount: buffer.frameCount,
                wetChannelCount: outChannels,
                dryChannelCount: buffer.channelCount,
                fadingIn: true
            )
        }

        return AudioBuffer(
            data: outData,
            frameCount: outFrameCount,
            channelCount: outChannels,
            sampleRate: outRate
        )
    }

    /// A graph has been prepared for this format, or is already being rendered.
    func isReadyForDiagnostics(sampleRate: Int, channelCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let prepared = preparedGraph.map {
            $0.sampleRate == sampleRate && $0.channelCount == channelCount
        } ?? false
        let rendered = publishedRenderSampleRate == sampleRate
            && publishedRenderChannelCount == channelCount
        return (prepared || rendered) && !needsRebuild && !rebuildScheduled
    }

    private func synchronizePreparedGraph(for buffer: AudioBuffer) {
        // Only defer the exchange when control is busy, not the active DSP.
        guard lock.try() else { return }
        defer { lock.unlock() }
        if sampleCountResetPending {
            processedSamples = 0
            sampleCountResetPending = false
        }
        if retiredFilterGraph != nil, retirementMailbox == nil {
            retirementMailbox = retiredFilterGraph
            retiredFilterGraph = nil
            scheduleGraphRebuildUnsafe()
        }
        if retirementMailbox != nil { scheduleGraphRebuildUnsafe() }
        if sampleRate != buffer.sampleRate || channelCount != buffer.channelCount {
            sampleRate = buffer.sampleRate
            channelCount = buffer.channelCount
            needsRebuild = true
        }
        if needsRebuild { scheduleGraphRebuildUnsafe() }
        if !needsRebuild, !rebuildScheduled, pendingFilterGraph == nil, retiredFilterGraph == nil,
           let prepared = preparedGraph,
           prepared.sampleRate == buffer.sampleRate,
           prepared.channelCount == buffer.channelCount {
            preparedGraph = nil
            if filterGraph != nil, activeGraphHasEffects,
               activeGraphSampleRate == buffer.sampleRate,
               activeGraphChannelCount == buffer.channelCount {
                pendingFilterGraph = prepared.graph
                pendingBufferSrcCtx = prepared.source
                pendingBufferSinkCtx = prepared.sink
                pendingGraphSampleRate = prepared.sampleRate
                pendingGraphChannelCount = prepared.channelCount
                pendingGraphHasEffects = prepared.hasEffects
                effectFadeOutFramesRemaining = effectTransitionDurationFrames
                effectFadeInFramesRemaining = 0
                rebuildWaitingForFadeOut = true
            } else {
                retiredFilterGraph = filterGraph
                filterGraph = prepared.graph
                bufferSrcCtx = prepared.source
                bufferSinkCtx = prepared.sink
                activeGraphSampleRate = prepared.sampleRate
                activeGraphChannelCount = prepared.channelCount
                activeGraphHasEffects = prepared.hasEffects
                effectFadeOutFramesRemaining = 0
                effectFadeInFramesRemaining = prepared.hasEffects ? effectTransitionDurationFrames : 0
                rebuildWaitingForFadeOut = false
            }
        }
        publishedRenderSampleRate = activeGraphSampleRate
        publishedRenderChannelCount = activeGraphChannelCount
        publishedRenderActive = activeGraphHasEffects || pendingFilterGraph != nil
    }

    private func promotePendingGraphUnsafe(fadeIn: Bool) {
        guard retiredFilterGraph == nil,
              let nextGraph = pendingFilterGraph,
              let nextSource = pendingBufferSrcCtx,
              let nextSink = pendingBufferSinkCtx else { return }
        retiredFilterGraph = filterGraph
        filterGraph = nextGraph
        bufferSrcCtx = nextSource
        bufferSinkCtx = nextSink
        activeGraphSampleRate = pendingGraphSampleRate
        activeGraphChannelCount = pendingGraphChannelCount
        activeGraphHasEffects = pendingGraphHasEffects
        pendingFilterGraph = nil
        pendingBufferSrcCtx = nil
        pendingBufferSinkCtx = nil
        rebuildWaitingForFadeOut = false
        effectFadeOutFramesRemaining = 0
        effectFadeInFramesRemaining = fadeIn && activeGraphHasEffects ? effectTransitionDurationFrames : 0
    }

    /// 首次建图时用同一输入帧的干声与湿声做连续接入。
    private func applyEffectTransitionUnsafe(
        wetData: UnsafeMutablePointer<Float>,
        dryData: UnsafeMutablePointer<Float>,
        wetFrameCount: Int,
        dryFrameCount: Int,
        wetChannelCount: Int,
        dryChannelCount: Int,
        fadingIn: Bool
    ) {
        let remaining = AudioEffectTransition.mix(
            wetData: wetData,
            dryData: dryData,
            wetFrameCount: wetFrameCount,
            dryFrameCount: dryFrameCount,
            wetChannelCount: wetChannelCount,
            dryChannelCount: dryChannelCount,
            durationFrames: effectTransitionDurationFrames,
            remainingFrames: fadingIn ? effectFadeInFramesRemaining : effectFadeOutFramesRemaining,
            fadingIn: fadingIn
        )
        if fadingIn {
            effectFadeInFramesRemaining = remaining
        } else {
            effectFadeOutFramesRemaining = remaining
        }
    }

    private func ensureTransitionInputCapacityUnsafe(
        _ sampleCount: Int
    ) -> UnsafeMutablePointer<Float>? {
        guard sampleCount > 0 else { return nil }
        if sampleCount > transitionInputCapacity {
            transitionInputScratch?.deallocate()
            var capacity = max(16_384, transitionInputCapacity)
            while capacity < sampleCount { capacity <<= 1 }
            transitionInputScratch = .allocate(capacity: capacity)
            transitionInputCapacity = capacity
        }
        return transitionInputScratch
    }

    /// Attaches pooled PCM storage; called only by the audio consumer.
    /// 池容量按 2 的幂增长，回调帧长小幅波动不会反复重建池；
    /// 稳态下 av_buffer_pool_get 直接复用已归还的缓冲，不触发 malloc。
    private func attachPooledInputBufferUnsafe(
        to frame: UnsafeMutablePointer<AVFrame>,
        byteCount: Int
    ) -> Bool {
        guard byteCount > 0 else { return false }
        if inputFramePool == nil || byteCount > inputFramePoolBufferSize {
            av_buffer_pool_uninit(&inputFramePool)
            var poolSize = 16_384
            while poolSize < byteCount { poolSize <<= 1 }
            inputFramePool = av_buffer_pool_init(poolSize, nil)
            inputFramePoolBufferSize = inputFramePool != nil ? poolSize : 0
        }
        guard let pool = inputFramePool,
              let bufferRef = av_buffer_pool_get(pool) else {
            // 池不可用时退回逐帧分配，保证功能不中断
            return av_frame_get_buffer(frame, 0) >= 0
        }
        frame.pointee.buf.0 = bufferRef
        frame.pointee.data.0 = bufferRef.pointee.data
        frame.pointee.linesize.0 = Int32(byteCount)
        frame.pointee.extended_data = UnsafeMutableRawPointer(frame)
            .advanced(by: MemoryLayout<AVFrame>.offset(of: \AVFrame.data)!)
            .assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
        return true
    }

    // MARK: - 滤镜图构建

    /// Called with the control/mailbox lock held. The worker never mutates an
    /// active graph or render-side transition state.
    private func scheduleGraphRebuildUnsafe() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        rebuildQueue.async { [weak self] in
            self?.performScheduledGraphRebuild()
        }
    }

    private func performScheduledGraphRebuild() {
        lock.lock()
        var graphToRetire = retirementMailbox
        retirementMailbox = nil
        lock.unlock()
        if graphToRetire != nil { avfilter_graph_free(&graphToRetire) }

        let builder = AudioFilterGraph()
        lock.lock()
        guard needsRebuild, sampleRate > 0, channelCount > 0 else {
            rebuildScheduled = false
            lock.unlock()
            return
        }
        needsRebuild = false
        let targetSampleRate = sampleRate
        let targetChannelCount = channelCount
        copyGraphConfigurationUnsafe(to: builder)
        lock.unlock()

        builder.rebuildGraph()
        var builtGraph = builder.filterGraph
        let builtSource = builder.bufferSrcCtx
        let builtSink = builder.bufferSinkCtx
        let hasEffects = builder.checkAnyFilterActive()
        builder.filterGraph = nil
        builder.bufferSrcCtx = nil
        builder.bufferSinkCtx = nil

        lock.lock()
        rebuildScheduled = false
        if needsRebuild || sampleRate != targetSampleRate || channelCount != targetChannelCount {
            needsRebuild = true
            scheduleGraphRebuildUnsafe()
            lock.unlock()
            if builtGraph != nil { avfilter_graph_free(&builtGraph) }
            return
        }
        guard let graph = builtGraph, let source = builtSource, let sink = builtSink else {
            lock.unlock()
            if builtGraph != nil { avfilter_graph_free(&builtGraph) }
            return
        }
        var superseded = preparedGraph?.graph
        preparedGraph = PreparedGraph(
            graph: graph, source: source, sink: sink,
            sampleRate: targetSampleRate, channelCount: targetChannelCount, hasEffects: hasEffects
        )
        lock.unlock()
        if superseded != nil { avfilter_graph_free(&superseded) }
    }

    /// Copies only graph-building state into an isolated instance. The
    /// replacement can then negotiate FFmpeg filters off the render lock while
    /// the active instance continues processing audio.
    private func copyGraphConfigurationUnsafe(to builder: AudioFilterGraph) {
        builder.volumeDB = volumeDB
        builder.loudnormEnabled = loudnormEnabled
        builder.loudnormTarget = loudnormTarget
        builder.loudnormLRA = loudnormLRA
        builder.loudnormTP = loudnormTP
        builder.compressorEnabled = compressorEnabled
        builder.compressorThreshold = compressorThreshold
        builder.compressorRatio = compressorRatio
        builder.compressorAttack = compressorAttack
        builder.compressorRelease = compressorRelease
        builder.compressorMakeup = compressorMakeup
        builder.limiterEnabled = limiterEnabled
        builder.limiterLimit = limiterLimit
        builder.gateEnabled = gateEnabled
        builder.gateThreshold = gateThreshold
        builder.autoGainEnabled = autoGainEnabled
        builder.tempo = tempo
        builder.pitchSemitones = pitchSemitones
        builder.bassGain = bassGain
        builder.trebleGain = trebleGain
        builder.subboostEnabled = subboostEnabled
        builder.subboostGain = subboostGain
        builder.subboostCutoff = subboostCutoff
        builder.bandpassEnabled = bandpassEnabled
        builder.bandpassFrequency = bandpassFrequency
        builder.bandpassWidth = bandpassWidth
        builder.bandrejectEnabled = bandrejectEnabled
        builder.bandrejectFrequency = bandrejectFrequency
        builder.bandrejectWidth = bandrejectWidth
        builder.surroundLevel = surroundLevel
        builder.reverbLevel = reverbLevel
        builder.stereoWidth = stereoWidth
        builder.channelBalance = channelBalance
        builder.monoEnabled = monoEnabled
        builder.channelSwapEnabled = channelSwapEnabled
        builder.fadeInDuration = fadeInDuration
        builder.fadeOutDuration = fadeOutDuration
        builder.fadeOutStartTime = fadeOutStartTime
        builder.delayMs = delayMs
        builder.vocalRemovalLevel = vocalRemovalLevel
        builder.chorusEnabled = chorusEnabled
        builder.chorusDepth = chorusDepth
        builder.flangerEnabled = flangerEnabled
        builder.flangerDepth = flangerDepth
        builder.tremoloEnabled = tremoloEnabled
        builder.tremoloFrequency = tremoloFrequency
        builder.tremoloDepth = tremoloDepth
        builder.vibratoEnabled = vibratoEnabled
        builder.vibratoFrequency = vibratoFrequency
        builder.vibratoDepth = vibratoDepth
        builder.crusherEnabled = crusherEnabled
        builder.crusherBits = crusherBits
        builder.crusherSamples = crusherSamples
        builder.telephoneEnabled = telephoneEnabled
        builder.underwaterEnabled = underwaterEnabled
        builder.radioEnabled = radioEnabled
        builder.fftDenoiseEnabled = fftDenoiseEnabled
        builder.fftDenoiseAmount = fftDenoiseAmount
        builder.declickEnabled = declickEnabled
        builder.declipEnabled = declipEnabled
        builder.dynaudnormEnabled = dynaudnormEnabled
        builder.dynaudnormFrameLen = dynaudnormFrameLen
        builder.dynaudnormGaussSize = dynaudnormGaussSize
        builder.dynaudnormPeak = dynaudnormPeak
        builder.speechnormEnabled = speechnormEnabled
        builder.compandEnabled = compandEnabled
        builder.bs2bEnabled = bs2bEnabled
        builder.bs2bFcut = bs2bFcut
        builder.bs2bFeed = bs2bFeed
        builder.crossfeedEnabled = crossfeedEnabled
        builder.crossfeedStrength = crossfeedStrength
        builder.haasEnabled = haasEnabled
        builder.haasDelay = haasDelay
        builder.virtualbassEnabled = virtualbassEnabled
        builder.virtualbassCutoff = virtualbassCutoff
        builder.virtualbassStrength = virtualbassStrength
        builder.exciterEnabled = exciterEnabled
        builder.exciterAmount = exciterAmount
        builder.exciterFreq = exciterFreq
        builder.softclipEnabled = softclipEnabled
        builder.softclipType = softclipType
        builder.dialogueEnhanceEnabled = dialogueEnhanceEnabled
        builder.dialogueEnhanceOriginal = dialogueEnhanceOriginal
        builder.dialogueEnhanceEnhance = dialogueEnhanceEnhance
        builder.sampleRate = sampleRate
        builder.channelCount = channelCount
    }

    /// Captures the current control-side filter configuration without sharing
    /// live FFmpeg graph objects. Used by the developer audio laboratory so
    /// temporary experiments can be reverted exactly.
    func makeDiagnosticConfigurationSnapshot() -> AudioFilterGraph {
        let snapshot = AudioFilterGraph()
        lock.lock()
        copyGraphConfigurationUnsafe(to: snapshot)
        lock.unlock()
        return snapshot
    }

    /// Restores a previously captured diagnostic configuration while keeping
    /// the format of the stream that is currently audible.
    func restoreDiagnosticConfiguration(from snapshot: AudioFilterGraph) {
        snapshot.lock.lock()
        lock.lock()
        let currentSampleRate = sampleRate
        let currentChannelCount = channelCount
        snapshot.copyGraphConfigurationUnsafe(to: self)
        sampleRate = currentSampleRate
        channelCount = currentChannelCount
        needsRebuild = true
        scheduleGraphRebuildUnsafe()
        lock.unlock()
        snapshot.lock.unlock()
    }

    /// 重建 FFmpeg avfilter 图
    private func rebuildGraph() {
        destroyGraphUnsafe()

        filterGraph = avfilter_graph_alloc()
        guard let graph = filterGraph else { return }

        // This graph is pulled by the hardware render callback. Slice workers
        // add a scheduling barrier to each block of stereo tone processing.
        graph.pointee.nb_threads = 1
        graph.pointee.thread_type = 0

        // abuffer（输入源）
        guard let abuffer = avfilter_get_by_name("abuffer") else { return }
        // 根据声道数获取对应的声道布局字符串
        let channelLayoutStr = getChannelLayoutString(for: channelCount)
        let srcArgs = "sample_rate=\(sampleRate):sample_fmt=flt:channel_layout=\(channelLayoutStr)"
        var srcCtx: UnsafeMutablePointer<AVFilterContext>?
        guard avfilter_graph_create_filter(&srcCtx, abuffer, "src", srcArgs, nil, graph) >= 0,
              let src = srcCtx else {
            destroyGraphUnsafe()
            return
        }
        bufferSrcCtx = src

        // abuffersink（输出）
        // 不需要设置 sample_fmts 和 sample_rates，因为我们在滤镜链末尾
        // 使用 aformat 滤镜来强制输出格式
        guard let abuffersink = avfilter_get_by_name("abuffersink") else {
            destroyGraphUnsafe()
            return
        }
        var sinkCtx: UnsafeMutablePointer<AVFilterContext>?
        guard avfilter_graph_create_filter(&sinkCtx, abuffersink, "sink", nil, nil, graph) >= 0,
              let sink = sinkCtx else {
            destroyGraphUnsafe()
            return
        }
        bufferSinkCtx = sink

        // 构建滤镜链
        var lastCtx = src

        // ==================== 音量控制 ====================
        if volumeDB != 0.0 {
            if let ctx = createFilter(graph: graph, name: "volume", label: "vol",
                                       args: "volume=\(String(format: "%.1f", volumeDB))dB") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 动态处理 ====================
        
        // 噪声门
        if gateEnabled {
            if let ctx = createFilter(graph: graph, name: "agate", label: "gate",
                                       args: "threshold=\(String(format: "%.1f", gateThreshold))dB") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 动态压缩
        if compressorEnabled {
            let args = "threshold=\(String(format: "%.1f", compressorThreshold))dB:ratio=\(String(format: "%.1f", compressorRatio)):attack=\(String(format: "%.1f", compressorAttack)):release=\(String(format: "%.1f", compressorRelease)):makeup=\(String(format: "%.1f", compressorMakeup))dB"
            if let ctx = createFilter(graph: graph, name: "acompressor", label: "comp", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 限幅器
        if limiterEnabled {
            if let ctx = createFilter(graph: graph, name: "alimiter", label: "limiter",
                                       args: "limit=\(String(format: "%.1f", limiterLimit))dB:level=false") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 自动增益
        if autoGainEnabled {
            if let ctx = createFilter(graph: graph, name: "dynaudnorm", label: "autogain",
                                       args: "framelen=500:gausssize=31:peak=0.95") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 响度标准化
        // 使用 linear=true 模式，避免实时处理时的 pumping 效果
        // dual_mono=true 对单声道内容更友好
        // offset=0 不额外调整偏移
        if loudnormEnabled {
            let args = "I=\(String(format: "%.1f", loudnormTarget)):LRA=\(String(format: "%.1f", loudnormLRA)):TP=\(String(format: "%.1f", loudnormTP)):linear=true:dual_mono=true:print_format=none"
            if let ctx = createFilter(graph: graph, name: "loudnorm", label: "loudnorm", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 动态音频标准化（dynaudnorm）- 比 loudnorm 更适合实时处理
        if dynaudnormEnabled {
            let args = "framelen=\(dynaudnormFrameLen):gausssize=\(dynaudnormGaussSize):peak=\(String(format: "%.2f", dynaudnormPeak))"
            if let ctx = createFilter(graph: graph, name: "dynaudnorm", label: "dynaudnorm", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 语音标准化（speechnorm）- 专为语音内容优化
        if speechnormEnabled {
            if let ctx = createFilter(graph: graph, name: "speechnorm", label: "speechnorm", args: "e=12.5:r=0.0001:l=1") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 压缩/扩展（compand）- 更灵活的动态控制
        if compandEnabled {
            // 默认参数：轻度压缩，适合音乐
            let args = "attacks=0.3:decays=0.8:points=-80/-80|-45/-45|-27/-25|0/-10:soft-knee=6:gain=5"
            if let ctx = createFilter(graph: graph, name: "compand", label: "compand", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 音频修复滤镜 ====================

        // FFT 降噪（afftdn）- 基于 FFT 的降噪
        if fftDenoiseEnabled {
            let args = "nr=\(String(format: "%.0f", fftDenoiseAmount)):nf=-25:tn=1"
            if let ctx = createFilter(graph: graph, name: "afftdn", label: "afftdn", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 去除脉冲噪声（adeclick）
        if declickEnabled {
            if let ctx = createFilter(graph: graph, name: "adeclick", label: "adeclick", args: "w=55:o=75") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 去除削波失真（adeclip）
        if declipEnabled {
            if let ctx = createFilter(graph: graph, name: "adeclip", label: "adeclip", args: "w=55:o=75") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 均衡器与频率 ====================
        
        // 低音
        if bassGain != 0.0 {
            if let ctx = createFilter(graph: graph, name: "bass", label: "bass",
                                       args: "gain=\(String(format: "%.1f", bassGain)):frequency=100:width_type=o:width=0.5") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 高音
        if trebleGain != 0.0 {
            if let ctx = createFilter(graph: graph, name: "treble", label: "treble",
                                       args: "gain=\(String(format: "%.1f", trebleGain)):frequency=3000:width_type=o:width=0.5") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 超低音增强
        if subboostEnabled {
            // asubboost has no direct dB gain control. Map the public gain to
            // its wet path so 0 dB is effectively neutral and 6 dB reaches a
            // full-strength generated sub signal.
            let wet = min(1, max(0, powf(10, subboostGain / 20) - 1))
            if let ctx = createFilter(graph: graph, name: "asubboost", label: "subboost",
                                       args: "dry=1:wet=\(String(format: "%.3f", wet)):decay=0.7:feedback=0.5:cutoff=\(String(format: "%.0f", subboostCutoff))") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 带通滤波
        if bandpassEnabled {
            if let ctx = createFilter(graph: graph, name: "bandpass", label: "bandpass",
                                       args: "frequency=\(String(format: "%.0f", bandpassFrequency)):width_type=h:width=\(String(format: "%.0f", bandpassWidth))") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 带阻滤波
        if bandrejectEnabled {
            if let ctx = createFilter(graph: graph, name: "bandreject", label: "bandreject",
                                       args: "frequency=\(String(format: "%.0f", bandrejectFrequency)):width_type=h:width=\(String(format: "%.0f", bandrejectWidth))") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 空间效果 ====================
        
        // 人声消除（需要在空间效果之前，因为它依赖立体声）
        if vocalRemovalLevel > 0.0 && channelCount == 2 {
            // 使用 stereotools 的 mlev（中置电平）来消除人声
            let mlev = 1.0 - vocalRemovalLevel
            if let ctx = createFilter(graph: graph, name: "stereotools", label: "vocal",
                                       args: "mlev=\(String(format: "%.2f", mlev))") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 声道交换（交换前左和前右声道）
        if channelSwapEnabled && channelCount >= 2 {
            // 根据声道数生成交换公式
            let swapArgs: String
            switch channelCount {
            case 2:
                swapArgs = "stereo|c0=c1|c1=c0"
            case 6:
                // 5.1: 交换 FL 和 FR，其他保持
                swapArgs = "5.1|c0=c1|c1=c0|c2=c2|c3=c3|c4=c4|c5=c5"
            case 8:
                // 7.1: 交换 FL 和 FR，其他保持
                swapArgs = "7.1|c0=c1|c1=c0|c2=c2|c3=c3|c4=c4|c5=c5|c6=c6|c7=c7"
            default:
                // 通用：只交换前两个声道
                var channels = ["c1", "c0"]
                for i in 2..<channelCount {
                    channels.append("c\(i)")
                }
                swapArgs = "\(channelCount)c|\(channels.enumerated().map { "c\($0.offset)=\($0.element)" }.joined(separator: "|"))"
            }
            if let ctx = createFilter(graph: graph, name: "pan", label: "swap", args: swapArgs) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 声道平衡（调整前左和前右声道的增益）
        if channelBalance != 0.0 && channelCount >= 2 {
            let leftGain = channelBalance < 0 ? 1.0 : 1.0 - channelBalance
            let rightGain = channelBalance > 0 ? 1.0 : 1.0 + channelBalance
            // 根据声道数生成平衡公式
            let balanceArgs: String
            switch channelCount {
            case 2:
                balanceArgs = "stereo|c0=\(String(format: "%.2f", leftGain))*c0|c1=\(String(format: "%.2f", rightGain))*c1"
            case 6:
                // 5.1: 调整 FL 和 FR，其他保持
                balanceArgs = "5.1|c0=\(String(format: "%.2f", leftGain))*c0|c1=\(String(format: "%.2f", rightGain))*c1|c2=c2|c3=c3|c4=\(String(format: "%.2f", leftGain))*c4|c5=\(String(format: "%.2f", rightGain))*c5"
            case 8:
                // 7.1: 调整 FL、FR、SL、SR
                balanceArgs = "7.1|c0=\(String(format: "%.2f", leftGain))*c0|c1=\(String(format: "%.2f", rightGain))*c1|c2=c2|c3=c3|c4=\(String(format: "%.2f", leftGain))*c4|c5=\(String(format: "%.2f", rightGain))*c5|c6=\(String(format: "%.2f", leftGain))*c6|c7=\(String(format: "%.2f", rightGain))*c7"
            default:
                // 通用：只调整前两个声道
                var channels = ["\(String(format: "%.2f", leftGain))*c0", "\(String(format: "%.2f", rightGain))*c1"]
                for i in 2..<channelCount {
                    channels.append("c\(i)")
                }
                balanceArgs = "\(channelCount)c|\(channels.enumerated().map { "c\($0.offset)=\($0.element)" }.joined(separator: "|"))"
            }
            if let ctx = createFilter(graph: graph, name: "pan", label: "balance", args: balanceArgs) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        let spatial = MonoSpatialFilterParameters(
            stereoWidth: stereoWidth,
            surroundLevel: surroundLevel,
            reverbLevel: reverbLevel
        )
        if abs(spatial.effectiveStereoWidth - 1) > 0.0005 && channelCount == 2 {
            if let ctx = createFilter(graph: graph, name: "stereotools", label: "width",
                                       args: "slev=\(String(format: "%.3f", spatial.effectiveStereoWidth))") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        if !spatial.echoDecays.isEmpty {
            let upstreamBoostDB = max(0, volumeDB) + max(0, bassGain) + max(0, trebleGain)
                + (compressorEnabled ? max(0, compressorMakeup) : 0)
                + (subboostEnabled ? max(0, subboostGain) : 0)
            let workingGain = String(format: "%.9g", spatial.echoWorkingGain(upstreamBoostDB: upstreamBoostDB))
            let delays = spatial.echoDelays.map { String($0) }.joined(separator: "|")
            let decays = spatial.echoDecays.map { String(format: "%.3f", $0) }.joined(separator: "|")
            let args = "in_gain=\(String(format: "%.3f", spatial.echoInputGain)):out_gain=\(workingGain):delays=\(delays):decays=\(decays)"
            guard let echo = createFilter(graph: graph, name: "aecho", label: "reverb", args: args),
                  let restoreGain = createFilter(
                    graph: graph, name: "volume", label: "reverb-working-gain",
                    args: "volume=1/\(workingGain):precision=double"
                  ),
                  avfilter_link(lastCtx, 0, echo, 0) >= 0,
                  avfilter_link(echo, 0, restoreGain, 0) >= 0 else {
                destroyGraphUnsafe()
                return
            }
            lastCtx = restoreGain
        }

        // 单声道听感：先下混，再复制到稳定的双声道输出总线。
        // StreamPlayer 的 Mono 总线固定为 stereo，滤镜不能在播放途中改变声道数。
        if monoEnabled && channelCount > 1 {
            // 根据声道数生成混音公式
            let monoExpression: String
            switch channelCount {
            case 2:
                monoExpression = "0.5*c0+0.5*c1"
            case 6:
                // 5.1: FL, FR, FC, LFE, BL, BR
                // 标准 5.1 下混公式
                monoExpression = "0.2*c0+0.2*c1+0.3*c2+0.1*c3+0.1*c4+0.1*c5"
            case 8:
                // 7.1: FL, FR, FC, LFE, BL, BR, SL, SR
                monoExpression = "0.15*c0+0.15*c1+0.25*c2+0.05*c3+0.1*c4+0.1*c5+0.1*c6+0.1*c7"
            default:
                // 通用：所有声道等权重混合
                let weight = 1.0 / Float(channelCount)
                let channels = (0..<channelCount).map { "\(String(format: "%.3f", weight))*c\($0)" }.joined(separator: "+")
                monoExpression = channels
            }
            let monoMixArgs = "stereo|c0=\(monoExpression)|c1=\(monoExpression)"
            if let ctx = createFilter(graph: graph, name: "pan", label: "mono", args: monoMixArgs) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 新增：空间音效滤镜 ====================

        // Bauer 立体声转双耳（bs2b）- 改善耳机听感
        if bs2bEnabled && channelCount == 2 {
            let args = "fcut=\(bs2bFcut):feed=\(bs2bFeed)"
            if let ctx = createFilter(graph: graph, name: "bs2b", label: "bs2b", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 耳机交叉馈送（crossfeed）- 使用 stereotools 实现
        if crossfeedEnabled && channelCount == 2 {
            // 使用 stereotools 的 balance 参数模拟交叉馈送
            let args = "balance_in=\(String(format: "%.2f", crossfeedStrength)):balance_out=\(String(format: "%.2f", crossfeedStrength * 0.5))"
            if let ctx = createFilter(graph: graph, name: "stereotools", label: "crossfeed", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // Haas 效果（haas）- 增加空间感
        if haasEnabled && channelCount == 2 {
            let args = "level_in=1:level_out=1:side_gain=1:middle_source=mid:middle_phase=false:left_delay=\(String(format: "%.1f", haasDelay)):left_balance=-1:left_gain=1:left_phase=false:right_delay=0:right_balance=1:right_gain=1:right_phase=false"
            if let ctx = createFilter(graph: graph, name: "haas", label: "haas", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 虚拟低音（virtualbass）- 通过谐波生成低音感
        if virtualbassEnabled {
            let args = "cutoff=\(String(format: "%.0f", virtualbassCutoff)):strength=\(String(format: "%.1f", virtualbassStrength))"
            if let ctx = createFilter(graph: graph, name: "virtualbass", label: "virtualbass", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 新增：音色处理滤镜 ====================

        // 激励器（aexciter）- 增加高频泛音
        if exciterEnabled {
            let args = "level_in=1:level_out=1:amount=\(String(format: "%.1f", exciterAmount)):drive=1:blend=0:freq=\(String(format: "%.0f", exciterFreq)):ceil=9999:listen=false"
            if let ctx = createFilter(graph: graph, name: "aexciter", label: "aexciter", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 软削波（asoftclip）- 温暖的失真
        if softclipEnabled {
            let typeNames = ["tanh", "atan", "cubic", "exp", "alg", "quintic", "sin", "erf"]
            let typeName = typeNames[min(softclipType, typeNames.count - 1)]
            let args = "type=\(typeName):threshold=1:output=1:param=1:oversample=1"
            if let ctx = createFilter(graph: graph, name: "asoftclip", label: "asoftclip", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 对话增强（dialoguenhance）- 增强人声清晰度
        if dialogueEnhanceEnabled && channelCount == 2 {
            let args = "original=\(String(format: "%.1f", dialogueEnhanceOriginal)):enhance=\(String(format: "%.1f", dialogueEnhanceEnhance))"
            if let ctx = createFilter(graph: graph, name: "dialoguenhance", label: "dialoguenhance", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 特殊效果 ====================
        
        // 合唱（使用更平滑的参数）
        if chorusEnabled {
            // 降低深度和速度，使用更保守的参数避免电流声
            let depth = 0.2 + chorusDepth * 0.4  // 更保守的深度
            let args = "in_gain=0.6:out_gain=0.8:delays=25|35|45:decays=\(String(format: "%.2f", depth))|\(String(format: "%.2f", depth * 0.85))|\(String(format: "%.2f", depth * 0.7)):speeds=0.2|0.25|0.3:depths=1.5|1.8|1.2"
            if let ctx = createFilter(graph: graph, name: "chorus", label: "chorus", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 镶边（使用更平滑的参数）
        if flangerEnabled {
            // 降低深度和 regen，使用更平滑的插值
            let depth = 1.5 + flangerDepth * 4.0  // 更保守的深度
            let args = "delay=1:depth=\(String(format: "%.1f", depth)):regen=0:width=50:speed=0.3:shape=sinusoidal:phase=50:interp=quadratic"
            if let ctx = createFilter(graph: graph, name: "flanger", label: "flanger", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 颤音（优化参数，减少电流声）
        if tremoloEnabled {
            // 使用更平滑的深度参数
            let smoothDepth = tremoloDepth * 0.7  // 降低最大深度
            let args = "f=\(String(format: "%.1f", tremoloFrequency)):d=\(String(format: "%.2f", smoothDepth))"
            if let ctx = createFilter(graph: graph, name: "tremolo", label: "tremolo", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 颤抖（优化参数）
        if vibratoEnabled {
            // 使用更保守的深度
            let smoothDepth = vibratoDepth * 0.6
            let args = "f=\(String(format: "%.1f", vibratoFrequency)):d=\(String(format: "%.2f", smoothDepth))"
            if let ctx = createFilter(graph: graph, name: "vibrato", label: "vibrato", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 失真（Lo-Fi，优化参数减少刺耳感）
        if crusherEnabled {
            // 使用更高的位深和更低的采样降低因子
            let smoothBits = max(crusherBits, 6.0)  // 最低 6 位，避免太刺耳
            let smoothSamples = min(crusherSamples, 8.0)  // 最高 8x 降采样
            let args = "bits=\(String(format: "%.0f", smoothBits)):samples=\(String(format: "%.0f", smoothSamples)):mix=0.8"
            if let ctx = createFilter(graph: graph, name: "acrusher", label: "crusher", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 电话效果（300-3400Hz 带通，优化参数）
        if telephoneEnabled {
            // 使用更平滑的滤波器
            let args = "frequency=1850:width_type=h:width=2800:poles=2"
            if let ctx = createFilter(graph: graph, name: "bandpass", label: "telephone", args: args) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 水下效果（低通 + 混响，使用更平滑的参数）
        if underwaterEnabled {
            // 使用更高的截止频率和更平滑的混响
            if let ctx = createFilter(graph: graph, name: "lowpass", label: "underwater_lp",
                                       args: "frequency=600:poles=2") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
            // 更自然的水下回声
            if let ctx = createFilter(graph: graph, name: "aecho", label: "underwater_echo",
                                       args: "in_gain=0.7:out_gain=0.7:delays=60|120|180:decays=0.35|0.25|0.15") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // 收音机效果（带通 + 轻微失真，优化参数）
        if radioEnabled {
            // 使用更自然的带通
            let args1 = "frequency=1800:width_type=h:width=2500:poles=2"
            if let ctx = createFilter(graph: graph, name: "bandpass", label: "radio_bp", args: args1) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
            // 更轻微的失真
            let args2 = "bits=10:samples=2:mix=0.4"
            if let ctx = createFilter(graph: graph, name: "acrusher", label: "radio_crush", args: args2) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 时间效果 ====================
        
        // 延迟
        if delayMs > 0.0 {
            if let ctx = createFilter(graph: graph, name: "adelay", label: "delay",
                                       args: "delays=\(String(format: "%.0f", delayMs))|0") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 速度与音调 ====================
        
        let effectiveTempo: Float
        if pitchSemitones != 0.0 {
            let pitchRatio = powf(2.0, pitchSemitones / 12.0)

            // 升调时先做防混叠低通，减少高频伪影与“沙沙声”
            if pitchSemitones > 4.0 {
                let nyquist = Float(sampleRate) * 0.5
                let cutoff = max(4500.0, min(nyquist * 0.95 / pitchRatio, nyquist * 0.95))
                if let ctx = createFilter(
                    graph: graph,
                    name: "lowpass",
                    label: "pitch_pre_lp",
                    args: "frequency=\(Int(cutoff)):poles=2"
                ) {
                    guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                    lastCtx = ctx
                }
            }

            let newRate = Int(Float(sampleRate) * pitchRatio)
            if let ctx = createFilter(graph: graph, name: "asetrate", label: "pitch",
                                       args: "r=\(newRate)") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }

            // 显式重采样回原采样率，减少 asetrate 后续链路中的伪影
            if let ctx = createFilter(
                graph: graph,
                name: "aresample",
                label: "pitch_resample",
                args: "sample_rate=\(sampleRate)"
            ) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }

            effectiveTempo = tempo / pitchRatio
        } else {
            effectiveTempo = tempo
        }

        if effectiveTempo != 1.0 {
            var remaining = effectiveTempo
            var atempoIndex = 0
            while remaining != 1.0 {
                let factor: Float
                if remaining > 2.0 {
                    factor = 2.0
                    remaining /= 2.0
                } else if remaining < 0.5 {
                    factor = 0.5
                    remaining /= 0.5
                } else {
                    factor = remaining
                    remaining = 1.0
                }
                if let ctx = createFilter(graph: graph, name: "atempo", label: "atempo\(atempoIndex)",
                                           args: "tempo=\(String(format: "%.4f", factor))") {
                    guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                    lastCtx = ctx
                    atempoIndex += 1
                }
            }
        }

        // 降调较大时去除次声低频，减轻“隆隆声/脏低频”
        if pitchSemitones < -4.0 {
            let hpFreq = Int(max(35.0, min(120.0, (-pitchSemitones - 4.0) * 20.0 + 35.0)))
            if let ctx = createFilter(
                graph: graph,
                name: "highpass",
                label: "pitch_post_hp",
                args: "frequency=\(hpFreq):poles=2"
            ) {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 淡入淡出 ====================
        
        if fadeInDuration > 0.0 {
            let samples = Int(fadeInDuration * Float(sampleRate))
            if let ctx = createFilter(graph: graph, name: "afade", label: "fadein",
                                       args: "type=in:start_sample=0:nb_samples=\(samples)") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        if fadeOutDuration > 0.0 {
            let startSample = Int(fadeOutStartTime * Float(sampleRate))
            let nbSamples = Int(fadeOutDuration * Float(sampleRate))
            if let ctx = createFilter(graph: graph, name: "afade", label: "fadeout",
                                       args: "type=out:start_sample=\(startSample):nb_samples=\(nbSamples)") {
                guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
                lastCtx = ctx
            }
        }

        // ==================== 输出格式 ====================
        
        // 根据声道数获取输出声道布局
        let outputChannelLayout = monoEnabled ? "stereo" : getChannelLayoutString(for: channelCount)
        let aformatArgs = "sample_fmts=flt:sample_rates=\(sampleRate):channel_layouts=\(outputChannelLayout)"
        if let ctx = createFilter(graph: graph, name: "aformat", label: "aformat", args: aformatArgs) {
            guard avfilter_link(lastCtx, 0, ctx, 0) >= 0 else { destroyGraphUnsafe(); return }
            lastCtx = ctx
        }

        // 连接到 sink
        guard avfilter_link(lastCtx, 0, sink, 0) >= 0 else {
            destroyGraphUnsafe()
            return
        }

        // 配置图
        guard avfilter_graph_config(graph, nil) >= 0 else {
            destroyGraphUnsafe()
            return
        }
    }

    /// 创建单个滤镜节点
    private func createFilter(graph: UnsafeMutablePointer<AVFilterGraph>, name: String, label: String, args: String) -> UnsafeMutablePointer<AVFilterContext>? {
        guard let filter = avfilter_get_by_name(name) else { return nil }
        var ctx: UnsafeMutablePointer<AVFilterContext>?
        guard avfilter_graph_create_filter(&ctx, filter, label, args, nil, graph) >= 0 else { return nil }
        return ctx
    }
    
    /// 根据声道数获取 FFmpeg 声道布局字符串
    /// 支持 1-8 声道，包括 5.1 和 7.1 环绕声
    private func getChannelLayoutString(for channels: Int) -> String {
        switch channels {
        case 1:
            return "mono"
        case 2:
            return "stereo"
        case 3:
            return "2.1"  // 立体声 + 低音炮
        case 4:
            return "quad"  // 四声道（前左、前右、后左、后右）
        case 5:
            return "4.1"  // 四声道 + 低音炮
        case 6:
            return "5.1"  // 5.1 环绕声（前左、前右、中置、低音炮、后左、后右）
        case 7:
            return "6.1"  // 6.1 环绕声
        case 8:
            return "7.1"  // 7.1 环绕声
        default:
            // 对于其他声道数，使用通用格式
            // FFmpeg 支持 "Nc" 格式表示 N 个声道
            return "\(channels)c"
        }
    }

    /// 销毁滤镜图（线程安全）
    private func destroyGraph() {
        lock.lock()
        destroyGraphUnsafe()
        lock.unlock()
    }

    /// Used only by an isolated builder or after the final owner releases this instance.
    private func destroyGraphUnsafe() {
        if filterGraph != nil {
            avfilter_graph_free(&filterGraph)
        }
        if pendingFilterGraph != nil {
            avfilter_graph_free(&pendingFilterGraph)
        }
        if retiredFilterGraph != nil {
            avfilter_graph_free(&retiredFilterGraph)
        }
        var prepared = preparedGraph?.graph
        if prepared != nil { avfilter_graph_free(&prepared) }
        preparedGraph = nil
        if retirementMailbox != nil { avfilter_graph_free(&retirementMailbox) }
        filterGraph = nil
        bufferSrcCtx = nil
        bufferSinkCtx = nil
        activeGraphSampleRate = 0
        activeGraphChannelCount = 0
        pendingFilterGraph = nil
        pendingBufferSrcCtx = nil
        pendingBufferSinkCtx = nil
    }
}
