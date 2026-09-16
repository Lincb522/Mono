import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UniformTypeIdentifiers

/// AVAssetExportSession 未标注 Sendable，跨并发域传递时用该包装绕过检查（导出过程实际串行使用）。
private struct SendableAVAssetExportSession: @unchecked Sendable {
    let session: AVAssetExportSession
}

/// 本地音乐曲库管理器：负责音频文件的导入、扫描、删除与持久化。
///
/// 主要职责：
/// - 从文件选择器、App 文稿目录、系统媒体库导入音频并统一拷贝到沙盒 `LocalMusic/Library`；
/// - 导入时读取内嵌元数据（标题/歌手/封面/歌词），并尝试在网易云/QQ/汽水三个平台在线匹配补全；
/// - 通过 `library.json` 清单持久化曲目列表，并与 `LocalPlaylistManager` 保持同步。
@MainActor
final class LocalMusicLibraryManager: ObservableObject {
    static let shared = LocalMusicLibraryManager()

    // MARK: - 导入结果与进度模型

    /// 单次导入/扫描的汇总结果，`summaryText` 用于面板展示的本地化摘要。
    struct ImportResult {
        var importedCount = 0
        var skippedCount = 0
        var failedItems: [String] = []
        var notices: [String] = []
        var importedSongs: [Song] = []
        var matchedMetadataCount = 0
        var prefetchedLyricsCount = 0

        var summaryText: String {
            var parts = [
                String(
                    format: NSLocalizedString("local_import_result_imported", comment: ""),
                    locale: Locale.current,
                    importedCount
                )
            ]
            if skippedCount > 0 {
                parts.append(
                    String(
                        format: NSLocalizedString("local_import_result_skipped", comment: ""),
                        locale: Locale.current,
                        skippedCount
                    )
                )
            }
            if !failedItems.isEmpty {
                parts.append(
                    String(
                        format: NSLocalizedString("local_import_result_failed", comment: ""),
                        locale: Locale.current,
                        failedItems.count
                    )
                )
            }
            if matchedMetadataCount > 0 {
                parts.append(
                    String(
                        format: NSLocalizedString("local_import_result_metadata_matched", comment: ""),
                        locale: Locale.current,
                        matchedMetadataCount
                    )
                )
            }
            if prefetchedLyricsCount > 0 {
                parts.append(
                    String(
                        format: NSLocalizedString("local_import_result_lyrics_prefetched", comment: ""),
                        locale: Locale.current,
                        prefetchedLyricsCount
                    )
                )
            }
            let summary = parts.joined(separator: "，")
            guard !notices.isEmpty else { return summary }
            if summary.isEmpty {
                return notices.joined(separator: "\n")
            }
            return ([summary] + notices).joined(separator: "\n")
        }
    }

    /// 导入过程的实时进度快照，驱动 `LocalImportProgressPanel` 的 UI 展示。
    struct ImportProgress {
        var title: String
        var phaseText: String
        var detailText: String?
        var processedItems: Int
        var totalItems: Int
        var importedCount: Int
        var skippedCount: Int
        var failedCount: Int
        var matchedMetadataCount: Int
        var prefetchedLyricsCount: Int
        var isCompleted: Bool

        var fraction: Double {
            guard totalItems > 0 else { return 0 }
            return min(max(Double(processedItems) / Double(totalItems), 0), 1)
        }

        var countText: String {
            guard totalItems > 0 else { return "" }
            return "\(processedItems)/\(totalItems)"
        }
    }

    // MARK: - 状态

    @Published private(set) var songs: [Song] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var lastImportResult: ImportResult?
    @Published private(set) var importProgress: ImportProgress?

    // MARK: - 在线元数据匹配模型

    /// 单个本地文件解析+在线补全后的产物。
    private struct LocalSongImportPayload {
        let song: Song
        let matchedMetadata: Bool
        let prefetchedLyrics: Bool
    }

    /// 某个平台的最佳匹配歌曲及其综合相似度得分（0~1）。
    private struct OnlineMetadataMatch {
        let song: Song
        let score: Double
    }

    /// 三平台匹配结果中被选定的主来源，用于决定元数据和歌词取自哪个平台。
    private struct OnlineMetadataSelection {
        let match: OnlineMetadataMatch
        let source: MusicSource
    }

    /// 一组"标题 + 歌手"搜索关键词候选，来自内嵌元数据、文件名推断等多个渠道。
    private struct MetadataSearchCandidate: Hashable {
        let title: String
        let artist: String

