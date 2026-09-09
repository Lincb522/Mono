import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum DownloadCenterSection: String, CaseIterable, Identifiable {
    case music = "音乐"
    case tasks = "任务"
    case lyrics = "歌词"

    var id: String { rawValue }

    var icon: MonoIcon.IconType {
        switch self {
        case .music: return .musicNote
        case .tasks: return .download
        case .lyrics: return .musicNoteList
        }
    }
}

private enum DownloadClearTarget {
    case none
    case music
    case lyrics
}

private enum DownloadCenterPalette {
    static var primary: Color { SignalStyle.isActive ? SignalStyle.ink : .white }
    static var secondary: Color { SignalStyle.isActive ? SignalStyle.inkSoft : .white.opacity(0.58) }
    static var accent: Color { SignalStyle.isActive ? SignalStyle.accent : Color(red: 0.55, green: 0.84, blue: 0.98) }
    static var separator: Color { SignalStyle.isActive ? SignalStyle.separator : .white.opacity(0.08) }
    static var card: Color { SignalStyle.isActive ? SignalStyle.surface : .white.opacity(0.055) }
    static var backdrop: Color { SignalStyle.isActive ? SignalStyle.base : Color(red: 0.028, green: 0.031, blue: 0.04) }
}

@MainActor
private func downloadCenterVisibleWidth(proxyWidth: CGFloat) -> CGFloat {
    max(1, proxyWidth)
}

private struct DownloadProgressGlyph: View {
    let progress: Double?
    var tint: Color = DownloadCenterPalette.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animates = false

    private var resolvedProgress: Double {
        max(0.02, min(progress ?? 0.72, 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.13), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: resolvedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(progress == nil && animates ? 360 : 0))

            MonoIcon(icon: .download, size: 12, color: tint, lineWidth: 1.7)
                .offset(y: !reduceMotion && animates ? 1.5 : -1.5)
        }
        .frame(width: 34, height: 34)
        .animation(.easeOut(duration: 0.22), value: resolvedProgress)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: progress == nil ? 1.05 : 0.72)
                    .repeatForever(autoreverses: progress != nil)
            ) {
                animates = true
            }
        }
        .accessibilityValue(progress.map { "\(Int($0 * 100))%" } ?? String(localized: "正在下载"))
    }
}

