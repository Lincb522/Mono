import XCTest
@testable import Mono

final class BloudCharacterTests: XCTestCase {
    func testCatalogTagsChooseExpressionsWithSpecificTagsBeforeGenericPop() {
        XCTAssertEqual(BloudTagExpression.resolve(["流行-华语流行", "思念"]), .shy)
        XCTAssertEqual(BloudTagExpression.resolve(["Pop", "Electronic"]), .excited)
        XCTAssertEqual(BloudTagExpression.resolve(["Pop", "Hip-Hop/Rap"]), .proud)
        XCTAssertEqual(BloudTagExpression.resolve(["Jazz"]), .curious)
        XCTAssertEqual(BloudTagExpression.resolve(["古典-钢琴"]), .attentive)
        XCTAssertEqual(BloudTagExpression.resolve(["氛围/助眠"]), .sleepy)
        XCTAssertEqual(BloudTagExpression.resolve(["Cantopop"]), .happy)
        XCTAssertEqual(BloudTagExpression.resolve(["Dark Ambient"]), .scared)
    }

    func testMissingAndUnrelatedTagsRemainUnresolved() {
        XCTAssertNil(BloudTagExpression.resolve([]))
        XCTAssertNil(BloudTagExpression.resolve(["Music", "2026", "VIP", "国语"]))
        XCTAssertNil(BloudTagExpression.resolve(["scrapbook"]))
    }

    func testAllReferenceExpressionsHaveDistinctPoses() {
        let expressions = BloudExpression.allCases
        XCTAssertEqual(expressions.count, 24)
        for (index, expression) in expressions.enumerated() {
            for other in expressions.dropFirst(index + 1) {
                XCTAssertNotEqual(expression.pose, other.pose)
            }
        }
    }

    func testExpressionMorphKeepsEndpointsAndMirroredEyeTilts() {
        let start = BloudExpression.angry.pose
        let end = BloudExpression.sad.pose
        XCTAssertEqual(start.blended(to: end, fraction: -1), start)
        XCTAssertEqual(start.blended(to: end, fraction: 2), end)
        let middle = start.blended(to: end, fraction: 0.5)
        XCTAssertEqual(middle.left.tilt, -middle.right.tilt)
        XCTAssertEqual(middle.left.height, (start.left.height + end.left.height) / 2)
    }
    func testGazeStartsContinuouslyAndKeepsVelocityWhenRetargeted() {
        var spring = BloudGazeSpring()
        spring.follow(SIMD2(38, -30), at: 100, returning: false)
        XCTAssertEqual(spring.sample(at: 100).position, .zero)
        let moving = spring.sample(at: 100.12)
        XCTAssertGreaterThan(moving.position.x, 0)
        XCTAssertLessThan(moving.position.x, 26)
        XCTAssertGreaterThan(spring.sample(at: 100.2).position.x, 27)
        spring.follow(SIMD2(-38, 20), at: 100.12, returning: false)
        XCTAssertEqual(spring.sample(at: 100.12).position, moving.position)
        XCTAssertEqual(spring.sample(at: 100.12).velocity, moving.velocity)
        XCTAssertEqual(spring.sample(at: 102).position.x, -38, accuracy: 0.01)
    }

    func testGazeReturnAlsoSettlesWithoutJumping() {
        var spring = BloudGazeSpring()
        spring.follow(SIMD2(38, 20), at: 10, returning: false)
        let before = spring.sample(at: 11)
        spring.follow(.zero, at: 11, returning: true)
        XCTAssertEqual(spring.sample(at: 11).position, before.position)
        XCTAssertGreaterThan(spring.sample(at: 11.1).position.x, 25)
        XCTAssertLessThan(spring.sample(at: 12.6).position.x, 0.1)
    }

    func testStrongAudioAttackClosesEyelidsSmoothlyAndReopensWithoutMoreFrames() {
        var motion = BloudAudioMotion()
        motion.ingest(.init(time: 10, rmsDB: -30, bass: 0.2))
        XCTAssertEqual(motion.eyeOpenness(at: 10).x, 1)
        motion.ingest(.init(time: 10.05, rmsDB: -20, bass: 0.5))
        XCTAssertEqual(motion.eyeOpenness(at: 10.05).x, 1)
        XCTAssertLessThan(motion.eyeOpenness(at: 10.17).x, 0.01)
        XCTAssertEqual(motion.eyeOpenness(at: 10.4).x, 1)
    }

    func testRapidDrumsDoNotRetriggerAFullBlinkEveryBeat() {
        var motion = BloudAudioMotion()
        motion.ingest(.init(time: 10, rmsDB: -30, bass: 0.2))
        motion.ingest(.init(time: 10.05, rmsDB: -20, bass: 0.5))
        for index in 1...6 {
            let time = 10.05 + Double(index) * 0.5
            motion.ingest(.init(time: time - 0.05, rmsDB: -30, bass: 0.2))
            motion.ingest(.init(time: time, rmsDB: -20, bass: 0.5))
            XCTAssertEqual(motion.eyeOpenness(at: time + 0.12).x, 1)
        }
        motion.ingest(.init(time: 13.5, rmsDB: -30, bass: 0.2))
        motion.ingest(.init(time: 13.55, rmsDB: -20, bass: 0.5))
        XCTAssertGreaterThan(motion.eyeOpenness(at: 13.67).x, 1)
    }

