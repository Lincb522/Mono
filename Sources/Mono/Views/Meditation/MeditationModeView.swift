import SwiftUI

struct MeditationModeView: View {
    @StateObject private var viewModel = MeditationModeViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var playerDestination: MeditationPlayerDestination?

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            pageBackground

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    scrollableHeader
                    topicSelector
                    contentSection
                    FloatingBarBottomSpacer()
                }
                .padding(.top, PetWhiteStyle.isActive || ThemedPageStyle.isActive ? 0 : 12)
                .padding(.bottom, 20)
                .iPadContentWidth(1000)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            .refreshable {
                await viewModel.refresh()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .task {
            await viewModel.loadIfNeeded()
        }
        .fullScreenCover(item: $playerDestination) { destination in
            MeditationPlayerView(source: destination.source)
        }
    }

    @ViewBuilder
    private var pageBackground: some View {
        if PetWhiteStyle.isActive {
            PetWhiteRootBackdrop()
        } else if MangaStyle.isActive {
            MangaRootBackdrop()
        } else if MujiStyle.isActive {
            MujiRootBackdrop()
        } else if SignalStyle.isActive {
            ThemeRenderBackdrop(theme: .default)
        } else {
            ThemedPageBackground()
                .ignoresSafeArea()
        }
    }

    private var petWhiteHeader: some View {
        PetWhitePageHeader(
            eyebrow: "MEDITATION",
            title: String(localized: "meditation_mode_title"),
            subtitle: "",
            icon: .moon
        ) {
            EmptyView()
        }
    }

    private var isAside: Bool {
        !ThemedPageStyle.isActive
    }

    @ViewBuilder
    private var scrollableHeader: some View {
        if PetWhiteStyle.isActive {
            petWhiteHeader
        } else if ThemedPageStyle.isActive {
            ThemedPageHeader(
                eyebrow: "MEDITATION",
                title: String(localized: "meditation_mode_title"),
                subtitle: "",
                icon: .moon
            )
        } else {
            // aside：编辑部刊头
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.monoAccent)
                        .frame(width: 18, height: 3)

                    Text("MEDITATION")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .tracking(2.4)
                        .foregroundColor(.monoTextSecondary.opacity(0.72))
                        .fixedSize()

                    Rectangle()
                        .fill(Color.monoSeparator.opacity(0.5))
                        .frame(height: 0.5)
                }
                .padding(.bottom, 16)

                Text(String(localized: "meditation_mode_title"))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.monoTextPrimary)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 4)
            .monoPageHeaderCollapse()
        }
    }

    @ViewBuilder
    private var topicSelector: some View {
        if isAside {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 24) {
                        ForEach(MeditationTopic.allCases) { topic in
                            asideTopicTab(topic)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()

                Rectangle()
                    .fill(Color.monoSeparator.opacity(0.5))
                    .frame(height: 0.5)
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(MeditationTopic.allCases) { topic in
                        topicChip(topic)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
    }

    private func asideTopicTab(_ topic: MeditationTopic) -> some View {
        let isSelected = viewModel.selectedTopic == topic

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                viewModel.selectedTopic = topic
            }
        } label: {
            VStack(spacing: 8) {
                Text(topic.title)
                    .font(.rounded(size: 14, weight: isSelected ? .bold : .semibold))
                    .foregroundColor(isSelected ? .monoTextPrimary : .monoTextSecondary.opacity(0.72))

                Capsule()
                    .fill(isSelected ? Color.monoAccent : Color.clear)
                    .frame(width: 18, height: 2.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isLoading && viewModel.radios.isEmpty && viewModel.satiResources.isEmpty {
            loadingView
                .padding(.horizontal, horizontalPadding)
        } else if viewModel.visibleItems.isEmpty {
            emptyView
                .padding(.horizontal, horizontalPadding)
        } else if isAside {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionTitle
                    .padding(.bottom, 4)

                ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.monoSeparator.opacity(0.5))
                            .frame(height: 0.5)
                            .padding(.leading, 72)
                    }

                    Button {
                        playerDestination = MeditationPlayerDestination(source: viewModel.playbackSource(for: item))
                    } label: {
                        asideContentRow(item)
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, horizontalPadding)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle

                LazyVStack(spacing: ThemedPageStyle.listSpacing == 0 ? 10 : ThemedPageStyle.listSpacing) {
                    ForEach(viewModel.visibleItems) { item in
                        Button {
                            playerDestination = MeditationPlayerDestination(source: viewModel.playbackSource(for: item))
                        } label: {
                            contentCard(item)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private var sectionTitle: some View {
        if isAside {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.monoAccent)
                    .frame(width: 3, height: 13)

                Text(viewModel.selectedTopic == .all ? String(localized: "meditation_recommended_title") : viewModel.selectedTopic.title)
                    .font(.rounded(size: 15, weight: .bold))
                    .foregroundColor(.monoTextPrimary)

                Text("\(viewModel.visibleContentCount)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.monoAccent)
                    .monospacedDigit()

                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                MonoIcon(icon: .headphones, size: 16, color: accentColor, lineWidth: 1.6)

                Text(viewModel.selectedTopic == .all ? String(localized: "meditation_recommended_title") : viewModel.selectedTopic.title)
                    .font(labelFont(size: 17, weight: .black))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Text("\(viewModel.visibleContentCount)")
                    .font(labelFont(size: 13, weight: .black))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(countBackground)
            }
        }
    }

    /// aside：发丝分隔的编辑部行 — 描边封面 + 标题 + 点号分隔元信息 + 描边播放钮
    private func asideContentRow(_ item: MeditationContentItem) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: item.coverURL) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.monoGlassTint)
                    .overlay(MonoIcon(icon: .moon, size: 20, color: .monoTextSecondary.opacity(0.42)))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.monoTextPrimary.opacity(0.1), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.rounded(size: 15, weight: .semibold))
                    .foregroundColor(.monoTextPrimary)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.rounded(size: 12))
                        .foregroundColor(.monoTextSecondary.opacity(0.85))
                        .lineLimit(1)
                }

                if let meta = asideMetaText(item) {
                    Text(meta)
                        .font(.rounded(size: 11, weight: .medium))
                        .foregroundColor(.monoTextSecondary.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            MonoIcon(icon: .play, size: 12, color: .monoTextPrimary.opacity(0.8), lineWidth: 1.7)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle().stroke(Color.monoSeparator.opacity(0.95), lineWidth: 0.8)
                )
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func asideMetaText(_ item: MeditationContentItem) -> String? {
        var parts: [String] = []
        if let detail = item.detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let category = item.category, !category.isEmpty {
            parts.append(category)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func topicChip(_ topic: MeditationTopic) -> some View {
        let isSelected = viewModel.selectedTopic == topic

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                viewModel.selectedTopic = topic
            }
        } label: {
            Text(topic.title)
                .font(labelFont(size: 13, weight: .black))
                .foregroundStyle(isSelected ? selectedChipTextColor : secondaryTextColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(chipBackground(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func contentCard(_ item: MeditationContentItem) -> some View {
        HStack(spacing: 13) {
            CachedAsyncImage(url: item.coverURL) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(coverPlaceholderColor)
                    .overlay(MonoIcon(icon: .moon, size: 22, color: secondaryTextColor.opacity(0.42)))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(labelFont(size: 15, weight: .black))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(labelFont(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let detail = item.detail, !detail.isEmpty {
                        metaPill(detail)
                    }

                    if let category = item.category, !category.isEmpty {
                        metaPill(category)
                    }
                }
            }

            Spacer(minLength: 8)

            MonoIcon(icon: .play, size: 14, color: playIconColor, lineWidth: 1.7)
                .frame(width: 34, height: 34)
                .background(playButtonBackground)
                .clipShape(Circle())
                .overlay(playButtonStroke)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(labelFont(size: 10, weight: .bold))
            .foregroundStyle(secondaryTextColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(metaPillBackground)
            .clipShape(Capsule())
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            MeditationModeLoadingGlyph(tint: accentColor, secondary: secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            MonoIcon(icon: .moon, size: 34, color: secondaryTextColor.opacity(0.44), lineWidth: 1.7)
            Text(viewModel.errorMessage == nil ? String(localized: "meditation_empty") : String(localized: "meditation_load_failed"))
                .font(labelFont(size: 15, weight: .black))
                .foregroundStyle(primaryTextColor)
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(labelFont(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Button {
                Task { await viewModel.refresh() }
            } label: {
                if isAside {
                    Text(String(localized: "reload"))
                        .font(.rounded(size: 13, weight: .bold))
                        .foregroundColor(.monoIconForeground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.monoIconBackground, in: Capsule())
                } else {
                    Text(String(localized: "reload"))
                        .font(labelFont(size: 13, weight: .black))
                        .foregroundStyle(selectedChipTextColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(accentColor, in: Capsule())
                }
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 76)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if PetWhiteStyle.isActive {
            PetWhiteSurfaceBackground(cornerRadius: 22, elevated: false, tint: PetWhiteStyle.surfaceRaised, accent: PetWhiteStyle.mint)
        } else {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
                )
        }
    }

    @ViewBuilder
    private var countBackground: some View {
        if PetWhiteStyle.isActive {
            Capsule().fill(PetWhiteStyle.mint.opacity(0.56))
        } else {
            Capsule().fill(accentColor.opacity(0.12))
        }
    }

    @ViewBuilder
    private func chipBackground(isSelected: Bool) -> some View {
        if PetWhiteStyle.isActive {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(isSelected ? PetWhiteStyle.mint : PetWhiteStyle.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(PetWhiteStyle.stroke.opacity(isSelected ? 1 : 0.42), lineWidth: isSelected ? 1.4 : 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.2) : cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(isSelected ? accentColor.opacity(0.45) : cardStrokeColor, lineWidth: cardStrokeWidth)
                )
        }
    }

    private var playButtonBackground: some View {
        Circle().fill(PetWhiteStyle.isActive ? PetWhiteStyle.butter : accentColor.opacity(0.16))
    }

    @ViewBuilder
    private var playButtonStroke: some View {
        if PetWhiteStyle.isActive {
            Circle().stroke(PetWhiteStyle.stroke, lineWidth: 1)
        }
    }

    private var metaPillBackground: some View {
        Capsule().fill(secondaryTextColor.opacity(0.09))
    }

    private var horizontalPadding: CGFloat {
        PetWhiteStyle.isActive ? DeviceLayout.homeHorizontalPadding : DeviceLayout.viewHorizontalPadding
    }

    private var cardCornerRadius: CGFloat {
        if PetWhiteStyle.isActive { return 22 }
        if MangaStyle.isActive { return MangaStyle.cardRadius + 2 }
        if MujiStyle.isActive { return 16 }
        if NeumorphicStyle.isActive { return 22 }
        if CapsuleStyle.isActive { return 24 }
        if SequoiaStyle.isActive { return 20 }
        return 20
    }

    private var cardStrokeWidth: CGFloat {
        PetWhiteStyle.isActive ? 1.2 : 0.7
    }

    private var cardFillColor: Color {
        if MangaStyle.isActive { return MangaStyle.bubbleWhite.opacity(0.82) }
        if MujiStyle.isActive { return MujiStyle.surface.opacity(0.82) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surface.opacity(0.92) }
        if CapsuleStyle.isActive { return CapsuleStyle.surfaceRaised.opacity(0.82) }
        if SequoiaStyle.isActive { return SequoiaStyle.materialList.opacity(0.78) }
        if SignalStyle.isActive { return SignalStyle.control.opacity(0.78) }
        return Color.monoGlassTint.opacity(0.82)
    }

    private var coverPlaceholderColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.surfacePressed }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        if SequoiaStyle.isActive { return SequoiaStyle.materialList }
        return Color.monoGlassTint
    }

    private var cardStrokeColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.stroke }
        if MangaStyle.isActive { return MangaStyle.strokeInk }
        if MujiStyle.isActive { return MujiStyle.hairline.opacity(0.52) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.separator.opacity(0.5) }
        if CapsuleStyle.isActive { return CapsuleStyle.separator.opacity(0.48) }
        if SequoiaStyle.isActive { return SequoiaStyle.separator.opacity(0.72) }
        if SignalStyle.isActive { return SignalStyle.separator.opacity(0.62) }
        return Color.monoSeparator.opacity(0.5)
    }

    private var accentColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.mint }
        if MangaStyle.isActive { return MangaStyle.bubbleBlue }
        if MujiStyle.isActive { return MujiStyle.tea }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        if CapsuleStyle.isActive { return CapsuleStyle.mint }
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if SignalStyle.isActive { return SignalStyle.accent }
        return .monoAccent
    }

    private var primaryTextColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.ink }
        if MangaStyle.isActive { return MangaStyle.ink }
        if MujiStyle.isActive { return MujiStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        if CapsuleStyle.isActive { return CapsuleStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if SignalStyle.isActive { return SignalStyle.ink }
        return .monoTextPrimary
    }

    private var secondaryTextColor: Color {
        if PetWhiteStyle.isActive { return PetWhiteStyle.inkSoft }
        if MangaStyle.isActive { return MangaStyle.inkSub }
        if MujiStyle.isActive { return MujiStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        return .monoTextSecondary
    }

    private var selectedChipTextColor: Color {
        PetWhiteStyle.isActive ? PetWhiteStyle.stroke : primaryTextColor
    }

    private var playIconColor: Color {
        PetWhiteStyle.isActive ? PetWhiteStyle.stroke : accentColor
    }

    private func labelFont(size: CGFloat, weight: Font.Weight) -> Font {
        if PetWhiteStyle.isActive { return PetWhiteStyle.labelFont(size, weight: weight) }
        if MangaStyle.isActive { return MangaStyle.labelFont(size, weight: weight) }
        if MujiStyle.isActive { return MujiStyle.labelFont(size, weight: weight) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(size, weight: weight) }
        if CapsuleStyle.isActive { return CapsuleStyle.labelFont(size, weight: weight) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(size, weight: weight) }
        if SignalStyle.isActive { return SignalStyle.labelFont(size, weight: weight) }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

private struct MeditationPlayerDestination: Identifiable {
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

private struct MeditationModeLoadingGlyph: View {
    let tint: Color
    let secondary: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(AppFrameRate.animationTimeline(maximumFramesPerSecond: 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    tint.opacity(0.0),
                                    tint.opacity(0.42 - Double(index) * 0.08),
                                    secondary.opacity(0.16),
                                    tint.opacity(0.0)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5 - CGFloat(index) * 0.35, lineCap: .round)
                        )
                        .frame(width: 48 + CGFloat(index) * 17, height: 48 + CGFloat(index) * 17)
                        .rotationEffect(.degrees(phase * (34 + Double(index) * 12) + Double(index) * 42))
                        .opacity(0.85 - Double(index) * 0.16)
                }

                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(tint.opacity(0.26), lineWidth: 1))

                MonoIcon(icon: .moon, size: 20, color: tint, lineWidth: 1.75)
                    .scaleEffect(reduceMotion ? 1 : 0.94 + CGFloat((sin(phase * 2.2) + 1) * 0.035))
            }
            .frame(width: 92, height: 92)
        }
    }
}
