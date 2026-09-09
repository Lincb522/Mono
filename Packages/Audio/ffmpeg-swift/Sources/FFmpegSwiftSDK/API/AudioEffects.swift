// AudioEffects.swift
// FFmpegSwiftSDK
//
// 公开 API：音频效果控制器，提供 50+ 种音频效果。
// 通过 StreamPlayer.audioEffects 访问。

import Foundation

/// Shared by graph construction and headroom accounting on the control side.
struct MonoSpatialFilterParameters {
    let effectiveStereoWidth: Float
    let echoInputGain: Float
    let echoDelays: [Int]
    let echoDecays: [Float]

    init(stereoWidth: Float, surroundLevel: Float, reverbLevel: Float) {
        let width = min(2, max(0, stereoWidth.isFinite ? stereoWidth : 1))
        let surround = min(1, max(0, surroundLevel.isFinite ? surroundLevel : 0))
        let reverb = min(1, max(0, reverbLevel.isFinite ? reverbLevel : 0))
        effectiveStereoWidth = Self.roundedCoefficient(min(1.85, max(0.65, width * (1 + surround * 0.55))))
        guard reverb > 0 else {
            echoInputGain = 1
            echoDelays = []
            echoDecays = []
            return
        }
        echoInputGain = Self.roundedCoefficient(1 - reverb * 0.18)
        let firstReflection = 0.02 + reverb * 0.62
        let tail = max(0, reverb - 0.18) * 0.55
        var decays = [firstReflection, firstReflection * 0.72, firstReflection * 0.50, firstReflection * 0.34]
        if tail > 0.005 {
            echoDelays = [29, 53, 89, 137, 191, 251]
            decays += [tail, tail * 0.62]
        } else {
            echoDelays = [29, 53, 89, 137]
        }
        echoDecays = decays.map(Self.roundedCoefficient)
    }

    var peakGain: Float {
        // M/S widening has row-sum norm max(1, width). aecho applies in_gain
        // only to the dry sample, so the reflection gains are added separately.
        max(1, effectiveStereoWidth) * (echoInputGain + echoDecays.reduce(0, +))
    }

    var peakBoostDB: Float { max(0, 20 * log10f(peakGain)) }

    func echoWorkingGain(upstreamBoostDB: Float) -> Float {
        // aecho clips even floating-point samples internally. Work below that
        // boundary, then undo this scale in a double-precision volume filter.
        // The extra factor of four reserves 12 dB for filter transients; it
        // cancels after aecho and does not change the requested effect level.
        1 / (4 * max(1, peakGain) * powf(10, max(0, upstreamBoostDB) / 20))
    }

    private static func roundedCoefficient(_ value: Float) -> Float {
        (value * 1_000).rounded() / 1_000
    }
}

/// Parameters that Mono can commit to the FFmpeg effect graph in one rebuild.
/// Final output limiting is applied separately by AudioRepairEngine after EQ.
public struct MonoEffectTuningConfiguration: Codable, Equatable, Sendable {
    public var loudnessNormalizationEnabled: Bool
    public var targetLUFS: Float
    public var targetLRA: Float
    public var truePeakCeilingDB: Float
    public var compressorEnabled: Bool
    public var compressorThresholdDB: Float
    public var compressorRatio: Float
    public var compressorAttackMS: Float
    public var compressorReleaseMS: Float
    public var compressorMakeupDB: Float
    public var subboostEnabled: Bool
    public var subboostGainDB: Float
    public var subboostCutoffHz: Float
    public var bs2bEnabled: Bool
    public var bs2bCutoffHz: Int
    public var bs2bFeed: Int
    public var crossfeedEnabled: Bool
    public var crossfeedStrength: Float
    public var haasEnabled: Bool
    public var haasDelayMS: Float
    public var virtualBassEnabled: Bool
    public var virtualBassCutoffHz: Float
    public var virtualBassStrength: Float
    public var exciterEnabled: Bool
    public var exciterAmountDB: Float
    public var exciterFrequencyHz: Float
    public var softclipEnabled: Bool
    public var softclipType: Int
    public var finalLimiterEnabled: Bool
    public var finalLimiterCeilingDB: Float

    public init(
        loudnessNormalizationEnabled: Bool = false,
        targetLUFS: Float = -14,
        targetLRA: Float = 9,
        truePeakCeilingDB: Float = -1,
        compressorEnabled: Bool = false,
        compressorThresholdDB: Float = -18,
        compressorRatio: Float = 2,
        compressorAttackMS: Float = 18,
        compressorReleaseMS: Float = 180,
        compressorMakeupDB: Float = 0,
        subboostEnabled: Bool = false,
        subboostGainDB: Float = 0,
        subboostCutoffHz: Float = 90,
        bs2bEnabled: Bool = false,
        bs2bCutoffHz: Int = 700,
        bs2bFeed: Int = 50,
        crossfeedEnabled: Bool = false,
        crossfeedStrength: Float = 0.2,
        haasEnabled: Bool = false,
        haasDelayMS: Float = 12,
        virtualBassEnabled: Bool = false,
        virtualBassCutoffHz: Float = 180,
        virtualBassStrength: Float = 0,
        exciterEnabled: Bool = false,
        exciterAmountDB: Float = 0,
        exciterFrequencyHz: Float = 7_500,
        softclipEnabled: Bool = false,
        softclipType: Int = 0,
        finalLimiterEnabled: Bool = true,
        finalLimiterCeilingDB: Float = -1
    ) {
        self.loudnessNormalizationEnabled = loudnessNormalizationEnabled
        self.targetLUFS = targetLUFS
        self.targetLRA = targetLRA
        self.truePeakCeilingDB = truePeakCeilingDB
        self.compressorEnabled = compressorEnabled
        self.compressorThresholdDB = compressorThresholdDB
        self.compressorRatio = compressorRatio
        self.compressorAttackMS = compressorAttackMS
        self.compressorReleaseMS = compressorReleaseMS
        self.compressorMakeupDB = compressorMakeupDB
        self.subboostEnabled = subboostEnabled
        self.subboostGainDB = subboostGainDB
        self.subboostCutoffHz = subboostCutoffHz
        self.bs2bEnabled = bs2bEnabled
        self.bs2bCutoffHz = bs2bCutoffHz
        self.bs2bFeed = bs2bFeed
        self.crossfeedEnabled = crossfeedEnabled
        self.crossfeedStrength = crossfeedStrength
        self.haasEnabled = haasEnabled
        self.haasDelayMS = haasDelayMS
        self.virtualBassEnabled = virtualBassEnabled
        self.virtualBassCutoffHz = virtualBassCutoffHz
        self.virtualBassStrength = virtualBassStrength
        self.exciterEnabled = exciterEnabled
        self.exciterAmountDB = exciterAmountDB
        self.exciterFrequencyHz = exciterFrequencyHz
        self.softclipEnabled = softclipEnabled
        self.softclipType = softclipType
        self.finalLimiterEnabled = finalLimiterEnabled
        self.finalLimiterCeilingDB = finalLimiterCeilingDB
    }