struct CurrentSongDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss
    @Environment(\.colorScheme) private var inheritedColorScheme
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var lyricDownloadManager = LyricDownloadManager.shared
    @ObservedObject private var lyricViewModel = LyricViewModel.shared

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = downloadCenterVisibleWidth(proxyWidth: proxy.size.width)
            let horizontalInset: CGFloat = availableWidth < 370 ? 12 : 16
            let viewportWidth = min(availableWidth, 520)
            let contentWidth = max(1, viewportWidth - horizontalInset * 2)

            ZStack {
                DownloadCenterPalette.backdrop
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    sheetHeader

                    if let song = player.currentSong {
                        songHeader(song)

                        VStack(spacing: 0) {
                            audioAction(song)
                            divider
                            lyricAction(song)
                        }
                        .background(panelBackground)

                        if let error = lyricDownloadManager.lastError, !error.isEmpty {
                            HStack(spacing: 9) {
                                MonoIcon(icon: .warning, size: 15, color: .monoAccentRed)
                                Text(error)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(DownloadCenterPalette.secondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: contentWidth, height: proxy.size.height, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .frame(width: availableWidth, height: proxy.size.height, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
                .clipped()
            }
        }
        .environment(\.colorScheme, .dark)
        .monoSheetSurface(id: "current-song-download") {
            DownloadCenterPalette.backdrop
        }
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "下载"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)

                Text(String(localized: "当前歌曲"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)
            }

            Spacer(minLength: 0)

            Button(action: close) {
                MonoIcon(icon: .close, size: 14, color: DownloadCenterPalette.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DownloadCenterPalette.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common_close"))
        }
    }

    private func songHeader(_ song: Song) -> some View {
        HStack(spacing: 14) {
            artwork(url: song.coverUrl, size: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(song.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)
                    .lineLimit(1)

                PlatformBadgeLabel(
                    text: song.musicSource.shortName,
                    source: song.musicSource,
                    fontSize: 10
                )
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(panelBackground)
    }

    private func audioAction(_ song: Song) -> some View {
        let isDownloaded = downloadManager.localFileURL(for: song) != nil
        let task = downloadManager.task(for: song)
        let isAvailable = song.musicSource != .local

        return Button {
            guard isAvailable, !isDownloaded else { return }
            if task != nil {
                downloadManager.cancelDownload(for: song)
            } else {
                startAudioDownload(song)
            }
        } label: {
            downloadOptionRow(
                icon: .soundQuality,
                title: String(localized: "下载音乐"),
                subtitle: isDownloaded
                    ? String(localized: "已保存到本地音乐")
                    : (task == nil ? defaultAudioQualityText(for: song) : String(localized: "正在下载")),
                status: isDownloaded ? String(localized: "已下载") : task.map { "\(Int($0.progress * 100))%" },
                isActive: isDownloaded || task != nil,
                showsProgress: task != nil,
                progress: task?.progress
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.4)
    }

    private func startAudioDownload(_ song: Song) {
        if song.isQishui {
            downloadManager.downloadQishui(
                song: song,
                quality: SettingsManager.shared.defaultQishuiPlaybackQuality
            )
        } else if song.isQQMusic {
            downloadManager.downloadQQ(
                song: song,
                quality: DownloadManager.defaultQQDownloadQuality
            )
        } else {
            downloadManager.download(
                song: song,
                quality: DownloadManager.defaultNeteaseDownloadQuality
            )
        }
        HapticManager.shared.success()
    }

    private func defaultAudioQualityText(for song: Song) -> String {
        if song.isQishui {
            return String(localized: "最高可用音质")
        }
        if song.isQQMusic {
            return DownloadManager.defaultQQDownloadQuality.displayName
        }
        return DownloadManager.defaultNeteaseDownloadQuality.displayName
    }

    private func lyricAction(_ song: Song) -> some View {
        let source = lyricViewModel.selectedSource(for: song)
        let record = lyricDownloadManager.record(for: song, source: source)
        let isWorking = lyricDownloadManager.isDownloading(song, source: source)

        return Button {
            guard record == nil, !isWorking else { return }
            Task { await lyricDownloadManager.downloadLyrics(for: song) }
        } label: {
            downloadOptionRow(
                icon: .musicNoteList,
                title: String(localized: "下载歌词"),
                subtitle: "\(source.shortName) · \(String(localized: "含逐字与翻译"))",
                status: record == nil ? nil : String(localized: "已下载"),
                isActive: record != nil || isWorking,
                showsProgress: isWorking,
                progress: nil
            )
        }
        .buttonStyle(.plain)
        .disabled(record != nil || isWorking)
    }

    private func downloadOptionRow(
        icon: MonoIcon.IconType,
        title: String,
        subtitle: String,
        status: String?,
        isActive: Bool,
        showsProgress: Bool,
        progress: Double?
    ) -> some View {
        HStack(spacing: 13) {
            MonoIcon(
                icon: icon,
                size: 18,
                color: isActive ? DownloadCenterPalette.accent : DownloadCenterPalette.primary.opacity(0.78)
            )
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((isActive ? DownloadCenterPalette.accent : DownloadCenterPalette.primary).opacity(0.09))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsProgress {
                DownloadProgressGlyph(progress: progress)
            } else if let status {
                Text(status)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.accent)
            } else {
                MonoIcon(icon: .chevronRight, size: 11, color: DownloadCenterPalette.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(DownloadCenterPalette.separator)
            .frame(height: 0.5)
            .padding(.leading, 65)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(DownloadCenterPalette.card)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DownloadCenterPalette.separator, lineWidth: 0.5)
            }
    }

    private func artwork(url: URL?, size: CGFloat) -> some View {
        Group {
            if let url {
                CachedAsyncImage(url: url.sized(240)) {
                    artworkPlaceholder(size: size)
                }
            } else {
                artworkPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func artworkPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(DownloadCenterPalette.primary.opacity(0.06))
            .frame(width: size, height: size)
            .overlay(MonoIcon(icon: .musicNote, size: 21, color: DownloadCenterPalette.secondary))
    }

    private func close() {
        dismissCurrentPresentation(
            systemDismiss: dismiss,
            monoSheetDismiss: monoSheetDismiss
        )
    }
}

struct DownloadManageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var inheritedColorScheme
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var lyricDownloadManager = LyricDownloadManager.shared
    @State private var selectedSection: DownloadCenterSection = .music
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var audioRecords: [DownloadedSong] = []
    @State private var taskRecords: [DownloadedSong] = []
    @State private var taskKeys: Set<String> = []
    @State private var totalBytes: Int64 = 0

    private var lyricTaskRecords: [LyricDownloadManager.ActiveTask] {
        lyricDownloadManager.activeTasks.values.sorted { $0.songName < $1.songName }
    }
    private var activeTaskCount: Int { taskRecords.count + lyricTaskRecords.count }
    private var lyricRecords: [DownloadedLyric] { lyricDownloadManager.records }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = downloadCenterVisibleWidth(proxyWidth: proxy.size.width)
            let horizontalInset: CGFloat = availableWidth < 370 ? 12 : 16
            let viewportWidth = min(availableWidth, 760)
            let contentWidth = max(1, viewportWidth - horizontalInset * 2)

            ZStack {
                downloadBackdrop

                ScrollView {
                    LazyVStack(spacing: 16) {
                        downloadHeader
                        overviewCard
                        sectionPicker
                        sectionContent
                        FloatingBarBottomSpacer()
                    }
                    .frame(maxWidth: contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .frame(width: availableWidth, height: proxy.size.height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
        }
        .environment(\.colorScheme, .dark)
        .compatFontDesign(nil)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedSection)
        .monoSheet(isPresented: $showShareSheet, preset: .standard) {
            DownloadShareSheet(activityItems: shareItems)
        }
        .onAppear(perform: refreshRecordSnapshots)
        .onReceive(downloadManager.$downloadedSongIds) { _ in
            audioRecords = downloadManager.fetchAllDownloaded()
            refreshTotalBytes()
        }
        .onReceive(downloadManager.$downloadingTasks) { tasks in
            let keys = Set(tasks.keys)
            guard keys != taskKeys else { return }
            taskKeys = keys
            taskRecords = downloadManager.fetchDownloading()
        }
        .onReceive(lyricDownloadManager.$records) { _ in
            refreshTotalBytes()
        }
    }

    private var downloadBackdrop: some View {
        Group {
            if SignalStyle.isActive {
                SignalRootBackdrop()
            } else {
                ZStack {
                    DownloadCenterPalette.backdrop

                    if let url = player.currentSong?.coverUrl?.sized(720) {
                        CachedAsyncImage(url: url) {
                            Color.clear
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(1.18)
                        .blur(radius: 76)
                        .saturation(0.68)
                        .opacity(0.16)
                        .clipped()
                    }

                    LinearGradient(
                        colors: [Color.black.opacity(0.3), Color.black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var downloadHeader: some View {
        if SignalStyle.isActive {
            SignalNestedPageHeader(
                title: String(localized: "下载管理"),
                eyebrow: "DOWNLOAD QUEUE",
                icon: .download,
                module: .storage
            )
        } else {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(DownloadCenterPalette.accent.opacity(0.11))

                    if activeTaskCount == 0 {
                        MonoIcon(icon: .download, size: 22, color: DownloadCenterPalette.accent)
                    } else {
                        DownloadProgressGlyph(progress: overallProgress)
                    }
                }
                .frame(width: 54, height: 54)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(DownloadCenterPalette.accent.opacity(0.2), lineWidth: 0.8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "下载管理"))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.primary)

                    Text(
                        activeTaskCount == 0
                            ? String(localized: "本地音乐与歌词")
                            : L10n.format("download_active_tasks_format", activeTaskCount)
                    )
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)
                }

                Spacer(minLength: 0)

                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .padding(.vertical, 4)
        }
    }

    private var overallProgress: Double? {
        let active = taskRecords.filter { $0.status == .downloading }
        guard !active.isEmpty, lyricTaskRecords.isEmpty else { return nil }
        let total = active.reduce(0.0) { partial, record in
            partial + (downloadManager.downloadingTasks[record.uniqueKey]?.progress ?? record.progress)
        }
        return total / Double(active.count)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "本地下载"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.primary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                MonoIcon(icon: .storage, size: 24, color: DownloadCenterPalette.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DownloadCenterPalette.accent.opacity(0.12))
                    )
            }

            HStack(spacing: 0) {
                metric(value: audioRecords.count, label: String(localized: "音乐"))
                metricDivider
                metric(value: activeTaskCount, label: String(localized: "任务"))
                metricDivider
                metric(value: lyricRecords.count, label: String(localized: "歌词"))
            }
        }
        .padding(18)
        .background(centerCard(cornerRadius: 24))
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(DownloadCenterPalette.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DownloadCenterPalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(DownloadCenterPalette.separator)
            .frame(width: 0.5, height: 30)
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(DownloadCenterSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 7) {
                        MonoIcon(
                            icon: section.icon,
                            size: 14,
                            color: selectedSection == section ? DownloadCenterPalette.primary : DownloadCenterPalette.secondary
                        )
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSection == section ? DownloadCenterPalette.primary : DownloadCenterPalette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(DownloadCenterPalette.primary.opacity(0.08))
                                .matchedGeometryEffect(id: "download-section", in: pickerNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(centerCard(cornerRadius: 18))
    }

    @Namespace private var pickerNamespace

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .music:
            musicSection
        case .tasks:
            taskSection
        case .lyrics:
            lyricSection
        }
    }

    private var musicSection: some View {
        downloadGroup(
            title: String(localized: "已下载音乐"),
            count: audioRecords.count,
            showsClearAction: !audioRecords.isEmpty,
            clearTarget: .music
        ) {
            if audioRecords.isEmpty {
                emptyState(icon: .musicNote, title: String(localized: "暂无已下载音乐"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(audioRecords, id: \.uniqueKey) { record in
                        audioRow(record)
                    }
                }
            }
        }
    }

    private var taskSection: some View {
        downloadGroup(
            title: String(localized: "下载任务"),
            count: activeTaskCount,
            showsClearAction: false,
            clearTarget: .none
        ) {
            if activeTaskCount == 0 {
                emptyState(icon: .download, title: String(localized: "暂无下载任务"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(taskRecords, id: \.uniqueKey) { record in
                        taskRow(record)
                    }

                    ForEach(lyricTaskRecords) { task in
                        lyricTaskRow(task)
                    }
                }
            }
        }
    }

    private var lyricSection: some View {
        downloadGroup(
            title: String(localized: "已下载歌词"),
            count: lyricRecords.count,
            showsClearAction: !lyricRecords.isEmpty,
            clearTarget: .lyrics
        ) {
            if lyricRecords.isEmpty {
                emptyState(icon: .musicNoteList, title: String(localized: "暂无已下载歌词"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(lyricRecords) { record in
                        lyricRow(record)
                    }
                }
            }
        }
    }

    private func downloadGroup<Content: View>(
        title: String,
        count: Int,
        showsClearAction: Bool,
        clearTarget: DownloadClearTarget,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)

                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.secondary)

                Spacer(minLength: 0)

                if showsClearAction {
                    Button(String(localized: "search_clear")) {
                        performClearAction(clearTarget)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.monoAccentRed)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            content()
        }
    }

    private func performClearAction(_ target: DownloadClearTarget) {
        switch target {
        case .none:
            return
        case .music:
            confirmClearMusic()
        case .lyrics:
            confirmClearLyrics()
        }
    }

    private func audioRow(_ record: DownloadedSong) -> some View {
        HStack(spacing: 13) {
            HStack(spacing: 13) {
                artwork(urlString: record.coverUrl, size: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.primary)
                        .lineLimit(1)
                    Text("\(record.artistName) · \(audioMetadata(record))")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                PlayerManager.shared.play(
                    song: record.toSong(),
                    in: audioRecords.map { $0.toSong() }
                )
            }

            rowAction(icon: .share) { share(record.localFileURL) }
            rowAction(icon: .trash, tint: .monoAccentRed) {
                downloadManager.deleteDownload(key: record.uniqueKey)
            }
        }
        .padding(12)
        .background(centerCard(cornerRadius: 18))
    }

    private func taskRow(_ record: DownloadedSong) -> some View {
        let progress = downloadManager.downloadingTasks[record.uniqueKey]?.progress ?? record.progress

        return HStack(spacing: 13) {
            artwork(urlString: record.coverUrl, size: 54)

            VStack(alignment: .leading, spacing: 7) {
                Text(record.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)
                    .lineLimit(1)

                MonoLiquidProgressBar(
                    progress: progress,
                    tint: record.status == .failed ? .monoAccentRed : DownloadCenterPalette.accent,
                    secondaryTint: record.status == .failed ? .monoAccentRed : Color.white.opacity(0.82),
                    isActive: record.status == .downloading,
                    height: 5
                )

                Text(taskStatus(record, progress: progress))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(record.status == .failed ? Color.monoAccentRed : DownloadCenterPalette.secondary)
            }

            if record.status != .failed {
                DownloadProgressGlyph(progress: record.status == .waiting ? nil : progress)
            }

            rowAction(icon: .close) {
                downloadManager.cancelDownload(for: record.toSong())
            }
        }
        .padding(12)
        .background(centerCard(cornerRadius: 18))
    }

    private func lyricRow(_ record: DownloadedLyric) -> some View {
        HStack(spacing: 13) {
            artwork(urlString: record.coverURLString, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.songName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    PlatformBadgeLabel(text: record.source.shortName, source: record.source.musicSource, fontSize: 9)
                    Text("\(record.artistName) · \(record.fileSizeText)")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            rowAction(icon: .share) { share(record.primaryFileURL) }
            rowAction(icon: .trash, tint: .monoAccentRed) {
                lyricDownloadManager.delete(record)
            }
        }
        .padding(12)
        .background(centerCard(cornerRadius: 18))
    }

    private func lyricTaskRow(_ task: LyricDownloadManager.ActiveTask) -> some View {
        HStack(spacing: 13) {
            artwork(urlString: task.coverURLString, size: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.songName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DownloadCenterPalette.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    PlatformBadgeLabel(text: task.source.shortName, source: task.source.musicSource, fontSize: 9)
                    Text("\(task.artistName) · \(String(localized: "正在获取歌词"))")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DownloadCenterPalette.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
            DownloadProgressGlyph(progress: nil)
        }
        .padding(12)
        .background(centerCard(cornerRadius: 18))
    }

    private func emptyState(icon: MonoIcon.IconType, title: String) -> some View {
        VStack(spacing: 11) {
            MonoIcon(icon: icon, size: 28, color: DownloadCenterPalette.secondary.opacity(0.56))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DownloadCenterPalette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(centerCard(cornerRadius: 20))
    }

    private func rowAction(
        icon: MonoIcon.IconType,
        tint: Color = DownloadCenterPalette.secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonoIcon(icon: icon, size: 14, color: tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    private func artwork(urlString: String?, size: CGFloat) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url.sized(220)) {
                    artworkPlaceholder(size: size)
                }
            } else {
                artworkPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func artworkPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(DownloadCenterPalette.primary.opacity(0.06))
            .frame(width: size, height: size)
            .overlay(MonoIcon(icon: .musicNote, size: 18, color: DownloadCenterPalette.secondary))
    }

    private func centerCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DownloadCenterPalette.card)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DownloadCenterPalette.separator, lineWidth: 0.5)
            }
    }

    private func audioMetadata(_ record: DownloadedSong) -> String {
        let quality: String
        if record.isQQMusic {
            quality = record.qqQuality?.displayName ?? String(localized: "音乐")
        } else if record.isQishui {
            quality = record.qishuiQualityRaw ?? String(localized: "音乐")
        } else {
            quality = record.quality.displayName
        }
        return [quality, record.fileSizeText].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func taskStatus(_ record: DownloadedSong, progress: Double) -> String {
        switch record.status {
        case .waiting: return String(localized: "等待下载")
        case .downloading: return "\(Int(progress * 100))%"
        case .failed: return String(localized: "download_failed_title")
        case .restored: return String(localized: "等待恢复")
        case .completed: return String(localized: "已完成")
        }
    }

    private func share(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        shareItems = [url]
        showShareSheet = true
    }

    private func confirmClearMusic() {
        AlertManager.shared.show(
            title: String(localized: "清空已下载音乐"),
            message: String(localized: "将删除全部本地音乐文件"),
            primaryButtonTitle: String(localized: "search_clear"),
            secondaryButtonTitle: String(localized: "cancel"),
            primaryAction: { downloadManager.deleteAll() }
        )
    }

    private func confirmClearLyrics() {
        AlertManager.shared.show(
            title: String(localized: "清空已下载歌词"),
            message: String(localized: "将删除全部本地歌词文件"),
            primaryButtonTitle: String(localized: "search_clear"),
            secondaryButtonTitle: String(localized: "cancel"),
            primaryAction: { lyricDownloadManager.deleteAll() }
        )
    }

    private func refreshRecordSnapshots() {
        audioRecords = downloadManager.fetchAllDownloaded()
        taskRecords = downloadManager.fetchDownloading()
        taskKeys = Set(downloadManager.downloadingTasks.keys)
        refreshTotalBytes()
    }

    private func refreshTotalBytes() {
        totalBytes = downloadManager.totalDownloadSize() + lyricDownloadManager.totalDownloadSize()
    }
}

private struct DownloadShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
