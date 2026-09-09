import SwiftUI

/// 电台分类浏览页面 — 顶部分类标签，选中后展示该分类下的电台列表，无限加载
struct RadioCategoryBrowseView: View {
    @StateObject private var viewModel = RadioCategoryBrowseViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if SignalStyle.isActive {
                    SignalNestedPageHeader(
                        title: String(localized: "radio_category_browse"),
                        eyebrow: "RADIO MATRIX",
                        icon: .gridSquare,
                        module: .radio
                    )
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                }

                // 分类标签栏
                if !viewModel.categories.isEmpty {
                    categoryBar
                }

                // 内容区
                if viewModel.isLoading && viewModel.radios.isEmpty {
                    Spacer()
                    MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING")
                    Spacer()
                } else if viewModel.radios.isEmpty && !viewModel.isLoading {
                    Spacer()
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
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                            ForEach(Array(viewModel.radios.enumerated()), id: \.element.id) { index, radio in
                                NavigationLink(value: PodcastView.PodcastDestination.radioDetail(radio.id)) {
                                    radioRow(radio: radio, index: index + 1)
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
                        .padding(.top, ThemedPageStyle.isActive ? 4 : 0)
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                }
            }
            .iPadContentWidth(900)
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            viewModel.initialLoad()
        }
    }

    // MARK: - 分类标签栏

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.categories) { cat in
                    let isSelected = viewModel.selectedCategory?.id == cat.id
                    Button(action: {
                        viewModel.selectCategory(cat)
                    }) {
                            Text(cat.name)
                                .font(categoryChipFont(isSelected: isSelected))
                                .foregroundColor(categoryTextColor(isSelected: isSelected))
                            .padding(.horizontal, (MinimalWhiteStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 16 : 14)
                            .padding(.vertical, (MinimalWhiteStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 9 : 8)
                            .background(categoryChipBackground(isSelected: isSelected))
                            .clipShape(MangaStyle.isActive ? AnyShape(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)) : AnyShape(Capsule()))
                            .overlay {
                                if MangaStyle.isActive {
                                    RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                                        .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth)
                                } else if MujiStyle.isActive {
                                    Capsule()
                                        .stroke(MujiStyle.hairline.opacity(0.45), lineWidth: 0.6)
                                } else if SequoiaStyle.isActive {
                                    Capsule()
                                        .stroke((isSelected ? SequoiaStyle.accent : SequoiaStyle.separator).opacity(0.45), lineWidth: 0.55)
                                } else if MinimalWhiteStyle.isActive {
                                    Capsule()
                                        .stroke(isSelected ? MinimalWhiteStyle.separator : MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private func categoryChipFont(isSelected: Bool) -> Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(11, weight: isSelected ? .bold : .medium) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(13, weight: isSelected ? .semibold : .regular) }
        if MangaStyle.isActive { return MangaStyle.labelFont(13, weight: isSelected ? .black : .bold) }
        if MujiStyle.isActive { return MujiStyle.labelFont(13, weight: isSelected ? .semibold : .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(13, weight: isSelected ? .semibold : .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(13, weight: isSelected ? .semibold : .medium) }
        if !ThemedPageStyle.isActive { return .rounded(size: 13, weight: isSelected ? .bold : .medium) }
        return .system(size: 13, weight: .medium, design: .rounded)
    }

    private func categoryTextColor(isSelected: Bool) -> Color {
        if SignalStyle.isActive {
            return isSelected ? SignalStyle.onAccent : SignalStyle.inkSoft
        } else if MinimalWhiteStyle.isActive {
            return isSelected ? MinimalWhiteStyle.ink : MinimalWhiteStyle.inkMuted
        } else if MangaStyle.isActive {
            return isSelected ? ThemeColorCustomization.readableForegroundColor(on: MangaStyle.labelYellow, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk) : .monoTextPrimary
        } else if MujiStyle.isActive {
            return isSelected ? MujiStyle.paper : .monoTextPrimary
        } else if NeumorphicStyle.isActive {
            return isSelected ? NeumorphicStyle.accent : NeumorphicStyle.inkSoft
        } else if SequoiaStyle.isActive {
            return isSelected ? SequoiaStyle.onAccent : SequoiaStyle.inkSoft
        } else {
            return isSelected ? .monoIconForeground : .monoTextPrimary
        }
    }

    @ViewBuilder
    private func categoryChipBackground(isSelected: Bool) -> some View {
        if SignalStyle.isActive {
            Capsule()
                .fill(isSelected ? SignalStyle.accent : SignalStyle.control)
                .overlay(Capsule().stroke(isSelected ? SignalStyle.accent.opacity(0.24) : SignalStyle.separator.opacity(0.72), lineWidth: 0.7))
        } else if MinimalWhiteStyle.isActive {
            MinimalWhiteCapsuleBackground(selected: isSelected)
        } else if MangaStyle.isActive {
            RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous)
                .fill(isSelected ? MangaStyle.labelYellow : MangaStyle.bubbleWhite)
                .overlay(RoundedRectangle(cornerRadius: MangaStyle.buttonRadius, style: .continuous).stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.fineStrokeWidth))
        } else if MujiStyle.isActive {
            Capsule().fill(isSelected ? MujiStyle.clay : MujiStyle.surfaceRaised)
        } else if NeumorphicStyle.isActive {
            NeumorphicSurfaceBackground(
                cornerRadius: 16,
                elevated: isSelected,
                pressed: !isSelected,
                tint: isSelected ? NeumorphicStyle.accent.opacity(0.16) : NeumorphicStyle.surface
            )
        } else if SequoiaStyle.isActive {
            Capsule()
                .fill(isSelected ? SequoiaStyle.accent : SequoiaStyle.materialList.opacity(0.76))
        } else if !ThemedPageStyle.isActive {
            Capsule()
                .fill(isSelected ? Color.monoIconBackground : Color.clear)
                .overlay {
                    if !isSelected {
                        Capsule().stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
                    }
                }
        } else {
            Capsule().fill(isSelected ? Color.monoIconBackground : Color.monoGlassTint)
        }
    }

    // MARK: - 电台行

    @ViewBuilder
    private func radioRow(radio: RadioStation, index: Int) -> some View {
        if !ThemedPageStyle.isActive {
            AsideRadioListRow(radio: radio)
        } else {
            legacyRadioRow(radio: radio, index: index)
        }
    }

    private func legacyRadioRow(radio: RadioStation, index: Int) -> some View {
        HStack(spacing: 14) {
            if SignalStyle.isActive {
                Text(String(format: "%02d", index))
                    .font(SignalStyle.monoFont(10, weight: .bold))
                    .foregroundStyle(SignalStyle.accent)
                    .frame(width: 23, alignment: .leading)
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
        .padding(.horizontal, ThemedPageStyle.isActive ? 16 : DeviceLayout.viewHorizontalPadding)
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
