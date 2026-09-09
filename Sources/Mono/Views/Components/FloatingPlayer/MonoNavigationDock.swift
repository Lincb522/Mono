import SwiftUI

/// The approved B/C docks share playback semantics and differ in navigation structure.
struct MonoNavigationDock: View {
    @Binding var currentTab: Tab
    let layout: MonoNavigationLayout
    @State private var showsQueue = false
    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            dock
                .frame(maxWidth: 560)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .environment(\.colorScheme, settings.activeColorScheme)
        .monoSheet(isPresented: $showsQueue, preset: .standard) {
            if PlayerManager.shared.isPlayingPodcast {
                PodcastPlaylistPopupView()
            } else {
                PlaylistPopupView()
            }
        }
    }

    @ViewBuilder
    private var dock: some View {
        if layout == .unified {
            VStack(spacing: 0) {
                player
                tabs
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
            }
            .modifier(MonoNavigationSurface(radius: 28))
        } else {
            VStack(spacing: 12) {
                player.modifier(MonoNavigationSurface(radius: 24))
                tabs
                    .padding(.horizontal, 6)
                    .modifier(MonoNavigationSurface(radius: 24))
                    .padding(.horizontal, 12)
            }
        }
    }

    private var player: some View {
        MonoNavigationPlayer(layout: layout, showsQueue: $showsQueue)
    }

    private var tabs: some View {
        MonoNavigationTabs(selection: $currentTab, layout: layout, isLocalMode: !onlineAccess.canUseOnlineFeatures)
    }
}

/// Only this adapter observes playback. Progress and lyric ticks stay in their existing readers.
struct MonoNavigationPlayer: View {
    let layout: MonoNavigationLayout
    var isInline = false
    @Binding var showsQueue: Bool
    @ObservedObject private var player = FloatingBarPlaybackModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var subtitleSize = 11.5

    private var hasSong: Bool {
        player.currentSong != nil && !player.isTabBarHidden
    }

    var body: some View {
        ZStack {
            MonoNavigationIdleRow(isInline: isInline) {
                NotificationCenter.default.post(name: .init("SwitchToHome"), object: nil)
            }
            .opacity(hasSong ? 0 : 1)
            .allowsHitTesting(!hasSong)
            .accessibilityHidden(hasSong)

            if let song = player.currentSong {
                MonoNavigationPlayerRow(
                    title: song.name,
                    layout: layout,
                    isInline: isInline,
                    isPlaying: player.isPlaying,
                    isLoading: player.isLoading,
                    openPlayer: openPlayer,
                    togglePlayback: { player.togglePlayPause() },
                    nextTrack: { player.next() },
                    openQueue: { showsQueue = true }
                ) {
                    CachedAsyncImage(url: song.coverUrl) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .overlay {
                                MonoIcon(icon: .musicNote, size: 18, color: .secondary, normalizesBitmapScale: true)
                            }
                    }
                    .aspectRatio(contentMode: .fill)
                } subtitle: {
                    FloatingBarLyricReader { line in
                        let text = line?.isEmpty == false ? (line ?? song.artistName) : song.artistName
                        if reduceMotion || dynamicTypeSize > .large {
                            Text(text)
                                .font(.system(size: subtitleSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            MarqueeText(text: text, font: .system(size: subtitleSize), color: .secondary, speed: 25)
                        }
                    }
                } progress: {
                    MonoNavigationProgress()
                }
                .swipeToSkip()
                .opacity(hasSong ? 1 : 0)
                .allowsHitTesting(hasSong)
                .accessibilityHidden(!hasSong)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hasSong)
    }

    private func openPlayer() {
        withAnimation(reduceMotion ? nil : MonoAnimation.playerTransition) {
            switch player.playSource {
            case .fm:
                NotificationCenter.default.post(name: .init("OpenFMPlayer"), object: nil)
            case let .podcast(radioId):
                NotificationCenter.default.post(name: .init("OpenRadioPlayer"), object: radioId)
            case .normal:
                NotificationCenter.default.post(name: .init("OpenNormalPlayer"), object: nil)
            }
        }
    }
}

struct MonoNavigationProgress: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FloatingBarProgressReader { progress, _, _ in
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.09))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(colorScheme == .dark ? MonoNavigationChrome.darkAccent : MonoNavigationChrome.accent)
                            .frame(width: geometry.size.width * progress)
                    }
            }
            .frame(height: 1.5)
            .accessibilityHidden(true)
        }
    }
}
