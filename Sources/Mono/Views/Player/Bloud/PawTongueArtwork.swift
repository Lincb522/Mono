import SwiftUI

/// Mouth-shaped roots from Figma components 28:692 and 28:707.
enum PawTongueArtwork {
    static let color = Color(hex: "F5A6B0")
    static let shiba = Path { p in
        p.move(to: CGPoint(x: -3.3, y: 2.5))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -2.4, y: 2), control2: CGPoint(x: -1, y: 0.8))
        p.addCurve(to: CGPoint(x: 3.3, y: 2.5), control1: CGPoint(x: 1, y: 0.8), control2: CGPoint(x: 2.4, y: 2))
        p.addLine(to: CGPoint(x: 3.3, y: 3.8))
        p.addCurve(to: CGPoint(x: -3.3, y: 3.8), control1: CGPoint(x: 3.3, y: 8), control2: CGPoint(x: -3.3, y: 8))
        p.closeSubpath()
    }
    static let cat = Path { p in
        p.move(to: CGPoint(x: -3.4, y: 2.3))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -2.4, y: 1.8), control2: CGPoint(x: -1, y: 0.6))
        p.addCurve(to: CGPoint(x: 3.4, y: 2.3), control1: CGPoint(x: 1, y: 0.6), control2: CGPoint(x: 2.4, y: 1.8))
        p.addLine(to: CGPoint(x: 3.4, y: 4))
        p.addCurve(to: CGPoint(x: -3.4, y: 4), control1: CGPoint(x: 3.4, y: 8.4), control2: CGPoint(x: -3.4, y: 8.4))
        p.closeSubpath()
    }
}
