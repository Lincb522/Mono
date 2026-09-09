import SwiftUI

/// Shared layout for the three approved bars; playback and lyric observation stay in the adapter.
struct MonoNavigationPlayerRow<Artwork: View, Subtitle: View, Progress: View>: View {
    let title: String
    let layout: MonoNavigationLayout
    var isInline = false
    var coverSize: CGFloat = 38
    let isPlaying: Bool
    let isLoading: Bool
    let openPlayer: () -> Void
    let togglePlayback: () -> Void
    let nextTrack: () -> Void
    let openQueue: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let progress: () -> Progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0

    private var artworkSize: CGFloat { isInline ? 28 : coverSize }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if layout == .separated {
                    Button(action: togglePlayback) {
                        cover
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.black.opacity(0.32))
                                playbackGlyph.foregroundStyle(.white)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playbackLabel)
                    .accessibilityIdentifier("mono.player.playPause")
                }

                Button(action: openPlayer) {
                    HStack(spacing: 9) {
                        if layout != .separated { cover }
                        VStack(alignment: .leading, spacing: 2) {
                            if reduceMotion || dynamicTypeSize > .large {
                                Text(title)
                                    .font(.system(size: titleSize, weight: .semibold))
                                    .lineLimit(isInline ? 1 : 2)
                                    .multilineTextAlignment(.leading)
                            } else {
                                MarqueeText(text: title, font: .system(size: titleSize, weight: .semibold), color: .primary, speed: 25)
                            }
                            if !isInline { subtitle() }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityIdentifier("mono.player.open")
                .contextMenu {
                    Button(action: nextTrack) {
                        Label {
                            Text(String(localized: "playback_next_track"))
                        } icon: {
                            MonoIcon(icon: .next, size: 18, normalizesBitmapScale: true)
                        }
                    }
                    Button(action: openQueue) {
                        Label {
                            Text(String(localized: "player_queue"))
                        } icon: {
                            MonoIcon(icon: .list, size: 18, normalizesBitmapScale: true)
                        }
                    }
                }

                if layout != .separated {
                    Button(action: togglePlayback) { control { playbackGlyph } }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playbackLabel)
                        .accessibilityIdentifier("mono.player.playPause")
                }
                if !isInline {
                    Button(action: nextTrack) {
                        control { MonoIcon(icon: .next, size: 18, normalizesBitmapScale: true) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "playback_next_track"))
                    .accessibilityIdentifier("mono.player.next")

                    Button(action: openQueue) {
                        control { MonoIcon(icon: .list, size: 18, normalizesBitmapScale: true) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "player_queue"))
                    .accessibilityIdentifier("mono.player.queue")
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, isInline ? 6 : 10)
            .padding(.top, isInline ? 0 : 7)
            .padding(.bottom, isInline ? 0 : 5)

            if !isInline {
                progress()
                    .padding(.leading, layout == .native ? 16 : 62)
                    .padding(.trailing, 16)
                    .padding(.bottom, 7)
            }
        }
    }

    private var cover: some View {
        artwork()
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var playbackLabel: String {
        isPlaying ? String(localized: "暂停") : String(localized: "action_play")
    }

    @ViewBuilder
    private var playbackGlyph: some View {
        if isLoading {
            ProgressView().controlSize(.small)
        } else {
            MonoIcon(
                icon: isPlaying ? .pause : .play,
                size: 18,
                color: layout == .separated ? .white : .primary,
                normalizesBitmapScale: true,
                artworkContrastBackground: layout == .separated ? .black : nil
            )
        }
    }

    private func control<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 44, height: 44)
            .background {
                if layout == .unified {
                    Circle().fill(.primary.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
    }
}

struct MonoNavigationIdleRow: View {
    var isInline = false
    let openHome: () -> Void

    var body: some View {
        Button(action: openHome) {
            HStack(spacing: 10) {
                MonoIcon(icon: .musicNote, size: 18, normalizesBitmapScale: true)
                    .frame(width: 38, height: 38)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "not_playing"))
                        .font(.subheadline.weight(.semibold))
                    if !isInline {
                        Text(String(localized: "not_playing_subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MonoIcon(icon: .chevronRight, size: 12, color: .secondary, normalizesBitmapScale: true)
                    .frame(width: 24, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isInline ? 0 : 9)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .accessibilityIdentifier("mono.player.idle")
    }
}
