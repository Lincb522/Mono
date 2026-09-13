import SwiftUI

/// 默认收起为云雾迷你播放器，需要导航时在同一个容器内展开 TabBar。
///
/// 视觉算法由 KTBOY/shuke-lab-flux（MIT）中的 WebGL 域扭曲 FBM 思路移植，
/// 使用 SwiftUI Metal 原生渲染。真实播放时间控制覆盖范围，独立视觉时钟控制云雾流动。
@MainActor
struct FluxFloatingBar: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab

    private let player = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @State private var isLoading = FloatingBarPlaybackModel.shared.isLoading
    @ObservedObject private var playbackTime = PlaybackTimePublisher.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var coverColors = CoverColorExtractor(minimumColorCount: 5)
    @AppStorage(AppConfig.StorageKeys.interfaceIconSet) private var iconSetRaw: String = AppInterfaceIconSet.hicon.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingTabs = false
    @State private var showPlaylist = false
    @State private var anchorTime: Double = 0
    @State private var anchorDate = Date()
    @State private var computeWorkloadToken: UUID?
    @State private var barWidth: CGFloat = 0
    @State private var scrubProgress: Double = 0
    @State private var scrubStartProgress: Double = 0
    @State private var scrubTargetProgress: Double = 0
    @State private var scrubFlowIntensity: CGFloat = 0
    @State private var scrubLocation: CGFloat = 0.5
    @State private var lastScrubTranslation: CGFloat = 0
    @State private var lastScrubUpdate = Date()
    @State private var isScrubbing = false
    @State private var isHoldingCommittedSeek = false
    @State private var scrubGeneration = 0
    @State private var isVisible = false

    private var displaysTabs: Bool {
        showingTabs || currentSong == nil
    }

    private var artworkURL: String? {
        currentSong?.coverUrl?.sized(220).absoluteString
    }

    private var hasResolvedArtworkPalette: Bool {
        guard let artworkURL else { return false }
        return coverColors.resolvedURL == artworkURL
    }

    private var hasVisibleFluid: Bool {
        currentSong != nil
            && hasResolvedArtworkPalette
            && playbackTime.duration.isFinite
            && playbackTime.duration > 0
            && presentedProgress > 0.001
    }

    private var palette: [Color] {
        let extracted = coverColors.palette
        guard extracted.count >= 3 else {
            return [
                coverColors.dominantColor,
                coverColors.secondaryColor,
                coverColors.dominantColor.opacity(0.78),
            ]
        }

        return [
            extracted[0],
            extracted[extracted.count / 2],
            extracted[extracted.count - 1],
        ]
    }

    private var liveProgress: Double {
        guard playbackTime.duration.isFinite, playbackTime.duration > 0,
              playbackTime.currentTime.isFinite else { return 0 }
        return min(max(playbackTime.currentTime / playbackTime.duration, 0), 1)
    }

    private var usesScrubProgress: Bool {
        isScrubbing || isHoldingCommittedSeek
    }

    private var presentedProgress: Double {
        usesScrubProgress ? scrubProgress : liveProgress
    }

    private var fluidProgress: Double {
        guard hasVisibleFluid else { return 0 }
        return presentedProgress
    }

    private var presentedAnchorTime: Double {
        usesScrubProgress ? scrubProgress * playbackTime.duration : anchorTime
    }

    private var motionSeed: CGFloat {
        fluxMotionSeed(for: currentSong)
    }

    private var fluidPrimaryColor: Color { coverColors.contentColor }

    private var fluidSecondaryColor: Color { coverColors.secondaryContentColor }

    private var usesAdaptiveOriginalArtwork: Bool {
        _ = iconSetRaw
        return [.pulseBloom, .monoGlyph].contains(AppInterfaceIconSet.selectedFromDefaults)
    }

    /// 仅用于圆形专辑图的装饰环，不参与悬浮栏外圈播放进度。
    private var artworkRingColors: [Color] {
        let colors = hasResolvedArtworkPalette ? palette : [Color.monoAccent, Color.monoAccent.opacity(0.55)]
        guard let first = colors.first else { return [Color.monoAccent, Color.monoAccent] }
        return colors + [first]
    }

    private var artworkRotation: Double {
        guard !reduceMotion else { return 0 }
        return sanitizedTime(playbackTime.currentTime) * 24
    }

    var body: some View {
        let _ = colorRevision

        let _ = settings.globalThemeRevision

        ZStack {
            FluidFloatingBarShell()

            if hasVisibleFluid {
                FluxLivingMaterial(
                    colors: palette,
                    anchorTime: presentedAnchorTime,
                    anchorDate: anchorDate,
                    duration: playbackTime.duration,
                    isPlaying: isVisible && isPlaying && !usesScrubProgress,
                    fillsEntireSurface: false,
                    stir: scrubFlowIntensity,
                    touchPosition: scrubLocation,
                    isInteracting: isScrubbing,
                    isDarkMaterial: coverColors.isDark,
                    motionSeed: motionSeed
                )
                .clipShape(Capsule(style: .continuous))
                .compositingGroup()
                .transition(.opacity)
            }

            Group {
                if displaysTabs {
                    FluxTabContent(
                        currentTab: currentTab,
                        panelPrimaryColor: Color.monoTextPrimary,
                        panelSecondaryColor: Color.monoTextPrimary.opacity(0.78),
                        panelBackgroundColor: Color.monoStructuralBackground,
                        fluidPrimaryColor: fluidPrimaryColor,
                        fluidSecondaryColor: fluidPrimaryColor.opacity(0.82),
                        fluidBackgroundColor: coverColors.isDark ? .black : .white,
                        fluidProgress: fluidProgress
                    ) { tab in
                        selectTab(tab)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
                } else if let song = currentSong {
                    miniPlayerContent(song: song)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 64)
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.82),
                            Color.white.opacity(0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .overlay {
            if currentSong != nil,
               playbackTime.duration.isFinite,
               playbackTime.duration > 0 {
                FluxPerimeterProgress(
                    anchorTime: presentedAnchorTime,
                    anchorDate: anchorDate,
                    duration: playbackTime.duration,
                    isPlaying: isVisible && isPlaying && !usesScrubProgress,
                    isPaused: reduceMotion || scenePhase != .active || usesScrubProgress,
                    darkStyle: colorScheme == .dark
                )
                .padding(-1.4)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.13 : 0.38))
                .frame(height: 1.2)
                .padding(.horizontal, 22)
                .padding(.top, 1)
        }
        .overlay(alignment: .bottom) {
            if !displaysTabs,
               currentSong != nil,
               playbackTime.duration.isFinite,
               playbackTime.duration > 0 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .highPriorityGesture(scrubGesture)
                    .zIndex(4)
            }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 16, x: 0, y: 8)
        .contentShape(Capsule(style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { barWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in barWidth = width }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: displaysTabs)
        .onReceive(player.$currentSong) { currentSong = $0 }
        .onReceive(player.$isPlaying.removeDuplicates()) { isPlaying = $0 }
        .onReceive(player.$isLoading.removeDuplicates()) { isLoading = $0 }
        .onAppear {
            isVisible = true
            synchronizePlaybackAnchor()
            coverColors.extract(from: artworkURL)
            synchronizeComputeWorkload()
        }
        .onChange(of: artworkURL) { _, newURL in
            cancelScrubPreview()
            coverColors.extract(from: newURL)
            synchronizePlaybackAnchor()
        }
        .onChange(of: playbackTime.currentTime) { _, newTime in
            if isHoldingCommittedSeek,
               playbackTime.duration > 0,
               abs((newTime / playbackTime.duration) - scrubProgress) < 0.008 {
                isHoldingCommittedSeek = false
            }
            guard !usesScrubProgress else { return }
            anchorTime = sanitizedTime(newTime)
            anchorDate = Date()
        }
        .onChange(of: isPlaying) { _, _ in
            synchronizePlaybackAnchor()
            synchronizeComputeWorkload()
        }
        .onChange(of: hasVisibleFluid) { _, _ in
            synchronizeComputeWorkload()
        }
        .onChange(of: scenePhase) { _, _ in
            synchronizeComputeWorkload()
        }
        .onChange(of: reduceMotion) { _, _ in
            synchronizeComputeWorkload()
        }
        .onDisappear {
            isVisible = false
            cancelScrubPreview()
            if let computeWorkloadToken {
                MonoComputeEngine.shared.endWorkload(computeWorkloadToken)
                self.computeWorkloadToken = nil
            }
        }
        .monoSheet(isPresented: $showPlaylist, preset: .standard) {
            if player.isPlayingPodcast {
                PodcastPlaylistPopupView()
            } else {
                PlaylistPopupView()
            }
        }
    }

    private func miniPlayerContent(song: Song) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                fluidArtworkDisc(song: song)

                VStack(alignment: .leading, spacing: 1) {
                    splitMarqueeText(
                        text: song.name,
                        font: .system(size: 14, weight: .semibold, design: .rounded),
                        panelColor: .monoTextPrimary,
                        fluidColor: fluidPrimaryColor,
                        coverage: fluxCoverage(progress: fluidProgress, start: 0.14, end: 0.66),
                        speed: 24
                    )

                    FloatingBarLyricReader { lineText in
                        HStack(spacing: 5) {
                            FluxPlaybackIndicator(
                                isActive: isVisible && isPlaying && !isLoading,
                                color: fluxCoverage(progress: fluidProgress, start: 0.14, end: 0.18) >= 0.5
                                    ? fluidSecondaryColor : Color.monoTextSecondary
                            )
                            .id(song.identityKey)

                            splitMarqueeText(
                                text: lineText ?? song.artistName,
                                font: .system(size: 11, weight: .medium, design: .rounded),
                                panelColor: .monoTextSecondary,
                                fluidColor: fluidSecondaryColor,
                                coverage: fluxCoverage(progress: fluidProgress, start: 0.14, end: 0.66),
                                speed: 22
                            )
                            .contentTransition(.interpolate)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .swipeSkipTextMotion()
            }
            .contentShape(Rectangle())
            .onTapWithHaptic { openPlayer() }
            .swipeToSkip()

            Button {
                player.togglePlayPause()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(
                                fluxCoverage(progress: fluidProgress, start: 0.70, end: 0.79) >= 0.5
                                    ? fluidPrimaryColor
                                    : Color.monoTextPrimary
                            )
                            .scaleEffect(0.72)
                    } else {
                        fluidControlIcon(
                            icon: isPlaying ? .pause : .play,
                            size: 14,
                            panelColor: Color.monoTextPrimary,
                            fluidColor: fluidPrimaryColor,
                            lineWidth: 1.8,
                            coverage: fluxCoverage(progress: fluidProgress, start: 0.70, end: 0.79)
                        )
                    }
                }
                .frame(width: 34, height: 34)
                .background(
                    fluxSplitGradient(
                        fluid: fluidPrimaryColor.opacity(0.10),
                        panel: Color.monoTextPrimary.opacity(0.08),
                        coverage: fluxCoverage(progress: fluidProgress, start: 0.70, end: 0.79)
                    ),
                    in: Circle()
                )
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.91))

            Button {
                HapticManager.shared.light()
                showPlaylist = true
            } label: {
                fluidControlIcon(
                    icon: .list,
                    size: 15,
                    panelColor: Color.monoTextSecondary,
                    fluidColor: fluidSecondaryColor,
                    lineWidth: 1.7,
                    coverage: fluxCoverage(progress: fluidProgress, start: 0.80, end: 0.89)
                )
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.91))
            .accessibilityLabel(String(localized: "player_queue"))

            Button {
                HapticManager.shared.light()
                showingTabs = true
            } label: {
                fluidControlIcon(
                    icon: .tabBar,
                    size: 15,
                    panelColor: Color.monoTextSecondary,
                    fluidColor: fluidSecondaryColor,
                    lineWidth: 1.7,
                    coverage: fluxCoverage(progress: fluidProgress, start: 0.90, end: 1.0)
                )
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.91))
            .accessibilityLabel(String(localized: "settings_floating_bar"))
        }
    }

    private func splitMarqueeText(
        text: String,
        font: Font,
        panelColor: Color,
        fluidColor: Color,
        coverage: Double,
        speed: Double
    ) -> some View {
        ZStack(alignment: .leading) {
            MarqueeText(text: text, font: font, color: panelColor, speed: speed)

            MarqueeText(text: text, font: font, color: fluidColor, speed: speed)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Color.white
                                .frame(width: proxy.size.width * min(max(coverage, 0), 1))
                            Spacer(minLength: 0)
                        }
                    }
                }
        }
        .frame(height: 20)
        .clipped()
    }

    private func fluidArtworkDisc(song: Song) -> some View {
        ZStack {
            Circle()
                .fill((palette.first ?? Color.monoAccent).opacity(hasVisibleFluid ? 0.30 : 0.10))
                .frame(width: 46, height: 46)
                .blur(radius: 5)

            Circle()
                .stroke(
                    AngularGradient(colors: artworkRingColors, center: .center),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-artworkRotation * 0.42))

            CachedAsyncImage(url: song.coverUrl?.sized(180)) {
                Circle()
                    .fill(Color.monoSeparator.opacity(0.30))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 39, height: 39)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 0.65)
            }
            .rotationEffect(.degrees(artworkRotation))

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .fill(fluidPrimaryColor.opacity(0.82))
                        .frame(width: 2.4, height: 2.4)
                }
        }
        .frame(width: 46, height: 46)
        .compositingGroup()
        .shadow(
            color: (palette.first ?? Color.monoAccent).opacity(hasVisibleFluid ? 0.26 : 0.08),
            radius: 7,
            x: 0,
            y: 2
        )
        .animation(
            isPlaying && !reduceMotion ? .linear(duration: 0.28) : nil,
            value: playbackTime.currentTime
        )
    }

    @ViewBuilder
    private func fluidControlIcon(
        icon: MonoIcon.IconType,
        size: CGFloat,
        panelColor: Color,
        fluidColor: Color,
        lineWidth: CGFloat,
        coverage: Double
    ) -> some View {
        if usesAdaptiveOriginalArtwork {
            FloatingBarArtworkProgressIcon(
                icon: icon,
                size: size,
                frameSize: size,
                lineWidth: lineWidth,
                panelColor: panelColor,
                coveredColor: fluidColor,
                panelBackgroundColor: .monoStructuralBackground,
                coveredBackgroundColor: coverColors.isDark ? .black : .white,
                coverage: coverage
            )
        } else {
            ZStack {
                MonoIcon(
                    icon: icon,
                    size: size,
                    color: panelColor,
                    lineWidth: lineWidth,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )

                MonoIcon(
                    icon: icon,
                    size: size,
                    color: fluidColor,
                    lineWidth: lineWidth,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Color.white
                                    .frame(width: proxy.size.width * min(max(coverage, 0), 1))
                                Spacer(minLength: 0)
                            }
                        }
                    }
            }
        }
    }

    private func selectTab(_ tab: Tab) {
        if currentTab != tab {
            HapticManager.shared.light()
            currentTab = tab
            return
        }

        // 展开后的 Tab 导航由用户显式控制；切换页面不再强制收回。
        // 再次点击当前 Tab 才恢复常规迷你播放器。
        guard currentSong != nil else { return }
        HapticManager.shared.light()
        showingTabs = false
    }

    private func openPlayer() {
        withAnimation(MonoAnimation.playerTransition) {
            switch player.playSource {
            case .fm:
                NotificationCenter.default.post(name: .init("OpenFMPlayer"), object: nil)
            case let .podcast(radioID):
                NotificationCenter.default.post(name: .init("OpenRadioPlayer"), object: radioID)
            case .normal:
                NotificationCenter.default.post(name: .init("OpenNormalPlayer"), object: nil)
            }
        }
    }

    private func synchronizePlaybackAnchor() {
        anchorTime = sanitizedTime(playbackTime.currentTime)
        anchorDate = Date()
    }

    private func synchronizeComputeWorkload() {
        let shouldObserve = hasVisibleFluid
            && isVisible
            && isPlaying
            && scenePhase == .active
            && !reduceMotion
        if shouldObserve, computeWorkloadToken == nil {
            computeWorkloadToken = MonoComputeEngine.shared.beginWorkload(.fluidFloatingBar)
        } else if !shouldObserve, let computeWorkloadToken {
            MonoComputeEngine.shared.endWorkload(computeWorkloadToken)
            self.computeWorkloadToken = nil
        }
    }

    private func sanitizedTime(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 7, coordinateSpace: .local)
            .onChanged { value in
                guard currentSong != nil,
                      playbackTime.duration.isFinite,
                      playbackTime.duration > 0,
                      barWidth > 1 else { return }

                if !isScrubbing {
                    scrubGeneration += 1
                    isHoldingCommittedSeek = false
                    scrubProgress = liveProgress
                    scrubStartProgress = liveProgress
                    scrubTargetProgress = liveProgress
                    scrubFlowIntensity = 0
                    lastScrubTranslation = value.translation.width
                    lastScrubUpdate = Date()
                    isScrubbing = true
                }

                let now = Date()
                let elapsed = max(now.timeIntervalSince(lastScrubUpdate), 1.0 / 120.0)
                let translationDelta = value.translation.width - lastScrubTranslation
                let normalizedVelocity = translationDelta / barWidth / CGFloat(elapsed)
                let nextFlow = min(max(normalizedVelocity / 1.65, -1), 1)
                scrubFlowIntensity = scrubFlowIntensity * 0.68 + nextFlow * 0.32
                scrubLocation = min(max(value.location.x / barWidth, 0), 1)
                lastScrubTranslation = value.translation.width
                lastScrubUpdate = now

                // 以按下时的进度为锚点，而不是直接映射手指的绝对位置。
                // 1.65 倍行程提供类似液体阻尼的精细拖动，避免刚按下就跳进度。
                let travel = max(barWidth * 1.65, 1)
                let target = min(max(scrubStartProgress + Double(value.translation.width / travel), 0), 1)
                scrubTargetProgress = target

                // 手指事件本身已接近屏幕刷新率；这里使用低通跟随而不是为每个事件
                // 重启一次弹簧动画，避免动画互相打断造成前沿猛抖。
                let distance = target - scrubProgress
                let response = min(max(0.22 + abs(distance) * 1.4, 0.22), 0.48)
                scrubProgress += distance * response
                anchorTime = scrubProgress * playbackTime.duration
                anchorDate = Date()
            }
            .onEnded { _ in
                commitScrubIfNeeded()
            }
    }

    private func commitScrubIfNeeded() {
        guard isScrubbing, playbackTime.duration.isFinite, playbackTime.duration > 0 else {
            isScrubbing = false
            return
        }

        let generation = scrubGeneration
        let committedProgress = min(max(scrubTargetProgress, 0), 1)
        let target = committedProgress * playbackTime.duration
        isScrubbing = false
        isHoldingCommittedSeek = true
        if reduceMotion {
            scrubProgress = committedProgress
        } else {
            withAnimation(.smooth(duration: 0.18)) {
                scrubProgress = committedProgress
            }
            withAnimation(.easeOut(duration: 0.42)) {
                scrubFlowIntensity = 0
            }
        }
        anchorTime = scrubProgress * playbackTime.duration
        anchorDate = Date()
        player.seek(to: target)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard generation == scrubGeneration, isHoldingCommittedSeek else { return }
            isHoldingCommittedSeek = false
            synchronizePlaybackAnchor()
        }
    }

    private func cancelScrubPreview() {
        scrubGeneration += 1
        isScrubbing = false
        isHoldingCommittedSeek = false
        scrubFlowIntensity = 0
    }
}

