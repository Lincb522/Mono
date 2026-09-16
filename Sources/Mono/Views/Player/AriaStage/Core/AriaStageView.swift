//  全新沉浸模式 —— folia-major 舞台世界观的 SwiftUI 复刻：
//  VisualizerShell（封面流体 + 音频光场 + 景深纹理）承载舞台氛围，
//  classic 渲染器负责歌词叙事，字幕层提供翻译 / 下一句。
//  Chrome 遵循 folia 播放页语言：屏幕上没有通栏工具条，
//  只有底部居中的悬浮玻璃胶囊（FloatingPlayerControls：播放时收起为细进度条，
//  暂停或触碰时展开为完整控制），以及右下角的统一面板（UnifiedPanel：
//  封面信息 / 歌架 / 舞台调校三个 tab）。左上角一枚极简圆钮负责退出。

import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - 歌词仓库：LyricViewModel → AriaLine 管线

@MainActor
final class AriaLyricStore: ObservableObject {
    private struct Content {
        var lines: [AriaLine] = []
        var language: AriaLyricLanguage = .chinese
    }

    @Published private var content = Content()

    var lines: [AriaLine] { content.lines }
    var language: AriaLyricLanguage { content.language }

    private var cancellables = Set<AnyCancellable>()
    private var sourceLyrics: [LyricLine] = []

    init() {
        LyricViewModel.shared.$lyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lyrics in
                guard let self else { return }
                sourceLyrics = lyrics
                replaceLines(AriaLyricEngine.buildLines(
                    from: lyrics,
                    forceUppercaseEnglish: UserDefaults.standard.bool(
                        forKey: "lyricsForceUppercaseEnglish"
                    )
                ))
                AriaFoliaTokenCache.clear()
            }
            .store(in: &cancellables)
    }

    func rebuild(forceUppercaseEnglish: Bool) {
        replaceLines(AriaLyricEngine.buildLines(
            from: sourceLyrics,
            forceUppercaseEnglish: forceUppercaseEnglish
        ))
        AriaFoliaTokenCache.clear()
    }

    private func replaceLines(_ lines: [AriaLine]) {
        content = Content(
            lines: lines,
            language: AriaLyricLanguage.resolve(lines: lines)
        )
    }
}

// MARK: - 沉浸舞台

