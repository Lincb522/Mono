import Foundation

/// Estimates tempo from the timestamped FFT timeline, without joining sparse PCM windows.
enum AIEqualizerTempoEstimator {
    nonisolated static func estimate(
        flux: [Float],
        rmsDB: [Float],
        timestamps: [TimeInterval]
    ) -> (bpm: Float, confidence: Float, onsetCount: Int, stability: Float) {
        let count = min(flux.count, min(rmsDB.count, timestamps.count))
        let samples = (0..<count).compactMap { index -> (time: Double, flux: Float, level: Float)? in
            guard timestamps[index].isFinite, flux[index].isFinite, rmsDB[index].isFinite else { return nil }
            return (timestamps[index], max(0, flux[index]), rmsDB[index])
        }.sorted { $0.time < $1.time }
        guard samples.count >= 16,
              let first = samples.first, let last = samples.last,
              last.time - first.time >= 4 else { return (0, 0, 0, 0) }

        var rises = Array(repeating: Float(0), count: samples.count)
        for index in 1..<samples.count {
            let interval = samples[index].time - samples[index - 1].time
            // Exclude RMS jumps across pauses and dropped callback gaps.
            guard interval > 0, interval <= 0.75 else { continue }
            rises[index] = max(0, samples[index].level - samples[index - 1].level - 0.75)
        }
        let spectralScale = max(0.000_05, percentile(samples.map(\.flux).sorted(), 0.90))
        let levelScale = max(3, percentile(rises.sorted(), 0.90))
        let values = samples.indices.map { index -> Float in
            let spectrum = min(1, samples[index].flux / spectralScale)
            // Normalizing a spectrum removes pure amplitude changes. Retain those
            // attacks through a separate RMS envelope before detecting peaks.
            let envelope = min(1, rises[index] / levelScale)
            return max(spectrum, envelope)
        }
        let median = percentile(values.sorted(), 0.50)
        let mad = percentile(values.map { abs($0 - median) }.sorted(), 0.50)
        let threshold = median + max(0.08, mad * 0.65)
        var onsets: [(time: TimeInterval, strength: Float)] = []
        var lastOnset = -Double.greatestFiniteMagnitude
        for index in 1..<(samples.count - 1) where values[index] >= threshold {
            guard values[index] >= values[index - 1], values[index] > values[index + 1] else { continue }
            let time = samples[index].time
            guard time - lastOnset >= 0.16 else { continue }
            let strength = max(0, (values[index] - median) / max(mad, 0.08))
            onsets.append((time, min(8, strength)))
            lastOnset = time
        }
        guard onsets.count >= 4 else { return (0, 0, onsets.count, 0) }

        let minimumBPM = 58
        let maximumBPM = 200
        var histogram = Array(repeating: Float(0), count: maximumBPM + 1)
        var candidates: [(bpm: Float, weight: Float)] = []
        for start in onsets.indices {
            let endLimit = min(onsets.count, start + 9)
            guard start + 1 < endLimit else { continue }
            for end in (start + 1)..<endLimit {
                let interval = onsets[end].time - onsets[start].time
                guard interval >= 0.28, interval <= 4.2 else { continue }
                var bpm = Float(60 / interval)
                while bpm < Float(minimumBPM) { bpm *= 2 }
                while bpm > Float(maximumBPM) { bpm /= 2 }
                guard bpm >= Float(minimumBPM), bpm <= Float(maximumBPM) else { continue }

                let distance = Float(end - start)
                // Long intervals repeat existing beats; inverse-distance weighting
                // prevents their octave-folded votes from dominating the beat period.
                let weight = sqrtf(max(0.01, onsets[start].strength * onsets[end].strength))
                    / distance
                let rounded = Int(bpm.rounded())
                histogram[rounded] += weight
                candidates.append((bpm, weight))
            }
        }
        guard !candidates.isEmpty else { return (0, 0, onsets.count, 0) }

        var smoothed = histogram
        for bpm in minimumBPM...maximumBPM {
            let lower = max(minimumBPM, bpm - 2)
            let upper = min(maximumBPM, bpm + 2)
            smoothed[bpm] = (lower...upper).reduce(Float(0)) { partial, candidate in
                let distance = abs(candidate - bpm)
                let kernel: Float = distance == 0 ? 1 : (distance == 1 ? 0.65 : 0.3)
                return partial + histogram[candidate] * kernel
            }
        }

        guard let bestBPM = (minimumBPM...maximumBPM).max(by: {
            smoothed[$0] < smoothed[$1]
        }) else { return (0, 0, onsets.count, 0) }
        let peak = smoothed[bestBPM]
        let runnerUp = (minimumBPM...maximumBPM)
            .filter { abs($0 - bestBPM) > 6 }
            .map { smoothed[$0] }
            .max() ?? 0

        let matching = candidates.filter {
            abs($0.bpm - Float(bestBPM)) <= max(3, Float(bestBPM) * 0.045)
        }
        let matchingWeight = matching.reduce(Float(0)) { $0 + $1.weight }
        let totalWeight = candidates.reduce(Float(0)) { $0 + $1.weight }
        let weightedDeviation = matchingWeight > 0
            ? matching.reduce(Float(0)) { $0 + abs($1.bpm - Float(bestBPM)) * $1.weight } / matchingWeight
            : Float(bestBPM)
        let stability = min(1, max(0, 1 - weightedDeviation / max(4, Float(bestBPM) * 0.055)))
        let peakSeparation = min(1, max(0, (peak - runnerUp) / max(peak, 0.000_1)))
        let support = min(1, matchingWeight / max(totalWeight * 0.24, 0.000_1))
        let evidence = min(1, Float(onsets.count) / 16)
        let confidence = min(1, evidence * (0.34 + support * 0.36 + peakSeparation * 0.30) * stability)

        guard confidence >= 0.18, stability >= 0.4 else {
            return (0, confidence, onsets.count, stability)
        }
        return (Float(bestBPM), confidence, onsets.count, stability)
    }

    nonisolated private static func percentile(_ sorted: [Float], _ fraction: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let position = Float(sorted.count - 1) * fraction
        let lower = Int(position)
        let upper = min(sorted.count - 1, lower + 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Float(lower))
    }
}
