import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 沉浸背景管理 — 从照片图库/文件导入视频，按「当前歌曲 / 全局沉浸」绑定。
/// 视觉语言与 Aria 沉浸设置保持一致。
struct ImmersiveBackgroundSheet: View {
    @ObservedObject private var bgManager = ImmersiveBackgroundManager.shared
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var coverColors = CoverColorExtractor()
    let palette: AriaPalette

    enum BindTarget: Hashable { case song, global }

    @State private var target: BindTarget = .song
    @State private var showFileImporter = false
    @State private var showMoeWallsBrowser = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var selectedWorkspace: ImmersiveBackgroundWorkspace = .sources

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    private var songId: Int? { player.currentSong?.id }

    private var settingsAccent: Color {
        normalizedEQAccent(coverColors.dominantColor)
    }

    init(palette: AriaPalette = .fallback) {
        self.palette = palette
    }

    private var currentBoundVideoId: String? {
        switch target {
        case .song:
            guard let songId else { return nil }
            return bgManager.boundVideoId(forSong: songId)
        case .global:
            return bgManager.boundGlobalVideoId()
        }
    }

    var body: some View {
        ZStack {
            sheetBackdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                PlayerSettingsWorkspaceBar(
                    selection: $selectedWorkspace,
                    items: ImmersiveBackgroundWorkspace.allCases.map {
                        PlayerSettingsWorkspaceItem(value: $0, title: $0.title, icon: $0.icon)
                    },
                    accent: settingsAccent
                )

                workspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        // monoSheet 内呈现时，深色背景铺满整个面板（含把手区）
        .monoSheetSurface(id: "immersive-background") {
            sheetBackdrop
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await importFromPhotos(item) }
        }
        .fullScreenCover(isPresented: $showMoeWallsBrowser) {
            MoeWallsBrowserView(
                palette: palette,
                isInUse: { video in
                    currentBoundVideoId == video.id
                },
                onUse: { video in
                    applyBinding(video.id)
                }
            )
        }
        .onAppear {
            refreshCoverAccent()
            if songId == nil {
                target = .global
            }
        }
        .onChange(of: player.currentSong?.id) { _, _ in
            refreshCoverAccent()
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedWorkspace {
                case .sources:
                    importCards
                    if let importError {
                        errorBanner(importError)
                    }
                case .binding:
                    targetPicker
                case .library:
                    librarySection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 44)
            .iPadContentWidth(720)
        }
    }

    // MARK: - 背景

    private var sheetBackdrop: some View {
        ZStack {
            PlaylistColorBackground(
                coverUrl: player.currentSong?.coverUrl?.sized(720)
            )
            .saturation(0.78)

            Color.black.opacity(0.48)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.54),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func refreshCoverAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
    }

    // MARK: - 导入入口

