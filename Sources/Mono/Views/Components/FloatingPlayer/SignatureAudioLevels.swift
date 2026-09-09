import Foundation

enum SignatureAudioLevels {
    /// The reference's VU face uses 0 VU at -18 dBFS; channels are measured independently.
    static func meter(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0.0) { sum, sample in
            sum + (sample.isFinite ? Double(sample) * Double(sample) : 0)
        } / Double(samples.count)
        guard meanSquare > 0 else { return 0 }
        let vu = 10 * log10(meanSquare) + 18
        let ticks = [-20.0, -10, -6, -3, 0, 3]
        for index in 0..<(ticks.count - 1) where vu <= ticks[index + 1] {
            let fraction = min(max((vu - ticks[index]) / (ticks[index + 1] - ticks[index]), 0), 1)
            return (Double(index) + fraction) / Double(ticks.count - 1)
        }
        return 1
    }

    static func waveform(_ magnitudes: [Float], count: Int) -> [Double] {
        guard !magnitudes.isEmpty, count > 0 else { return [] }
        return (0..<count).map { band in
            let lower = min(Int(pow(Double(band) / Double(count), 1.65) * Double(magnitudes.count)), magnitudes.count - 1)
            let upper = min(max(Int(pow(Double(band + 1) / Double(count), 1.65) * Double(magnitudes.count)), lower + 1), magnitudes.count)
            let peak = magnitudes[lower..<upper].filter(\.isFinite).max() ?? 0
            guard peak > 0 else { return 0 }
            // Analysis observers provide linear magnitudes, unlike the visual callback's dB-normalized bins.
            return min(max((20 * log10(Double(peak)) + 72) / 72, 0), 1)
        }
    }
}
