import Foundation

public enum ShibaAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    case welcome, appear, nod, tilt, blink, breathe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .appear: return "探身"
        case .nod: return "点头"
        case .tilt: return "歪头"
        case .blink: return "眨眼"
        case .breathe: return "呼吸"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .welcome: return 4.6
        case .appear: return 2.4
        case .nod, .blink: return 2.6
        case .tilt: return 3.2
        case .breathe: return 3.6
        }
    }
}

struct ShibaPose {
    var tilt: Float = 0
    var nod: Float = 0
    var breath: Float = 0
    var blink: Float = 0
    var tail: Float = 0
    var offsetY: Float = 0
    var scale: Float = 1
    var opacity: Float = 1
}

enum ShibaMotion {
    static func pose(for action: ShibaAction, at time: TimeInterval) -> ShibaPose {
        let t = Float(min(action.duration, max(0, time)))
        var p = ShibaPose()

        switch action {
        case .welcome:
            let enter = ramp(t, 0, 0.85)
            p.offsetY = 0.16 * (1 - enter)
            p.scale = 0.97 + 0.03 * enter
            p.opacity = enter
            p.nod = pulse(t, 0.9, 1.24, 1.42, 1.95)
            p.tilt = -0.085 * pulse(t, 1.85, 2.45, 2.95, 3.85)
            p.blink = max(eye(t, 1.28), eye(t, 3.35))
            p.tail = 0.11 * sine(t * 6) * pulse(t, 0.8, 1.4, 3.5, 4.2)
        case .appear:
            let enter = ramp(t, 0, 1)
            p.offsetY = 0.2 * (1 - enter)
            p.scale = 0.96 + 0.04 * enter
            p.opacity = enter
            p.nod = 0.28 * pulse(t, 1, 1.2, 1.4, 2)
        case .nod:
            p.nod = pulse(t, 0.22, 0.7, 1.02, 1.62)
                + 0.34 * pulse(t, 1.6, 1.85, 1.95, 2.4)
            p.blink = eye(t, 0.82)
        case .tilt:
            p.tilt = -0.12 * pulse(t, 0.1, 0.8, 1.22, 2.05)
                + 0.06 * pulse(t, 1.65, 2.25, 2.45, 3.1)
            p.blink = eye(t, 1.03)
        case .blink:
            p.blink = max(eye(t, 0.55), eye(t, 1.1))
            p.nod = 0.15 * pulse(t, 0.3, 0.65, 1.3, 2.1)
        case .breathe:
            let phase = t / Float(action.duration)
            p.breath = 0.5 - 0.5 * cosine(phase * .pi * 2)
            p.blink = eye(t, 2.15)
            let envelope = sine(phase * .pi)
            p.tail = 0.06 * sine(t * 4) * envelope * envelope
        }
        return p
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private static func sine(_ value: Float) -> Float { Float(sin(Double(value))) }
    private static func cosine(_ value: Float) -> Float { Float(cos(Double(value))) }

    private static func ramp(_ t: Float, _ a: Float, _ b: Float) -> Float {
        smooth((t - a) / (b - a))
    }

    private static func pulse(
        _ t: Float, _ a: Float, _ b: Float, _ c: Float, _ d: Float
    ) -> Float {
        ramp(t, a, b) * (1 - ramp(t, c, d))
    }

    private static func eye(_ t: Float, _ a: Float) -> Float {
        pulse(t, a, a + 0.095, a + 0.13, a + 0.26)
    }
}
