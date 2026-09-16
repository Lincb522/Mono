import SwiftUI

/// Figma PAW CAT component 28:3: exported 480-point SVG normalized to 120 points.
/// Static geometry and colors retain the SVG values; animation is applied by the renderer.
enum PawCatArtwork {
    static let head = Path { p in
        p.move(to: CGPoint(x: 21, y: 42))
        p.addCurve(to: CGPoint(x: 27.5, y: 16.1), control1: CGPoint(x: 20.1, y: 33), control2: CGPoint(x: 20.8, y: 18.2))
        p.addCurve(to: CGPoint(x: 46.2, y: 26.7), control1: CGPoint(x: 33.1, y: 14.4), control2: CGPoint(x: 41.2, y: 21.3))
        p.addCurve(to: CGPoint(x: 73.8, y: 26.7), control1: CGPoint(x: 54.7, y: 24.5), control2: CGPoint(x: 64.9, y: 24.5))
        p.addCurve(to: CGPoint(x: 92.5, y: 16.1), control1: CGPoint(x: 78.8, y: 21.3), control2: CGPoint(x: 86.9, y: 14.4))
        p.addCurve(to: CGPoint(x: 99, y: 42), control1: CGPoint(x: 99.2, y: 18.2), control2: CGPoint(x: 99.9, y: 33))
        p.addCurve(to: CGPoint(x: 105.5, y: 65), control1: CGPoint(x: 104, y: 49.2), control2: CGPoint(x: 105.5, y: 56.4))
        p.addCurve(to: CGPoint(x: 60, y: 101.1), control1: CGPoint(x: 105.5, y: 86.8), control2: CGPoint(x: 89.3, y: 101.1))
        p.addCurve(to: CGPoint(x: 14.5, y: 65), control1: CGPoint(x: 30.7, y: 101.1), control2: CGPoint(x: 14.5, y: 86.8))
        p.addCurve(to: CGPoint(x: 21, y: 42), control1: CGPoint(x: 14.5, y: 56.4), control2: CGPoint(x: 16, y: 49.2))
        p.closeSubpath()
    }

    static let leftEar = Path { p in
        p.move(to: CGPoint(x: 26.2, y: 38.7))
        p.addCurve(to: CGPoint(x: 29, y: 23.1), control1: CGPoint(x: 25.4, y: 32.7), control2: CGPoint(x: 26.3, y: 24))
        p.addCurve(to: CGPoint(x: 40.4, y: 30.5), control1: CGPoint(x: 31.9, y: 22.1), control2: CGPoint(x: 37.7, y: 27.1))
        p.addCurve(to: CGPoint(x: 26.2, y: 38.7), control1: CGPoint(x: 35.5, y: 32.1), control2: CGPoint(x: 30.8, y: 35))
        p.closeSubpath()
    }

    static let rightEar = Path { p in
        p.move(to: CGPoint(x: 93.8, y: 38.7))
        p.addCurve(to: CGPoint(x: 91, y: 23.1), control1: CGPoint(x: 94.6, y: 32.7), control2: CGPoint(x: 93.7, y: 24))
        p.addCurve(to: CGPoint(x: 79.6, y: 30.5), control1: CGPoint(x: 88.1, y: 22.1), control2: CGPoint(x: 82.3, y: 27.1))
        p.addCurve(to: CGPoint(x: 93.8, y: 38.7), control1: CGPoint(x: 84.5, y: 32.1), control2: CGPoint(x: 89.2, y: 35))
        p.closeSubpath()
    }

