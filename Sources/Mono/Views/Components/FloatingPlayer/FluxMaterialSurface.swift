import SwiftUI

@available(iOS 17.0, *)
struct FluxMaterialSurface: View, Animatable {
    let size: CGSize
    let colors: [Color]
    let time: TimeInterval
    nonisolated var progress: Double
    nonisolated var stir: CGFloat
    let touchPosition: CGFloat
    let motionSeed: CGFloat
    let isDarkMode: Bool

    // Shader uniforms need explicit interpolation for seek settling and release.
    nonisolated var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(progress, stir) }
        set {
            progress = newValue.first
            stir = newValue.second
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .colorEffect(
                ShaderLibrary.fluxTabMaterial(
                    .float2(size),
                    .float(Float(time)),
                    .float(Float(progress)),
                    .float(Float(stir)),
                    .float(Float(touchPosition)),
                    .float(Float(motionSeed)),
                    .float(isDarkMode ? 1 : 0),
                    .color(colors[0]),
                    .color(colors[1]),
                    .color(colors[2])
                )
            )
    }
}
