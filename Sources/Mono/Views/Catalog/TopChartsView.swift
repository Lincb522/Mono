import SwiftUI

struct TopChartsView: View {
    @State private var topLists: [TopList] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @ObservedObject private var subManager = SubscriptionManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    typealias Theme = PlaylistDetailView.Theme

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            if MangaStyle.isActive {
                MangaRootBackdrop()
            } else if MujiStyle.isActive {
                MujiRootBackdrop()
            } else if MinimalWhiteStyle.isActive {
                MinimalWhiteRootBackdrop()
            } else {
                ThemedPageBackground()
            }

            if isLoading {
                MonoLoadingView(text: MinimalWhiteStyle.isActive ? nil : "LOADING CHARTS")
            } else if let error = errorMessage {
                VStack(spacing: 14) {
                    if MinimalWhiteStyle.isActive {
                        MinimalWhiteIconBadge(icon: .warning, size: 56)
                    } else {
                        MonoIcon(icon: .warning, size: 48, color: secondaryTextColor)
                    }
                    Text(error)
                        .foregroundColor(secondaryTextColor)
                        .padding()
                    Button("Retry") {
                        loadData()
                    }
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
                VStack(spacing: 0) {
                    ScrollView {
                        if MangaStyle.isActive {
                            MangaPageHeader(
                                eyebrow: "RANKING",
                                title: String(localized: "top_charts"),
                                subtitle: ""
                            ) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                                        .fill(MangaStyle.bubblePink)
                                    MonoIcon(icon: .chart, size: 23, color: MangaStyle.ink, lineWidth: 2)
                                }
                                .frame(width: 48, height: 48)
                                .overlay(RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous).stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth))
                                .background(RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous).fill(MangaStyle.strokeInk).offset(x: MangaStyle.shadowOffset, y: MangaStyle.shadowOffset))
                            }
                        } else if MinimalWhiteStyle.isActive {
                            MinimalWhitePageHeader(eyebrow: "", title: String(localized: "top_charts"), icon: .chart)
                        } else if MujiStyle.isActive {
                            MujiPageHeader(
                                eyebrow: String(localized: "lib_tab_charts"),
                                title: String(localized: "top_charts"),
                                subtitle: ""
                            ) {
                                MujiIconBadge(icon: .chart, tint: MujiStyle.indigo, size: 48)
                            }
                        } else if NeumorphicStyle.isActive {
                            NeumorphicPageHeader(
                                eyebrow: "RANKING",
                                title: String(localized: "top_charts"),
                                subtitle: ""
                            ) {
                                NeumorphicIconBadge(icon: .chart, tint: NeumorphicStyle.warm, size: 48)
                            }
                        } else if SequoiaStyle.isActive {
                            SequoiaPageHeader(
                                eyebrow: "RANKING",
                                title: String(localized: "top_charts"),
                                subtitle: ""
                            ) {
                                SequoiaIconBadge(icon: .chart, tint: SequoiaStyle.violet, size: 48)
                            }
                        } else if BentoStyle.isActive {
                            BentoPageHeader(
                                eyebrow: "BENTO RANK",
                                title: String(localized: "top_charts"),
                                subtitle: ""
                            ) {
                                BentoIconBadge(icon: .chart, foreground: BentoStyle.mustard, size: 48)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(topLists) { list in
                                chartCard(list)
                            }
                        }
                        .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear {
            loadData()
        }
    }

    private func chartCard(_ list: TopList) -> some View {
        let isSubscribed = subManager.isPlaylistSubscribed(list.id)
        return NavigationLink(
            destination: PlaylistDetailView(playlist: Playlist(id: list.id, name: list.name, coverImgUrl: list.coverImgUrl, picUrl: nil, trackCount: nil, playCount: nil, subscribedCount: nil, shareCount: nil, commentCount: nil, creator: nil, description: nil, tags: nil))

        ) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: list.coverUrl) {
                        chartCoverPlaceholder
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: chartCoverRadius, style: .continuous))
                    .overlay {
                        if MangaStyle.isActive {
                            RoundedRectangle(cornerRadius: MangaStyle.cardRadius, style: .continuous)
                                .stroke(MangaStyle.strokeInk.opacity(0.7), lineWidth: 1)
                        } else if MujiStyle.isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MujiStyle.hairline.opacity(0.55), lineWidth: 0.6)
                        } else if NeumorphicStyle.isActive {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(NeumorphicStyle.separator.opacity(0.34), lineWidth: 0.7)
                        } else if SequoiaStyle.isActive {
                            RoundedRectangle(cornerRadius: chartCoverRadius, style: .continuous)
                                .stroke(SequoiaStyle.separator.opacity(0.76), lineWidth: 0.6)
                        } else if BentoStyle.isActive {
                            RoundedRectangle(cornerRadius: chartCoverRadius, style: .continuous)
                                .stroke(BentoStyle.hairline.opacity(0.62), lineWidth: 0.7)
                        } else if MinimalWhiteStyle.isActive {
                            RoundedRectangle(cornerRadius: chartCoverRadius, style: .continuous)
                                .stroke(MinimalWhiteStyle.hairline, lineWidth: MinimalWhiteStyle.strokeWidth)
                        }
                    }
                    .shadow(color: Color.black.opacity(ThemedPageStyle.isActive ? 0.055 : 0.1), radius: ThemedPageStyle.isActive ? 8 : 5, x: 0, y: ThemedPageStyle.isActive ? 4 : 2)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            subManager.togglePlaylistSubscription(id: list.id)
                        }
                    } label: {
                        MonoIcon(
                            icon: isSubscribed ? .liked : .like,
                            size: 14,
                            color: chartLikeColor(isSubscribed: isSubscribed),
                            lineWidth: 1.4
                        )
                        .padding(6)
                        .background {
                            if MangaStyle.isActive {
                                Circle().fill(MangaStyle.bubbleWhite)
                                Circle().stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.fineStrokeWidth)
                            } else if MujiStyle.isActive {
                                Circle().fill(MujiStyle.surface.opacity(0.92))
                            } else if NeumorphicStyle.isActive {
                                Circle().fill(NeumorphicStyle.surfaceRaised.opacity(0.94))
                            } else if SequoiaStyle.isActive {
                                Circle().fill(SequoiaStyle.materialFloating.opacity(0.92))
                            } else if BentoStyle.isActive {
                                Circle().fill(BentoStyle.surfaceRaised.opacity(0.94))
                            } else if MinimalWhiteStyle.isActive {
                                MinimalWhiteCircleBackground(elevated: false, selected: isSubscribed)
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.85))
                    .padding(6)
                }

                Text(list.name)
                    .font(chartTitleFont)
                    .foregroundColor(primaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(list.updateFrequency)
                    .font(chartSubtitleFont)
                    .foregroundColor(secondaryTextColor)
            }
            .padding(ThemedPageStyle.isActive && !MangaStyle.isActive ? 8 : 0)
            .background {
                if MangaStyle.isActive {
                    // 去卡片化：榜单格直接排在纸上，封面细墨框即可
                    EmptyView()
                } else if NeumorphicStyle.isActive {
                    NeumorphicSurfaceBackground(cornerRadius: 18, elevated: false)
                } else if SequoiaStyle.isActive {
                    SequoiaSurfaceBackground(cornerRadius: 18, elevated: false, role: .list)
                } else if BentoStyle.isActive {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BentoStyle.surface)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BentoStyle.hairline.opacity(0.52), lineWidth: 0.7))
                } else if MinimalWhiteStyle.isActive {
                    MinimalWhiteSurfaceBackground(
                        cornerRadius: MinimalWhiteStyle.cardRadius,
                        elevated: false,
                        tint: MinimalWhiteStyle.glassFill
                    )
                }
            }
        }
    }

    private var chartCoverPlaceholder: Color {
        if MangaStyle.isActive { return MangaStyle.paperCool }
        if MujiStyle.isActive { return MujiStyle.surfaceRaised }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        if SequoiaStyle.isActive { return SequoiaStyle.materialList }
        if BentoStyle.isActive { return BentoStyle.buckwheat.opacity(0.45) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.controlGlassFill }
        return Color.gray.opacity(0.1)
    }

    private var chartCoverRadius: CGFloat {
        if MangaStyle.isActive { return MangaStyle.cardRadius }
        if MujiStyle.isActive { return 8 }
        if NeumorphicStyle.isActive || SequoiaStyle.isActive { return 16 }
        if BentoStyle.isActive { return 16 }
        if MinimalWhiteStyle.isActive { return 12 }
        return 12
    }

    private var chartTitleFont: Font {
        if MangaStyle.isActive { return MangaStyle.bodyFont(12, weight: .black) }
        if MujiStyle.isActive { return MujiStyle.bodyFont(12, weight: .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(12, weight: .semibold) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(12, weight: .semibold) }
        if BentoStyle.isActive { return BentoStyle.labelFont(12, weight: .heavy) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(12, weight: .medium) }
        return .system(size: 12, weight: .medium)
    }

    private var chartSubtitleFont: Font {
        if MangaStyle.isActive { return MangaStyle.bodyFont(10, weight: .bold) }
        if MujiStyle.isActive { return MujiStyle.labelFont(10, weight: .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(10, weight: .medium) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(10, weight: .regular) }
        if BentoStyle.isActive { return BentoStyle.labelFont(10, weight: .semibold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(10, weight: .regular) }
        return .system(size: 10)
    }

    private var primaryTextColor: Color {
        if MangaStyle.isActive { return MangaStyle.ink }
        if MujiStyle.isActive { return MujiStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if BentoStyle.isActive { return BentoStyle.ink }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        return Theme.text
    }

    private var secondaryTextColor: Color {
        if MangaStyle.isActive { return MangaStyle.inkSub }
        if MujiStyle.isActive { return MujiStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if BentoStyle.isActive { return BentoStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        return Theme.secondaryText
    }

    private func chartLikeColor(isSubscribed: Bool) -> Color {
        if MangaStyle.isActive { return isSubscribed ? MangaStyle.red : MangaStyle.strokeInk }
        if MujiStyle.isActive { return isSubscribed ? MujiStyle.red : MujiStyle.inkSoft }
        if NeumorphicStyle.isActive { return isSubscribed ? NeumorphicStyle.red : NeumorphicStyle.inkSoft }
        if SequoiaStyle.isActive { return isSubscribed ? SequoiaStyle.red : SequoiaStyle.inkSoft }
        if BentoStyle.isActive { return isSubscribed ? BentoStyle.tomato : BentoStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return isSubscribed ? MinimalWhiteStyle.ink : MinimalWhiteStyle.inkMuted }
        return isSubscribed ? .red : .primary
    }

    private func loadData() {
        Task {
            do {
                let lists = try await APIService.shared.fetchTopLists().async()
                topLists = lists
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
