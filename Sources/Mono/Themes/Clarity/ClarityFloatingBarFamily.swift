import SwiftUI

/// 通透主题的四套导航不是同一底栏换圆角，而是四种不同的信息结构：
/// 统一 = 播放行与等宽导航同舱；经典 = 播放条悬在贴底光轨之上；
/// 极简 = 单条低干扰图标光轨；悬浮球 = 可展开的角落控制器。
struct ClarityFloatingBarFamily: View {
    @Binding var currentTab: Tab
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        switch settings.floatingBarStyle {
        case .unified:
            ClarityGalleryDeck(currentTab: $currentTab)
        case .classic:
            ClarityHorizonRail(currentTab: $currentTab)
        case .minimal:
            ClarityLensStrip(currentTab: $currentTab)
        case .floatingBall:
            ClarityCornerBloom(currentTab: $currentTab)
        case .flux:
            VStack {
                Spacer(minLength: 0)
                FluxFloatingBar(currentTab: $currentTab).frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 8)
            }
        case .liquid:
            VStack {
                Spacer(minLength: 0)
                LiquidFloatingBar(currentTab: $currentTab).frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 8)
            }
        case .vinylNeedle, .cassette, .orbit, .waveform, .filmstrip, .studioMeter:
            VStack {
                Spacer(minLength: 0)
                SignatureFloatingBar(currentTab: $currentTab, kind: SignatureFloatingBarKind(style: settings.floatingBarStyle))
                    .frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Unified · Gallery Deck

/// 播放信息在上、四个等宽入口在下，单手可直接触达且不再把导航塞到侧边。
private struct ClarityGalleryDeck: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab
    private let playback = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @State private var playSource = FloatingBarPlaybackModel.shared.playSource
    @State private var showsQueue = false
    @Namespace private var selection

    var body: some View {
        let _ = colorRevision

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 7) {
                playbackRow

                Rectangle()
                    .fill(ClarityStyle.line)
                    .frame(height: 1)
                    .padding(.horizontal, 5)

                HStack(spacing: 5) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        let selected = currentTab == tab
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                currentTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                MonoIcon(
                                    icon: tab.icon,
                                    size: 14,
                                    color: selected ? ClarityStyle.onSelection : ClarityStyle.inkFaint,
                                    lineWidth: selected ? 1.8 : 1.35,
                                    artworkContrastBackground: selected ? ClarityStyle.selection : nil
                                )
                                Text(clarityTabTitle(tab))
                                    .font(ClarityStyle.body(8.5, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.74)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background {
                                if selected {
                                    ClaritySelectionLens(
                                        shape: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    )
                                    .matchedGeometryEffect(id: "clarity-gallery-tab", in: selection)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(clarityTabTitle(tab))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(9)
            .background {
                ClarityPrismaticDockSurface(
                    shape: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
            }
            .frame(maxWidth: 690)
            .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 30 : 13)
            .padding(.bottom, 6)
        }
        .monoSheet(isPresented: $showsQueue, preset: .standard) {
            playSource.isPodcast ? AnyView(PodcastPlaylistPopupView()) : AnyView(PlaylistPopupView())
        }
        .onReceive(playback.$currentSong.removeDuplicates()) { song in
            currentSong = song
        }
        .onReceive(playback.$isPlaying.removeDuplicates()) { playing in
            isPlaying = playing
        }
        .onReceive(playback.$playSource.removeDuplicates()) { source in
            playSource = source
        }
    }

    @ViewBuilder
    private var playbackRow: some View {
        if let song = currentSong {
            HStack(spacing: 10) {
                Button { clarityOpenPlayer(playback) } label: {
                    ClarityArtwork(url: song.coverUrl, size: 52, radius: 17)
                }
                .buttonStyle(ClarityPressStyle())

                Button { clarityOpenPlayer(playback) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        MarqueeText(
                            text: song.name,
                            font: .system(size: 13.5, weight: .semibold),
                            color: ClarityStyle.ink
                        )
                        FloatingBarLyricReader { lyricLineText in
                            Text(lyricLineText ?? song.artistName)
                                .font(ClarityStyle.body(9.5, weight: .medium))
                                .foregroundStyle(ClarityStyle.inkSoft)
                                .lineLimit(1)
                        }
                        ClarityLinearProgress()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button { showsQueue = true } label: {
                    MonoIcon(icon: .list, size: 13, color: ClarityStyle.inkSoft, lineWidth: 1.45)
                        .frame(width: 36, height: 38)
                }
                .frame(width: 44, height: 44)
                .buttonStyle(ClarityPressStyle())

                Button { playback.togglePlayPause() } label: {
                    MonoIcon(
                        icon: isPlaying ? .pause : .play,
                        size: 14,
                        color: ClarityStyle.onSelection,
                        lineWidth: 1.8
                    )
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(ClarityStyle.selection))
                }
                .frame(width: 44, height: 44)
                .buttonStyle(ClarityPressStyle())
            }
            .padding(.horizontal, 3)
            .swipeToSkip()
        } else {
            HStack(spacing: 10) {
                MonoIcon(icon: currentTab.icon, size: 18, color: ClarityStyle.accent, lineWidth: 1.7)
                    .frame(width: 42, height: 42)
                    .background(ClarityMembrane(shape: Circle(), strength: .quiet, tint: ClarityStyle.accent))
                Text(clarityTabTitle(currentTab))
                    .font(ClarityStyle.title(15, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 5)
        }
    }
}

// MARK: - Classic · Horizon Rail

/// 经典模式重新解释为贴底光轨：播放信息独立悬浮，导航在屏幕边缘形成稳定基线。
private struct ClarityHorizonRail: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab
    private let playback = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @State private var playSource = FloatingBarPlaybackModel.shared.playSource
    @State private var showsQueue = false
    @Namespace private var selection

    var body: some View {
        let _ = colorRevision

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let song = currentSong {
                HStack(spacing: 10) {
                    Button { clarityOpenPlayer(playback) } label: {
                        ClarityArtwork(url: song.coverUrl, size: 42, radius: 13)
                    }
                    .buttonStyle(ClarityPressStyle())

                    Button { clarityOpenPlayer(playback) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.name)
                                .font(ClarityStyle.body(12.5, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                            FloatingBarLyricReader { lyricLineText in
                                Text(lyricLineText ?? song.artistName)
                                    .font(ClarityStyle.body(9.5))
                                    .foregroundStyle(ClarityStyle.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    ClarityLinearProgress()
                        .frame(width: DeviceLayout.usesExpandedLayout ? 120 : 58)

                    Button { showsQueue = true } label: {
                        MonoIcon(icon: .list, size: 14, color: ClarityStyle.inkSoft, lineWidth: 1.45)
                            .frame(width: 34, height: 38)
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())

                    Button { playback.togglePlayPause() } label: {
                        MonoIcon(
                            icon: isPlaying ? .pause : .play,
                            size: 14,
                            color: ClarityStyle.onSelection,
                            lineWidth: 1.8
                        )
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(ClarityStyle.selection))
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ClarityPrismaticDockSurface(shape: Capsule(style: .continuous)))
                .frame(maxWidth: 620)
                .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 34 : 15)
                .padding(.bottom, 8)
                .swipeToSkip()
            }

            HStack(spacing: 7) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let selected = currentTab == tab
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            currentTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            MonoIcon(
                                icon: tab.icon,
                                size: selected ? 16 : 15,
                                color: selected ? ClarityStyle.onSelection : ClarityStyle.inkFaint,
                                lineWidth: selected ? 1.85 : 1.3,
                                artworkContrastBackground: selected ? ClarityStyle.selection : nil
                            )
                            if selected {
                                Text(clarityTabTitle(tab))
                                    .font(ClarityStyle.body(10, weight: .semibold))
                                    .foregroundStyle(ClarityStyle.onSelection)
                                    .lineLimit(1)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .frame(width: selected ? 112 : 52, height: 44)
                        .background {
                            if selected {
                                ClaritySelectionLens(shape: Capsule(style: .continuous))
                                    .matchedGeometryEffect(id: "clarity-horizon-tab", in: selection)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clarityTabTitle(tab))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 7)
            .padding(.bottom, max(7, min(DeviceLayout.safeAreaBottom * 0.35, 14)))
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(ClarityStyle.membraneStrong.opacity(0.72)))
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.9), ClarityStyle.accent.opacity(0.16), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 20, y: -8)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .monoSheet(isPresented: $showsQueue, preset: .standard) {
            playSource.isPodcast ? AnyView(PodcastPlaylistPopupView()) : AnyView(PlaylistPopupView())
        }
        .onReceive(playback.$currentSong.removeDuplicates()) { song in
            currentSong = song
        }
        .onReceive(playback.$isPlaying.removeDuplicates()) { playing in
            isPlaying = playing
        }
        .onReceive(playback.$playSource.removeDuplicates()) { source in
            playSource = source
        }
    }
}

// MARK: - Minimal · Lens Strip

/// 极简模式只保留一条低矮光轨，四个入口保持相同命中宽度，选中项以圆形镜片标记。
private struct ClarityLensStrip: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab
    private let playback = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @Namespace private var selection

    var body: some View {
        let _ = colorRevision

        VStack(spacing: 7) {
            Spacer(minLength: 0)

            if let song = currentSong {
                HStack(spacing: 9) {
                    Button { clarityOpenPlayer(playback) } label: {
                        ClarityArtwork(url: song.coverUrl, size: 38, radius: 12)
                    }
                    .buttonStyle(ClarityPressStyle())

                    Button { clarityOpenPlayer(playback) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.name)
                                .font(ClarityStyle.body(11.5, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                            ClarityLinearProgress()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button { playback.togglePlayPause() } label: {
                        MonoIcon(
                            icon: isPlaying ? .pause : .play,
                            size: 13,
                            color: ClarityStyle.onSelection,
                            lineWidth: 1.75
                        )
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ClarityStyle.selection))
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ClarityPrismaticDockSurface(shape: Capsule(style: .continuous)))
                .frame(maxWidth: 320)
                .swipeToSkip()
            }

            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let selected = currentTab == tab
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                            currentTab = tab
                        }
                    } label: {
                        ZStack {
                            if selected {
                                ClaritySelectionLens(shape: Circle())
                                    .frame(width: 38, height: 38)
                                    .matchedGeometryEffect(id: "clarity-minimal-tab", in: selection)
                            }

                            MonoIcon(
                                icon: tab.icon,
                                size: selected ? 16 : 15,
                                color: selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft,
                                lineWidth: selected ? 1.85 : 1.35,
                                artworkContrastBackground: selected ? ClarityStyle.selection : nil
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clarityTabTitle(tab))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(ClarityMembrane(shape: Capsule(style: .continuous), strength: .regular))
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: 690)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 34 : 15)
        .padding(.bottom, 9)
        .onReceive(playback.$currentSong.removeDuplicates()) { song in
            currentSong = song
        }
        .onReceive(playback.$isPlaying.removeDuplicates()) { playing in
            isPlaying = playing
        }
    }
}

// MARK: - Floating Ball · Corner Bloom

/// 悬浮球位于右下角；导航按需从角落展开，收起时只保留当前页面与唱片球。
private struct ClarityCornerBloom: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @Binding var currentTab: Tab
    private let playback = FloatingBarPlaybackModel.shared
    @State private var currentSong = FloatingBarPlaybackModel.shared.currentSong
    @State private var isPlaying = FloatingBarPlaybackModel.shared.isPlaying
    @State private var playSource = FloatingBarPlaybackModel.shared.playSource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var showsQueue = false
    @Namespace private var selection

    var body: some View {
        let _ = colorRevision

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 0)

                if isExpanded {
                    expandedPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Button { setExpanded(true) } label: {
                        HStack(spacing: 7) {
                            MonoIcon(icon: currentTab.icon, size: 14, color: ClarityStyle.ink, lineWidth: 1.6)
                            Text(clarityTabTitle(currentTab))
                                .font(ClarityStyle.body(10, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(ClarityPrismaticDockSurface(shape: Capsule(style: .continuous)))
                    }
                    .buttonStyle(ClarityPressStyle())
                    .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
                }

                VStack(spacing: 7) {
                    Button { setExpanded(!isExpanded) } label: {
                        MonoIcon(
                            icon: isExpanded ? .close : .layers,
                            size: 13,
                            color: ClarityStyle.ink,
                            lineWidth: 1.65
                        )
                        .frame(width: 42, height: 42)
                        .background(ClarityMembrane(shape: Circle(), strength: .strong))
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())

                    Button { clarityOpenPlayer(playback) } label: {
                        ZStack {
                            Circle().stroke(ClarityStyle.line, lineWidth: 3)
                            ClarityCircularProgress()

                            ClarityArtwork(
                                url: currentSong?.coverUrl,
                                size: 53,
                                radius: 27
                            )
                            .clipShape(Circle())
                            .padding(5)
                        }
                        .frame(width: 67, height: 67)
                        .background(ClarityMembrane(shape: Circle(), strength: .strong))
                        .shadow(color: Color.black.opacity(0.11), radius: 16, y: 9)
                    }
                    .buttonStyle(ClarityPressStyle())
                    .accessibilityLabel(String(localized: "now_playing"))
                }
            }
            .frame(maxWidth: 690)
            .padding(.horizontal, DeviceLayout.usesExpandedLayout ? 34 : 14)
            .padding(.bottom, 8)
        }
        .onChange(of: currentTab) { _, _ in
            if isExpanded { setExpanded(false) }
        }
        .monoSheet(isPresented: $showsQueue, preset: .standard) {
            playSource.isPodcast ? AnyView(PodcastPlaylistPopupView()) : AnyView(PlaylistPopupView())
        }
        .onReceive(playback.$currentSong.removeDuplicates()) { song in
            currentSong = song
        }
        .onReceive(playback.$isPlaying.removeDuplicates()) { playing in
            isPlaying = playing
        }
        .onReceive(playback.$playSource.removeDuplicates()) { source in
            playSource = source
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 8) {
            if let song = currentSong {
                HStack(spacing: 8) {
                    Button { clarityOpenPlayer(playback) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name)
                                .font(ClarityStyle.body(11.5, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                            FloatingBarLyricReader { lyricLineText in
                                Text(lyricLineText ?? song.artistName)
                                    .font(ClarityStyle.body(9))
                                    .foregroundStyle(ClarityStyle.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button { showsQueue = true } label: {
                        MonoIcon(icon: .list, size: 12, color: ClarityStyle.inkSoft, lineWidth: 1.4)
                            .frame(width: 32, height: 32)
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())

                    Button { playback.togglePlayPause() } label: {
                        MonoIcon(
                            icon: isPlaying ? .pause : .play,
                            size: 12,
                            color: ClarityStyle.onSelection,
                            lineWidth: 1.8
                        )
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(ClarityStyle.selection))
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(ClarityPressStyle())
                }

                ClarityLinearProgress()
            }

            HStack(spacing: 5) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let selected = currentTab == tab
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            currentTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            MonoIcon(
                                icon: tab.icon,
                                size: 14,
                                color: selected ? ClarityStyle.onSelection : ClarityStyle.inkFaint,
                                lineWidth: selected ? 1.8 : 1.3,
                                artworkContrastBackground: selected ? ClarityStyle.selection : nil
                            )
                            Text(clarityTabTitle(tab))
                                .font(ClarityStyle.body(8, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if selected {
                                ClaritySelectionLens(shape: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .matchedGeometryEffect(id: "clarity-bloom-tab", in: selection)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clarityTabTitle(tab))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(9)
        .frame(width: DeviceLayout.usesExpandedLayout ? 340 : 282)
        .background {
            ClarityPrismaticDockSurface(
                shape: RoundedRectangle(cornerRadius: 27, style: .continuous)
            )
        }
        .swipeToSkip()
    }

    private func setExpanded(_ expanded: Bool) {
        if reduceMotion {
            isExpanded = expanded
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                isExpanded = expanded
            }
        }
    }
}

// MARK: - Shared optical primitives

private struct ClarityPrismaticDockSurface<S: InsettableShape>: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    let shape: S

    var body: some View {
        let _ = colorRevision

        ClarityMembrane(shape: shape, strength: .strong)
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                ClarityStyle.accent.opacity(0.055),
                                ClarityStyle.accent.opacity(0.025),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.46), lineWidth: 0.65)
            }
    }
}

private struct ClarityLinearProgress: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @ObservedObject private var time = PlaybackTimePublisher.shared

    var body: some View {
        let _ = colorRevision

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ClarityStyle.line)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ClarityStyle.accent.opacity(0.72), ClarityStyle.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, proxy.size.width * clarityPlaybackProgress(time)))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// The clock owns only this 67pt vector layer. Progress publications no longer
/// rebuild the corner controller, artwork, buttons or membrane surface.
private struct ClarityCircularProgress: View {
    @Environment(\.floatingBarColorRevision) private var colorRevision
    @ObservedObject private var time = PlaybackTimePublisher.shared

    var body: some View {
        let _ = colorRevision

        Circle()
            .trim(from: 0, to: clarityPlaybackProgress(time))
            .stroke(ClarityStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)
    }
}

@MainActor
private func clarityPlaybackProgress(_ time: PlaybackTimePublisher) -> CGFloat {
    guard time.duration > 0 else { return 0 }
    return CGFloat(min(max(time.currentTime / time.duration, 0), 1))
}

private func clarityTabTitle(_ tab: Tab) -> String {
    String(localized: String.LocalizationValue(tab.titleKey()))
}

@MainActor
private func clarityOpenPlayer(_ playback: FloatingBarPlaybackModel) {
    guard playback.currentSong != nil else { return }
    switch playback.playSource {
    case .fm:
        NotificationCenter.default.post(name: .init("OpenFMPlayer"), object: nil)
    case let .podcast(id):
        NotificationCenter.default.post(name: .init("OpenRadioPlayer"), object: id)
    case .normal:
        NotificationCenter.default.post(name: .init("OpenNormalPlayer"), object: nil)
    }
}