    private enum CodingKeys: String, CodingKey {
        case loudnessNormalizationEnabled
        case targetLUFS
        case targetLRA
        case truePeakCeilingDB
        case compressorEnabled
        case compressorThresholdDB
        case compressorRatio
        case compressorAttackMS
        case compressorReleaseMS
        case compressorMakeupDB
        case subboostEnabled
        case subboostGainDB
        case subboostCutoffHz
        case bs2bEnabled
        case bs2bCutoffHz
        case bs2bFeed
        case crossfeedEnabled
        case crossfeedStrength
        case haasEnabled
        case haasDelayMS
        case virtualBassEnabled
        case virtualBassCutoffHz
        case virtualBassStrength
        case exciterEnabled
        case exciterAmountDB
        case exciterFrequencyHz
        case softclipEnabled
        case softclipType
        case finalLimiterEnabled
        case finalLimiterCeilingDB
    }

    /// AI providers and older persisted presets may omit parameters that are
    /// disabled or did not exist when the value was written. Missing values are
    /// neutral defaults instead of making the entire tuning plan undecodable.
    public init(from decoder: any Swift.Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MonoEffectTuningConfiguration()
        self.init(
            loudnessNormalizationEnabled: try values.decodeIfPresent(Bool.self, forKey: .loudnessNormalizationEnabled) ?? defaults.loudnessNormalizationEnabled,
            targetLUFS: try values.decodeIfPresent(Float.self, forKey: .targetLUFS) ?? defaults.targetLUFS,
            targetLRA: try values.decodeIfPresent(Float.self, forKey: .targetLRA) ?? defaults.targetLRA,
            truePeakCeilingDB: try values.decodeIfPresent(Float.self, forKey: .truePeakCeilingDB) ?? defaults.truePeakCeilingDB,
            compressorEnabled: try values.decodeIfPresent(Bool.self, forKey: .compressorEnabled) ?? defaults.compressorEnabled,
            compressorThresholdDB: try values.decodeIfPresent(Float.self, forKey: .compressorThresholdDB) ?? defaults.compressorThresholdDB,
            compressorRatio: try values.decodeIfPresent(Float.self, forKey: .compressorRatio) ?? defaults.compressorRatio,
            compressorAttackMS: try values.decodeIfPresent(Float.self, forKey: .compressorAttackMS) ?? defaults.compressorAttackMS,
            compressorReleaseMS: try values.decodeIfPresent(Float.self, forKey: .compressorReleaseMS) ?? defaults.compressorReleaseMS,
            compressorMakeupDB: try values.decodeIfPresent(Float.self, forKey: .compressorMakeupDB) ?? defaults.compressorMakeupDB,
            subboostEnabled: try values.decodeIfPresent(Bool.self, forKey: .subboostEnabled) ?? defaults.subboostEnabled,
            subboostGainDB: try values.decodeIfPresent(Float.self, forKey: .subboostGainDB) ?? defaults.subboostGainDB,
            subboostCutoffHz: try values.decodeIfPresent(Float.self, forKey: .subboostCutoffHz) ?? defaults.subboostCutoffHz,
            bs2bEnabled: try values.decodeIfPresent(Bool.self, forKey: .bs2bEnabled) ?? defaults.bs2bEnabled,
            bs2bCutoffHz: try values.decodeIfPresent(Int.self, forKey: .bs2bCutoffHz) ?? defaults.bs2bCutoffHz,
            bs2bFeed: try values.decodeIfPresent(Int.self, forKey: .bs2bFeed) ?? defaults.bs2bFeed,
            crossfeedEnabled: try values.decodeIfPresent(Bool.self, forKey: .crossfeedEnabled) ?? defaults.crossfeedEnabled,
            crossfeedStrength: try values.decodeIfPresent(Float.self, forKey: .crossfeedStrength) ?? defaults.crossfeedStrength,
            haasEnabled: try values.decodeIfPresent(Bool.self, forKey: .haasEnabled) ?? defaults.haasEnabled,
            haasDelayMS: try values.decodeIfPresent(Float.self, forKey: .haasDelayMS) ?? defaults.haasDelayMS,
            virtualBassEnabled: try values.decodeIfPresent(Bool.self, forKey: .virtualBassEnabled) ?? defaults.virtualBassEnabled,
            virtualBassCutoffHz: try values.decodeIfPresent(Float.self, forKey: .virtualBassCutoffHz) ?? defaults.virtualBassCutoffHz,
            virtualBassStrength: try values.decodeIfPresent(Float.self, forKey: .virtualBassStrength) ?? defaults.virtualBassStrength,
            exciterEnabled: try values.decodeIfPresent(Bool.self, forKey: .exciterEnabled) ?? defaults.exciterEnabled,
            exciterAmountDB: try values.decodeIfPresent(Float.self, forKey: .exciterAmountDB) ?? defaults.exciterAmountDB,
            exciterFrequencyHz: try values.decodeIfPresent(Float.self, forKey: .exciterFrequencyHz) ?? defaults.exciterFrequencyHz,
            softclipEnabled: try values.decodeIfPresent(Bool.self, forKey: .softclipEnabled) ?? defaults.softclipEnabled,
            softclipType: try values.decodeIfPresent(Int.self, forKey: .softclipType) ?? defaults.softclipType,
            finalLimiterEnabled: try values.decodeIfPresent(Bool.self, forKey: .finalLimiterEnabled) ?? defaults.finalLimiterEnabled,
            finalLimiterCeilingDB: try values.decodeIfPresent(Float.self, forKey: .finalLimiterCeilingDB) ?? defaults.finalLimiterCeilingDB
        )
    }