    private var importCards: some View {
        let accent = settingsAccent

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoPickerItem, matching: .videos, photoLibrary: .shared()) {
                    ImportCardLabel(
                        icon: .album,
                        title: String(localized: "immersive_bg_from_photos"),
                        accent: accent
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                .disabled(isImporting)

                Button {
                    showFileImporter = true
                } label: {
                    ImportCardLabel(
                        icon: .arrowDownToLine,
                        title: String(localized: "immersive_bg_from_files"),
                        accent: settingsAccent
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                .disabled(isImporting)
            }

            Button {
                showMoeWallsBrowser = true
            } label: {
                HStack(spacing: 10) {
                    MonoIcon(icon: .search, size: 16, color: settingsAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(settingsAccent.opacity(0.13)))

                    Text(String(localized: "immersive_bg_moewalls"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 0)

                    MonoIcon(icon: .chevronRight, size: 12, color: .white.opacity(0.42))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
            .disabled(isImporting)
        }
        .overlay {
            if isImporting {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(String(localized: "immersive_bg_importing"))
                        .font(.rounded(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
            }
        }
    }

    /// 独立 View 结构体：PhotosPicker 的 label 闭包是 nonisolated 的，
    /// 不能直接调用主 actor 隔离的视图构建方法，构造结构体则没有隔离限制
    private struct ImportCardLabel: View {
        let icon: MonoIcon.IconType
        let title: String
        let accent: Color

        var body: some View {
            HStack(spacing: 10) {
                MonoIcon(icon: icon, size: 16, color: accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.13)))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            MonoIcon(icon: .warning, size: 13, color: .monoAccentRed)
            Text(message)
                .font(.rounded(size: 12, weight: .medium))
                .foregroundColor(.monoAccentRed)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.monoAccentRed.opacity(0.12))
        )
    }

    // MARK: - 绑定目标

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "immersive_bg_bind_target"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 10) {
                targetChip(.song, icon: .musicNote, title: String(localized: "immersive_bg_target_song"), subtitle: player.currentSong?.name)
                    .disabled(songId == nil)
                    .opacity(songId == nil ? 0.42 : 1)
                targetChip(
                    .global,
                    icon: .immersive,
                    title: String(localized: "全局沉浸模式"),
                    subtitle: String(localized: "所有未单独绑定的歌曲")
                )
            }

            bindingSummary
        }
    }

    private func targetChip(_ value: BindTarget, icon: MonoIcon.IconType, title: String, subtitle: String?) -> some View {
        let selected = target == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { target = value }
        } label: {
            HStack(spacing: 10) {
                MonoIcon(icon: icon, size: 14, color: selected ? settingsAccent : .white.opacity(0.6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(size: 13, weight: .bold))
                        .foregroundColor(selected ? .white : .white.opacity(0.65))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.rounded(size: 10, weight: .medium))
                            .foregroundColor(selected ? .white.opacity(0.6) : .white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if selected {
                    Circle()
                        .fill(settingsAccent)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? settingsAccent.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? settingsAccent.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
    }

    @ViewBuilder
    private var bindingSummary: some View {
        if let vid = currentBoundVideoId, let v = bgManager.video(withId: vid) {
            HStack(spacing: 10) {
                VideoThumbnailView(url: bgManager.fileURL(for: v), id: v.id)
                    .frame(width: 52, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(v.displayName)
                        .font(.rounded(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(String(localized: "immersive_bg_in_use"))
                        .font(.rounded(size: 10, weight: .bold))
                        .foregroundColor(settingsAccent)
                }

                Spacer()

                Button {
                    HapticManager.shared.light()
                    applyBinding(nil)
                } label: {
                    Text(String(localized: "immersive_bg_unbind"))
                        .font(.rounded(size: 12, weight: .semibold))
                        .foregroundColor(.monoAccentRed)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.monoAccentRed.opacity(0.12)))
                }
                .buttonStyle(MonoBouncingButtonStyle())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        } else {
            Text(String(localized: "immersive_bg_no_binding"))
                .font(.rounded(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 2)
        }
    }

    // MARK: - 视频库

    @ViewBuilder
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !bgManager.library.isEmpty {
                HStack(spacing: 8) {
                    Text(String(localized: "immersive_bg_library_section"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                    Text("\(bgManager.library.count)")
                        .font(.rounded(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            if bgManager.library.isEmpty {
                emptyLibrary
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(bgManager.library) { video in
                        libraryCard(video)
                    }
                }
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            MonoIcon(icon: .mv, size: 30, color: .white.opacity(0.25))
            Text(String(localized: "immersive_bg_empty"))
                .font(.rounded(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                )
        )
    }

    private func libraryCard(_ video: ImmersiveVideo) -> some View {
        let isBound = currentBoundVideoId == video.id
        return Button {
            HapticManager.shared.light()
            applyBinding(isBound ? nil : video.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                VideoThumbnailView(url: bgManager.fileURL(for: video), id: video.id)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                // 底部渐变压暗，托出片名
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 6) {
                    Text(video.displayName)
                        .font(.rounded(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    VideoDurationBadge(url: bgManager.fileURL(for: video), id: video.id)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .topLeading) {
                if isBound {
                    HStack(spacing: 4) {
                        MonoIcon(icon: .checkmark, size: 9, color: .white)
                        Text(String(localized: "immersive_bg_in_use"))
                            .font(.rounded(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(settingsAccent))
                    .padding(7)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    HapticManager.shared.light()
                    bgManager.delete(video)
                } label: {
                    MonoIcon(icon: .trash, size: 11, color: .white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isBound ? settingsAccent : Color.white.opacity(0.08), lineWidth: isBound ? 1.6 : 1)
            )
            .shadow(color: isBound ? settingsAccent.opacity(0.24) : .clear, radius: 8)
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
    }

    // MARK: - Actions

    private func applyBinding(_ videoId: String?) {
        switch target {
        case .song:
            guard let songId else { return }
            bgManager.bindSong(songId, to: videoId)
        case .global:
            bgManager.bindGlobal(to: videoId)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                defer { isImporting = false }
                guard await Self.videoWithin4K(url) else {
                    importError = String(localized: "视频分辨率超过 4K，无法导入")
                    return
                }
                if let video = bgManager.importVideo(from: url) {
                    applyBinding(video.id)
                } else {
                    importError = String(localized: "immersive_bg_import_failed")
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// 照片图库导入：视频先落到临时目录，再入库并自动绑定当前目标
    private func importFromPhotos(_ item: PhotosPickerItem) async {
        importError = nil
        isImporting = true
        defer {
            isImporting = false
            photoPickerItem = nil
        }

        do {
            guard let picked = try await item.loadTransferable(type: PickedImmersiveVideo.self) else {
                importError = String(localized: "immersive_bg_import_failed")
                return
            }
            defer { try? FileManager.default.removeItem(at: picked.url) }

            guard await Self.videoWithin4K(picked.url) else {
                importError = String(localized: "视频分辨率超过 4K，无法导入")
                return
            }

            let name = Date().formatted(.dateTime.month().day().hour().minute())
            if let video = bgManager.importVideo(
                from: picked.url,
                displayName: String(localized: "immersive_bg_photos_name_prefix") + " " + name
            ) {
                applyBinding(video.id)
            } else {
                importError = String(localized: "immersive_bg_import_failed")
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    /// 分辨率校验：支持导入最大 4K（DCI 4096×2160 / UHD 3840×2160，含竖屏方向）
    private static func videoWithin4K(_ url: URL) async -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            // 读不出轨道信息时放行，交由播放层兜底
            return true
        }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let w = abs(rect.width)
        let h = abs(rect.height)
        return max(w, h) <= 4200 && min(w, h) <= 2400
    }
}

private enum ImmersiveBackgroundWorkspace: String, CaseIterable, Identifiable {
    case sources
    case binding
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sources: return String(localized: "来源")
        case .binding: return String(localized: "绑定")
        case .library: return String(localized: "视频库")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .sources: return .add
        case .binding: return .musicNote
        case .library: return .mv
        }
    }
}

// MARK: - 照片图库视频落盘载体

private struct PickedImmersiveVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("immersive-import-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

// MARK: - 时长角标

private struct VideoDurationBadge: View {
    let url: URL
    let id: String
    @State private var text: String?

    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }
        }
        .task(id: id) {
            text = await VideoDurationCache.shared.durationText(for: url, id: id)
        }
    }
}

@MainActor
private final class VideoDurationCache {
    static let shared = VideoDurationCache()
    private var cache: [String: String] = [:]

    private init() {
        MonoMemoryEngine.shared.registerResource(
            id: "cache.video-duration",
            priority: .recreatable,
            budgetWeight: 0.01,
            minimumBudgetBytes: 256 * 1_024,
            applyBudget: { _ in },
            trim: { [weak self] context in
                self?.trimMemory(context) ?? .none
            },
            measureUsage: { [weak self] in
                guard let self else { return .unknown }
                return .init(itemCount: self.cache.count, estimatedBytes: self.cache.count * 128)
            }
        )
    }

    func durationText(for url: URL, id: String) async -> String? {
        if let cached = cache[id] { return cached }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let total = Int(duration.seconds.rounded())
        guard total > 0 else { return nil }
        let text: String
        if total >= 3600 {
            text = String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        } else {
            text = String(format: "%d:%02d", total / 60, total % 60)
        }
        cache[id] = text
        if cache.count > 256 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(192).map { ($0.key, $0.value) })
        }
        return text
    }

    private func trimMemory(_ context: MonoMemoryEngine.TrimContext) -> MonoMemoryEngine.TrimResult {
        let before = cache.count
        if context.level >= .background {
            cache.removeAll(keepingCapacity: false)
        } else if cache.count > 192 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(192).map { ($0.key, $0.value) })
        }
        let released = max(0, before - cache.count)
        return .init(
            releasedItemCount: released,
            estimatedReleasedBytes: released * 128,
            preservedItemCount: cache.count
        )
    }
}

// MARK: - 视频缩略图

struct VideoThumbnailView: View {
    let url: URL
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .overlay(MonoIcon(icon: .mv, size: 20, color: .white.opacity(0.3)))
            }
        }
        .task(id: id) {
            image = await VideoThumbnailCache.shared.thumbnail(for: url, id: id)
        }
    }
}

@MainActor
final class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()
    private var cache: [String: UIImage] = [:]

    private init() {
        MonoMemoryEngine.shared.registerResource(
            id: "cache.video-thumbnails",
            priority: .recreatable,
            budgetWeight: 0.04,
            minimumBudgetBytes: 3 * 1_024 * 1_024,
            applyBudget: { _ in },
            trim: { [weak self] context in
                self?.trimMemory(context) ?? .none
            },
            measureUsage: { [weak self] in
                self?.memoryUsage() ?? .unknown
            }
        )
    }

    func thumbnail(for url: URL, id: String) async -> UIImage? {
        if let cached = cache[id] { return cached }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        do {
            let cgImage = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let image = UIImage(cgImage: cgImage)
            cache[id] = image
            if cache.count > 64 {
                cache = Dictionary(uniqueKeysWithValues: cache.suffix(48).map { ($0.key, $0.value) })
            }
            return image
        } catch {
            return nil
        }
    }

    private func trimMemory(_ context: MonoMemoryEngine.TrimContext) -> MonoMemoryEngine.TrimResult {
        let beforeCount = cache.count
        let beforeBytes = cache.values.reduce(0) { partial, image in
            partial + (image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        }
        if context.level >= .background {
            cache.removeAll(keepingCapacity: false)
        } else if cache.count > 48 {
            cache = Dictionary(uniqueKeysWithValues: cache.suffix(48).map { ($0.key, $0.value) })
        }
        let afterBytes = cache.values.reduce(0) { partial, image in
            partial + (image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        }
        return .init(
            releasedItemCount: max(0, beforeCount - cache.count),
            estimatedReleasedBytes: max(0, beforeBytes - afterBytes),
            preservedItemCount: cache.count
        )
    }

    private func memoryUsage() -> MonoMemoryEngine.ResourceUsage {
        .init(
            itemCount: cache.count,
            estimatedBytes: cache.values.reduce(0) { partial, image in
                partial + (image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
            }
        )
    }
}