        var query: String {
            [effectiveArtistName(artist), title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private typealias OnlineMetadataMatches = (netease: OnlineMetadataMatch?, qq: OnlineMetadataMatch?, qishui: OnlineMetadataMatch?)

    // MARK: - 目录与常量

    /// 本地音乐根目录：`Documents/LocalMusic`，不存在时自动创建。
    nonisolated static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("LocalMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 音频文件存放目录：`LocalMusic/Library`。
    nonisolated static var musicDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 内嵌封面导出目录：`LocalMusic/Artwork`，按 `<songID>.artwork` 命名。
    nonisolated static var artworkDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// 曲库清单文件，持久化整份 `[Song]` 列表。
    nonisolated private static var manifestURL: URL {
        rootDirectory.appendingPathComponent("library.json")
    }

    nonisolated static let importableContentTypes: [UTType] = [.audio, .folder]

    private static let supportedExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "flac", "m4a", "m4b", "mp3", "ogg", "opus", "wav"
    ]

    /// 在线匹配的接受阈值：歌手已知时综合分 ≥ 0.78 即接受；歌手未知时提高到 0.88 以降低误匹配。
    private static let onlineMetadataMatchThreshold = 0.78
    private static let unknownArtistMetadataMatchThreshold = 0.88
    /// 标题与歌手的单项最低分，低于则直接淘汰候选。
    private static let minimumTitleMatchScore = 0.72
    private static let minimumKnownArtistMatchScore = 0.42

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var progressDismissTask: Task<Void, Never>?

    private init() {
        loadManifest()
    }

    var songCount: Int {
        songs.count
    }

    // MARK: - 进度面板管理

    private func beginImportProgress(title: String, phase: String, detail: String?, totalItems: Int) {
        progressDismissTask?.cancel()
        progressDismissTask = nil
        importProgress = ImportProgress(
            title: title,
            phaseText: phase,
            detailText: detail,
            processedItems: 0,
            totalItems: totalItems,
            importedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            matchedMetadataCount: 0,
            prefetchedLyricsCount: 0,
            isCompleted: false
        )
    }

    private func updateImportProgress(
        phase: String? = nil,
        detail: String? = nil,
        processedItems: Int? = nil,
        totalItems: Int? = nil,
        result: ImportResult? = nil
    ) {
        guard var progress = importProgress else { return }
        if let phase {
            progress.phaseText = phase
        }
        if let detail {
            progress.detailText = detail
        }
        if let processedItems {
            progress.processedItems = processedItems
        }
        if let totalItems {
            progress.totalItems = max(totalItems, progress.totalItems)
        }
        if let result {
            progress.importedCount = result.importedCount
            progress.skippedCount = result.skippedCount
            progress.failedCount = result.failedItems.count
            progress.matchedMetadataCount = result.matchedMetadataCount
            progress.prefetchedLyricsCount = result.prefetchedLyricsCount
        }
        importProgress = progress
    }

    /// 标记进度完成，并在 6 秒后自动收起进度面板（期间有新任务则取消收起）。
    private func completeImportProgress(title: String, result: ImportResult, totalItems: Int) {
        importProgress = ImportProgress(
            title: title,
            phaseText: String(localized: "common_done"),
            detailText: result.summaryText,
            processedItems: max(totalItems, result.importedCount + result.skippedCount + result.failedItems.count),
            totalItems: max(totalItems, result.importedCount + result.skippedCount + result.failedItems.count),
            importedCount: result.importedCount,
            skippedCount: result.skippedCount,
            failedCount: result.failedItems.count,
            matchedMetadataCount: result.matchedMetadataCount,
            prefetchedLyricsCount: result.prefetchedLyricsCount,
            isCompleted: true
        )

        progressDismissTask?.cancel()
        progressDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            guard self?.importProgress?.isCompleted == true else { return }
            self?.importProgress = nil
        }
    }

    // MARK: - 导入与扫描

    /// 从用户选择的文件/文件夹 URL 导入音频。
    /// 逐个拷贝进曲库目录、解析元数据并尝试在线补全，全程更新进度面板。
    func importItems(from urls: [URL]) async -> ImportResult {
        guard !isProcessing else {
            var result = ImportResult()
            result.notices.append(String(localized: "已有导入任务正在进行"))
            return result
        }

        isProcessing = true
        defer { isProcessing = false }

        var result = ImportResult()
        var nextSongs = songs
        let existingPaths = Set(nextSongs.compactMap(\.localRelativePath))
        var processedItems = 0
        var totalItems = max(urls.count, 1)

        beginImportProgress(
            title: String(localized: "导入本地音乐"),
            phase: String(localized: "准备文件"),
            detail: String(localized: "正在读取选择的音乐文件"),
            totalItems: totalItems
        )

        for rootURL in urls {
            let accessGranted = rootURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    rootURL.stopAccessingSecurityScopedResource()
                }
            }

            updateImportProgress(
                phase: String(localized: "扫描文件"),
                detail: rootURL.lastPathComponent
            )
            let candidates = Self.collectImportableFiles(from: rootURL)
            totalItems = max(totalItems, processedItems + candidates.count)
            updateImportProgress(totalItems: totalItems, result: result)

            if candidates.isEmpty {
                result.skippedCount += 1
                processedItems += 1
                updateImportProgress(
                    phase: String(localized: "跳过"),
                    detail: rootURL.lastPathComponent,
                    processedItems: processedItems,
                    result: result
                )
                continue
            }

            for candidate in candidates {
                do {
                    updateImportProgress(
                        phase: String(localized: "复制文件"),
                        detail: candidate.lastPathComponent,
                        processedItems: processedItems,
                        totalItems: totalItems,
                        result: result
                    )
                    let destinationURL = try Self.copyToLibrary(candidate)
                    let relativePath = destinationURL.lastPathComponent

                    if existingPaths.contains(relativePath) || nextSongs.contains(where: { $0.localRelativePath == relativePath }) {
                        result.skippedCount += 1
                        processedItems += 1
                        updateImportProgress(
                            phase: String(localized: "跳过已存在"),
                            detail: candidate.lastPathComponent,
                            processedItems: processedItems,
                            result: result
                        )
                        continue
                    }

                    updateImportProgress(
                        phase: String(localized: "匹配封面和歌词"),
                        detail: candidate.lastPathComponent,
                        processedItems: processedItems,
                        result: result
                    )
                    let payload = try await Self.makeLocalSongImportPayload(from: destinationURL, relativePath: relativePath)
                    let song = payload.song
                    nextSongs.append(song)
                    result.importedSongs.append(song)
                    result.importedCount += 1
                    if payload.matchedMetadata {
                        result.matchedMetadataCount += 1
                    }
                    if payload.prefetchedLyrics {
                        result.prefetchedLyricsCount += 1
                    }
                    processedItems += 1
                    updateImportProgress(
                        phase: payload.matchedMetadata ? String(localized: "已匹配") : String(localized: "已导入"),
                        detail: song.name,
                        processedItems: processedItems,
                        result: result
                    )
                } catch {
                    result.failedItems.append(candidate.lastPathComponent)
                    processedItems += 1
                    updateImportProgress(
                        phase: String(localized: "导入失败"),
                        detail: candidate.lastPathComponent,
                        processedItems: processedItems,
                        result: result
                    )
                    AppLogger.error("本地音乐导入失败: \(candidate.lastPathComponent), error=\(error.localizedDescription)")
                }
            }
        }

        updateImportProgress(
            phase: String(localized: "保存曲库"),
            detail: String(localized: "正在更新本地音乐列表"),
            processedItems: processedItems,
            result: result
        )
        applyLibrarySongs(nextSongs)
        lastImportResult = result
        completeImportProgress(
            title: String(localized: "导入完成"),
            result: result,
            totalItems: totalItems
        )
        return result
    }

