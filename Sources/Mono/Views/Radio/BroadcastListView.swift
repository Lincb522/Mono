import SwiftUI

/// 广播电台列表页（支持地区/分类筛选）
struct BroadcastListView: View {
    @StateObject private var viewModel = BroadcastListViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedChannel: BroadcastChannel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()

            VStack(spacing: 0) {
                if SignalStyle.isActive {
                    SignalNestedPageHeader(
                        title: NSLocalizedString("broadcast_title", comment: ""),
                        eyebrow: "FM TUNER",
                        icon: .radio,
                        module: .broadcast
                    )
                    .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                }

                // 地区筛选标签
                if !viewModel.regions.isEmpty {
                    regionFilter
                }

                if viewModel.isLoading && viewModel.channels.isEmpty {
                    Spacer()
                    MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING")
                    Spacer()
                } else if viewModel.channels.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        if MinimalWhiteStyle.isActive {
                            MinimalWhiteIconBadge(icon: .radio, size: 54)
                        }
                        Text(LocalizedStringKey("broadcast_no_stations"))
                            .font(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.labelFont(14, weight: .medium) : (SequoiaStyle.isActive ? SequoiaStyle.labelFont(14, weight: .regular) : .system(size: 14, design: .rounded)))
                            .foregroundColor(MinimalWhiteStyle.isActive ? MinimalWhiteStyle.inkMuted : (SequoiaStyle.isActive ? SequoiaStyle.inkSoft : .monoTextSecondary))
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
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                            ForEach(Array(viewModel.channels.enumerated()), id: \.element.id) { index, channel in
                                channelRow(channel: channel, index: index + 1)
                                    .onTapWithHaptic {
                                        selectedChannel = channel
                                    }
                            }
                        }
                        .padding(.horizontal, ThemedPageStyle.horizontalInset)
                        .padding(.top, ThemedPageStyle.isActive ? 4 : 0)
                        .padding(.bottom, 100)
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
            if viewModel.channels.isEmpty {
                viewModel.fetchData()
            }
        }
        .fullScreenCover(item: $selectedChannel) { channel in
            BroadcastPlayerView(channel: channel)
        }
    }

    // MARK: - 地区筛选

    private var regionFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                // "全部"按钮
                filterCapsule(title: NSLocalizedString("broadcast_all", comment: ""), isSelected: viewModel.selectedRegionId == "0") {
                    viewModel.selectRegion("0")
                }

                ForEach(viewModel.regions) { region in
                    filterCapsule(
                        title: region.name ?? "",
                        isSelected: viewModel.selectedRegionId == String(region.id)
                    ) {
                        viewModel.selectRegion(String(region.id))
                    }
                }
            }
            .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    private func filterCapsule(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(chipFont(isSelected: isSelected))
                .foregroundColor(chipTextColor(isSelected: isSelected))
                .padding(.horizontal, (MinimalWhiteStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 16 : 14)
                .padding(.vertical, (MinimalWhiteStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 9 : 8)
                .background(chipBackground(isSelected: isSelected))
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
        .buttonStyle(ScaleButtonStyle())
    }

    private func chipFont(isSelected: Bool) -> Font {
        if SignalStyle.isActive { return SignalStyle.labelFont(11, weight: isSelected ? .bold : .medium) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(13, weight: isSelected ? .semibold : .regular) }
        if MangaStyle.isActive { return MangaStyle.labelFont(13, weight: isSelected ? .black : .bold) }
        if MujiStyle.isActive { return MujiStyle.labelFont(13, weight: isSelected ? .semibold : .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(13, weight: isSelected ? .semibold : .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(13, weight: isSelected ? .semibold : .medium) }
        return .system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded)
    }

    private func chipTextColor(isSelected: Bool) -> Color {
        if SignalStyle.isActive { return isSelected ? SignalStyle.onAccent : SignalStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return isSelected ? MinimalWhiteStyle.ink : MinimalWhiteStyle.inkMuted }
        if MangaStyle.isActive {
            return isSelected
                ? ThemeColorCustomization.readableForegroundColor(on: MangaStyle.labelYellow, light: MangaStyle.strokeInk, dark: MangaStyle.onStrokeInk)
                : MangaStyle.inkSub
        }
        if MujiStyle.isActive { return isSelected ? MujiStyle.paper : MujiStyle.ink }
        if NeumorphicStyle.isActive { return isSelected ? NeumorphicStyle.accent : NeumorphicStyle.inkSoft }
        if SequoiaStyle.isActive { return isSelected ? SequoiaStyle.onAccent : SequoiaStyle.inkSoft }
        if !ThemedPageStyle.isActive { return isSelected ? .monoIconForeground : .monoTextPrimary.opacity(0.82) }
        return isSelected ? .white : .monoTextPrimary
    }

    @ViewBuilder
    private func chipBackground(isSelected: Bool) -> some View {
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
            Capsule().fill(isSelected ? Color.monoTextPrimary : Color.monoGlassTint)
        }
    }

    // MARK: - 频道行

    @ViewBuilder
    private func channelRow(channel: BroadcastChannel, index: Int) -> some View {
        if !ThemedPageStyle.isActive {
            asideChannelRow(channel: channel)
        } else {
            legacyChannelRow(channel: channel, index: index)
        }
    }

    private func asideChannelRow(channel: BroadcastChannel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Group {
                    if let url = channel.coverImageUrl {
                        CachedAsyncImage(url: url) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.monoGlassTint)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.monoGlassTint)
                            .overlay(
                                MonoIcon(icon: .radio, size: 20, color: .monoTextSecondary.opacity(0.6), lineWidth: 1.4)
                            )
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.monoSeparator.opacity(0.9), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.displayName)
                        .font(.rounded(size: 15, weight: .semibold))
                        .foregroundColor(.monoTextPrimary)
                        .lineLimit(1)

                    if let program = channel.displayProgram, !program.isEmpty {
                        Text(program)
                            .font(.rounded(size: 12))
                            .foregroundColor(.monoTextSecondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text("FM")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.monoTextSecondary.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .overlay(Capsule().stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.7))

                MonoIcon(icon: .playCircle, size: 22, color: .monoTextSecondary.opacity(0.7), lineWidth: 1.3)
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.monoSeparator.opacity(0.7))
                .frame(height: 0.6)
                .padding(.leading, 68)
        }
        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
        .contentShape(Rectangle())
    }

    private func legacyChannelRow(channel: BroadcastChannel, index: Int) -> some View {
        HStack(spacing: 14) {
            if SignalStyle.isActive {
                Text(String(format: "%02d", index))
                    .font(SignalStyle.monoFont(10, weight: .bold))
                    .foregroundStyle(SignalStyle.accent)
                    .frame(width: 23, alignment: .leading)
            }

            // 封面
            if let url = channel.coverImageUrl {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: coverRadius)
                        .fill(coverPlaceholderFill)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
                .overlay(coverStroke)
            } else {
                RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                    .fill(coverPlaceholderFill)
                    .frame(width: 56, height: 56)
                    .overlay(
                        MonoIcon(icon: .radio, size: 22, color: SequoiaStyle.isActive ? SequoiaStyle.aqua : (NeumorphicStyle.isActive ? NeumorphicStyle.sage : .monoTextSecondary), lineWidth: 1.4)
                    )
                    .overlay(coverStroke)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.displayName)
                    .font(rowTitleFont)
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                if let program = channel.displayProgram, !program.isEmpty {
                    Text(program)
                        .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : .system(size: 12, design: .rounded))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            // FM 标识
            if SignalStyle.isActive {
                SignalPill(text: "FM", tint: SignalStyle.accent, icon: .radio, compact: true)
            } else if NeumorphicStyle.isActive {
                NeumorphicPill(text: "FM", tint: NeumorphicStyle.sage, compact: true)
            } else if SequoiaStyle.isActive {
                SequoiaPill(text: "FM", icon: .radio, tint: SequoiaStyle.aqua, compact: true)
            } else {
                Text("FM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.monoTextSecondary)
            }

            MonoIcon(icon: .playCircle, size: 26, color: SignalStyle.isActive ? SignalStyle.accent : (SequoiaStyle.isActive ? SequoiaStyle.accent : (NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary)), lineWidth: 1.4)
        }
        .padding(.horizontal, ThemedPageStyle.isActive ? 16 : DeviceLayout.viewHorizontalPadding)
        .padding(.vertical, 10)
        .themedOnlyPageSurface(cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius, elevated: false)
        .contentShape(Rectangle())
    }

    private var coverRadius: CGFloat {
        if SignalStyle.isActive { return 8 }
        if MinimalWhiteStyle.isActive { return 12 }
        return (NeumorphicStyle.isActive || SequoiaStyle.isActive) ? 14 : 12
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

    private var coverPlaceholderFill: Color {
        if SignalStyle.isActive { return SignalStyle.controlPressed }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.controlGlassFill }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        if SequoiaStyle.isActive { return SequoiaStyle.materialList }
        return Color.monoGlassTint
    }
}