struct AriaStageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var player = PlayerManager.shared
    /// 刻意不做 @ObservedObject：歌词由 TimelineView 逐帧驱动，
    /// 再订阅时间发布器会让整个舞台 body 每个时间 tick 重算一遍（双重驱动白耗 CPU）
    private let timePublisher = PlaybackTimePublisher.shared
    @ObservedObject private var bgManager = ImmersiveBackgroundManager.shared

    @StateObject private var lyricStore = AriaLyricStore()
    @StateObject private var audioPulse = AriaAudioPulse()
    @StateObject private var stageColors = CoverColorExtractor()
    @ObservedObject private var perf = AriaPerformanceGovernor.shared

    @AppStorage("showTranslation") private var showTranslation = true
    @AppStorage("ariaGeometricBackground") private var ambientMotion = true
    @AppStorage("ariaLyricsFontScale") private var fontScale = 1.0
    @AppStorage("ariaBackgroundOpacity") private var backgroundOpacity = 0.75
    @AppStorage("ariaLyricEffect") private var lyricEffectRaw = AriaLyricEffect.classic.rawValue
    @AppStorage("ariaLyricFont") private var lyricFontRaw = AriaLyricFontChoice.system.rawValue
    @AppStorage("ariaLyricAutoColor") private var lyricAutoColor = true
    @AppStorage("ariaLyricColorHex") private var lyricColorHex = "FFFFFF"
    @AppStorage("ariaLyricLayout") private var lyricLayoutRaw = AriaLyricLayoutChoice.center.rawValue
    @AppStorage("ariaLyricMaterialStyle") private var lyricMaterialStyleRaw = AriaLyricMaterialStyle.solid.rawValue
    @AppStorage("ariaLyricOpacity") private var lyricOpacity = 1.0
    @AppStorage("ariaLyricGlowStrength") private var lyricGlowStrength = 0.0
    @AppStorage("ariaLyricParticleDensity") private var particleDensity = 0.58
    @AppStorage("ariaLyricParticleSize") private var particleSize = 1.15
    @AppStorage("ariaLyricParticleMotion") private var particleMotion = true
    @AppStorage("ariaLyricGlassIntensity") private var glassIntensity = 0.64
    @AppStorage("ariaVideoAdaptiveLyricGlass") private var videoAdaptiveLyricGlass = true
    @AppStorage("ariaCustomLyricFontID") private var customFontID = ""
    @AppStorage("ariaForeignLyricFont") private var foreignLyricFontRaw = MonoPlayerFont.followThemeRawValue
    @AppStorage("ariaForeignCustomLyricFontID") private var foreignCustomFontID = ""
    @AppStorage("lyricsForceUppercaseEnglish") private var forceUppercaseEnglish = false
    @AppStorage("ariaLyricDepthIntensity") private var lyricDepthIntensity = 0.68
    @AppStorage("ariaLyricEmboss") private var lyricEmbossEnabled = true
    @AppStorage("ariaCanopyCaptionTranslation") private var canopyCaptionTranslation = false
    @AppStorage("ariaGestureGuideShown.v1") private var hasShownGestureGuide = false
    // 沉浸实验室（全部默认关闭）
    @AppStorage("ariaHapticBeatEnabled") private var hapticBeatEnabled = false
    @AppStorage("ariaVocalBreathingWeight") private var vocalBreathingEnabled = false
    @AppStorage("ariaTensionSystemEnabled") private var tensionSystemEnabled = false
    @AppStorage("ariaGPUStageEnabled") private var gpuStageEnabled = false
    /// 节拍触觉 / 副歌张力：引用类型状态，逐帧推进不触发视图失效
    @State private var hapticBeat = AriaHapticBeat()
    @State private var tensionEngine = AriaTensionEngine()

    @State private var showPanel = false
    @State private var panelTab: AriaPanelTab = .cover
    /// 歌架搜索聚焦中：面板改锚右上角避开键盘
    @State private var panelSearchActive = false
    /// 横屏键盘实际高度：搜索态面板按「键盘上方剩余空间」精确定高
    @State private var stageKeyboardHeight: CGFloat = 0
    @State private var showLandscapeSettings = false
    @State private var showVideoSheet = false
    /// folia 首页歌架墙：全屏惯性封面长廊
    @State private var showShelfWall = false
    /// 胶囊展开态：暂停时或触碰后展开，播放中静置自动收起为细进度条
    @State private var capsuleExpanded = true
    @State private var chromeHidden = false
    /// 入场揭幕：背景先亮、歌词随后聚焦
    @State private var stageRevealed = false
    @State private var isDraggingSlider = false
    @State private var dragTimeValue: Double = 0
    @State private var lastInteractionAt = Date()
    /// 暂停态刷新计数：暂停时歌词时间轴完全停摆（画面本就冻结，白跑纯耗电），
    /// 拖动进度/远程 seek 改变时间时靠它触发一次重渲染
    @State private var pausedSeekRefresh = 0
    @State private var showGestureGuide = false
    @State private var videoBackgroundIsBright: Bool?

    private let idleTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// folia：播放中悬浮胶囊静置后收起为一条细进度
    private let capsuleCollapseDelay: TimeInterval = 4

    private var palette: AriaPalette {
        AriaPalette.derive(colors: stageColors.palette)
    }

    private var stageSeed: Double {
        Double(abs((player.currentSong?.id ?? 1) % 100_000))
    }

    private var lyricEffect: AriaLyricEffect {
        AriaLyricEffect.resolveStored(lyricEffectRaw)
    }

    private var lyricFont: AriaLyricFontChoice {
        AriaLyricFontChoice(rawValue: lyricFontRaw) ?? .system
    }

    /// 外语歌的独立字体；「复用中文字体」或中文歌一律回落到主歌词字体。
    /// 中文歌里夹带的英文因此始终使用中文字体自带的拉丁字形。
    private func effectiveLyricFont(
        for language: AriaLyricLanguage
    ) -> AriaLyricFontChoice {
        guard language == .foreign,
              foreignLyricFontRaw != MonoPlayerFont.followThemeRawValue,
              let choice = AriaLyricFontChoice(rawValue: foreignLyricFontRaw) else {
            AriaLyricFontChoice.customFontIDOverride = nil
            return lyricFont
        }
        AriaLyricFontChoice.customFontIDOverride =
            choice == .custom ? foreignCustomFontID : nil
        return choice
    }

    private var lyricLayout: AriaLyricLayoutChoice {
        AriaLyricLayoutChoice(rawValue: lyricLayoutRaw) ?? .center
    }

    private var lyricMaterialStyle: AriaLyricMaterialStyle {
        AriaLyricMaterialStyle.resolveStored(lyricMaterialStyleRaw)
    }

    /// 自定义字幕色（自动取色关闭时生效）
    private var customLyricColor: Color? {
        lyricAutoColor ? nil : Color(hex: lyricColorHex)
    }

    /// 歌词层调色板：自定义颜色覆盖 primary/accent，背景层仍用封面取色
    private var lyricPalette: AriaPalette {
        guard let custom = customLyricColor else { return palette }
        var p = palette
        p.primary = custom
        p.accent = custom
        p.accentCycle = []
        return p
    }

    /// 绑定的视频背景（歌曲优先，其次全局；旧上下文仅作兼容回退）
    private var videoURL: URL? {
        bgManager.resolvedVideoURL(for: player.currentSong, context: player.playContext)
    }

    /// 字幕排版位置 → 纵向偏移
    private func lyricLayoutOffset(stageHeight: CGFloat) -> CGFloat {
        switch lyricLayout {
        case .center: return 0
        case .lower: return stageHeight * 0.16
        case .upper: return -stageHeight * 0.16
        }
    }

    /// 暂停且不在拖动进度时，播放时间静止 → 每一帧都和上一帧完全相同，
    /// 直接停掉时间轴（seek 由 pausedSeekRefresh 单独触发重渲染）
    private var lyricTimelinePaused: Bool {
        scenePhase != .active
            || showPanel
            || showShelfWall
            || showLandscapeSettings
            || showVideoSheet
            || showGestureGuide
            || (!player.isPlaying && !isDraggingSlider)
    }

    /// Full-screen overlays own the display while visible. Suspending the hidden
    /// stage avoids running FFT, Metal and lyric timelines underneath them.
    private var stageRuntimeSuspended: Bool {
        scenePhase != .active
            || showShelfWall
            || showLandscapeSettings
            || showVideoSheet
    }

    private var enabledStageEffectCount: Int {
        (gpuStageEnabled ? 1 : 0)
    }

    /// Keep a clean divisor between the screen cadence and the 24 fps visual
    /// layers when several stages are stacked. This reduces uneven frame
    /// pacing as well as GPU wakeups without changing any rendered content.
    private var preferredStageFrameRateCeiling: Int {
        return 60
    }

    private var preferredSpectrumAnalysisFPS: Int {
        switch perf.tier {
        case .high: return enabledStageEffectCount >= 2 ? 24 : 30
        case .medium: return enabledStageEffectCount >= 2 ? 20 : 24
        case .low: return enabledStageEffectCount >= 2 ? 16 : 20
        }
    }

    /// 歌词包含逐字颜色、位移和光效，必须跟随显示刷新节奏推进；
    /// 性能降档由统一渲染引擎处理，常态不再用 30fps 人为制造顿挫。
    private func lyricFPS(material: AriaLyricMaterialStyle) -> Int {
        AriaLyricRenderEngine.framesPerSecond(
            effect: lyricEffect,
            material: material,
            tier: perf.tier,
            isPlaying: player.isPlaying,
            enabledStageEffectCount: enabledStageEffectCount
        )
    }

    var body: some View {
        // 帧闭包外提：这些值与帧无关，避免 60fps 逐帧重算（调色板派生含多次 UIColor 转换）
        let palette = self.palette
        let lyricEffect = self.lyricEffect
        let lyricLines = lyricStore.lines
        let lyricLanguage = lyricStore.language
        let videoURL = self.videoURL
        let videoBackgroundActive = videoURL != nil
        let usesAdaptiveVideoGlass = videoAdaptiveLyricGlass && videoBackgroundActive
        let glassUsesDarkInk = usesAdaptiveVideoGlass && videoBackgroundIsBright == true
        let lyricPalette: AriaPalette = {
            var resolved = self.lyricPalette
            guard usesAdaptiveVideoGlass else { return resolved }
            let glassInk = glassUsesDarkInk ? Color.black : Color.white
            resolved.primary = glassInk.opacity(0.9)
            resolved.secondary = glassInk.opacity(0.62)
            resolved.accent = glassInk.opacity(0.86)
            resolved.accentCycle = []
            return resolved
        }()
        // 翻译字体先于外语字体覆盖解析：确保 .custom 绑定的是主字体的导入 ID
        let translationFont: Font = {
            AriaLyricFontChoice.customFontIDOverride = nil
            return self.lyricFont.font(
                size: 20 * CGFloat(fontScale),
                weight: .medium
            )
        }()
        let lyricFont = effectiveLyricFont(for: lyricLanguage)
        let lyricMaterialStyle: AriaLyricMaterialStyle = usesAdaptiveVideoGlass
            ? .glass
            : self.lyricMaterialStyle
        let lyricTypography = AriaLyricTypographyConfiguration(
            style: lyricMaterialStyle,
            opacity: usesAdaptiveVideoGlass ? min(lyricOpacity, 0.82) : lyricOpacity,
            glowStrength: lyricGlowStrength,
            particleDensity: particleDensity,
            particleSize: particleSize,
            particleMotion: particleMotion,
            glassIntensity: usesAdaptiveVideoGlass ? max(glassIntensity, 0.72) : glassIntensity,
            glassUsesDarkInk: glassUsesDarkInk
        )
        let lyricDepthAmount = pow(min(max(lyricDepthIntensity, 0), 1), 0.72)
        let videoGlassAnalysisIdentity = "\(videoURL?.path ?? "none")|\(videoAdaptiveLyricGlass)"

        GeometryReader { geo in
            ZStack {
                if lyricEffect == .poster {
                    // 海报底色独立于歌词换句，前奏、间奏和空歌词也不露出封面背景。
                    AriaPosterLyricLineView.contrastingInk(for: lyricPalette.accent)
                        .ignoresSafeArea()
                } else {
                    // 舞台底座：封面流体 + 音频光场 + 景深纹理
                    AriaStageShell(
                        coverUrl: player.currentSong?.coverUrl?.sized(500),
                        palette: palette,
                        pulse: audioPulse,
                        isPlaying: player.isPlaying,
                        seed: stageSeed,
                        backgroundOpacity: backgroundOpacity,
                        reduceMotion: !ambientMotion,
                        videoURL: videoURL,
                        isStageActive: !stageRuntimeSuspended,
                        depthIntensity: lyricDepthIntensity,
                        gpuEffectsEnabled: gpuStageEnabled
                    )
                }

                // 歌词舞台 + 字幕层：同一条时间轴逐帧驱动
                Group {
                    if lyricLines.isEmpty {
                        emptyLyricsState
                    } else {
                        TimelineView(AppFrameRate.throttledTimeline(
                            maximumFramesPerSecond: lyricFPS(material: lyricMaterialStyle),
                            paused: lyricTimelinePaused
                        )) { _ in
                            // 暂停态 seek 后靠此状态失效重渲染一帧
                            let _ = pausedSeekRefresh
                            let frame = AriaLyricRenderEngine.frame(
                                lines: lyricLines,
                                time: currentPlaybackTime
                            )
                            let time = frame.time
                            let activeIndex = frame.activeIndex
                            let activeLine = frame.activeLine
                            // 副歌张力跟随歌词时间轴。
                            let _ = advanceStageIntelligence(time: time, lines: lyricLines)
                            // 默认未开启 GPU 光学和人声呼吸时，歌词不需要争用
                            // 音频频谱锁；背景拥有自己的低频率快照读取。
                            let needsLyricPulse = lyricEffect != .poster && (vocalBreathingEnabled || gpuStageEnabled)
                            let stagePulse = needsLyricPulse
                                ? audioPulse.snapshot()
                                : AriaAudioPulse.Snapshot()
                            let breathing = vocalBreathingEnabled
                                ? stagePulse.vocal
                                : 0

                            if lyricEffect == .poster {
                                // 全屏海报拥有自己的转场，不进入玻璃、景深和 GPU 光学合成。
                                AriaFoliaLyricStage(
                                    lines: lyricLines,
                                    activeIndex: activeIndex,
                                    palette: lyricPalette,
                                    effect: .poster,
                                    songIdentity: player.currentSong?.identityKey ?? "",
                                    language: lyricLanguage,
                                    fontChoice: lyricFont,
                                    fontScale: fontScale,
                                    time: time,
                                    stageSize: geo.size
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                            } else {
                                ZStack {
                                    Group {
                                        if lyricEffect == .classic {
                                            if let activeLine {
                                                if lyricLanguage == .foreign {
                                                    AriaForeignClassicLyricStage(
                                                        line: activeLine,
                                                        palette: lyricPalette.lineVariant(activeLine.id),
                                                        fontChoice: lyricFont,
                                                        fontScale: fontScale,
                                                        time: time,
                                                        stageSize: geo.size,
                                                        breathing: breathing
                                                    )
                                                } else {
                                                    AriaClassicLyricStage(
                                                        line: activeLine,
                                                        palette: lyricPalette.lineVariant(activeLine.id),
                                                        fontChoice: lyricFont,
                                                        fontScale: fontScale,
                                                        time: time,
                                                        stageSize: geo.size,
                                                        breathing: breathing
                                                    )
                                                }
                                            }
                                        } else {
                                            AriaFoliaLyricStage(
                                                lines: lyricLines,
                                                activeIndex: activeIndex,
                                                palette: lyricPalette,
                                                effect: lyricEffect,
                                                songIdentity: player.currentSong?.identityKey ?? "",
                                                language: lyricLanguage,
                                                fontChoice: lyricFont,
                                                fontScale: fontScale,
                                                time: time,
                                                stageSize: geo.size
                                            )
                                        }
                                    }
                                    .id(
                                        "\(lyricEffect.rawValue)|\(lyricFont.cacheIdentity)|\(customFontID)|\(foreignLyricFontRaw)|\(foreignCustomFontID)|\(lyricLanguage)|\(lyricTypography)"
                                    )
                                    .ariaLyricRenderSurface(
                                        effect: lyricEffect,
                                        material: lyricMaterialStyle
                                    )
                                    .frame(
                                        width: geo.size.width,
                                        height: lyricEffect.usesFullStage
                                            ? geo.size.height
                                            : geo.size.height * 0.7
                                    )
                                    // 材质在歌词自身视口内完成合成，避免粒子、玻璃和
                                    // 棱镜为整块全屏透明区域反复分配离屏纹理。
                                    .ariaLyricTypography(
                                        configuration: lyricTypography,
                                        palette: lyricPalette,
                                        time: time
                                    )
                                    .offset(
                                        y: lyricEffect.usesFullStage
                                            ? 0
                                            : lyricLayoutOffset(stageHeight: geo.size.height)
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .ariaLyricSpatialDepth(
                                        palette: lyricPalette,
                                        intensity: lyricDepthIntensity,
                                        time: time,
                                        motionEnabled: ambientMotion && player.isPlaying,
                                        usesFullStage: lyricEffect.usesFullStage,
                                        embossEnabled: lyricEmbossEnabled
                                    )
                                    .ariaLyricStageOptics(
                                        pulse: stagePulse,
                                        fallbackAccent: lyricPalette.accent,
                                        gpuEnabled: gpuStageEnabled,
                                        isActive: player.isPlaying && scenePhase == .active,
                                        reduceMotion: reduceMotion,
                                        time: time
                                    )

                                    // 巨幕开启「小字显示翻译」后，翻译已内嵌到注音位，
                                    // 不再叠加底部字幕胶囊
                                    if showTranslation,
                                       !(lyricEffect == .canopy && canopyCaptionTranslation),
                                       let translation = activeLine?.translation,
                                       !translation.isEmpty,
                                       !chromeHidden {
                                        subtitleOverlay(
                                            translation: translation,
                                            palette: lyricPalette,
                                            font: translationFont,
                                            typographyOpacity: lyricTypography.opacity,
                                            depthAmount: lyricDepthAmount
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(stageTapGesture)
                // 入场揭幕：歌词层从轻微缩小 + 模糊中聚焦
                .opacity(lyricEffect == .poster || stageRevealed ? 1 : 0)
                .scaleEffect(lyricEffect == .poster || stageRevealed ? 1 : 0.94)
                .blur(radius: lyricEffect == .poster || stageRevealed ? 0 : 8)

                // 左上角退出（folia 封面悬浮小圆钮语言：黑玻璃 + 白描边）
                VStack {
                    HStack {
                        exitButton
                        Spacer()
                        HStack(spacing: 10) {
                            videoBackgroundToggleButton
                            settingsButton
                        }
                    }
                    .padding(.top, DeviceLayout.headerTopPadding)
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(chromeHidden ? 0 : 1)
                .allowsHitTesting(!chromeHidden)

                // 底部居中悬浮胶囊（folia FloatingPlayerControls）
                VStack {
                    Spacer()
                    AriaControlCapsule(
                        palette: palette,
                        expanded: capsuleExpanded,
                        isDragging: $isDraggingSlider,
                        dragValue: $dragTimeValue,
                        onExpand: {
                            markInteraction()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                capsuleExpanded = true
                            }
                        },
                        onInteract: { markInteraction() },
                        onToggleShelf: {
                            markInteraction()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                showShelfWall.toggle()
                            }
                        }
                    )
                    .padding(.bottom, 22)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(chromeHidden ? 0 : 1)
                .offset(y: chromeHidden ? 24 : 0)
                .scaleEffect(chromeHidden ? 0.97 : 1)
                .allowsHitTesting(!chromeHidden)
                .animation(.easeOut(duration: 0.26), value: chromeHidden)

                // 右下统一面板（folia UnifiedPanel：从右下角生长出的玻璃卡片）
                // 歌架搜索聚焦时改锚到右上并压缩高度，避开横屏键盘；
                // 同一实例只换对齐，避免重建丢焦点
                if showPanel {
                    // 搜索态：面板锚到右上，高度精确铺满「键盘上方」的剩余空间；
                    // 键盘高度未知（尚未弹出）时按横屏典型键盘 210pt 预估
                    let keyboardInset = stageKeyboardHeight > 0 ? stageKeyboardHeight : 210
                    let searchHeight = max(geo.size.height - keyboardInset - 16, 150)
                    AriaUnifiedPanel(
                        isOpen: $showPanel,
                        tab: $panelTab,
                        searchActive: $panelSearchActive,
                        palette: palette,
                        maxHeight: panelSearchActive
                            ? searchHeight
                            : geo.size.height - 56
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, panelSearchActive ? 0 : 24)
                    .padding(.top, panelSearchActive ? 8 : 0)
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height,
                        alignment: panelSearchActive ? .topTrailing : .bottomTrailing
                    )
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(
                        .scale(scale: 0.9, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                    )
                }

                // 歌架墙（folia 首页 Grid3DSlider：全屏惯性封面长廊）
                if showShelfWall {
                    AriaShelfWall(isOpen: $showShelfWall, palette: palette)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(10)
                }

                if showLandscapeSettings {
                    AriaLandscapeSettingsView(palette: palette) {
                        markInteraction()
                        withAnimation(.smooth(duration: 0.28)) {
                            showLandscapeSettings = false
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(20)
                }

                AriaMultiTouchGestureBridge(
                    isEnabled: !showPanel
                        && !showShelfWall
                        && !showLandscapeSettings
                        && !showVideoSheet
                        && !showGestureGuide,
                    onTwoFingerSwipeDown: openShelfFromGesture,
                    onThreeFingerSwipeDown: openSettingsFromGesture
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

                if showGestureGuide {
                    AriaGestureGuideOverlay(
                        palette: palette,
                        onDismiss: dismissGestureGuide
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.97))
                    )
                    .zIndex(100)
                }

                AIEqualizerArtworkStatusView(
                    accent: palette.accent,
                    isDarkArtwork: stageColors.isDark
                )
                    .padding(.trailing, 24)
                    .padding(.bottom, 22)
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height,
                        alignment: .bottomTrailing
                    )
                    .zIndex(80)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .modifier(
                AriaImmersiveGestureModifier(
                    stageSize: geo.size,
                    isEnabled: !showPanel
                        && !showShelfWall
                        && !showLandscapeSettings
                        && !showVideoSheet
                        && !showGestureGuide
                        && !isDraggingSlider
                        && player.currentSong != nil,
                    protectedTop: max(DeviceLayout.headerTopPadding + 54, 76),
                    protectedBottom: capsuleExpanded ? 106 : 70,
                    accent: palette.accent,
                    onInteraction: markInteraction
                )
            )
        }
        // 舞台整体不参与系统键盘避让：歌词/背景不能被键盘顶起，
        // 歌架搜索（面板 / 歌架墙）各自按键盘实际高度手动让位
        .ignoresSafeArea(.keyboard)
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .fullScreenCover(isPresented: $showVideoSheet) {
            ImmersiveBackgroundLandscapeView(palette: palette)
        }
        .onAppear {
            audioPulse.start()
            if hapticBeatEnabled {
                hapticBeat.attach(to: audioPulse)
            }
            updateStageRuntimeActivity()
            OrientationManager.shared.enterLandscape()
            // ProMotion 压回 60Hz：沉浸模式全屏动画在 120Hz 下渲染开销翻倍，是发热主源之一；
            // 录屏/投屏时系统还要逐帧抓取编码，进一步压到 30Hz。
            AppFrameRate.pushFrameRateCeiling(
                preferredStageFrameRateCeiling,
                reason: "aria stage"
            )
            stageColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                stageRevealed = true
            }
        }
        .onDisappear {
            hapticBeat.detach()
            audioPulse.stop()
            OrientationManager.shared.exitLandscape()
            AppFrameRate.popFrameRateCeiling(reason: "aria stage")
            // 离开舞台清掉外语字体的自定义 ID 覆盖，避免污染设置页预览
            AriaLyricFontChoice.customFontIDOverride = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            // 记录横屏键盘真实高度：搜索面板据此精确让位，不再靠固定比例猜
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                stageKeyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            stageKeyboardHeight = 0
        }
        .onReceive(timePublisher.$currentTime) { _ in
            // 暂停中时间只会因 seek 而变：触发一帧重渲染让歌词跟上新位置。
            // 播放中直接短路，不产生任何状态变化。
            guard !player.isPlaying, !isDraggingSlider else { return }
            pausedSeekRefresh &+= 1
        }
        .onReceive(idleTicker) { _ in
            audioPulse.reattachIfNeeded()
            guard capsuleExpanded,
                  player.isPlaying,
                  !isDraggingSlider,
                  !showPanel,
                  !showShelfWall,
                  !showLandscapeSettings,
                  !showVideoSheet,
                  !showGestureGuide else {
                return
            }
            if Date().timeIntervalSince(lastInteractionAt) >= capsuleCollapseDelay {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    capsuleExpanded = false
                }
            }
        }
        .onChange(of: player.currentSong?.id) { _, _ in
            markInteraction()
            audioPulse.resetForNewTrack()
            tensionEngine.reset()
        }
        .onChange(of: hapticBeatEnabled) { _, enabled in
            if enabled {
                hapticBeat.attach(to: audioPulse)
            } else {
                hapticBeat.detach()
            }
        }
        .onChange(of: tensionSystemEnabled) { _, enabled in
            if !enabled {
                tensionEngine.clearTension(pulse: audioPulse)
            }
        }
        .onChange(of: player.isPlaying) { _, playing in
            // folia：暂停时胶囊常驻展开
            if !playing {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    capsuleExpanded = true
                }
            }
            markInteraction()
        }
        .onChange(of: forceUppercaseEnglish) { _, enabled in
            lyricStore.rebuild(forceUppercaseEnglish: enabled)
        }
        .onChange(of: preferredStageFrameRateCeiling) { _, ceiling in
            guard scenePhase == .active else { return }
            AppFrameRate.pushFrameRateCeiling(
                ceiling,
                reason: "aria stage"
            )
        }
        .onChange(of: scenePhase) { _, _ in
            updateStageRuntimeActivity()
            if scenePhase == .active {
                AppFrameRate.pushFrameRateCeiling(
                    preferredStageFrameRateCeiling,
                    reason: "aria stage"
                )
            }
        }
        .onChange(of: showVideoSheet) { _, _ in
            updateStageRuntimeActivity()
        }
        .onChange(of: showShelfWall) { _, _ in
            updateStageRuntimeActivity()
        }
        .onChange(of: showLandscapeSettings) { _, _ in
            updateStageRuntimeActivity()
        }
        .onChange(of: preferredSpectrumAnalysisFPS, initial: true) { _, fps in
            audioPulse.setPreferredAnalysisFramesPerSecond(fps)
        }
        .onChange(of: isDraggingSlider) { _, _ in markInteraction() }
        .task {
            guard !hasShownGestureGuide else { return }
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  !showPanel,
                  !showShelfWall,
                  !showLandscapeSettings,
                  !showVideoSheet else { return }
            hasShownGestureGuide = true
            markInteraction()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                showGestureGuide = true
            }
        }
        .task(id: player.currentSong?.coverUrl?.absoluteString) {
            stageColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
        }
        .task(id: videoGlassAnalysisIdentity) {
            guard videoAdaptiveLyricGlass, let videoURL else {
                videoBackgroundIsBright = nil
                return
            }
            videoBackgroundIsBright = nil
            let isBright = await ImmersiveVideoBrightnessAnalyzer.shared.isBright(videoURL)
            guard !Task.isCancelled else { return }
            videoBackgroundIsBright = isBright
        }
    }

    private func updateStageRuntimeActivity() {
        if !stageRuntimeSuspended {
            audioPulse.resume()
        } else {
            audioPulse.suspend()
        }
    }

    /// 副歌张力逐帧推进（歌词时间轴驱动）：
    /// 只写入 AriaAudioPulse 的外部通道，不触碰任何 SwiftUI 状态。
    /// 返回值仅为满足 ViewBuilder 里 `let _ =` 的调用形式。
    @discardableResult
    private func advanceStageIntelligence(time: Double, lines: [AriaLine]) -> Bool {
        if tensionSystemEnabled {
            tensionEngine.syncWindows(lines: lines)
            tensionEngine.update(time: time, pulse: audioPulse)
        }
        return true
    }

    private func subtitleOverlay(
        translation: String,
        palette: AriaPalette,
        font: Font,
        typographyOpacity: Double,
        depthAmount: Double
    ) -> some View {
        let lightShadowOpacity = lyricEmbossEnabled ? 0.18 * depthAmount : 0
        let darkShadowOpacity = lyricEmbossEnabled ? 0.4 * depthAmount : 0
        let darkShadowRadius = CGFloat(2 + 3 * depthAmount)
        let darkShadowOffset = CGFloat(2 + 2 * depthAmount)
        let bottomPadding: CGFloat = capsuleExpanded ? 118 : 62

        return VStack {
            Spacer()
            AriaSubtitleOverlay(
                translation: translation,
                palette: palette,
                font: font
            )
            .padding(.bottom, bottomPadding)
            .opacity(typographyOpacity)
            .shadow(
                color: .white.opacity(lightShadowOpacity),
                radius: 1.5,
                y: -1
            )
            .shadow(
                color: .black.opacity(darkShadowOpacity),
                radius: darkShadowRadius,
                y: darkShadowOffset
            )
        }
        .transition(.opacity)
    }

    // MARK: - 空态

    @ViewBuilder
    private var emptyLyricsState: some View {
        if LyricViewModel.shared.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.7)))
        } else {
            Text(String(localized: "lyrics_no_lyrics"))
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondary)
                .opacity(0.5)
        }
    }

    // MARK: - 时间源

    private var currentPlaybackTime: Double {
        if isDraggingSlider { return dragTimeValue }
        return LyricKaraokeTimeline.playbackTime(
            streamPlayerTime: player.streamPlayer.currentTime,
            publishedTime: timePublisher.currentTime,
            isAppleMusic: player.currentSong?.isAppleMusic == true,
            appleMusicPlayerTime: player.appleMusicPlayback.renderingPlaybackTime
        )
    }

    // MARK: - 交互

    private func markInteraction() {
        lastInteractionAt = Date()
    }

    private var stageTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { handleStageDoubleTap() }
            .exclusively(
                before: TapGesture(count: 1)
                    .onEnded { handleStageTap() }
            )
    }

    private func handleStageDoubleTap() {
        guard !showPanel,
              !showShelfWall,
              !showLandscapeSettings,
              !showVideoSheet,
              !showGestureGuide,
              player.currentSong != nil,
              !player.isLoading else { return }

        HapticManager.shared.medium()
        player.togglePlayPause()
        chromeHidden = false
        withAnimation(.easeOut(duration: 0.2)) {
            capsuleExpanded = true
        }
        markInteraction()
    }

    private func handleStageTap() {
        // 面板开着时，点空白先收面板
        if showPanel {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { showPanel = false }
            markInteraction()
            return
        }
        if chromeHidden {
            chromeHidden = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { capsuleExpanded = true }
        } else {
            chromeHidden = true
        }
        markInteraction()
    }

    private func openShelfFromGesture() {
        guard !showPanel,
              !showShelfWall,
              !showLandscapeSettings,
              !showVideoSheet,
              !showGestureGuide else { return }

        HapticManager.shared.medium()
        chromeHidden = false
        markInteraction()
        withAnimation(.easeOut(duration: 0.22)) {
            showShelfWall = true
        }
    }

    private func openSettingsFromGesture() {
        guard !showPanel,
              !showShelfWall,
              !showLandscapeSettings,
              !showVideoSheet,
              !showGestureGuide else { return }

        HapticManager.shared.medium()
        chromeHidden = false
        markInteraction()
        withAnimation(.easeOut(duration: 0.22)) {
            showLandscapeSettings = true
        }
    }

    private func dismissGestureGuide() {
        HapticManager.shared.light()
        markInteraction()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            showGestureGuide = false
        }
    }

    // MARK: - 退出钮

    private var exitButton: some View {
        Button {
            dismiss()
        } label: {
            MonoIcon(icon: .back, size: 18, color: .white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.black.opacity(0.25)))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(MonoBouncingButtonStyle())
    }

    private var settingsButton: some View {
        Button {
            markInteraction()
            withAnimation(.smooth(duration: 0.28)) {
                showLandscapeSettings = true
            }
        } label: {
            MonoIcon(icon: .settings, size: 18, color: .white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.black.opacity(0.25)))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(MonoBouncingButtonStyle())
    }

    /// 视频背景开关：开着 → 一键暂停（绑定保留）；有设定但关着 → 一键恢复；
    /// 完全没设定 → 跳到视频背景设置界面选择视频。
    private var videoBackgroundToggleButton: some View {
        let isActive = videoURL != nil

        return Button(action: toggleVideoBackground) {
            ZStack {
                MonoIcon(
                    icon: .mv,
                    size: 17,
                    color: .white.opacity(isActive ? 0.9 : 0.5)
                )
                if isActive {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 1.6, height: 23)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.black.opacity(0.25)))
            )
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(MonoBouncingButtonStyle())
        .accessibilityLabel(
            isActive
                ? String(localized: "关闭视频背景")
                : String(localized: "开启视频背景")
        )
    }

    private func toggleVideoBackground() {
        markInteraction()

        if videoURL != nil {
            bgManager.videoBackgroundEnabled = false
            HapticManager.shared.light()
            return
        }

        let hasBinding = bgManager.boundVideo(
            for: player.currentSong,
            context: player.playContext
        ) != nil

        if hasBinding {
            bgManager.videoBackgroundEnabled = true
            HapticManager.shared.light()
        } else {
            showVideoSheet = true
        }
    }
}

