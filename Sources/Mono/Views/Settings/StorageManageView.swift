import SwiftUI

private enum StorageTheme {
    static var ink: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    static var inkSoft: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        return .monoTextSecondary
    }

    static var separator: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoSeparator.opacity(0.3)
    }

    static var destructive: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.red }
        if NeumorphicStyle.isActive { return NeumorphicStyle.red }
        return .red
    }

    static func titleFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if SequoiaStyle.isActive { return SequoiaStyle.titleFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.titleFont(size, weight: weight) }
        return .system(size: size, weight: weight, design: .rounded)
    }

    static func bodyFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(size, weight: weight) }
        return .rounded(size: size, weight: weight)
    }

    static func labelFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(size, weight: weight) }
        return .rounded(size: size, weight: weight)
    }
}

/// 存储管理 —— 真实占用分析版：
/// 逐目录递归扫描（下载歌曲 / 接口缓存 / 图片网络缓存 / 用户数据 /
/// 导入字体 / 视频背景 / 临时文件），带分析动画与单项清除。
struct StorageManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsManager.shared

    private enum Phase {
        case scanning
        case ready
    }

    private struct StorageCategory: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String?
        let color: Color
        var size: Int64
        /// 内容型目录（本地音乐、主题背景）在各自页面管理，不提供一键清除
        var clearable = true

        static func == (lhs: StorageCategory, rhs: StorageCategory) -> Bool {
            lhs.id == rhs.id && lhs.size == rhs.size && lhs.detail == rhs.detail
        }
    }

    @State private var phase: Phase = .scanning
    @State private var categories: [StorageCategory] = []
    @State private var scanningLabel = ""
    @State private var scannedTotal: Int64 = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var categoryScanTasks: [String: Task<Void, Never>] = [:]

    private var totalUsage: Int64 {
        categories.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedSettingsBackground()

            ScrollView {
                VStack(spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "storage_title"),
                        eyebrow: String(localized: "settings_eyebrow_storage"),
                        icon: .storage,
                        signalModule: .storage
                    )

                    VStack(spacing: SettingsPageLayout.sectionSpacing) {
                        if phase == .scanning {
                            scanningCard
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            overviewCard
                                .transition(.opacity.combined(with: .move(edge: .top)))

                            categoriesCard

                            quickCleanCard
                        }

                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 44)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { startScan() } label: {
                    MonoIcon(icon: .refresh, size: 15, color: StorageTheme.inkSoft)
                }
                .disabled(phase == .scanning)
                .opacity(phase == .scanning ? 0.4 : 1)
            }
        }
        .onAppear { startScan() }
        .onDisappear { cancelScans() }
    }

    // MARK: - 分析动画

    private var scanningCard: some View {
        VStack(spacing: 0) {
            // 与总览同一尺寸的圆环：扫描弧旋转，中心数字实时长大，结束后无缝过渡
            ZStack {
                StorageScanRing()

                VStack(spacing: 5) {
                    Text(String(localized: "storage_analyzing"))
                        .font(StorageTheme.labelFont(11, weight: .semibold))
                        .foregroundColor(StorageTheme.inkSoft)
                        .tracking(0.6)

                    usageNumeral(scannedTotal)
                }
            }
            .frame(width: StorageRingMetrics.diameter, height: StorageRingMetrics.diameter)
            .padding(.top, 8)

            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(StorageTheme.inkSoft)

                Text(scanningLabel)
                    .font(StorageTheme.labelFont(12.5))
                    .foregroundColor(StorageTheme.inkSoft)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: scanningLabel)
            }
            .frame(height: 18)
            .padding(.top, 16)

            // 已扫出的分类逐条浮现
            if !categories.isEmpty {
                VStack(spacing: 9) {
                    ForEach(categories) { category in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 6, height: 6)

                            Text(category.title)
                                .font(StorageTheme.labelFont(12.5))
                                .foregroundColor(StorageTheme.inkSoft)

                            Spacer()

                            Text(formatBytes(category.size))
                                .font(StorageTheme.labelFont(12.5, weight: .semibold))
                                .foregroundColor(StorageTheme.ink)
                                .monospacedDigit()
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.top, 18)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .themedPageSurface(cornerRadius: MangaStyle.isActive ? 24 : 20, elevated: true, mangaTint: MangaStyle.bubbleWhite)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: categories)
    }

    // MARK: - 总览（圆环仪表 + 图例 + 磁盘信息）

    private var overviewCard: some View {
        VStack(spacing: 0) {
            ZStack {
                StorageRingGauge(segments: ringSegments)

                VStack(spacing: 5) {
                    Text(String(localized: "storage_total"))
                        .font(StorageTheme.labelFont(11, weight: .semibold))
                        .foregroundColor(StorageTheme.inkSoft)
                        .tracking(0.6)

                    usageNumeral(totalUsage)
                }
            }
            .frame(width: StorageRingMetrics.diameter, height: StorageRingMetrics.diameter)
            .padding(.top, 8)

            legendFlow
                .padding(.top, 22)

            Rectangle()
                .fill(StorageTheme.separator)
                .frame(height: 0.5)
                .padding(.top, 20)

            HStack(spacing: 0) {
                diskStat(
                    title: String(localized: "storage_available"),
                    value: formatBytes(availableSpace)
                )

                Rectangle()
                    .fill(StorageTheme.separator)
                    .frame(width: 0.5, height: 26)

                diskStat(
                    title: String(localized: "storage_disk_total"),
                    value: formatBytes(totalDiskSpace)
                )
            }
            .padding(.top, 14)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .themedPageSurface(cornerRadius: MangaStyle.isActive ? 24 : 20, elevated: true, mangaTint: MangaStyle.bubbleWhite)
    }

    private var ringSegments: [StorageRingGauge.Segment] {
        let total = max(totalUsage, 1)
        return categories
            .filter { $0.size > 0 }
            .map { StorageRingGauge.Segment(id: $0.id, fraction: Double($0.size) / Double(total), color: $0.color) }
    }

    /// 数值与单位分级排版：数字大而重，单位小而轻
    private func usageNumeral(_ bytes: Int64) -> some View {
        let text = formatBytes(bytes).replacingOccurrences(of: "\u{00A0}", with: " ")
        let parts = text.split(separator: " ", maxSplits: 1)
        let value = parts.first.map(String.init) ?? text
        let unit = parts.count > 1 ? String(parts[1]) : ""

        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(StorageTheme.titleFont(32, weight: .heavy))
                .foregroundColor(StorageTheme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())

            if !unit.isEmpty {
                Text(unit)
                    .font(StorageTheme.labelFont(14, weight: .semibold))
                    .foregroundColor(StorageTheme.inkSoft)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .frame(maxWidth: StorageRingMetrics.diameter - StorageRingMetrics.lineWidth * 2 - 34)
    }

    private func diskStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(StorageTheme.bodyFont(15, weight: .semibold))
                .foregroundColor(StorageTheme.ink)
                .monospacedDigit()

            Text(title)
                .font(StorageTheme.labelFont(11.5))
                .foregroundColor(StorageTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    /// 图例：色点 + 名称，流式排布
    private var legendFlow: some View {
        let visible = categories.filter { $0.size > 0 }
        return FlowLayout(spacing: 10) {
            ForEach(visible) { category in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(category.color)
                        .frame(width: 8, height: 8)

                    Text(category.title)
                        .font(StorageTheme.labelFont(11.5))
                        .foregroundColor(StorageTheme.inkSoft)
                }
            }
        }
    }

    // MARK: - 分类列表（单项清除）

    private var categoriesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                categoryRow(category)

                if index < categories.count - 1 {
                    Rectangle()
                        .fill(StorageTheme.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.vertical, 6)
        .themedPageSurface(cornerRadius: MangaStyle.isActive ? 20 : 16, elevated: true, mangaTint: MangaStyle.bubbleWhite)
    }

    private func categoryRow(_ category: StorageCategory) -> some View {
        let fraction = totalUsage > 0 ? CGFloat(category.size) / CGFloat(totalUsage) : 0
        let clearable = category.size > 0 && category.clearable

        return HStack(spacing: 12) {
            Circle()
                .fill(category.color)
                .frame(width: 9, height: 9)
                .padding(.leading, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(category.title)
                        .font(StorageTheme.bodyFont(15))
                        .foregroundColor(StorageTheme.ink)

                    if let detail = category.detail {
                        Text(detail)
                            .font(StorageTheme.labelFont(11))
                            .foregroundColor(StorageTheme.inkSoft.opacity(0.8))
                    }

                    Spacer()

                    Text(formatBytes(category.size))
                        .font(StorageTheme.labelFont(13, weight: .semibold))
                        .foregroundColor(StorageTheme.inkSoft)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(StorageTheme.separator)
                            .frame(height: 4)
                        Capsule()
                            .fill(category.color)
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0), height: 4)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: category.size)
                    }
                }
                .frame(height: 4)
            }

            Button {
                confirmClear(category)
            } label: {
                Text(String(localized: "storage_clear_btn"))
                    .font(StorageTheme.labelFont(12, weight: .semibold))
                    .foregroundColor(clearable ? StorageTheme.destructive : StorageTheme.inkSoft.opacity(0.4))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(
                            (clearable ? StorageTheme.destructive : StorageTheme.inkSoft).opacity(clearable ? 0.34 : 0.18),
                            lineWidth: 0.8
                        )
                    )
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
            .disabled(!clearable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    // MARK: - 一键清理缓存

    private var quickCleanCard: some View {
        Button {
            AlertManager.shared.show(
                title: String(localized: "storage_clean_caches_title"),
                message: String(localized: "storage_clean_caches_desc"),
                primaryButtonTitle: String(localized: "storage_clear"),
                secondaryButtonTitle: String(localized: "cancel"),
                primaryAction: { cleanAllCaches() }
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(StorageTheme.destructive.opacity(0.1))
                        .frame(width: 42, height: 42)
                    MonoIcon(icon: .trash, size: 18, color: StorageTheme.destructive)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "storage_clean_caches_title"))
                        .font(StorageTheme.bodyFont(15.5, weight: .semibold))
                        .foregroundColor(StorageTheme.destructive)
                    Text(String(localized: "storage_clean_caches_subtitle"))
                        .font(StorageTheme.labelFont(12))
                        .foregroundColor(StorageTheme.inkSoft)
                }

                Spacer()

                MonoIcon(icon: .chevronRight, size: 13, color: StorageTheme.destructive.opacity(0.7))
            }
            .padding(16)
            .themedPageSurface(cornerRadius: MangaStyle.isActive ? 20 : 16, elevated: true, mangaTint: MangaStyle.bubblePink.opacity(0.92))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
    }

    // MARK: - 扫描

    private func cancelScans() {
        scanTask?.cancel()
        scanTask = nil
        categoryScanTasks.values.forEach { $0.cancel() }
        categoryScanTasks.removeAll()
    }

    private func startScan() {
        cancelScans()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            phase = .scanning
            categories = []
            scannedTotal = 0
        }

        scanTask = Task { @MainActor in
            // 各内容项数量在主线程读取
            let fontCount = CustomFontManager.shared.fonts.count
            let videoCount = ImmersiveBackgroundManager.shared.library.count

            let steps: [(id: String, title: String, detail: String?, color: Color, urls: [URL], extra: Int64)] = [
                // 下载歌曲已并入本地音乐，这里合并为「本地歌曲」统一统计（下载目录 + 导入曲库）
                (
                    "localSongs",
                    String(localized: "storage_local_songs"),
                    String(localized: "storage_manage_in_local"),
                    Color(light: Color(hex: "3A7BD5"), dark: Color(hex: "7FB2FF")),
                    [StoragePaths.downloads, StoragePaths.localMusic],
                    0
                ),
                (
                    "apiCache",
                    String(localized: "storage_api_cache"),
                    nil,
                    .orange,
                    [StoragePaths.monoCache],
                    0
                ),
                (
                    "imageCache",
                    String(localized: "storage_image_cache"),
                    nil,
                    .teal,
                    StoragePaths.imageCacheDirs,
                    Int64(URLCache.shared.currentDiskUsage)
                ),
                (
                    "database",
                    String(localized: "storage_user_data"),
                    nil,
                    .purple,
                    [],
                    0
                ),
                (
                    "fonts",
                    String(localized: "storage_custom_fonts"),
                    fontCount > 0 ? String(format: String(localized: "storage_item_count"), fontCount) : nil,
                    .indigo,
                    [StoragePaths.customFonts],
                    0
                ),
                (
                    "videos",
                    String(localized: "storage_video_backgrounds"),
                    videoCount > 0 ? String(format: String(localized: "storage_item_count"), videoCount) : nil,
                    .pink,
                    [StoragePaths.immersiveBackgrounds],
                    0
                ),
                (
                    "temp",
                    String(localized: "storage_temp_files"),
                    nil,
                    .gray,
                    [FileManager.default.temporaryDirectory],
                    0
                ),
            ]

            for step in steps {
                guard !Task.isCancelled else { return }

                scanningLabel = String(format: String(localized: "storage_scanning_format"), step.title)

                let size: Int64
                if step.id == "database" {
                    size = await StoragePaths.measure {
                        StoragePaths.databaseSize()
                    }
                } else {
                    let urls = step.urls
                    let extra = step.extra
                    size = await StoragePaths.measure {
                        urls.reduce(Int64(0)) { $0 + StoragePaths.recursiveSize(at: $1) } + extra
                    }
                }

                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    categories.append(
                        StorageCategory(
                            id: step.id,
                            title: step.title,
                            detail: step.detail,
                            color: step.color,
                            size: size,
                            clearable: step.id != "localSongs"
                        )
                    )
                    scannedTotal += size
                }

                // 留出让数字与列表动画可感知的节奏
                try? await Task.sleep(nanoseconds: 140_000_000)
            }

            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                phase = .ready
            }
        }
    }

    /// 清除后只重算受影响的分类，不整页回到扫描态
    private func refreshCategory(_ id: String) {
        categoryScanTasks[id]?.cancel()
        categoryScanTasks[id] = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let size: Int64
            switch id {
            case "localSongs":
                size = await StoragePaths.measure {
                    StoragePaths.recursiveSize(at: StoragePaths.downloads)
                        + StoragePaths.recursiveSize(at: StoragePaths.localMusic)
                }
            case "apiCache":
                size = await StoragePaths.measure { StoragePaths.recursiveSize(at: StoragePaths.monoCache) }
            case "imageCache":
                let dirs = StoragePaths.imageCacheDirs
                let dirSize = await StoragePaths.measure { dirs.reduce(Int64(0)) { $0 + StoragePaths.recursiveSize(at: $1) } }
                size = dirSize + Int64(URLCache.shared.currentDiskUsage)
            case "database":
                size = await StoragePaths.measure { StoragePaths.databaseSize() }
            case "fonts":
                size = await StoragePaths.measure { StoragePaths.recursiveSize(at: StoragePaths.customFonts) }
            case "videos":
                size = await StoragePaths.measure { StoragePaths.recursiveSize(at: StoragePaths.immersiveBackgrounds) }
            case "temp":
                size = await StoragePaths.measure { StoragePaths.recursiveSize(at: FileManager.default.temporaryDirectory) }
            default:
                return
            }

            guard !Task.isCancelled else { return }
            categoryScanTasks.removeValue(forKey: id)
            guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                categories[index].size = size
            }
        }
    }

    // MARK: - 清除操作

    private func confirmClear(_ category: StorageCategory) {
        let (title, message): (String, String)
        switch category.id {
        case "apiCache":
            (title, message) = (String(localized: "storage_clear_api_cache"), String(localized: "storage_clear_api_cache_desc"))
        case "imageCache":
            (title, message) = (String(localized: "storage_clear_image"), String(localized: "storage_clear_image_desc"))
        case "database":
            (title, message) = (String(localized: "storage_clear_data"), String(localized: "storage_clear_data_desc"))
        case "fonts":
            (title, message) = (String(localized: "storage_clear_fonts"), String(localized: "storage_clear_fonts_desc"))
        case "videos":
            (title, message) = (String(localized: "storage_clear_videos"), String(localized: "storage_clear_videos_desc"))
        case "temp":
            (title, message) = (String(localized: "storage_clear_temp"), String(localized: "storage_clear_temp_desc"))
        default:
            return
        }

        AlertManager.shared.show(
            title: title,
            message: message,
            primaryButtonTitle: String(localized: "storage_clear"),
            secondaryButtonTitle: String(localized: "cancel"),
            primaryAction: { performClear(category.id) }
        )
    }

    private func performClear(_ id: String) {
        HapticManager.shared.success()

        switch id {
        case "apiCache":
            CacheManager.shared.clearAll()
            OptimizedCacheManager.shared.clearAll()
        case "imageCache":
            CachedAsyncImage<EmptyView>.clearMemoryCache()
            URLCache.shared.removeAllCachedResponses()
            for dir in StoragePaths.imageCacheDirs {
                try? FileManager.default.removeItem(at: dir)
            }
        case "database":
            DatabaseManager.shared.clearCacheData()
            UserDefaults.standard.removeObject(forKey: AppConfig.StorageKeys.dailyCacheTimestamp)
            UserDefaults.standard.removeObject(forKey: AppConfig.StorageKeys.lastSyncTimestamp)
        case "fonts":
            let manager = CustomFontManager.shared
            for record in manager.fonts {
                manager.delete(record)
            }
        case "videos":
            let manager = ImmersiveBackgroundManager.shared
            for video in manager.library {
                manager.delete(video)
            }
        case "temp":
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.removeItem(at: file)
                }
            }
        default:
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            refreshCategory(id)
        }
    }

    /// 一键清理：接口缓存 + 图片网络缓存 + 临时文件（不动内容与用户数据）
    private func cleanAllCaches() {
        HapticManager.shared.success()

        MonoMemoryEngine.shared.trim(level: .critical, reason: .manual)
        CacheManager.shared.clearAll()
        OptimizedCacheManager.shared.clearAll()
        CachedAsyncImage<EmptyView>.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()

        let fm = FileManager.default
        for dir in StoragePaths.imageCacheDirs {
            try? fm.removeItem(at: dir)
        }
        if let tmpFiles = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            for file in tmpFiles {
                try? fm.removeItem(at: file)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            refreshCategory("apiCache")
            refreshCategory("imageCache")
            refreshCategory("temp")
        }
    }

    // MARK: - 磁盘信息

    private var totalDiskSpace: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    private var availableSpace: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - 圆环仪表

