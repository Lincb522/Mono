import SwiftUI

@MainActor
private final class ExternalPlaylistImportViewModel: ObservableObject {
    enum Phase: Equatable {
        case input
        case resolving
        case preview
        case importing
        case finished(imported: Int, skipped: Int)
    }

    @Published var provider: ExternalPlaylistProvider = .automatic
    @Published var input = ""
    @Published var playlistName = ""
    @Published var draft: ExternalPlaylistDraft?
    @Published var selectedTrackIDs = Set<Int>()
    @Published var states: [Int: ExternalPlaylistMatchState] = [:]
    @Published var matchedSources: [Int: MusicSource] = [:]
    @Published var phase: Phase = .input
    @Published var errorMessage: String?
    @Published var completedCount = 0
    @Published var currentTrackTitle: String?
    @Published private(set) var previewPage = 0

    private var operationTask: Task<Void, Never>?
    private let previewPageSize = 10

    var selectedCount: Int {
        selectedTrackIDs.count
    }

    var progress: Double {
        let total = max(1, selectedTrackIDs.count)
        return min(1, Double(completedCount) / Double(total))
    }

    var canResolve: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .resolving
    }

    var canImport: Bool {
        draft != nil &&
            !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !selectedTrackIDs.isEmpty &&
            phase != .importing
    }

    var previewTracks: [ExternalPlaylistTrack] {
        guard let tracks = draft?.tracks, !tracks.isEmpty else { return [] }
        let start = min(previewPage * previewPageSize, tracks.count)
        let end = min(start + previewPageSize, tracks.count)
        return Array(tracks[start..<end])
    }

    var previewPageCount: Int {
        guard let count = draft?.tracks.count, count > 0 else { return 1 }
        return max(1, Int(ceil(Double(count) / Double(previewPageSize))))
    }

    var previewPageRangeText: String {
        guard let count = draft?.tracks.count, count > 0 else { return "0 / 0" }
        let start = min(previewPage * previewPageSize + 1, count)
        let end = min((previewPage + 1) * previewPageSize, count)
        return "\(start)–\(end) / \(count)"
    }

    var canShowPreviousPreviewPage: Bool {
        previewPage > 0
    }

    var canShowNextPreviewPage: Bool {
        previewPage + 1 < previewPageCount
    }

    func resolve() {
        operationTask?.cancel()
        errorMessage = nil
        currentTrackTitle = nil
        previewPage = 0
        phase = .resolving
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await ExternalPlaylistImportService.shared.resolve(
                    input: input,
                    provider: provider
                )
                guard !Task.isCancelled else { return }
                draft = result
                playlistName = result.name
                selectedTrackIDs = Set(result.tracks.map(\.id))
                states = Dictionary(
                    uniqueKeysWithValues: result.tracks.map { ($0.id, .pending) }
                )
                matchedSources.removeAll()
                completedCount = 0
                currentTrackTitle = nil
                previewPage = 0
                phase = .preview
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                currentTrackTitle = nil
                phase = .input
            }
        }
    }

    func toggle(_ trackID: Int) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
    }

    func toggleAll() {
        guard let draft else { return }
        if selectedTrackIDs.count == draft.tracks.count {
            selectedTrackIDs.removeAll()
        } else {
            selectedTrackIDs = Set(draft.tracks.map(\.id))
        }
    }

    func showPreviousPreviewPage() {
        previewPage = max(0, previewPage - 1)
    }

    func showNextPreviewPage() {
        previewPage = min(previewPageCount - 1, previewPage + 1)
    }

    func importPlaylist() {
        guard let draft, canImport else { return }
        operationTask?.cancel()
        errorMessage = nil
        completedCount = 0
        currentTrackTitle = nil
        phase = .importing

        operationTask = Task { [weak self] in
            guard let self else { return }
            var matchedSongs: [Song] = []
            var songKeys = Set<String>()
            let tracks = draft.tracks.filter { selectedTrackIDs.contains($0.id) }

            for track in tracks {
                guard !Task.isCancelled else { return }
                currentTrackTitle = track.title
                states[track.id] = .matching
                let result = await ExternalPlaylistImportService.shared.match(track)
                if let song = result.song {
                    states[track.id] = .matched
                    matchedSources[track.id] = song.musicSource
                    let key = songKey(song)
                    if songKeys.insert(key).inserted {
                        matchedSongs.append(song)
                    }
                } else {
                    states[track.id] = .unmatched
                }
                completedCount += 1
            }

            guard !Task.isCancelled else { return }
            currentTrackTitle = nil
            guard !matchedSongs.isEmpty else {
                errorMessage = "没有找到可安全匹配的平台歌曲"
                phase = .preview
                return
            }

            let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
            LocalPlaylistManager.shared.importPlaylist(
                name: trimmedName,
                description: draft.description,
                coverURL: draft.coverURL,
                songs: matchedSongs
            )
            phase = .finished(
                imported: matchedSongs.count,
                skipped: max(0, tracks.count - matchedSongs.count)
            )
        }
    }

    func restart() {
        operationTask?.cancel()
        draft = nil
        selectedTrackIDs.removeAll()
        states.removeAll()
        matchedSources.removeAll()
        completedCount = 0
        currentTrackTitle = nil
        previewPage = 0
        errorMessage = nil
        phase = .input
    }

    func cancel() {
        operationTask?.cancel()
        operationTask = nil
        currentTrackTitle = nil
    }

    private func songKey(_ song: Song) -> String {
        let identifier: String = switch song.musicSource {
        case .netease:
            String(song.id)
        case .qqmusic:
            song.qqMid ?? String(song.id)
        case .qishui:
            song.qishuiTrackId.map(String.init) ?? String(song.id)
        case .kugou:
            song.kugouHash ?? String(song.id)
        case .appleMusic:
            song.appleMusicID ?? String(song.id)
        case .local:
            song.localRelativePath ?? String(song.id)
        }
        return "\(song.musicSource.rawValue):\(identifier)"
    }
}

