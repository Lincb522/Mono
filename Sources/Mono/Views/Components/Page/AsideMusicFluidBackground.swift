import SwiftUI
import UIKit

/// AsideMusic 默认主题的全屏流体背景。
///
/// 封面变化时重新提取调色板，播放时流动；离开页面、暂停、
/// 切到后台或开启“减弱动态效果”时冻结当前画面。
@MainActor
struct AsideMusicFluidBackground: View {
    let artworkURL: String?
    var onBrightnessChanged: ((Bool) -> Void)?

    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    // FLUX 原版使用三种独立颜料。这里固定至少提取五色，再从首、中、尾
    // 选出跨度最大的三色，避免全局取色数量设为 2 时退化成双色渐变。
    @StateObject private var coverColors = CoverColorExtractor(minimumColorCount: 5)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var accumulatedMotionTime: TimeInterval = 0
    @State private var motionAnchorDate = Date()
    @State private var motionIsRunning = false
    @State private var isVisible = false
    @State private var computeWorkloadToken: UUID?
    @State private var paletteTransition = AsideMusicFluidPaletteTransition()

    private var resolvedPalette: AsideMusicFluidPalette? {
        let extracted = coverColors.palette
        guard extracted.count >= 3,
              let first = rgb(extracted[0]),
              let middle = rgb(extracted[extracted.count / 2]),
              let last = rgb(extracted[extracted.count - 1]) else { return nil }
        return AsideMusicFluidPalette(first: first, middle: middle, last: last)
    }

    private var shouldRunMotion: Bool {
        guard #available(iOS 17.0, *) else { return false }
        return isVisible && isPlaying
            && scenePhase == .active
            && !reduceMotion
    }

    private var shouldRenderFrames: Bool {
        isVisible && scenePhase == .active
            && (motionIsRunning || paletteTransition.isAnimating)
    }

    var body: some View {
        GeometryReader { proxy in
            // 渲染分辨率是该材质的固定设计参数，不随设备压力改变，避免
            // MonoCompute 策略更新令整块 Shader 视图重建或视觉清晰度跳变。
            let renderScale = CGFloat(0.58)
            let renderSize = CGSize(
                width: max(proxy.size.width * renderScale, 1),
                height: max(proxy.size.height * renderScale, 1)
            )

            ZStack {
                Color.monoBackground

                // Loading a cover must not unmount the material or expose the base color.
                if paletteTransition.target != nil {
                    TimelineView(
                        AppFrameRate.throttledTimeline(
                            maximumFramesPerSecond: 30,
                            paused: !shouldRenderFrames
                        )
                    ) { context in
                        let palette = paletteTransition.value(at: context.date.timeIntervalSinceReferenceDate)
                        if let palette {
                            let colors = [palette.first, palette.middle, palette.last].map {
                                Color(red: $0.x, green: $0.y, blue: $0.z)
                            }
                            Group {
                                if #available(iOS 17.0, *) {
                                    AsideMusicFluidMetalSurface(
                                        size: renderSize,
                                        colors: colors,
                                        motionTime: motionTime(at: context.date),
                                        isDarkMode: colorScheme == .dark
                                    )
                                    .frame(width: renderSize.width, height: renderSize.height)
                                    .scaleEffect(1 / renderScale, anchor: .topLeading)
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.height,
                                        alignment: .topLeading
                                    )
                                } else {
                                    DynamicCoverPaletteLayer(
                                        colors: colors,
                                        opacity: colorScheme == .dark ? 0.82 : 0.62
                                    )
                                    .blur(radius: 34)
                                    .scaleEffect(1.16)
                                }
                            }
                            .onChange(of: context.date) { _, date in
                                let time = date.timeIntervalSinceReferenceDate
                                guard let end = paletteTransition.completionTime, time >= end else { return }
                                paletteTransition.finishIfNeeded(at: time)
                                synchronizeComputeWorkload()
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            isVisible = true
            coverColors.extract(from: artworkURL)
            synchronizeMotionClock()
        }
        .onChange(of: artworkURL) { _, newURL in
            coverColors.extract(from: newURL)
        }
        .onReceive(FloatingBarPlaybackModel.shared.$isPlaying.removeDuplicates()) { playing in
            guard isPlaying != playing else { return }
            isPlaying = playing
            synchronizeMotionClock()
        }
        .onChange(of: scenePhase) { _, _ in
            synchronizeMotionClock()
        }
        .onChange(of: reduceMotion) { _, _ in
            synchronizeMotionClock()
        }
        .onChange(of: coverColors.isDark) { _, isDark in
            if let resolvedURL = coverColors.resolvedURL, resolvedURL == artworkURL {
                onBrightnessChanged?(isDark)
            }
        }
        .onChange(of: coverColors.resolvedURL) { _, _ in
            acceptResolvedPalette()
        }
        .onChange(of: coverColors.palette) { _, _ in
            acceptResolvedPalette()
        }
        .onDisappear {
            isVisible = false
            synchronizeMotionClock()
        }
    }

    private func acceptResolvedPalette() {
        guard let resolvedURL = coverColors.resolvedURL,
              resolvedURL == artworkURL,
              let resolvedPalette else { return }
        paletteTransition.update(to: resolvedPalette, at: Date().timeIntervalSinceReferenceDate)
        onBrightnessChanged?(coverColors.isDark)
        synchronizeComputeWorkload()
    }

    private func rgb(_ color: Color) -> SIMD3<Double>? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return SIMD3(Double(red), Double(green), Double(blue))
    }

    private func motionTime(at date: Date) -> TimeInterval {
        accumulatedMotionTime + (motionIsRunning ? max(date.timeIntervalSince(motionAnchorDate), 0) : 0)
    }

    private func synchronizeMotionClock() {
        let now = Date()
        if motionIsRunning {
            accumulatedMotionTime += max(now.timeIntervalSince(motionAnchorDate), 0)
        }

        motionAnchorDate = now
        motionIsRunning = shouldRunMotion
        synchronizeComputeWorkload()
    }

    private func synchronizeComputeWorkload() {
        let shouldObserve = shouldRenderFrames && paletteTransition.target != nil
        if shouldObserve, computeWorkloadToken == nil {
            computeWorkloadToken = MonoComputeEngine.shared.beginWorkload(.fluidBackground)
        } else if !shouldObserve, let computeWorkloadToken {
            MonoComputeEngine.shared.endWorkload(computeWorkloadToken)
            self.computeWorkloadToken = nil
        }
    }
}

@available(iOS 17.0, *)
private struct AsideMusicFluidMetalSurface: View {
    let size: CGSize
    let colors: [Color]
    let motionTime: TimeInterval
    let isDarkMode: Bool

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .colorEffect(
                ShaderLibrary.asideMusicFluidBackgroundMaterial(
                    .float2(size),
                    .float(Float(motionTime)),
                    .float(isDarkMode ? 1 : 0),
                    .color(colors[0]),
                    .color(colors[1]),
                    .color(colors[2])
                )
            )
    }
}
