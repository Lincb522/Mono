// 听歌识曲 - 使用 ShazamKit 识别音乐

import SwiftUI
import ShazamKit
import AVFoundation

// MARK: - AudioMatchViewModel

@MainActor
final class AudioMatchViewModel: ObservableObject {
    enum MatchState: Equatable {
        case idle
        case listening
        case matching
        case found
        case notFound
        case error(String)

        static func == (lhs: MatchState, rhs: MatchState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.listening, .listening), (.matching, .matching),
                 (.found, .found), (.notFound, .notFound):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: MatchState = .idle
    @Published var matchedSongs: [Song] = []
    @Published var shazamTitle: String?
    @Published var shazamArtist: String?
    @Published var shazamArtworkURL: URL?
    let progress = AudioMatchListeningProgress()

    private var session: SHSession?
    private var audioEngine: AVAudioEngine?
    private var audioSessionActivationTask: Task<Void, Never>?
    private var listenTimer: Timer?
    private var listenDuration: TimeInterval = 0
    private let maxListenDuration: TimeInterval = 15
    private var shazamDelegate: ShazamDelegate?

    func startListening() {
        let handlePermission: @Sendable (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.beginShazamSession()
                } else {
                    self.state = .error(NSLocalizedString("audio_match_mic_denied", comment: ""))
                }
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handlePermission)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handlePermission)
        }
    }

    func stopListening() {
        stopAudioEngine()
        listenTimer?.invalidate()
        listenTimer = nil
        listenDuration = 0
        progress.value = 0
        if state == .listening {
            state = .idle
        }
    }

    func reset() {
        stopListening()
        state = .idle
        matchedSongs = []
        shazamTitle = nil
        shazamArtist = nil
        shazamArtworkURL = nil
    }

    // MARK: - ShazamKit

    private func beginShazamSession() {
        state = .listening
        listenDuration = 0
        progress.value = 0

        session = SHSession()
        shazamDelegate = ShazamDelegate(viewModel: self)
        session?.delegate = shazamDelegate

        audioSessionActivationTask?.cancel()
        audioSessionActivationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let activated = await PlayerManager.shared.activateAudioSessionForRecording(
                reason: "Shazam listening"
            )
            guard !Task.isCancelled, self.state == .listening else {
                PlayerManager.shared.reapplyAudioSessionOptions(reason: "Shazam activation cancelled")
                return
            }
            guard activated else {
                self.state = .error(NSLocalizedString("audio_match_error", comment: ""))
                return
            }

            do {
                let audioEngine = AVAudioEngine()
                self.audioEngine = audioEngine

                let inputNode = audioEngine.inputNode
                inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
                    self?.session?.matchStreamingBuffer(buffer, at: nil)
                }

                try audioEngine.start()

                self.listenTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.state == .listening else { return }
                        self.listenDuration += 0.1
                        self.progress.value = min(CGFloat(self.listenDuration / self.maxListenDuration), 1.0)

                        if self.listenDuration >= self.maxListenDuration {
                            self.stopListening()
                            if self.state == .listening {
                                self.state = .notFound
                            }
                        }
                    }
                }
            } catch {
                AppLogger.error("AudioMatch: 启动录音失败 - \(error)")
                self.state = .error(NSLocalizedString("audio_match_error", comment: ""))
                self.stopAudioEngine()
            }
            self.audioSessionActivationTask = nil
        }
    }

    private func stopAudioEngine() {
        audioSessionActivationTask?.cancel()
        audioSessionActivationTask = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        // 让 PlayerManager 按用户当前的 backgroundAudioPolicy 重新决议 options，
        // 避免写死成 [] 把用户的 alwaysMix / 游戏模式 ducking 设置静默覆盖。
        PlayerManager.shared.lastAppliedAudioSessionOptions = nil
        PlayerManager.shared.reapplyAudioSessionOptions(reason: "Shazam 录音结束")
    }

    fileprivate func handleMatch(_ match: SHMatch) {
        stopListening()
        guard let item = match.mediaItems.first else {
            state = .notFound
            return
        }
        state = .matching
        shazamTitle = item.title
        shazamArtist = item.artist
        shazamArtworkURL = item.artworkURL
        AppLogger.info("AudioMatch: Shazam 识别成功 - \(item.title ?? "") by \(item.artist ?? "")")
        searchMatchedSong(title: item.title, artist: item.artist)
    }

    fileprivate func handleNoMatch() {}

    fileprivate func handleError(_ error: Error) {
        stopListening()
        AppLogger.error("AudioMatch: Shazam 错误 - \(error)")
        state = .error(NSLocalizedString("audio_match_error", comment: ""))
    }

    private func searchMatchedSong(title: String?, artist: String?) {
        guard let title, !title.isEmpty else {
            state = .notFound
            return
        }
        let query = [title, artist].compactMap { $0 }.joined(separator: " ")
        Task {
            do {
                let songs = try await APIService.shared.searchSongs(keyword: query).async()
                let topSongs = Array(songs.prefix(5))
                if topSongs.isEmpty {
                    state = .notFound
                } else {
                    matchedSongs = topSongs
                    state = .found
                }
            } catch {
                AppLogger.error("AudioMatch: 搜索匹配失败 - \(error)")
                state = .found
            }
        }
    }
}