private struct AriaGestureGuideOverlay: View {
    let palette: AriaPalette
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text(String(localized: "immersive_gesture_guide_title"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 17)

                HStack(spacing: 0) {
                    gestureItem(
                        semantic: .gestureSwipeHorizontal,
                        fallback: .layers,
                        text: String(localized: "immersive_gesture_switch_track")
                    )
                    guideDivider
                    gestureItem(
                        semantic: .volumeMedium,
                        fallback: .soundQuality,
                        text: String(localized: "immersive_gesture_volume")
                    )
                    guideDivider
                    gestureItem(
                        semantic: .gestureTap,
                        fallback: .haptic,
                        text: String(localized: "immersive_gesture_pause")
                    )
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.vertical, 13)

                HStack(spacing: 0) {
                    multiFingerItem(
                        count: 2,
                        text: String(localized: "immersive_gesture_open_shelf")
                    )
                    guideDivider
                    multiFingerItem(
                        count: 3,
                        text: String(localized: "immersive_gesture_open_settings")
                    )
                }

                Button(action: onDismiss) {
                    Text(String(localized: "common_ok"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 112, height: 38)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.accent.opacity(0.9))
                        )
                }
                .buttonStyle(MonoBouncingButtonStyle())
                .padding(.top, 18)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 520)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.34))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 0.8)
            }
            .padding(.horizontal, 28)
        }
    }

    private func gestureItem(
        semantic: MonoGlyphSemantic,
        fallback: MonoIcon.IconType,
        text: String
    ) -> some View {
        VStack(spacing: 8) {
            MonoSemanticIcon(
                semantic: semantic,
                fallback: fallback,
                size: 20,
                color: palette.accent
            )
                .frame(height: 23)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    private func multiFingerItem(count: Int, text: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.18))
                    .frame(width: 30, height: 30)
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .offset(y: 20)
            }
            .frame(width: 34, height: 42)

            Text(text)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    private var guideDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 42)
    }
}

