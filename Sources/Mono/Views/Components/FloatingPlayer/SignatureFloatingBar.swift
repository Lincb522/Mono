import SwiftUI

extension SignatureFloatingBarKind {
    init(style: FloatingBarStyle) {
        switch style {
        case .cassette: self = .cassette
        case .orbit: self = .orbit
        case .waveform: self = .waveform
        case .filmstrip: self = .filmstrip
        case .studioMeter: self = .studioMeter
        default: self = .vinylNeedle
        }
    }

    @MainActor var activeHeight: CGFloat {
        let inset: CGFloat = DeviceLayout.usesExpandedLayout ? 80 : 40
        return min(472, max(0, DeviceLayout.viewportWidth - inset)) * 180 / 472
    }
}

@MainActor
struct SignatureFloatingBar: View {
    @Binding var currentTab: Tab
    let kind: SignatureFloatingBarKind
    @ObservedObject private var player = FloatingBarPlaybackModel.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @State private var spectrum = SignatureSpectrumModel()
    @State private var showsQueue = false
    @State private var isVisible = false
    @State private var scrubProgress: Double?
    @State private var committedProgress: Double?
    @State private var seekRecoveryTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool { isVisible && player.isPlaying && !reduceMotion && scenePhase == .active }

    var body: some View {
        Group {
            if let song = player.currentSong {
                FloatingBarProgressReader(progressOverride: scrubProgress ?? committedProgress) { progress, time, duration in
                    FloatingBarLyricReader { lyric in
                        SignatureSpectrumReader(model: spectrum) { bands, levels in
                            SignatureBarFace(
                                kind: kind, title: song.name,
                                subtitle: lyric?.isEmpty == false ? (lyric ?? song.artistName) : song.artistName,
                                isPlaying: player.isPlaying, isLoading: player.isLoading,
                                animates: shouldAnimate, progress: progress, elapsed: time, duration: duration,
                                bands: bands, meterLevels: levels, selectedTab: currentTab.rawValue,
                                tabLabels: Tab.allCases.map { NSLocalizedString($0.titleKey(isLocalMode: !onlineAccess.canUseOnlineFeatures), comment: "") },
                                onOpen: openPlayer, onPlayPause: { player.togglePlayPause() },
                                onNext: { player.next() }, onQueue: { showsQueue = true },
                                onSelect: { index in
                                    guard let tab = Tab(rawValue: index), currentTab != tab else { return }
                                    HapticManager.shared.light(); currentTab = tab
                                },
                                onScrub: { value in
                                    guard duration.isFinite, duration > 0 else { return }
                                    seekRecoveryTask?.cancel(); committedProgress = nil; scrubProgress = value
                                },
                                onCommitScrub: { commitSeek(duration: duration) }
                            ) {
                                CachedAsyncImage(url: song.coverUrl?.sized(300)) {
                                    Rectangle().fill(.quaternary).overlay {
                                        MonoIcon(icon: .musicNote, size: 22, normalizesBitmapScale: true)
                                    }
                                }
                            } asset: { Image($0) } icon: { role, size, color, selected in
                                MonoIcon(icon: iconType(role, selected: selected), size: size, color: color, normalizesBitmapScale: true)
                            }
                        }
                    }
                }
                .swipeToSkip()
            } else {
                MonoNavigationIdleRow { currentTab = .home }
                    .padding(4)
                    .modifier(MonoNavigationSurface(radius: 16))
            }
        }
        .environment(\.colorScheme, settings.activeColorScheme)
        .onAppear { isVisible = true; updateSpectrum() }
        .onDisappear { isVisible = false; spectrum.stop(); seekRecoveryTask?.cancel() }
        .onChange(of: shouldAnimate) { _, _ in updateSpectrum() }
        .onChange(of: kind) { _, _ in spectrum.stop(); updateSpectrum() }
        .onChange(of: player.currentSong?.id) { _, _ in
            scrubProgress = nil; committedProgress = nil; seekRecoveryTask?.cancel()
            spectrum.stop(); updateSpectrum()
        }
        .onReceive(PlaybackTimePublisher.shared.$currentTime.removeDuplicates()) { time in
            let duration = PlaybackTimePublisher.shared.duration
            if let committedProgress, duration > 0, abs(time / duration - committedProgress) < 0.014 {
                self.committedProgress = nil; seekRecoveryTask?.cancel()
            }
        }
        .monoSheet(isPresented: $showsQueue, preset: .standard) {
            if player.isPlayingPodcast { PodcastPlaylistPopupView() } else { PlaylistPopupView() }
        }
    }

