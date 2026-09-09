// MV 发现页 + MV 列表页 + MV 卡片组件
// aside 编辑部风格：眉题刻度 + 平排列表 + 发丝分隔；其余主题保持卡片版式

import SwiftUI

// MARK: - MV ID 包装（用于 fullScreenCover(item:)）

struct MVIdItem: Identifiable {
    let id: Int
}

struct QQMVVidItem: Identifiable {
    let vid: String
    var id: String { vid }
}

private enum MVTheme {
    /// aside 编辑部风格：默认主题走平排编辑部版式，其余主题保持卡片版式
    static var isAside: Bool {
        !ThemedPageStyle.isActive
    }

    static var ink: Color {
        if SignalStyle.isActive { return SignalStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    static var inkSoft: Color {
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        return .monoTextSecondary
    }

    static var inkMuted: Color {
        if SignalStyle.isActive { return SignalStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary.opacity(0.55)
    }

    static var accent: Color {
        if SignalStyle.isActive { return SignalStyle.accent }
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        if isAside { return .monoAccent }
        return .monoIconBackground
    }

    static var separator: Color {
        if SignalStyle.isActive { return SignalStyle.separator }
        if SequoiaStyle.isActive { return SequoiaStyle.separator }
        if NeumorphicStyle.isActive { return NeumorphicStyle.separator.opacity(0.48) }
        return .monoSeparator
    }

    static var coverPlaceholder: Color {
        if SignalStyle.isActive { return SignalStyle.controlPressed }
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed.opacity(0.72) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoTextSecondary.opacity(0.06)
    }

    static var selectedIconBackground: Color {
        if SignalStyle.isActive { return SignalStyle.control }
        if SequoiaStyle.isActive { return SequoiaStyle.selectedWash }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoSeparator
    }

    static func titleFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if SignalStyle.isActive { return SignalStyle.titleFont(size, weight: weight) }
        if SequoiaStyle.isActive { return SequoiaStyle.titleFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.titleFont(size, weight: weight) }
        return .rounded(size: size, weight: weight)
    }

    static func bodyFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if SignalStyle.isActive { return SignalStyle.bodyFont(size, weight: weight) }
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(size, weight: weight) }
        return .rounded(size: size, weight: weight)
    }

    static func labelFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(size, weight: weight) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(size, weight: weight) }
        return .rounded(size: size, weight: weight)
    }

    static func cardRadius(_ fallback: CGFloat = 20) -> CGFloat {
        if SignalStyle.isActive { return 10 }
        if SequoiaStyle.isActive { return 18 }
        if NeumorphicStyle.isActive { return 18 }
        return fallback
    }
}

// MARK: - aside 编辑部通用小件

/// 眉题行：强调色刻度 + 字距 small caps
private struct MVAsideKicker: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.monoAccent)
                .frame(width: 18, height: 3)

            Text(text)
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundColor(.monoTextSecondary.opacity(0.72))
        }
    }
}

/// 封面时长角标：黑纱底 + 白色等宽字，贴图可读
private struct MVDurationTag: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .monospaced))
            .foregroundColor(MVTheme.isAside ? .white : MVTheme.ink)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background {
                if MVTheme.isAside {
                    Capsule().fill(Color.black.opacity(0.55))
                } else {
                    Color.clear.monoGlassCapsule()
                }
            }
            .padding(compact ? 6 : 8)
    }
}

// MARK: - MV 网格卡片

