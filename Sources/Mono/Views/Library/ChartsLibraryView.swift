import Combine
import QQMusicKit
import SwiftUI
import UniformTypeIdentifiers

struct ChartsLibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    typealias Theme = PlaylistDetailView.Theme

    private let officialIds: Set<Int> = [19_723_756, 3_779_629, 2_884_035, 3_778_678]

    private var officialCharts: [TopList] {
        viewModel.displayedTopLists.filter { officialIds.contains($0.id) }
    }

    private var otherCharts: [TopList] {
        viewModel.displayedTopLists.filter { !officialIds.contains($0.id) }
    }

    let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: DeviceLayout.artistGridColumns)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MusicSourcePicker(source: $viewModel.chartsSource, sources: [.ncm, .qq, .kugou, .appleMusic], usesPlatformTint: false)
                Spacer()
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.top, 4)
            .onChange(of: viewModel.chartsSource) { _, newSource in
                viewModel.fetchChartsForSelectedSource()
            }

            if viewModel.chartsSource == .qq {
                qqChartsContent
            } else {
                ncmChartsContent
            }
        }
        .background(Color.clear)
    }

    // MARK: - NCM Charts

    private var ncmChartsContent: some View {
        ScrollView {
            if viewModel.isLoadingDisplayedCharts && viewModel.displayedTopLists.isEmpty {
                LibraryLoadingStateView(horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if viewModel.displayedTopLists.isEmpty {
                if NeumorphicStyle.isActive {
                    NeumorphicLibraryEmptyState(
                        icon: .chart,
                        title: String(localized: "empty_no_charts"),
                        tint: NeumorphicStyle.red
                    )
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.top, 24)
                } else {
                    VStack(spacing: 16) {
                        MonoIcon(icon: .chart, size: 50, color: Theme.secondaryText.opacity(0.5))
                        Text(LocalizedStringKey("empty_no_charts"))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.top, 50)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    if !officialCharts.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(LocalizedStringKey("charts_official"))
                                .font(NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(18, weight: .semibold) : .system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : Theme.text)
                                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

                            ScrollView(.horizontal) {
                                HStack(spacing: 14) {
                                    ForEach(officialCharts) { list in
                                        NavigationLink(value: chartDestination(list)) {
                                            OfficialChartCard(list: list)
                                        }
                                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                                    }
                                }
                                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                            }
                            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                        }
                    }

                    if !otherCharts.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(LocalizedStringKey("charts_more"))
                                .font(NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(18, weight: .semibold) : .system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : Theme.text)
                                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(otherCharts) { list in
                                    NavigationLink(value: chartDestination(list)) {
                                        CompactChartCard(list: list)
                                    }
                                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
                                }
                            }
                            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                        }
                    }
                }
                .padding(.top, 8)
            }

            FloatingBarBottomSpacer()
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshCharts()
        }
    }

    // MARK: - QQ Charts

    private var qqChartsContent: some View {
        ScrollView {
            if viewModel.isLoadingQQCharts && viewModel.qqTopLists.isEmpty {
                LibraryLoadingStateView(horizontalPadding: DeviceLayout.viewHorizontalPadding)
            } else if viewModel.qqTopLists.isEmpty {
                if NeumorphicStyle.isActive {
                    NeumorphicLibraryEmptyState(
                        icon: .chart,
                        title: String(localized: "暂无QCM排行榜"),
                        tint: MusicSource.qqmusic.themedBadgeColor
                    )
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                    .padding(.top, 24)
                } else {
                    VStack(spacing: 16) {
                        MonoIcon(icon: .chart, size: 50, color: Theme.secondaryText.opacity(0.5))
                        Text("暂无QCM排行榜")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.top, 50)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(viewModel.qqTopLists) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(group.groupName)
                                .font(NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(18, weight: .semibold) : .system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : Theme.text)
                                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)

                            if group.groupId == 0 || group.items.count <= 4 {
                                // 官方榜：横向大卡片
                                ScrollView(.horizontal) {
                                    HStack(spacing: 14) {
                                        ForEach(group.items) { item in
                                            NavigationLink(value: qqChartDestination(item)) {
                                                QQOfficialChartCard(item: item)
                                            }
                                            .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                                        }
                                    }
                                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                                }
                                .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                            } else {
                                // 其他榜：三列网格
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(group.items) { item in
                                        NavigationLink(value: qqChartDestination(item)) {
                                            QQChartCard(item: item)
                                        }
                                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
                                    }
                                }
                                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }

            FloatingBarBottomSpacer()
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshQQCharts()
        }
    }

    // MARK: - Helpers

    private func chartDestination(_ list: TopList) -> LibraryViewModel.NavigationDestination {
        .playlist(list.playlist())
    }

    private func qqChartDestination(_ item: QQTopListItem) -> LibraryViewModel.NavigationDestination {
        .playlist(Playlist(
            id: item.topId, name: item.title, coverImgUrl: item.coverUrl,
            picUrl: nil, trackCount: nil, playCount: nil,
            subscribedCount: nil, shareCount: nil, commentCount: nil,
            creator: nil, description: item.intro.isEmpty ? nil : item.intro,
            tags: nil, source: .qqmusic, isTopList: true
        ))
    }

    private func refreshCharts() async {
        viewModel.fetchChartsForSelectedSource(force: true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }

    private func refreshQQCharts() async {
        viewModel.fetchChartsForSelectedSource(force: true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
}

// MARK: - QQ 排行榜卡片

struct QQChartCard: View {
    let item: QQTopListItem
    typealias Theme = PlaylistDetailView.Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = item.coverURL {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.monoSeparator)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.monoSeparator)
                    .aspectRatio(1, contentMode: .fit)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .semibold) : .system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 32, alignment: .topLeading)

                Text(item.subtitle.isEmpty ? " " : item.subtitle)
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(10, weight: .medium) : .system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(NeumorphicStyle.isActive ? 8 : 0)
        .background {
            if NeumorphicStyle.isActive {
                NeumorphicSurfaceBackground(cornerRadius: 20, elevated: true, lightweight: true)
            }
        }
    }
}

