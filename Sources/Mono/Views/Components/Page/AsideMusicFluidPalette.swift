import Foundation

struct AsideMusicFluidPalette: Equatable {
    let first: SIMD3<Double>
    let middle: SIMD3<Double>
    let last: SIMD3<Double>

    func interpolated(to other: Self, fraction: Double) -> Self {
        Self(
            first: first + (other.first - first) * fraction,
            middle: middle + (other.middle - middle) * fraction,
            last: last + (other.last - last) * fraction
        )
    }
}

/// A new cover starts from the colors currently on screen, including an unfinished fade.
struct AsideMusicFluidPaletteTransition {
    static let duration: TimeInterval = 1.2

    private(set) var target: AsideMusicFluidPalette?
    private(set) var isAnimating = false
    private var source: AsideMusicFluidPalette?
    private var startedAt: TimeInterval = 0

    var completionTime: TimeInterval? {
        isAnimating ? startedAt + Self.duration : nil
    }

    mutating func update(to palette: AsideMusicFluidPalette, at time: TimeInterval) {
        guard target != palette else { return }
        source = value(at: time) ?? palette
        target = palette
        startedAt = time
        isAnimating = source != palette
    }

    func value(at time: TimeInterval) -> AsideMusicFluidPalette? {
        guard let target, let source else { return target }
        let progress = min(max((time - startedAt) / Self.duration, 0), 1)
        let fraction = progress * progress * (3 - 2 * progress)
        return source.interpolated(to: target, fraction: fraction)
    }

    mutating func finishIfNeeded(at time: TimeInterval) {
        guard isAnimating, time >= startedAt + Self.duration else { return }
        source = target
        isAnimating = false
    }
}
