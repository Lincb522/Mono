import Foundation

/// The caller supplies monotonic uptime, so changing the system clock is harmless.
struct ShibaPlayback {
    private(set) var accumulated: TimeInterval = 0
    private(set) var anchor: TimeInterval?
    private(set) var isFinished = false

    var isRunning: Bool { anchor != nil && !isFinished }

    func elapsed(at now: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let runningTime = anchor.map { max(0, now - $0) } ?? 0
        return min(duration, max(0, accumulated + runningTime))
    }

    mutating func restart(at now: TimeInterval, running: Bool) {
        accumulated = 0
        anchor = running ? now : nil
        isFinished = false
    }

    mutating func pause(at now: TimeInterval) {
        guard let previousAnchor = anchor else { return }
        accumulated += max(0, now - previousAnchor)
        anchor = nil
    }

    mutating func resume(at now: TimeInterval) {
        guard anchor == nil, !isFinished else { return }
        anchor = now
    }

    mutating func finish(duration: TimeInterval) {
        accumulated = duration
        anchor = nil
        isFinished = true
    }
}
