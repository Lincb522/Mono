import SwiftUI

/// 播客搜索页面
struct PodcastSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PodcastSearchViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if SignalStyle.isActive {
                    SignalNestedPageHeader(
                        title: String(localized: "podcast_title"),
                        eyebrow: "RADIO SEARCH",
                        icon: .magnifyingGlass,
                        module: .search
                    )
                    .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                }

                // 搜索栏
                searchBar
                    .padding(.top, 8)

                if viewModel.searchText.isEmpty {
                    // 热门电台推荐
                    hotRadiosSection
                } else if viewModel.isSearching && viewModel.results.isEmpty {
                    Spacer()
                    MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "SEARCHING")
                    Spacer()
                } else if !viewModel.searchText.isEmpty && viewModel.results.isEmpty && !viewModel.isSearching {
                    Spacer()
                    emptyResultView
                    Spacer()
                } else {
                    // 搜索结果
                    searchResultsList
                }
            }
            .iPadContentWidth(900)
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            viewModel.fetchHotRadios()
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if SignalStyle.isActive {
                    Text(">")
                        .font(SignalStyle.monoFont(14, weight: .bold))
                        .foregroundStyle(SignalStyle.accent)
                }

                MonoIcon(icon: .magnifyingGlass, size: 15, color: searchAccentColor, lineWidth: 1.4)

                TextField(String(localized: "podcast_search_placeholder"), text: $viewModel.searchText)
                    .font(searchFieldFont)
                    .foregroundColor(primaryTextColor)
                    .monoTextInputBehavior()
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .monoOnSubmit(text: $viewModel.searchText) { _ in
                        isSearchFocused = false
                    }

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        MonoIcon(icon: .xmarkCircle, size: 14, color: secondaryTextColor, lineWidth: 1.2)
                    }
                }
            }
            .padding(.horizontal, ThemedPageStyle.isActive ? 12 : 14)
            .padding(.vertical, (MinimalWhiteStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 11 : 10)
            .background {
                if !ThemedPageStyle.isActive {
                    RoundedRectangle(cornerRadius: searchRadius, style: .continuous)
                        .fill(Color.monoGlassTint.opacity(0.4))
                }
            }
            .themedPageSurface(cornerRadius: searchRadius, elevated: false)
            .clipShape(RoundedRectangle(cornerRadius: searchRadius, style: .continuous))
            .overlay {
                if !ThemedPageStyle.isActive {
                    RoundedRectangle(cornerRadius: searchRadius, style: .continuous)
                        .stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
                }
            }

            Button(String(localized: "podcast_search_cancel")) {
                dismiss()
            }
            .font(searchCancelFont)
            .foregroundColor(searchAccentColor)
        }
        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
        .padding(.bottom, 12)
    }

    // MARK: - 热门电台

    private var hotRadiosSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if SignalStyle.isActive {
                    SignalSectionTitle(title: String(localized: "podcast_hot_radios"))
                        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                } else if ThemedPageStyle.isActive {
                    Text("podcast_hot_radios")
                        .font(sectionTitleFont)
                        .foregroundColor(primaryTextColor)
                        .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                } else {
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(Color.monoAccent)
                            .frame(width: 4, height: 15)
                        Text("podcast_hot_radios")
                            .font(.rounded(size: 19, weight: .bold))
                            .foregroundColor(.monoTextPrimary)
                    }
                    .padding(.horizontal, DeviceLayout.homeHorizontalPadding)
                }

                if viewModel.isLoadingHot {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                        ForEach(viewModel.hotRadios) { radio in
                            NavigationLink(value: PodcastView.PodcastDestination.radioDetail(radio.id)) {
                                radioRow(radio: radio)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, ThemedPageStyle.horizontalInset)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    // MARK: - 搜索结果

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                ForEach(viewModel.results) { radio in
                    NavigationLink(value: PodcastView.PodcastDestination.radioDetail(radio.id)) {
                        radioRow(radio: radio)
                    }
                    .buttonStyle(.plain)

                    // 滚动到底部加载更多
                    if radio.id == viewModel.results.last?.id && viewModel.hasMore {
                        Color.clear.frame(height: 1)
                            .onAppear { viewModel.loadMoreResults() }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 16)
                }

                if !viewModel.hasMore && !viewModel.results.isEmpty {
                    NoMoreDataView()
                }
            }
            .padding(.horizontal, ThemedPageStyle.horizontalInset)
            .padding(.top, ThemedPageStyle.isActive ? 4 : 0)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    // MARK: - 空结果

    private var emptyResultView: some View {
        VStack(spacing: 12) {
            if MinimalWhiteStyle.isActive {
                MinimalWhiteIconBadge(icon: .magnifyingGlass, size: 54)
            } else {
                MonoIcon(icon: .magnifyingGlass, size: 36, color: secondaryTextColor.opacity(0.5))
            }
            Text("podcast_no_results")
                .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(14, weight: .medium) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(15, weight: .medium) : .system(size: 15, weight: .medium, design: .rounded)))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background {
            if MinimalWhiteStyle.isActive {
                MinimalWhiteSurfaceBackground(
                    cornerRadius: MinimalWhiteStyle.cardRadius,
                    elevated: false,
                    tint: MinimalWhiteStyle.glassFill
                )
            }
        }
        .padding(.horizontal, MinimalWhiteStyle.isActive ? DeviceLayout.viewHorizontalPadding : 0)
    }

    // MARK: - 电台行

    @ViewBuilder
    private func radioRow(radio: RadioStation) -> some View {
        if !ThemedPageStyle.isActive {
            AsideRadioListRow(radio: radio)
        } else {
            legacyRadioRow(radio: radio)
        }
    }

    private func legacyRadioRow(radio: RadioStation) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: radio.coverUrl) {
                RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                    .fill(coverPlaceholderFill)
                    .monoGlass(cornerRadius: coverRadius)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
            .overlay(coverStroke)

            VStack(alignment: .leading, spacing: 4) {
                Text(radio.name)
                    .font(rowTitleFont)
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let dj = radio.dj?.nickname {
                        Text(dj)
                            .font(rowMetaFont)
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    if let count = radio.programCount, count > 0 {
                        Text(String(format: String(localized: "podcast_episode_count"), count))
                            .font(rowMetaFont)
                            .foregroundColor(SequoiaStyle.isActive ? SequoiaStyle.inkMuted : (NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : .monoTextSecondary))
                    }
                }
            }

            Spacer()

            MonoIcon(icon: .chevronRight, size: 12, color: searchAccentColor, lineWidth: 1.2)
        }
        .padding(.horizontal, ThemedPageStyle.isActive ? 16 : DeviceLayout.homeHorizontalPadding)
        .padding(.vertical, 12)
        .themedOnlyPageSurface(cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius, elevated: false)
        .contentShape(Rectangle())
    }

    private var coverRadius: CGFloat {
        if SignalStyle.isActive { return 8 }
        if MinimalWhiteStyle.isActive { return 12 }
        return (NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 14 : 10
    }

    @ViewBuilder
    private var coverStroke: some View {
        if SignalStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(SignalStyle.separator.opacity(0.72), lineWidth: 0.7)
        } else if NeumorphicStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(NeumorphicStyle.separator.opacity(0.5), lineWidth: 0.7)
        } else if SequoiaStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(SequoiaStyle.separator.opacity(0.78), lineWidth: 0.6)
        } else if MinimalWhiteStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth)
        }
    }

    private var searchRadius: CGFloat {
        if SignalStyle.isActive { return 9 }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.cardRadius }
        if NeumorphicStyle.isActive { return 18 }
        if SequoiaStyle.isActive { return 16 }
        if !ThemedPageStyle.isActive { return 21 }
        return 12
    }

    private var searchFieldFont: Font {
        if SignalStyle.isActive { return SignalStyle.bodyFont(14, weight: .medium) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.bodyFont(15, weight: .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(15, weight: .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(15, weight: .regular) }
        return .system(size: 15, design: .rounded)
    }

    private var searchCancelFont: Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(12, weight: .bold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(15, weight: .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(15, weight: .semibold) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(15, weight: .semibold) }
        return .system(size: 15, weight: .medium, design: .rounded)
    }

    private var sectionTitleFont: Font {
        if SignalStyle.isActive { return SignalStyle.titleFont(18, weight: .bold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.titleFont(18, weight: .semibold) }
        if MangaStyle.isActive { return MangaStyle.titleFont(18, weight: .black) }
        if MujiStyle.isActive { return MujiStyle.titleFont(17, weight: .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.titleFont(18, weight: .semibold) }
        if SequoiaStyle.isActive { return SequoiaStyle.titleFont(18, weight: .semibold) }
        return .system(size: 18, weight: .bold, design: .rounded)
    }

    private var rowTitleFont: Font {
        if SignalStyle.isActive { return SignalStyle.bodyFont(14, weight: .semibold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.bodyFont(15, weight: .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(15, weight: .semibold) }
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(15, weight: .semibold) }
        return .system(size: 15, weight: .medium, design: .rounded)
    }

    private var rowMetaFont: Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(10, weight: .medium) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(12, weight: .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(12, weight: .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(12, weight: .regular) }
        return .system(size: 12, design: .rounded)
    }

    private var primaryTextColor: Color {
        if SignalStyle.isActive { return SignalStyle.ink }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        return .monoTextPrimary
    }

    private var secondaryTextColor: Color {
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        return .monoTextSecondary
    }

    private var searchAccentColor: Color {
        if SignalStyle.isActive { return SignalStyle.accent }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        return .monoTextSecondary
    }

    private var coverPlaceholderFill: Color {
        if SignalStyle.isActive { return SignalStyle.controlPressed }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.controlGlassFill }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        if SequoiaStyle.isActive { return SequoiaStyle.materialList }
        return Color.monoGlassTint
    }
}