private enum StorageRingMetrics {
    static let diameter: CGFloat = 192
    static let lineWidth: CGFloat = 16
}

/// 总览圆环：圆头分段弧 + 内侧细刻度，出场时从顶部顺时针绘入
private struct StorageRingGauge: View {
    struct Segment {
        let id: String
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    @State private var reveal: Double = 0

    private struct Arc: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    /// 把占比换算成 trim 区间：圆头端帽向内缩进，缝隙只留可视间隔；
    /// 小占用分类钳到最小跨度，呈现为一个圆点
    private var arcs: [Arc] {
        guard !segments.isEmpty else { return [] }

        let circumference = Double.pi * Double(StorageRingMetrics.diameter - StorageRingMetrics.lineWidth)
        let capInset = Double(StorageRingMetrics.lineWidth) / 2 / circumference
        let gap = segments.count > 1 ? 4.5 / circumference : 0

        let minSpan = capInset * 2 + 0.002
        var spans = segments.map { max($0.fraction, minSpan) }
        let scale = (1.0 - gap * Double(segments.count)) / spans.reduce(0, +)
        spans = spans.map { $0 * scale }

        var cursor = 0.0
        var result: [Arc] = []
        for (index, segment) in segments.enumerated() {
            let span = spans[index]
            let start = cursor + capInset
            let end = max(cursor + span - capInset, start + 0.0005)
            result.append(Arc(id: segment.id, start: start, end: end, color: segment.color))
            cursor += span + gap
        }
        return result
    }