@MainActor
private struct FluxTabContent: View {
    let currentTab: Tab
    let panelPrimaryColor: Color
    let panelSecondaryColor: Color
    let panelBackgroundColor: Color
    let fluidPrimaryColor: Color
    let fluidSecondaryColor: Color
    let fluidBackgroundColor: Color
    let fluidProgress: Double
    let onSelect: (Tab) -> Void

    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @AppStorage(AppConfig.StorageKeys.interfaceIconSet) private var iconSetRaw: String = AppInterfaceIconSet.hicon.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private var usesAdaptiveOriginalArtwork: Bool {
        _ = iconSetRaw
        return [.pulseBloom, .monoGlyph].contains(AppInterfaceIconSet.selectedFromDefaults)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, tab in
                    tabButton(tab, index: index, contentWidth: proxy.size.width)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.22),
            value: currentTab
        )
    }

    private func tabButton(_ tab: Tab, index: Int, contentWidth: CGFloat) -> some View {
        let iconFrame: CGFloat = 28
        let iconSize: CGFloat = 21
        let selected = currentTab == tab
        let tabCount = max(Tab.allCases.count, 1)
        let tabWidth = contentWidth / CGFloat(tabCount)
        let tabStart = CGFloat(index) * tabWidth
        let coverage = floatingBarElementCoverage(
            progress: fluidProgress,
            contentWidth: contentWidth,
            elementMinX: tabStart,
            elementWidth: tabWidth
        )
        let iconCoverage = floatingBarElementCoverage(
            progress: fluidProgress,
            contentWidth: contentWidth,
            elementMinX: tabStart + max((tabWidth - iconFrame) / 2, 0),
            elementWidth: iconFrame
        )
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                splitIcon(
                    icon: icon(for: tab, selected: selected),
                    size: iconSize,
                    frameSize: iconFrame,
                    panelColor: selected ? panelPrimaryColor : panelSecondaryColor,
                    fluidColor: selected ? fluidPrimaryColor : fluidSecondaryColor,
                    lineWidth: selected ? 1.9 : 1.6,
                    coverage: iconCoverage
                )
                .frame(width: iconFrame, height: iconFrame)

                Text(NSLocalizedString(tab.titleKey(isLocalMode: !onlineAccess.canUseOnlineFeatures), comment: ""))
                    .font(.system(size: 9, weight: selected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(
                        fluxSplitGradient(
                            fluid: selected ? fluidPrimaryColor : fluidSecondaryColor,
                            panel: selected ? panelPrimaryColor : panelSecondaryColor,
                            coverage: coverage
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .offset(y: selected ? -0.6 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule(style: .continuous))
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(
                            fluxSplitGradient(
                                fluid: fluidPrimaryColor.opacity(0.11),
                                panel: panelPrimaryColor.opacity(0.09),
                                coverage: coverage
                            )
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    fluxSplitGradient(
                                        fluid: fluidPrimaryColor.opacity(0.24),
                                        panel: panelPrimaryColor.opacity(0.18),
                                        coverage: coverage
                                    ),
                                    lineWidth: 0.65
                                )
                        }
                        .overlay(alignment: .bottom) {
                            Capsule(style: .continuous)
                                .fill(
                                    fluxSplitGradient(
                                        fluid: fluidPrimaryColor.opacity(0.86),
                                        panel: panelPrimaryColor.opacity(0.66),
                                        coverage: coverage
                                    )
                                )
                                .frame(width: 17, height: 2)
                                .padding(.bottom, 2.5)
                        }
                        .matchedGeometryEffect(id: "flux-selection", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(FluxTabPressStyle())
        .accessibilityLabel(NSLocalizedString(tab.titleKey(isLocalMode: !onlineAccess.canUseOnlineFeatures), comment: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func splitIcon(
        icon: MonoIcon.IconType,
        size: CGFloat,
        frameSize: CGFloat,
        panelColor: Color,
        fluidColor: Color,
        lineWidth: CGFloat,
        coverage: Double
    ) -> some View {
        if usesAdaptiveOriginalArtwork {
            FloatingBarArtworkProgressIcon(
                icon: icon,
                size: size,
                frameSize: frameSize,
                lineWidth: lineWidth,
                panelColor: panelColor,
                coveredColor: fluidColor,
                panelBackgroundColor: panelBackgroundColor,
                coveredBackgroundColor: fluidBackgroundColor,
                coverage: coverage
            )
        } else {
            ZStack {
                MonoIcon(
                    icon: icon,
                    size: size,
                    color: panelColor,
                    lineWidth: lineWidth,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                    .frame(width: size, height: size)

                MonoIcon(
                    icon: icon,
                    size: size,
                    color: fluidColor,
                    lineWidth: lineWidth,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                    .frame(width: size, height: size)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Color.white
                                    .frame(width: proxy.size.width * min(max(coverage, 0), 1))
                                Spacer(minLength: 0)
                            }
                        }
                    }
            }
        }
    }

    private func icon(for tab: Tab, selected: Bool) -> MonoIcon.IconType {
        switch tab {
        case .home:
            return selected ? .homeFilled : .home
        case .podcast:
            if onlineAccess.canUseOnlineFeatures {
                return selected ? .podcastFilled : .podcast
            }
            return selected ? .musicNoteList : .musicNote
        case .library:
            return selected ? .libraryFilled : .library
        case .profile:
            return selected ? .profileFilled : .profile
        }
    }
}

private struct FluxLivingMaterial: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    let colors: [Color]
    let anchorTime: Double
    let anchorDate: Date
    let duration: Double
    let isPlaying: Bool
    let fillsEntireSurface: Bool
    let stir: CGFloat
    let touchPosition: CGFloat
    let isInteracting: Bool
    let isDarkMaterial: Bool
    let motionSeed: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = colorRevision

        GeometryReader { proxy in
            if #available(iOS 17.0, *) {
                FluxMetalMaterial(
                    size: CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1)),
                    colors: resolvedColors,
                    anchorTime: anchorTime,
                    anchorDate: anchorDate,
                    duration: duration,
                    isPlaying: isPlaying,
                    fillsEntireSurface: fillsEntireSurface,
                    stir: stir,
                    touchPosition: touchPosition,
                    motionSeed: motionSeed,
                    isDarkMode: isDarkMaterial,
                    isPaused: reduceMotion || (!isPlaying && !isInteracting) || scenePhase != .active
                )
            } else {
                fallbackMaterial
            }
        }
    }

    private var resolvedColors: [Color] {
        guard colors.count >= 3 else {
            return [Color.monoAccent, Color.monoAccent.opacity(0.72), Color.monoTextSecondary]
        }
        return Array(colors.prefix(3))
    }

    private var fallbackProgress: CGFloat {
        if fillsEntireSurface { return 1 }
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(anchorTime / duration, 0), 1)
    }

    private var fallbackMaterial: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                LinearGradient(
                    colors: resolvedColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * fallbackProgress)

                Spacer(minLength: 0)
            }
        }
    }
}

