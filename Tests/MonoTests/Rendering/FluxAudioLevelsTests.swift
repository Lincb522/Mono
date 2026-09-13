import XCTest
@testable import Mono

final class FluxAudioLevelsTests: XCTestCase {
    func testSilentAndInvalidInputDoesNotInventPlaybackMotion() {
        let signal = Array(repeating: Float(0.1), count: 1_024)
        XCTAssertEqual(FluxAudioLevels.measure(signal, sampleRate: 48_000, rms: 0), .silence)
        XCTAssertEqual(FluxAudioLevels.measure(signal, sampleRate: .nan, rms: 0.1), .silence)
        XCTAssertEqual(FluxAudioLevels.measure(signal, sampleRate: 48_000, rms: .infinity), .silence)
        XCTAssertEqual(FluxAudioLevels.measure([], sampleRate: 48_000, rms: 0.1), .silence)
        XCTAssertEqual(FluxAudioLevels.measure([.nan, -.infinity, -1], sampleRate: 48_000, rms: 0.1), .silence)
        XCTAssertEqual(FluxAudioLevels.measure(signal, sampleRate: .leastNonzeroMagnitude, rms: 0.1), .silence)
    }

    func testFrequencyMappingRemainsStableAcrossSampleRates() {
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            for (frequency, expected) in [
                (120.0, FluxAudioLevels(bass: 1)),
                (1_000.0, FluxAudioLevels(mid: 1)),
                (6_000.0, FluxAudioLevels(treble: 1)),
            ] {
                var bins = Array(repeating: Float(0), count: 1_024)
                bins[Int((frequency / (rate / 2) * Double(bins.count)).rounded())] = 1
                XCTAssertEqual(FluxAudioLevels.measure(bins, sampleRate: rate, rms: 0.1), expected)
            }
        }
    }

    func testQuieterAudioProducesSmallerBoundedMotion() {
        var bins = Array(repeating: Float(0), count: 1_024)
        bins[5] = 0.002
        let quiet = FluxAudioLevels.measure(bins, sampleRate: 48_000, rms: 0.01)
        bins[5] = 0.02
        let loud = FluxAudioLevels.measure(bins, sampleRate: 48_000, rms: 0.1)
        XCTAssertGreaterThan(quiet.bass, 0)
        XCTAssertGreaterThan(loud.bass, quiet.bass)
        XCTAssertLessThanOrEqual(loud.bass, 1)
        XCTAssertEqual(loud.mid, 0)
        XCTAssertEqual(loud.treble, 0)
    }
}