// MARK: - QQ 官方排行榜大卡片

struct QQOfficialChartCard: View {
    let item: QQTopListItem
    typealias Theme = PlaylistDetailView.Theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = item.coverURL {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.monoSeparator)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: DeviceLayout.chartCardSize, height: DeviceLayout.chartCardSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.monoSeparator)
                    .frame(width: DeviceLayout.chartCardSize, height: DeviceLayout.chartCardSize)
            }

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: DeviceLayout.chartCardSize, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
        }
        .frame(width: DeviceLayout.chartCardSize, height: DeviceLayout.chartCardSize)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

// MARK: - 官方榜单大卡片

struct OfficialChartCard: View {
    let list: TopList
    typealias Theme = PlaylistDetailView.Theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: list.coverUrl?.sized(600)) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.monoSeparator)
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: DeviceLayout.chartCardSize, height: DeviceLayout.chartCardSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(list.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(list.updateFrequency)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(14)
            .frame(width: DeviceLayout.chartCardSize, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
        }
        .frame(width: DeviceLayout.chartCardSize, height: DeviceLayout.chartCardSize)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

// MARK: - 紧凑榜单卡片

struct CompactChartCard: View {
    let list: TopList
    typealias Theme = PlaylistDetailView.Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: list.coverUrl?.sized(400)) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.monoSeparator)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .semibold) : .system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 32, alignment: .topLeading)

                Text(list.updateFrequency)
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(10, weight: .medium) : .system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(NeumorphicStyle.isActive ? 8 : 0)
        .background {
            if NeumorphicStyle.isActive {
                NeumorphicSurfaceBackground(cornerRadius: 20, elevated: true, lightweight: true)
            }
        }
    }
}

// MARK: - Components

struct LibraryPlaylistRow: View {
    let playlist: Playlist
    typealias Theme = PlaylistDetailView.Theme