private struct AriaMultiTouchGestureBridge: UIViewRepresentable {
    let isEnabled: Bool
    let onTwoFingerSwipeDown: () -> Void
    let onThreeFingerSwipeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            onTwoFingerSwipeDown: onTwoFingerSwipeDown,
            onThreeFingerSwipeDown: onThreeFingerSwipeDown
        )
    }

    func makeUIView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowAttachmentView, context: Context) {
        context.coordinator.update(
            isEnabled: isEnabled,
            onTwoFingerSwipeDown: onTwoFingerSwipeDown,
            onThreeFingerSwipeDown: onThreeFingerSwipeDown
        )
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowAttachmentView, coordinator: Coordinator) {
        uiView.onWindowChange = nil
        coordinator.detach()
    }

    final class WindowAttachmentView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var attachedWindow: UIWindow?
        private var twoFingerRecognizer: UIPanGestureRecognizer?
        private var threeFingerRecognizer: UIPanGestureRecognizer?
        private var isEnabled: Bool
        private var onTwoFingerSwipeDown: () -> Void
        private var onThreeFingerSwipeDown: () -> Void

        init(
            isEnabled: Bool,
            onTwoFingerSwipeDown: @escaping () -> Void,
            onThreeFingerSwipeDown: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onTwoFingerSwipeDown = onTwoFingerSwipeDown
            self.onThreeFingerSwipeDown = onThreeFingerSwipeDown
        }

        func update(
            isEnabled: Bool,
            onTwoFingerSwipeDown: @escaping () -> Void,
            onThreeFingerSwipeDown: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onTwoFingerSwipeDown = onTwoFingerSwipeDown
            self.onThreeFingerSwipeDown = onThreeFingerSwipeDown
        }

        func attach(to window: UIWindow?) {
            guard attachedWindow !== window else { return }
            detach()
            guard let window else { return }

            let twoFinger = makeRecognizer(
                touches: 2,
                action: #selector(handleTwoFingerSwipe(_:))
            )
            let threeFinger = makeRecognizer(
                touches: 3,
                action: #selector(handleThreeFingerSwipe(_:))
            )
            window.addGestureRecognizer(twoFinger)
            window.addGestureRecognizer(threeFinger)
            attachedWindow = window
            twoFingerRecognizer = twoFinger
            threeFingerRecognizer = threeFinger
        }

        func detach() {
            if let recognizer = twoFingerRecognizer {
                attachedWindow?.removeGestureRecognizer(recognizer)
            }
            if let recognizer = threeFingerRecognizer {
                attachedWindow?.removeGestureRecognizer(recognizer)
            }
            twoFingerRecognizer = nil
            threeFingerRecognizer = nil
            attachedWindow = nil
        }

        private func makeRecognizer(touches: Int, action: Selector) -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer(target: self, action: action)
            recognizer.minimumNumberOfTouches = touches
            recognizer.maximumNumberOfTouches = touches
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }

        @objc private func handleTwoFingerSwipe(_ recognizer: UIPanGestureRecognizer) {
            guard completesDownwardSwipe(recognizer) else { return }
            onTwoFingerSwipeDown()
        }

        @objc private func handleThreeFingerSwipe(_ recognizer: UIPanGestureRecognizer) {
            guard completesDownwardSwipe(recognizer) else { return }
            onThreeFingerSwipeDown()
        }

        private func completesDownwardSwipe(_ recognizer: UIPanGestureRecognizer) -> Bool {
            guard isEnabled, recognizer.state == .ended, let view = recognizer.view else {
                return false
            }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            return translation.y > 64
                && translation.y > abs(translation.x) * 1.15
                && velocity.y > 0
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.y > 0 && velocity.y > abs(velocity.x) * 1.08
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct AriaImmersiveGestureModifier: ViewModifier {
    let stageSize: CGSize
    let isEnabled: Bool
    let protectedTop: CGFloat
    let protectedBottom: CGFloat
    let accent: Color
    let onInteraction: () -> Void

    @ObservedObject private var player = PlayerManager.shared
    @State private var gestureAxis: AriaStageGestureAxis?
    @State private var gestureBlocked = false
    @State private var trackSwipeProgress: CGFloat = 0
    @State private var trackSwipeDirection: AriaTrackSwipeDirection?
    @State private var volumeAtGestureStart: Float = 0
    @State private var requestedSystemVolume: Float?
    @State private var volumeHUDVisible = false
    @State private var trackHUDVisible = false
    @State private var hudGeneration = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    AriaSystemVolumeBridge(volume: $requestedSystemVolume)
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)

                    AriaImmersiveGestureHUD(
                        volume: requestedSystemVolume ?? 0,
                        showsVolume: volumeHUDVisible,
                        trackDirection: trackSwipeDirection,
                        trackProgress: trackSwipeProgress,
                        showsTrack: trackHUDVisible,
                        accent: accent
                    )
                    .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(stageGesture)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { resetHUDImmediately() }
            }
            .onDisappear { hudGeneration &+= 1 }
    }

    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged(updateGesture)
            .onEnded(finishGesture)
    }

    private func updateGesture(_ value: DragGesture.Value) {
        guard isEnabled, !gestureBlocked else { return }

        if gestureAxis == nil {
            guard canBeginGesture(value) else {
                gestureBlocked = true
                return
            }

            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard horizontal > 8 || vertical > 8 else { return }

            if horizontal > vertical * 1.18 {
                gestureAxis = .track
                trackHUDVisible = true
                volumeHUDVisible = false
            } else if vertical > horizontal * 1.18,
                      value.startLocation.x >= stageSize.width * 0.56 {
                gestureAxis = .volume
                volumeAtGestureStart = AVAudioSession.sharedInstance().outputVolume
                requestedSystemVolume = volumeAtGestureStart
                volumeHUDVisible = true
                trackHUDVisible = false
                HapticManager.shared.light()
            } else {
                return
            }
        }

        switch gestureAxis {
        case .track:
            let normalized = value.translation.width / max(stageSize.width * 0.28, 1)
            trackSwipeProgress = max(-1, min(1, normalized))
            trackSwipeDirection = AriaTrackSwipeDirection(translation: value.translation.width)
            trackHUDVisible = true
        case .volume:
            let usableHeight = max(stageSize.height * 0.64, 180)
            let delta = Float(-value.translation.height / usableHeight)
            requestedSystemVolume = max(0, min(1, volumeAtGestureStart + delta))
            volumeHUDVisible = true
        case nil:
            break
        }
    }

    private func finishGesture(_ value: DragGesture.Value) {
        defer {
            gestureAxis = nil
            gestureBlocked = false
        }

        guard isEnabled else {
            resetHUDImmediately()
            return
        }

        switch gestureAxis {
        case .track:
            let raw = value.translation.width
            let predicted = value.predictedEndTranslation.width
            let shouldCommit = abs(raw) > max(58, stageSize.width * 0.075)
                || abs(predicted) > max(92, stageSize.width * 0.12)

            guard shouldCommit, player.currentSong != nil else {
                withAnimation(.easeOut(duration: 0.18)) {
                    trackSwipeProgress = 0
                    trackHUDVisible = false
                }
                trackSwipeDirection = nil
                return
            }

            let direction = AriaTrackSwipeDirection(
                translation: abs(predicted) > abs(raw) ? predicted : raw
            )
            trackSwipeDirection = direction
            HapticManager.shared.medium()
            onInteraction()

            withAnimation(.easeOut(duration: 0.14)) {
                trackSwipeProgress = direction == .next ? 1 : -1
            }
            switch direction {
            case .next:
                player.next()
            case .previous:
                player.previous()
            }
            dismissTrackHUD()

        case .volume:
            onInteraction()
            dismissVolumeHUD()

        case nil:
            break
        }
    }

    private func canBeginGesture(_ value: DragGesture.Value) -> Bool {
        value.startLocation.y > protectedTop
            && value.startLocation.y < stageSize.height - protectedBottom
    }

    private func dismissTrackHUD() {
        hudGeneration &+= 1
        let generation = hudGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard hudGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                trackSwipeProgress = 0
                trackHUDVisible = false
            }
            trackSwipeDirection = nil
        }
    }

    private func dismissVolumeHUD() {
        hudGeneration &+= 1
        let generation = hudGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 720_000_000)
            guard hudGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                volumeHUDVisible = false
            }
        }
    }

    private func resetHUDImmediately() {
        hudGeneration &+= 1
        trackSwipeProgress = 0
        trackSwipeDirection = nil
        trackHUDVisible = false
        volumeHUDVisible = false
    }
}

