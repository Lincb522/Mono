import XCTest
@testable import Mono

final class AIEqualizerTempoEstimatorTests: XCTestCase {
    func testAmplitudeOnlyBeatsRemainDetectableWithAnUnchangedNormalizedSpectrum() {
        let times = (0..<160).map { Double($0) * 0.125 }
        let levels: [Float] = times.indices.map { $0.isMultiple(of: 4) ? -12 : -30 }
        let result = AIEqualizerTempoEstimator.estimate(
            flux: Array(repeating: 0, count: times.count),
            rmsDB: levels,
            timestamps: times
        )
        XCTAssertEqual(result.bpm, 120, accuracy: 2)
        XCTAssertGreaterThan(result.confidence, 0.18)
    }

    func testSixteenAcceptedFramesCanResolveSlowBeats() {
        let result = AIEqualizerTempoEstimator.estimate(
            flux: Array(repeating: 0, count: 16),
            rmsDB: (0..<16).map { $0.isMultiple(of: 2) ? -12 : -30 },
            timestamps: (0..<16).map { Double($0) * 0.5 }
        )
        XCTAssertEqual(result.bpm, 60, accuracy: 2)
    }

    func testSpectralBeatsAtTheNormalSamplingCadenceDoNotCollapseToHalfTime() {
        let result = AIEqualizerTempoEstimator.estimate(
            flux: (0..<150).map { $0.isMultiple(of: 3) ? 0.1 : 0 },
            rmsDB: Array(repeating: -18, count: 150),
            timestamps: (0..<150).map { Double($0) * 0.16 }
        )
        XCTAssertEqual(result.bpm, 125, accuracy: 2)
    }

    func testSilenceAndSteadyTonesDoNotInventATempo() {
        for level: Float in [-100, -18] {
            let result = AIEqualizerTempoEstimator.estimate(
                flux: Array(repeating: 0, count: 100),
                rmsDB: Array(repeating: level, count: 100),
                timestamps: (0..<100).map { Double($0) * 0.16 }
            )
            XCTAssertEqual(result.bpm, 0)
            XCTAssertEqual(result.onsetCount, 0)
        }
    }

    func testSparseInvalidOrTooShortInputHasNoTempo() {
        let result = AIEqualizerTempoEstimator.estimate(
            flux: [0, .nan, 0.2, 0],
            rmsDB: [-20, -10, -.infinity, -20],
            timestamps: [0, 0.5, 1, 1.5]
        )
        XCTAssertEqual(result.bpm, 0)
    }
}