private struct FluxPerimeterProgress: View {
    let anchorTime: Double
    let anchorDate: Date
    let duration: Double
    let isPlaying: Bool
    let isPaused: Bool
    let darkStyle: Bool

    var body: some View {
        TimelineView(
            AppFrameRate.throttledTimeline(
                maximumFramesPerSecond: 30,
                paused: isPaused || !isPlaying
            )
        ) { context in
            let time = projectedPlaybackTime(at: context.date)
            let progress = resolvedProgress(at: time)

            GeometryReader { proxy in
                let point = FluxCapsulePerimeterMetrics.point(
                    at: progress,
                    in: CGRect(origin: .zero, size: proxy.size)
                )
                let pulsePhase = CGFloat(sin(context.date.timeIntervalSinceReferenceDate * 3.6))
                let pulse: CGFloat = isPaused || !isPlaying ? 1 : 0.96 + pulsePhase * 0.06
                let glowOpacity: Double = isPaused || !isPlaying
                    ? 0.16
                    : 0.18 + Double((pulsePhase + 1) * 0.04)
                let neutralColor = darkStyle ? Color.white : Color.black

                ZStack {
                    FluxCapsulePerimeterShape()
                        .stroke(
                            darkStyle ? Color.white.opacity(0.10) : Color.black.opacity(0.07),
                            lineWidth: 1.2
                        )

                    FluxCapsulePerimeterShape()
                        .trim(from: 0, to: max(CGFloat(progress), 0.0001))
                        .stroke(
                            neutralColor.opacity(darkStyle ? 0.42 : 0.22),
                            style: StrokeStyle(lineWidth: 2.15, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(
                            color: neutralColor.opacity(darkStyle ? 0.14 : 0.08),
                            radius: 2.2
                        )

                    if progress > 0.002, progress < 0.999 {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        neutralColor.opacity(glowOpacity),
                                        neutralColor.opacity(glowOpacity * 0.30),
                                        Color.clear,
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 4.4
                                )
                            )
                            .frame(width: 8.8, height: 8.8)
                            .blur(radius: 0.45)
                            .scaleEffect(pulse)
                            .position(point)
                    }
                }
            }
        }
    }

