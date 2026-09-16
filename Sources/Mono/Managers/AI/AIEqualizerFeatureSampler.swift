import Foundation
import FFmpegSwiftSDK
import UIKit

private struct AIEqualizerSamplingDiagnostics: Sendable {
    let callbackFrames: Int
    let acceptedFrames: Int
    let invalidShapeFrames: Int
    let invalidValueFrames: Int
    let silentFrames: Int
    let emptySpectrumFrames: Int
    let lastBinCount: Int
    let lastSampleRate: Double
    let lastRMS: Float
    let pcmFrames: Int
    let pcmChannelCount: Int
    let pcmSampleRate: Double
    let pcmSamplePeak: Float

    var logText: String {
        String(
            format: "callbacks=%d accepted=%d invalidShape=%d invalidValue=%d silent=%d emptySpectrum=%d lastBins=%d sampleRate=%.0f lastRMS=%.6f pcmFrames=%d pcmChannels=%d pcmRate=%.0f pcmPeak=%.6f",
            callbackFrames,
            acceptedFrames,
            invalidShapeFrames,
            invalidValueFrames,
            silentFrames,
            emptySpectrumFrames,
            lastBinCount,
            lastSampleRate,
            lastRMS,
            pcmFrames,
            pcmChannelCount,
            pcmSampleRate,
            pcmSamplePeak
        )
    }
}

