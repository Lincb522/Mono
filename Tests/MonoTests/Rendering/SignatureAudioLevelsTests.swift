import XCTest
@testable import Mono

final class SignatureAudioLevelsTests: XCTestCase {
    func testSilentAndInvalidSamplesDoNotMoveTheNeedle() {
        XCTAssertEqual(SignatureAudioLevels.meter([]), 0)
        XCTAssertEqual(SignatureAudioLevels.meter([0, 0, .nan, .infinity]), 0)
    }

    func testReferenceLevelAndChannelSeparation() {
        let reference = Float(pow(10.0, -18.0 / 20))
        XCTAssertEqual(SignatureAudioLevels.meter([reference, -reference]), 0.8, accuracy: 0.00001)
        XCTAssertEqual(SignatureAudioLevels.meter([0, 0]), 0)
        XCTAssertEqual(SignatureAudioLevels.meter([1, -1]), 1)
    }

    func testNeedleFollowsIncreasingEnergyWithoutLeavingItsScale() {
        let levels = stride(from: -70.0, through: 0, by: 1).map { db in
            SignatureAudioLevels.meter([Float(pow(10, db / 20))])
        }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertTrue(levels.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testQuietLinearFFTBecomesVisibleInsteadOfFlatDots() {
        let bars = SignatureAudioLevels.waveform(Array(repeating: 0.01, count: 512), count: 64)
        XCTAssertEqual(bars.count, 64)
        XCTAssertTrue(bars.allSatisfy { abs($0 - 32.0 / 72) < 0.00001 })
    }

    func testInvalidAndSilentSpectrumStaysFiniteWithoutFabricatedSignal() {
        XCTAssertEqual(SignatureAudioLevels.waveform([], count: 64), [])
        XCTAssertEqual(SignatureAudioLevels.waveform([1], count: 0), [])
        let bars = SignatureAudioLevels.waveform([0, .nan, .infinity, -1], count: 64)
        XCTAssertEqual(bars, Array(repeating: 0, count: 64))
        XCTAssertTrue(SignatureAudioLevels.waveform([1000], count: 64).allSatisfy { $0 == 1 })
    }
}