struct MVGridCard: View {
    let mv: MV
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 10) {
                // 封面
                ZStack(alignment: .bottomTrailing) {
                    coverImage(url: mv.coverUrl, height: 100, cornerRadius: MVTheme.isAside ? 12 : 16)

                    // 时长角标
                    if !mv.durationText.isEmpty {
                        MVDurationTag(text: mv.durationText)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mv.displayName)
                        .font(MVTheme.bodyFont(14, weight: .semibold))
                        .foregroundColor(MVTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(mv.artistName ?? String(localized: "mv_unknown_artist"))
                            .font(MVTheme.labelFont(12))
                            .foregroundColor(MVTheme.inkSoft)
                            .lineLimit(1)

                        if !mv.playCountText.isEmpty {
                            Circle()
                                .fill(MVTheme.inkMuted.opacity(0.35))
                                .frame(width: 3, height: 3)
                            Text(mv.playCountText + String(localized: "mv_play_suffix"))
                                .font(MVTheme.labelFont(11))
                                .foregroundColor(MVTheme.inkMuted)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MV 行卡片

struct MVRowCard: View {
    let mv: MV
    var rank: Int? = nil
    var showsDivider: Bool = true
    var onTap: (() -> Void)? = nil

    var body: some View {
        if MVTheme.isAside {
            asideRow
        } else {
            themedCard
        }
    }

    /// aside 编辑部式：平排行 + 发丝分隔，大号排名数字
    private var asideRow: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    if let rank {
                        Text("\(rank)")
                            .font(.system(size: 20, weight: rank <= 3 ? .heavy : .semibold, design: .rounded))
                            .foregroundColor(rank <= 3 ? .monoAccent : .monoTextSecondary.opacity(0.45))
                            .monospacedDigit()
                            .frame(width: 30, alignment: .center)
                    }

                    ZStack(alignment: .bottomTrailing) {
                        coverImage(url: mv.coverUrl, width: 118, height: 66, cornerRadius: 10)

                        if !mv.durationText.isEmpty {
                            MVDurationTag(text: mv.durationText, compact: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mv.displayName)
                            .font(.rounded(size: 15, weight: .semibold))
                            .foregroundColor(.monoTextPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(mv.artistName ?? String(localized: "mv_unknown_artist"))
                            .font(.rounded(size: 12.5))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))
                            .lineLimit(1)

                        if !mv.playCountText.isEmpty {
                            HStack(spacing: 3) {
                                MonoIcon(icon: .play, size: 8.5, color: .monoTextSecondary.opacity(0.55))
                                Text(mv.playCountText)
                                    .font(.rounded(size: 11))
                                    .foregroundColor(.monoTextSecondary.opacity(0.6))
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)

                if showsDivider {
                    Rectangle()
                        .fill(Color.monoSeparator.opacity(0.7))
                        .frame(height: 0.6)
                        .padding(.leading, rank != nil ? 44 : 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.92))
    }

    /// 其余主题：卡片式
    private var themedCard: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 14) {
                // 排名序号
                if let rank {
                    Text("\(rank)")
                        .font(MVTheme.labelFont(16, weight: .semibold))
                        .foregroundColor(rank <= 3 ? (SequoiaStyle.isActive ? SequoiaStyle.red : (NeumorphicStyle.isActive ? NeumorphicStyle.red : .monoAccentRed)) : MVTheme.inkMuted.opacity(0.68))
                        .frame(width: 24)
                }

                // 封面
                ZStack(alignment: .bottomTrailing) {
                    coverImage(url: mv.coverUrl, width: 120, height: 68, cornerRadius: 12)

                    if !mv.durationText.isEmpty {
                        MVDurationTag(text: mv.durationText, compact: true)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(mv.displayName)
                        .font(MVTheme.bodyFont(15, weight: .semibold))
                        .foregroundColor(MVTheme.ink)
                        .lineLimit(2)

                    Text(mv.artistName ?? String(localized: "mv_unknown_artist"))
                        .font(MVTheme.labelFont(13))
                        .foregroundColor(MVTheme.inkSoft)
                        .lineLimit(1)

                    if !mv.playCountText.isEmpty {
                        HStack(spacing: 3) {
                            MonoIcon(icon: .play, size: 9, color: MVTheme.inkMuted.opacity(0.72))
                            Text(mv.playCountText)
                                .font(MVTheme.labelFont(11))
                                .foregroundColor(MVTheme.inkMuted.opacity(0.9))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .themedPageSurface(cornerRadius: MVTheme.cardRadius(), elevated: false)
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
    }
}

// MARK: - 封面图片辅助

@MainActor
@ViewBuilder
private func coverImage(url: String?, width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    ZStack {
        shape.fill(MVTheme.coverPlaceholder)

        if let urlStr = url, let imageUrl = URL(string: urlStr) {
            CachedAsyncImage(url: imageUrl) {
                shape.fill(MVTheme.coverPlaceholder)
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    .frame(width: width, height: height)
    .frame(maxWidth: width == nil ? .infinity : nil)
    .clipShape(shape)
    .clipped()
    .overlay {
        if MVTheme.isAside {
            shape.stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.8)
        } else if SignalStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive {
            shape.stroke(MVTheme.separator, lineWidth: 0.7)
        }
    }
}

// MARK: - MV 发现页

struct MVDiscoverView: View {
    @StateObject private var viewModel = MVDiscoverViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedSource: MusicSource?
    @State private var selectedItem: UnifiedMVItem?

    private let sources: [MusicSource] = [.netease, .qqmusic, .kugou]

    var body: some View {
        let _ = settings.globalThemeRevision

        GeometryReader { viewport in
            let contentWidth = min(
                max(viewport.size.width, 1),
                DeviceLayout.usesExpandedLayout ? 1_040 : max(viewport.size.width, 1)
            )

            ZStack {
                ThemedPageBackground().ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if SignalStyle.isActive {
                            SignalNestedPageHeader(
                                title: "MV",
                                eyebrow: "VIDEO FEED",
                                icon: .mv,
                                module: .track
                            )
                            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                        }

                        sourceFilter

                        if let source = selectedSource {
                            platformSection(source: source, expanded: true)
                        } else {
                            if let hero = sources.compactMap({ viewModel.items(for: $0).first }).first {
                                unifiedHero(hero)
                            }
                            ForEach(sources, id: \.self) { source in
                                platformSection(source: source, expanded: false)
                            }
                        }

                        FloatingBarBottomSpacer()
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
                .refreshable { viewModel.fetchUnified(refresh: true) }

                if viewModel.isUnifiedLoading && sources.allSatisfy({ viewModel.items(for: $0).isEmpty }) {
                    MonoLoadingView(text: "LOADING MV")
                }
            }
        }
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear { viewModel.fetchUnified() }
        .fullScreenCover(item: $selectedItem) { item in
            switch item.source {
            case .netease:
                if let id = item.ncmID { MVPlayerView(mvId: id) }
            case .qqmusic:
                if let vid = item.qqVID { QQMVPlayerView(vid: vid) }
            case .kugou:
                if let mv = item.kcmMV { KCMMVPlayerView(mv: mv) }
            case .qishui, .appleMusic, .local:
                EmptyView()
            }
        }
    }

    private var sourceFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                sourceFilterButton(source: nil, title: String(localized: "filter_all"))
                ForEach(sources, id: \.self) { source in
                    sourceFilterButton(source: source, title: source.shortName)
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceFilterButton(source: MusicSource?, title: String) -> some View {
        let selected = selectedSource == source
        let tint = source?.themedBadgeColor ?? Color.monoAccent
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                selectedSource = source
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: selected ? .bold : .medium) : .rounded(size: 12, weight: selected ? .bold : .medium))
            }
            .foregroundStyle(SignalStyle.isActive ? (selected ? SignalStyle.onAccent : SignalStyle.inkSoft) : (selected ? Color.monoTextPrimary : Color.monoTextSecondary))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(SignalStyle.isActive ? (selected ? SignalStyle.accent : SignalStyle.control) : (selected ? tint.opacity(0.14) : Color.monoTextPrimary.opacity(0.045)))
            )
        }
        .buttonStyle(.plain)
    }

    private func unifiedHero(_ item: UnifiedMVItem) -> some View {
        Button { selectedItem = item } label: {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: item.coverURL.flatMap(URL.init(string:))) {
                    Rectangle().fill(MVTheme.coverPlaceholder)
                }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 8) {
                    PlatformBadgeLabel(text: item.source.shortName, source: item.source, fontSize: 10)
                    Text(item.title)
                        .font(.rounded(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.artistName)
                        if !item.durationText.isEmpty { Text(item.durationText).monospacedDigit() }
                    }
                    .font(.rounded(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: SignalStyle.isActive ? 11 : 20, style: .continuous))
            .overlay {
                if SignalStyle.isActive {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(SignalStyle.separator.opacity(0.74), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }

    @ViewBuilder
    private func platformSection(source: MusicSource, expanded: Bool) -> some View {
        let items = viewModel.items(for: source)
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Capsule().fill(source.themedBadgeColor).frame(width: 18, height: 3)
                Text(source.shortName)
                    .font(.rounded(size: 18, weight: .bold))
                    .foregroundStyle(Color.monoTextPrimary)
                Spacer()
                if viewModel.unifiedLoadingSources.contains(source), !items.isEmpty {
                    ProgressView().scaleEffect(0.72).tint(source.themedBadgeColor)
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

            if items.isEmpty {
                platformState(source: source)
            } else {
                let visible = expanded ? items : Array(items.prefix(6))
                LazyVGrid(columns: platformGridColumns, spacing: 22) {
                    ForEach(visible) { item in
                        unifiedCard(item)
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

                if expanded, viewModel.unifiedHasMore[source] == true {
                    Button { viewModel.loadMoreUnified(source: source) } label: {
                        HStack(spacing: 8) {
                            if viewModel.unifiedLoadingSources.contains(source) {
                                ProgressView().scaleEffect(0.75)
                            }
                            Text(String(localized: "event_load_more"))
                                .font(.rounded(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(source.themedBadgeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(source.themedBadgeColor.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                }
            }
        }
    }

    private func unifiedCard(_ item: UnifiedMVItem) -> some View {
        Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    coverImage(url: item.coverURL, height: 96, cornerRadius: 14)
                    if !item.durationText.isEmpty { MVDurationTag(text: item.durationText, compact: true) }
                }

                HStack(spacing: 6) {
                    PlatformBadgeLabel(text: item.source.shortName, source: item.source, fontSize: 9)
                    Text(item.title)
                        .font(MVTheme.bodyFont(14, weight: .semibold))
                        .foregroundStyle(MVTheme.ink)
                        .lineLimit(1)
                }
                Text(item.artistName)
                    .font(MVTheme.labelFont(12))
                    .foregroundStyle(MVTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var platformGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 18),
            count: DeviceLayout.usesExpandedLayout ? 3 : 2
        )
    }

    private func platformState(source: MusicSource) -> some View {
        VStack(spacing: 12) {
            if viewModel.unifiedLoadingSources.contains(source) {
                ProgressView().tint(source.themedBadgeColor)
            } else {
                Text(viewModel.unifiedErrors[source] ?? String(localized: "search_no_results"))
                    .font(.rounded(size: 13))
                    .foregroundStyle(Color.monoTextSecondary)
                    .multilineTextAlignment(.center)
                if viewModel.unifiedErrors[source] != nil {
                    Button(String(localized: "radio_retry")) { viewModel.fetchUnified() }
                        .font(.rounded(size: 12, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
    }
}

private struct LegacyMVDiscoverView: View {
    @StateObject private var viewModel = MVDiscoverViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedMV: MVIdItem?
    @State private var selectedMlog: MlogItem?
    @State private var showSublist = false

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            MonoSheetAwareBackground {
                ThemedPageBackground().ignoresSafeArea()
            }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero 区域
                        if let heroMV = viewModel.latestMVs.first {
                            heroSection(mv: heroMV)
                        }

                        VStack(spacing: MVTheme.isAside ? 34 : 28) {
                            // 功能入口：全部浏览 + 我的收藏
                            actionRow

                            // 最新 MV（横向滚动，跳过 Hero 已展示的第一个）
                            if viewModel.latestMVs.count > 1 {
                                mvHorizontalSection(
                                    title: String(localized: "mv_latest"),
                                    subtitle: String(localized: "mv_latest_desc"),
                                    kicker: "NEW ARRIVALS",
                                    mvs: Array(viewModel.latestMVs.dropFirst()),
                                    listType: .latest
                                )
                            }

                            // 热门排行（带排名的列表）
                            if !viewModel.topMVs.isEmpty {
                                mvRankSection(
                                    title: String(localized: "mv_top"),
                                    subtitle: String(localized: "mv_top_desc"),
                                    kicker: "TOP CHARTS",
                                    mvs: viewModel.topMVs,
                                    listType: .top
                                )
                            }

                            // 独家放送（双列网格）
                            if !viewModel.exclusiveMVs.isEmpty {
                                mvGridSection(
                                    title: String(localized: "mv_exclusive"),
                                    subtitle: String(localized: "mv_exclusive_desc"),
                                    kicker: "EXCLUSIVE",
                                    mvs: viewModel.exclusiveMVs,
                                    listType: .exclusive
                                )
                            }

                            // Mlog 音乐短视频
                            if !viewModel.mlogItems.isEmpty {
                                mlogSection
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 120)
                    }
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            if viewModel.latestMVs.isEmpty {
                viewModel.fetchAll()
            }
        }
        .navigationDestination(for: MVListDestination.self) { dest in
            MVFullListView(listType: dest.listType, title: dest.title)

        }
        .fullScreenCover(item: $selectedMV) { item in
            MVPlayerView(mvId: item.id)
        }
        .monoSheet(isPresented: $showSublist, preset: .standard){
            MVSublistSheet()

        }
        .fullScreenCover(item: $selectedMlog) { mlog in
            MlogPlayerView(mlog: mlog)
        }
        .overlay {
            if viewModel.isLoading && viewModel.latestMVs.isEmpty {
                MonoLoadingView(text: "LOADING MV")
            }
        }
    }

    // MARK: - Hero 大图

    private func heroSection(mv: MV) -> some View {
        Button(action: {
            selectedMV = MVIdItem(id: mv.id)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let urlStr = mv.coverUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) {
                            Rectangle().fill(MVTheme.coverPlaceholder)
                        }
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(MVTheme.coverPlaceholder)
                            .frame(height: 220)
                    }

                    // 底部渐变遮罩
                    LinearGradient(
                        colors: [.clear, .black.opacity(MVTheme.isAside ? 0.78 : 0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    if MVTheme.isAside {
                        asideHeroCaption(mv: mv)
                    } else {
                        themedHeroCaption(mv: mv)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: MVTheme.isAside ? 18 : 24, style: .continuous))
                .overlay {
                    if MVTheme.isAside {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.8)
                    } else if NeumorphicStyle.isActive || SequoiaStyle.isActive {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(MVTheme.separator, lineWidth: 0.6)
                    }
                }
                .shadow(
                    color: .black.opacity(MVTheme.isAside ? 0.0 : ((NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 0.04 : 0.1)),
                    radius: SequoiaStyle.isActive ? 12 : 16,
                    x: 0,
                    y: 8
                )
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// aside 编辑部式封面题注：刻度眉题 + 大标题 + 发丝元信息行
    private func asideHeroCaption(mv: MV) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 18, height: 3)

                Text("LATEST RELEASE")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(.white.opacity(0.82))
            }

            Text(mv.displayName)
                .font(.rounded(size: 23, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(mv.artistName ?? "")
                    .font(.rounded(size: 13.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))

                if !mv.playCountText.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 0.7, height: 10)

                    Text(mv.playCountText + String(localized: "mv_play_suffix"))
                        .font(.rounded(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer(minLength: 8)

                MonoIcon(icon: .playCircle, size: 34, color: .white, lineWidth: 1.4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private func themedHeroCaption(mv: MV) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "mv_latest_release"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .clipShape(Capsule())

                Text(mv.displayName)
                    .font(.rounded(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(mv.artistName ?? "")
                        .font(.rounded(size: 14))
                        .foregroundColor(.white.opacity(0.8))

                    if !mv.playCountText.isEmpty {
                        Text(mv.playCountText + String(localized: "mv_play_suffix"))
                            .font(.rounded(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            MonoIcon(icon: .play, size: 48, color: .white)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(20)
    }

    // MARK: - 功能入口行（只放区块里没有的功能）

    private var actionRow: some View {
        HStack(spacing: 12) {
            NavigationLink(value: MVListDestination(title: String(localized: "mv_all"), listType: .all)) {
                actionCard(icon: .gridSquare, title: String(localized: "mv_all"), subtitle: String(localized: "mv_browse_all"))
            }

            Button(action: { showSublist = true }) {
                actionCard(icon: .like, title: String(localized: "mv_my_collection"), subtitle: String(localized: "mv_collected_mv"))
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func actionCard(icon: MonoIcon.IconType, title: String, subtitle: String) -> some View {
        if MVTheme.isAside {
            // aside 编辑部式：发丝描边平面入口，单色细线图标
            HStack(spacing: 11) {
                MonoIcon(icon: icon, size: 17, color: .monoTextPrimary.opacity(0.85), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(size: 14, weight: .semibold))
                        .foregroundColor(.monoTextPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(subtitle)
                        .font(.rounded(size: 11))
                        .foregroundColor(.monoTextSecondary.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                MonoIcon(icon: .chevronRight, size: 11, color: .monoTextSecondary.opacity(0.6))
            }
            .padding(.horizontal, 13)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            HStack(spacing: 12) {
                MonoIcon(icon: icon, size: 20, color: MVTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(MVTheme.selectedIconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MVTheme.bodyFont(14, weight: .semibold))
                        .foregroundColor(MVTheme.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(subtitle)
                        .font(MVTheme.labelFont(11))
                        .foregroundColor(MVTheme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                MonoIcon(icon: .chevronRight, size: 12, color: MVTheme.accent.opacity(0.78))
            }
            .padding(12)
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .themedPageSurface(cornerRadius: MVTheme.cardRadius(), elevated: false)
        }
    }

    // MARK: - 横向滚动区块

    private func mvHorizontalSection(title: String, subtitle: String, kicker: String, mvs: [MV], listType: MVListViewModel.ListType) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: title, subtitle: subtitle, kicker: kicker, listType: listType)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(mvs.prefix(8)) { mv in
                        Button(action: { selectedMV = MVIdItem(id: mv.id) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    coverImage(url: mv.coverUrl, width: 200, height: 112, cornerRadius: MVTheme.isAside ? 12 : 16)

                                    if !mv.durationText.isEmpty {
                                        MVDurationTag(text: mv.durationText)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mv.displayName)
                                        .font(MVTheme.bodyFont(14, weight: .semibold))
                                        .foregroundColor(MVTheme.ink)
                                        .lineLimit(1)
                                    Text(mv.artistName ?? String(localized: "mv_unknown_artist"))
                                        .font(MVTheme.labelFont(12))
                                        .foregroundColor(MVTheme.inkSoft)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 2)
                            }
                            .frame(width: 200)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }

    // MARK: - 双列网格区块

    private func mvGridSection(title: String, subtitle: String, kicker: String, mvs: [MV], listType: MVListViewModel.ListType) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: title, subtitle: subtitle, kicker: kicker, listType: listType)

            let columns = [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(mvs.prefix(6)) { mv in
                    MVGridCard(mv: mv) {
                        selectedMV = MVIdItem(id: mv.id)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - 排行榜区块

    private func mvRankSection(title: String, subtitle: String, kicker: String, mvs: [MV], listType: MVListViewModel.ListType) -> some View {
        VStack(alignment: .leading, spacing: MVTheme.isAside ? 6 : 14) {
            sectionHeader(title: title, subtitle: subtitle, kicker: kicker, listType: listType)

            VStack(spacing: MVTheme.isAside ? 0 : 10) {
                let items = Array(mvs.prefix(5).enumerated())
                ForEach(items, id: \.element.id) { index, mv in
                    MVRowCard(mv: mv, rank: index + 1, showsDivider: index < items.count - 1) {
                        selectedMV = MVIdItem(id: mv.id)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Mlog 音乐短视频

    private var mlogSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitleBlock(
                title: String(localized: "mlog_title"),
                subtitle: String(localized: "mlog_subtitle"),
                kicker: "MLOG"
            )
            .padding(.horizontal, 24)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(viewModel.mlogItems) { mlog in
                        Button(action: { selectedMlog = mlog }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    Group {
                                        if let url = mlog.coverURL {
                                            CachedAsyncImage(url: url) {
                                                RoundedRectangle(cornerRadius: MVTheme.isAside ? 12 : 16, style: .continuous)
                                                    .fill(MVTheme.coverPlaceholder)
                                            }
                                            .aspectRatio(9/16, contentMode: .fill)
                                            .frame(width: 140, height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: MVTheme.isAside ? 12 : 16, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: MVTheme.isAside ? 12 : 16, style: .continuous)
                                                .fill(MVTheme.coverPlaceholder)
                                                .frame(width: 140, height: 200)
                                        }
                                    }
                                    .overlay {
                                        if MVTheme.isAside {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.8)
                                        }
                                    }

                                    // 时长角标
                                    if !mlog.durationText.isEmpty {
                                        MVDurationTag(text: mlog.durationText)
                                    }

                                    // 播放图标
                                    MonoIcon(icon: .play, size: 28, color: .white)
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(width: 140, height: 200)

                                Text(mlog.text)
                                    .font(MVTheme.bodyFont(13, weight: .semibold))
                                    .foregroundColor(MVTheme.ink)
                                    .lineLimit(2)
                                    .frame(width: 140, alignment: .leading)

                                if let song = mlog.song {
                                    HStack(spacing: 4) {
                                        MonoIcon(icon: .musicNote, size: 10, color: MVTheme.inkMuted)
                                        Text(song.name)
                                            .font(MVTheme.labelFont(11))
                                            .foregroundColor(MVTheme.inkSoft)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 140, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }

    // MARK: - 区块标题

    /// 标题块：aside 用眉题刻度 + 大标题；其余主题保持原样
    @ViewBuilder
    private func sectionTitleBlock(title: String, subtitle: String, kicker: String) -> some View {
        if MVTheme.isAside {
            VStack(alignment: .leading, spacing: 7) {
                MVAsideKicker(text: kicker)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.monoTextPrimary)

                    Text(subtitle)
                        .font(.rounded(size: 12))
                        .foregroundColor(.monoTextSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MVTheme.titleFont(22, weight: .semibold))
                    .foregroundColor(MVTheme.ink)
                Text(subtitle)
                    .font(MVTheme.labelFont(14))
                    .foregroundColor(MVTheme.inkSoft)
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String, kicker: String, listType: MVListViewModel.ListType) -> some View {
        HStack(alignment: MVTheme.isAside ? .firstTextBaseline : .bottom) {
            sectionTitleBlock(title: title, subtitle: subtitle, kicker: kicker)

            Spacer()

            NavigationLink(value: MVListDestination(title: title, listType: listType)) {
                if MVTheme.isAside {
                    HStack(spacing: 3) {
                        Text("MORE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.4)
                        MonoIcon(icon: .chevronRight, size: 10, color: .monoTextSecondary.opacity(0.75), lineWidth: 1.6)
                    }
                    .foregroundColor(.monoTextSecondary.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .overlay(Capsule().stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.7))
                } else {
                    HStack(spacing: 4) {
                        Text("mv_more_section")
                            .font(MVTheme.labelFont(14, weight: .semibold))
                            .foregroundColor(MVTheme.accent)
                        MonoIcon(icon: .chevronRight, size: 12, color: MVTheme.accent)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 导航目标

struct MVListDestination: Hashable {
    let title: String
    let listType: MVListViewModel.ListType

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }

    static func == (lhs: MVListDestination, rhs: MVListDestination) -> Bool {
        lhs.title == rhs.title
    }
}

// MARK: - MV 完整列表页

struct MVFullListView: View {
    @StateObject private var viewModel: MVListViewModel
    @State private var selectedMV: MVIdItem?

    let title: String

    init(listType: MVListViewModel.ListType, title: String) {
        _viewModel = StateObject(wrappedValue: MVListViewModel(listType: listType))
        self.title = title
    }

    var body: some View {
        ZStack {
            MonoSheetAwareBackground {
                ThemedPageBackground().ignoresSafeArea()
            }

            VStack(spacing: 0) {
                ScrollView {
                    let columns = [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ]
                    LazyVGrid(columns: columns, spacing: MVTheme.isAside ? 20 : 16) {
                        ForEach(viewModel.mvs) { mv in
                            MVGridCard(mv: mv) {
                                selectedMV = MVIdItem(id: mv.id)
                            }

                            if mv.id == viewModel.mvs.last?.id {
                                Color.clear.frame(height: 1)
                                    .onAppear { viewModel.loadMore() }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    if viewModel.isLoadingMore {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("mv_loading_more")
                                .font(MVTheme.labelFont(13))
                                .foregroundColor(MVTheme.inkSoft)
                        }
                        .padding(.vertical, 14)
                    }

                    if !viewModel.hasMore && !viewModel.mvs.isEmpty {
                        NoMoreDataView()
                    }

                    FloatingBarBottomSpacer()
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            if viewModel.mvs.isEmpty {
                viewModel.fetchInitial()
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.mvs.isEmpty {
                MonoLoadingView(text: "LOADING")
            }
        }
        .fullScreenCover(item: $selectedMV) { item in
            MVPlayerView(mvId: item.id)
        }
    }
}

// MARK: - 已收藏 MV Sheet

struct MVSublistSheet: View {
    @StateObject private var viewModel = MVSublistViewModel()
    @State private var selectedMV: MVIdItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            VStack(alignment: .leading, spacing: 7) {
                if MVTheme.isAside {
                    MVAsideKicker(text: "COLLECTION")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("mv_my_collection")
                        .font(MVTheme.isAside ? .system(size: 22, weight: .bold, design: .rounded) : MVTheme.titleFont(20, weight: .semibold))
                        .foregroundColor(MVTheme.ink)
                    Spacer()
                    if !viewModel.items.isEmpty {
                        Text(String(format: String(localized: "mv_mv_count"), viewModel.items.count))
                            .font(MVTheme.labelFont(13))
                            .foregroundColor(MVTheme.inkSoft)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Rectangle()
                .fill(MVTheme.isAside ? Color.monoSeparator.opacity(0.7) : MVTheme.separator)
                .frame(height: MVTheme.isAside ? 0.6 : 0.5)

            if viewModel.isLoading && viewModel.items.isEmpty {
                Spacer()
                MonoLoadingView(text: "LOADING")
                Spacer()
            } else if viewModel.items.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    MonoIcon(icon: .like, size: 40, color: MVTheme.inkMuted.opacity(0.34))
                    Text("mv_no_collection")
                        .font(MVTheme.bodyFont(15))
                        .foregroundColor(MVTheme.inkSoft)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: MVTheme.isAside ? 0 : 10) {
                        let lastId = viewModel.items.last?.id
                        ForEach(viewModel.items) { item in
                            sublistRow(item: item, showsDivider: item.id != lastId)

                            if item.id == lastId {
                                Color.clear.frame(height: 1)
                                    .onAppear { viewModel.loadMore() }
                            }
                        }

                        if viewModel.isLoadingMore {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("mv_loading_more")
                                    .font(MVTheme.labelFont(13))
                                    .foregroundColor(MVTheme.inkSoft)
                            }
                            .padding(.vertical, 14)
                        }

                        if !viewModel.hasMore && !viewModel.items.isEmpty {
                            NoMoreDataView()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, MVTheme.isAside ? 6 : 14)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            }
        }
        .background {
            Rectangle()
                .fill(SequoiaStyle.isActive ? SequoiaStyle.materialFloating : (NeumorphicStyle.isActive ? NeumorphicStyle.surface : Color.monoGlassTint))
                .monoGlass(cornerRadius: 20)
                .overlay(SequoiaStyle.isActive ? SequoiaStyle.materialChrome.opacity(0.5) : (NeumorphicStyle.isActive ? NeumorphicStyle.surface.opacity(0.38) : Color.monoGlassTint.opacity(0.55)))
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            viewModel.fetchInitial()
        }
        .fullScreenCover(item: $selectedMV) { item in
            MVPlayerView(mvId: item.id)
        }
    }

    @ViewBuilder
    private func sublistRow(item: MVSubItem, showsDivider: Bool) -> some View {
        if MVTheme.isAside {
            asideSublistRow(item: item, showsDivider: showsDivider)
        } else {
            themedSublistRow(item: item)
        }
    }

    /// aside 编辑部式：平排行 + 发丝分隔
    private func asideSublistRow(item: MVSubItem, showsDivider: Bool) -> some View {
        Button(action: {
            if let vid = item.vid, let mvId = Int(vid) {
                selectedMV = MVIdItem(id: mvId)
            }
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        coverImage(url: item.coverUrl, width: 118, height: 66, cornerRadius: 10)

                        if !item.durationText.isEmpty {
                            MVDurationTag(text: item.durationText, compact: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? String(localized: "mv_unknown_name"))
                            .font(.rounded(size: 15, weight: .semibold))
                            .foregroundColor(.monoTextPrimary)
                            .lineLimit(1)

                        if let artist = item.artistName {
                            Text(artist)
                                .font(.rounded(size: 12.5))
                                .foregroundColor(.monoTextSecondary.opacity(0.85))
                                .lineLimit(1)
                        }

                        if !item.playCountText.isEmpty {
                            HStack(spacing: 3) {
                                MonoIcon(icon: .play, size: 8.5, color: .monoTextSecondary.opacity(0.55))
                                Text(item.playCountText)
                                    .font(.rounded(size: 11))
                                    .foregroundColor(.monoTextSecondary.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)

                if showsDivider {
                    Rectangle()
                        .fill(Color.monoSeparator.opacity(0.7))
                        .frame(height: 0.6)
                        .padding(.leading, 132)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.92))
    }

    private func themedSublistRow(item: MVSubItem) -> some View {
        Button(action: {
            if let vid = item.vid, let mvId = Int(vid) {
                selectedMV = MVIdItem(id: mvId)
            }
        }) {
            HStack(spacing: 14) {
                // 封面
                ZStack(alignment: .bottomTrailing) {
                    coverImage(url: item.coverUrl, width: 120, height: 68, cornerRadius: 12)

                    if !item.durationText.isEmpty {
                        MVDurationTag(text: item.durationText, compact: true)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title ?? String(localized: "mv_unknown_name"))
                        .font(MVTheme.bodyFont(15, weight: .semibold))
                        .foregroundColor(MVTheme.ink)
                        .lineLimit(1)

                    if let artist = item.artistName {
                        Text(artist)
                            .font(MVTheme.labelFont(13))
                            .foregroundColor(MVTheme.inkSoft)
                            .lineLimit(1)
                    }

                    if !item.playCountText.isEmpty {
                        HStack(spacing: 3) {
                            MonoIcon(icon: .play, size: 9, color: MVTheme.inkMuted.opacity(0.72))
                            Text(item.playCountText)
                                .font(MVTheme.labelFont(11))
                                .foregroundColor(MVTheme.inkMuted.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(height: 88)
            .padding(10)
            .themedPageSurface(cornerRadius: MVTheme.cardRadius(), elevated: false)
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
    }
}