private actor AIEqualizerSpectrumAccumulator {
    struct PCMCaptureProfile: Sendable, Equatable {
        let targetSampleRate: Double
        let maximumDuration: Double
        let estimatesTruePeak: Bool

        static let normal = PCMCaptureProfile(
            targetSampleRate: 10_000,
            maximumDuration: 36,
            estimatesTruePeak: false
        )

        static let protected = PCMCaptureProfile(
            targetSampleRate: 10_000,
            maximumDuration: 24,
            estimatesTruePeak: false
        )
    }

    private let mode: GraphicEQMode
    private let centers: [Float]
    private let pcmCaptureProfile: PCMCaptureProfile

    private var bandDBFrames: [[Float]]
    private var centroidFrames: [Float] = []
    private var rolloffFrames: [Float] = []
    private var flatnessFrames: [Float] = []
    private var bandwidthFrames: [Float] = []
    private var spectralFluxFrames: [Float] = []
    private var samplingTimestamps: [TimeInterval] = []
    private var dominantPitchFrames: [(timestamp: TimeInterval, frequency: Float, confidence: Float)] = []
    private var lowEnergyRatioFrames: [Float] = []
    private var midEnergyRatioFrames: [Float] = []
    private var highEnergyRatioFrames: [Float] = []
    private var accumulatedChroma = Array(repeating: Float(0), count: 12)
    private var previousNormalizedSpectrum: [Float]?
    private var rmsDBFrames: [Float] = []
    private var pcmAnalysisSamples: [Float] = []
    private var pcmAnalysisSampleRate: Double = 12_000
    private var pcmChannelCount = 1
    private var pcmSourceSampleCount = 0
    private var pcmClippedSampleCount = 0
    private var pcmSamplePeak: Float = 0
    private var pcmEstimatedTruePeak: Float = 0
    private var latestSampleRate: Double = 44_100
    private var callbackFrames = 0
    private var invalidShapeFrames = 0
    private var invalidValueFrames = 0
    private var silentFrames = 0
    private var emptySpectrumFrames = 0
    private var lastBinCount = 0
    private var lastRMS: Float = 0
    private(set) var frameCount = 0

    init(mode: GraphicEQMode, pcmCaptureProfile: PCMCaptureProfile = .normal) {
        self.mode = mode
        self.pcmCaptureProfile = pcmCaptureProfile
        centers = mode.centerFrequencies
        bandDBFrames = Array(repeating: [], count: mode.bandCount)
    }

    func ingest(
        magnitudes: [Float],
        sampleRate: Double,
        rms: Float,
        timestamp: TimeInterval
    ) {
        callbackFrames += 1
        lastBinCount = magnitudes.count
        lastRMS = rms
        guard magnitudes.count > 16 else {
            invalidShapeFrames += 1
            return
        }
        guard sampleRate.isFinite, sampleRate > 0, rms.isFinite else {
            invalidValueFrames += 1
            return
        }
        latestSampleRate = sampleRate

        let binHz = Float(sampleRate) / Float(magnitudes.count * 2)
        var bandPower = Array(repeating: Float(0), count: centers.count)
        var bandWeights = Array(repeating: Float(0), count: centers.count)
        var totalPower: Float = 0
        var weightedPower: Float = 0
        var squaredFrequencyPower: Float = 0
        var lowPower: Float = 0
        var midPower: Float = 0
        var highPower: Float = 0
        var frameChroma = Array(repeating: Float(0), count: 12)
        var frequencyPowers: [(frequency: Float, power: Float)] = []
        frequencyPowers.reserveCapacity(magnitudes.count)

        for (index, magnitude) in magnitudes.enumerated() {
            guard magnitude.isFinite else { continue }
            let frequency = Float(index) * binHz
            guard frequency >= 20, frequency <= 20_000 else { continue }
            let power = max(magnitude * magnitude, 1e-20)
            totalPower += power
            weightedPower += frequency * power
            squaredFrequencyPower += frequency * frequency * power
            frequencyPowers.append((frequency, power))

            switch frequency {
            case ..<250:
                lowPower += power
            case 250..<4_000:
                midPower += power
            default:
                highPower += power
            }

            if frequency >= 55, frequency <= 5_000 {
                let midi = Int((69 + 12 * log2f(frequency / 440)).rounded())
                let pitchClass = (midi % 12 + 12) % 12
                // Log-compressed harmonic energy prevents a single loud overtone
                // from dominating the key estimate for the whole capture.
                frameChroma[pitchClass] += sqrtf(power) / sqrtf(max(frequency, 55))
            }
            for contribution in interpolatedBands(for: frequency) {
                bandPower[contribution.index] += power * contribution.weight
                bandWeights[contribution.index] += contribution.weight
            }
        }

        let rmsDB = 20 * log10f(max(rms, 1e-8))
        guard rmsDB > -72 else {
            silentFrames += 1
            return
        }
        guard totalPower.isFinite, totalPower > 1e-18, !frequencyPowers.isEmpty else {
            emptySpectrumFrames += 1
            return
        }
        var frameBandDB = Array(repeating: Float(-80), count: centers.count)
        for index in centers.indices where bandWeights[index] > 0 {
            let meanPower = bandPower[index] / bandWeights[index]
            frameBandDB[index] = 10 * log10f(max(meanPower, 1e-20))
        }
        for index in centers.indices {
            // Keep absolute band levels until final aggregation. Normalizing each
            // frame independently gave quiet passages the same weight as choruses
            // and changed the apparent tonal balance.
            bandDBFrames[index].append(frameBandDB[index])
        }

        let centroid = weightedPower / totalPower
        centroidFrames.append(centroid)
        rolloffFrames.append(Self.rolloffFrequency(frequencyPowers: frequencyPowers, ratio: 0.85))
        let variance = max(0, squaredFrequencyPower / totalPower - centroid * centroid)
        bandwidthFrames.append(sqrtf(variance))

        let normalizedSpectrum = frequencyPowers.map { $0.power / totalPower }
        if let previousNormalizedSpectrum,
           previousNormalizedSpectrum.count == normalizedSpectrum.count {
            let flux = zip(normalizedSpectrum, previousNormalizedSpectrum).reduce(Float(0)) {
                $0 + max(0, $1.0 - $1.1)
            }
            spectralFluxFrames.append(flux)
        } else {
            spectralFluxFrames.append(0)
        }
        previousNormalizedSpectrum = normalizedSpectrum
        samplingTimestamps.append(timestamp)

        lowEnergyRatioFrames.append(lowPower / totalPower)
        midEnergyRatioFrames.append(midPower / totalPower)
        highEnergyRatioFrames.append(highPower / totalPower)
        let chromaEnergy = frameChroma.reduce(0, +)
        if chromaEnergy > 0 {
            for index in accumulatedChroma.indices {
                accumulatedChroma[index] += sqrtf(max(0, frameChroma[index] / chromaEnergy))
            }
        }
        let melodyPeak = Self.dominantMelodyPeak(
            magnitudes: magnitudes,
            binHz: binHz,
            totalPower: totalPower
        )
        if melodyPeak.confidence >= 0.004, melodyPeak.frequency > 0 {
            dominantPitchFrames.append((timestamp, melodyPeak.frequency, melodyPeak.confidence))
        }

        let arithmeticMean = frequencyPowers.reduce(Float(0)) { $0 + $1.power } / Float(frequencyPowers.count)
        let logMean = frequencyPowers.reduce(Float(0)) { $0 + logf(max($1.power, 1e-20)) } / Float(frequencyPowers.count)
        flatnessFrames.append(arithmeticMean > 0 ? min(1, expf(logMean) / arithmeticMean) : 0)
        rmsDBFrames.append(rmsDB)
        frameCount += 1
    }

    func ingestPCM(
        leftSamples: [Float],
        rightSamples: [Float]?,
        sampleRate: Double
    ) {
        guard sampleRate.isFinite, sampleRate > 0, !leftSamples.isEmpty else { return }
        let count = min(leftSamples.count, rightSamples?.count ?? leftSamples.count)
        guard count > 3 else { return }

        let resolvedChannelCount = rightSamples == nil ? 1 : 2
        let downsampleStride = max(1, Int((sampleRate / pcmCaptureProfile.targetSampleRate).rounded()))
        let reducedRate = sampleRate / Double(downsampleStride)
        if pcmAnalysisSamples.isEmpty {
            pcmChannelCount = resolvedChannelCount
            pcmAnalysisSampleRate = reducedRate
            pcmAnalysisSamples.reserveCapacity(
                Int(min(pcmCaptureProfile.maximumDuration, 24) * reducedRate) * resolvedChannelCount
            )
        } else if pcmChannelCount != resolvedChannelCount
                    || abs(pcmAnalysisSampleRate - reducedRate) > 1 {
            // Audio-route format changes invalidate phase and loudness history.
            pcmAnalysisSamples.removeAll(keepingCapacity: true)
            pcmChannelCount = resolvedChannelCount
            pcmAnalysisSampleRate = reducedRate
            pcmSourceSampleCount = 0
            pcmClippedSampleCount = 0
            pcmSamplePeak = 0
            pcmEstimatedTruePeak = 0
        }

        let maximumStoredFrames = Int(pcmCaptureProfile.maximumDuration * pcmAnalysisSampleRate)
        for index in 0..<count {
            let left = leftSamples[index]
            let right = rightSamples?[index] ?? left
            guard left.isFinite, right.isFinite else { continue }
            pcmSourceSampleCount += resolvedChannelCount
            pcmSamplePeak = max(pcmSamplePeak, max(abs(left), abs(right)))
            if abs(left) >= 0.999 { pcmClippedSampleCount += 1 }
            if resolvedChannelCount == 2, abs(right) >= 0.999 { pcmClippedSampleCount += 1 }

            if pcmCaptureProfile.estimatesTruePeak, index >= 1, index + 2 < count {
                pcmEstimatedTruePeak = max(
                    pcmEstimatedTruePeak,
                    Self.estimatedIntersamplePeak(
                        previous: leftSamples[index - 1],
                        start: left,
                        end: leftSamples[index + 1],
                        next: leftSamples[index + 2]
                    )
                )
                if let rightSamples {
                    pcmEstimatedTruePeak = max(
                        pcmEstimatedTruePeak,
                        Self.estimatedIntersamplePeak(
                            previous: rightSamples[index - 1],
                            start: right,
                            end: rightSamples[index + 1],
                            next: rightSamples[index + 2]
                        )
                    )
                }
            }

            guard index % downsampleStride == 0,
                  pcmAnalysisSamples.count / resolvedChannelCount < maximumStoredFrames else { continue }
            pcmAnalysisSamples.append(left)
            if resolvedChannelCount == 2 { pcmAnalysisSamples.append(right) }
        }
    }

    func diagnostics() -> AIEqualizerSamplingDiagnostics {
        AIEqualizerSamplingDiagnostics(
            callbackFrames: callbackFrames,
            acceptedFrames: frameCount,
            invalidShapeFrames: invalidShapeFrames,
            invalidValueFrames: invalidValueFrames,
            silentFrames: silentFrames,
            emptySpectrumFrames: emptySpectrumFrames,
            lastBinCount: lastBinCount,
            lastSampleRate: latestSampleRate,
            lastRMS: lastRMS,
            pcmFrames: pcmAnalysisSamples.count / max(pcmChannelCount, 1),
            pcmChannelCount: pcmChannelCount,
            pcmSampleRate: pcmAnalysisSampleRate,
            pcmSamplePeak: pcmSamplePeak
        )
    }

    func makeFeatures(
        songID: Int,
        title: String,
        artist: String,
        source: String,
        outputDevice: String,
        outputKind: String,
        currentBassGain: Float,
        currentTrebleGain: Float,
        currentSurroundLevel: Float,
        currentReverbLevel: Float,
        currentStereoWidth: Float,
        professionalProcessingIntensity: Float,
        outputCalibrationEnabled: Bool,
        loudnessMatchingEnabled: Bool,
        smartSongCompensationEnabled: Bool,
        dynamicEQEnabled: Bool,
        multibandDynamicsEnabled: Bool,
        parametricEQEnabled: Bool,
        duration: Double,
        minimumFrames: Int
    ) throws -> AIEqualizerAudioFeatures {
        // 门槛必须与采样循环的 minimumValidFrames 一致：受保护低频采样
        // （录屏/沉浸模式）可能以 16 帧合法收尾，这里再卡 48 会把已判定
        // 成功的采样翻案成 sampleUnavailable。
        guard frameCount >= max(16, minimumFrames) else { throw AIEqualizerError.sampleUnavailable }

        let measuredBandLevels = bandDBFrames.map {
            Self.trimmedMean($0, trimFraction: 0.12)
        }
        let absoluteBandLevels = Self.fillingUnresolvedEdgeBands(measuredBandLevels)
        let bandReference = absoluteBandLevels.max() ?? 0
        let bands = absoluteBandLevels.map {
            min(0, max(-60, $0 - bandReference))
        }
        let bandEnergySpreadDB = bandDBFrames.map { frames -> Float in
            let sorted = frames.sorted()
            return min(40, max(0, Self.percentile(sorted, 0.90) - Self.percentile(sorted, 0.10)))
        }
        let sectionBandEnergyDB = Self.sectionBandProfiles(
            bandFrames: bandDBFrames,
            fallback: bands,
            sectionCount: 3
        )
        let sortedRMS = rmsDBFrames.sorted()
        let p10 = Self.percentile(sortedRMS, 0.10)
        let p50 = Self.percentile(sortedRMS, 0.50)
        let p90 = Self.percentile(sortedRMS, 0.90)
        let rmsMean = Self.trimmedMean(rmsDBFrames, trimFraction: 0.10)
        let flatness = min(1, max(0, Self.trimmedMean(flatnessFrames, trimFraction: 0.12)))
        let centroid = Self.trimmedMean(centroidFrames, trimFraction: 0.12)
        let dynamicSpread = max(0, p90 - p10)
        let lowRatio = min(1, max(0, Self.trimmedMean(lowEnergyRatioFrames, trimFraction: 0.1)))
        let midRatio = min(1, max(0, Self.trimmedMean(midEnergyRatioFrames, trimFraction: 0.1)))
        let highRatio = min(1, max(0, Self.trimmedMean(highEnergyRatioFrames, trimFraction: 0.1)))
        // PCM observer windows are sparse. Use timestamped spectral and RMS
        // attacks rather than concatenating non-contiguous PCM blocks.
        let tempo = AIEqualizerTempoEstimator.estimate(
            flux: spectralFluxFrames,
            rmsDB: rmsDBFrames,
            timestamps: samplingTimestamps
        )
        let pcm = Self.analyzePCM(
            samples: pcmAnalysisSamples,
            sampleRate: pcmAnalysisSampleRate,
            channelCount: pcmChannelCount,
            sourceSampleCount: pcmSourceSampleCount,
            clippedSampleCount: pcmClippedSampleCount,
            samplePeak: pcmSamplePeak,
            estimatedTruePeak: pcmEstimatedTruePeak
        )
        let melody = Self.melodyEstimate(samples: dominantPitchFrames)
        let chroma = Self.normalizedChroma(accumulatedChroma)
        let key = Self.keyEstimate(chroma: chroma)
        let spectralFlux = Self.trimmedMean(spectralFluxFrames, trimFraction: 0.1)
        let sortedCentroids = centroidFrames.sorted()
        let sortedRolloffs = rolloffFrames.sorted()
        let sortedFlux = spectralFluxFrames.sorted()
        let activeDuration: TimeInterval
        if let first = samplingTimestamps.first, let last = samplingTimestamps.last, last > first {
            activeDuration = last - first
        } else {
            activeDuration = duration
        }
        let transientDensity = activeDuration > 0
            ? Float(tempo.onsetCount) / Float(activeDuration)
            : 0
        let vocalReference = Self.vocalReference(
            frameCount: frameCount,
            pitchFrames: dominantPitchFrames,
            lowRatio: lowRatio,
            midRatio: midRatio,
            highRatio: highRatio,
            centroid: centroid,
            flatness: flatness,
            dynamicSpread: dynamicSpread,
            melody: melody
        )
        let instrumentScores = Self.instrumentScores(
            lowRatio: lowRatio,
            midRatio: midRatio,
            highRatio: highRatio,
            centroid: centroid,
            flatness: flatness,
            dynamicSpread: dynamicSpread,
            transientDensity: transientDensity,
            melodicActivity: melody.activity
        )
        let instrumentHints = Self.rankedHints(
            instrumentScores.map { (name: $0.key, score: $0.value) },
            threshold: 0.61,
            limit: 4
        )
        let genreScores = Self.genreScores(
            bpm: tempo.bpm,
            tempoConfidence: tempo.confidence,
            tempoStability: tempo.stability,
            lowRatio: lowRatio,
            midRatio: midRatio,
            highRatio: highRatio,
            centroid: centroid,
            flatness: flatness,
            dynamicSpread: dynamicSpread,
            transientDensity: transientDensity,
            melodicActivity: melody.activity
        )
        let genreHints = Self.rankedHints(
            genreScores.map { (name: $0.key, score: $0.value) },
            threshold: 0.60,
            limit: 3
        )

        return AIEqualizerAudioFeatures(
            songID: songID,
            title: title,
            artist: artist,
            source: source,
            outputDevice: outputDevice,
            outputKind: outputKind,
            sampleDuration: duration,
            sampleRate: latestSampleRate,
            frameCount: frameCount,
            graphicEQMode: mode,
            bandFrequenciesHz: centers,
            bandEnergyDB: bands,
            bandEnergySpreadDB: bandEnergySpreadDB,
            sectionBandEnergyDB: sectionBandEnergyDB,
            spectralCentroidHz: centroid,
            spectralRolloffHz: Self.trimmedMean(rolloffFrames, trimFraction: 0.12),
            spectralCentroidP10Hz: Self.percentile(sortedCentroids, 0.10),
            spectralCentroidP90Hz: Self.percentile(sortedCentroids, 0.90),
            spectralRolloffP10Hz: Self.percentile(sortedRolloffs, 0.10),
            spectralRolloffP90Hz: Self.percentile(sortedRolloffs, 0.90),
            rmsDBFS: rmsMean,
            dynamicSpreadDB: dynamicSpread,
            integratedLUFS: pcm.integratedLUFS,
            shortTermLUFS: pcm.shortTermLUFS,
            momentaryLUFS: pcm.momentaryLUFS,
            loudnessRangeLU: pcm.loudnessRangeLU,
            samplePeakDBFS: pcm.samplePeakDBFS,
            estimatedTruePeakDBTP: pcm.estimatedTruePeakDBTP,
            crestFactorDB: pcm.crestFactorDB,
            dynamicRangeDR: pcm.dynamicRangeDR,
            clippingRatio: pcm.clippingRatio,
            phaseCorrelation: pcm.phaseCorrelation,
            monoCompatibility: pcm.monoCompatibility,
            measuredStereoWidth: pcm.stereoWidth,
            spectralFlatness: flatness,
            spectralBandwidthHz: Self.trimmedMean(bandwidthFrames, trimFraction: 0.12),
            spectralFlux: spectralFlux,
            spectralFluxP90: Self.percentile(sortedFlux, 0.90),
            lowEnergyRatio: lowRatio,
            midEnergyRatio: midRatio,
            highEnergyRatio: highRatio,
            estimatedBPM: tempo.bpm,
            tempoConfidence: tempo.confidence,
            tempoStability: tempo.stability,
            estimatedKey: key.name,
            keyConfidence: key.confidence,
            dominantPitchHz: melody.dominantPitch,
            melodyRangeSemitones: melody.rangeSemitones,
            melodicActivity: melody.activity,
            melodyContourHz: melody.contour,
            transientDensity: transientDensity,
            chroma: chroma,
            genreHints: genreHints,
            instrumentHints: instrumentHints,
            genreScores: genreScores,
            instrumentScores: instrumentScores,
            rmsP10DBFS: p10,
            rmsP50DBFS: p50,
            rmsP90DBFS: p90,
            vocalReference: vocalReference,
            currentBassGain: currentBassGain,
            currentTrebleGain: currentTrebleGain,
            currentSurroundLevel: currentSurroundLevel,
            currentReverbLevel: currentReverbLevel,
            currentStereoWidth: currentStereoWidth,
            professionalProcessingIntensity: professionalProcessingIntensity,
            outputCalibrationEnabled: outputCalibrationEnabled,
            loudnessMatchingEnabled: loudnessMatchingEnabled,
            smartSongCompensationEnabled: smartSongCompensationEnabled,
            dynamicEQEnabled: dynamicEQEnabled,
            multibandDynamicsEnabled: multibandDynamicsEnabled,
            parametricEQEnabled: parametricEQEnabled
        )
    }

    private func interpolatedBands(for frequency: Float) -> [(index: Int, weight: Float)] {
        guard centers.count > 1 else { return [(0, 1)] }
        if frequency <= centers[0] { return [(0, 1)] }
        if frequency >= centers[centers.count - 1] { return [(centers.count - 1, 1)] }

        let logFrequency = log2f(max(frequency, 1))
        for upperIndex in 1..<centers.count where frequency <= centers[upperIndex] {
            let lowerIndex = upperIndex - 1
            let lower = log2f(centers[lowerIndex])
            let upper = log2f(centers[upperIndex])
            let fraction = min(1, max(0, (logFrequency - lower) / max(upper - lower, 0.000_1)))
            return [
                (lowerIndex, 1 - fraction),
                (upperIndex, fraction)
            ]
        }
        return [(centers.count - 1, 1)]
    }

    private static func rolloffFrequency(
        frequencyPowers: [(frequency: Float, power: Float)],
        ratio: Float
    ) -> Float {
        let threshold = frequencyPowers.reduce(Float(0)) { $0 + $1.power } * ratio
        var accumulated: Float = 0
        for sample in frequencyPowers {
            accumulated += sample.power
            if accumulated >= threshold {
                return sample.frequency
            }
        }
        return frequencyPowers.last?.frequency ?? 0
    }

    private static func dominantMelodyPeak(
        magnitudes: [Float],
        binHz: Float,
        totalPower: Float
    ) -> (frequency: Float, confidence: Float) {
        guard binHz > 0, totalPower > 0 else { return (0, 0) }
        let lowerBin = max(1, Int(65 / binHz))
        let upperBin = min(magnitudes.count - 2, Int(1_400 / binHz))
        guard lowerBin < upperBin else { return (0, 0) }

        var bestIndex = 0
        var bestScore: Float = 0
        for index in lowerBin...upperBin {
            let base = magnitudes[index] * magnitudes[index]
            guard base / totalPower >= 0.000_08 else { continue }

            // Harmonic summation favors the fundamental even when the second or
            // third harmonic is louder, which substantially reduces octave-high
            // melody estimates on vocals, guitars, and piano.
            var score = base
            var observedHarmonics = 1
            for harmonic in 2...6 {
                let target = index * harmonic
                guard target < magnitudes.count - 1 else { break }
                let neighborhood = max(
                    magnitudes[target - 1] * magnitudes[target - 1],
                    max(
                        magnitudes[target] * magnitudes[target],
                        magnitudes[target + 1] * magnitudes[target + 1]
                    )
                )
                score += neighborhood / Float(harmonic)
                if neighborhood / totalPower >= 0.000_04 {
                    observedHarmonics += 1
                }
            }
            let frequency = Float(index) * binHz
            let registerWeight: Float = frequency >= 85 && frequency <= 1_000 ? 1 : 0.82
            let harmonicEvidence = 0.72 + min(0.28, Float(observedHarmonics - 1) * 0.07)
            score *= registerWeight * harmonicEvidence
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        guard bestIndex > 0, bestScore > 0 else { return (0, 0) }

        // Quadratic interpolation between neighboring FFT bins improves pitch
        // resolution without increasing callback cost.
        let left = logf(max(magnitudes[bestIndex - 1], 1e-12))
        let center = logf(max(magnitudes[bestIndex], 1e-12))
        let right = logf(max(magnitudes[bestIndex + 1], 1e-12))
        let denominator = left - 2 * center + right
        let offset = abs(denominator) > 1e-8
            ? min(0.5, max(-0.5, 0.5 * (left - right) / denominator))
            : 0
        let frequency = (Float(bestIndex) + offset) * binHz
        return (frequency, min(1, bestScore / max(totalPower, 1e-12)))
    }

    private static func estimatedIntersamplePeak(
        previous p0: Float,
        start p1: Float,
        end p2: Float,
        next p3: Float
    ) -> Float {
        var peak = max(abs(p1), abs(p2))
        for step in 1...3 {
            let t = Float(step) / 4
            let t2 = t * t
            let t3 = t2 * t
            let value = 0.5 * (
                2 * p1
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
            )
            peak = max(peak, abs(value))
        }
        return peak
    }

    private struct PCMAnalysisSummary {
        let integratedLUFS: Float
        let shortTermLUFS: Float
        let momentaryLUFS: Float
        let loudnessRangeLU: Float
        let samplePeakDBFS: Float
        let estimatedTruePeakDBTP: Float
        let crestFactorDB: Float
        let dynamicRangeDR: Float
        let clippingRatio: Float
        let phaseCorrelation: Float
        let monoCompatibility: Float
        let stereoWidth: Float

        static let empty = PCMAnalysisSummary(
            integratedLUFS: -70,
            shortTermLUFS: -70,
            momentaryLUFS: -70,
            loudnessRangeLU: 0,
            samplePeakDBFS: -80,
            estimatedTruePeakDBTP: -80,
            crestFactorDB: 0,
            dynamicRangeDR: 0,
            clippingRatio: 0,
            phaseCorrelation: 0,
            monoCompatibility: 0.5,
            stereoWidth: 0
        )
    }

    private static func analyzePCM(
        samples: [Float],
        sampleRate: Double,
        channelCount: Int,
        sourceSampleCount: Int,
        clippedSampleCount: Int,
        samplePeak: Float,
        estimatedTruePeak: Float
    ) -> PCMAnalysisSummary {
        guard sampleRate >= 8_000,
              (1...2).contains(channelCount),
              samples.count >= Int(sampleRate) * channelCount * 2 else {
            return .empty
        }

        let rate = Int(sampleRate.rounded())
        let mono = AudioAnalyzer.convertToMono(samples: samples, channelCount: channelCount)
        let loudness = AudioAnalyzer.measureLoudness(
            samples: samples,
            sampleRate: rate,
            channelCount: channelCount
        )
        let dynamics = AudioAnalyzer.analyzeDynamicRange(samples: mono, sampleRate: rate)
        let phase = channelCount == 2
            ? AudioAnalyzer.detectPhase(samples: samples, sampleRate: rate)
            : nil
        let samplePeakDB = 20 * log10f(max(samplePeak, 0.000_1))
        let truePeakDB = 20 * log10f(max(max(samplePeak, estimatedTruePeak), 0.000_1))

        return PCMAnalysisSummary(
            integratedLUFS: loudness.integratedLUFS.isFinite ? loudness.integratedLUFS : -70,
            shortTermLUFS: loudness.shortTermLUFS.isFinite ? loudness.shortTermLUFS : -70,
            momentaryLUFS: loudness.momentaryLUFS.isFinite ? loudness.momentaryLUFS : -70,
            loudnessRangeLU: max(0, loudness.loudnessRange),
            samplePeakDBFS: samplePeakDB,
            estimatedTruePeakDBTP: truePeakDB,
            crestFactorDB: max(0, dynamics.crestFactor),
            dynamicRangeDR: max(0, dynamics.dynamicRange),
            clippingRatio: sourceSampleCount > 0
                ? Float(clippedSampleCount) / Float(sourceSampleCount)
                : 0,
            phaseCorrelation: phase?.correlation ?? 1,
            monoCompatibility: phase?.monoCompatibility ?? 1,
            stereoWidth: phase?.stereoWidth ?? 0
        )
    }

    private static func melodyEstimate(
        samples: [(timestamp: TimeInterval, frequency: Float, confidence: Float)]
    ) -> (dominantPitch: Float, rangeSemitones: Float, activity: Float, contour: [Float]) {
        let ordered = samples
            .filter {
                $0.timestamp.isFinite
                    && $0.frequency.isFinite
                    && $0.frequency >= 55
                    && $0.frequency <= 2_000
                    && $0.confidence >= 0.004
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 6 else { return (0, 0, 0, []) }

        // Keep the contour in a stable register. Harmonic-rich sources can make
        // adjacent frames alternate between a fundamental and its octave even
        // when the melody did not jump.
        var corrected: [(frequency: Float, confidence: Float)] = []
        corrected.reserveCapacity(ordered.count)
        for sample in ordered {
            var frequency = sample.frequency
            if !corrected.isEmpty {
                let recent = corrected.suffix(7).map(\.frequency).sorted()
                let reference = percentile(recent, 0.50)
                while frequency / max(reference, 1) > 1.72 { frequency /= 2 }
                while reference / max(frequency, 1) > 1.72 { frequency *= 2 }
            }
            corrected.append((frequency, sample.confidence))
        }

        let valid = corrected.map(\.frequency)

        let sorted = valid.sorted()
        let lower = percentile(sorted, 0.12)
        let upper = percentile(sorted, 0.88)
        let dominant = weightedPercentile(corrected, percentile: 0.50)
        let range = upper > lower ? 12 * log2f(upper / lower) : 0
        var pitchDeltas: [Float] = []
        for index in 1..<valid.count {
            let semitoneDelta = abs(12 * log2f(valid[index] / valid[index - 1]))
            if semitoneDelta.isFinite, semitoneDelta <= 12 {
                pitchDeltas.append(semitoneDelta)
            }
        }
        let medianDelta = pitchDeltas.isEmpty ? 0 : percentile(pitchDeltas.sorted(), 0.50)
        let activity = min(1, max(0, medianDelta / 3.5))

        let contourPointCount = min(16, valid.count)
        let contour = (0..<contourPointCount).map { point -> Float in
            let start = point * valid.count / contourPointCount
            let end = max(start + 1, (point + 1) * valid.count / contourPointCount)
            return percentile(Array(valid[start..<min(end, valid.count)]).sorted(), 0.50)
        }
        return (dominant, min(48, max(0, range)), activity, contour)
    }

    private static func weightedPercentile(
        _ values: [(frequency: Float, confidence: Float)],
        percentile target: Float
    ) -> Float {
        let sorted = values.sorted { $0.frequency < $1.frequency }
        let totalWeight = sorted.reduce(Float(0)) { $0 + max(0.000_1, $1.confidence) }
        guard totalWeight > 0 else { return sorted.first?.frequency ?? 0 }
        let threshold = totalWeight * min(1, max(0, target))
        var accumulated: Float = 0
        for value in sorted {
            accumulated += max(0.000_1, value.confidence)
            if accumulated >= threshold { return value.frequency }
        }
        return sorted.last?.frequency ?? 0
    }

    private static func normalizedChroma(_ values: [Float]) -> [Float] {
        let normalized = Array(values.prefix(12))
            + Array(repeating: Float(0), count: max(0, 12 - values.count))
        let total = normalized.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: 12) }
        return normalized.map { min(1, max(0, $0 / total)) }
    }

    private static func keyEstimate(chroma: [Float]) -> (name: String, confidence: Float) {
        guard chroma.count == 12, chroma.reduce(0, +) > 0 else { return ("", 0) }
        let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let pitchClassNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        var scores: [(name: String, score: Float)] = []

        for tonic in 0..<12 {
            let rotated = (0..<12).map { chroma[(tonic + $0) % 12] }
            let majorScore = correlation(rotated, majorProfile)
            let minorScore = correlation(rotated, minorProfile)
            scores.append(("\(pitchClassNames[tonic]) major", majorScore))
            scores.append(("\(pitchClassNames[tonic]) minor", minorScore))
        }

        let ranked = scores.sorted { $0.score > $1.score }
        guard let best = ranked.first else { return ("", 0) }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        let absoluteSupport = min(1, max(0, (best.score + 1) * 0.5))
        let separation = min(1, max(0, (best.score - runnerUp) / 0.18))
        let confidence = absoluteSupport * separation
        return (best.name, confidence)
    }

    private static func correlation(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let lhsMean = lhs.reduce(0, +) / Float(lhs.count)
        let rhsMean = rhs.reduce(0, +) / Float(rhs.count)
        var numerator: Float = 0
        var lhsEnergy: Float = 0
        var rhsEnergy: Float = 0
        for index in lhs.indices {
            let left = lhs[index] - lhsMean
            let right = rhs[index] - rhsMean
            numerator += left * right
            lhsEnergy += left * left
            rhsEnergy += right * right
        }
        let denominator = sqrtf(lhsEnergy * rhsEnergy)
        return denominator > 0 ? numerator / denominator : 0
    }

    private static func instrumentScores(
        lowRatio: Float,
        midRatio: Float,
        highRatio: Float,
        centroid: Float,
        flatness: Float,
        dynamicSpread: Float,
        transientDensity: Float,
        melodicActivity: Float
    ) -> [String: Float] {
        let transient = normalizedEvidence(transientDensity, lower: 0.18, upper: 1.15)
        let low = normalizedEvidence(lowRatio, lower: 0.14, upper: 0.38)
        let mid = normalizedEvidence(midRatio, lower: 0.30, upper: 0.62)
        let high = normalizedEvidence(highRatio, lower: 0.035, upper: 0.20)
        let brightness = normalizedEvidence(centroid, lower: 1_150, upper: 3_500)
        let noisiness = normalizedEvidence(flatness, lower: 0.18, upper: 0.62)
        let tonality = 1 - noisiness
        let dynamics = normalizedEvidence(dynamicSpread, lower: 5, upper: 15)
        let melody = normalizedEvidence(melodicActivity, lower: 0.035, upper: 0.36)

        return Dictionary(uniqueKeysWithValues: [
            ("drums", transient * 0.62 + high * 0.20 + noisiness * 0.18),
            ("bass", low * 0.72 + tonality * 0.18 + (1 - brightness) * 0.10),
            ("vocals", mid * 0.38 + melody * 0.32 + tonality * 0.20 + dynamics * 0.10),
            ("synth", noisiness * 0.42 + high * 0.25 + brightness * 0.18 + melody * 0.15),
            ("guitar", brightness * 0.32 + transient * 0.25 + tonality * 0.25 + mid * 0.18),
            ("piano", dynamics * 0.34 + transient * 0.28 + melody * 0.25 + tonality * 0.13),
            ("strings", mid * 0.38 + melody * 0.30 + (1 - transient) * 0.20 + tonality * 0.12)
        ].map { ($0.0, min(1, max(0, $0.1))) })
    }

    private static func vocalReference(
        frameCount: Int,
        pitchFrames: [(timestamp: TimeInterval, frequency: Float, confidence: Float)],
        lowRatio: Float,
        midRatio: Float,
        highRatio: Float,
        centroid: Float,
        flatness: Float,
        dynamicSpread: Float,
        melody: (dominantPitch: Float, rangeSemitones: Float, activity: Float, contour: [Float])
    ) -> AIEqualizerVocalReferenceFeatures? {
        guard frameCount > 0, !pitchFrames.isEmpty else { return nil }
        let voicedRatio = min(1, Float(pitchFrames.count) / Float(frameCount))
        let pitchEvidence = normalizedEvidence(
            trimmedMean(pitchFrames.map(\.confidence), trimFraction: 0.12),
            lower: 0.004,
            upper: 0.075
        )
        let midEvidence = normalizedEvidence(midRatio, lower: 0.30, upper: 0.62)
        let lowEvidence = normalizedEvidence(lowRatio, lower: 0.12, upper: 0.36)
        let highEvidence = normalizedEvidence(highRatio, lower: 0.03, upper: 0.18)
        let brightnessEvidence = normalizedEvidence(centroid, lower: 1_050, upper: 3_500)
        let noisiness = normalizedEvidence(flatness, lower: 0.16, upper: 0.58)
        let tonality = 1 - noisiness
        let confidence = min(
            1,
            voicedRatio * 0.38 + pitchEvidence * 0.34 + midEvidence * 0.16 + tonality * 0.12
        )
        guard confidence >= 0.28 else { return nil }

        let presence = min(1, midEvidence * 0.48 + voicedRatio * 0.30 + pitchEvidence * 0.22)
        let warmth = min(
            1,
            max(0, lowEvidence * 0.42 + midEvidence * 0.38 + (1 - brightnessEvidence) * 0.20)
        )
        let brightness = min(1, brightnessEvidence * 0.68 + highEvidence * 0.32)
        let airiness = min(1, highEvidence * 0.42 + noisiness * 0.34 + brightnessEvidence * 0.24)
        let dynamicExpression = min(
            1,
            normalizedEvidence(dynamicSpread, lower: 4, upper: 16) * 0.55
                + melody.activity * 0.45
        )
        let register: String
        switch melody.dominantPitch {
        case ...0: register = "unknown"
        case ..<155: register = "low"
        case ..<310: register = "mid"
        default: register = "high"
        }

        return AIEqualizerVocalReferenceFeatures(
            confidence: confidence,
            presence: presence,
            warmth: warmth,
            brightness: brightness,
            airiness: airiness,
            dynamicExpression: dynamicExpression,
            register: register
        )
    }

    private static func genreScores(
        bpm: Float,
        tempoConfidence: Float,
        tempoStability: Float,
        lowRatio: Float,
        midRatio: Float,
        highRatio: Float,
        centroid: Float,
        flatness: Float,
        dynamicSpread: Float,
        transientDensity: Float,
        melodicActivity: Float
    ) -> [String: Float] {
        let reliableTempo = min(1, max(0, tempoConfidence * 0.65 + tempoStability * 0.35))
        let danceTempo = bpm >= 108 && bpm <= 155 ? reliableTempo : 0
        let hiphopTempo = bpm >= 68 && bpm <= 112 ? reliableTempo : 0
        let slowTempo = bpm > 0 && bpm <= 96 ? reliableTempo : 0
        let low = normalizedEvidence(lowRatio, lower: 0.14, upper: 0.38)
        let mid = normalizedEvidence(midRatio, lower: 0.30, upper: 0.62)
        let high = normalizedEvidence(highRatio, lower: 0.035, upper: 0.20)
        let brightness = normalizedEvidence(centroid, lower: 1_150, upper: 3_500)
        let noisiness = normalizedEvidence(flatness, lower: 0.18, upper: 0.62)
        let tonality = 1 - noisiness
        let dynamics = normalizedEvidence(dynamicSpread, lower: 5, upper: 15)
        let transient = normalizedEvidence(transientDensity, lower: 0.18, upper: 1.15)
        let melody = normalizedEvidence(melodicActivity, lower: 0.035, upper: 0.36)
        let spectralBalance = 1 - min(1, abs(lowRatio - 0.23) * 2 + abs(highRatio - 0.10) * 2.5)

        return Dictionary(uniqueKeysWithValues: [
            ("electronic", danceTempo * 0.35 + noisiness * 0.25 + transient * 0.22 + low * 0.18),
            ("hiphop", hiphopTempo * 0.34 + low * 0.34 + transient * 0.20 + (1 - high) * 0.12),
            ("rock", brightness * 0.28 + transient * 0.30 + tonality * 0.20 + dynamics * 0.22),
            ("acoustic", dynamics * 0.34 + tonality * 0.32 + (1 - noisiness) * 0.18 + (1 - low) * 0.16),
            ("ballad", slowTempo * 0.34 + melody * 0.28 + dynamics * 0.20 + (1 - transient) * 0.18),
            ("pop", mid * 0.28 + melody * 0.24 + reliableTempo * 0.18 + spectralBalance * 0.30)
        ].map { ($0.0, min(1, max(0, $0.1))) })
    }

    private static func normalizedEvidence(_ value: Float, lower: Float, upper: Float) -> Float {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }

    private static func rankedHints(
        _ values: [(name: String, score: Float)],
        threshold: Float,
        limit: Int
    ) -> [String] {
        values
            .filter { $0.score >= threshold }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.name)
    }

    private static func sectionBandProfiles(
        bandFrames: [[Float]],
        fallback: [Float],
        sectionCount: Int
    ) -> [[Float]] {
        guard sectionCount > 0,
              !bandFrames.isEmpty,
              let frameCount = bandFrames.map(\.count).min(),
              frameCount >= sectionCount else {
            return Array(repeating: fallback, count: max(0, sectionCount))
        }
        return (0..<sectionCount).map { section in
            let lower = frameCount * section / sectionCount
            let upper = max(lower + 1, frameCount * (section + 1) / sectionCount)
            let measured = bandFrames.map { frames in
                trimmedMean(Array(frames[lower..<min(upper, frames.count)]), trimFraction: 0.1)
            }
            let filled = fillingUnresolvedEdgeBands(measured)
            let reference = filled.max() ?? 0
            return filled.map { min(0, max(-60, $0 - reference)) }
        }
    }

    private static func percentile(_ values: [Float], _ percentile: Float) -> Float {
        guard !values.isEmpty else { return -80 }
        let position = Int((Float(values.count - 1) * percentile).rounded())
        return values[min(values.count - 1, max(0, position))]
    }

    private static func fillingUnresolvedEdgeBands(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }
        var result = values
        for index in result.indices where result[index] <= -79.5 {
            var lower: Int?
            if index > 0 {
                lower = stride(from: index - 1, through: 0, by: -1)
                    .first { result[$0] > -79.5 }
            }
            let upper = ((index + 1)..<result.count)
                .first { result[$0] > -79.5 }
            switch (lower, upper) {
            case let (lower?, upper?):
                let progress = Float(index - lower) / Float(upper - lower)
                result[index] = result[lower] + (result[upper] - result[lower]) * progress
            case let (lower?, nil):
                result[index] = result[lower]
            case let (nil, upper?):
                result[index] = result[upper]
            case (nil, nil):
                break
            }
        }
        return result
    }

    private static func trimmedMean(_ values: [Float], trimFraction: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let trimCount = min(
            max(0, Int(Float(sorted.count) * trimFraction)),
            max(0, (sorted.count - 1) / 2)
        )
        let retained = sorted[trimCount..<(sorted.count - trimCount)]
        return retained.reduce(0, +) / Float(max(1, retained.count))
    }
}