private enum AriaStageGestureAxis {
    case track
    case volume
}

private enum AriaTrackSwipeDirection {
    case next
    case previous

    init(translation: CGFloat) {
        // 与应用内 MiniPlayer 保持一致：右滑下一首，左滑上一首。
        self = translation >= 0 ? .next : .previous
    }
}

private struct AriaSystemVolumeBridge: UIViewRepresentable {
    @Binding var volume: Float?

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        guard let volume,
              let slider = view.subviews.compactMap({ $0 as? UISlider }).first else {
            return
        }
        let clamped = max(0, min(1, volume))
        guard abs(slider.value - clamped) > 0.002 else { return }
        slider.setValue(clamped, animated: false)
        slider.sendActions(for: .valueChanged)
    }
}

private struct AriaImmersiveGestureHUD: View {
    let volume: Float
    let showsVolume: Bool
    let trackDirection: AriaTrackSwipeDirection?
    let trackProgress: CGFloat
    let showsTrack: Bool
    let accent: Color

    var body: some View {
        ZStack {
            volumeHUD
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 34)

            trackHUD
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var volumeHUD: some View {
        VStack(spacing: 10) {
            MonoSemanticIcon(
                semantic: volumeSemantic,
                fallback: .soundQuality,
                size: 17,
                color: .white
            )

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .frame(height: max(5, geometry.size.height * CGFloat(volume)))
                }
            }
            .frame(width: 7, height: 86)

            Text("\(Int((volume * 100).rounded()))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 30)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(hudGlass(shape: Capsule()))
        .opacity(showsVolume ? 1 : 0)
        .scaleEffect(showsVolume ? 1 : 0.94)
        .animation(.easeOut(duration: 0.18), value: showsVolume)
        .animation(.easeOut(duration: 0.1), value: volume)
    }

    private var trackHUD: some View {
        let direction = trackDirection ?? .next
        let progress = min(abs(trackProgress), 1)

        return ZStack {
            Circle()
                .fill(accent.opacity(0.16 + 0.12 * progress))
                .frame(width: 54, height: 54)

            MonoIcon(
                icon: direction == .next ? .next : .previous,
                size: 21,
                color: .white
            )
        }
        .frame(width: 66, height: 66)
        .background(hudGlass(shape: Circle()))
        .offset(x: trackProgress * 26)
        .scaleEffect(0.94 + 0.06 * progress)
        .opacity(showsTrack ? 0.72 + 0.28 * progress : 0)
        .animation(.easeOut(duration: 0.14), value: showsTrack)
    }

    private var volumeSemantic: MonoGlyphSemantic {
        if volume <= 0.001 { return .volumeMute }
        if volume < 0.34 { return .volumeLow }
        if volume < 0.68 { return .volumeMedium }
        return .volumeHigh
    }

    private func hudGlass<S: InsettableShape>(shape: S) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(0.3)))
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