    private func projectedPlaybackTime(at date: Date) -> Double {
        let elapsed = isPlaying ? max(date.timeIntervalSince(anchorDate), 0) : 0
        let projected = anchorTime + elapsed
        guard duration.isFinite, duration > 0 else { return max(projected, 0) }
        return min(max(projected, 0), duration)
    }

    private func resolvedProgress(at time: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}

private struct FluxCapsulePerimeterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, rect.width / 2)
        let midY = rect.midY
        let kappa = 0.552_284_749_8
        let control = radius * kappa
        var path = Path()

        // 从左下切点开始，先沿底边前进，让播放进度始终从悬浮栏底部出现。
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: rect.maxX - radius + control, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: midY + control)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: midY - control),
            control2: CGPoint(x: rect.maxX - radius + control, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: midY),
            control1: CGPoint(x: rect.minX + radius - control, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: midY - control)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: midY + control),
            control2: CGPoint(x: rect.minX + radius - control, y: rect.maxY)
        )
        return path
    }
}

private enum FluxCapsulePerimeterMetrics {
    static func point(at progress: Double, in rect: CGRect) -> CGPoint {
        let radius = min(rect.height / 2, rect.width / 2)
        let horizontal = max(rect.width - radius * 2, 0)
        let arc = CGFloat.pi * radius
        let total = horizontal * 2 + arc * 2
        guard total > 0, radius > 0 else { return CGPoint(x: rect.midX, y: rect.maxY) }

        var distance = CGFloat(min(max(progress, 0), 1)) * total
        if distance <= horizontal {
            return CGPoint(x: rect.minX + radius + distance, y: rect.maxY)
        }
        distance -= horizontal

        if distance <= arc {
            let angle = Double.pi / 2 - Double(distance / radius)
            return CGPoint(
                x: rect.maxX - radius + radius * cos(angle),
                y: rect.midY + radius * sin(angle)
            )
        }
        distance -= arc

        if distance <= horizontal {
            return CGPoint(x: rect.maxX - radius - distance, y: rect.minY)
        }
        distance -= horizontal

        let angle = -Double.pi / 2 - Double(min(distance, arc) / radius)
        return CGPoint(
            x: rect.minX + radius + radius * cos(angle),
            y: rect.midY + radius * sin(angle)
        )
    }
}

