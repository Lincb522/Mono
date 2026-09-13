import SwiftUI
import XCTest
@testable import Mono

final class WelcomeAnimationDriverTests: XCTestCase {
    @MainActor
    func testCompletedAnimationAppliesUpdateOnce() async throws {
        var updateCount = 0
        try await WelcomeAnimationDriver.animate(.linear(duration: 0), fallbackDuration: 0) {
            updateCount += 1
        }
        XCTAssertEqual(updateCount, 1)
    }

    @MainActor
    func testCancelledEntranceDoesNotApplyDelayedUpdate() async {
        var updateCount = 0
        let task = Task { @MainActor in
            try await WelcomeAnimationDriver.animate(.linear(duration: 0), fallbackDuration: 0, delay: 0.15) {
                updateCount += 1
            }
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("A cancelled entrance must not reach its update.")
        } catch is CancellationError {
            XCTAssertEqual(updateCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testCancellationAtCompletionDoesNotContinueToSceneMount() async {
        var mounted = false
        let task = Task { @MainActor in
            try await WelcomeAnimationDriver.animate(.linear(duration: 0), fallbackDuration: 0) {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            mounted = true
        }

        do {
            try await task.value
            XCTFail("A cancelled animation must not advance to the next scene.")
        } catch is CancellationError {
            XCTAssertFalse(mounted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