    func testSoftAudioAttackOnlyPartiallyClosesEyelids() {
        var motion = BloudAudioMotion()
        motion.ingest(.init(time: 10, rmsDB: -30, bass: 0.2))
        motion.ingest(.init(time: 10.05, rmsDB: -27.5, bass: 0.2))
        let openness = motion.eyeOpenness(at: 10.375).x
        XCTAssertGreaterThan(openness, 0.6)
        XCTAssertLessThan(openness, 0.95)
        for index in 1...4 {
            let time = 10.05 + Double(index) * 0.5
            motion.ingest(.init(time: time - 0.05, rmsDB: -30, bass: 0.2))
            motion.ingest(.init(time: time, rmsDB: -27.5, bass: 0.2))
            XCTAssertEqual(motion.eyeOpenness(at: time + 0.16).x, 1)
        }
    }

    func testResumingAfterPauseDoesNotCreateAnAudioAttack() {
        var motion = BloudAudioMotion()
        for index in 0..<60 {
            motion.ingest(.init(time: Double(index) * 0.05, rmsDB: -30, bass: 0.7))
        }
        motion.ingest(.init(time: 100, rmsDB: -12, bass: 0.7))
        XCTAssertEqual(motion.eyeOpenness(at: 100).x, 1)
    }

    func testRepeatedStrongBeatsVaryBothEyesAndReturnToTheBasePose() {
        var motion = BloudAudioMotion()
        var peaks: [SIMD2<Double>] = []
        let peakDelays = [0.12, 0.275, 0.19, 0.19, 0.325, 0.3, 0.3, 0.35, 0.25]
        for (index, delay) in peakDelays.enumerated() {
            let time = 10 + Double(index) * 4
            motion.ingest(.init(time: time, rmsDB: -30, bass: 0.2))
            motion.ingest(.init(time: time + 0.05, rmsDB: -20, bass: 0.5))
            peaks.append(motion.eyeOpenness(at: time + 0.05 + delay))
            XCTAssertEqual(motion.eyeOpenness(at: time + 1), SIMD2<Double>(repeating: 1))
        }
        XCTAssertLessThan(peaks[0].x, 0.01)
        XCTAssertGreaterThan(peaks[1].x, 1)
        XCTAssertLessThan(peaks[2].x, peaks[2].y)
        XCTAssertGreaterThan(peaks[3].x, peaks[3].y)
        XCTAssertEqual(peaks[4].x, peaks[4].y)
        XCTAssertGreaterThan(peaks[4].x, 0.5)
        XCTAssertLessThan(peaks[4].x, 1)
        XCTAssertGreaterThan(peaks[5].x, 1)
        XCTAssertLessThan(peaks[5].y, 1)
        XCTAssertGreaterThan(peaks[6].y, 1)
        XCTAssertLessThan(peaks[6].x, 1)
        XCTAssertGreaterThan(peaks[7].x, peaks[7].y)
        XCTAssertLessThan(peaks[8].x, 0.1)
    }

    func testSpectrumMeasurementRejectsSilenceAndUsesFrequencyBands() {
        var spectrum = Array(repeating: Float(0), count: 2048)
        spectrum[5] = 0.01
        let low = BloudAudioFrame.measure(spectrum, rate: 44100, rms: 0.1, time: 0)
        XCTAssertEqual(low?.bass, 1)
        XCTAssertEqual(low?.rmsDB, -20)
        XCTAssertNil(BloudAudioFrame.measure(spectrum, rate: 44100, rms: 0, time: 0))
        XCTAssertNil(BloudAudioFrame.measure(spectrum, rate: .nan, rms: 0.1, time: 0))
    }

    func testHandFocusConvertsVisionOriginWithoutMirroringTwice() {
        var focus = BloudHandFocus()
        let point = focus.update(visionPoint: CGPoint(x: 0.2, y: 0.8), confidence: 0.9, at: 1)
        XCTAssertEqual(point?.x ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 0.2, accuracy: 0.0001)
    }

    func testHandFocusHoldsThroughBriefOcclusionThenReleases() {
        var focus = BloudHandFocus()
        let start = focus.update(visionPoint: CGPoint(x: 0.4, y: 0.6), confidence: 0.9, at: 1)
        XCTAssertEqual(focus.update(visionPoint: nil, confidence: 0, at: 1.3), start)
        XCTAssertNil(focus.update(visionPoint: nil, confidence: 0, at: 1.5))
        XCTAssertNil(focus.update(visionPoint: CGPoint(x: 0.8, y: 0.1), confidence: 0.2, at: 1.6))
    }

    func testHandFocusSuppressesTinyJitterAndRejectsInvalidPoints() {
        var focus = BloudHandFocus()
        let start = focus.update(visionPoint: CGPoint(x: 0.4, y: 0.6), confidence: 0.9, at: 1)
        XCTAssertEqual(focus.update(visionPoint: CGPoint(x: 0.4008, y: 0.6005), confidence: 0.9, at: 1.1), start)
        XCTAssertNotEqual(focus.update(visionPoint: CGPoint(x: 0.402, y: 0.6), confidence: 0.9, at: 1.2), start)
        XCTAssertNil(focus.update(visionPoint: CGPoint(x: CGFloat.nan, y: 0.1), confidence: 1, at: 2))
    }

    func testCameraGazeUsesLensCenterAndRespondsToSmallFingerMovement() {
        XCTAssertEqual(BloudCameraGaze.target(for: CGPoint(x: 0.5, y: 0.5)), .zero)
        let moved = BloudCameraGaze.target(for: CGPoint(x: 0.52, y: 0.48))
        XCTAssertEqual(moved.x, 2.128, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 1.68, accuracy: 0.0001)
        XCTAssertEqual(BloudCameraGaze.target(for: CGPoint(x: 2, y: -1)), SIMD2(38, 30))
        XCTAssertEqual(BloudCameraGaze.target(for: CGPoint(x: CGFloat.nan, y: 0.5)), .zero)
    }

}
