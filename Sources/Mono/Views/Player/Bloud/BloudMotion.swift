import Foundation

/// Analytic critically damped motion preserves velocity when the finger changes direction.
struct BloudGazeSpring {
    var origin: SIMD2<Double> = .zero
    var velocity: SIMD2<Double> = .zero
    var target: SIMD2<Double> = .zero
    var startedAt: TimeInterval = 0
    var response: Double = 14

    func sample(at time: TimeInterval) -> (position: SIMD2<Double>, velocity: SIMD2<Double>) {
        let t = max(0, time - startedAt)
        let delta = origin - target
        let c = velocity + delta * response
        let decay = exp(-response * t)
        return (target + (delta + c * t) * decay, (velocity - c * (response * t)) * decay)
    }

    mutating func follow(_ next: SIMD2<Double>, at time: TimeInterval, returning: Bool) {
        let current = sample(at: time)
        origin = current.position
        velocity = current.velocity
        target = next
        startedAt = time
        response = returning ? 6 : 14
    }
}

struct BloudAudioFrame: Sendable {
    let time: TimeInterval
    let rmsDB: Float
    let bass: Float

    nonisolated static func measure(_ spectrum: [Float], rate: Double, rms: Float,
                                   time: TimeInterval) -> Self? {
        guard spectrum.count > 16, rate.isFinite, rate > 0, rms.isFinite, rms > 0.000_1 else { return nil }
        var low: Float = 0, total: Float = 0
        let bin = Float(rate / Double(spectrum.count * 2))
        for (index, magnitude) in spectrum.enumerated() where magnitude.isFinite {
            let frequency = Float(index) * bin
            guard frequency >= 30, frequency <= 16_000 else { continue }
            let power = magnitude * magnitude
            total += power
            if frequency < 250 { low += power }
        }
        guard total.isFinite, total > 1e-16 else { return nil }
        return .init(time: time, rmsDB: 20 * log10f(rms), bass: low / total)
    }
}

/// Audio attacks vary the eyes while the song keeps its chosen expression.
struct BloudAudioMotion {
    private enum Reaction: Equatable {
        case blink, squint, leftWink, rightWink, widen, leftLift, rightLift, asymmetricSquint, slowBlink

        var duration: TimeInterval {
            switch self {
            case .blink: return 0.24
            case .squint: return 0.65
            case .leftWink, .rightWink: return 0.38
            case .widen: return 0.55
            case .leftLift, .rightLift: return 0.6
            case .asymmetricSquint: return 0.7
            case .slowBlink: return 0.5
            }
        }
    }

    private var reaction: Reaction = .blink
    private var reactionIndex = 0
    private var startedAt: TimeInterval = -.infinity
    private var strength: Double = 0
    private var strongAttack = false
    private var previous: BloudAudioFrame?

    func eyeOpenness(at time: TimeInterval) -> SIMD2<Double> {
        let phase = (time - startedAt) / reaction.duration
        guard phase > 0, phase < 1 else { return SIMD2(repeating: 1) }
        let wave = sin(.pi * phase)
        let envelope = wave * wave
        let delta: SIMD2<Double>
        switch reaction {
        case .blink:
            delta = SIMD2(repeating: -1)
        case .squint:
            delta = SIMD2(repeating: -(0.12 + strength * 0.32))
        case .leftWink:
            delta = SIMD2(strongAttack ? -0.85 : -0.45, -0.04)
        case .rightWink:
            delta = SIMD2(-0.04, strongAttack ? -0.85 : -0.45)
        case .widen:
            delta = SIMD2(repeating: 0.1 + strength * 0.1)
        case .leftLift:
            delta = SIMD2(0.12 + strength * 0.08, -0.08)
        case .rightLift:
            delta = SIMD2(-0.08, 0.12 + strength * 0.08)
        case .asymmetricSquint:
            delta = SIMD2(-0.12, -(0.2 + strength * 0.15))
        case .slowBlink:
            delta = SIMD2(repeating: -0.92)
        }
        return SIMD2(repeating: 1) + delta * envelope
    }

    mutating func ingest(_ frame: BloudAudioFrame) {
        let dt = previous.map { frame.time - $0.time } ?? 0
        let continuous = dt > 0 && dt < 0.75
        let rise = continuous ? max(0, frame.rmsDB - (previous?.rmsDB ?? frame.rmsDB)) : 0
        let bassAttack = continuous ? max(0, frame.bass - (previous?.bass ?? frame.bass)) : 0
        let attack = min(1, Double(rise) / 7 + Double(bassAttack) * 3)
        let interval = strongAttack ? 3.2 : 2.2
        if attack >= 0.28, frame.time - startedAt >= interval {
            let strong = attack >= 0.7
            let options: [Reaction] = strong
                ? [.blink, .widen, .leftWink, .rightWink, .squint, .leftLift, .rightLift, .asymmetricSquint, .slowBlink]
                : [.squint, .leftWink, .widen, .rightWink, .leftLift, .rightLift, .asymmetricSquint]
            var next = options[reactionIndex % options.count]
            reactionIndex = (reactionIndex + 1) % 63
            if startedAt.isFinite, next == reaction {
                next = options[reactionIndex % options.count]
                reactionIndex = (reactionIndex + 1) % 63
            }
            reaction = next
            startedAt = frame.time
            strength = attack
            strongAttack = strong
        }
        previous = frame
    }
}

/// Camera coordinates remain centered on the lens, independently of player layout and safe areas.
enum BloudCameraGaze {
    static func target(for point: CGPoint) -> SIMD2<Double> {
        guard point.x.isFinite, point.y.isFinite else { return .zero }
        let x = min(1, max(-1, (Double(point.x) - 0.5) * 2.8))
        let y = min(1, max(-1, (Double(point.y) - 0.5) * 2.8))
        return SIMD2(x * 38, -y * 30)
    }
}
