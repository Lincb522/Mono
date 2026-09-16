import Foundation

/// Coordinates are normalized to the character square, not the player or screen.
struct BloudPawTouch: Equatable {
    let origin: SIMD2<Double>
    let location: SIMD2<Double>
    let translation: SIMD2<Double>
}

/// Contact feedback is temporary and never changes the song's selected expression.
struct BloudPawMotion {
    struct Frame {
        var side: Double = 1
        var pinch: Double = 0
        var disgust: Double = 0
        var comfort: Double = 0
        var drag: SIMD2<Double> = .zero
        var leftEar: Double = 0
        var rightEar: Double = 0
        var tongue: Double = 0
        var lick: Double = 0
        var mouthOpen: Double = 0
        var eyeClosure: SIMD2<Double> = .zero
        var whiskerSpread: Double = 0
        var noseLift: Double = 0
    }

    private enum Zone: Equatable { case cheek, forehead, nose }
    private var zone: Zone = .cheek
    private var side: Double = 1
    private var contact = false
    private var beganAt: TimeInterval = -.infinity
    private var pressure = BloudGazeSpring()
    private var drag = BloudGazeSpring()

    mutating func follow(_ touch: BloudPawTouch?, at time: TimeInterval) {
        if let touch {
            if !contact {
                beganAt = time
                side = touch.origin.x < 0 ? -1 : 1
                zone = touch.origin.y < -0.28 ? .forehead : (abs(touch.origin.x) > 0.22 ? .cheek : .nose)
            }
            pressure.follow(SIMD2(1, 0), at: time, returning: false)
            if zone == .cheek { pressure.response = 10 }
            drag.follow(SIMD2(min(1, max(-1, touch.translation.x)) * 7,
                              min(1, max(-1, touch.translation.y)) * 5), at: time, returning: false)
        } else {
            pressure.follow(.zero, at: time, returning: true)
            drag.follow(.zero, at: time, returning: true)
        }
        contact = touch != nil
    }

    func sample(at time: TimeInterval, idleTime: TimeInterval?, expression: PawExpression,
                reducedMotion: Bool = false, isCat: Bool = false) -> Frame {
        let elapsed = time - beganAt
        // Even a quick tap gets a complete response; holding sustains it without retriggering.
        let tap = zone == .cheek
            ? Self.pulse(elapsed, rise: 0.28, hold: 0.12, fall: 0.9)
            : Self.pulse(elapsed, rise: 0.16, hold: 0.18, fall: 0.65)
        let amount = reducedMotion ? ((contact || (elapsed >= 0 && elapsed < (zone == .cheek ? 1.3 : 0.99))) ? 0.65 : 0) : min(1, max(tap, pressure.sample(at: time).position.x))
        var result = Frame()
        result.side = side
        result.drag = reducedMotion ? .zero : drag.sample(at: time).position
        switch zone {
        case .cheek:
            result.pinch = reducedMotion ? 0 : amount
            result.disgust = amount * 0.28
            result.leftEar = amount * (side < 0 ? 0.12 : 0.04)
            result.rightEar = amount * (side > 0 ? 0.12 : 0.04)
        case .forehead:
            result.comfort = amount
            result.leftEar = amount * 0.6
            result.rightEar = amount * 0.6
            result.tongue = amount * 0.7
        case .nose:
            result.lick = amount
            result.leftEar = amount * 0.2
            result.rightEar = amount * 0.2
        }
        if isCat {
            result.tongue = 0
            result.lick = 0
            result.leftEar *= 0.4
            result.rightEar *= 0.4
            switch zone {
            case .cheek:
                result.pinch *= 0.55
                result.disgust *= 0.45
                result.eyeClosure = SIMD2(repeating: amount * 0.25)
            case .forehead:
                result.comfort *= 0.45
                result.eyeClosure = SIMD2(repeating: amount * 0.65)
            case .nose:
                result.noseLift = amount * 0.7
                result.whiskerSpread = amount * 0.3
            }
        }
        if reducedMotion {
            result.leftEar = 0
            result.rightEar = 0
            result.noseLift = 0
            result.whiskerSpread = 0
            return result
        }
        guard let idleTime, idleTime.isFinite, idleTime >= 0 else { return result }
        if isCat {
            // A cat pauses between slow blinks, whisker attention, sniffing and ear listening.
            let cycle = Int((idleTime / 19).truncatingRemainder(dividingBy: 4))
            let phase = idleTime.truncatingRemainder(dividingBy: 19) - 7
            let idle = Self.pulse(phase, rise: 0.65, hold: 0.35, fall: 1.1) * (1 - amount)
            switch cycle {
            case 0:
                result.eyeClosure.x = max(result.eyeClosure.x, idle * 0.92)
                result.eyeClosure.y = max(result.eyeClosure.y,
                    Self.pulse(phase - 0.1, rise: 0.65, hold: 0.35, fall: 1.1) * (1 - amount) * 0.92)
            case 1:
                result.whiskerSpread = max(result.whiskerSpread, idle * 0.7)
                result.eyeClosure += SIMD2(repeating: idle * 0.2)
                result.leftEar += idle * 0.14
            case 2:
                result.noseLift = max(result.noseLift, idle * 0.65)
                result.whiskerSpread = max(result.whiskerSpread, idle * 0.3)
            default:
                result.leftEar += idle * 0.24
                result.rightEar += Self.pulse(phase - 0.3, rise: 0.4, hold: 0.2, fall: 0.9) * (1 - amount) * 0.18
                result.eyeClosure += SIMD2(repeating: idle * 0.15)
            }
            return result
        }
        // One brief action per 16 seconds, with a quiet interval between actions.
        let cycle = Int((idleTime / 16).truncatingRemainder(dividingBy: 4))
        let phase = idleTime.truncatingRemainder(dividingBy: 16) - 6
        let idle = Self.pulse(phase, rise: 0.3, hold: 0.65, fall: 0.7) * (1 - amount)
        let action = (expression == .drowsy || expression == .sleeping) && cycle == 0 ? 3 : cycle
        switch action {
        case 0:
            let peek = Self.pulse(phase, rise: 0.26, hold: 0.22, fall: 0.48) * (1 - amount)
            result.tongue = max(result.tongue, peek)
            result.comfort = max(result.comfort, peek * 0.18)
        case 1:
            result.leftEar += idle * 0.8
            result.rightEar += Self.pulse(phase - 0.22, rise: 0.18, hold: 0.1, fall: 0.45) * 0.5 * (1 - amount)
        case 2:
            result.lick = max(result.lick, idle)
        default:
            result.mouthOpen = idle
            result.comfort = max(result.comfort, idle * 0.7)
        }
        return result
    }

    private static func pulse(_ time: TimeInterval, rise: Double, hold: Double, fall: Double) -> Double {
        guard time.isFinite, time > 0, time < rise + hold + fall else { return 0 }
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if time < rise { return smooth(time / rise) }
        if time < rise + hold { return 1 }
        return 1 - smooth((time - rise - hold) / fall)
    }
}
