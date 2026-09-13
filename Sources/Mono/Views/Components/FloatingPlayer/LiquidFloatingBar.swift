import SwiftUI

/// 独立的液态悬浮栏。与云雾样式不同，播放进度本身是一团沿水平方向推进、
/// 带液面和分离液滴的实体液体；容器材质跟随全局液态玻璃开关。
@MainActor
struct LiquidFloatingBar: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab

    private let player = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @ObservedObject private var playbackTime = PlaybackTimePublisher.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var coverColors = CoverColorExtractor(minimumColorCount: 3)
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
    @State private var scrubFlow: CGFloat = 0
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

    private var hasResolvedPalette: Bool {
        guard let artworkURL else { return false }
        return coverColors.resolvedURL == artworkURL
    }

    private var liveProgress: Double {
        guard playbackTime.duration.isFinite, playbackTime.duration > 0,
              playbackTime.currentTime.isFinite else { return 0 }
        return min(max(playbackTime.currentTime / playbackTime.duration, 0), 1)
    }

    private var usesScrubProgress: Bool {
        isScrubbing || isHoldingCommittedSeek
    }

    private var progress: Double {
        usesScrubProgress ? scrubProgress : liveProgress
    }

    private var presentedAnchorTime: Double {
        usesScrubProgress ? scrubProgress * playbackTime.duration : anchorTime
    }

    private var motionSeed: CGFloat {
        liquidMotionSeed(for: currentSong)
    }

    private var liquidColors: [Color] {
        let palette = coverColors.palette
        guard hasResolvedPalette, palette.count >= 2 else {
            return [Color.monoAccent, Color.monoAccent.opacity(0.76), Color.monoAccent.opacity(0.56)]
        }
        if palette.count == 2 {
            return [palette[0], palette[1], palette[0].opacity(0.72)]
        }
        return [palette[0], palette[palette.count / 2], palette[palette.count - 1]]
    }

    private var liquidPrimaryColor: Color {
        hasResolvedPalette ? coverColors.contentColor : .white
    }

    private var liquidSecondaryColor: Color {
        hasResolvedPalette ? coverColors.secondaryContentColor : .white.opacity(0.72)
    }

    private var usesAdaptiveOriginalArtwork: Bool {
        _ = iconSetRaw
        return [.pulseBloom, .monoGlyph].contains(AppInterfaceIconSet.selectedFromDefaults)
    }

    var body: some View {
        let _ = colorRevision

        let _ = settings.globalThemeRevision

        ZStack {
            FluidFloatingBarShell()

            if currentSong != nil, playbackTime.duration > 0 {
                LiquidPlaybackProgress(
                    colors: liquidColors,
                    anchorTime: presentedAnchorTime,
                    anchorDate: anchorDate,
                    duration: playbackTime.duration,
                    isPlaying: isVisible && isPlaying && !usesScrubProgress,
                    isPaused: reduceMotion || scenePhase != .active || !isVisible,
                    isInteracting: isScrubbing,
                    isDarkMaterial: hasResolvedPalette ? coverColors.isDark : true,
                    reducesMotion: reduceMotion,
                    scrubFlow: scrubFlow,
                    motionSeed: motionSeed
                )
                .clipShape(Capsule(style: .continuous))
                .transition(.opacity)
            }

            Group {
                if displaysTabs {
                    LiquidTabContent(
                        currentTab: currentTab,
                        panelPrimaryColor: .monoTextPrimary,
                        panelSecondaryColor: Color.monoTextPrimary.opacity(0.78),
                        panelBackgroundColor: .monoStructuralBackground,
                        liquidPrimaryColor: liquidPrimaryColor,
                        liquidSecondaryColor: liquidPrimaryColor.opacity(0.82),
                        liquidBackgroundColor: hasResolvedPalette && !coverColors.isDark ? .white : .black,
                        liquidProgress: progress,
                        onSelect: selectTab
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if let song = currentSong {
                    miniPlayer(song: song)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 64)
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.16)
                        : Color.black.opacity(0.09),
                    lineWidth: 0.8
                )
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.24))
                .frame(height: 1)
                .padding(.horizontal, 24)
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
        .shadow(
            color: (liquidColors.first ?? Color.monoAccent).opacity(colorScheme == .dark ? 0.24 : 0.15),
            radius: 12,
            x: 0,
            y: 7
        )
        .contentShape(Capsule(style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { barWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in barWidth = width }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: displaysTabs)
        .onReceive(player.$currentSong) { currentSong = $0 }
        .onReceive(player.$isPlaying.removeDuplicates()) { isPlaying = $0 }
        .onAppear {
            isVisible = true
            synchronizePlaybackAnchor()
            coverColors.extract(from: artworkURL)
            synchronizeWorkload()
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
            synchronizeWorkload()
        }
        .onChange(of: scenePhase) { _, _ in
            synchronizeWorkload()
        }
        .onChange(of: reduceMotion) { _, _ in
            synchronizeWorkload()
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

    private func miniPlayer(song: Song) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 10) {
                liquidArtwork(song: song)

                VStack(alignment: .leading, spacing: 1) {
                    splitMarqueeText(
                        text: song.name,
                        font: .system(size: 14, weight: .semibold, design: .rounded),
                        panelColor: .monoTextPrimary,
                        liquidColor: liquidPrimaryColor,
                        coverage: liquidCoverage(progress: progress, start: 0.14, end: 0.65),
                        speed: 24
                    )

                    FloatingBarLyricReader { lineText in
                        splitMarqueeText(
                            text: lineText ?? song.artistName,
                            font: .system(size: 11, weight: .medium, design: .rounded),
                            panelColor: .monoTextSecondary,
                            liquidColor: liquidSecondaryColor,
                            coverage: liquidCoverage(progress: progress, start: 0.14, end: 0.65),
                            speed: 22
                        )
                            .contentTransition(.interpolate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .swipeSkipTextMotion()
            }
            .contentShape(Rectangle())
            .onTapWithHaptic { openPlayer() }
            .swipeToSkip()

            liquidButton(
                icon: isPlaying ? .pause : .play,
                start: 0.68,
                end: 0.78,
                primary: true
            ) {
                player.togglePlayPause()
            }

            liquidButton(icon: .list, start: 0.79, end: 0.89) {
                HapticManager.shared.light()
                showPlaylist = true
            }
            .accessibilityLabel(String(localized: "player_queue"))

            liquidButton(icon: .tabBar, start: 0.90, end: 1) {
                HapticManager.shared.light()
                showingTabs = true
            }
            .accessibilityLabel(String(localized: "settings_floating_bar"))
        }
    }

    private func splitMarqueeText(
        text: String,
        font: Font,
        panelColor: Color,
        liquidColor: Color,
        coverage: Double,
        speed: Double
    ) -> some View {
        ZStack(alignment: .leading) {
            MarqueeText(text: text, font: font, color: panelColor, speed: speed)

            MarqueeText(text: text, font: font, color: liquidColor, speed: speed)
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

    private func liquidArtwork(song: Song) -> some View {
        let rotation = reduceMotion ? 0 : sanitizedTime(playbackTime.currentTime) * 22
        return ZStack {
            Circle()
                .fill((liquidColors.first ?? Color.monoAccent).opacity(0.30))
                .frame(width: 46, height: 46)

            CachedAsyncImage(url: song.coverUrl?.sized(180)) {
                Circle().fill(Color.monoSeparator.opacity(0.30))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 39, height: 39)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.36), lineWidth: 0.7))
            .rotationEffect(.degrees(rotation))

            Circle()
                .fill(liquidPrimaryColor.opacity(0.90))
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.5))
        }
        .frame(width: 46, height: 46)
        .shadow(color: (liquidColors.first ?? Color.monoAccent).opacity(0.28), radius: 5)
        .animation(
            isPlaying && !reduceMotion ? .linear(duration: 0.28) : nil,
            value: playbackTime.currentTime
        )
    }

    private func liquidButton(
        icon: MonoIcon.IconType,
        start: Double,
        end: Double,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let coverage = liquidCoverage(progress: progress, start: start, end: end)
        let panelColor: Color = primary ? .monoTextPrimary : .monoTextSecondary
        let fillColor: Color = primary ? liquidPrimaryColor : liquidSecondaryColor
        return Button(action: action) {
            splitIcon(
                icon: icon,
                panelColor: panelColor,
                liquidColor: fillColor,
                coverage: coverage
            )
            .frame(width: primary ? 34 : 31, height: primary ? 34 : 31)
            .background(
                liquidSplitGradient(
                    liquid: liquidPrimaryColor.opacity(primary ? 0.13 : 0.07),
                    panel: Color.monoTextPrimary.opacity(primary ? 0.08 : 0.04),
                    coverage: coverage
                ),
                in: Circle()
            )
            .contentShape(Circle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.91))
    }

    @ViewBuilder
    private func splitIcon(
        icon: MonoIcon.IconType,
        panelColor: Color,
        liquidColor: Color,
        coverage: Double
    ) -> some View {
        if usesAdaptiveOriginalArtwork {
            FloatingBarArtworkProgressIcon(
                icon: icon,
                size: 15,
                frameSize: 15,
                lineWidth: 1.75,
                panelColor: panelColor,
                coveredColor: liquidColor,
                panelBackgroundColor: .monoStructuralBackground,
                coveredBackgroundColor: hasResolvedPalette && !coverColors.isDark ? .white : .black,
                coverage: coverage
            )
        } else {
            ZStack {
                MonoIcon(
                    icon: icon,
                    size: 15,
                    color: panelColor,
                    lineWidth: 1.75,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                MonoIcon(
                    icon: icon,
                    size: 15,
                    color: liquidColor,
                    lineWidth: 1.75,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Color.white.frame(width: proxy.size.width * min(max(coverage, 0), 1))
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

    private func synchronizeWorkload() {
        let shouldRun = currentSong != nil
            && isVisible
            && isPlaying
            && scenePhase == .active
            && !reduceMotion
        if shouldRun, computeWorkloadToken == nil {
            computeWorkloadToken = MonoComputeEngine.shared.beginWorkload(.fluidFloatingBar)
        } else if !shouldRun, let computeWorkloadToken {
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
                    scrubFlow = 0
                    lastScrubTranslation = value.translation.width
                    lastScrubUpdate = Date()
                    isScrubbing = true
                }

                let now = Date()
                let elapsed = max(now.timeIntervalSince(lastScrubUpdate), 1.0 / 120.0)
                let translationDelta = value.translation.width - lastScrubTranslation
                let signedVelocity = translationDelta / barWidth / CGFloat(elapsed)
                let normalizedFlow = min(max(signedVelocity / 1.65, -1), 1)
                scrubFlow = scrubFlow * 0.66 + normalizedFlow * 0.34
                lastScrubTranslation = value.translation.width
                lastScrubUpdate = now

                let travel = max(barWidth * 1.65, 1)
                let target = min(max(scrubStartProgress + Double(value.translation.width / travel), 0), 1)
                scrubTargetProgress = target

                let distance = target - scrubProgress
                let response = min(max(0.20 + abs(distance) * 1.35, 0.20), 0.46)
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
            scrubFlow = 0
        } else {
            withAnimation(.smooth(duration: 0.20)) {
                scrubProgress = committedProgress
            }
            withAnimation(.easeOut(duration: 0.46)) {
                scrubFlow = 0
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
        scrubFlow = 0
    }
}

@MainActor
private struct LiquidTabContent: View {
    let currentTab: Tab
    let panelPrimaryColor: Color
    let panelSecondaryColor: Color
    let panelBackgroundColor: Color
    let liquidPrimaryColor: Color
    let liquidSecondaryColor: Color
    let liquidBackgroundColor: Color
    let liquidProgress: Double
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: currentTab)
    }

    private func tabButton(_ tab: Tab, index: Int, contentWidth: CGFloat) -> some View {
        let iconFrame: CGFloat = 28
        let selected = currentTab == tab
        let count = max(Tab.allCases.count, 1)
        let tabWidth = contentWidth / CGFloat(count)
        let tabStart = CGFloat(index) * tabWidth
        let coverage = floatingBarElementCoverage(
            progress: liquidProgress,
            contentWidth: contentWidth,
            elementMinX: tabStart,
            elementWidth: tabWidth
        )
        let iconCoverage = floatingBarElementCoverage(
            progress: liquidProgress,
            contentWidth: contentWidth,
            elementMinX: tabStart + max((tabWidth - iconFrame) / 2, 0),
            elementWidth: iconFrame
        )

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                tabIcon(tab, selected: selected, coverage: iconCoverage)

                Text(NSLocalizedString(tab.titleKey(isLocalMode: !onlineAccess.canUseOnlineFeatures), comment: ""))
                    .font(.system(size: 9, weight: selected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(
                        liquidSplitGradient(
                            liquid: selected ? liquidPrimaryColor : liquidSecondaryColor,
                            panel: selected ? panelPrimaryColor : panelSecondaryColor,
                            coverage: coverage
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .offset(y: selected ? -0.8 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule(style: .continuous))
            .background {
                if selected {
                    Circle()
                        .fill(
                            liquidSplitGradient(
                                liquid: liquidPrimaryColor.opacity(0.16),
                                panel: panelPrimaryColor.opacity(0.08),
                                coverage: coverage
                            )
                        )
                        .frame(width: 43, height: 43)
                        .blur(radius: 0.2)
                        .matchedGeometryEffect(id: "liquid-selection", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(LiquidTabPressStyle())
        .accessibilityLabel(NSLocalizedString(tab.titleKey(isLocalMode: !onlineAccess.canUseOnlineFeatures), comment: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func tabIcon(_ tab: Tab, selected: Bool, coverage: Double) -> some View {
        let icon = icon(for: tab, selected: selected)
        let iconFrame: CGFloat = 28
        let iconSize: CGFloat = 21
        if usesAdaptiveOriginalArtwork {
            FloatingBarArtworkProgressIcon(
                icon: icon,
                size: iconSize,
                frameSize: iconFrame,
                lineWidth: selected ? 1.9 : 1.6,
                panelColor: selected ? panelPrimaryColor : panelSecondaryColor,
                coveredColor: selected ? liquidPrimaryColor : liquidSecondaryColor,
                panelBackgroundColor: panelBackgroundColor,
                coveredBackgroundColor: liquidBackgroundColor,
                coverage: coverage
            )
        } else {
            ZStack {
                MonoIcon(
                    icon: icon,
                    size: iconSize,
                    color: selected ? panelPrimaryColor : panelSecondaryColor,
                    lineWidth: selected ? 1.9 : 1.6,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                .frame(width: iconFrame, height: iconFrame)
                MonoIcon(
                    icon: icon,
                    size: iconSize,
                    color: selected ? liquidPrimaryColor : liquidSecondaryColor,
                    lineWidth: selected ? 1.9 : 1.6,
                    normalizesBitmapScale: true,
                    forceTemplateRendering: true
                )
                .frame(width: iconFrame, height: iconFrame)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Color.white.frame(width: proxy.size.width * min(max(coverage, 0), 1))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func icon(for tab: Tab, selected: Bool) -> MonoIcon.IconType {
        switch tab {
        case .home: return selected ? .homeFilled : .home
        case .podcast:
            if onlineAccess.canUseOnlineFeatures {
                return selected ? .podcastFilled : .podcast
            }
            return selected ? .musicNoteList : .musicNote
        case .library: return selected ? .libraryFilled : .library
        case .profile: return selected ? .profileFilled : .profile
        }
    }
}

private struct LiquidPlaybackProgress: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    let colors: [Color]
    let anchorTime: Double
    let anchorDate: Date
    let duration: Double
    let isPlaying: Bool
    let isPaused: Bool
    let isInteracting: Bool
    let isDarkMaterial: Bool
    let reducesMotion: Bool
    let scrubFlow: CGFloat
    let motionSeed: CGFloat

    var body: some View {
        let _ = colorRevision

        TimelineView(
            AppFrameRate.throttledTimeline(
                maximumFramesPerSecond: 30,
                paused: isPaused || (!isPlaying && !isInteracting)
            )
        ) { context in
            LiquidMaterialSurface(
                colors: colors,
                progress: resolvedProgress(at: projectedTime(at: context.date)),
                time: reducesMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600),
                scrubFlow: reducesMotion ? 0 : scrubFlow,
                motionSeed: motionSeed,
                isDarkMaterial: isDarkMaterial
            )
        }
    }

    private func projectedTime(at date: Date) -> Double {
        let elapsed = isPlaying ? max(date.timeIntervalSince(anchorDate), 0) : 0
        let value = anchorTime + elapsed
        guard duration.isFinite, duration > 0 else { return max(value, 0) }
        return min(max(value, 0), duration)
    }

    private func resolvedProgress(at time: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}

private struct LiquidMaterialSurface: View, Animatable {
    let colors: [Color]
    nonisolated var progress: Double
    let time: TimeInterval
    nonisolated var scrubFlow: CGFloat
    let motionSeed: CGFloat
    let isDarkMaterial: Bool

    // Interpolate the entire contour and its glow together when a seek settles.
    nonisolated var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(progress, scrubFlow) }
        set {
            progress = newValue.first
            scrubFlow = newValue.second
        }
    }

    var body: some View {
        Canvas { graphics, size in
            drawLiquid(context: &graphics, size: size, progress: progress, time: time)
        }
    }

    private func drawLiquid(
        context: inout GraphicsContext,
        size: CGSize,
        progress: Double,
        time: Double
    ) {
        guard progress > 0.001, size.width > 0, size.height > 0 else { return }
        let front = min(max(CGFloat(progress) * size.width, 0), size.width)
        let profile = LiquidMotionProfile(seed: motionSeed)
        let flowStrength = min(abs(scrubFlow), 1)
        let flowDirection: CGFloat = scrubFlow < 0 ? -1 : 1
        let phase = CGFloat(time) * profile.waveSpeed + profile.phaseOffset
        let edgeEnvelope = CGFloat(min(1, max(0, progress / 0.06), max(0, (1 - progress) / 0.06)))
        let rippleAmplitude = min(
            size.height * (profile.baseRipple + flowStrength * 0.075 / profile.viscosity),
            12.8
        ) * edgeEnvelope
        let diagonalAmplitude = min(
            size.width * (0.018 + profile.surfaceTilt * 0.012 + flowStrength * 0.014),
            14.5
        ) * edgeEnvelope
        // 液面不会与手指完全同步倾斜：速度越快，靠惯性越向反方向滞后。
        let diagonalDirection = sin(phase * profile.tiltFrequency)
            - flowDirection * flowStrength * (0.48 / profile.viscosity)
        var body = Path()
        var surface = Path()

        if progress >= 0.997 {
            body.addRect(CGRect(origin: .zero, size: size))
        } else {
            body.move(to: .zero)
            body.addLine(to: CGPoint(x: resolvedFrontX(
                front: front,
                fraction: 0,
                phase: phase,
                rippleAmplitude: rippleAmplitude,
                diagonalAmplitude: diagonalAmplitude,
                diagonalDirection: diagonalDirection,
                profile: profile,
                scrubFlow: scrubFlow * edgeEnvelope,
                width: size.width
            ), y: 0))

            let steps = 48
            for step in 0...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                let y = fraction * size.height
                let x = resolvedFrontX(
                    front: front,
                    fraction: fraction,
                    phase: phase,
                    rippleAmplitude: rippleAmplitude,
                    diagonalAmplitude: diagonalAmplitude,
                    diagonalDirection: diagonalDirection,
                    profile: profile,
                    scrubFlow: scrubFlow * edgeEnvelope,
                    width: size.width
                )
                if step == 0 {
                    surface.move(to: CGPoint(x: x, y: y))
                } else {
                    surface.addLine(to: CGPoint(x: x, y: y))
                }
                body.addLine(to: CGPoint(x: x, y: y))
            }
            body.addLine(to: CGPoint(x: 0, y: size.height))
            body.closeSubpath()
        }

        context.fill(body, with: .color(isDarkMaterial ? Color(white: 0.025) : Color(white: 0.98)))
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: resolvedColors.map { $0.opacity(isDarkMaterial ? 0.56 : 0.70) }),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: max(size.width, 1), y: size.height)
            )
        )

        drawLiquidVolume(
            context: &context,
            body: body,
            size: size,
            front: front,
            phase: phase,
            profile: profile,
            flowStrength: flowStrength
        )

        if progress < 0.997 {
            drawSurfaceLight(
                context: &context,
                surface: surface,
                body: body,
                size: size,
                front: front,
                strength: edgeEnvelope,
                flowStrength: flowStrength
            )
        }

        guard progress > 0.025, progress < 0.95 else { return }
        drawVelocityDroplets(
            context: &context,
            size: size,
            front: front,
            phase: phase,
            profile: profile,
            flowStrength: flowStrength,
            flowDirection: flowDirection
        )
    }

    private func drawLiquidVolume(
        context: inout GraphicsContext,
        body: Path,
        size: CGSize,
        front: CGFloat,
        phase: CGFloat,
        profile: LiquidMotionProfile,
        flowStrength: CGFloat
    ) {
        // 顶部透光、底部密度更高，让颜色不再像一块扁平遮罩。
        context.drawLayer { layer in
            layer.clip(to: body)
            var depth = Path()
            depth.addRect(CGRect(origin: .zero, size: size))
            layer.fill(
                depth,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.22),
                        Color.clear,
                        Color.black.opacity(0.16),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }

        // Each wake has a different phase and depth but remains inside the same liquid body.
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.addFilter(.blur(radius: 2.8))

            for index in 0..<4 {
                let depth = CGFloat(index)
                let drift = phase * (profile.innerUpperSpeed + depth * 0.09)
                let inset = size.height * (0.22 + depth * 0.54)
                var wake = Path()
                for step in 0...32 {
                    let fraction = CGFloat(step) / 32
                    let curl = sin(fraction * .pi * 2.2 + drift + depth * 0.8)
                        + 0.38 * sin(fraction * .pi * 4.6 - phase * profile.innerLowerSpeed + depth)
                    let displacement = curl * size.height * (0.11 + flowStrength * 0.05)
                    let point = CGPoint(x: front - inset + displacement, y: fraction * size.height)
                    if step == 0 {
                        wake.move(to: point)
                    } else {
                        wake.addLine(to: point)
                    }
                }

                layer.stroke(
                    wake,
                    with: .color(Color.black.opacity(isDarkMaterial ? 0.30 : 0.08)),
                    style: StrokeStyle(lineWidth: 13 + depth * 2, lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    wake.offsetBy(dx: -3, dy: 0),
                    with: .linearGradient(
                        Gradient(colors: [
                            resolvedColors[index % resolvedColors.count].opacity(0.06),
                            resolvedColors[(index + 1) % resolvedColors.count].opacity(0.46 - Double(index) * 0.07),
                            Color.white.opacity(isDarkMaterial ? 0.15 : 0.25),
                            Color.clear,
                        ]),
                        startPoint: CGPoint(x: front - inset, y: 0),
                        endPoint: CGPoint(x: front - inset, y: size.height)
                    ),
                    style: StrokeStyle(lineWidth: 3.5 + depth * 1.3, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func drawSurfaceLight(
        context: inout GraphicsContext,
        surface: Path,
        body: Path,
        size: CGSize,
        front: CGFloat,
        strength: CGFloat,
        flowStrength: CGFloat
    ) {
        let pigment = resolvedColors[1]
        let light = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [pigment.opacity(0.55), pigment, Color.white.opacity(0.92), pigment]),
            startPoint: CGPoint(x: front, y: 0),
            endPoint: CGPoint(x: front, y: size.height)
        )

        // Broad pigment bloom, a narrower luminous edge, and a continuous hot core.
        context.drawLayer { glow in
            glow.opacity = Double(strength) * (isDarkMaterial ? 0.72 : 0.48)
            glow.addFilter(.blur(radius: 6))
            glow.stroke(
                surface,
                with: light,
                style: StrokeStyle(lineWidth: 10 + flowStrength * 3, lineCap: .round, lineJoin: .round)
            )
        }
        context.drawLayer { rim in
            rim.opacity = Double(strength)
            rim.addFilter(.blur(radius: 1.4))
            rim.stroke(
                surface,
                with: light,
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
            )
        }
        context.drawLayer { core in
            core.opacity = Double(strength)
            core.stroke(
                surface,
                with: .color(Color.white.opacity(isDarkMaterial ? 0.94 : 0.86)),
                style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
            )
        }
        context.drawLayer { refraction in
            refraction.clip(to: body)
            refraction.opacity = Double(strength) * 0.25
            refraction.addFilter(.blur(radius: 3))
            refraction.stroke(surface.offsetBy(dx: -9, dy: 0), with: light, lineWidth: 4)
        }
    }

    private func drawVelocityDroplets(
        context: inout GraphicsContext,
        size: CGSize,
        front: CGFloat,
        phase: CGFloat,
        profile: LiquidMotionProfile,
        flowStrength: CGFloat,
        flowDirection: CGFloat
    ) {
        let velocityEmergence = min(
            max((flowStrength - profile.dropletThreshold) / max(1 - profile.dropletThreshold, 0.01), 0),
            1
        )
        let pulse = (sin(phase * profile.dropletSpeed + profile.phaseOffset) + 1) * 0.5
        // 水珠始终保留：静止时贴着液面轻微呼吸；拖动加速后才被惯性
        // 拉成长水滴并逐渐脱离，避免既像固定圆点，也不会突然消失。
        let restingEmergence = 0.10 + pulse * (0.05 + profile.dropletScale * 0.035)
        let emergence = max(restingEmergence, velocityEmergence)
        let radius = 2.1 + emergence * (2.3 + profile.dropletScale * 1.2)
        let separation = 1.2 + emergence * (8.8 + profile.dropletScale * 4.2)
        let centerY = size.height * (0.25 + profile.dropletLane * 0.48)
            + sin(phase * 0.63 + profile.phaseOffset) * 2.6
        let leadingDirection: CGFloat = flowDirection >= 0 ? 1 : -1
        let centerX = min(max(front + leadingDirection * separation, radius), size.width - radius)
        let stretch = 1 + emergence * 1.25
        let alpha = 0.34 + Double(emergence) * 0.54

        // 先画一条会随速度拉断的液桥，水珠不再像贴上去的独立圆点。
        let bridgeLength = max(abs(centerX - front) - radius * 0.65, 0)
        if bridgeLength > 0.2, emergence < 0.92 {
            let bridgeWidth = max(0.7, radius * (0.72 - emergence * 0.48))
            let bridgeRect = CGRect(
                x: min(front, centerX),
                y: centerY - bridgeWidth / 2,
                width: bridgeLength + radius * 0.55,
                height: bridgeWidth
            )
            context.fill(
                Path(roundedRect: bridgeRect, cornerRadius: bridgeWidth / 2),
                with: .color((resolvedColors.last ?? Color.monoAccent).opacity(alpha * 0.72))
            )
        }

        let droplet = teardropPath(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            stretch: stretch,
            direction: leadingDirection
        )
        context.fill(
            droplet,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(alpha * 0.42),
                    (resolvedColors.last ?? Color.monoAccent).opacity(alpha),
                ]),
                startPoint: CGPoint(x: centerX, y: centerY - radius),
                endPoint: CGPoint(x: centerX, y: centerY + radius)
            )
        )

        if emergence > 0.66, profile.secondaryDroplet {
            let satelliteRadius = radius * (0.38 + pulse * 0.16)
            let satelliteX = min(
                max(centerX + leadingDirection * (radius * 2.0 + pulse * 4), satelliteRadius),
                size.width - satelliteRadius
            )
            let satelliteRect = CGRect(
                x: satelliteX - satelliteRadius,
                y: centerY + radius * 1.25 - satelliteRadius,
                width: satelliteRadius * 2,
                height: satelliteRadius * 2
            )
            context.fill(
                Path(ellipseIn: satelliteRect),
                with: .color((resolvedColors.dropFirst().first ?? Color.monoAccent).opacity(alpha * 0.72))
            )
        }
    }

    private func teardropPath(
        center: CGPoint,
        radius: CGFloat,
        stretch: CGFloat,
        direction: CGFloat
    ) -> Path {
        let tail = radius * stretch * direction
        var path = Path()
        path.move(to: CGPoint(x: center.x - tail, y: center.y))
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - radius),
            control1: CGPoint(x: center.x - tail * 0.42, y: center.y - radius * 0.20),
            control2: CGPoint(x: center.x - radius * 0.70 * direction, y: center.y - radius)
        )
        path.addCurve(
            to: CGPoint(x: center.x + radius * direction, y: center.y),
            control1: CGPoint(x: center.x + radius * 0.72 * direction, y: center.y - radius),
            control2: CGPoint(x: center.x + radius * direction, y: center.y - radius * 0.45)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + radius),
            control1: CGPoint(x: center.x + radius * direction, y: center.y + radius * 0.45),
            control2: CGPoint(x: center.x + radius * 0.72 * direction, y: center.y + radius)
        )
        path.addCurve(
            to: CGPoint(x: center.x - tail, y: center.y),
            control1: CGPoint(x: center.x - radius * 0.70 * direction, y: center.y + radius),
            control2: CGPoint(x: center.x - tail * 0.42, y: center.y + radius * 0.20)
        )
        path.closeSubpath()
        return path
    }

    /// 让液体上下分层以不同相位推进。各偏移围绕真实进度前沿摆动，
    /// 因此不会退化为一条平行竖线，也不会改变歌曲进度的平均位置。
    private func resolvedFrontX(
        front: CGFloat,
        fraction: CGFloat,
        phase: CGFloat,
        rippleAmplitude: CGFloat,
        diagonalAmplitude: CGFloat,
        diagonalDirection: CGFloat,
        profile: LiquidMotionProfile,
        scrubFlow: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let centeredY = (fraction - 0.5) * 2
        let envelope = sin(fraction * .pi)
        let diagonal = centeredY * diagonalAmplitude * diagonalDirection
        let broadCurl = sin(
            fraction * .pi * profile.primaryFrequency + phase * profile.primaryPhaseSpeed
        ) * rippleAmplitude * 0.72
        let fineCurl = sin(
            fraction * .pi * profile.secondaryFrequency - phase * profile.secondaryPhaseSpeed
        ) * rippleAmplitude * profile.fineCurlWeight * envelope
        let shoulder = sin(fraction * .pi) * rippleAmplitude * profile.shoulderWeight
        let inertialLag = -scrubFlow * (3.0 + 5.5 / profile.viscosity) * envelope
        let x = front + diagonal + broadCurl + fineCurl + shoulder + inertialLag
        return min(max(x, 0), width)
    }

    private var resolvedColors: [Color] {
        guard colors.count >= 2 else { return [Color.monoAccent, Color.monoAccent.opacity(0.72)] }
        return colors
    }

}

/// 每首歌获得稳定但不同的黏度、波速、液面频率和水珠行为。
/// 这些参数只改变材质性格，不参与真实播放进度计算。
private struct LiquidMotionProfile {
    let phaseOffset: CGFloat
    let waveSpeed: CGFloat
    let viscosity: CGFloat
    let baseRipple: CGFloat
    let surfaceTilt: CGFloat
    let tiltFrequency: CGFloat
    let primaryFrequency: CGFloat
    let secondaryFrequency: CGFloat
    let primaryPhaseSpeed: CGFloat
    let secondaryPhaseSpeed: CGFloat
    let fineCurlWeight: CGFloat
    let shoulderWeight: CGFloat
    let innerUpperSpeed: CGFloat
    let innerLowerSpeed: CGFloat
    let dropletThreshold: CGFloat
    let dropletScale: CGFloat
    let dropletLane: CGFloat
    let dropletSpeed: CGFloat
    let secondaryDroplet: Bool

    init(seed: CGFloat) {
        let a = Self.randomized(seed, salt: 0.17)
        let b = Self.randomized(seed, salt: 1.31)
        let c = Self.randomized(seed, salt: 2.73)
        let d = Self.randomized(seed, salt: 4.19)
        let e = Self.randomized(seed, salt: 6.07)

        phaseOffset = seed * .pi * 2
        waveSpeed = 0.66 + a * 0.64
        viscosity = 0.76 + b * 0.58
        baseRipple = 0.105 + c * 0.052
        surfaceTilt = d
        tiltFrequency = 0.22 + e * 0.20
        primaryFrequency = 1.65 + b * 1.05
        secondaryFrequency = 4.25 + d * 2.40
        primaryPhaseSpeed = 0.50 + a * 0.42
        secondaryPhaseSpeed = 0.82 + e * 0.62
        fineCurlWeight = 0.22 + c * 0.22
        shoulderWeight = 0.24 + b * 0.28
        innerUpperSpeed = 0.42 + d * 0.30
        innerLowerSpeed = 0.30 + a * 0.27
        dropletThreshold = 0.34 + e * 0.22
        dropletScale = c
        dropletLane = b
        dropletSpeed = 0.60 + d * 0.52
        secondaryDroplet = a > 0.46
    }

    private static func randomized(_ seed: CGFloat, salt: CGFloat) -> CGFloat {
        let value = sin((seed + salt) * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

private func liquidMotionSeed(for song: Song?) -> CGFloat {
    guard let song else { return 0.417 }
    let identity = "\(song.musicSource.rawValue)|\(song.id)|\(song.name)|\(song.artistName)"
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in identity.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return CGFloat(hash % 10_007) / 10_006
}

private func liquidCoverage(progress: Double, start: Double, end: Double) -> Double {
    guard end > start else { return progress >= end ? 1 : 0 }
    return min(max((progress - start) / (end - start), 0), 1)
}

/// 把悬浮栏真实进度前沿转换为某个子元素内部的覆盖比例。
/// 外层悬浮栏在内容两侧各保留 8pt，因此不能直接用 Tab 序号等分计算。
func floatingBarElementCoverage(
    progress: Double,
    contentWidth: CGFloat,
    elementMinX: CGFloat,
    elementWidth: CGFloat
) -> Double {
    guard contentWidth > 0, elementWidth > 0 else { return 0 }
    let horizontalInset: CGFloat = 8
    let shellWidth = contentWidth + horizontalInset * 2
    let frontX = CGFloat(min(max(progress, 0), 1)) * shellWidth
    let elementStartX = horizontalInset + elementMinX
    return Double(min(max((frontX - elementStartX) / elementWidth, 0), 1))
}

private func liquidSplitGradient(
    liquid: Color,
    panel: Color,
    coverage: Double
) -> LinearGradient {
    let value = min(max(coverage, 0), 1)
    if value <= 0.001 {
        return LinearGradient(colors: [panel, panel], startPoint: .leading, endPoint: .trailing)
    }
    if value >= 0.999 {
        return LinearGradient(colors: [liquid, liquid], startPoint: .leading, endPoint: .trailing)
    }
    let edge = CGFloat(value)
    let feather: CGFloat = 0.035
    return LinearGradient(
        stops: [
            .init(color: liquid, location: 0),
            .init(color: liquid, location: max(edge - feather, 0)),
            .init(color: panel, location: min(edge + feather, 1)),
            .init(color: panel, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct LiquidTabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .offset(y: configuration.isPressed ? 1.2 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
