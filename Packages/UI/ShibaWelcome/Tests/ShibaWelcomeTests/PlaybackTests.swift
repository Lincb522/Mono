import XCTest
@testable import ShibaWelcome

final class PlaybackTests: XCTestCase {
    func testBackgroundTimeDoesNotSkipAnimation() {
        var clock = ShibaPlayback()
        clock.restart(at: 100, running: true)
        clock.pause(at: 101.25)
        XCTAssertEqual(clock.elapsed(at: 400, duration: 4.6), 1.25, accuracy: 0.0001)
        clock.resume(at: 400)
        XCTAssertEqual(clock.elapsed(at: 400.5, duration: 4.6), 1.75, accuracy: 0.0001)
    }

    func testFinishCannotResumeUntilExplicitReplay() {
        var clock = ShibaPlayback()
        clock.restart(at: 0, running: true)
        clock.finish(duration: 4.6)
        clock.resume(at: 100)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 200, duration: 4.6), 4.6, accuracy: 0.0001)
        clock.restart(at: 200, running: true)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 200.25, duration: 4.6), 0.25, accuracy: 0.0001)
    }

    func testReplayRequestedWhileInactiveWaitsForForeground() {
        var clock = ShibaPlayback()
        clock.restart(at: 10, running: false)
        XCTAssertEqual(clock.elapsed(at: 50, duration: 3.2), 0)
        clock.resume(at: 50)
        XCTAssertEqual(clock.elapsed(at: 50.5, duration: 3.2), 0.5, accuracy: 0.0001)
    }
}
