import SwiftUI

struct ClarityMeditationView: View {
    @StateObject private var viewModel = MeditationModeViewModel()
    @State private var playerDestination: ClarityMeditationPlayerDestination?
    @Namespace private var topicNamespace

    var body: some View {
        GeometryReader { viewport in
            let contentWidth = min(max(viewport.size.width - horizontalPadding * 2, 0), 720)
            let heroHeight = min(max(contentWidth * 0.58, 220), 330)

            ZStack {
                ClarityBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        topicSelector
                        contentSection(width: contentWidth, heroHeight: heroHeight)
                        FloatingBarBottomSpacer()
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await viewModel.refresh()
                }
                .themeRenderScrollLayer()
            }
        }
        .monoNavigationBackButton(iconColor: ClarityStyle.ink)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    MonoIcon(icon: .refresh, size: 18, color: ClarityStyle.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "reload"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .fullScreenCover(item: $playerDestination) { destination in
            MeditationPlayerView(source: destination.source)
        }
    }

    private var horizontalPadding: CGFloat {
        DeviceLayout.usesExpandedLayout ? 28 : 14
    }

    private var topicSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(MeditationTopic.allCases) { topic in
                    let selected = viewModel.selectedTopic == topic

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            viewModel.selectedTopic = topic
                        }
                    } label: {
                        Text(topic.title)
                            .font(ClarityStyle.body(11.5, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                            .padding(.horizontal, 15)
                            .frame(height: 38)
                            .background {
                                if selected {
                                    ClaritySelectionLens(shape: Capsule())
                                        .matchedGeometryEffect(id: "clarity-meditation-topic", in: topicNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
        }
        .scrollIndicators(.hidden)
        .background(ClarityMembrane(shape: Capsule(), strength: .regular))
    }

    @ViewBuilder
    private func contentSection(width: CGFloat, heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(sectionTitle)
                    .font(ClarityStyle.title(18, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)

                Text("\(viewModel.visibleContentCount)")
                    .font(ClarityStyle.body(11, weight: .semibold))
                    .foregroundStyle(ClarityStyle.inkFaint)
                    .monospacedDigit()

                Spacer(minLength: 0)
            }

            if viewModel.isLoading && viewModel.visibleItems.isEmpty {
                ClarityShell(cornerRadius: 32) {
                    ProgressView()
                        .tint(ClarityStyle.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                }
            } else if viewModel.visibleItems.isEmpty {
                emptyState
            } else {
                contentShell(width: width, heroHeight: heroHeight)
            }
        }
    }

    private var sectionTitle: String {
        viewModel.selectedTopic == .all
            ? String(localized: "meditation_recommended_title")
            : viewModel.selectedTopic.title
    }

    private func contentShell(width: CGFloat, heroHeight: CGFloat) -> some View {
        let items = viewModel.visibleItems

        return ClarityShell(cornerRadius: 32) {
            LazyVStack(spacing: 0) {
                if let featured = items.first {
                    Button {
                        open(featured)
                    } label: {
                        featuredContent(featured, width: width, height: heroHeight)
                    }
                    .buttonStyle(ClarityPressStyle())
                }

                ForEach(Array(items.dropFirst())) { item in
                    Rectangle()
                        .fill(ClarityStyle.line)
                        .frame(height: 1)
                        .padding(.leading, 88)

                    Button {
                        open(item)
                    } label: {
                        contentRow(item)
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
        }
    }

    private func featuredContent(
        _ item: MeditationContentItem,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: item.coverURL, width: width, height: height) {
                LinearGradient(
                    colors: [ClarityStyle.lilac.opacity(0.82), ClarityStyle.cyan.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    MonoIcon(icon: .moon, size: 46, color: Color.white.opacity(0.62), lineWidth: 1.4)
                )
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    if let category = item.category, !category.isEmpty {
                        Text(category)
                            .font(ClarityStyle.body(10.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Text(item.title)
                        .font(ClarityStyle.title(24, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(ClarityStyle.body(12.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                MonoIcon(icon: .play, size: 17, color: ClarityStyle.onSelection, lineWidth: 1.7)
                    .frame(width: 48, height: 48)
                    .background(ClaritySelectionLens(shape: Circle()))
            }
            .padding(20)
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func contentRow(_ item: MeditationContentItem) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: item.coverURL, width: 58, height: 58) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(ClarityStyle.membraneQuiet)
                    .overlay(MonoIcon(icon: .moon, size: 19, color: ClarityStyle.inkFaint, lineWidth: 1.4))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(ClarityStyle.body(14, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                    .lineLimit(2)

                Text(rowDetail(item))
                    .font(ClarityStyle.body(11))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            MonoIcon(icon: .play, size: 13, color: ClarityStyle.inkSoft, lineWidth: 1.6)
                .frame(width: 40, height: 40)
                .background(ClarityMembrane(shape: Circle(), strength: .quiet))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        ClarityShell(cornerRadius: 32) {
            VStack(spacing: 13) {
                MonoIcon(icon: .moon, size: 25, color: ClarityStyle.inkFaint, lineWidth: 1.5)
                    .frame(width: 58, height: 58)
                    .background(ClarityMembrane(shape: Circle(), strength: .regular))

                Text(viewModel.errorMessage == nil
                     ? String(localized: "meditation_empty")
                     : String(localized: "meditation_load_failed"))
                    .font(ClarityStyle.body(13, weight: .medium))
                    .foregroundStyle(ClarityStyle.inkSoft)

                if viewModel.errorMessage != nil {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text(String(localized: "meditation_player_retry"))
                            .font(ClarityStyle.body(11.5, weight: .semibold))
                            .foregroundStyle(ClarityStyle.onSelection)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(ClaritySelectionLens(shape: Capsule()))
                    }
                    .buttonStyle(ClarityPressStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 62)
        }
    }

    private func rowDetail(_ item: MeditationContentItem) -> String {
        if !item.subtitle.isEmpty { return item.subtitle }
        if let category = item.category, !category.isEmpty { return category }
        return String(localized: "meditation_sati_source")
    }

    private func open(_ item: MeditationContentItem) {
        playerDestination = ClarityMeditationPlayerDestination(
            source: viewModel.playbackSource(for: item)
        )
    }
}

private struct ClarityMeditationPlayerDestination: Identifiable {
    let source: MeditationPlaybackSource

    var id: String {
        switch source {
        case .radio(let radio):
            return "radio-\(radio.id)"
        case .sati(_, let resource):
            return "sati-\(resource.playableTrackId)"
        }
    }
}