    private var signature: [Double] {
        segments.map(\.fraction)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(StorageTheme.separator.opacity(0.55), lineWidth: StorageRingMetrics.lineWidth)
                .padding(StorageRingMetrics.lineWidth / 2)

            ForEach(arcs) { arc in
                Circle()
                    .trim(from: min(arc.start, reveal), to: min(arc.end, reveal))
                    .stroke(
                        arc.color,
                        style: StrokeStyle(lineWidth: StorageRingMetrics.lineWidth, lineCap: .round)
                    )
                    .padding(StorageRingMetrics.lineWidth / 2)
                    .shadow(color: arc.color.opacity(0.3), radius: 4)
            }

            StorageRingTicks()
        }
        .rotationEffect(.degrees(-90))
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: signature)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.08)) {
                reveal = 1
            }
        }
    }
}

/// 分析中的圆环：同尺寸底轨上的拖尾扫描弧，与总览无缝衔接
private struct StorageScanRing: View {
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(StorageTheme.separator.opacity(0.55), lineWidth: StorageRingMetrics.lineWidth)
                .padding(StorageRingMetrics.lineWidth / 2)

            Circle()
                .trim(from: 0, to: 0.34)
                .stroke(
                    AngularGradient(
                        colors: [Color.monoAccent.opacity(0), Color.monoAccent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(122)
                    ),
                    style: StrokeStyle(lineWidth: StorageRingMetrics.lineWidth, lineCap: .round)
                )
                .padding(StorageRingMetrics.lineWidth / 2)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spinning)