@available(iOS 17.0, *)
private struct FluxMetalMaterial: View {
    let size: CGSize
    let colors: [Color]
    let anchorTime: Double
    let anchorDate: Date
    let duration: Double
    let isPlaying: Bool
    let fillsEntireSurface: Bool
    let stir: CGFloat
    let touchPosition: CGFloat
    let motionSeed: CGFloat
    let isDarkMode: Bool
    let isPaused: Bool

    var body: some View {
        TimelineView(
            AppFrameRate.throttledTimeline(
                maximumFramesPerSecond: 30,
                paused: isPaused
            )
        ) { context in
            let projectedPlaybackTime = resolvedPlaybackTime(at: context.date)
            let progress = resolvedProgress(at: projectedPlaybackTime)
            // 云雾形态使用独立的连续时钟。不能把歌曲时间当噪声相位，
            // 否则拖动几秒就会令 FBM 跨越大量相位，看起来像猛烈闪跳。
            let motionTime = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 600)

            FluxMaterialSurface(
                size: size,
                colors: colors,
                time: motionTime,
                progress: progress,
                stir: stir,
                touchPosition: touchPosition,
                motionSeed: motionSeed,
                isDarkMode: isDarkMode
            )
        }
    }

    private func resolvedPlaybackTime(at date: Date) -> Double {
        let elapsed = isPlaying ? max(date.timeIntervalSince(anchorDate), 0) : 0
        let projected = anchorTime + elapsed
        guard duration.isFinite, duration > 0 else { return max(projected, 0) }
        return min(max(projected, 0), duration)
    }

    private func resolvedProgress(at time: Double) -> Double {
        if fillsEntireSurface { return 1 }
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}

