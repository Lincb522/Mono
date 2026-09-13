import Foundation

struct FluxAudioLevels: Equatable, Sendable {
    var bass: Double = 0
    var mid: Double = 0
    var treble: Double = 0

    static let silence = FluxAudioLevels()

    static func measure(_ magnitudes: [Float], sampleRate: Double, rms: Float) -> Self {
        guard magnitudes.count > 1, sampleRate.isFinite, sampleRate > 0,
              rms.isFinite, rms > 0.000_1 else { return .silence }

        let binWidth = sampleRate / Double(magnitudes.count * 2)
        func level(from lower: Double, to upper: Double) -> Double {
            let start = max(1, Int(min(Double(magnitudes.count), ceil(lower / binWidth))))
            let end = max(start, Int(min(Double(magnitudes.count), ceil(upper / binWidth))))
            guard start < end else { return 0 }
            let peak = magnitudes[start..<end].reduce(Float(0)) { current, value in
                value.isFinite ? max(current, value) : current
            }
            let decibels = 20 * log10(max(Double(peak), 0.000_001))
            return min(max((decibels + 66) / 54, 0), 1)
        }

        return Self(
            bass: level(from: 60, to: 280),
            mid: level(from: 280, to: 2_000),
            treble: level(from: 2_000, to: 9_000)
        )
    }
}
