import SwiftUI

@MainActor
enum WelcomeAnimationDriver {
    /// Await the actual animation boundary before mounting or removing the main scene.
    static func animate(
        _ animation: Animation,
        fallbackDuration: TimeInterval,
        delay: TimeInterval = 0,
        updates: @escaping @MainActor () -> Void
    ) async throws {
        try await sleep(seconds: delay)

        if #available(iOS 17.0, *) {
            await withCheckedContinuation { continuation in
                withAnimation(animation, completionCriteria: .logicallyComplete) {
                    updates()
                } completion: {
                    continuation.resume()
                }
            }
        } else {
            withAnimation(animation) {
                updates()
            }
            try await sleep(seconds: fallbackDuration)
        }

        try Task.checkCancellation()
    }

    static func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
