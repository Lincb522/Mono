import SwiftUI

enum SignatureFloatingBarKind: String, CaseIterable {
    case vinylNeedle, cassette, orbit, waveform, filmstrip, studioMeter
}

enum SignatureFaceIcon {
    case home, podcast, library, profile, play, pause, next, queue
}

/// Presentation shared with the render harness; playback ownership stays in the app adapter.
struct SignatureBarFace<Cover: View, Icon: View>: View {
    let kind: SignatureFloatingBarKind
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let isLoading: Bool
    let animates: Bool
    let progress: Double
    let elapsed: Double
    let duration: Double
    let bands: [Double]
    let meterLevels: [Double]
    let selectedTab: Int
    let tabLabels: [String]
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onQueue: () -> Void
    let onSelect: (Int) -> Void
    let onScrub: (Double) -> Void
    let onCommitScrub: () -> Void
    @ViewBuilder let cover: () -> Cover
    let asset: (String) -> Image
    @ViewBuilder let icon: (SignatureFaceIcon, CGFloat, Color, Bool) -> Icon
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var ink: Color { scheme == .dark ? Color(white: 0.96) : Color(white: 0.08) }
    private var muted: Color { scheme == .dark ? Color(white: 0.73) : Color(white: 0.37) }
    private var accent: Color { Color(red: 0.95, green: 0.29, blue: 0.28) }

    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize {
                accessibleFace
            } else {
                GeometryReader { geometry in
                    let s = geometry.size.width / 472
                    VStack(spacing: 0) {
                        player(scale: s)
                            .frame(height: 116 * s)
                        Rectangle().fill(ink.opacity(scheme == .dark ? 0.20 : 0.15)).frame(height: 0.6)
                        navigation(scale: s)
                            .frame(maxHeight: .infinity)
                    }
                }
                .aspectRatio(472.0 / 180.0, contentMode: .fit)
            }
        }
        .foregroundStyle(ink)
        .background { SignatureMetalPanel(isDark: scheme == .dark) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.36) : Color.black.opacity(0.18), lineWidth: 0.6)
                .padding(0.5)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.10), radius: 7, x: 0, y: 4)
        .frame(maxWidth: 472)
    }

    @ViewBuilder
    private func player(scale s: CGFloat) -> some View {
        switch kind {
        case .vinylNeedle, .orbit:
            HStack(spacing: 10 * s) {
                artwork(scale: s).frame(width: 130 * s, height: 110 * s)
                VStack(alignment: .leading, spacing: 9 * s) {
                    metadata(scale: s)
                    progressLine(scale: s)
                    timePair(scale: s)
                }
                .frame(maxWidth: .infinity)
                controls(scale: s)
            }
            .padding(.leading, 13 * s).padding(.trailing, 12 * s)
        case .cassette:
            HStack(alignment: .top, spacing: 16 * s) {
                artwork(scale: s).frame(width: 70 * s, height: 70 * s)
                    .padding(.top, 17 * s)
                VStack(alignment: .leading, spacing: 6 * s) {
                    HStack(alignment: .bottom, spacing: 4) {
                        metadata(scale: s)
                        Spacer(minLength: 0)
                        Text("\(time(elapsed)) / \(time(duration))")
                            .font(.system(size: 12 * s)).monospacedDigit().foregroundStyle(muted)
                    }
                    .padding(.trailing, 3 * s)
                    seekable {
                        SignatureCassetteArt(progress: progress, animates: animates, asset: asset)
                    }.frame(height: 40 * s)
                }
                .padding(.top, 19 * s)
                .frame(maxWidth: .infinity)
                controls(scale: s).padding(.top, 24 * s)
            }
            .padding(.horizontal, 20 * s)
        case .waveform:
            VStack(spacing: 3 * s) {
                HStack(spacing: 18 * s) {
                    artwork(scale: s).frame(width: 70 * s, height: 66 * s)
                    metadata(scale: s).frame(maxWidth: .infinity, alignment: .leading)
                    controls(scale: s)
                }
                HStack(spacing: 12 * s) {
                    timestamp(elapsed, scale: s)
                    seekable {
                        SignatureWaveform(bands: bands, progress: progress, accent: accent, ink: ink)
                    }.frame(height: 30 * s)
                    timestamp(duration, scale: s)
                }
            }
            .padding(.horizontal, 20 * s)
        case .filmstrip:
            HStack(spacing: 18 * s) {
                artwork(scale: s).frame(width: 112 * s, height: 96 * s)
                VStack(spacing: 10 * s) {
                    HStack(spacing: 6 * s) {
                        metadata(scale: s).frame(maxWidth: .infinity, alignment: .leading)
                        controls(scale: s)
                    }
                    HStack(spacing: 10 * s) {
                        timestamp(elapsed, scale: s)
                        seekable { SignatureFilmRuler(progress: progress, accent: accent, ink: ink) }
                            .frame(height: 23 * s)
                        timestamp(duration, scale: s)
                    }
                }
            }
            .padding(.horizontal, 16 * s)
        case .studioMeter:
            VStack(spacing: 3 * s) {
                HStack(spacing: 15 * s) {
                    artwork(scale: s).frame(width: 58 * s, height: 58 * s)
                    metadata(scale: s).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12 * s) {
                        meter(channel: 0, scale: s)
                        meter(channel: 1, scale: s)
                    }
                }
                HStack(spacing: 14 * s) {
                    timestamp(elapsed, scale: s)
                    progressLine(scale: s)
                    timestamp(duration, scale: s)
                    controls(scale: s)
                }
            }
            .padding(.horizontal, 19 * s)
        }
    }

    private func metadata(scale s: CGFloat) -> some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(title).font(.system(size: 17 * s, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 14 * s)).foregroundStyle(muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42 * s, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ", " + subtitle)
    }

    private func artwork(scale s: CGFloat) -> some View {
        Button(action: onOpen) {
            SignatureArtworkFace(kind: kind, progress: progress, animates: animates, accent: accent, cover: cover, asset: asset)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private func controls(scale s: CGFloat) -> some View {
        HStack(spacing: 1 * s) {
            Button(action: onPlayPause) {
                ZStack {
                    Circle().fill(ink.opacity(scheme == .dark ? 0.035 : 0.025))
                    Circle().strokeBorder(ink.opacity(0.20), lineWidth: 0.6)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        icon(isPlaying ? .pause : .play, 20 * s, ink, false)
                    }
                }
                .frame(width: 47 * s, height: 47 * s)
                .frame(width: max(44, 51 * s), height: max(44, 51 * s))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: isPlaying ? "暂停" : "action_play"))
            Button(action: onNext) {
                icon(.next, 20 * s, ink, false)
                    .frame(width: max(44, 49 * s), height: max(44, 49 * s)).contentShape(Rectangle())
            }.accessibilityLabel(String(localized: "playback_next_track"))
            Button(action: onQueue) {
                icon(.queue, 22 * s, ink, false)
                    .frame(width: max(44, 49 * s), height: max(44, 49 * s)).contentShape(Rectangle())
            }.accessibilityLabel(String(localized: "player_queue"))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func navigation(scale s: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { index in
                let selected = selectedTab == index
                let role: SignatureFaceIcon = [.home, .podcast, .library, .profile][index]
                Button { onSelect(index) } label: {
                    VStack(spacing: 4 * s) {
                        icon(role, 23 * s, selected ? accent : ink, selected)
                            .frame(width: 28 * s, height: 27 * s)
                        Text(tabLabels[index])
                            .font(.system(size: 14 * s))
                            .foregroundStyle(selected ? accent : ink)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("signature.tab.\(index)")
            }
        }
        .padding(.horizontal, 8 * s)
    }

    private func progressLine(scale s: CGFloat) -> some View {
        seekable {
            GeometryReader { geometry in
                Capsule().fill(ink.opacity(0.19))
                    .overlay(alignment: .leading) {
                        Capsule().fill(scheme == .dark ? accent : ink.opacity(0.58))
                            .frame(width: geometry.size.width * progress)
                    }
            }.frame(height: 2.6 * s)
        }
    }

    private func timePair(scale s: CGFloat) -> some View {
        HStack { timestamp(elapsed, scale: s); Spacer(minLength: 0); timestamp(duration, scale: s) }
    }

    private func timestamp(_ seconds: Double, scale s: CGFloat) -> some View {
        Text(time(seconds)).font(.system(size: 12 * s)).monospacedDigit().foregroundStyle(muted).fixedSize()
    }

    private func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func seekable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().overlay {
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            guard duration > 0, geometry.size.width > 0 else { return }
                            onScrub(min(max(value.location.x / geometry.size.width, 0), 1))
                        }
                        .onEnded { _ in onCommitScrub() })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "playback_progress"))
        .accessibilityValue(time(elapsed))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            onScrub(min(max(progress + (direction == .increment ? 10 : -10) / duration, 0), 1))
            onCommitScrub()
        }
    }

    private func meter(channel: Int, scale s: CGFloat) -> some View {
        SignatureMeterFace(level: meterLevels.indices.contains(channel) ? meterLevels[channel] : 0, channel: channel, asset: asset)
            .frame(width: 108 * s, height: 57 * s)
            .accessibilityHidden(true)
    }

    private var accessibleFace: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artwork(scale: 1).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.subheadline).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            controls(scale: 1)
            HStack { timestamp(elapsed, scale: 1); progressLine(scale: 1); timestamp(duration, scale: 1) }
            navigation(scale: 1)
        }.padding(16)
    }
}

private struct SignatureMetalPanel: View {
    let isDark: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: isDark
                ? [Color(white: 0.20), Color(white: 0.135), Color(white: 0.11), Color(white: 0.15)]
                : [Color(red: 0.98, green: 0.975, blue: 0.965), Color(red: 0.94, green: 0.935, blue: 0.925)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(isDark ? 0.22 : 0.72), lineWidth: 1.4).padding(1.2)
        }
    }
}
