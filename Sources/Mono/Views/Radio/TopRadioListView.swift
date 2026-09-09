import SwiftUI

/// 热门电台完整列表（查看更多），无限加载
struct TopRadioListView: View {
    let title: String
    let listType: ListType

    @StateObject private var viewModel: TopRadioListViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    enum ListType: Equatable {
        case hot
        case toplist
    }

    init(title: String, listType: ListType) {
        self.title = title
        self.listType = listType
        _viewModel = StateObject(wrappedValue: TopRadioListViewModel(listType: listType))
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.radios.isEmpty {
                MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING")
            } else if viewModel.radios.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    if MinimalWhiteStyle.isActive {
                        MinimalWhiteIconBadge(icon: .micSlash, size: 54)
                    } else {
                        MonoIcon(icon: .micSlash, size: 40, color: emptyStateColor)
                    }
                    Text("radio_empty")
                        .font(emptyStateFont)
                        .foregroundColor(emptyStateColor)
                }
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
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
            } else {
                ScrollView {
                    LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                        if SignalStyle.isActive {
                            SignalNestedPageHeader(
                                title: title,
                                eyebrow: "RADIO RANK",
                                icon: .chart,
                                module: .radio
                            )
                        }

                        ForEach(Array(viewModel.radios.enumerated()), id: \.element.id) { index, radio in
                            NavigationLink(value: PodcastView.PodcastDestination.radioDetail(radio.id)) {
                                radioRow(radio: radio, index: index)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if index >= viewModel.radios.count - 5 {
                                    viewModel.loadMore()
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 16)
                        }

                        if !viewModel.hasMore && !viewModel.radios.isEmpty {
                            NoMoreDataView()
                        }
                    }
                    .padding(.horizontal, ThemedPageStyle.horizontalInset)
                    .padding(.top, ThemedPageStyle.isActive ? 8 : 0)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
                .iPadContentWidth(900)
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            if viewModel.radios.isEmpty {
                viewModel.fetchRadios()
            }
        }
    }

    @ViewBuilder
    private func radioRow(radio: RadioStation, index: Int) -> some View {
        if !ThemedPageStyle.isActive {
            AsideRadioListRow(radio: radio, rank: listType == .toplist ? index + 1 : nil)
        } else {
            legacyRadioRow(radio: radio, index: index + 1)
        }
    }

    private func legacyRadioRow(radio: RadioStation, index: Int) -> some View {
        HStack(spacing: 14) {
            if SignalStyle.isActive {
                Text(String(format: "%02d", index))
                    .font(SignalStyle.monoFont(12, weight: .bold))
                    .foregroundStyle(index <= 3 ? SignalStyle.accent : SignalStyle.inkMuted)
                    .frame(width: 25, alignment: .leading)
            }

            CachedAsyncImage(url: radio.coverUrl) {
                RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                    .fill(coverPlaceholderFill)
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
                            .foregroundColor(tertiaryTextColor)
                    }
                }
            }

            Spacer()

            MonoIcon(icon: .chevronRight, size: 12, color: accentColor, lineWidth: 1.2)
        }
        .padding(.horizontal, ThemedPageStyle.isActive ? 16 : 20)
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

    private var emptyStateFont: Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(13, weight: .semibold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(14, weight: .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(16, weight: .medium) }
        return .system(size: 16, weight: .medium, design: .rounded)
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

    private var tertiaryTextColor: Color {
        if SignalStyle.isActive { return SignalStyle.inkMuted }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        return .monoTextSecondary
    }

    private var emptyStateColor: Color {
        if SignalStyle.isActive { return SignalStyle.inkMuted }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        return .monoTextSecondary
    }

    private var accentColor: Color {
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