    /// Removes legacy realtime processors that are not stable enough for the
    /// main music playback graph. Haas is retained as the bounded spatial
    /// profile stage; tone, spatial values and output limiting are applied
    /// separately and remain untouched.
    public var realtimePlaybackSafe: MonoEffectTuningConfiguration {
        var configuration = self
        configuration.loudnessNormalizationEnabled = false
        configuration.compressorEnabled = false
        configuration.subboostEnabled = false
        configuration.bs2bEnabled = false
        configuration.crossfeedEnabled = false
        configuration.virtualBassEnabled = false
        configuration.exciterEnabled = false
        configuration.softclipEnabled = false
        return configuration
    }

    public static let neutral = MonoEffectTuningConfiguration(finalLimiterEnabled: false)
}

/// 音频效果控制器，封装 FFmpeg avfilter 提供的完整音频处理能力。
///
/// 支持以下效果分类：
/// - 基础音量控制
/// - 动态处理（压缩、限幅、噪声门、自动增益、响度标准化）
/// - 速度与音调（变速不变调、变调不变速）
/// - 均衡器与频率（低音、高音、超低音、带通、带阻）
/// - 空间效果（环绕、混响、立体声宽度、声道平衡、单声道）
/// - 时间效果（淡入淡出、延迟）
/// - 特殊效果（人声消除、合唱、镶边、颤音、失真、电话/水下/收音机效果）
///
/// 通过 `StreamPlayer.audioEffects` 访问：
/// ```swift
/// let player = StreamPlayer()
/// player.audioEffects.setVolume(3.0)           // +3dB
/// player.audioEffects.setTempo(1.5)            // 1.5x 倍速
/// player.audioEffects.setVocalRemoval(0.8)     // 人声消除
/// player.audioEffects.setNightModeEnabled(true) // 夜间模式
/// ```
public final class AudioEffects {

    internal let filterGraph: AudioFilterGraph

    internal init(filterGraph: AudioFilterGraph) {
        self.filterGraph = filterGraph
    }

    /// Commits all automatic mastering and enhancement parameters atomically,
    /// causing at most one FFmpeg graph rebuild.
    public func applyMonoTuning(_ configuration: MonoEffectTuningConfiguration) {
        filterGraph.applyMonoTuning(configuration.realtimePlaybackSafe)
    }

    /// Commits the complete AI playback plan under one graph lock. This keeps
    /// the render thread from rebuilding once for every tone/spatial property.
    public func applyMonoTuning(
        _ configuration: MonoEffectTuningConfiguration,
        bassGain: Float,
        trebleGain: Float,
        surroundLevel: Float,
        reverbLevel: Float,
        stereoWidth: Float
    ) {
        filterGraph.applyMonoTuning(
            configuration.realtimePlaybackSafe,
            bassGain: bassGain,
            trebleGain: trebleGain,
            surroundLevel: surroundLevel,
            reverbLevel: reverbLevel,
            stereoWidth: stereoWidth
        )
    }

    // MARK: - 基础音量控制

    /// 设置音量增益（dB）。0 = 不变，正值增大，负值减小。
    public func setVolume(_ db: Float) {
        filterGraph.setVolume(0)
    }

    /// 当前音量增益（dB）
    public var volume: Float {
        0
    }

    // MARK: - 动态处理

    /// 启用/禁用响度标准化（EBU R128）。
    /// 开启后，不同歌曲的音量会被标准化到统一响度。
    public func setLoudnormEnabled(_ enabled: Bool) {
        filterGraph.setLoudnormEnabled(enabled)
    }

    /// 响度标准化是否启用
    public var isLoudnormEnabled: Bool {
        filterGraph.loudnormEnabled
    }

    /// 设置 loudnorm 参数
    /// - Parameters:
    ///   - targetLUFS: 目标响度（LUFS），默认 -14.0（Spotify 标准）
    ///   - lra: 响度范围（LRA），默认 11.0
    ///   - truePeak: 真峰值限制（dBTP），默认 -1.0
    public func setLoudnormParams(targetLUFS: Float = -14.0, lra: Float = 11.0, truePeak: Float = -1.0) {
        filterGraph.setLoudnormParams(targetLUFS: targetLUFS, lra: lra, truePeak: truePeak)
    }

    /// 启用/禁用夜间模式（动态压缩）。
    /// 压缩动态范围，让响的变轻、轻的变响，适合夜间低音量听歌。
    public func setNightModeEnabled(_ enabled: Bool) {
        filterGraph.setCompressorEnabled(enabled)
    }

    /// 夜间模式是否启用
    public var isNightModeEnabled: Bool {
        filterGraph.compressorEnabled
    }

    /// 设置动态压缩参数
    /// - Parameters:
    ///   - threshold: 阈值（dB），默认 -20.0
    ///   - ratio: 压缩比，默认 4.0
    ///   - attack: 启动时间（ms），默认 5.0
    ///   - release: 释放时间（ms），默认 50.0
    ///   - makeup: 补偿增益（dB），默认 2.0
    public func setCompressorParams(threshold: Float = -20.0, ratio: Float = 4.0, attack: Float = 5.0, release: Float = 50.0, makeup: Float = 2.0) {
        filterGraph.setCompressorParams(threshold: threshold, ratio: ratio, attack: attack, release: release, makeup: makeup)
    }

    /// 启用/禁用限幅器。防止音量过大导致削波失真。
    public func setLimiterEnabled(_ enabled: Bool) {
        filterGraph.setLimiterEnabled(enabled)
    }