private func fluxMotionSeed(for song: Song?) -> CGFloat {
    guard let song else { return 0.283 }
    let identity = "\(song.musicSource.rawValue)|\(song.id)|\(song.name)|\(song.artistName)"
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in identity.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return CGFloat(hash % 10_007) / 10_006
}

private func fluxCoverage(progress: Double, start: Double, end: Double) -> Double {
    guard end > start else { return progress >= end ? 1 : 0 }
    return min(max((progress - start) / (end - start), 0), 1)
}

private func fluxSplitGradient(
    fluid: Color,
    panel: Color,
    coverage: Double
) -> LinearGradient {
    let clamped = min(max(coverage, 0), 1)
    if clamped <= 0.001 {
        return LinearGradient(colors: [panel, panel], startPoint: .leading, endPoint: .trailing)
    }
    if clamped >= 0.999 {
        return LinearGradient(colors: [fluid, fluid], startPoint: .leading, endPoint: .trailing)
    }

    let edge = CGFloat(clamped)
    let feather: CGFloat = 0.025
    return LinearGradient(
        stops: [
            .init(color: fluid, location: 0),
            .init(color: fluid, location: max(edge - feather, 0)),
            .init(color: panel, location: min(edge + feather, 1)),
            .init(color: panel, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct FluxTabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
