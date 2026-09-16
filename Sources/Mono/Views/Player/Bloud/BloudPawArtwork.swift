import SwiftUI

/// PAW geometry in a 120-point square; shiba paths use Figma component 28:648 at 1/4 scale.
/// Rendering has no image dependency.
enum BloudPawArtwork {
    static func draw(in context: inout GraphicsContext, size: CGSize, pose: PawFacePose,
                     gaze: SIMD2<Double>, openness: SIMD2<Double>, fur: Color, eyeInk: Color,
                     isCat: Bool = false, colors: BloudFeatureColors? = nil, motion: BloudPawMotion.Frame = .init()) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        var dog = context
        dog.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        dog.scaleBy(x: side / 120, y: side / 120)
        // Gaze already follows the continuous spring; move the entire portrait before drawing any layer.
        let headX = min(1, max(-1, gaze.x / 38))
        let headY = min(1, max(-1, -gaze.y / 30))
        let contactWeight = 1 - motion.pinch * 0.55
        let shiftX = headX * (isCat ? 3.8 : 3.4) * contactWeight
            + motion.drag.x * (1 - motion.pinch * 0.65) - motion.side * motion.pinch * 0.35
        let shiftY = headY * 2.8 * contactWeight + motion.drag.y * (1 - motion.pinch * 0.65)
        let roll = pose.tilt * (isCat ? 0.45 : 1) + headX * (isCat ? 5.5 : 4.5) * contactWeight
            + motion.drag.x * 0.5 * (1 - motion.pinch * 0.8) - motion.side * motion.pinch * 0.6
        dog.translateBy(x: 60 + min(8, max(-8, shiftX)), y: 60 + min(6, max(-6, shiftY)))
        dog.rotate(by: .degrees(min(9, max(-9, roll))))
        dog.concatenate(CGAffineTransform(a: 1 - abs(headX) * 0.055 * contactWeight, b: 0,
                                         c: headX * headY * 0.025 * contactWeight,
                                         d: 1 - abs(headY) * 0.035 * contactWeight, tx: 0, ty: 0))
        dog.translateBy(x: -60, y: -60)
        let colors = colors ?? BloudFeatureColors(character: isCat ? .pawCat : .paw)
        let outline = colors[.outline]
        let cream = colors[.muzzle]
        var deformation = motion
        deformation.leftEar += pose.earLeft * (1 - motion.pinch * 0.7)
        deformation.rightEar += pose.earRight * (1 - motion.pinch * 0.7)
        let contour = deformed(isCat ? PawCatArtwork.head : head, by: deformation)
        dog.fill(contour, with: .color(fur))
        var face = dog
        face.clip(to: contour)
        let earColor = colors[.ears]
        face.fill(deformed(isCat ? PawCatArtwork.leftEar : leftInnerEar, by: deformation), with: .color(earColor))
        face.fill(deformed(isCat ? PawCatArtwork.rightEar : rightInnerEar, by: deformation), with: .color(earColor))
        if isCat {
            face.fill(deformed(PawCatArtwork.stripes, by: deformation), with: .color(colors[.stripes]))
        }

        let lookX = CGFloat(min(1, max(-1, gaze.x / 38 + pose.lookX * (1 - motion.pinch))))
        let lookY = CGFloat(min(1, max(-1, -gaze.y / 30 + pose.lookY * (1 - motion.pinch))))
        face.translateBy(x: lookX * 1.5, y: lookY * 1.0)
        if !isCat { face.fill(deformed(muzzle, by: deformation), with: .color(cream)) }
        if isCat {
            let spread = motion.whiskerSpread
            let whiskers = PawCatArtwork.whiskers.applying(CGAffineTransform(
                a: 1 + spread * 0.055, b: 0, c: 0, d: 1 + spread * 0.22,
                tx: -60 * spread * 0.055, ty: -73 * spread * 0.22))
            face.stroke(deformed(whiskers, by: deformation), with: .color(colors[.whiskers]),
                        style: StrokeStyle(lineWidth: PawCatArtwork.whiskerWidth, lineCap: .round))
        }
        let blush = colors[.blush].opacity(isCat ? 1 : min(1, 0.9 + pose.blush * (0.1 / 0.45)))
        face.fill(deformed(isCat ? PawCatArtwork.leftBlush : leftBlush, by: deformation), with: .color(blush))
        face.fill(deformed(isCat ? PawCatArtwork.rightBlush : rightBlush, by: deformation), with: .color(blush))