    /// 限幅器是否启用
    public var isLimiterEnabled: Bool {
        filterGraph.limiterEnabled
    }

    /// 设置限幅器阈值（dBFS），默认 -1.0
    public func setLimiterLimit(_ limit: Float) {
        filterGraph.setLimiterLimit(limit)
    }

    /// 启用/禁用噪声门。低于阈值的信号会被静音。
    public func setGateEnabled(_ enabled: Bool) {
        filterGraph.setGateEnabled(enabled)
    }

    /// 噪声门是否启用
    public var isGateEnabled: Bool {
        filterGraph.gateEnabled
    }

    /// 设置噪声门阈值（dB），默认 -40.0
    public func setGateThreshold(_ threshold: Float) {
        filterGraph.setGateThreshold(threshold)
    }

    /// 启用/禁用自动增益（动态标准化）。
    /// 自动调整音量，让整首歌的响度更均匀。
    public func setAutoGainEnabled(_ enabled: Bool) {
        filterGraph.setAutoGainEnabled(enabled)
    }

    /// 自动增益是否启用
    public var isAutoGainEnabled: Bool {
        filterGraph.autoGainEnabled
    }

    // MARK: - 速度与音调

    /// 设置播放速度倍率（变速不变调）。
    /// - Parameter rate: 速度倍率，范围 [0.5, 4.0]。1.0 = 原速。
    public func setTempo(_ rate: Float) {
        filterGraph.setTempo(rate)
    }

    /// 当前播放速度倍率
    public var tempo: Float {
        filterGraph.tempo
    }

    /// 设置变调（半音数，变调不变速）。
    /// - Parameter semitones: 半音数，范围 [-12, +12]。0 = 不变调。
    public func setPitch(_ semitones: Float) {
        filterGraph.setPitchSemitones(semitones)
    }

    /// 当前变调值（半音数）
    public var pitchSemitones: Float {
        filterGraph.pitchSemitones
    }

    // MARK: - 均衡器与频率

    /// 设置低音增益（dB）。
    /// - Parameter db: 增益值，范围 [-12, +12]。0 = 不变。
    public func setBassGain(_ db: Float) {
        filterGraph.setBassGain(db)
    }

    /// 当前低音增益（dB）
    public var bassGain: Float {
        filterGraph.bassGain
    }

    /// 设置高音增益（dB）。
    /// - Parameter db: 增益值，范围 [-12, +12]。0 = 不变。
    public func setTrebleGain(_ db: Float) {
        filterGraph.setTrebleGain(db)
    }

    /// 当前高音增益（dB）
    public var trebleGain: Float {
        filterGraph.trebleGain
    }

    /// 启用/禁用超低音增强。增强 100Hz 以下的超低频。
    public func setSubboostEnabled(_ enabled: Bool) {
        filterGraph.setSubboostEnabled(enabled)
    }

    /// 超低音增强是否启用
    public var isSubboostEnabled: Bool {
        filterGraph.subboostEnabled
    }

    /// 设置超低音增强参数
    /// - Parameters:
    ///   - gain: 增益（dB），默认 6.0
    ///   - cutoff: 截止频率（Hz），默认 100.0
    public func setSubboostParams(gain: Float = 6.0, cutoff: Float = 100.0) {
        filterGraph.setSubboostParams(gain: gain, cutoff: cutoff)
    }

    /// 启用/禁用带通滤波。只保留指定频率范围的声音。
    public func setBandpassEnabled(_ enabled: Bool) {
        filterGraph.setBandpassEnabled(enabled)
    }

    /// 带通滤波是否启用
    public var isBandpassEnabled: Bool {
        filterGraph.bandpassEnabled
    }

    /// 设置带通滤波参数
    /// - Parameters:
    ///   - frequency: 中心频率（Hz）
    ///   - width: 带宽（Hz）
    public func setBandpassParams(frequency: Float, width: Float) {
        filterGraph.setBandpassParams(frequency: frequency, width: width)
    }

    /// 启用/禁用带阻滤波。去除指定频率范围的声音。
    public func setBandrejectEnabled(_ enabled: Bool) {
        filterGraph.setBandrejectEnabled(enabled)
    }

    /// 带阻滤波是否启用
    public var isBandrejectEnabled: Bool {
        filterGraph.bandrejectEnabled
    }

    /// 设置带阻滤波参数
    /// - Parameters:
    ///   - frequency: 中心频率（Hz）
    ///   - width: 带宽（Hz）
    public func setBandrejectParams(frequency: Float, width: Float) {
        filterGraph.setBandrejectParams(frequency: frequency, width: width)
    }

    // MARK: - 空间效果

    /// 设置环绕强度。增强立体声分离度。
    /// - Parameter level: 强度 0~1。0 = 关闭，1 = 最大环绕。
    public func setSurroundLevel(_ level: Float) {
        filterGraph.setSurroundLevel(level)
    }

    /// 当前环绕强度（0~1）
    public var surroundLevel: Float {
        filterGraph.surroundLevel
    }

    /// 设置混响强度。模拟房间混响效果。
    /// - Parameter level: 强度 0~1。0 = 关闭，1 = 最大混响。
    public func setReverbLevel(_ level: Float) {
        filterGraph.setReverbLevel(level)
    }

    /// 当前混响强度（0~1）
    public var reverbLevel: Float {
        filterGraph.reverbLevel
    }

    /// 设置立体声宽度。
    /// - Parameter width: 宽度 0~2。0 = 单声道，1.0 = 原始，2.0 = 最宽。
    public func setStereoWidth(_ width: Float) {
        filterGraph.setStereoWidth(width)
    }

    /// 当前立体声宽度
    public var stereoWidth: Float {
        filterGraph.stereoWidth
    }

    /// Peak bound of the width/early-reflection cascade, including the same
    /// rounded coefficients used by the FFmpeg graph. Does not estimate loudness.
    public var estimatedSpatialPeakBoostDB: Float {
        MonoSpatialFilterParameters(
            stereoWidth: stereoWidth,
            surroundLevel: surroundLevel,
            reverbLevel: reverbLevel
        ).peakBoostDB
    }