struct ExternalPlaylistImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ExternalPlaylistImportViewModel()
    private let trackPreviewAnchor = "external-playlist-track-preview"

    var body: some View {
        ZStack {
            ThemedPageBackground(useRenderLayer: true)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        if SignalStyle.isActive {
                            SignalNestedPageHeader(
                                title: String(localized: "导入歌单"),
                                eyebrow: "DATA IMPORT",
                                icon: .download,
                                module: .importData
                            )
                        }

                        switch model.phase {
                        case .input, .resolving:
                            inputSection
                        case .preview, .importing:
                            previewSection(scrollProxy: proxy)
                        case let .finished(imported, skipped):
                            resultSection(imported: imported, skipped: skipped)
                        }

                        FloatingBarBottomSpacer()
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton()
        .animation(.easeInOut(duration: 0.18), value: model.phase)
        .onDisappear {
            model.cancel()
        }
    }

    @ViewBuilder
    private func phaseContent(scrollProxy: ScrollViewProxy) -> some View {
        switch model.phase {
        case .input, .resolving:
            inputSection
        case .preview, .importing:
            previewSection(scrollProxy: scrollProxy)
        case let .finished(imported, skipped):
            resultSection(imported: imported, skipped: skipped)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("来源")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ExternalPlaylistProvider.allCases) { provider in
                        providerButton(provider)
                    }
                }
                .padding(.horizontal, 1)
            }

            sectionTitle("歌单链接或曲目")

            TextEditor(text: $model.input)
                .font(SignalStyle.isActive ? SignalStyle.bodyFont(13, weight: .medium) : .system(size: 15, design: .rounded))
                .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)
                .scrollContentBackground(.hidden)
                .monoTextInputBehavior()
                .padding(12)
                .frame(minHeight: 176, alignment: .topLeading)
                .background(SignalStyle.isActive ? SignalStyle.controlPressed : Color.monoGlassTint)
                .clipShape(.rect(cornerRadius: SignalStyle.isActive ? 10 : 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SignalStyle.isActive ? 10 : 18, style: .continuous)
                        .stroke(SignalStyle.isActive ? SignalStyle.separator.opacity(0.74) : Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
                }
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("粘贴 NCM、QCM、KCM、汽水音乐、Apple Music、Spotify 或酷我音乐歌单链接，也可每行输入一首歌曲")
                            .font(SignalStyle.isActive ? SignalStyle.labelFont(11, weight: .medium) : .system(size: 14, design: .rounded))
                            .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkMuted : Color.monoTextSecondary.opacity(0.72))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            if let error = model.errorMessage {
                statusMessage(error, icon: .warning)
            }

            if model.phase == .resolving {
                ExternalPlaylistRecognitionIndicator()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            operationSpeedNotice

            primaryButton(
                title: model.phase == .resolving ? "正在读取" : "读取歌单",
                isEnabled: model.canResolve
            ) {
                MonoTextInputCommitter.commit(text: $model.input) { _ in
                    model.resolve()
                }
            }
        }
    }

    private func previewSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let draft = model.draft {
                playlistSummary(draft)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("曲目")
                        Text("\(model.selectedCount) / \(draft.tracks.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.monoTextSecondary)
                        Spacer()
                        Button(
                            model.selectedCount == draft.tracks.count ? "取消全选" : "全选",
                            action: model.toggleAll
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.monoTextPrimary)
                        .buttonStyle(.plain)
                        .disabled(model.phase == .importing)
                    }
                    .id(trackPreviewAnchor)

                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(model.previewTracks) { track in
                                trackRow(track)
                                if track.id != model.previewTracks.last?.id {
                                    Divider().opacity(0.22)
                                        .padding(.leading, 38)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(SignalStyle.isActive ? SignalStyle.surface : Color.monoGlassTint)
                    .clipShape(.rect(cornerRadius: SignalStyle.isActive ? 10 : 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SignalStyle.isActive ? 10 : 18, style: .continuous)
                            .stroke(SignalStyle.isActive ? SignalStyle.separator.opacity(0.72) : Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
                    }

                    if model.previewPageCount > 1 {
                        previewPagination(scrollProxy: scrollProxy)
                    }
                }
            }

            if model.phase == .importing {
                ExternalPlaylistImportProgressIndicator(
                    progress: model.progress,
                    completedCount: model.completedCount,
                    totalCount: model.selectedCount,
                    trackTitle: model.currentTrackTitle
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let error = model.errorMessage {
                statusMessage(error, icon: .warning)
            }

            primaryButton(
                title: model.phase == .importing ? "正在导入" : "导入所选曲目",
                isEnabled: model.canImport
            ) {
                MonoTextInputCommitter.commit(text: $model.playlistName) { _ in
                    model.importPlaylist()
                }
            }

            operationSpeedNotice
        }
    }

    private func previewPagination(
        scrollProxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: 12) {
            paginationButton(
                title: "上一页",
                isEnabled: model.canShowPreviousPreviewPage
            ) {
                model.showPreviousPreviewPage()
                scrollToTrackPreview(using: scrollProxy)
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text("第 \(model.previewPage + 1) / \(model.previewPageCount) 页")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .monospacedDigit()
                Text(model.previewPageRangeText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            paginationButton(
                title: "下一页",
                isEnabled: model.canShowNextPreviewPage
            ) {
                model.showNextPreviewPage()
                scrollToTrackPreview(using: scrollProxy)
            }
        }
    }

    private func paginationButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.monoTextPrimary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.monoGlassTint)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }

    private func scrollToTrackPreview(
        using proxy: ScrollViewProxy
    ) {
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(trackPreviewAnchor, anchor: .top)
        }
    }

    private func playlistSummary(_ draft: ExternalPlaylistDraft) -> some View {
        HStack(spacing: 14) {
            Group {
                if let coverURL = draft.coverURL {
                    CachedAsyncImage(
                        url: coverURL,
                        placeholder: { artworkPlaceholder },
                        width: 76,
                        height: 76
                    )
                } else {
                    artworkPlaceholder
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                TextField("歌单名称", text: $model.playlistName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .monoTextInputBehavior()
                HStack(spacing: 8) {
                    Text(draft.provider.title)
                    if let creator = draft.creator, !creator.isEmpty {
                        Text("·")
                        Text(creator)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalStyle.isActive ? SignalStyle.surface : Color.monoGlassTint)
        .clipShape(.rect(cornerRadius: SignalStyle.isActive ? 12 : 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SignalStyle.isActive ? 12 : 20, style: .continuous)
                .stroke(SignalStyle.isActive ? SignalStyle.separator.opacity(0.72) : Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
        }
    }

    private func providerButton(_ provider: ExternalPlaylistProvider) -> some View {
        let isSelected = model.provider == provider
        return Button {
            model.provider = provider
        } label: {
            Text(provider.title)
                .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: isSelected ? .semibold : .medium) : .system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SignalStyle.isActive ? (isSelected ? SignalStyle.accent : SignalStyle.inkSoft) : (isSelected ? Color.monoIconForeground : Color.monoTextPrimary))
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background(SignalStyle.isActive ? (isSelected ? SignalStyle.accent.opacity(0.14) : SignalStyle.control) : (isSelected ? Color.monoIconBackground : Color.monoGlassTint))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(SignalStyle.isActive ? (isSelected ? SignalStyle.accent.opacity(0.22) : SignalStyle.separator.opacity(0.72)) : Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .resolving)
    }

    private func sectionTitle(_ title: String) -> some View {
        Group {
            if SignalStyle.isActive {
                SignalSectionTitle(title: title)
            } else {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
            }
        }
    }

    private var operationSpeedNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            MonoIcon(icon: .info, size: 14, color: .monoTextSecondary)
                .padding(.top, 1)
            Text("识别与导入速度受网络状况和歌曲数量影响")
                .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkMuted : Color.monoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func trackRow(_ track: ExternalPlaylistTrack) -> some View {
        let isSelected = model.selectedTrackIDs.contains(track.id)
        let state = model.states[track.id] ?? .pending
        return Button {
            guard model.phase != .importing else { return }
            model.toggle(track.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(SignalStyle.isActive ? (isSelected ? SignalStyle.accent : SignalStyle.controlPressed) : (isSelected ? Color.monoIconBackground : Color.monoTextPrimary.opacity(0.08)))
                    if isSelected {
                        MonoIcon(icon: .checkmark, size: 12, color: SignalStyle.isActive ? SignalStyle.onAccent : .monoIconForeground)
                    }
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(SignalStyle.isActive ? SignalStyle.bodyFont(12, weight: .semibold) : .system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? (track.album ?? "未知歌手") : track.artist)
                        .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 12, design: .rounded))
                        .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                matchIndicator(state, source: model.matchedSources[track.id])
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func matchIndicator(
        _ state: ExternalPlaylistMatchState,
        source: MusicSource?
    ) -> some View {
        switch state {
        case .pending:
            EmptyView()
        case .matching:
            ProgressView().controlSize(.small)
        case .matched:
            Text(source?.displayName ?? "已匹配")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary)
        case .unmatched:
            Text("未匹配")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.orange)
        }
    }

    private func resultSection(imported: Int, skipped: Int) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.monoIconBackground)
                    .frame(width: 72, height: 72)
                MonoIcon(icon: .checkmark, size: 28, color: .monoIconForeground)
            }
            Text("歌单已导入")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.monoTextPrimary)
            Text(skipped > 0 ? "已导入 \(imported) 首，跳过 \(skipped) 首" : "已导入 \(imported) 首")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary)

            primaryButton(title: "完成", isEnabled: true, action: close)
            Button("继续导入") {
                model.restart()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.monoTextPrimary)
            .buttonStyle(.plain)
        }
        .padding(.top, 44)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Color.monoTextPrimary.opacity(0.07)
            MonoIcon(icon: .musicNoteList, size: 28, color: .monoTextSecondary)
        }
    }

    private func statusMessage(_ text: String, icon: MonoIcon.IconType) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MonoIcon(icon: icon, size: 16, color: .orange)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.09))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private func primaryButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(SignalStyle.isActive ? SignalStyle.labelFont(12, weight: .bold) : .system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(SignalStyle.isActive ? SignalStyle.onAccent : Color.monoIconForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SignalStyle.isActive ? SignalStyle.accent : Color.monoIconBackground)
                .clipShape(.rect(cornerRadius: SignalStyle.isActive ? 9 : 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func close() {
        dismiss()
    }
}

private struct ExternalPlaylistRecognitionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            TimelineView(AppFrameRate.animationTimeline(maximumFramesPerSecond: 30, paused: reduceMotion)) { context in
                let phase = animationPhase(at: context.date, duration: 1.25)
                ZStack {
                    Circle()
                        .stroke(Color.monoTextPrimary.opacity(0.08), lineWidth: 4)

                    Circle()
                        .trim(from: 0.06, to: 0.68)
                        .stroke(
                            Color.monoIconBackground,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(reduceMotion ? -90 : phase * 360 - 90))

                    Circle()
                        .fill(Color.monoIconBackground.opacity(0.12))
                        .scaleEffect(reduceMotion ? 0.94 : 0.92 + sin(phase * .pi * 2) * 0.04)

                    MonoIcon(icon: .search, size: 20, color: .monoTextPrimary)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text("正在识别歌单")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                Text("正在读取链接和曲目信息")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.monoGlassTint)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
        }
    }

    private func animationPhase(at date: Date, duration: TimeInterval) -> Double {
        guard !reduceMotion else { return 0 }
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: duration) / duration
    }
}

private struct ExternalPlaylistImportProgressIndicator: View {
    let progress: Double
    let completedCount: Int
    let totalCount: Int
    let trackTitle: String?

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                MonoLiquidProgressBar(
                    progress: progress,
                    tint: .monoIconBackground,
                    secondaryTint: .monoAccent,
                    isActive: progress < 1,
                    height: 8
                )
            }
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text("正在导入 \(completedCount) / \(totalCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .monospacedDigit()

                Text(trackTitle ?? "正在准备歌曲")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.monoGlassTint)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.monoSeparator.opacity(0.7), lineWidth: 0.8)
        }
    }
}