    /// 全量重建曲库：先吸收 App 文稿目录与系统媒体库中的音频，再按 Library 目录现存文件重新生成歌曲列表。
    func scanLibrary() async -> ImportResult {
        guard !isProcessing else {
            var result = ImportResult()
            result.notices.append(String(localized: "已有导入任务正在进行"))
            return result
        }

        isProcessing = true
        defer { isProcessing = false }

        beginImportProgress(
            title: String(localized: "扫描本地音乐"),
            phase: String(localized: "准备扫描"),
            detail: String(localized: "正在检查 App 文稿和系统媒体库"),
            totalItems: 1
        )

        var result = ImportResult()
        updateImportProgress(
            phase: String(localized: "扫描 App 文稿"),
            detail: String(localized: "查找可导入音频")
        )
        let sharedImportResult = await importSharedDocumentAudio()
        result.skippedCount += sharedImportResult.skippedCount
        result.failedItems.append(contentsOf: sharedImportResult.failedItems)
        result.notices.append(contentsOf: sharedImportResult.notices)

        updateImportProgress(
            phase: String(localized: "读取系统媒体库"),
            detail: String(localized: "同步本机可访问音频"),
            result: result
        )
        let mediaImportResult = await importSystemMediaLibraryAudio()
        result.skippedCount += mediaImportResult.skippedCount
        result.failedItems.append(contentsOf: mediaImportResult.failedItems)
        result.notices.append(contentsOf: mediaImportResult.notices)

        let files = Self.collectImportableFiles(from: Self.musicDirectory)
        var processedItems = 0
        let totalItems = max(files.count, 1)
        updateImportProgress(
            phase: String(localized: "匹配封面和歌词"),
            detail: files.first?.lastPathComponent ?? String(localized: "整理本地曲库"),
            processedItems: processedItems,
            totalItems: totalItems,
            result: result
        )
        var rebuilt: [Song] = []

        for file in files {
            do {
                updateImportProgress(
                    phase: String(localized: "匹配封面和歌词"),
                    detail: file.lastPathComponent,
                    processedItems: processedItems,
                    totalItems: totalItems,
                    result: result
                )
                let payload = try await Self.makeLocalSongImportPayload(from: file, relativePath: file.lastPathComponent)
                rebuilt.append(payload.song)
                if payload.matchedMetadata {
                    result.matchedMetadataCount += 1
                }
                if payload.prefetchedLyrics {
                    result.prefetchedLyricsCount += 1
                }
                processedItems += 1
                updateImportProgress(
                    phase: payload.matchedMetadata ? String(localized: "已匹配") : String(localized: "已扫描"),
                    detail: payload.song.name,
                    processedItems: processedItems,
                    result: result
                )
            } catch {
                result.failedItems.append(file.lastPathComponent)
                processedItems += 1
                updateImportProgress(
                    phase: String(localized: "扫描失败"),
                    detail: file.lastPathComponent,
                    processedItems: processedItems,
                    result: result
                )
                AppLogger.error("扫描本地曲库失败: \(file.lastPathComponent), error=\(error.localizedDescription)")
            }
        }

        updateImportProgress(
            phase: String(localized: "保存曲库"),
            detail: String(localized: "正在更新本地音乐列表"),
            processedItems: processedItems,
            result: result
        )
        applyLibrarySongs(rebuilt)
        result.importedCount = rebuilt.count
        lastImportResult = result
        completeImportProgress(
            title: String(localized: "local_scan_complete_title"),
            result: result,
            totalItems: totalItems
        )
        return result
    }

    // MARK: - 删除与持久化

    func deleteSong(_ song: Song) {
        deleteSongs([song])
    }

    /// 删除本地歌曲：连带清理音频文件、封面文件与歌词缓存，仅对 `.local` 来源生效。
    func deleteSongs(_ songsToDelete: [Song]) {
        let localSongs = songsToDelete.filter { $0.musicSource == .local }
        guard !localSongs.isEmpty else { return }

        var removedIds = Set<Int>()

        for song in localSongs {
            guard let relativePath = song.localRelativePath else { continue }

            let fileURL = Self.musicDirectory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }

            let artworkURL = Self.artworkDirectory.appendingPathComponent("\(song.id).artwork")
            if FileManager.default.fileExists(atPath: artworkURL.path) {
                try? FileManager.default.removeItem(at: artworkURL)
            }

            OptimizedCacheManager.shared.removeLyrics(songId: song.id, source: .local)
            removedIds.insert(song.id)
        }

