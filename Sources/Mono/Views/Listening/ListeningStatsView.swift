import SwiftUI

// MARK: - 听歌统计页面

/// 本地听歌统计 —— 本周真实播放时长第一的歌曲封面作为沉浸头图，
/// 下方展示核心指标、报告入口、周期走势、时段分布与歌曲/歌手排行。
/// 数据来自独立播放日志（清空最近播放不受影响）。
struct ListeningStatsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var aiInsightAgent = AIListeningInsightAgent.shared
    @State private var selectedPeriod: ListeningStatsService.Period = .week
    @State private var stats: ListeningStatsService.Stats = .empty
    @State private var weeklyStats: ListeningStatsService.Stats = .empty
    @State private var isLoading = true
    @State private var refreshTask: Task<Void, Never>?
    @State private var showClearAlert = false
    @State private var showMoreMenu = false
    @State private var presentedReportKind: ListeningReportKind?
    @State private var reportSummaries: [ReportCardSummary] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            immersivePageBackground

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    statsHeader

                    VStack(alignment: .leading, spacing: 26) {
                        periodPicker

                        if stats.totalPlays == 0 && !isLoading {
                            emptyState
                        } else {
                            if settings.listeningReportsEnabled, !reportSummaries.isEmpty {
                                reportCards
                            }

                            if !isLoading {
                                AIListeningInsightSection(
                                    agent: aiInsightAgent,
                                    input: .statistics(period: selectedPeriod, stats: stats)
                                )
                            }

                            if stats.trend.contains(where: { $0.seconds > 0 || $0.plays > 0 }) {
                                trendSection
                            }

                            if stats.hourHistogram.contains(where: { $0 > 0 }) {
                                hourSection
                            }

                            if !stats.topSongs.isEmpty {
                                topSongsSection
                            }

                            if !stats.topArtists.isEmpty {
                                topArtistsSection
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .background(immersiveContentTransition)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: settings.globalThemeId == .default ? [] : .top)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton(iconColor: settings.globalThemeId == .default ? .monoTextPrimary : .white)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showMoreMenu.toggle()
                    }
                } label: {
                    if settings.globalThemeId == .default {
                        DefaultHeaderActionLabel(icon: .more, title: String(localized: "player_more_title"))
                    } else {
                        MonoIcon(icon: .more, size: 17, color: .white)
                            .frame(width: 36, height: 36)
                            .monoGlassCircle(interactive: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "player_more_title"))
            }
        }
        .overlay {
            if showMoreMenu {
                MonoMoreMenuOverlay(
                    isPresented: $showMoreMenu,
                    title: String(localized: "player_more_title"),
                    isDarkBackground: colorScheme == .dark
                ) {
                    listeningStatsMoreMenu
                }
                .zIndex(20)
            }
        }
        .alert(String(localized: "确认清理"), isPresented: $showClearAlert) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "清理"), role: .destructive) {
                ListeningStatsService.shared.clearAllData()
                refreshStats()
            }
        } message: {
            Text(String(localized: "将清除所有本地播放统计记录，此操作不可撤销"))
        }
        .task {
            refreshStats()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .onChange(of: selectedPeriod) { _, _ in
            refreshStats()
        }
        .fullScreenCover(item: $presentedReportKind) { kind in
            ListeningReportView(kind: kind)
        }
    }

    private var weeklyArtworkURL: URL? {
        weeklyStats.topSongs.first?
            .coverUrl
            .flatMap(URL.init(string:))
    }

    /// 固定在滚动层之后的封面氛围。只渲染一张缓存图，避免把大图模糊
    /// 放进 LazyVStack 后随滚动反复失效。
    private var immersivePageBackground: some View {
        GeometryReader { proxy in
            ZStack {
                if SignalStyle.isActive {
                    SignalRootBackdrop()
                } else {
                    ThemedPageBackground(useRenderLayer: false)
                }

                if !SignalStyle.isActive, let url = weeklyArtworkURL {
                    CachedAsyncImage(
                        url: url.artworkURL(atLeastPixelSize: 1_536),
                        width: 768,
                        height: 768
                    ) {
                        immersiveArtworkFallback
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1.08)
                    .blur(radius: 34, opaque: true)
                    .saturation(1.12)
                    .opacity(colorScheme == .dark ? 0.5 : 0.36)
                    .clipped()
                }

                if !SignalStyle.isActive {
                    Color.monoBackground
                        .opacity(colorScheme == .dark ? 0.38 : 0.5)

                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.2), location: 0),
                            .init(color: Color.monoBackground.opacity(0.28), location: 0.32),
                            .init(color: Color.monoBackground.opacity(0.62), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var immersiveContentTransition: some View {
        LinearGradient(
            stops: [
                .init(
                    color: Color.monoBackground.opacity(colorScheme == .dark ? 0.72 : 0.82),
                    location: 0
                ),
                .init(
                    color: Color.monoBackground.opacity(colorScheme == .dark ? 0.58 : 0.7),
                    location: 0.18
                ),
                .init(
                    color: Color.monoBackground.opacity(colorScheme == .dark ? 0.48 : 0.62),
                    location: 1
                ),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var listeningStatsMoreMenu: some View {
        VStack(alignment: .leading, spacing: 16) {
            MonoMoreMenuSection(title: String(localized: "more_menu_reports_section")) {
                MonoMoreMenuGroup {
                    MonoMoreMenuToggleRow(
                        icon: .chart,
                        title: String(localized: "日报 / 周报 / 月报 / 年报"),
                        isOn: $settings.listeningReportsEnabled
                    )

                    if settings.listeningReportsEnabled {
                        MonoMoreMenuDivider()

                        MonoMoreMenuToggleRow(
                            icon: .history,
                            title: String(localized: "每周自动弹出"),
                            isOn: $settings.listeningReportWeeklyPopupEnabled
                        )

                        MonoMoreMenuDivider()

                        MonoMoreMenuToggleRow(
                            icon: .clock,
                            title: String(localized: "每月自动弹出"),
                            isOn: $settings.listeningReportMonthlyPopupEnabled
                        )
                    }
                }
            }

            MonoMoreMenuSection(title: String(localized: "more_menu_data_section")) {
                MonoMoreMenuGroup {
                    MonoMoreMenuRow(
                        icon: .trash,
                        title: String(localized: "清理全部数据"),
                        isDestructive: true
                    ) {
                        showMoreMenu = false
                        showClearAlert = true
                    }
                }
            }
        }
    }

    // MARK: - 报告入口

    private struct ReportCardSummary: Identifiable {
        let kind: ListeningReportKind
        let periodLabel: String
        let durationText: String?

        var id: String { kind.rawValue }
    }

    private var reportCards: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(String(localized: "听歌报告"))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.monoTextPrimary)

            HStack(spacing: 0) {
                ForEach(Array(reportSummaries.enumerated()), id: \.element.id) { index, summary in
                    reportCard(summary)

                    if index < reportSummaries.count - 1 {
                        Rectangle()
                            .fill(Color.monoTextPrimary.opacity(0.09))
                            .frame(width: 0.5, height: 32)
                    }
                }
            }
            .padding(.vertical, 7)
            .themedPageSurface(cornerRadius: 16, elevated: true, mangaTint: MangaStyle.bubbleWhite)
        }
    }

    private func reportCard(_ summary: ReportCardSummary) -> some View {
        Button {
            presentedReportKind = summary.kind
        } label: {
            VStack(spacing: 6) {
                Text(summary.kind.shortTitle)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)

                Text(summary.durationText ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        summary.durationText == nil
                            ? Color.monoTextSecondary.opacity(0.45)
                            : Color.monoTextPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.kind.title)，\(summary.periodLabel)")
        .accessibilityValue(summary.durationText ?? String(localized: "暂无记录"))
    }

    // MARK: - 周期选择器（左对齐胶囊分段）

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ListeningStatsService.Period.allCases) { period in
                    let selected = selectedPeriod == period

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            selectedPeriod = period
                        }
                    } label: {
                        Text(period.rawValue)
                            .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(
                                selected
                                    ? Color.monoTextPrimary
                                    : Color.monoTextSecondary.opacity(0.8)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    selected
                                        ? Color.monoTextPrimary.opacity(0.08)
                                        : Color.clear
                                )
                            )
                            .overlay(
                                Capsule().stroke(
                                    selected
                                        ? Color.monoTextPrimary.opacity(0.1)
                                        : Color.monoTextPrimary.opacity(0.05),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Color.monoBackground.opacity(colorScheme == .dark ? 0.48 : 0.62))
                .background(.ultraThinMaterial, in: Capsule())
        )
    }

    // MARK: - 沉浸式周榜头部

    @ViewBuilder
    private var statsHeader: some View {
        if settings.globalThemeId == .default {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(localized: "听歌时长"))
                        .font(.subheadline)
                        .foregroundStyle(Color.monoTextSecondary)
                    Spacer(minLength: 0)
                    Text(isLoading ? "—" : stats.formattedDuration)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.monoTextPrimary)
                }
                if let song = weeklyStats.topSongs.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "本周播放时长第一"))
                            .font(.caption)
                            .foregroundStyle(Color.monoTextSecondary)
                        Text(song.name)
                            .font(.headline)
                            .foregroundStyle(Color.monoTextPrimary)
                            .lineLimit(2)
                        Text("\(song.artistName) · \(formatDuration(song.totalDuration))")
                            .font(.subheadline)
                            .foregroundStyle(Color.monoTextSecondary)
                    }
                } else {
                    Text(String(localized: "本周暂无有效播放"))
                        .font(.subheadline)
                        .foregroundStyle(Color.monoTextSecondary)
                }
                immersiveMetrics
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        } else if SignalStyle.isActive {
            signalStatsHeader
        } else {
            immersiveHeader
        }
    }

    private var signalStatsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            SignalNestedPageHeader(
                title: String(localized: "听歌统计"),
                eyebrow: "LISTENING DATA",
                icon: .chart,
                module: .playback
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "听歌时长"))
                        .font(SignalStyle.labelFont(10, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(SignalStyle.inkSoft)

                    Spacer()

                    SignalPill(text: selectedPeriod.rawValue, tint: SignalStyle.accent, compact: true)
                }

                Text(isLoading ? "—" : stats.formattedDuration)
                    .font(SignalStyle.titleFont(38, weight: .bold))
                    .foregroundStyle(SignalStyle.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                HStack(spacing: 0) {
                    signalMetric(value: isLoading ? "—" : "\(stats.totalPlays)", label: String(localized: "有效播放"))
                    signalMetricDivider
                    signalMetric(value: isLoading ? "—" : "\(stats.completionRate)%", label: String(localized: "完播率"))
                    signalMetricDivider
                    signalMetric(value: isLoading ? "—" : "\(stats.uniqueSongs)", label: String(localized: "歌曲"))
                }
            }
            .padding(16)
            .background(SignalSurfaceBackground(cornerRadius: SignalStyle.cardRadius, elevated: true))
        }
        .padding(.horizontal, 20)
        .padding(.top, 88)
    }

    private func signalMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SignalStyle.titleFont(18, weight: .bold))
                .foregroundStyle(SignalStyle.accent)
                .monospacedDigit()
            Text(label)
                .font(SignalStyle.labelFont(9, weight: .medium))
                .foregroundStyle(SignalStyle.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signalMetricDivider: some View {
        Rectangle()
            .fill(SignalStyle.separator)
            .frame(width: 1, height: 30)
            .padding(.horizontal, 10)
    }

    private var immersiveHeader: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)

            ZStack(alignment: .bottomLeading) {
                immersiveHeaderArtwork(width: width, height: height)

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.46), location: 0),
                        .init(color: Color.black.opacity(0.04), location: 0.34),
                        .init(color: Color.black.opacity(0.28), location: 0.58),
                        .init(color: Color.black.opacity(0.96), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.5),
                        Color.clear,
                        Color.black.opacity(0.16),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 88)

                    Text("\(selectedPeriod.rawValue) · \(String(localized: "听歌时长"))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(isLoading ? "—" : stats.formattedDuration)
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(.numericText())
                        .padding(.top, 5)

                    if let song = weeklyStats.topSongs.first {
                        Text(String(localized: "本周播放时长第一"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.64))
                            .padding(.top, 17)

                        Text(song.name)
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .padding(.top, 3)

                        HStack(spacing: 6) {
                            Text(song.artistName)
                            Text("·")
                            Text(formatDuration(song.totalDuration))
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    } else {
                        Text(String(localized: "本周暂无有效播放"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.top, 17)
                    }

                    immersiveMetrics
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(width: width, height: height, alignment: .bottomLeading)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(height: 540)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func immersiveHeaderArtwork(width: CGFloat, height: CGFloat) -> some View {
        if let url = weeklyArtworkURL {
            CachedAsyncImage(
                url: url.artworkURL(atLeastPixelSize: 2_304),
                width: 1_152,
                height: 1_152
            ) {
                immersiveArtworkFallback
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
        } else {
            immersiveArtworkFallback
                .frame(width: width, height: height)
        }
    }

    private var immersiveArtworkFallback: some View {
        LinearGradient(
            colors: [
                Color.monoAccent.opacity(0.88),
                Color.black.opacity(0.78),
                Color.black,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var immersiveMetrics: some View {
        HStack(spacing: 0) {
            immersiveMetric(
                value: isLoading ? "—" : "\(stats.totalPlays)",
                label: String(localized: "有效播放")
            )
            immersiveMetricDivider
            immersiveMetric(
                value: isLoading ? "—" : "\(stats.completionRate)%",
                label: String(localized: "完播率")
            )
            immersiveMetricDivider
            immersiveMetric(
                value: isLoading ? "—" : "\(stats.uniqueSongs)",
                label: String(localized: "歌曲")
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(settings.globalThemeId == .default ? Color.monoSeparator.opacity(0.35) : Color.black.opacity(0.32))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(settings.globalThemeId == .default ? Color.clear : Color.white.opacity(0.16), lineWidth: 0.8)
        }
    }

    private func immersiveMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(settings.globalThemeId == .default ? .headline : .system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(settings.globalThemeId == .default ? Color.monoTextPrimary : Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(settings.globalThemeId == .default ? 1 : 0.7)
                .contentTransition(.numericText())

            Text(label)
                .font(settings.globalThemeId == .default ? .caption : .system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(settings.globalThemeId == .default ? Color.monoTextSecondary : Color.white.opacity(0.62))
                .lineLimit(settings.globalThemeId == .default ? 2 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var immersiveMetricDivider: some View {
        Rectangle()
            .fill(settings.globalThemeId == .default ? Color.monoSeparator : Color.white.opacity(0.14))
            .frame(width: 0.5, height: 26)
    }

    // MARK: - 走势（随周期自适应：周 7 天 / 月逐日 / 年逐月 / 其他 14 天）

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(stats.trendTitle)

            let maxSeconds = max(stats.trend.map(\.seconds).max() ?? 1, 1)
            let compact = stats.trend.count > 16

            HStack(alignment: .bottom, spacing: compact ? 2.5 : 5) {
                ForEach(stats.trend) { bucket in
                    let isCurrent = isCurrentTrendBucket(bucket)

                    VStack(spacing: 5) {
                        statsTrackBar(
                            value: bucket.seconds,
                            maximum: maxSeconds,
                            isHighlighted: isCurrent,
                            height: 64,
                            width: compact ? 5 : (stats.trend.count <= 7 ? 14 : 8)
                        )

                        if !compact {
                            Text(trendLabel(bucket.date))
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isCurrent
                                        ? Color.monoAccent
                                        : Color.monoTextSecondary.opacity(0.7)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if compact {
                compactTrendAxis
            }
        }
    }

    /// 本月逐日走势的稀疏横轴（1 / 8 / 15 / 22 / 月末）
    private var compactTrendAxis: some View {
        HStack {
            Text("1")
            Spacer()
            Text("8")
            Spacer()
            Text("15")
            Spacer()
            Text("22")
            Spacer()
            Text("\(stats.trend.count)")
        }
        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color.monoTextSecondary.opacity(0.65))
    }

    /// 当前所在桶（今天 / 本月）高亮
    private func isCurrentTrendBucket(_ bucket: ListeningStatsService.DayBucket) -> Bool {
        let calendar = Calendar.current
        switch stats.trendGranularity {
        case .day:
            return calendar.isDateInToday(bucket.date)
        case .month:
            return calendar.isDate(bucket.date, equalTo: Date(), toGranularity: .month)
        }
    }

    private func trendLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        switch stats.trendGranularity {
        case .day:
            if selectedPeriod == .week {
                let weekday = calendar.component(.weekday, from: date)
                let symbols = [
                    String(localized: "日"), String(localized: "一"), String(localized: "二"),
                    String(localized: "三"), String(localized: "四"), String(localized: "五"),
                    String(localized: "六"),
                ]
                return symbols[(weekday - 1) % 7]
            }
            return "\(calendar.component(.day, from: date))"
        case .month:
            return "\(calendar.component(.month, from: date))"
        }
    }

    // MARK: - 24 小时分布

    private var hourSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                String(localized: "收听时段"),
                trailing: stats.peakHour.map { String(format: String(localized: "峰值 %02d:00"), $0) }
            )

            let maxValue = max(stats.hourHistogram.max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = stats.hourHistogram[hour]
                    let isPeak = stats.peakHour == hour

                    statsTrackBar(
                        value: value,
                        maximum: maxValue,
                        isHighlighted: isPeak,
                        height: 44,
                        width: 6
                    )
                        .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text("0")
                Spacer()
                Text("6")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("23")
            }
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.monoTextSecondary.opacity(0.65))
        }
    }

    // MARK: - TOP 歌曲（序号发丝线行）

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(localized: "最常听的歌曲"))
                .padding(.bottom, 8)

            ForEach(Array(stats.topSongs.enumerated()), id: \.element.id) { index, song in
                topSongRow(song: song, rank: index + 1)
            }
        }
    }

    private func topSongRow(song: ListeningStatsService.SongStat, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: rank <= 3 ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    rank <= 3
                        ? Color.monoAccent
                        : Color.monoTextSecondary.opacity(0.7)
                )
                .frame(width: 22, alignment: .leading)

            CachedAsyncImage(url: song.coverUrl.flatMap(URL.init(string:)), width: 42, height: 42) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.monoTextPrimary.opacity(0.06))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.monoTextPrimary.opacity(0.07), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(song.playCount) 次")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.monoTextPrimary)

                if song.totalDuration > 0 {
                    Text(formatDuration(song.totalDuration))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.monoTextSecondary)
                }
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.monoTextPrimary.opacity(0.055))
                .frame(height: 0.5)
                .padding(.leading, 34)
        }
    }

    // MARK: - TOP 歌手（序号发丝线行）

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(String(localized: "最常听的歌手"))
                .padding(.bottom, 8)

            ForEach(Array(stats.topArtists.enumerated()), id: \.element.id) { index, artist in
                topArtistRow(artist: artist, rank: index + 1)
            }
        }
    }

    private func topArtistRow(artist: ListeningStatsService.ArtistStat, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: rank <= 3 ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    rank <= 3
                        ? Color.monoAccent
                        : Color.monoTextSecondary.opacity(0.7)
                )
                .frame(width: 22, alignment: .leading)

            CachedAsyncImage(url: artist.representativeCoverUrl.flatMap(URL.init(string:)), width: 42, height: 42) {
                Circle()
                    .fill(Color.monoTextPrimary.opacity(0.06))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.monoTextSecondary.opacity(0.5))
                    )
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.monoTextPrimary.opacity(0.07), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .lineLimit(1)

                if artist.totalDuration > 0 {
                    Text(formatDuration(artist.totalDuration))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.monoTextSecondary)
                }
            }

            Spacer(minLength: 4)

            Text("\(artist.playCount) 次")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.monoTextPrimary)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.monoTextPrimary.opacity(0.055))
                .frame(height: 0.5)
                .padding(.leading, 34)
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42))
                .foregroundStyle(Color.monoTextSecondary.opacity(0.5))

            Text(String(localized: "暂无播放记录"))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary)

            Text(String(localized: "播放歌曲后这里会显示你的听歌统计"))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.monoTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    // MARK: - 辅助

    private func statsTrackBar(
        value: Int,
        maximum: Int,
        isHighlighted: Bool,
        height: CGFloat,
        width: CGFloat
    ) -> some View {
        let ratio = CGFloat(value) / CGFloat(max(maximum, 1))
        let cornerRadius = min(2.5, width * 0.34)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.monoTextPrimary.opacity(0.065))

            if value > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHighlighted ? Color.monoAccent : Color.monoTextPrimary.opacity(0.26))
                    .frame(height: max(3, height * ratio))
            }
        }
        .frame(width: width, height: height)
    }

    /// 强调色竖标小节头（与搜索/队列一致的语言）
    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.monoAccent)
                .frame(width: 3, height: 13)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.monoTextPrimary)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.monoTextSecondary)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func refreshStats() {
        refreshTask?.cancel()
        let period = selectedPeriod
        isLoading = true
        refreshTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let result = ListeningStatsService.shared.fetchStats(for: period)
            let weekResult = period == .week
                ? result
                : ListeningStatsService.shared.fetchStats(for: .week)
            let summaries = makeReportSummaries()
            withAnimation(.easeOut(duration: 0.2)) {
                stats = result
                weeklyStats = weekResult
                reportSummaries = summaries
                isLoading = false
            }
            refreshTask = nil
        }
    }

    private func makeReportSummaries() -> [ReportCardSummary] {
        let service = ListeningReportService.shared
        return ListeningReportKind.allCases.map { kind in
            let interval = service.defaultInterval(for: kind)
            let seconds = service.totalSeconds(in: interval)
            // 年报直接标年份，其余报告优先使用相对日期。
            let label = kind == .year
                ? ListeningReportFormatter.periodTitle(kind: kind, interval: interval)
                : (ListeningReportFormatter.relativeLabel(kind: kind, interval: interval)
                    ?? ListeningReportFormatter.periodTitle(kind: kind, interval: interval))
            return ReportCardSummary(
                kind: kind,
                periodLabel: label,
                durationText: seconds > 0
                    ? ListeningReportFormatter.compactDuration(seconds: seconds)
                    : nil
            )
        }
    }
}
