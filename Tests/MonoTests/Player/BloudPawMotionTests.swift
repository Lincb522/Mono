import XCTest
@testable import Mono

final class BloudPawMotionTests: XCTestCase {
    private func touch(_ x: Double, _ y: Double, drag: SIMD2<Double> = .zero) -> BloudPawTouch {
        .init(origin: SIMD2(x, y), location: SIMD2(x, y) + drag, translation: drag)
    }

    func testQuickCheekTapCompletesFeedbackThenReturnsToRest() {
        var motion = BloudPawMotion()
        motion.follow(touch(-0.6, 0.3), at: 10)
        motion.follow(nil, at: 10.02)
        let peak = motion.sample(at: 10.3, idleTime: nil, expression: .soft)
        XCTAssertEqual(peak.side, -1)
        XCTAssertGreaterThan(peak.disgust, 0.25)
        XCTAssertLessThanOrEqual(peak.disgust, 0.28)
        XCTAssertLessThanOrEqual(peak.leftEar, 0.12)
        XCTAssertGreaterThan(peak.pinch, 0.9)
        let rest = motion.sample(at: 12, idleTime: nil, expression: .soft)
        XCTAssertLessThan(rest.pinch, 0.001)
        XCTAssertEqual(rest.tongue, 0)
    }

    func testHeldCheekSustainsReactionAndReleaseSettlesWhilePaused() {
        var motion = BloudPawMotion()
        motion.follow(touch(0.6, 0.3), at: 10)
        XCTAssertGreaterThan(motion.sample(at: 15, idleTime: nil, expression: .bright).disgust, 0.27)
        motion.follow(nil, at: 15)
        XCTAssertGreaterThan(motion.sample(at: 15.1, idleTime: nil, expression: .bright).disgust, 0.14)
        XCTAssertLessThan(motion.sample(at: 17, idleTime: nil, expression: .bright).disgust, 0.001)
    }

    func testDraggingRetargetsWithoutPositionJumpAndStaysBounded() {
        var motion = BloudPawMotion()
        motion.follow(touch(0.6, 0.3, drag: SIMD2(1, 1)), at: 10)
        let before = motion.sample(at: 10.12, idleTime: nil, expression: .soft).drag
        motion.follow(touch(0.6, 0.3, drag: SIMD2(-5, -5)), at: 10.12)
        let retargeted = motion.sample(at: 10.12, idleTime: nil, expression: .soft).drag
        XCTAssertEqual(retargeted.x, before.x, accuracy: 1e-10)
        XCTAssertEqual(retargeted.y, before.y, accuracy: 1e-10)
        let after = motion.sample(at: 12, idleTime: nil, expression: .soft).drag
        XCTAssertEqual(after.x, -7, accuracy: 0.001)
        XCTAssertEqual(after.y, -5, accuracy: 0.001)
        motion.follow(nil, at: 12)
        let released = motion.sample(at: 12, idleTime: nil, expression: .soft).drag
        XCTAssertEqual(released.x, after.x, accuracy: 1e-10)
        XCTAssertEqual(released.y, after.y, accuracy: 1e-10)
        XCTAssertLessThan(abs(motion.sample(at: 14, idleTime: nil, expression: .soft).drag.x), 0.001)
    }

    func testForeheadAndNoseHaveDistinctResponses() {
        var forehead = BloudPawMotion()
        forehead.follow(touch(0, -0.5), at: 10)
        let pet = forehead.sample(at: 10.2, idleTime: nil, expression: .soft)
        XCTAssertGreaterThan(pet.comfort, 0.9)
        XCTAssertGreaterThan(pet.tongue, 0.6)
        XCTAssertEqual(pet.pinch, 0)
        var nose = BloudPawMotion()
        nose.follow(touch(0, 0.3), at: 10)
        let lick = nose.sample(at: 10.2, idleTime: nil, expression: .soft)
        XCTAssertGreaterThan(lick.lick, 0.9)
        XCTAssertEqual(lick.disgust, 0)
    }