// MARK: - SHSessionDelegate

private class ShazamDelegate: NSObject, SHSessionDelegate {
    weak var viewModel: AudioMatchViewModel?
    init(viewModel: AudioMatchViewModel) { self.viewModel = viewModel }

    func session(_ session: SHSession, didFind match: SHMatch) {
        let vm = UnsafeSendableBox(viewModel)
        Task { @MainActor in vm.value?.handleMatch(match) }
    }
    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        let vm = UnsafeSendableBox(viewModel)
        let err = error
        Task { @MainActor in
            if let err { vm.value?.handleError(err) }
            else { vm.value?.handleNoMatch() }
        }
    }
}

// MARK: - AudioMatchView

struct AudioMatchView: View {
    @StateObject private var viewModel = AudioMatchViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedSongForDetail: Song?
    @State private var showSongDetail = false
    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 40)

                        // 中心识别区域
                        centerContent
                            .frame(minHeight: 360)

                        // 结果区域
                        if viewModel.state == .found && !viewModel.matchedSongs.isEmpty {
                            resultsSection
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        FloatingBarBottomSpacer()
                    }
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $showSongDetail) {
            if let song = selectedSongForDetail {
                SongDetailView(song: song)

            }
        }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - 中心内容

    @ViewBuilder
    private var centerContent: some View {
        switch viewModel.state {
        case .idle:         idleView
        case .listening:    listeningView
        case .matching:     matchingView
        case .found:        foundView
        case .notFound:     notFoundView
        case .error(let m): errorView(message: m)
        }
    }

    // MARK: - 空闲状态

    private var idleView: some View {
        VStack(spacing: 36) {
            // 主按钮
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.startListening()
            }) {
                ZStack {
                    // 装饰环
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.monoTextPrimary.opacity(0.05), .monoTextPrimary.opacity(0.15), .monoTextPrimary.opacity(0.05)],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 190, height: 190)

                    // 主圆
                    Circle()
                        .fill(Color.monoGlassTint)
                        .frame(width: 150, height: 150)
                        .monoGlassCircle()
                        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 10)

                    // 图标
                    MonoIcon(icon: .audioWave, size: 52, color: .monoTextPrimary, lineWidth: 1.8)
                }
            }
            .buttonStyle(MonoBouncingButtonStyle())

            VStack(spacing: 8) {
                Text(LocalizedStringKey("audio_match_tap_to_start"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundColor(.monoTextPrimary)

                Text(LocalizedStringKey("audio_match_hint"))
                    .font(.rounded(size: 14))
                    .foregroundColor(.monoTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
        }
    }

    // MARK: - 监听中

    private var listeningView: some View {
        VStack(spacing: 36) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.stopListening()
            }) {
                ZStack {
                    // 脉冲波纹
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.monoTextPrimary.opacity(0.12), lineWidth: 1.5)
                            .frame(width: 190 + CGFloat(i) * 44, height: 190 + CGFloat(i) * 44)
                            .scaleEffect(pulsePhase > 0 ? 1.08 : 0.92)
                            .opacity(pulsePhase > 0 ? 0.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 1.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.35),
                                value: pulsePhase
                            )
                    }

                    // 进度环
                    AudioMatchProgressRing(progress: viewModel.progress)

                    // 主圆
                    Circle()
                        .fill(Color.monoGlassTint)
                        .frame(width: 150, height: 150)
                        .monoGlassCircle()
                        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 10)

                    // 音纹动画
                    HStack(spacing: 5) {
                        ForEach(0..<5, id: \.self) { i in
                            AudioWaveBar(index: i)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onAppear { pulsePhase = 1 }
            .onDisappear { pulsePhase = 0 }

            VStack(spacing: 8) {
                Text(LocalizedStringKey("audio_match_listening"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundColor(.monoTextPrimary)

                Text(LocalizedStringKey("audio_match_listening_hint"))
                    .font(.rounded(size: 14))
                    .foregroundColor(.monoTextSecondary)
            }
        }
    }

    // MARK: - 匹配中

    private var matchingView: some View {
        VStack(spacing: 28) {
            if let artworkURL = viewModel.shazamArtworkURL {
                CachedAsyncImage(url: artworkURL) {
                    RoundedRectangle(cornerRadius: 24).fill(Color.monoGlassTint).monoGlass(cornerRadius: 24)
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
            }

            VStack(spacing: 6) {
                if let title = viewModel.shazamTitle {
                    Text(title)
                        .font(.rounded(size: 22, weight: .bold))
                        .foregroundColor(.monoTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let artist = viewModel.shazamArtist {
                    Text(artist)
                        .font(.rounded(size: 16, weight: .medium))
                        .foregroundColor(.monoTextSecondary)
                }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(LocalizedStringKey("audio_match_searching"))
                    .font(.rounded(size: 14, weight: .medium))
                    .foregroundColor(.monoTextSecondary)
            }
        }
    }

    // MARK: - 找到结果

    private var foundView: some View {
        VStack(spacing: 24) {
            if let artworkURL = viewModel.shazamArtworkURL {
                CachedAsyncImage(url: artworkURL) {
                    RoundedRectangle(cornerRadius: 24).fill(Color.monoGlassTint).monoGlass(cornerRadius: 24)
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 8)
            }

            VStack(spacing: 6) {
                if let title = viewModel.shazamTitle {
                    Text(title)
                        .font(.rounded(size: 22, weight: .bold))
                        .foregroundColor(.monoTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let artist = viewModel.shazamArtist {
                    Text(artist)
                        .font(.rounded(size: 16, weight: .medium))
                        .foregroundColor(.monoTextSecondary)
                }
            }
            .padding(.horizontal, 40)

            // 重新识别
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.reset()
            }) {
                HStack(spacing: 6) {
                    MonoIcon(icon: .refresh, size: 14, color: .monoTextSecondary, lineWidth: 1.4)
                    Text(LocalizedStringKey("audio_match_retry"))
                        .font(.rounded(size: 14, weight: .medium))
                        .foregroundColor(.monoTextSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.monoGlassTint).monoGlassCapsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - 未找到

    private var notFoundView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Color.monoGlassTint)
                    .frame(width: 120, height: 120)
                    .monoGlassCircle()
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)

                MonoIcon(icon: .audioWave, size: 44, color: .monoTextSecondary.opacity(0.4), lineWidth: 1.6)
            }

            VStack(spacing: 8) {
                Text(LocalizedStringKey("audio_match_not_found"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundColor(.monoTextPrimary)

                Text(LocalizedStringKey("audio_match_not_found_hint"))
                    .font(.rounded(size: 14))
                    .foregroundColor(.monoTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.reset()
                viewModel.startListening()
            }) {
                HStack(spacing: 6) {
                    MonoIcon(icon: .refresh, size: 14, color: .monoIconForeground, lineWidth: 1.4)
                    Text(LocalizedStringKey("audio_match_try_again"))
                        .font(.rounded(size: 15, weight: .bold))
                }
                .foregroundColor(.monoIconForeground)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.monoGlassTint))
                .monoGlassCapsule()
            }
            .buttonStyle(MonoBouncingButtonStyle())
        }
    }

    // MARK: - 错误

    private func errorView(message: String) -> some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Color.monoGlassTint)
                    .frame(width: 120, height: 120)
                    .monoGlassCircle()
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)

                MonoIcon(icon: .warning, size: 44, color: .monoTextSecondary.opacity(0.4))
            }

            VStack(spacing: 8) {
                Text(LocalizedStringKey("audio_match_error"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundColor(.monoTextPrimary)

                Text(message)
                    .font(.rounded(size: 14))
                    .foregroundColor(.monoTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }

            Button(action: {
                viewModel.reset()
                viewModel.startListening()
            }) {
                HStack(spacing: 6) {
                    MonoIcon(icon: .refresh, size: 14, color: .monoIconForeground, lineWidth: 1.4)
                    Text(LocalizedStringKey("audio_match_try_again"))
                        .font(.rounded(size: 15, weight: .bold))
                }
                .foregroundColor(.monoIconForeground)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.monoGlassTint))
                .monoGlassCapsule()
            }
            .buttonStyle(MonoBouncingButtonStyle())
        }
    }

    // MARK: - 搜索结果列表

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 分隔线
            Rectangle()
                .fill(Color.monoSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, 24)

            Text(LocalizedStringKey("audio_match_results"))
                .font(.rounded(size: 17, weight: .bold))
                .foregroundColor(.monoTextPrimary)
                .padding(.horizontal, 24)

            LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                ForEach(Array(viewModel.matchedSongs.enumerated()), id: \.element.identityKey) { index, song in
                    matchResultRow(song: song, index: index)
                }
            }
            .padding(.horizontal, ThemedPageStyle.horizontalInset)
        }
        .padding(.top, 8)
    }

    private func matchResultRow(song: Song, index: Int) -> some View {
        Button(action: {
            PlayerManager.shared.play(song: song, in: viewModel.matchedSongs)
        }) {
            HStack(spacing: 14) {
                // 封面
                CachedAsyncImage(url: song.coverUrl) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.monoGlassTint)
                        .monoGlass(cornerRadius: 12)
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.monoTextPrimary)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.monoTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // 匹配度标签（第一个最匹配）
                if index == 0 {
                    Text(LocalizedStringKey("search_best_match"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.monoIconForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.monoGlassTint))
                        .monoGlassCapsule()
                }

                MonoIcon(icon: .play, size: 14, color: .monoTextSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.monoGlassTint)
                    .clipShape(Circle())
            }
            .padding(.horizontal, ThemedPageStyle.isActive ? 16 : 24)
            .padding(.vertical, 10)
            .themedOnlyPageSurface(cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius, elevated: index == 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
        .contextMenu {
            Button(action: {
                selectedSongForDetail = song
                showSongDetail = true
            }) {
                Label(NSLocalizedString("action_details", comment: ""), systemImage: "info.circle")
            }
        }
    }
}

// MARK: - 音纹波形条动画

private struct AudioWaveBar: View {
    let index: Int
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.monoTextPrimary)
            .frame(width: 4, height: animating ? CGFloat.random(in: 16...38) : 8)
            .animation(
                .easeInOut(duration: Double.random(in: 0.3...0.6))
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.1),
                value: animating
            )
            .onAppear { animating = true }
    }
}


@MainActor
final class AudioMatchListeningProgress: ObservableObject {
    @Published var value: CGFloat = 0
}

private struct AudioMatchProgressRing: View {
    @ObservedObject var progress: AudioMatchListeningProgress

    var body: some View {
        Circle()
            .trim(from: 0, to: progress.value)
            .stroke(
                Color.monoTextPrimary,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 190, height: 190)
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.1), value: progress.value)
    }
}