        for index in 0..<2 {
            let eye = index == 0 ? pose.left : pose.right
            let nearCheek = (index == 0 ? -1.0 : 1.0) == motion.side ? 1.0 : 0.5
            let tilt = eye.tilt + motion.disgust * (index == 0 ? 5 : -5)
            var brow = face
            brow.translateBy(x: index == 0 ? 46.8 : 73.5,
                             y: 49.4 + (index == 0 ? pose.browLeft : pose.browRight) + motion.comfort * 0.35)
            brow.rotate(by: .degrees(eye.tilt * 0.4))
            if !isCat { brow.fill(browDot, with: .color(cream)) }

            var eyeContext = face
            let catEye = index == 0 ? PawCatArtwork.leftEyeBounds : PawCatArtwork.rightEyeBounds
            eyeContext.translateBy(x: (isCat ? catEye.midX : (index == 0 ? 42.8 : 77.5)) + lookX * (isCat ? 3.2 : 3.0),
                                   y: (isCat ? catEye.midY : 61.8) + eye.lift * (isCat ? 0.6 : 1) + lookY * (isCat ? 2.0 : 1.8))
            eyeContext.rotate(by: .degrees(tilt))
            let closed = min(1, max(0, 1 - (1 - eye.closed) * min(1, openness[index])
                * (1 - min(1, motion.eyeClosure[index])) * (1 - motion.disgust * nearCheek * 0.4) * (1 - motion.comfort * 0.5)))
            let width = eye.width * (isCat ? catEye.width / 10.5 : 12 / 10.5)
            let height = eye.height * (isCat ? catEye.height / 11 : 12 / 11) * max(0.015, 1 - closed) * max(1, openness[index])
            let curve = eye.curve * (isCat ? 0.7 : 1) + motion.comfort * 0.65 * (1 - eye.curve)
            let eyePath = roundedEyePath(width: width, height: height, curve: curve)
            eyeContext.fill(eyePath, with: .color(eyeInk))
            if closed > 0.45 {
                eyeContext.stroke(eyePath, with: .color(eyeInk),
                                  style: StrokeStyle(lineWidth: (closed - 0.45) / 0.55 * 1.8,
                                                     lineCap: .round, lineJoin: .round))
            }
            if eye.shine > 0 {
                var light = eyeContext
                light.clip(to: eyePath)
                let opacity = eye.shine * pow(1 - closed, 2)
                light.fill(Path(ellipseIn: CGRect(x: -width * 0.23 - 1.3, y: -height * 0.26 - 1.3, width: 2.6, height: 2.6)),
                           with: .color(.white.opacity(opacity)))
                light.fill(Path(ellipseIn: CGRect(x: width * 0.16 - 0.55, y: height * 0.23 - 0.55, width: 1.1, height: 1.1)),
                           with: .color(.white.opacity(opacity * 0.5)))
            }
        }