    /// 设置声道平衡。
    /// - Parameter balance: -1 = 全左，0 = 居中，+1 = 全右。
    public func setChannelBalance(_ balance: Float) {
        filterGraph.setChannelBalance(balance)
    }

    /// 当前声道平衡
    public var channelBalance: Float {
        filterGraph.channelBalance
    }

    /// 启用/禁用单声道模式。将立体声混合为单声道。
    public func setMonoEnabled(_ enabled: Bool) {
        filterGraph.setMonoEnabled(enabled)
    }

    /// 单声道模式是否启用
    public var isMonoEnabled: Bool {
        filterGraph.monoEnabled
    }

    /// 启用/禁用声道交换。交换左右声道。
    public func setChannelSwapEnabled(_ enabled: Bool) {
        filterGraph.setChannelSwapEnabled(enabled)
    }

    /// 声道交换是否启用
    public var isChannelSwapEnabled: Bool {
        filterGraph.channelSwapEnabled
    }

    // MARK: - 时间效果

    /// 设置淡入效果。歌曲开头音量从 0 渐变到正常。
    /// - Parameter duration: 淡入时长（秒），0 = 关闭。
    public func setFadeIn(duration: Float) {
        filterGraph.setFadeIn(duration: duration)
    }

    /// 当前淡入时长（秒）
    public var fadeInDuration: Float {
        filterGraph.fadeInDuration
    }

    /// 设置淡出效果。歌曲结尾音量从正常渐变到 0。
    /// - Parameters:
    ///   - duration: 淡出时长（秒），0 = 关闭。
    ///   - startTime: 淡出开始的时间点（秒）。
    public func setFadeOut(duration: Float, startTime: Float) {
        filterGraph.setFadeOut(duration: duration, startTime: startTime)
    }

    /// 当前淡出时长（秒）
    public var fadeOutDuration: Float {
        filterGraph.fadeOutDuration
    }

    /// 设置延迟（毫秒）。给左声道添加延迟，产生空间感。
    /// - Parameter ms: 延迟时间（毫秒），0 = 关闭。
    public func setDelay(_ ms: Float) {
        filterGraph.setDelay(ms)
    }

    /// 当前延迟（毫秒）
    public var delayMs: Float {
        filterGraph.delayMs
    }

    // MARK: - 特殊效果

    /// 设置人声消除强度（卡拉OK 模式）。
    /// 通过消除立体声中置信号来去除人声。
    /// - Parameter level: 强度 0~1。0 = 关闭，1 = 最大消除。
    public func setVocalRemoval(_ level: Float) {
        filterGraph.setVocalRemoval(level)
    }

    /// 当前人声消除强度（0~1）
    public var vocalRemovalLevel: Float {
        filterGraph.vocalRemovalLevel
    }

    /// 启用/禁用合唱效果。产生多声部叠加的丰富音色。
    public func setChorusEnabled(_ enabled: Bool) {
        filterGraph.setChorusEnabled(enabled)
    }

    /// 合唱效果是否启用
    public var isChorusEnabled: Bool {
        filterGraph.chorusEnabled
    }

    /// 设置合唱深度（0~1）
    public func setChorusDepth(_ depth: Float) {
        filterGraph.setChorusDepth(depth)
    }

    /// 当前合唱深度
    public var chorusDepth: Float {
        filterGraph.chorusDepth
    }

    /// 启用/禁用镶边效果。产生梳状滤波扫描的金属感。
    public func setFlangerEnabled(_ enabled: Bool) {
        filterGraph.setFlangerEnabled(enabled)
    }

    /// 镶边效果是否启用
    public var isFlangerEnabled: Bool {
        filterGraph.flangerEnabled
    }

    /// 设置镶边深度（0~1）
    public func setFlangerDepth(_ depth: Float) {
        filterGraph.setFlangerDepth(depth)
    }

    /// 当前镶边深度
    public var flangerDepth: Float {
        filterGraph.flangerDepth
    }

    /// 启用/禁用颤音效果。音量周期性变化。
    public func setTremoloEnabled(_ enabled: Bool) {
        filterGraph.setTremoloEnabled(enabled)
    }

    /// 颤音效果是否启用
    public var isTremoloEnabled: Bool {
        filterGraph.tremoloEnabled
    }

    /// 设置颤音参数
    /// - Parameters:
    ///   - frequency: 频率（Hz），默认 5.0
    ///   - depth: 深度（0~1），默认 0.5
    public func setTremoloParams(frequency: Float = 5.0, depth: Float = 0.5) {
        filterGraph.setTremoloParams(frequency: frequency, depth: depth)
    }

    /// 启用/禁用颤抖效果。音调周期性变化。
    public func setVibratoEnabled(_ enabled: Bool) {
        filterGraph.setVibratoEnabled(enabled)
    }

    /// 颤抖效果是否启用
    public var isVibratoEnabled: Bool {
        filterGraph.vibratoEnabled
    }

    /// 设置颤抖参数
    /// - Parameters:
    ///   - frequency: 频率（Hz），默认 5.0
    ///   - depth: 深度（0~1），默认 0.5
    public func setVibratoParams(frequency: Float = 5.0, depth: Float = 0.5) {
        filterGraph.setVibratoParams(frequency: frequency, depth: depth)
    }

    /// 启用/禁用失真效果（Lo-Fi）。降低位深和采样率产生复古效果。
    public func setLoFiEnabled(_ enabled: Bool) {
        filterGraph.setCrusherEnabled(enabled)
    }

    /// 失真效果是否启用
    public var isLoFiEnabled: Bool {
        filterGraph.crusherEnabled
    }

    /// 设置失真参数
    /// - Parameters:
    ///   - bits: 位深（1~16），默认 8.0
    ///   - samples: 采样率降低因子（1~16），默认 4.0
    public func setLoFiParams(bits: Float = 8.0, samples: Float = 4.0) {
        filterGraph.setCrusherParams(bits: bits, samples: samples)
    }