// MARK: - 悬浮控制胶囊（folia FloatingPlayerControls）
//
//  收起态：60% 宽的细玻璃条，只剩进度与时间；
//  展开态：白色圆形播放键 + 歌名 + 进度 + 上一首/下一首/歌架。

private struct AriaControlCapsule: View {
    let palette: AriaPalette
    let expanded: Bool
    @Binding var isDragging: Bool
    @Binding var dragValue: Double
    let onExpand: () -> Void
    let onInteract: () -> Void
    let onToggleShelf: () -> Void

    @ObservedObject private var player = PlayerManager.shared

    private let maxWidth: CGFloat = 520
    private let playButtonBackground = Color.white

    var body: some View {
        ZStack {
            if expanded {
                expandedView
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                collapsedView
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: expanded ? maxWidth : maxWidth * 0.62)
        .background(capsuleGlass(strong: expanded))
        .contentShape(Capsule())
        .onTapGesture { if !expanded { onExpand() } }
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expanded)
    }

    // folia 玻璃：展开 black/40，收起 black/20，白 5% 描边
    private func capsuleGlass(strong: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(strong ? 0.30 : 0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    // MARK: - 展开态

    private var expandedView: some View {
        HStack(spacing: 12) {
            playButton

            VStack(spacing: 7) {
                Text(player.currentSong?.name ?? String(localized: "not_playing"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                AriaCapsuleProgressBar(
                    isDragging: $isDragging,
                    dragValue: $dragValue,
                    onInteract: onInteract
                )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                smallButton(icon: .previous, size: 17) {
                    onInteract()
                    player.previous()
                }
                smallButton(icon: .next, size: 17) {
                    onInteract()
                    player.next()
                }
                smallButton(icon: .list, size: 16) {
                    onToggleShelf()
                }
            }
        }
    }

    /// folia：白底反色圆形播放键（primary 填充 / 背景色 icon）
    private var playButton: some View {
        Button {
            onInteract()
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(playButtonBackground)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 3)

                if player.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.8)))
                } else {
                    MonoIcon(
                        icon: player.isPlaying ? .pause : .play,
                        size: 20,
                        color: .black.opacity(0.85),
                        artworkContrastBackground: playButtonBackground
                    )
                    .offset(x: player.isPlaying ? 0 : 1)
                }
            }
        }
        .buttonStyle(MonoBouncingButtonStyle())
    }

    private func smallButton(icon: MonoIcon.IconType, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MonoIcon(icon: icon, size: size, color: .white)
                .opacity(0.55)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(MonoBouncingButtonStyle())
    }

    // MARK: - 收起态

    private var collapsedView: some View {
        AriaCapsuleProgressBar(
            isDragging: $isDragging,
            dragValue: $dragValue,
            onInteract: onInteract
        )
    }
}

