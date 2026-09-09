import XCTest
@testable import Mono

final class AsideMusicFluidPaletteTests: XCTestCase {
    private func palette(_ value: Double) -> AsideMusicFluidPalette {
        AsideMusicFluidPalette(
            first: SIMD3(repeating: value),
            middle: SIMD3(value, 0.45, 0.55),
            last: SIMD3(0.65, value, 0.35)
        )
    }

    func testFirstResolvedCoverAppearsWithoutFadingFromPlaceholder() {
        var transition = AsideMusicFluidPaletteTransition()
        XCTAssertNil(transition.value(at: 0))
        transition.update(to: palette(0.3), at: 10)
        XCTAssertEqual(transition.value(at: 10), palette(0.3))
        XCTAssertFalse(transition.isAnimating)
    }

    func testDisplayedPaletteRemainsAvailableWhileNextCoverIsPending() {
        var transition = AsideMusicFluidPaletteTransition()
        transition.update(to: palette(0.3), at: 10)
        XCTAssertEqual(transition.value(at: 30), palette(0.3))
        transition.update(to: palette(0.7), at: 30)
        XCTAssertEqual(transition.value(at: 30), palette(0.3))
        XCTAssertTrue(transition.isAnimating)
    }

    func testEveryFrameStaysWithinTheTwoCoverPalettes() {
        var transition = AsideMusicFluidPaletteTransition()
        let first = palette(0.3)
        let second = palette(0.7)
        transition.update(to: first, at: 0)
        transition.update(to: second, at: 10)
        var previous = 0.3
        for frame in 0...36 {
            let value = transition.value(at: 10 + Double(frame) / 30)!
            XCTAssertGreaterThanOrEqual(value.first.x, previous)
            XCTAssertLessThanOrEqual(value.first.x, 0.7)
            XCTAssertEqual(value.middle.y, 0.45)
            XCTAssertEqual(value.last.z, 0.35)
            previous = value.first.x
        }
        XCTAssertEqual(transition.value(at: 10.6)!.first.x, 0.5, accuracy: 0.000001)
        XCTAssertEqual(transition.value(at: 12), second)
    }

    func testRapidTrackChangeContinuesFromTheCurrentlyDisplayedColors() {
        var transition = AsideMusicFluidPaletteTransition()
        transition.update(to: palette(0.3), at: 0)
        transition.update(to: palette(0.7), at: 10)
        let visible = transition.value(at: 10.4)
        transition.update(to: palette(0.4), at: 10.4)
        XCTAssertEqual(transition.value(at: 10.4), visible)
        XCTAssertEqual(transition.value(at: 12), palette(0.4))
    }

    func testDuplicateResolvedNotificationDoesNotRestartTheFade() {
        var transition = AsideMusicFluidPaletteTransition()
        transition.update(to: palette(0.3), at: 0)
        transition.update(to: palette(0.7), at: 10)
        transition.update(to: palette(0.7), at: 10.8)
        XCTAssertEqual(transition.completionTime, 11.2)
        transition.finishIfNeeded(at: 11)
        XCTAssertTrue(transition.isAnimating)
        transition.finishIfNeeded(at: 11.3)
        XCTAssertFalse(transition.isAnimating)
        XCTAssertNil(transition.completionTime)
        XCTAssertEqual(transition.value(at: 20), palette(0.7))
    }
}