    private func iconType(_ role: SignatureFaceIcon, selected: Bool) -> MonoIcon.IconType {
        switch role {
        case .home: return Tab.home.navigationIcon(isLocalMode: !onlineAccess.canUseOnlineFeatures, selected: selected)
        case .podcast: return Tab.podcast.navigationIcon(isLocalMode: !onlineAccess.canUseOnlineFeatures, selected: selected)
        case .library: return Tab.library.navigationIcon(isLocalMode: !onlineAccess.canUseOnlineFeatures, selected: selected)
        case .profile: return Tab.profile.navigationIcon(isLocalMode: !onlineAccess.canUseOnlineFeatures, selected: selected)
        case .play: return .play
        case .pause: return .pause
        case .next: return .next
        case .queue: return .list
        }
    }

    private func commitSeek(duration: Double) {
        guard let scrubProgress, duration.isFinite, duration > 0 else { return }
        committedProgress = scrubProgress
        player.seek(to: scrubProgress * duration)
        HapticManager.shared.soft()
        self.scrubProgress = nil
        seekRecoveryTask?.cancel()
        seekRecoveryTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
            committedProgress = nil
        }
    }

    private func updateSpectrum() {
        if shouldAnimate && (kind == .waveform || kind == .studioMeter) { spectrum.start(kind: kind) }
        else { spectrum.stop() }
    }

    private func openPlayer() {
        withAnimation(reduceMotion ? nil : MonoAnimation.playerTransition) {
            switch player.playSource {
            case .fm: NotificationCenter.default.post(name: .init("OpenFMPlayer"), object: nil)
            case let .podcast(radioID): NotificationCenter.default.post(name: .init("OpenRadioPlayer"), object: radioID)
            case .normal: NotificationCenter.default.post(name: .init("OpenNormalPlayer"), object: nil)
            }
        }
    }
}

private struct SignatureSpectrumReader<Content: View>: View {
    @ObservedObject var model: SignatureSpectrumModel
    @ViewBuilder var content: ([Double], [Double]) -> Content
    var body: some View { content(model.bands, model.meterLevels) }
}

@MainActor
private final class SignatureSpectrumModel: ObservableObject {
    @Published private(set) var bands: [Double] = []
    @Published private(set) var meterLevels: [Double] = [0, 0]
    private var observerToken: UUID?
    private var pcmToken: UUID?
    private var generation = 0

    func start(kind: SignatureFloatingBarKind) {
        guard observerToken == nil, pcmToken == nil else { return }
        let currentGeneration = generation
        if kind == .studioMeter {
            pcmToken = PlayerManager.shared.spectrumAnalyzer.addPCMAnalysisObserver(minimumInterval: 1.0 / 20.0) { [weak self] left, right, _ in
                let levels = [SignatureAudioLevels.meter(left), SignatureAudioLevels.meter(right ?? left)]
                Task { @MainActor [weak self] in
                    guard let self, generation == currentGeneration else { return }
                    meterLevels = zip(meterLevels, levels).map { previous, next in
                        previous + (next - previous) * (next > previous ? 0.56 : 0.18)
                    }
                }
            }
        } else {
            observerToken = PlayerManager.shared.spectrumAnalyzer.addAnalysisObserver(minimumInterval: 1.0 / 20.0) { [weak self] magnitudes, _, _ in
                let values = SignatureAudioLevels.waveform(magnitudes, count: 64)
                Task { @MainActor [weak self] in
                    guard let self, generation == currentGeneration else { return }
                    if bands.count == values.count {
                        bands = zip(bands, values).map { previous, next in previous + (next - previous) * (next > previous ? 0.58 : 0.22) }
                    } else { bands = values }
                }
            }
        }
    }

    func stop() {
        generation += 1
        if let observerToken { PlayerManager.shared.spectrumAnalyzer.removeAnalysisObserver(observerToken) }
        if let pcmToken { PlayerManager.shared.spectrumAnalyzer.removePCMAnalysisObserver(pcmToken) }
        observerToken = nil; pcmToken = nil; meterLevels = [0, 0]
    }
}