// MARK: - 进度条（folia ProgressBar：1.5pt 级细条 + 等宽小字时间）

private struct AriaCapsuleProgressBar: View {
    @Binding var isDragging: Bool
    @Binding var dragValue: Double
    let onInteract: () -> Void

    @ObservedObject private var player = PlayerManager.shared
    @ObservedObject private var timePublisher = PlaybackTimePublisher.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(formatTime(isDragging ? dragValue : timePublisher.currentTime))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .trailing)

            GeometryReader { geo in
                let duration = timePublisher.duration
                let progress: Double = duration > 0
                    ? min(max((isDragging ? dragValue : timePublisher.currentTime) / duration, 0), 1)
                    : 0
                let barHeight: CGFloat = isDragging ? 8 : 5
                let fillWidth: CGFloat = geo.size.width * CGFloat(progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: barHeight)

                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: max(fillWidth, barHeight), height: barHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isDragging = true
                            let p = min(max(value.location.x / geo.size.width, 0), 1)
                            dragValue = p * duration
                        }
                        .onEnded { value in
                            onInteract()
                            guard duration > 0 else { isDragging = false; return }
                            let p = min(max(value.location.x / geo.size.width, 0), 1)
                            isDragging = false
                            player.seek(to: p * duration)
                        }
                )
            }
            .frame(height: 24)

            Text(formatTime(timePublisher.duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