    var body: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: playlist.coverUrl?.sized(200)) {
                PetWhiteStyle.isActive ? PetWhiteStyle.surfacePressed : Color.gray.opacity(0.1)
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: PetWhiteStyle.isActive ? 64 : DeviceLayout.listRowCoverStandard, height: PetWhiteStyle.isActive ? 64 : DeviceLayout.listRowCoverStandard)
            .cornerRadius(PetWhiteStyle.isActive ? 18 : (CapsuleStyle.isActive ? 16 : (SequoiaStyle.isActive ? 14 : 12)))
            .overlay {
                if PetWhiteStyle.isActive {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PetWhiteStyle.stroke, lineWidth: 1)
                } else if SequoiaStyle.isActive {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SequoiaStyle.separator.opacity(0.78), lineWidth: 0.6)
                } else if CapsuleStyle.isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CapsuleStyle.hairline.opacity(0.7), lineWidth: 0.8)
                }
            }
            .shadow(color: CapsuleStyle.isActive ? Color.clear : (SequoiaStyle.isActive ? Color.black.opacity(0.04) : Color.black.opacity(0.08)), radius: CapsuleStyle.isActive ? 0 : (SequoiaStyle.isActive ? 3 : 4), x: 0, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(PetWhiteStyle.isActive ? PetWhiteStyle.bodyFont(16, weight: .black) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .semibold) : (CapsuleStyle.isActive ? CapsuleStyle.bodyFont(15, weight: .bold) : (SequoiaStyle.isActive ? SequoiaStyle.bodyFont(15, weight: .semibold) : .system(size: 15, weight: .semibold, design: .rounded)))))
                    .foregroundColor(PetWhiteStyle.isActive ? PetWhiteStyle.ink : (NeumorphicStyle.isActive ? NeumorphicStyle.ink : (CapsuleStyle.isActive ? CapsuleStyle.ink : (SequoiaStyle.isActive ? SequoiaStyle.ink : Theme.text))))
                    .lineLimit(1)

                Text(String(format: NSLocalizedString("track_count_songs", comment: ""), playlist.trackCount ?? 0))
                    .font(PetWhiteStyle.isActive ? PetWhiteStyle.labelFont(12, weight: .semibold) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : (CapsuleStyle.isActive ? CapsuleStyle.labelFont(12, weight: .semibold) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(12, weight: .regular) : .system(size: 12, weight: .medium, design: .rounded)))))
                    .foregroundColor(PetWhiteStyle.isActive ? PetWhiteStyle.inkSoft : (NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : (CapsuleStyle.isActive ? CapsuleStyle.inkSoft : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : Theme.secondaryText))))
            }

            Spacer()

            if PetWhiteStyle.isActive {
                PetWhitePackIcon(icon: .chevronRight, size: 16, visualScale: 1.05, fallbackColor: PetWhiteStyle.inkMuted)
            } else {
                MonoIcon(icon: .chevronRight, size: 12, color: (NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : (CapsuleStyle.isActive ? CapsuleStyle.inkMuted : (SequoiaStyle.isActive ? SequoiaStyle.inkMuted : Theme.secondaryText))).opacity(0.7))
            }
        }
        .padding(PetWhiteStyle.isActive ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if PetWhiteStyle.isActive {
                PetWhiteSurfaceBackground(cornerRadius: 22, elevated: false, tint: PetWhiteStyle.surfaceRaised, accent: (playlist.source ?? .netease).themedBadgeColor)
            } else if NeumorphicStyle.isActive {
                NeumorphicSurfaceBackground(cornerRadius: 20, elevated: true, lightweight: true)
            } else if CapsuleStyle.isActive {
                CapsuleFlatRowBackground(cornerRadius: 18)
            } else if SequoiaStyle.isActive {
                SequoiaSurfaceBackground(cornerRadius: 20, elevated: false, role: .list)
            } else {
                Color.clear.monoGlass(cornerRadius: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PetWhiteStyle.isActive ? 22 : (NeumorphicStyle.isActive ? 20 : (CapsuleStyle.isActive ? 18 : (SequoiaStyle.isActive ? 20 : 18))), style: .continuous))
        .contentShape(Rectangle())
    }
}