    /// 启用/禁用电话效果。模拟电话音质（300-3400Hz 带通）。
    public func setTelephoneEnabled(_ enabled: Bool) {
        filterGraph.setTelephoneEnabled(enabled)
    }

    /// 电话效果是否启用
    public var isTelephoneEnabled: Bool {
        filterGraph.telephoneEnabled
    }

    /// 启用/禁用水下效果。模拟水下声音（低通 + 混响）。
    public func setUnderwaterEnabled(_ enabled: Bool) {
        filterGraph.setUnderwaterEnabled(enabled)
    }

    /// 水下效果是否启用
    public var isUnderwaterEnabled: Bool {
        filterGraph.underwaterEnabled
    }

    /// 启用/禁用收音机效果。模拟老式收音机音质。
    public func setRadioEnabled(_ enabled: Bool) {
        filterGraph.setRadioEnabled(enabled)
    }

    /// 收音机效果是否启用
    public var isRadioEnabled: Bool {
        filterGraph.radioEnabled
    }

    // MARK: - 音频修复

    /// 启用/禁用 FFT 降噪。基于 FFT 的智能降噪，适合去除背景噪声。
    public func setFFTDenoiseEnabled(_ enabled: Bool) {
        filterGraph.setFFTDenoiseEnabled(enabled)
    }

    /// FFT 降噪是否启用
    public var isFFTDenoiseEnabled: Bool {
        filterGraph.fftDenoiseEnabled
    }

    /// 设置 FFT 降噪量（dB），范围 0~100，默认 10
    public func setFFTDenoiseAmount(_ amount: Float) {
        filterGraph.setFFTDenoiseAmount(amount)
    }

    /// 当前 FFT 降噪量
    public var fftDenoiseAmount: Float {
        filterGraph.fftDenoiseAmount
    }

    /// 启用/禁用去除脉冲噪声（Declick）。去除黑胶唱片的爆音。
    public func setDeclickEnabled(_ enabled: Bool) {
        filterGraph.setDeclickEnabled(enabled)
    }

    /// 去除脉冲噪声是否启用
    public var isDeclickEnabled: Bool {
        filterGraph.declickEnabled
    }

    /// 启用/禁用去除削波失真（Declip）。修复过载录音的削波。
    public func setDeclipEnabled(_ enabled: Bool) {
        filterGraph.setDeclipEnabled(enabled)
    }

    /// 去除削波失真是否启用
    public var isDeclipEnabled: Bool {
        filterGraph.declipEnabled
    }

    // MARK: - 高级动态处理

    /// 启用/禁用动态音频标准化（Dynaudnorm）。
    /// 比 loudnorm 更适合实时处理，响应更快。
    public func setDynaudnormEnabled(_ enabled: Bool) {
        filterGraph.setDynaudnormEnabled(enabled)
    }

    /// 动态音频标准化是否启用
    public var isDynaudnormEnabled: Bool {
        filterGraph.dynaudnormEnabled
    }

    /// 设置动态音频标准化参数
    /// - Parameters:
    ///   - frameLen: 帧长度（ms），默认 500
    ///   - gaussSize: 高斯窗口大小，默认 31
    ///   - peak: 目标峰值（0~1），默认 0.95
    public func setDynaudnormParams(frameLen: Int = 500, gaussSize: Int = 31, peak: Float = 0.95) {
        filterGraph.setDynaudnormParams(frameLen: frameLen, gaussSize: gaussSize, peak: peak)
    }

    /// 启用/禁用语音标准化（Speechnorm）。专为语音内容优化的标准化。
    public func setSpeechnormEnabled(_ enabled: Bool) {
        filterGraph.setSpeechnormEnabled(enabled)
    }

    /// 语音标准化是否启用
    public var isSpeechnormEnabled: Bool {
        filterGraph.speechnormEnabled
    }

    /// 启用/禁用压缩/扩展（Compand）。更灵活的动态范围控制。
    public func setCompandEnabled(_ enabled: Bool) {
        filterGraph.setCompandEnabled(enabled)
    }

    /// 压缩/扩展是否启用
    public var isCompandEnabled: Bool {
        filterGraph.compandEnabled
    }

    // MARK: - 耳机优化

    /// 启用/禁用 Bauer 立体声转双耳（BS2B）。
    /// 改善耳机听感，减少头中效应。
    public func setBS2BEnabled(_ enabled: Bool) {
        filterGraph.setBS2BEnabled(enabled)
    }

    /// BS2B 是否启用
    public var isBS2BEnabled: Bool {
        filterGraph.bs2bEnabled
    }

    /// 设置 BS2B 参数
    /// - Parameters:
    ///   - fcut: 截止频率（Hz），默认 700
    ///   - feed: 馈送量（0.1dB 单位），默认 50
    public func setBS2BParams(fcut: Int = 700, feed: Int = 50) {
        filterGraph.setBS2BParams(fcut: fcut, feed: feed)
    }

    /// 启用/禁用耳机交叉馈送（Crossfeed）。
    /// 模拟扬声器听感，减少耳机疲劳。
    public func setCrossfeedEnabled(_ enabled: Bool) {
        filterGraph.setCrossfeedEnabled(enabled)
    }

    /// 交叉馈送是否启用
    public var isCrossfeedEnabled: Bool {
        filterGraph.crossfeedEnabled
    }

    /// 设置交叉馈送强度（0~1），默认 0.3
    public func setCrossfeedStrength(_ strength: Float) {
        filterGraph.setCrossfeedStrength(strength)
    }

    /// 当前交叉馈送强度
    public var crossfeedStrength: Float {
        filterGraph.crossfeedStrength
    }

    /// 启用/禁用 Haas 效果。通过微小延迟增加空间感。
    public func setHaasEnabled(_ enabled: Bool) {
        filterGraph.setHaasEnabled(enabled)
    }

    /// Haas 效果是否启用
    public var isHaasEnabled: Bool {
        filterGraph.haasEnabled
    }

    /// 设置 Haas 延迟（ms），范围 0~40，默认 20
    public func setHaasDelay(_ delay: Float) {
        filterGraph.setHaasDelay(delay)
    }