    func testIdleActionsHaveQuietIntervalsAndStopWithoutPlayback() {
        let motion = BloudPawMotion()
        let peek = motion.sample(at: 10, idleTime: 6.4, expression: .soft)
        XCTAssertGreaterThan(peek.tongue, 0.9)
        XCTAssertEqual(peek.mouthOpen, 0)
        XCTAssertGreaterThan(peek.comfort, 0)
        XCTAssertEqual(motion.sample(at: 11, idleTime: 7.1, expression: .soft).tongue, 0)
        XCTAssertGreaterThan(motion.sample(at: 26, idleTime: 22.4, expression: .soft).leftEar, 0.7)
        XCTAssertGreaterThan(motion.sample(at: 42, idleTime: 38.4, expression: .soft).lick, 0.9)
        XCTAssertGreaterThan(motion.sample(at: 58, idleTime: 54.4, expression: .soft).mouthOpen, 0.9)
        for time in [0.0, 5, 9, 15, 21, 25] {
            let quiet = motion.sample(at: time, idleTime: time, expression: .soft)
            XCTAssertEqual(quiet.tongue + quiet.lick + quiet.leftEar + quiet.rightEar + quiet.mouthOpen, 0)
        }
        XCTAssertEqual(motion.sample(at: 10, idleTime: nil, expression: .soft).tongue, 0)
    }

    func testCatHasSlowBlinkWhiskerAndSniffActionsInsteadOfDogIdleActions() {
        let motion = BloudPawMotion()
        let blink = motion.sample(at: 10, idleTime: 7.8, expression: .soft, isCat: true)
        XCTAssertGreaterThan(blink.eyeClosure.x, 0.9)
        XCTAssertEqual(blink.tongue + blink.lick + blink.mouthOpen, 0)
        let attention = motion.sample(at: 30, idleTime: 26.8, expression: .soft, isCat: true)
        XCTAssertGreaterThan(attention.whiskerSpread, 0.6)
        let sniff = motion.sample(at: 50, idleTime: 45.8, expression: .soft, isCat: true)
        XCTAssertGreaterThan(sniff.noseLift, 0.6)
        let paused = motion.sample(at: 50, idleTime: nil, expression: .soft, isCat: true)
        XCTAssertEqual(paused.eyeClosure, .zero)
        XCTAssertEqual(paused.whiskerSpread + paused.noseLift, 0)
    }

    func testCatForeheadContactSquintsWithoutTongueAndReducedMotionStopsSniffing() {
        var motion = BloudPawMotion()
        motion.follow(touch(0, -0.5), at: 10)
        let cat = motion.sample(at: 10.2, idleTime: nil, expression: .soft, isCat: true)
        XCTAssertGreaterThan(cat.eyeClosure.x, 0.6)
        XCTAssertEqual(cat.tongue + cat.lick, 0)
        XCTAssertGreaterThan(motion.sample(at: 10.2, idleTime: nil, expression: .soft).tongue, 0.6)
        motion.follow(nil, at: 11)
        motion.follow(touch(0, 0), at: 12)
        let reduced = motion.sample(at: 12.2, idleTime: 45.8, expression: .soft, reducedMotion: true, isCat: true)
        XCTAssertEqual(reduced.noseLift + reduced.whiskerSpread + reduced.leftEar + reduced.rightEar, 0)
        XCTAssertEqual(reduced.drag, .zero)
    }

    func testReduceMotionKeepsContactExpressionWithoutDeformationOrIdleMotion() {
        var motion = BloudPawMotion()
        motion.follow(touch(0.6, 0.3, drag: SIMD2(1, 1)), at: 10)
        let reduced = motion.sample(at: 11, idleTime: 6.4, expression: .soft, reducedMotion: true)
        XCTAssertGreaterThan(reduced.disgust, 0)
        XCTAssertEqual(reduced.pinch, 0)
        XCTAssertEqual(reduced.drag, .zero)
        XCTAssertEqual(reduced.leftEar + reduced.rightEar + reduced.tongue, 0)
    }
}