    static let stripes = Path { p in
        p.move(to: CGPoint(x: 44.1, y: 29.5))
        p.addCurve(to: CGPoint(x: 51.8, y: 28.2), control1: CGPoint(x: 46.5, y: 28.9), control2: CGPoint(x: 49.1, y: 28.4))
        p.addCurve(to: CGPoint(x: 50, y: 42.3), control1: CGPoint(x: 52.1, y: 32.6), control2: CGPoint(x: 52.3, y: 39.8))
        p.addCurve(to: CGPoint(x: 44.1, y: 29.5), control1: CGPoint(x: 47, y: 44.5), control2: CGPoint(x: 44.8, y: 39.6))
        p.closeSubpath()
        p.move(to: CGPoint(x: 55.5, y: 27.8))
        p.addCurve(to: CGPoint(x: 63.8, y: 27.8), control1: CGPoint(x: 58.5, y: 27.5), control2: CGPoint(x: 60.8, y: 27.5))
        p.addCurve(to: CGPoint(x: 60, y: 48.2), control1: CGPoint(x: 63.6, y: 36.6), control2: CGPoint(x: 63.5, y: 43))
        p.addCurve(to: CGPoint(x: 55.5, y: 27.8), control1: CGPoint(x: 56.5, y: 43), control2: CGPoint(x: 55.8, y: 36.5))
        p.closeSubpath()
        p.move(to: CGPoint(x: 68.2, y: 28.2))
        p.addCurve(to: CGPoint(x: 75.9, y: 29.5), control1: CGPoint(x: 70.9, y: 28.4), control2: CGPoint(x: 73.5, y: 28.9))
        p.addCurve(to: CGPoint(x: 70, y: 42.3), control1: CGPoint(x: 75.2, y: 39.6), control2: CGPoint(x: 73, y: 44.5))
        p.addCurve(to: CGPoint(x: 68.2, y: 28.2), control1: CGPoint(x: 67.7, y: 39.8), control2: CGPoint(x: 67.9, y: 32.6))
        p.closeSubpath()
    }

    static let nose = Path { p in
        p.move(to: CGPoint(x: 57.2, y: 68.8))
        p.addCurve(to: CGPoint(x: 62.8, y: 68.8), control1: CGPoint(x: 58.3, y: 68.1), control2: CGPoint(x: 61.7, y: 68.1))
        p.addCurve(to: CGPoint(x: 60, y: 72.6), control1: CGPoint(x: 64, y: 69.8), control2: CGPoint(x: 61.8, y: 72.3))
        p.addCurve(to: CGPoint(x: 57.2, y: 68.8), control1: CGPoint(x: 58.2, y: 72.3), control2: CGPoint(x: 56, y: 69.8))
        p.closeSubpath()
    }

    static let mouth = Path { p in
        p.move(to: CGPoint(x: 60, y: 71.5))
        p.addLine(to: CGPoint(x: 60, y: 73.2))
        p.move(to: CGPoint(x: 60, y: 73.2))
        p.addCurve(to: CGPoint(x: 51.2, y: 74.5), control1: CGPoint(x: 60, y: 78.3), control2: CGPoint(x: 54, y: 79.1))
        p.move(to: CGPoint(x: 60, y: 73.2))
        p.addCurve(to: CGPoint(x: 68.8, y: 74.5), control1: CGPoint(x: 60, y: 78.3), control2: CGPoint(x: 66, y: 79.1))
    }

    static let whiskers = Path { p in
        p.move(to: CGPoint(x: 20.1, y: 69.2))
        p.addLine(to: CGPoint(x: 26.9, y: 71))
        p.move(to: CGPoint(x: 20.5, y: 74.7))
        p.addLine(to: CGPoint(x: 26.7, y: 74.6))
        p.move(to: CGPoint(x: 99.9, y: 69.2))
        p.addLine(to: CGPoint(x: 93.1, y: 71))
        p.move(to: CGPoint(x: 99.5, y: 74.7))
        p.addLine(to: CGPoint(x: 93.3, y: 74.6))
    }

    static let leftEyeBounds = CGRect(x: 37, y: 59.5, width: 11, height: 10.5)
    static let rightEyeBounds = CGRect(x: 72, y: 59.5, width: 10.5, height: 10.5)
    static let leftBlush = Path(ellipseIn: CGRect(x: 30.8, y: 70.7, width: 9.5, height: 9.1))
    static let rightBlush = Path(ellipseIn: CGRect(x: 79.7, y: 70.7, width: 9.5, height: 9.1))

    static let furHex = "F4F2F3"
    static let ink = Color(hex: "171717")
    static let pink = Color(hex: "FFAFB5")
    static let stripeColor = Color(hex: "CECCCC")
    static let whiskerInk = Color(hex: "383838")
    static let outlineWidth: CGFloat = 3.5
    static let mouthWidth: CGFloat = 2.4
    static let whiskerWidth: CGFloat = 1.3
}