        var snout = face
        snout.translateBy(x: lookX * 0.45 + pose.skew * 0.6, y: lookY * 0.3)
        var noseContext = snout
        if isCat { noseContext.translateBy(x: 0, y: -motion.noseLift * 0.8) }
        noseContext.fill(isCat ? PawCatArtwork.nose : nose, with: .color(colors[.nose]))
        let tongueAmount = max(pose.tongue * (1 - motion.pinch), motion.tongue)
        let opening = max(pose.open * (1 - motion.disgust), motion.mouthOpen)
        let smile = max(-0.65, min(1, pose.smile + tongueAmount * 0.15 - motion.disgust * 0.7))
        let mouthBlend = min(1, opening / 0.2)
        if opening > 0 {
            let width = 3 + opening * 4 * (1 - pose.round * 0.65)
            let height = 3 + opening * 4
            let y = (isCat ? 73.2 : 78.6) + pose.round * 1.8
            var openMouth = Path()
            openMouth.move(to: CGPoint(x: 60 - width, y: y))
            openMouth.addCurve(to: CGPoint(x: 60 + width, y: y),
                               control1: CGPoint(x: 60 - width, y: y - 1 - pose.round * height * 0.65),
                               control2: CGPoint(x: 60 + width, y: y - 1 - pose.round * height * 0.65))
            openMouth.addCurve(to: CGPoint(x: 60 - width, y: y),
                               control1: CGPoint(x: 60 + width, y: y + height),
                               control2: CGPoint(x: 60 - width, y: y + height))
            openMouth.closeSubpath()
            snout.fill(openMouth, with: .color(outline.opacity(mouthBlend)))
            var inside = snout
            inside.clip(to: openMouth)
            inside.fill(Path(ellipseIn: CGRect(x: 56.5, y: y + height * 0.5, width: 7, height: 3)),
                        with: .color(colors[.tongue].opacity((1 - pose.round) * mouthBlend)))
        }
        if tongueAmount > 0.001 || motion.lick > 0.001 {
            var tip = snout
            let tipPath = isCat ? PawTongueArtwork.cat : PawTongueArtwork.shiba
            tip.translateBy(x: 60, y: isCat ? 74 : 77.2)
            // Keep the mouth-shaped root fixed while the tip extends below it.
            tip.clip(to: tipPath)
            tip.scaleBy(x: 1, y: max(tongueAmount, motion.lick))
            tip.fill(tipPath, with: .color(colors[.tongue]))
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: 60, y: 74.2))
        mouth.addLine(to: CGPoint(x: 60, y: 76.7))
        mouth.addCurve(to: CGPoint(x: 50.8 - (smile - 0.2), y: 77 - smile * 1.1),
                       control1: CGPoint(x: 58, y: 80.6 + smile * 0.8),
                       control2: CGPoint(x: 51.5, y: 82 + smile * 0.8))
        mouth.move(to: CGPoint(x: 60, y: 76.7))
        mouth.addCurve(to: CGPoint(x: 69.2 + (smile - 0.2), y: 77 - smile * 1.1 + pose.skew * 0.5),
                       control1: CGPoint(x: 62, y: 80.6 + smile * 0.8),
                       control2: CGPoint(x: 68.5, y: 82 + smile * 0.8))
        if isCat {
            let stretch = (smile - PawFacePose().smile) * 0.06
            mouth = PawCatArtwork.mouth.applying(CGAffineTransform(
                a: 1 + stretch, b: 0, c: 0, d: 1 + stretch,
                tx: -60 * stretch, ty: -73.2 * stretch))
        }
        snout.stroke(mouth, with: .color(outline.opacity(1 - mouthBlend)),
                     style: StrokeStyle(lineWidth: isCat ? PawCatArtwork.mouthWidth : 2.5, lineCap: .round, lineJoin: .round))
        dog.stroke(contour, with: .color(outline),
                   style: StrokeStyle(lineWidth: isCat ? PawCatArtwork.outlineWidth : 3.6, lineCap: .round, lineJoin: .round))
    }

    /// An ellipse at rest, bent into a smile/sleep arc while retaining each companion's base eye proportions.
    private static func roundedEyePath(width: Double, height: Double, curve: Double) -> Path {
        let rx = width / 2, ry = height / 2, k = 0.5522847498307936
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x, y: y - curve * 3 * (1 - pow(x / rx, 2)))
        }
        return Path { p in
            p.move(to: point(rx, 0))
            p.addCurve(to: point(0, ry), control1: point(rx, ry * k), control2: point(rx * k, ry))
            p.addCurve(to: point(-rx, 0), control1: point(-rx * k, ry), control2: point(-rx, ry * k))
            p.addCurve(to: point(0, -ry), control1: point(-rx, -ry * k), control2: point(-rx * k, -ry))
            p.addCurve(to: point(rx, 0), control1: point(rx * k, -ry), control2: point(rx, -ry * k))
            p.closeSubpath()
        }
    }

    /// The same local deformation is applied to fur, outline and markings, so they stay attached.
    private static func deformed(_ path: Path, by motion: BloudPawMotion.Frame) -> Path {
        guard motion.pinch > 0.001 || abs(motion.leftEar) > 0.001 || abs(motion.rightEar) > 0.001 else { return path }
        func point(_ p: CGPoint) -> CGPoint {
            let x = Double(p.x), y = Double(p.y)
            let earSide = x < 60 ? -1.0 : 1.0
            let ear = (x < 60 ? motion.leftEar : motion.rightEar) * max(0, min(1, (44 - y) / 27))
            let cheekX = motion.side < 0 ? 21.0 : 99.0
            let weight = exp(-pow((x - cheekX) / 18, 2) - pow((y - 75) / 18, 2)) * motion.pinch
            return CGPoint(x: x + earSide * ear * 3.5 + (motion.side * 2.2 + motion.drag.x * 0.9) * weight,
                           y: y + ear * 7 + ((75 - y) * 0.1 + motion.drag.y * 0.4) * weight)
        }
        var result = Path()
        path.forEach { element in
            switch element {
            case .move(to: let p): result.move(to: point(p))
            case .line(to: let p): result.addLine(to: point(p))
            case .quadCurve(to: let p, control: let c): result.addQuadCurve(to: point(p), control: point(c))
            case .curve(to: let p, control1: let a, control2: let b):
                result.addCurve(to: point(p), control1: point(a), control2: point(b))
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
    }

    private static let head = Path { p in
        p.move(to: CGPoint(x: 21.6, y: 43.4))
        p.addCurve(to: CGPoint(x: 27.7, y: 17.6), control1: CGPoint(x: 19.9, y: 32.9), control2: CGPoint(x: 20.4, y: 18.9))
        p.addCurve(to: CGPoint(x: 46.1, y: 26.2), control1: CGPoint(x: 33.2, y: 15.3), control2: CGPoint(x: 41.5, y: 21.1))
        p.addCurve(to: CGPoint(x: 74.7, y: 26.2), control1: CGPoint(x: 54.5, y: 23.2), control2: CGPoint(x: 65.9, y: 23.2))
        p.addCurve(to: CGPoint(x: 93.1, y: 17.6), control1: CGPoint(x: 80.1, y: 20.5), control2: CGPoint(x: 88.1, y: 15.3))
        p.addCurve(to: CGPoint(x: 98.5, y: 43.3), control1: CGPoint(x: 100.2, y: 20), control2: CGPoint(x: 100.5, y: 33.4))
        p.addCurve(to: CGPoint(x: 105.4, y: 65.6), control1: CGPoint(x: 103.8, y: 50.7), control2: CGPoint(x: 105.9, y: 57.2))
        p.addCurve(to: CGPoint(x: 96.1, y: 89.5), control1: CGPoint(x: 105.4, y: 74.8), control2: CGPoint(x: 102.5, y: 83.4))
        p.addCurve(to: CGPoint(x: 60.1, y: 101), control1: CGPoint(x: 87.4, y: 97.9), control2: CGPoint(x: 74.2, y: 101.3))
        p.addCurve(to: CGPoint(x: 24.3, y: 89.6), control1: CGPoint(x: 44.1, y: 101.3), control2: CGPoint(x: 31.6, y: 97.8))
        p.addCurve(to: CGPoint(x: 14.3, y: 65.7), control1: CGPoint(x: 17.3, y: 82.8), control2: CGPoint(x: 14.1, y: 74.9))
        p.addCurve(to: CGPoint(x: 21.6, y: 43.4), control1: CGPoint(x: 14.3, y: 57.1), control2: CGPoint(x: 16.7, y: 50.1))
        p.closeSubpath()
    }

    private static let leftInnerEar = Path { p in
        p.move(to: CGPoint(x: 27.1, y: 36.3))
        p.addCurve(to: CGPoint(x: 30.2, y: 23.5), control1: CGPoint(x: 26.9, y: 31.7), control2: CGPoint(x: 27.3, y: 23.8))
        p.addCurve(to: CGPoint(x: 40.2, y: 29.3), control1: CGPoint(x: 32.4, y: 22.8), control2: CGPoint(x: 37.6, y: 26.4))
        p.addCurve(to: CGPoint(x: 29.3, y: 38.1), control1: CGPoint(x: 36.4, y: 31.4), control2: CGPoint(x: 32.4, y: 35.1))
        p.addCurve(to: CGPoint(x: 27.1, y: 36.3), control1: CGPoint(x: 28.2, y: 39.1), control2: CGPoint(x: 27.2, y: 38.4))
        p.closeSubpath()
    }

    private static let rightInnerEar = Path { p in
        p.move(to: CGPoint(x: 93, y: 36.2))
        p.addCurve(to: CGPoint(x: 90.1, y: 23.5), control1: CGPoint(x: 93.3, y: 31.8), control2: CGPoint(x: 93, y: 23.9))
        p.addCurve(to: CGPoint(x: 80, y: 29.3), control1: CGPoint(x: 87.7, y: 22.8), control2: CGPoint(x: 82.7, y: 26.4))
        p.addCurve(to: CGPoint(x: 90.8, y: 38.1), control1: CGPoint(x: 83.7, y: 31.5), control2: CGPoint(x: 87.6, y: 35.1))
        p.addCurve(to: CGPoint(x: 93, y: 36.2), control1: CGPoint(x: 92, y: 39.1), control2: CGPoint(x: 92.9, y: 38.3))
        p.closeSubpath()
    }

    private static let muzzle = Path { p in
        p.move(to: CGPoint(x: 16.3, y: 79.3))
        p.addCurve(to: CGPoint(x: 30.5, y: 65.6), control1: CGPoint(x: 19.5, y: 71.7), control2: CGPoint(x: 24.1, y: 66.3))
        p.addCurve(to: CGPoint(x: 43, y: 67.2), control1: CGPoint(x: 36.4, y: 64.7), control2: CGPoint(x: 39.9, y: 67.2))
        p.addCurve(to: CGPoint(x: 53.4, y: 62.1), control1: CGPoint(x: 47, y: 67.2), control2: CGPoint(x: 48.5, y: 62.1))
        p.addCurve(to: CGPoint(x: 66.6, y: 62.1), control1: CGPoint(x: 57.6, y: 61.6), control2: CGPoint(x: 62.4, y: 61.6))
        p.addCurve(to: CGPoint(x: 77, y: 67.2), control1: CGPoint(x: 71.5, y: 62.1), control2: CGPoint(x: 73, y: 67.2))
        p.addCurve(to: CGPoint(x: 89.5, y: 65.6), control1: CGPoint(x: 80.1, y: 67.2), control2: CGPoint(x: 83.6, y: 64.7))
        p.addCurve(to: CGPoint(x: 104, y: 79.3), control1: CGPoint(x: 95.9, y: 66.3), control2: CGPoint(x: 100.5, y: 71.7))
        p.addCurve(to: CGPoint(x: 96.1, y: 89.5), control1: CGPoint(x: 102.2, y: 83.5), control2: CGPoint(x: 99.6, y: 86.6))
        p.addCurve(to: CGPoint(x: 60.1, y: 101), control1: CGPoint(x: 87.4, y: 97.9), control2: CGPoint(x: 74.2, y: 101.3))
        p.addCurve(to: CGPoint(x: 24.3, y: 89.6), control1: CGPoint(x: 44.1, y: 101.3), control2: CGPoint(x: 31.6, y: 97.8))
        p.addCurve(to: CGPoint(x: 16.3, y: 79.3), control1: CGPoint(x: 20.9, y: 86.4), control2: CGPoint(x: 18.2, y: 83))
        p.closeSubpath()
    }

    private static let nose = Path { p in
        p.move(to: CGPoint(x: 55.4, y: 68.7))
        p.addCurve(to: CGPoint(x: 64.8, y: 68.7), control1: CGPoint(x: 57.9, y: 68.1), control2: CGPoint(x: 62.4, y: 68.1))
        p.addCurve(to: CGPoint(x: 63.7, y: 73), control1: CGPoint(x: 67.1, y: 69.3), control2: CGPoint(x: 66, y: 71.9))
        p.addCurve(to: CGPoint(x: 56.4, y: 73), control1: CGPoint(x: 61.5, y: 75.4), control2: CGPoint(x: 58.7, y: 75.4))
        p.addCurve(to: CGPoint(x: 55.4, y: 68.7), control1: CGPoint(x: 54.1, y: 71.6), control2: CGPoint(x: 53.1, y: 69.2))
        p.closeSubpath()
    }

    private static let browDot = Path(ellipseIn: CGRect(x: -3.5, y: -3.6, width: 7, height: 7.2))
    private static let leftBlush = Path(ellipseIn: CGRect(x: 28.8, y: 69.4, width: 10.5, height: 10.8))
    private static let rightBlush = Path(ellipseIn: CGRect(x: 81.6, y: 69.4, width: 10.5, height: 10.8))
}
