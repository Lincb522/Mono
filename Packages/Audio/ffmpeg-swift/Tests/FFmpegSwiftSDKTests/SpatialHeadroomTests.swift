import XCTest
@testable import FFmpegSwiftSDK

final class SpatialHeadroomTests: XCTestCase {
    func testNeutralAndNarrowStagesDoNotReservePositiveGain() {
        for width: Float in [0, 0.7, 1] {
            let stage = MonoSpatialFilterParameters(stereoWidth: width, surroundLevel: 0, reverbLevel: 0)
            XCTAssertEqual(stage.peakBoostDB, 0)
            XCTAssertTrue(stage.echoDecays.isEmpty)
        }
    }

    func testImmersiveAirPodsStageIncludesSideAndReflectionEnergy() {
        let stage = MonoSpatialFilterParameters(stereoWidth: 1.385, surroundLevel: 0.119, reverbLevel: 0.0324)
        XCTAssertEqual(stage.effectiveStereoWidth, 1.476, accuracy: 0.00001)
        XCTAssertEqual(stage.echoDelays, [29, 53, 89, 137])
        XCTAssertEqual(stage.echoDecays, [0.040, 0.029, 0.020, 0.014])
        // For opposite full-scale channels, aecho's dry and all delayed
        // samples can align. Its in_gain does not attenuate delayed samples.
        let alignedPeak: Float = 1.476 * (0.994 + 0.040 + 0.029 + 0.020 + 0.014)
        XCTAssertEqual(stage.peakGain, alignedPeak, accuracy: 0.00001)
        XCTAssertGreaterThan(stage.peakBoostDB, 4)
    }

    func testHeadroomBoundsStereoMatrixAndAlignedEchoes() {
        for width: Float in [0.7, 1, 1.14, 1.385, 1.8, 2] {
            for surround: Float in [0, 0.12, 0.85, 1] {
                for reverb: Float in [0, 0.0324, 0.18, 0.19, 0.42, 1] {
                    let stage = MonoSpatialFilterParameters(stereoWidth: width, surroundLevel: surround, reverbLevel: reverb)
                    for left: Float in [-1, 0, 1] {
                        for right: Float in [-1, 0, 1] {
                            let mid = (left + right) / 2
                            let side = (left - right) / 2 * stage.effectiveStereoWidth
                            let alignedEchoGain = stage.echoInputGain + stage.echoDecays.reduce(0, +)
                            let peak = max(abs(mid + side), abs(mid - side)) * alignedEchoGain
                            XCTAssertLessThanOrEqual(peak, stage.peakGain + 0.00001)
                        }
                    }
                    for upstreamDB: Float in [0, 6, 12, 24] {
                        let workingGain = stage.echoWorkingGain(upstreamBoostDB: upstreamDB)
                        let upstreamGain = powf(10, upstreamDB / 20)
                        XCTAssertLessThanOrEqual(stage.peakGain * upstreamGain * workingGain, 0.25001)
                        XCTAssertEqual(workingGain * (1 / workingGain), 1, accuracy: 0.00001)
                    }
                }
            }
        }
    }

    func testInvalidSpatialValuesStayFiniteAndNeutral() {
        let stage = MonoSpatialFilterParameters(stereoWidth: .nan, surroundLevel: .infinity, reverbLevel: .nan)
        XCTAssertEqual(stage.peakBoostDB, 0)
        XCTAssertTrue(stage.echoDecays.isEmpty)
    }

    func testStandaloneSpatialTrimReachesTheProcessorBelowMinusNineDB() {
        let repair = AudioRepairEngine()
        repair.configureOutputSafety(limiterEnabled: false, outputGainDB: -15)
        XCTAssertEqual(repair.outputGainDB, -15)
        let data = UnsafeMutablePointer<Float>.allocate(capacity: 1_024)
        data.initialize(repeating: 0.5, count: 1_024)
        defer { data.deallocate() }
        for _ in 0..<32 {
            data.update(repeating: 0.5, count: 1_024)
            repair.process(data, frameCount: 512, channelCount: 2, sampleRate: 48_000)
        }
        XCTAssertEqual(data[1_023], 0.5 * powf(10, -15.0 / 20), accuracy: 0.00001)
    }
}