        guard !removedIds.isEmpty else { return }
        applyLibrarySongs(songs.filter { !removedIds.contains($0.id) })
    }

    func reload() {
        loadManifest()
    }

    /// 应用新的曲目列表：按 id 去重、按导入时间倒序排序，随后持久化并同步本地歌单。
    private func applyLibrarySongs(_ inputSongs: [Song]) {
        let deduplicated = Dictionary(grouping: inputSongs, by: \.id)
            .compactMap { $0.value.first }
            .sorted { lhs, rhs in
                let lhsDate = lhs.localImportedAt ?? .distantPast
                let rhsDate = rhs.localImportedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        songs = deduplicated
        persist()
        LocalPlaylistManager.shared.syncLocalMusicPlaylist(with: deduplicated)
        pruneMissingLocalSongsFromPlaylists(validSongIDs: Set(deduplicated.map(\.id)))
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: Self.manifestURL),
              let storedSongs = try? decoder.decode([Song].self, from: data) else {
            songs = []
            return
        }

        songs = storedSongs.sorted { lhs, rhs in
            let lhsDate = lhs.localImportedAt ?? .distantPast
            let rhsDate = rhs.localImportedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(songs)
            try data.write(to: Self.manifestURL, options: [.atomic])
        } catch {
            AppLogger.error("保存本地曲库失败: \(error.localizedDescription)")
        }
    }

    /// 从所有本地歌单中移除已不存在于曲库的本地歌曲引用。
    private func pruneMissingLocalSongsFromPlaylists(validSongIDs: Set<Int>) {
        let manager = LocalPlaylistManager.shared

        for playlist in manager.playlists {
            let missingLocalSongIds = Set(manager.songs(for: playlist).filter {
                $0.musicSource == .local && !validSongIDs.contains($0.id)
            }.map(\.identityKey))

            manager.removeSongs(ids: missingLocalSongIds, from: playlist)
        }
    }

    // MARK: - 文件收集与拷贝

    /// 递归收集 URL 下所有受支持的音频文件；传入单个文件时直接校验其扩展名。
    private static func collectImportableFiles(from rootURL: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            return isSupportedAudioFile(rootURL) ? [rootURL] : []
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var urls: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            if isSupportedAudioFile(item) {
                urls.append(item)
            }
        }

        return urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 收集 Documents 下可导入的音频，但排除曲库自身目录和下载目录，避免重复导入。
    private static func collectSharedDocumentFiles() -> [URL] {
        let excludedDirectories = [rootDirectory, DownloadedSong.downloadsDirectory]

        return collectImportableFiles(from: documentsDirectory).filter { url in
            !excludedDirectories.contains { excluded in
                isDescendant(url, of: excluded)
            }
        }
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let normalizedDirectory = directory.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedURL = url.standardizedFileURL.path
        return normalizedURL == directory.standardizedFileURL.path
            || normalizedURL.hasPrefix("/\(normalizedDirectory)/")
            || normalizedURL.hasPrefix(directory.standardizedFileURL.path + "/")
    }

    private static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && supportedExtensions.contains(ext)
    }

    /// 拷贝文件到曲库目录；同名文件通过追加 " (2)"、" (3)" 后缀避让。
    private static func copyToLibrary(_ sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension
        let baseName = sanitizedFileNameComponent(sourceURL.deletingPathExtension().lastPathComponent)

        var destination = musicDirectory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var index = 2

        while fileManager.fileExists(atPath: destination.path) {
            destination = musicDirectory
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension(ext)
            index += 1
        }

        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    // MARK: - App 文稿与系统媒体库吸收

    /// 把 App 文稿目录（如"用 Mono 打开"传入的文件）中的音频复制进曲库。
    private func importSharedDocumentAudio() async -> ImportResult {
        var result = ImportResult()
        let files = Self.collectSharedDocumentFiles()

        for file in files {
            do {
                let (_, isNewFile) = try Self.ensureScannedFileInLibrary(
                    from: file,
                    stableKey: "docs:\(file.standardizedFileURL.path)"
                )
                if !isNewFile {
                    result.skippedCount += 1
                }
            } catch {
                result.failedItems.append(file.lastPathComponent)
                AppLogger.error("扫描 App 文稿音频失败: \(file.lastPathComponent), error=\(error.localizedDescription)")
            }
        }

        return result
    }

    /// 把系统媒体库中本机可访问（非云端）的歌曲导出/复制进曲库，需要媒体库授权。
    private func importSystemMediaLibraryAudio() async -> ImportResult {
        var result = ImportResult()

        let status = await requestMediaLibraryAuthorizationIfNeeded()
        guard status == .authorized else {
            result.notices.append(NSLocalizedString("local_scan_notice_media_denied", comment: ""))
            return result
        }

        let items = MPMediaQuery.songs().items ?? []
        for item in items {
            let isCloudItem = (item.value(forProperty: MPMediaItemPropertyIsCloudItem) as? Bool) ?? false
            guard !isCloudItem, let assetURL = item.assetURL else {
                result.skippedCount += 1
                continue
            }

            do {
                let (_, isNewFile) = try await Self.ensureMediaItemInLibrary(item, assetURL: assetURL)
                if !isNewFile {
                    result.skippedCount += 1
                }
            } catch {
                result.failedItems.append(item.title ?? assetURL.lastPathComponent)
                AppLogger.error("导入系统媒体库失败: \(item.title ?? assetURL.lastPathComponent), error=\(error.localizedDescription)")
            }
        }

        return result
    }

    private func requestMediaLibraryAuthorizationIfNeeded() async -> MPMediaLibraryAuthorizationStatus {
        let current = MPMediaLibrary.authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// 确保外部文件在曲库中存在一份拷贝；用 stableKey 生成稳定文件名，重复扫描不会产生副本。
    private static func ensureScannedFileInLibrary(from sourceURL: URL, stableKey: String) throws -> (url: URL, isNewFile: Bool) {
        let baseName = sanitizedFileNameComponent(sourceURL.deletingPathExtension().lastPathComponent)
        let ext = normalizedAudioExtension(sourceURL.pathExtension)
        let destination = managedLibraryDestinationURL(baseName: baseName, stableKey: stableKey, fileExtension: ext)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return (destination, false)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return (destination, true)
    }

    /// 确保媒体库条目在曲库中存在拷贝：本地文件直接复制，DRM-free 的流式资源走 AVAssetExportSession 导出。
    private static func ensureMediaItemInLibrary(_ item: MPMediaItem, assetURL: URL) async throws -> (url: URL, isNewFile: Bool) {
        let title = sanitizedFileNameComponent(item.title ?? assetURL.deletingPathExtension().lastPathComponent)
        let ext = normalizedAudioExtension(assetURL.pathExtension.isEmpty ? "m4a" : assetURL.pathExtension)
        let stableKey = "media:\(item.persistentID)"
        let destination = managedLibraryDestinationURL(baseName: title, stableKey: stableKey, fileExtension: ext)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return (destination, false)
        }

        if assetURL.isFileURL {
            try FileManager.default.copyItem(at: assetURL, to: destination)
            return (destination, true)
        }

        let asset = AVURLAsset(url: assetURL)
        let exportedURL = try await exportMediaAsset(asset, fallbackURL: destination)
        return (exportedURL, true)
    }

    /// 生成带稳定哈希后缀的目标路径（`名称-xxxxxxxx.ext`），保证同一来源多次扫描落到同一文件。
    private static func managedLibraryDestinationURL(baseName: String, stableKey: String, fileExtension: String) -> URL {
        let token = stableToken(for: stableKey)
        let safeBaseName = sanitizedFileNameComponent(baseName)
        let decoratedBase = "\(safeBaseName)-\(token.prefix(8))"
        return musicDirectory
            .appendingPathComponent(decoratedBase)
            .appendingPathExtension(fileExtension)
    }

    private static func normalizedAudioExtension(_ fileExtension: String) -> String {
        let lowercased = fileExtension.lowercased()
        return supportedExtensions.contains(lowercased) ? lowercased : "m4a"
    }

    /// FNV-1a 哈希生成稳定短 token，用于文件名去重后缀。
    private static func stableToken(for key: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16, uppercase: false)
    }

    /// 导出媒体库资源：优先 Passthrough（保留原始编码），不支持时回退到 AppleM4A 转码。
    private static func exportMediaAsset(_ asset: AVAsset, fallbackURL: URL) async throws -> URL {
        let passthroughExporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)

        let exporter: AVAssetExportSession
        let outputType: AVFileType

        if let passthroughExporter,
           let passthroughType = preferredPassthroughFileType(from: passthroughExporter.supportedFileTypes) {
            exporter = passthroughExporter
            outputType = passthroughType
        } else {
            guard let fallbackExporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw NSError(domain: "LocalMusicLibrary", code: -10, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "无法导出系统媒体库音频")
                ])
            }
            exporter = fallbackExporter
            outputType = fallbackExporter.supportedFileTypes.contains(.m4a)
                ? .m4a
                : (fallbackExporter.supportedFileTypes.first ?? .m4a)
        }

        let finalURL = fallbackURL
            .deletingPathExtension()
            .appendingPathExtension(fileExtension(for: outputType))

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }

        exporter.outputURL = finalURL
        exporter.outputFileType = outputType
        exporter.shouldOptimizeForNetworkUse = false

        let sendableExporter = SendableAVAssetExportSession(session: exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendableExporter.session.exportAsynchronously {
                let exporter = sendableExporter.session
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? NSError(domain: "LocalMusicLibrary", code: -11))
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "LocalMusicLibrary", code: -12, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "系统媒体库导出已取消")
                    ]))
                default:
                    continuation.resume(throwing: NSError(domain: "LocalMusicLibrary", code: -13, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "系统媒体库导出失败")
                    ]))
                }
            }
        }

        return finalURL
    }

    private static func preferredPassthroughFileType(from fileTypes: [AVFileType]) -> AVFileType? {
        let preferredTypes: [AVFileType] = [.m4a, .mp3, .wav, .aiff, .caf]
        for type in preferredTypes where fileTypes.contains(type) {
            return type
        }
        return nil
    }

    private static func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .m4a: return "m4a"
        case .mp3: return "mp3"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .caf: return "caf"
        case .mov: return "mov"
        case .mp4: return "mp4"
        default: return "m4a"
        }
    }

    /// 清理文件名中的非法字符与首尾空格/点号，空结果回退为 "Local Track"。
    private static func sanitizedFileNameComponent(_ text: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
            .union(.illegalCharacters)

        let cleaned = text
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))

        return cleaned.isEmpty ? "Local Track" : cleaned
    }

    // MARK: - 元数据解析与在线补全

    /// 解析音频文件的内嵌元数据构造 `Song`（id 由相对路径哈希生成，恒为负数以避免与在线曲目冲突），
    /// 随后尝试在线匹配补全封面、专辑、歌手信息与歌词。
    private static func makeLocalSongImportPayload(from fileURL: URL, relativePath: String) async throws -> LocalSongImportPayload {
        let asset = AVURLAsset(url: fileURL)
        let duration = try? await asset.load(.duration)
        let commonMetadata = try? await asset.load(.commonMetadata)
        let metadata = (commonMetadata ?? []) + ((try? await asset.load(.metadata)) ?? [])

        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let inferred = inferredMetadata(from: fileName)
        let metadataTitle = await metadataValue(for: metadata, identifier: .commonIdentifierTitle)
        let metadataArtist = await metadataValue(for: metadata, identifier: .commonIdentifierArtist)
        let title = metadataTitle ?? inferred.title
        let artistName = metadataArtist
            ?? inferred.artist
            ?? "Unknown Artist"
        let albumName = await metadataValue(for: metadata, identifier: .commonIdentifierAlbumName) ?? "Local Library"

        let durationMs: Int?
        if let duration {
            let seconds = CMTimeGetSeconds(duration)
            durationMs = seconds.isFinite ? Int(seconds * 1000) : nil
        } else {
            durationMs = nil
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let importedAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? Date()
        let songID = stableSongID(for: relativePath)
        let artistID = stableSongID(for: "artist:\(artistName)")
        let albumID = stableSongID(for: "album:\(albumName)")
        let embeddedArtworkURL = await embeddedArtworkURL(from: metadata, songID: songID)
        let embeddedLyrics = await embeddedLyrics(from: metadata)

        let localSong = Song(
            id: songID,
            name: title,
            ar: [Artist(id: artistID, name: artistName)],
            al: Album(id: albumID, name: albumName, picUrl: embeddedArtworkURL?.absoluteString),
            dt: durationMs,
            fee: nil,
            mv: nil,
            h: nil,
            m: nil,
            l: nil,
            sq: nil,
            hr: nil,
            alia: nil,
            privilege: nil,
            source: .local,
            qqMid: nil,
            qqAlbumMid: nil,
            qqArtistMid: nil,
            qqMaxQuality: nil,
            localRelativePath: relativePath,
            localImportedAt: importedAt,
            genreTags: await SongGenreMetadata.localTags(in: metadata)
        )

        let searchCandidates = metadataSearchCandidates(
            fileName: fileName,
            metadataTitle: metadataTitle,
            metadataArtist: metadataArtist,
            fallbackTitle: title,
            fallbackArtist: artistName
        )

        return await enrichLocalSong(
            localSong,
            embeddedArtworkURL: embeddedArtworkURL,
            embeddedLyrics: embeddedLyrics,
            searchCandidates: searchCandidates
        )
    }

    /// 从文件名推断标题与歌手：去掉序号前缀后按 "歌手 - 标题" 形式的分隔符拆分。
    private static func inferredMetadata(from fileName: String) -> (title: String, artist: String?) {
        let cleaned = fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\s*[-.、_]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for separator in [" - ", " – ", " — "] {
            let parts = cleaned.components(separatedBy: separator)
            if parts.count >= 2 {
                let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                if !artist.isEmpty, !title.isEmpty {
                    return (title, artist)
                }
            }
        }

        return (cleaned.isEmpty ? "Local Track" : cleaned, nil)
    }

    /// 提取内嵌封面并写入 Artwork 目录，返回本地文件 URL。
    private static func embeddedArtworkURL(from metadata: [AVMetadataItem]?, songID: Int) async -> URL? {
        guard let item = AVMetadataItem.metadataItems(from: metadata ?? [], filteredByIdentifier: .commonIdentifierArtwork).first,
              let data = try? await item.load(.dataValue),
              !data.isEmpty else {
            return nil
        }

        let destination = artworkDirectory.appendingPathComponent("\(songID).artwork")
        do {
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            AppLogger.warning("本地音乐封面写入失败: \(error.localizedDescription)")
            return nil
        }
    }

    private static func embeddedLyrics(from metadata: [AVMetadataItem]?) async -> String? {
        for item in metadata ?? [] where isLyricsMetadataItem(item) {
            guard let value = try? await item.load(.stringValue) else { continue }
            let normalized = normalizedEmbeddedLyrics(value)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private static func isLyricsMetadataItem(_ item: AVMetadataItem) -> Bool {
        let identifier = item.identifier?.rawValue.lowercased() ?? ""
        let commonKey = item.commonKey?.rawValue.lowercased() ?? ""
        let key = item.key.map { "\($0)".lowercased() } ?? ""
        return identifier.contains("lyric")
            || commonKey.contains("lyric")
            || key.contains("lyric")
            || key == "uslt"
            || key == "sylt"
    }

    /// 归一化内嵌歌词：已带 LRC 时间戳则原样返回；纯文本则按每行 5 秒生成伪时间戳以便滚动显示。
    private static func normalizedEmbeddedLyrics(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil {
            return trimmed
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return trimmed }
        return lines.enumerated().map { index, line in
            let seconds = Double(index) * 5.0
            let minutes = Int(seconds) / 60
            let remainingSeconds = seconds - Double(minutes * 60)
            return String(format: "[%02d:%05.2f]%@", locale: Locale(identifier: "en_US_POSIX"), minutes, remainingSeconds, line)
        }.joined(separator: "\n")
    }

    /// 在线补全入口：并发查询三平台取最佳匹配，合并元数据并预取歌词。
    /// 内嵌歌词优先于在线歌词（overwrite: true 覆盖旧缓存）。
    private static func enrichLocalSong(
        _ song: Song,
        embeddedArtworkURL: URL?,
        embeddedLyrics: String?,
        searchCandidates: [MetadataSearchCandidate]
    ) async -> LocalSongImportPayload {
        let candidates = searchCandidates.isEmpty
            ? [MetadataSearchCandidate(title: song.name, artist: song.artistName)]
            : searchCandidates

        guard candidates.contains(where: { !$0.query.isEmpty }) else {
            return LocalSongImportPayload(song: song, matchedMetadata: false, prefetchedLyrics: cacheEmbeddedLyrics(embeddedLyrics, localSongId: song.id))
        }

        let matches = await bestOnlineMatches(for: candidates, durationMs: song.dt)
        let primarySelection = bestSelection(from: matches)
        let enrichedSong = applyOnlineMetadata(
            to: song,
            primarySelection: primarySelection,
            neteaseSong: matches.netease?.song,
            qqSong: matches.qq?.song,
            qishuiSong: matches.qishui?.song,
            embeddedArtworkURL: embeddedArtworkURL
        )

        var prefetchedLyrics = cacheEmbeddedLyrics(embeddedLyrics, localSongId: enrichedSong.id, overwrite: true)
        if !prefetchedLyrics {
            prefetchedLyrics = await prefetchLyrics(
                for: enrichedSong,
                primarySelection: primarySelection,
                neteaseSong: matches.netease?.song,
                qqSong: matches.qq?.song,
                qishuiSong: matches.qishui?.song
            )
        }
        if !prefetchedLyrics, primarySelection == nil, embeddedLyrics == nil {
            OptimizedCacheManager.shared.removeLyrics(songId: enrichedSong.id, source: .local)
        }

        return LocalSongImportPayload(
            song: enrichedSong,
            matchedMetadata: primarySelection != nil,
            prefetchedLyrics: prefetchedLyrics
        )
    }

    /// 依次用各候选关键词并发搜索三平台，保留各平台历史最高分；任一平台得分 ≥ 0.96 即提前结束。
    private static func bestOnlineMatches(
        for candidates: [MetadataSearchCandidate],
        durationMs: Int?
    ) async -> OnlineMetadataMatches {
        var best: OnlineMetadataMatches = (nil, nil, nil)

        for candidate in candidates.prefix(4) where !candidate.query.isEmpty {
            async let neteaseMatch = fetchNeteaseMetadataMatch(
                query: candidate.query,
                title: candidate.title,
                artist: candidate.artist,
                durationMs: durationMs
            )
            async let qqMatch = fetchQQMetadataMatch(
                query: candidate.query,
                title: candidate.title,
                artist: candidate.artist,
                durationMs: durationMs
            )
            async let qishuiMatch = fetchQishuiMetadataMatch(
                query: candidate.query,
                title: candidate.title,
                artist: candidate.artist,
                durationMs: durationMs
            )
            let result = await (netease: neteaseMatch, qq: qqMatch, qishui: qishuiMatch)

            best.netease = strongerMatch(best.netease, result.netease)
            best.qq = strongerMatch(best.qq, result.qq)
            best.qishui = strongerMatch(best.qishui, result.qishui)

            if let selection = bestSelection(from: best), selection.match.score >= 0.96 {
                break
            }
        }

        return best
    }

    private static func bestSelection(from matches: OnlineMetadataMatches) -> OnlineMetadataSelection? {
        [
            matches.netease.map { OnlineMetadataSelection(match: $0, source: .netease) },
            matches.qq.map { OnlineMetadataSelection(match: $0, source: .qqmusic) },
            matches.qishui.map { OnlineMetadataSelection(match: $0, source: .qishui) }
        ]
        .compactMap { $0 }
        .max { $0.match.score < $1.match.score }
    }

    private static func strongerMatch(_ lhs: OnlineMetadataMatch?, _ rhs: OnlineMetadataMatch?) -> OnlineMetadataMatch? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.score >= rhs.score ? lhs : rhs
    }

    private static func fetchNeteaseMetadataMatch(query: String, title: String, artist: String, durationMs: Int?) async -> OnlineMetadataMatch? {
        do {
            let candidates = try await APIService.shared.searchSongs(keyword: query, offset: 0).async()
            return bestMetadataMatch(from: candidates, title: title, artist: artist, durationMs: durationMs)
        } catch {
            AppLogger.warning("本地音乐 NCM 元数据匹配失败: \(query), error=\(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchQQMetadataMatch(query: String, title: String, artist: String, durationMs: Int?) async -> OnlineMetadataMatch? {
        do {
            let candidates = try await APIService.shared.searchQQSongs(keyword: query, page: 1, num: 10).async()
            return bestMetadataMatch(from: candidates, title: title, artist: artist, durationMs: durationMs)
        } catch {
            AppLogger.warning("本地音乐 QCM 元数据匹配失败: \(query), error=\(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchQishuiMetadataMatch(query: String, title: String, artist: String, durationMs: Int?) async -> OnlineMetadataMatch? {
        do {
            let candidates = try await APIService.shared.searchQishuiSongs(keyword: query, page: 0).async()
            return bestMetadataMatch(from: Array(candidates.prefix(10)), title: title, artist: artist, durationMs: durationMs)
        } catch {
            AppLogger.warning("本地音乐 Qishui 元数据匹配失败: \(query), error=\(error.localizedDescription)")
            return nil
        }
    }

    /// 在搜索结果中挑选最佳匹配。
    /// 综合得分 = 标题相似度 + 歌手相似度 + 时长接近度 的加权和；
    /// 歌手未知时权重转移到标题与时长，且要求更高的接受阈值。
    private static func bestMetadataMatch(from songs: [Song], title: String, artist: String, durationMs: Int?) -> OnlineMetadataMatch? {
        let normalizedTitle = normalizeMatchText(title)
        let normalizedArtist = normalizeMatchText(effectiveArtistName(artist))
        let hasKnownArtist = !normalizedArtist.isEmpty

        var bestMatch: Song?
        var bestScore = 0.0

        for song in songs {
            let titleScore = similarityScore(normalizedTitle, normalizeMatchText(song.name))
            guard titleScore >= minimumTitleMatchScore else { continue }

            let artistScore = hasKnownArtist
                ? similarityScore(normalizedArtist, normalizeMatchText(song.artistName))
                : 1.0
            if hasKnownArtist, artistScore < minimumKnownArtistMatchScore {
                continue
            }

            let exactDurationScore = durationMatchScore(localDurationMs: durationMs, remoteDurationMs: song.dt)
            if let exactDurationScore, exactDurationScore < 0.35 {
                continue
            }
            if !hasKnownArtist, exactDurationScore == nil, titleScore < 0.96 {
                continue
            }

            let durationScore = exactDurationScore ?? (hasKnownArtist ? 0.72 : 0.0)
            let totalScore = hasKnownArtist
                ? titleScore * 0.58 + artistScore * 0.27 + durationScore * 0.15
                : titleScore * 0.70 + durationScore * 0.30

            if totalScore > bestScore {
                bestScore = totalScore
                bestMatch = song
            }
        }

        let threshold = hasKnownArtist ? onlineMetadataMatchThreshold : unknownArtistMetadataMatchThreshold
        guard let bestMatch, bestScore >= threshold else { return nil }
        return OnlineMetadataMatch(song: bestMatch, score: bestScore)
    }

    /// 将在线匹配结果合并进本地 Song。
    /// 封面选取策略：高置信度（≥0.90）时优先在线封面，否则优先内嵌封面；
    /// 同时保留各平台 ID（qqMid、qishuiTrackId 等）以便后续跳转与歌词获取。
    private static func applyOnlineMetadata(
        to baseSong: Song,
        primarySelection: OnlineMetadataSelection?,
        neteaseSong: Song?,
        qqSong: Song?,
        qishuiSong: Song?,
        embeddedArtworkURL: URL?
    ) -> Song {
        guard primarySelection != nil || embeddedArtworkURL != nil else { return baseSong }

        let primarySong = primarySelection?.match.song
        let isHighConfidence = (primarySelection?.match.score ?? 0) >= 0.90
        let coverURL = firstNonEmpty(
            isHighConfidence ? primarySong?.coverUrl?.absoluteString : embeddedArtworkURL?.absoluteString,
            isHighConfidence ? neteaseSong?.coverUrl?.absoluteString : nil,
            isHighConfidence ? qqSong?.coverUrl?.absoluteString : nil,
            isHighConfidence ? qishuiSong?.coverUrl?.absoluteString : nil,
            isHighConfidence ? embeddedArtworkURL?.absoluteString : primarySong?.coverUrl?.absoluteString,
            isHighConfidence ? nil : neteaseSong?.coverUrl?.absoluteString,
            isHighConfidence ? nil : qqSong?.coverUrl?.absoluteString,
            isHighConfidence ? nil : qishuiSong?.coverUrl?.absoluteString,
            baseSong.coverUrl?.absoluteString
        )
        let albumName = firstNonEmpty(primarySong?.album?.name, baseSong.album?.name) ?? "Local Library"
        let albumID = primarySong?.album?.id ?? baseSong.album?.id ?? stableSongID(for: "album:\(albumName)")
        let artists = nonEmptyArtists(primarySong?.ar) ?? nonEmptyArtists(baseSong.ar) ?? [Artist(id: stableSongID(for: "artist:\(baseSong.artistName)"), name: baseSong.artistName)]

        var mergedSong = Song(
            id: baseSong.id,
            name: firstNonEmpty(primarySong?.name, baseSong.name) ?? baseSong.name,
            ar: artists,
            al: Album(id: albumID, name: albumName, picUrl: coverURL),
            dt: baseSong.dt ?? primarySong?.dt,
            fee: nil,
            mv: nil,
            h: nil,
            m: nil,
            l: nil,
            sq: nil,
            hr: nil,
            alia: baseSong.alia
        )

        mergedSong.source = .local
        mergedSong.qqMid = qqSong?.qqMid ?? baseSong.qqMid
        mergedSong.qqAlbumMid = qqSong?.qqAlbumMid ?? baseSong.qqAlbumMid
        mergedSong.qqArtistMid = qqSong?.qqArtistMid ?? baseSong.qqArtistMid
        mergedSong.qqMaxQuality = qqSong?.qqMaxQuality ?? baseSong.qqMaxQuality
        mergedSong.qishuiTrackId = qishuiSong?.qishuiTrackId ?? baseSong.qishuiTrackId
        mergedSong.localRelativePath = baseSong.localRelativePath
        mergedSong.localImportedAt = baseSong.localImportedAt
        mergedSong.genreTags = baseSong.genreTags
        return mergedSong
    }

    /// 按主匹配来源预取歌词并写入缓存，成功返回 true。
    private static func prefetchLyrics(
        for song: Song,
        primarySelection: OnlineMetadataSelection?,
        neteaseSong: Song?,
        qqSong: Song?,
        qishuiSong: Song?
    ) async -> Bool {
        guard let primarySelection else { return false }

        switch primarySelection.source {
        case .qishui:
            guard let qishuiTrackId = qishuiSong?.qishuiTrackId ?? primarySelection.match.song.qishuiTrackId else {
                return false
            }
            do {
                let content = try await APIService.shared.fetchQishuiLyric(trackId: qishuiTrackId).async()
                if cacheQishuiLyrics(content, localSongId: song.id) {
                    return true
                }
            } catch {
                AppLogger.warning("本地音乐 Qishui 歌词预取失败: \(song.name), error=\(error.localizedDescription)")
            }
            return false

        case .netease:
            let matchedSong = neteaseSong ?? primarySelection.match.song
            do {
                let response = try await APIService.shared.fetchLyric(id: matchedSong.id).async()
                if cacheNeteaseLyrics(response, localSongId: song.id) {
                    return true
                }
            } catch {
                AppLogger.warning("本地音乐 NCM 歌词预取失败: \(song.name), error=\(error.localizedDescription)")
            }
            return false

        case .qqmusic:
            guard let qqMid = firstNonEmpty(qqSong?.qqMid, primarySelection.match.song.qqMid) else {
                return false
            }
            do {
                let response = try await APIService.shared.fetchQQLyric(mid: qqMid).async()
                if cacheQQLyrics(response, localSongId: song.id) {
                    return true
                }
            } catch {
                AppLogger.warning("本地音乐 QCM 歌词预取失败: \(song.name), error=\(error.localizedDescription)")
            }
            return false

        case .kugou, .appleMusic, .local:
            return false
        }
    }

    // MARK: - 歌词缓存

    private static func cacheNeteaseLyrics(_ response: LyricResponse, localSongId: Int) -> Bool {
        guard let lyric = firstNonEmpty(response.yrc?.lyric, response.lrc?.lyric) else { return false }
        OptimizedCacheManager.shared.cacheLyrics(
            songId: localSongId, source: .local,
            lyrics: lyric,
            translated: firstNonEmpty(response.tlyric?.lyric)
        )
        return true
    }

    private static func cacheQQLyrics(_ response: QQLyricResponse, localSongId: Int) -> Bool {
        guard let lyric = firstNonEmpty(response.qrc, response.lyric) else { return false }
        OptimizedCacheManager.shared.cacheLyrics(
            songId: localSongId, source: .local,
            lyrics: lyric,
            translated: firstNonEmpty(response.trans, response.roma)
        )
        return true
    }

    private static func cacheQishuiLyrics(_ content: String, localSongId: Int) -> Bool {
        let lyric = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lyric.isEmpty else { return false }
        OptimizedCacheManager.shared.cacheLyrics(songId: localSongId, source: .local, lyrics: lyric)
        return true
    }

    private static func cacheEmbeddedLyrics(_ lyrics: String?, localSongId: Int, overwrite: Bool = false) -> Bool {
        guard (overwrite || OptimizedCacheManager.shared.getLyrics(songId: localSongId, source: .local) == nil),
              let lyrics,
              !lyrics.isEmpty else {
            return false
        }
        OptimizedCacheManager.shared.cacheLyrics(songId: localSongId, source: .local, lyrics: lyrics)
        return true
    }

    // MARK: - 搜索候选与相似度

    /// 组合多渠道（内嵌元数据、文件名推断、兜底值）生成去重后的搜索候选，最多被上层取前 4 个使用。
    private static func metadataSearchCandidates(
        fileName: String,
        metadataTitle: String?,
        metadataArtist: String?,
        fallbackTitle: String,
        fallbackArtist: String
    ) -> [MetadataSearchCandidate] {
        var candidates: [MetadataSearchCandidate] = []
        var seen = Set<String>()

        func append(title: String?, artist: String?) {
            let cleanedTitle = cleanedSearchTitle(title ?? "")
            let cleanedArtist = cleanedSearchArtist(artist ?? "")
            guard !cleanedTitle.isEmpty else { return }

            let key = "\(normalizeMatchText(cleanedTitle))|\(normalizeMatchText(cleanedArtist))"
            guard seen.insert(key).inserted else { return }
            candidates.append(MetadataSearchCandidate(title: cleanedTitle, artist: cleanedArtist))
        }

        append(title: metadataTitle, artist: metadataArtist)

        let inferred = inferredMetadata(from: fileName)
        append(title: inferred.title, artist: inferred.artist)

        append(title: fallbackTitle, artist: fallbackArtist)

        if let metadataTitle, metadataArtist == nil || metadataArtist?.isEmpty == true {
            append(title: metadataTitle, artist: nil)
        }

        return candidates
    }

    /// 清理搜索标题：移除扩展名、序号前缀、方括号标注及 "cover/伴奏/320k" 等质量标记。
    private static func cleanedSearchTitle(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?i)\.(mp3|m4a|flac|wav|aac|aiff|ogg|opus)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\s*[-.、_]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\((?:cover|伴奏|instrumental|karaoke|320k|flac|mp3|hq|sq|hi-?res)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"（(?:cover|伴奏|instrumental|karaoke|320k|flac|mp3|hq|sq|hi-?res)[^）]*）"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedSearchArtist(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return effectiveArtistName(cleaned)
    }

    /// 时长接近度评分：差值 ≤3 秒记满分，>30 秒记 0；任一侧缺时长则返回 nil（由调用方决定兜底权重）。
    private static func durationMatchScore(localDurationMs: Int?, remoteDurationMs: Int?) -> Double? {
        guard let localDurationMs,
              let remoteDurationMs,
              localDurationMs > 0,
              remoteDurationMs > 0 else {
            return nil
        }

        let diff = abs(Double(localDurationMs - remoteDurationMs)) / 1000.0
        switch diff {
        case 0...3:
            return 1.0
        case 3...8:
            return 0.88
        case 8...15:
            return 0.68
        case 15...30:
            return 0.42
        default:
            return 0.0
        }
    }

    /// "Unknown Artist" 视为无歌手信息，返回空串。
    nonisolated private static func effectiveArtistName(_ artist: String) -> String {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveCompare("Unknown Artist") == .orderedSame {
            return ""
        }
        return trimmed
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func nonEmptyArtists(_ artists: [Artist]?) -> [Artist]? {
        guard let artists, !artists.isEmpty else { return nil }
        let cleaned = artists.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 匹配前归一化：转小写并只保留字母数字与汉字，消除标点/空格差异。
    private static func normalizeMatchText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "\u{4E00}"..."\u{9FFF}")).inverted)
            .joined()
    }

    /// 文本相似度（0~1）：包含关系直接给高分；否则用最长公共子序列长度归一化，长度悬殊时提前返回低分。
    private static func similarityScore(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty && !rhs.isEmpty else { return lhs == rhs ? 1.0 : 0.0 }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return max(Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count)), 0.8)
        }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let m = lhsChars.count
        let n = rhsChars.count

        if Double(min(m, n)) / Double(max(m, n)) < 0.3 {
            return 0.2
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = lhsChars[i - 1] == rhsChars[j - 1]
                    ? dp[i - 1][j - 1] + 1
                    : max(dp[i - 1][j], dp[i][j - 1])
            }
        }

        return Double(dp[m][n] * 2) / Double(m + n)
    }

    private static func metadataValue(for metadata: [AVMetadataItem]?, identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata ?? [], filteredByIdentifier: identifier).first else {
            return nil
        }

        let value = try? await item.load(.stringValue)
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 由字符串生成稳定的本地歌曲 ID（FNV-1a 哈希取负），负数域与在线平台的正数 ID 天然隔离。
    private static func stableSongID(for key: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        let positive = Int64(bitPattern: hash & 0x7FFF_FFFF_FFFF_FFFF)
        let negative = positive == 0 ? Int64(-1) : -positive
        return Int(truncatingIfNeeded: negative)
    }
}