            StorageRingTicks()
        }
        .onAppear { spinning = true }
    }
}

/// 环内侧一圈细刻度：每 15 格一根长刻度，其余为短刻度
private struct StorageRingTicks: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = size.width / 2 - StorageRingMetrics.lineWidth - 7

            for index in 0 ..< 60 {
                let isMajor = index % 15 == 0
                let inner = outer - (isMajor ? 5.5 : 3.5)
                let angle = Double(index) / 60 * 2 * .pi

                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * outer,
                    y: center.y + sin(angle) * outer
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * inner,
                    y: center.y + sin(angle) * inner
                ))

                context.stroke(
                    path,
                    with: .color(StorageTheme.inkSoft.opacity(isMajor ? 0.3 : 0.16)),
                    lineWidth: isMajor ? 1.1 : 0.7
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 磁盘路径与体积计算

private enum StoragePaths {
    // Propagate view cancellation to the disk worker, including recursive scans.
    static func measure(_ operation: @escaping @Sendable () -> Int64) async -> Int64 {
        guard !Task.isCancelled else { return 0 }
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static var downloads: URL {
        DownloadedSong.downloadsDirectory
    }

    static var monoCache: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MonoCache")
    }

    static var localMusic: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LocalMusic", isDirectory: true)
    }

    static var imageCacheDirs: [URL] {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        return ["ImageCache", "zijiu.Monologue.com.images", "com.monologue.images", "fsCachedData"]
            .map { cacheDir.appendingPathComponent($0) }
    }

    static var customFonts: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CustomFonts", isDirectory: true)
    }

    static var immersiveBackgrounds: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ImmersiveBackgrounds", isDirectory: true)
    }

    /// 递归统计目录体积（含所有子目录）
    static func recursiveSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { return total }
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// 数据库体积：SwiftData default.store 及 iOS 16 的 CoreData 回退库
    static func databaseSize() -> Int64 {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return 0 }

        var total: Int64 = 0
        for name in ["default.store", "MonoLocal.sqlite"] {
            let base = appSupport.appendingPathComponent(name)
            for ext in ["", "-wal", "-shm", ".wal", ".shm"] {
                guard !Task.isCancelled else { return total }
                let path = base.path + ext
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        return total
    }
}