    /// 当前 Haas 延迟
    public var haasDelay: Float {
        filterGraph.haasDelay
    }

    // MARK: - 低音增强

    /// 启用/禁用虚拟低音（Virtualbass）。
    /// 通过谐波生成在小扬声器上产生低音感。
    public func setVirtualbassEnabled(_ enabled: Bool) {
        filterGraph.setVirtualbassEnabled(enabled)
    }

    /// 虚拟低音是否启用
    public var isVirtualbassEnabled: Bool {
        filterGraph.virtualbassEnabled
    }

    /// 设置虚拟低音参数
    /// - Parameters:
    ///   - cutoff: 截止频率（Hz），默认 250
    ///   - strength: 强度，默认 3.0
    public func setVirtualbassParams(cutoff: Float = 250.0, strength: Float = 3.0) {
        filterGraph.setVirtualbassParams(cutoff: cutoff, strength: strength)
    }

    // MARK: - 音色处理

    /// 启用/禁用激励器（Exciter）。增加高频泛音，让声音更明亮。
    public func setExciterEnabled(_ enabled: Bool) {
        filterGraph.setExciterEnabled(enabled)
    }

    /// 激励器是否启用
    public var isExciterEnabled: Bool {
        filterGraph.exciterEnabled
    }

    /// 设置激励器参数
    /// - Parameters:
    ///   - amount: 激励量（dB），默认 3.0
    ///   - freq: 起始频率（Hz），默认 7500
    public func setExciterParams(amount: Float = 3.0, freq: Float = 7500.0) {
        filterGraph.setExciterParams(amount: amount, freq: freq)
    }

    /// 启用/禁用软削波（Softclip）。产生温暖的模拟失真。
    public func setSoftclipEnabled(_ enabled: Bool) {
        filterGraph.setSoftclipEnabled(enabled)
    }

    /// 软削波是否启用
    public var isSoftclipEnabled: Bool {
        filterGraph.softclipEnabled
    }

    /// 设置软削波类型
    /// - Parameter type: 0=tanh, 1=atan, 2=cubic, 3=exp, 4=alg, 5=quintic, 6=sin, 7=erf
    public func setSoftclipType(_ type: Int) {
        filterGraph.setSoftclipType(type)
    }

    /// 当前软削波类型
    public var softclipType: Int {
        filterGraph.softclipType
    }

    /// 启用/禁用对话增强（Dialogue Enhance）。增强人声清晰度。
    public func setDialogueEnhanceEnabled(_ enabled: Bool) {
        filterGraph.setDialogueEnhanceEnabled(enabled)
    }

    /// 对话增强是否启用
    public var isDialogueEnhanceEnabled: Bool {
        filterGraph.dialogueEnhanceEnabled
    }

    /// 设置对话增强参数
    /// - Parameters:
    ///   - original: 原始信号混合量，默认 1.0
    ///   - enhance: 增强信号混合量，默认 1.0
    public func setDialogueEnhanceParams(original: Float = 1.0, enhance: Float = 1.0) {
        filterGraph.setDialogueEnhanceParams(original: original, enhance: enhance)
    }

    // MARK: - 重置

    /// 重置所有音频效果到默认值
    public func reset() {
        filterGraph.reset()
    }

    /// 是否有任何效果处于激活状态
    public var isActive: Bool {
        filterGraph.isActive
    }

    /// Starts an isolated live-filter session. The complete filter state is
    /// restored when the session ends.
    public func beginDiagnosticSession() -> AudioEffectsDiagnosticSession {
        AudioEffectsDiagnosticSession(filterGraph: filterGraph)
    }
}

/// Individually addressable FFmpeg audio paths exposed to the developer lab.
public enum AudioEffectsDiagnosticKind: String, CaseIterable, Sendable {
    case volume
    case loudness
    case compressor
    case limiter
    case noiseGate
    case autoGain
    case tempo
    case pitch
    case bass
    case treble
    case subBass
    case bandPass
    case bandReject
    case surround
    case reverb
    case stereoWidth
    case channelBalance
    case mono
    case channelSwap
    case fadeIn
    case fadeOut
    case delay
    case vocalRemoval
    case chorus
    case flanger
    case tremolo
    case vibrato
    case loFi
    case telephone
    case underwater
    case radio
    case fftDenoise
    case declick
    case declip
    case dynamicNormalize
    case speechNormalize
    case compand
    case bs2b
    case crossfeed
    case haas
    case virtualBass
    case exciter
    case softclip
    case dialogueEnhance
}

/// An opaque, reversible live-audio experiment. Each `apply` call isolates
/// one FFmpeg path so dry/effect A/B comparisons remain meaningful.
public final class AudioEffectsDiagnosticSession: @unchecked Sendable {
    private let filterGraph: AudioFilterGraph
    private let snapshot: AudioFilterGraph
    private let workingConfiguration = AudioFilterGraph()
    private let stateLock = NSLock()
    private var hasRestored = false

    internal init(filterGraph: AudioFilterGraph) {
        self.filterGraph = filterGraph
        snapshot = filterGraph.makeDiagnosticConfigurationSnapshot()
    }

    deinit {
        restore()
    }