@MainActor
final class AIEqualizerFeatureSampler {
    private struct SamplingCadence: Equatable {
        let spectrumInterval: TimeInterval
        let pcmInterval: TimeInterval
    }

    private struct SpectrumDelivery: Sendable {
        let magnitudes: [Float]
        let sampleRate: Double
        let rms: Float
        let timestamp: TimeInterval
    }

    private struct PCMDelivery: Sendable {
        let leftSamples: [Float]
        let rightSamples: [Float]?
        let sampleRate: Double
    }

    private static func samplingCadence(
        thermalState: ProcessInfo.ThermalState,
        lowPowerMode: Bool,
        screenCaptured: Bool,
        immersiveMode: Bool,
        computeTier: MonoComputeBudget.Tier
    ) -> SamplingCadence {
        let cadence: SamplingCadence
        switch thermalState {
        case .nominal:
            cadence = SamplingCadence(spectrumInterval: 0.16, pcmInterval: 0.50)
        case .fair:
            cadence = SamplingCadence(spectrumInterval: 0.22, pcmInterval: 0.70)
        case .serious:
            cadence = SamplingCadence(spectrumInterval: 0.32, pcmInterval: 1.00)
        case .critical:
            cadence = SamplingCadence(spectrumInterval: 0.45, pcmInterval: 1.40)
        @unknown default:
            cadence = SamplingCadence(spectrumInterval: 0.32, pcmInterval: 1.00)
        }
        var protectedCadence = cadence
        if lowPowerMode {
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.32),
                pcmInterval: max(protectedCadence.pcmInterval, 1.10)
            )
        }
        if screenCaptured {
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.38),
                pcmInterval: max(protectedCadence.pcmInterval, 1.35)
            )
        }
        // Aria runs an independent post-effect FFT for its visuals. Keep the
        // pre-effect Agent measurement accurate, but lower its delivery rate
        // while both analyzers are active so entering immersive mode cannot
        // create an analysis-task burst that competes with audio rendering.
        if immersiveMode {
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.30),
                pcmInterval: max(protectedCadence.pcmInterval, 1.00)
            )
        }
        switch computeTier {
        case .maximum:
            break
        case .balanced:
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.22),
                pcmInterval: max(protectedCadence.pcmInterval, 0.70)
            )
        case .reduced:
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.35),
                pcmInterval: max(protectedCadence.pcmInterval, 1.10)
            )
        case .minimum:
            protectedCadence = SamplingCadence(
                spectrumInterval: max(protectedCadence.spectrumInterval, 0.50),
                pcmInterval: max(protectedCadence.pcmInterval, 1.60)
            )
        }
        return protectedCadence
    }

    func sample(
        song: Song,
        duration requestedDuration: TimeInterval,
        graphicEQMode: GraphicEQMode,
        progress: @escaping @MainActor (Double, AIEqualizerSamplingStage) -> Void
    ) async throws -> AIEqualizerAudioFeatures {
        var isScreenCaptured = UIScreen.main.isCaptured
        var isImmersivePresented = ImmersiveModeController.shared.isPresented
        let samplingDuration = min(isScreenCaptured ? 20 : 120, max(8, requestedDuration))
        let timeout = samplingDuration + 4
        let player = PlayerManager.shared
        guard isCurrentSong(song, in: player) else { throw AIEqualizerError.noSong }
        guard player.isPlaying else { throw AIEqualizerError.playbackRequired }

        let analyzer = player.analysisSpectrumAnalyzer
        let accumulator = AIEqualizerSpectrumAccumulator(
            mode: graphicEQMode,
            pcmCaptureProfile: (isScreenCaptured || isImmersivePresented) ? .protected : .normal
        )
        let startedAt = Date()
        let targetText = String(format: "%.1f", samplingDuration)
        let startPositionText = String(format: "%.1f", player.currentTime)
        let startDurationText = String(format: "%.1f", player.duration)
        let analyzerRateText = String(format: "%.0f", analyzer.sampleRate)
        AppLogger.info(
            "[AIEqualizerSampler] Start source=\(song.musicSource.rawValue) songID=\(song.id) target=\(targetText)s eqBands=\(graphicEQMode.bandCount) screenCaptured=\(isScreenCaptured) immersive=\(isImmersivePresented) playerState=\(String(describing: player.streamPlayer.state)) appPlaying=\(player.isPlaying) loading=\(player.isLoading) position=\(startPositionText)/\(startDurationText) analyzerEnabled=\(analyzer.isEnabled) calibrationEnabled=\(analyzer.isCalibrationEnabled) sampleRate=\(analyzerRateText)",
            step: "sampling.start"
        )
        let processInfo = ProcessInfo.processInfo
        var thermalState = processInfo.thermalState
        var lowPowerMode = processInfo.isLowPowerModeEnabled
        var computeTier = MonoComputeBudgetStore.shared.current.tier
        var cadence = Self.samplingCadence(
            thermalState: thermalState,
            lowPowerMode: lowPowerMode,
            screenCaptured: isScreenCaptured,
            immersiveMode: isImmersivePresented,
            computeTier: computeTier
        )
        let expectedFrames = Int(samplingDuration / max(cadence.spectrumInterval, 0.16))
        let minimumValidFrames = max(16, min(48, Int(Double(expectedFrames) * 0.55)))

        // Buffer only the newest undigested callback. The old implementation
        // created a new unstructured task for every FFT and PCM delivery. Under
        // immersive/video load those tasks could queue faster than the feature
        // actor consumed them, causing CPU spikes and audible render underruns.
        let spectrumPipe = AsyncStream<SpectrumDelivery>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let pcmPipe = AsyncStream<PCMDelivery>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let spectrumConsumerTask = Task.detached(priority: .utility) {
            for await delivery in spectrumPipe.stream {
                guard !Task.isCancelled else { break }
                await accumulator.ingest(
                    magnitudes: delivery.magnitudes,
                    sampleRate: delivery.sampleRate,
                    rms: delivery.rms,
                    timestamp: delivery.timestamp
                )
            }
        }
        let pcmConsumerTask = Task.detached(priority: .utility) {
            for await delivery in pcmPipe.stream {
                guard !Task.isCancelled else { break }
                await accumulator.ingestPCM(
                    leftSamples: delivery.leftSamples,
                    rightSamples: delivery.rightSamples,
                    sampleRate: delivery.sampleRate
                )
            }
        }
        let token = analyzer.addAnalysisObserver(
            minimumInterval: cadence.spectrumInterval
        ) { magnitudes, sampleRate, rms in
            spectrumPipe.continuation.yield(
                SpectrumDelivery(
                    magnitudes: magnitudes,
                    sampleRate: sampleRate,
                    rms: rms,
                    timestamp: Date().timeIntervalSinceReferenceDate
                )
            )
        }
        let pcmToken = analyzer.addPCMAnalysisObserver(
            minimumInterval: cadence.pcmInterval
        ) { leftSamples, rightSamples, sampleRate in
            pcmPipe.continuation.yield(
                PCMDelivery(
                    leftSamples: leftSamples,
                    rightSamples: rightSamples,
                    sampleRate: sampleRate
                )
            )
        }
        AppLogger.debug(
            "[AIEqualizerSampler] Observers registered spectrum=\(token.uuidString) pcm=\(pcmToken.uuidString)",
            step: "sampling.observer"
        )
        var observersAreRegistered = true
        defer {
            if observersAreRegistered {
                analyzer.removeAnalysisObserver(token)
                analyzer.removePCMAnalysisObserver(pcmToken)
            }
            spectrumPipe.continuation.finish()
            pcmPipe.continuation.finish()
            spectrumConsumerTask.cancel()
            pcmConsumerTask.cancel()
            AppLogger.debug(
                "[AIEqualizerSampler] Observers removed spectrum=\(token.uuidString) pcm=\(pcmToken.uuidString)",
                step: "sampling.observer"
            )
        }

        var lastLoggedSecond = -1
        var didLogFirstCallback = false
        var didLogMissingCallbackWarning = false
        var didLogRejectedFrameWarning = false
        var lastLoggedStage: AIEqualizerSamplingStage?
        var immersiveTransitionProtectionUntil: Date?
        AppLogger.info(
            "[AIEqualizerSampler] Cadence thermal=\(thermalState.rawValue) lowPower=\(lowPowerMode) screenCaptured=\(isScreenCaptured) immersive=\(isImmersivePresented) spectrum=\(String(format: "%.2f", cadence.spectrumInterval))s pcm=\(String(format: "%.2f", cadence.pcmInterval))s minimumFrames=\(minimumValidFrames)",
            step: "sampling.cadence"
        )

        while Date().timeIntervalSince(startedAt) < timeout {
            try Task.checkCancellation()
            guard isCurrentSong(song, in: player) else {
                let actualIdentifier = player.currentSong.map {
                    "\($0.musicSource.rawValue):\($0.id)"
                } ?? "none"
                AppLogger.warning(
                    "[AIEqualizerSampler] Song changed during sampling expected=\(song.musicSource.rawValue):\(song.id) actual=\(actualIdentifier)",
                    step: "sampling.interrupted"
                )
                throw AIEqualizerError.noSong
            }

            let currentThermalState = processInfo.thermalState
            let currentLowPowerMode = processInfo.isLowPowerModeEnabled
            let currentScreenCaptured = UIScreen.main.isCaptured
            let currentImmersivePresented = ImmersiveModeController.shared.isPresented
            let currentComputeTier = MonoComputeBudgetStore.shared.current.tier
            let didEnterImmersive = currentImmersivePresented && !isImmersivePresented
            if didEnterImmersive {
                // Orientation, video background and Aria's visual FFT all start
                // inside the same short window. Temporarily reduce Agent callback
                // delivery while that transition settles; audio capture continues
                // and the user does not lose sampling progress.
                immersiveTransitionProtectionUntil = Date().addingTimeInterval(1.2)
                AppLogger.info(
                    "[AIEqualizerSampler] Immersive transition protection enabled for 1.2s",
                    step: "sampling.immersive-transition"
                )
            }
            let environmentChanged = currentThermalState != thermalState
                || currentLowPowerMode != lowPowerMode
                || currentScreenCaptured != isScreenCaptured
                || currentImmersivePresented != isImmersivePresented
                || currentComputeTier != computeTier
            if environmentChanged {
                thermalState = currentThermalState
                lowPowerMode = currentLowPowerMode
                isScreenCaptured = currentScreenCaptured
                isImmersivePresented = currentImmersivePresented
                computeTier = currentComputeTier
            }
            var nextCadence = Self.samplingCadence(
                thermalState: thermalState,
                lowPowerMode: lowPowerMode,
                screenCaptured: isScreenCaptured,
                immersiveMode: isImmersivePresented,
                computeTier: computeTier
            )
            if let protectionUntil = immersiveTransitionProtectionUntil {
                if Date() < protectionUntil {
                    nextCadence = SamplingCadence(
                        spectrumInterval: max(nextCadence.spectrumInterval, 0.50),
                        pcmInterval: max(nextCadence.pcmInterval, 1.60)
                    )
                } else {
                    immersiveTransitionProtectionUntil = nil
                }
            }
            if nextCadence != cadence {
                cadence = nextCadence
                analyzer.setAnalysisObserverMinimumInterval(
                    cadence.spectrumInterval,
                    for: token
                )
                analyzer.setPCMAnalysisObserverMinimumInterval(
                    cadence.pcmInterval,
                    for: pcmToken
                )
                AppLogger.warning(
                    "[AIEqualizerSampler] Cadence adjusted thermal=\(thermalState.rawValue) lowPower=\(lowPowerMode) screenCaptured=\(isScreenCaptured) immersive=\(isImmersivePresented) transitionProtected=\(immersiveTransitionProtectionUntil != nil) spectrum=\(String(format: "%.2f", cadence.spectrumInterval))s pcm=\(String(format: "%.2f", cadence.pcmInterval))s",
                    step: "sampling.cadence"
                )
            }
            let snapshot = await accumulator.diagnostics()
            let count = snapshot.acceptedFrames
            let elapsed = Date().timeIntervalSince(startedAt)
            let timeProgress = min(1, elapsed / samplingDuration)
            let frameReadiness = min(1, Double(count) / Double(minimumValidFrames))
            let stage: AIEqualizerSamplingStage
            if snapshot.callbackFrames == 0 {
                stage = .waitingForAudio
            } else if timeProgress < 0.38 {
                stage = .collectingSpectrum
            } else if timeProgress < 0.7 {
                stage = .measuringDynamics
            } else if timeProgress < 0.94 {
                stage = .organizingFeatures
            } else {
                stage = .finalizing
            }
            progress(min(0.98, timeProgress * 0.9 + frameReadiness * 0.1), stage)
            if stage != lastLoggedStage {
                lastLoggedStage = stage
                AppLogger.info(
                    "[AIEqualizerSampler] Stage changed stage=\(stage.rawValue) elapsed=\(String(format: "%.1f", elapsed))s accepted=\(snapshot.acceptedFrames)",
                    step: "sampling.stage"
                )
            }
            if !didLogFirstCallback, snapshot.callbackFrames > 0 {
                didLogFirstCallback = true
                let firstCallbackText = String(format: "%.2f", elapsed)
                AppLogger.info(
                    "[AIEqualizerSampler] First spectrum callback after \(firstCallbackText)s; \(snapshot.logText)",
                    step: "sampling.first-frame"
                )
            }
            if !didLogMissingCallbackWarning, elapsed >= 3, snapshot.callbackFrames == 0 {
                didLogMissingCallbackWarning = true
                AppLogger.warning(
                    "[AIEqualizerSampler] No spectrum callback after 3s playerState=\(String(describing: player.streamPlayer.state)) appPlaying=\(player.isPlaying) loading=\(player.isLoading) analyzerEnabled=\(analyzer.isEnabled) calibrationEnabled=\(analyzer.isCalibrationEnabled)",
                    step: "sampling.no-callback"
                )
            }
            if !didLogRejectedFrameWarning,
               elapsed >= 5,
               snapshot.callbackFrames > 0,
               snapshot.acceptedFrames == 0 {
                didLogRejectedFrameWarning = true
                AppLogger.warning(
                    "[AIEqualizerSampler] Spectrum callbacks received but all frames were rejected; \(snapshot.logText)",
                    step: "sampling.frames-rejected"
                )
            }
            let elapsedSecond = Int(elapsed)
            if elapsedSecond > 0, elapsedSecond % 5 == 0, elapsedSecond != lastLoggedSecond {
                lastLoggedSecond = elapsedSecond
                AppLogger.debug(
                    "[AIEqualizerSampler] Progress elapsed=\(elapsedSecond)s target=\(targetText)s playerState=\(String(describing: player.streamPlayer.state)) appPlaying=\(player.isPlaying) loading=\(player.isLoading); \(snapshot.logText)",
                    step: "sampling.progress"
                )
            }
            if count >= minimumValidFrames, elapsed >= samplingDuration { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        // Stop producers first, then drain the two bounded streams. This makes
        // final diagnostics deterministic without leaving analysis work alive
        // while feature synthesis is running.
        analyzer.removeAnalysisObserver(token)
        analyzer.removePCMAnalysisObserver(pcmToken)
        observersAreRegistered = false
        spectrumPipe.continuation.finish()
        pcmPipe.continuation.finish()
        await spectrumConsumerTask.value
        await pcmConsumerTask.value
        let finalDiagnostics = await accumulator.diagnostics()
        guard finalDiagnostics.acceptedFrames >= minimumValidFrames else {
            let elapsedText = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            AppLogger.error(
                "[AIEqualizerSampler] No usable audio after \(elapsedText)s playerState=\(String(describing: player.streamPlayer.state)) appPlaying=\(player.isPlaying) loading=\(player.isLoading) analyzerEnabled=\(analyzer.isEnabled) calibrationEnabled=\(analyzer.isCalibrationEnabled); \(finalDiagnostics.logText)",
                step: "sampling.failed"
            )
            throw AIEqualizerError.sampleUnavailable
        }

        let manager = EQManager.shared
        let effects = player.audioEffects
        let outputName = manager.currentOutputName.isEmpty
            ? manager.currentOutputKind.title
            : manager.currentOutputName
        let outputKind = manager.currentOutputKind.rawValue
        let currentBassGain = effects.bassGain
        let currentTrebleGain = effects.trebleGain
        let currentSurroundLevel = effects.surroundLevel
        let currentReverbLevel = effects.reverbLevel
        let currentStereoWidth = effects.stereoWidth
        let processingIntensity = manager.professionalProcessingIntensity
        let outputCalibrationEnabled = manager.isOutputCalibrationEnabled
        let loudnessMatchingEnabled = manager.isLoudnessMatchingEnabled
        let smartSongCompensationEnabled = manager.isSmartSongCompensationEnabled
        let dynamicEQEnabled = manager.isDynamicEQEnabled
        let multibandDynamicsEnabled = manager.isMultibandDynamicsEnabled
        let parametricEQEnabled = manager.isParametricEQEnabled
        let measuredDuration = Date().timeIntervalSince(startedAt)
        let songID = song.id
        let title = song.name
        let artist = song.artistName
        let source = song.musicSource.rawValue
        let features = try await MonoComputeScheduler.shared.withPermit(.analysis) {
            try await Task.detached(priority: .utility) {
                try await accumulator.makeFeatures(
                    songID: songID,
                    title: title,
                    artist: artist,
                    source: source,
                    outputDevice: outputName,
                    outputKind: outputKind,
                    currentBassGain: currentBassGain,
                    currentTrebleGain: currentTrebleGain,
                    currentSurroundLevel: currentSurroundLevel,
                    currentReverbLevel: currentReverbLevel,
                    currentStereoWidth: currentStereoWidth,
                    professionalProcessingIntensity: processingIntensity,
                    outputCalibrationEnabled: outputCalibrationEnabled,
                    loudnessMatchingEnabled: loudnessMatchingEnabled,
                    smartSongCompensationEnabled: smartSongCompensationEnabled,
                    dynamicEQEnabled: dynamicEQEnabled,
                    multibandDynamicsEnabled: multibandDynamicsEnabled,
                    parametricEQEnabled: parametricEQEnabled,
                    duration: measuredDuration,
                    minimumFrames: minimumValidFrames
                )
            }.value
        }
        let measuredDurationText = String(format: "%.1f", features.sampleDuration)
        let measuredRateText = String(format: "%.0f", features.sampleRate)
        let measuredRMSText = String(format: "%.2f", features.rmsDBFS)
        let measuredBPMText = features.estimatedBPM > 0
            ? String(format: "%.1f", features.estimatedBPM)
            : "unresolved"
        let analysisLog = [
            "duration=\(measuredDurationText)s",
            "frames=\(features.frameCount)",
            "sampleRate=\(measuredRateText)",
            "rms=\(measuredRMSText)dBFS",
            "integrated=\(String(format: "%.2f", features.integratedLUFS))LUFS",
            "lra=\(String(format: "%.2f", features.loudnessRangeLU))LU",
            "truePeak=\(String(format: "%.2f", features.estimatedTruePeakDBTP))dBTP",
            "crest=\(String(format: "%.2f", features.crestFactorDB))dB",
            "dr=\(String(format: "%.2f", features.dynamicRangeDR))",
            "clipping=\(String(format: "%.5f", features.clippingRatio))",
            "phase=\(String(format: "%.3f", features.phaseCorrelation))",
            "mono=\(String(format: "%.3f", features.monoCompatibility))",
            "stereoWidth=\(String(format: "%.3f", features.measuredStereoWidth))",
            "bpm=\(measuredBPMText)",
            "tempoConfidence=\(String(format: "%.2f", features.tempoConfidence))",
            "key=\(features.estimatedKey.isEmpty ? "unresolved" : features.estimatedKey)",
            "keyConfidence=\(String(format: "%.2f", features.keyConfidence))",
            "dominantPitch=\(String(format: "%.1f", features.dominantPitchHz))Hz",
            "melodyRange=\(String(format: "%.1f", features.melodyRangeSemitones))st",
            "transientDensity=\(String(format: "%.2f", features.transientDensity))",
            "vocalConfidence=\(String(format: "%.2f", features.vocalReference?.confidence ?? 0))",
            "vocalRegister=\(features.vocalReference?.register ?? "unresolved")",
            "genres=\(features.genreHints.joined(separator: ","))",
            "instruments=\(features.instrumentHints.joined(separator: ","))"
        ].joined(separator: " ")
        AppLogger.success(
            "[AIEqualizerSampler] Completed \(analysisLog)",
            step: "sampling.completed"
        )
        progress(1, .finalizing)
        return features
    }

    private func isCurrentSong(_ song: Song, in player: PlayerManager) -> Bool {
        guard let current = player.currentSong else { return false }
        return current.id == song.id && current.musicSource == song.musicSource
    }
}