    public func apply(
        _ effect: AudioEffectsDiagnosticKind,
        values: [Float],
        enabled: Bool
    ) {
        stateLock.lock()
        guard !hasRestored else {
            stateLock.unlock()
            return
        }
        defer { stateLock.unlock() }

        let liveFilterGraph = self.filterGraph
        let filterGraph = workingConfiguration
        filterGraph.reset()
        guard enabled else {
            liveFilterGraph.restoreDiagnosticConfiguration(from: filterGraph)
            return
        }

        func value(_ index: Int, _ fallback: Float) -> Float {
            values.indices.contains(index) ? values[index] : fallback
        }

        switch effect {
        case .volume:
            filterGraph.setVolume(value(0, 3))
        case .loudness:
            filterGraph.setLoudnormParams(
                targetLUFS: value(0, -14),
                lra: value(1, 7),
                truePeak: value(2, -1)
            )
            filterGraph.setLoudnormEnabled(true)
        case .compressor:
            filterGraph.setCompressorParams(
                threshold: value(0, -20),
                ratio: value(1, 4),
                attack: value(2, 5),
                release: value(3, 50),
                makeup: value(4, 2)
            )
            filterGraph.setCompressorEnabled(true)
        case .limiter:
            filterGraph.setLimiterLimit(value(0, -1))
            filterGraph.setLimiterEnabled(true)
        case .noiseGate:
            filterGraph.setGateThreshold(value(0, -40))
            filterGraph.setGateEnabled(true)
        case .autoGain:
            filterGraph.setAutoGainEnabled(true)
        case .tempo:
            filterGraph.setTempo(value(0, 1))
        case .pitch:
            filterGraph.setPitchSemitones(value(0, 0))
        case .bass:
            filterGraph.setBassGain(value(0, 4))
        case .treble:
            filterGraph.setTrebleGain(value(0, 4))
        case .subBass:
            filterGraph.setSubboostParams(gain: value(0, 6), cutoff: value(1, 100))
            filterGraph.setSubboostEnabled(true)
        case .bandPass:
            filterGraph.setBandpassParams(frequency: value(0, 1_000), width: value(1, 2_000))
            filterGraph.setBandpassEnabled(true)
        case .bandReject:
            filterGraph.setBandrejectParams(frequency: value(0, 1_000), width: value(1, 200))
            filterGraph.setBandrejectEnabled(true)
        case .surround:
            filterGraph.setSurroundLevel(value(0, 0.45))
        case .reverb:
            filterGraph.setReverbLevel(value(0, 0.3))
        case .stereoWidth:
            filterGraph.setStereoWidth(value(0, 1.4))
        case .channelBalance:
            filterGraph.setChannelBalance(value(0, 0))
        case .mono:
            filterGraph.setMonoEnabled(true)
        case .channelSwap:
            filterGraph.setChannelSwapEnabled(true)
        case .fadeIn:
            filterGraph.setFadeIn(duration: value(0, 3))
            filterGraph.resetProcessedSamples()
        case .fadeOut:
            filterGraph.setFadeOut(duration: value(0, 3), startTime: value(1, 0))
            filterGraph.resetProcessedSamples()
        case .delay:
            filterGraph.setDelay(value(0, 20))
        case .vocalRemoval:
            filterGraph.setVocalRemoval(value(0, 0.7))
        case .chorus:
            filterGraph.setChorusDepth(value(0, 0.5))
            filterGraph.setChorusEnabled(true)
        case .flanger:
            filterGraph.setFlangerDepth(value(0, 0.5))
            filterGraph.setFlangerEnabled(true)
        case .tremolo:
            filterGraph.setTremoloParams(frequency: value(0, 5), depth: value(1, 0.5))
            filterGraph.setTremoloEnabled(true)
        case .vibrato:
            filterGraph.setVibratoParams(frequency: value(0, 5), depth: value(1, 0.5))
            filterGraph.setVibratoEnabled(true)
        case .loFi:
            filterGraph.setCrusherParams(bits: value(0, 8), samples: value(1, 4))
            filterGraph.setCrusherEnabled(true)
        case .telephone:
            filterGraph.setTelephoneEnabled(true)
        case .underwater:
            filterGraph.setUnderwaterEnabled(true)
        case .radio:
            filterGraph.setRadioEnabled(true)
        case .fftDenoise:
            filterGraph.setFFTDenoiseAmount(value(0, 10))
            filterGraph.setFFTDenoiseEnabled(true)
        case .declick:
            filterGraph.setDeclickEnabled(true)
        case .declip:
            filterGraph.setDeclipEnabled(true)
        case .dynamicNormalize:
            filterGraph.setDynaudnormParams(
                frameLen: Int(value(0, 500).rounded()),
                gaussSize: Int(value(1, 31).rounded()),
                peak: value(2, 0.95)
            )
            filterGraph.setDynaudnormEnabled(true)
        case .speechNormalize:
            filterGraph.setSpeechnormEnabled(true)
        case .compand:
            filterGraph.setCompandEnabled(true)
        case .bs2b:
            filterGraph.setBS2BParams(
                fcut: Int(value(0, 700).rounded()),
                feed: Int(value(1, 50).rounded())
            )
            filterGraph.setBS2BEnabled(true)
        case .crossfeed:
            filterGraph.setCrossfeedStrength(value(0, 0.3))
            filterGraph.setCrossfeedEnabled(true)
        case .haas:
            filterGraph.setHaasDelay(value(0, 20))
            filterGraph.setHaasEnabled(true)
        case .virtualBass:
            filterGraph.setVirtualbassParams(cutoff: value(0, 250), strength: value(1, 3))
            filterGraph.setVirtualbassEnabled(true)
        case .exciter:
            filterGraph.setExciterParams(amount: value(0, 3), freq: value(1, 7_500))
            filterGraph.setExciterEnabled(true)
        case .softclip:
            filterGraph.setSoftclipType(Int(value(0, 0).rounded()))
            filterGraph.setSoftclipEnabled(true)
        case .dialogueEnhance:
            filterGraph.setDialogueEnhanceParams(original: value(0, 1), enhance: value(1, 1))
            filterGraph.setDialogueEnhanceEnabled(true)
        }
        liveFilterGraph.restoreDiagnosticConfiguration(from: filterGraph)
    }

    public func restore() {
        stateLock.lock()
        guard !hasRestored else {
            stateLock.unlock()
            return
        }
        hasRestored = true
        stateLock.unlock()
        filterGraph.restoreDiagnosticConfiguration(from: snapshot)
    }

    public func restoreAsynchronously() {
        stateLock.lock()
        guard !hasRestored else {
            stateLock.unlock()
            return
        }
        hasRestored = true
        let liveFilterGraph = filterGraph
        let savedSnapshot = snapshot
        stateLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            liveFilterGraph.restoreDiagnosticConfiguration(from: savedSnapshot)
        }
    }
}
