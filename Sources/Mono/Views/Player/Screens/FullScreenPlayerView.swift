import SwiftUI

/// 全屏播放器 - 路由层，根据主题切换不同布局
struct FullScreenPlayerView: View {
    @ObservedObject var player = CurrentSongPresentationModel.shared
    
    @ObservedObject private var themeManager = PlayerThemeManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var immersiveController = ImmersiveModeController.shared
    @Environment(\.colorScheme) private var envColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            playerBackground
            .ignoresSafeArea()

            Group {
                switch themeManager.currentTheme {
                case .classic:
                    ClassicPlayerLayout(presentation: .aside)
                case .vinyl:
                    VinylPlayerLayout()
                case .lyricFocus:
                    MinimalPlayerLayout()
                case .card:
                    CardPlayerLayout()
                case .neumorphic:
                    NeumorphicPlayerLayout()
                case .poster:
                    PosterPlayerLayout()
                        .compatFontDesign(nil)
                case .motoPager:
                    MotoPagerLayout()
                case .typewriter:
                    TypewriterPlayerLayout()
                case .pixel:
                    PixelPlayerLayout()
                        .compatFontDesign(nil)
                case .aqua:
                    AquaPlayerLayout()
                case .breathing:
                    BreathingPlayerLayout()
                case .cassette:
                    CassettePlayerLayout()
                case .radio:
                    RadioPlayerLayout()
                case .immersiveLyric:
                    ImmersiveLyricPlayerLayout()
                case .folk:
                    FolkPlayerLayout()
                case .game2048:
                    Game2048PlayerLayout()
                case .ipod:
                    IPodPlayerLayout()
                case .liquidGlass:
                    LiquidGlassPlayerLayout()
                case .tornPaper:
                    TornPaperPlayerLayout()
                case .clarity:
                    ClarityPlayerLayout()
                case .dotMatrix:
                    DotMatrixPlayerLayout()
                case .console:
                    ConsolePlayerLayout()
                case .muji:
                    ClassicPlayerLayout(presentation: .muji)
                case .capsule:
                    ClassicPlayerLayout(presentation: .capsule)
                case .petWhite:
                    PawcelainPlayerLayout()
                case .minimalWhite:
                    ClassicPlayerLayout(presentation: .minimalWhite)
                }
            }
            .id(themeManager.currentTheme)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.985))
            )
            .environment(\.colorScheme, playerColorScheme)

        }
        .compatFontDesign(nil)
        .animation(
            reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.94, blendDuration: 0.06),
            value: themeManager.currentTheme
        )
        .monoEdgeSwipeToDismiss()
        .fullScreenCover(isPresented: $immersiveController.isPresented) {
            AriaStageView()
        }
    }

    @ViewBuilder
    private var playerBackground: some View {
        switch themeManager.currentTheme {
        case .classic:
            if settings.usesPlayerCoverBackground {
                PlaylistColorBackground(coverUrl: player.currentSong?.coverUrl?.sized(200))
            } else {
                ThemeRenderBackdrop(theme: .default)
            }
        case .muji, .capsule, .petWhite, .minimalWhite:
            Color.clear
        default:
            if settings.usesPlayerCoverBackground && !MinimalWhiteStyle.isActive {
                PlaylistColorBackground(coverUrl: player.currentSong?.coverUrl?.sized(200))
            } else {
                ThemedPageBackground()
            }
        }
    }

    private var playerColorScheme: ColorScheme {
        if themeManager.currentTheme == .classic || themeManager.currentTheme.hasCustomBackground {
            return settings.nativeColorScheme
        }
        return envColorScheme
    }

    // MARK: - 播放器进度条组件（供默认播放器及共享布局复用）

    struct WaveformProgressBar: View {
        @Binding var currentTime: Double
        let duration: Double
        var color: Color = .monoTextPrimary
        /// 未播放部分的不透明度（默认 0.2，越低越融入背景）
        var trackOpacity: Double = 0.2
        var isAnimating: Bool = true
        let onSeek: (Double) -> Void
        let onCommit: (Double) -> Void

        var body: some View {
            let progress = duration > 0 ? CGFloat(min(max(currentTime / duration, 0), 1)) : 0

            GlobalWaveformPlaybackProgressBar(
                progress: progress,
                isPlaying: isAnimating,
                color: color,
                trackOpacity: trackOpacity,
                fillColors: progressFillColors,
                onSeek: { p in onSeek(Double(p) * duration) },
                onCommit: { p in onCommit(Double(p) * duration) }
            )
        }

        private var progressFillColors: [Color] {
            if MinimalWhiteStyle.isActive { return [MinimalWhiteStyle.accent, MinimalWhiteStyle.accent] }
            if MangaStyle.isActive { return [MangaStyle.ink, MangaComicPalette.toneMid] }
            if MujiStyle.isActive { return [MujiStyle.clay, MujiStyle.indigo.opacity(0.86)] }
            if NeumorphicStyle.isActive { return [NeumorphicStyle.accent, NeumorphicStyle.sage] }
            if CapsuleStyle.isActive { return CapsuleStyle.accentGradient }
            if ClarityStyle.isActive { return ClarityStyle.accentGradient }
            if SequoiaStyle.isActive { return [SequoiaStyle.accent, SequoiaStyle.aqua] }
            if LiquidGlassStyle.isActive { return [LiquidGlassStyle.accent, LiquidGlassStyle.cyan, LiquidGlassStyle.violet] }
            if ClayStyle.isActive { return [ClayStyle.sky, ClayStyle.peach] }
            if SignalStyle.isActive { return [SignalStyle.accent, SignalStyle.mint] }
            if BentoStyle.isActive { return [BentoStyle.tomato, BentoStyle.mustard] }
            return [color.opacity(0.66), color.opacity(0.96)]
        }
        
    }
}

/// 封面上的 AI 调音状态。进行中显示紧凑进度，完成后保留可展开的调音入口。
struct AIEqualizerArtworkStatusView: View {
    let accent: Color
    let isDarkArtwork: Bool

    @ObservedObject private var agent = AIEqualizerAgent.shared
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var showQuickControls = false
    @State private var showTuningDetails = false
    @State private var completionNoticeTask: Task<Void, Never>?
    @State private var openDetailsTask: Task<Void, Never>?

    private var foregroundColor: Color {
        isDarkArtwork ? .white : Color(hex: "111318")
    }

    private var tuningProgress: Double? {
        switch agent.phase {
        case let .sampling(progress):
            return min(0.72, max(0.02, progress * 0.72))
        case .requesting:
            switch agent.generationStage {
            case .preparingModel: return 0.02
            case .preparing: return 0.76
            case .generating: return 0.84
            case .validating: return 0.92
            case .finalizing: return 0.97
            }
        case .applying:
            return 0.99
        case .idle, .ready, .failed:
            return nil
        }
    }

    private var appliedProfileName: String? {
        guard agent.isCurrentProposalApplied else { return nil }
        let name = agent.proposal?.profileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private var compactProfileName: String? {
        guard let name = appliedProfileName else { return nil }
        let characterLimit = 8
        guard name.count > characterLimit else { return name }
        return String(name.prefix(characterLimit)) + "…"
    }

    private var isVisible: Bool {
        tuningProgress != nil
            || appliedProfileName != nil
            || agent.isAutomaticTuningActive
            || agent.proposal != nil
    }

    var body: some View {
        Group {
            if agent.showsPlayerTuningStatus, isVisible {
                Button(action: openQuickControls) {
                    HStack(spacing: 5) {
                        if let name = compactProfileName, isExpanded {
                            // Once the proposal is applied, the cover capsule only
                            // identifies the active profile. Timing belongs to the
                            // tuning detail page, not the persistent player chrome.
                            Text(name)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(foregroundColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .transition(
                                    .opacity.combined(
                                        with: .scale(scale: 0.96, anchor: .trailing)
                                    )
                                )
                        }

                        if tuningProgress != nil {
                            if let startedAt = agent.tuningStartedAt {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(compactElapsed(since: startedAt, now: context.date))
                                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(foregroundColor)
                                        .contentTransition(.numericText())
                                }
                            } else if let progress = tuningProgress {
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(foregroundColor)
                                    .contentTransition(.numericText())
                            }
                        }

                        AIEqualizerArtworkStatusGlyph(
                            progress: tuningProgress,
                            isComplete: appliedProfileName != nil,
                            isEnabled: agent.isAutomaticTuningActive,
                            reduceMotion: reduceMotion,
                            foregroundColor: foregroundColor
                        )
                        .monoCompletionMotion(
                            trigger: agent.appliedProposalID,
                            reduceMotion: reduceMotion
                        )
                    }
                    .padding(.leading, tuningProgress == nil && !isExpanded ? 3 : 8)
                    .padding(.trailing, 3)
                    .frame(height: 29)
                    .background {
                        AIEqualizerStatusGlassBackground(
                            accent: accent,
                            isDarkArtwork: isDarkArtwork
                        )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                foregroundColor.opacity(isDarkArtwork ? 0.24 : 0.18),
                                lineWidth: 0.6
                            )
                    }
                    .contentShape(Capsule(style: .continuous))
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MonoBouncingButtonStyle())
                .accessibilityLabel(accessibilityText)
                .accessibilityHint(String(localized: "ai_quick_open_controls"))
                .popover(
                    isPresented: $showQuickControls,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    AIEqualizerQuickControlsView(
                        accent: accent,
                        tuningProgress: tuningProgress,
                        onOpenDetails: openTuningDetails
                    )
                    .modifier(AIEqualizerQuickPopoverPresentation())
                }
                .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showTuningDetails, onDismiss: {
            isExpanded = false
        }) {
            NavigationStack {
                AIEqualizerLabView()
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: tuningProgress
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: isExpanded
        )
        .onChange(of: player.currentSong?.id) { _, _ in
            completionNoticeTask?.cancel()
            openDetailsTask?.cancel()
            isExpanded = false
            showQuickControls = false
        }
        .onChange(of: agent.phase) { _, newPhase in
            if newPhase.isWorking {
                isExpanded = false
            }
        }
        .onChange(of: agent.appliedProposalID) { _, proposalID in
            completionNoticeTask?.cancel()
            guard proposalID != nil else { return }
            isExpanded = true
            completionNoticeTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                isExpanded = false
            }
        }
        .onDisappear {
            completionNoticeTask?.cancel()
            openDetailsTask?.cancel()
        }
    }

    private var accessibilityText: String {
        if let name = appliedProfileName {
            return String(format: String(localized: "ai_tuning_player_notice"), name)
        }
        if !agent.isAutomaticTuningActive {
            return String(localized: "ai_quick_disabled")
        }
        return agent.samplingStage.title
    }

    private func compactElapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func openQuickControls() {
        completionNoticeTask?.cancel()
        isExpanded = false
        showQuickControls = true
    }

    private func openTuningDetails() {
        showQuickControls = false
        openDetailsTask?.cancel()
        openDetailsTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 20 : 170))
            guard !Task.isCancelled else { return }
            showTuningDetails = true
        }
    }
}

private struct AIEqualizerQuickControlsView: View {
    let accent: Color
    let tuningProgress: Double?
    let onOpenDetails: () -> Void

    @ObservedObject private var agent = AIEqualizerAgent.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        .primary
    }

    private var secondaryColor: Color {
        .secondary
    }

    private var currentProfileName: String {
        let name = agent.proposal?.profileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(localized: "ai_lab_result_empty") : name
    }

    private var currentTuningProfileTitle: String {
        agent.proposal?.resolvedTuningProfile.title ?? agent.tuningProfile.title
    }

    private var currentQuickProfileLabel: String {
        "\(currentTuningProfileTitle) · \(currentProfileName)"
    }

    private var statusText: String {
        switch agent.phase {
        case .idle:
            return agent.isAutomaticTuningActive
                ? String(localized: "ai_lab_not_analyzed")
                : String(localized: "ai_quick_disabled")
        case .sampling:
            return agent.samplingStage.title
        case .requesting:
            return agent.generationStage.title
        case .applying:
            return String(localized: "ai_lab_applying")
        case .ready:
            return agent.isCurrentProposalApplied
                ? String(localized: "ai_lab_applied")
                : String(localized: "ai_lab_ready")
        case .failed:
            return String(localized: "ai_lab_failed")
        }
    }

    private var tuningProfileSelection: Binding<String> {
        Binding(
            get: { agent.tuningProfile.rawValue },
            set: { rawValue in
                guard let profile = AIEqualizerTuningProfile(rawValue: rawValue) else { return }
                agent.selectTuningProfile(profile)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(foregroundColor.opacity(0.1))
                .padding(.horizontal, 14)

            profileMenu
                .padding(.horizontal, 14)
                .padding(.top, 11)

            tuningDirection
                .padding(.horizontal, 14)
                .padding(.top, 12)

            actions
                .padding(14)
        }
        .frame(width: 274)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AIEqualizerArtworkStatusGlyph(
                progress: tuningProgress,
                isComplete: agent.isCurrentProposalApplied,
                isEnabled: agent.isAutomaticTuningActive,
                reduceMotion: reduceMotion,
                foregroundColor: foregroundColor
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "ai_lab_auto_configure"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foregroundColor)

                Text(statusText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { agent.isAutomaticTuningActive },
                set: { agent.automaticConfigurationEnabled = $0 }
            ))
                .disabled(!agent.tuningServiceStore.settings.isEnabled)
                .labelsHidden()
                .tint(accent)
                .controlSize(.mini)
                .accessibilityLabel(String(localized: "ai_lab_automation"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var profileMenu: some View {
        Menu {
            if agent.applicableSavedProposals.isEmpty {
                Button(String(localized: "ai_lab_history_empty")) {}
                    .disabled(true)
            } else {
                ForEach(AIEqualizerTuningProfile.allCases) { profile in
                    if agent.applicableSavedProposals.contains(where: {
                        $0.proposal.resolvedTuningProfile == profile
                    }) {
                        Section(profile.title) {
                            ForEach(agent.applicableSavedProposals.filter {
                                $0.proposal.resolvedTuningProfile == profile
                            }) { saved in
                                Button {
                                    if !agent.isAutomaticTuningActive {
                                        agent.automaticConfigurationEnabled = true
                                    }
                                    agent.applySavedProposal(saved)
                                } label: {
                                    let title = saved.proposal.profileName.isEmpty
                                        ? String(localized: "ai_eq_profile_default")
                                        : saved.proposal.profileName
                                    let time = saved.proposal.createdAt.formatted(
                                        date: .omitted,
                                        time: .shortened
                                    )
                                    if agent.appliedProposalID == saved.id {
                                        Label("\(title) · \(time)", systemImage: "checkmark")
                                    } else {
                                        Text("\(title) · \(time)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(String(localized: "ai_quick_current_profile"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(secondaryColor)

                Spacer(minLength: 8)

                Text(currentQuickProfileLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)

                MonoIcon(
                    icon: .chevronDown,
                    size: 9,
                    color: secondaryColor,
                    lineWidth: 1.6
                )
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(agent.applicableSavedProposals.isEmpty)
        .accessibilityLabel(String(localized: "ai_quick_current_profile"))
    }

    private var tuningDirection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "ai_quick_tuning_direction"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(secondaryColor)

            Picker("", selection: tuningProfileSelection) {
                ForEach(AIEqualizerTuningProfile.allCases) { profile in
                    Text(profile.title)
                        .tag(profile.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(accent)
            .controlSize(.small)
            .disabled(agent.phase.isWorking)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    MonoIcon(
                        icon: agent.phase.isWorking ? .close : .refresh,
                        size: 11,
                        color: foregroundColor,
                        lineWidth: 1.7
                    )
                    Text(
                        agent.phase.isWorking
                            ? String(localized: "ai_lab_cancel")
                            : String(localized: "ai_lab_reanalyze")
                    )
                    .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                )
            }
            .buttonStyle(MonoBouncingButtonStyle())

            Button(action: onOpenDetails) {
                HStack(spacing: 5) {
                    Text(String(localized: "ai_quick_details"))
                        .font(.system(size: 11.5, weight: .semibold))
                    MonoIcon(
                        icon: .chevronRight,
                        size: 9,
                        color: secondaryColor,
                        lineWidth: 1.6
                    )
                }
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(foregroundColor.opacity(0.07))
                )
            }
            .buttonStyle(MonoBouncingButtonStyle())
        }
    }

    private func primaryAction() {
        if agent.phase.isWorking {
            agent.cancelAnalysis()
            return
        }
        if !agent.isAutomaticTuningActive {
            agent.automaticConfigurationEnabled = true
        }
        agent.analyzeCurrentSong()
    }
}

private struct AIEqualizerQuickPopoverPresentation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}

private struct AIEqualizerStatusGlassBackground: View {
    let accent: Color
    let isDarkArtwork: Bool

    private var adaptiveWash: Color {
        isDarkArtwork ? Color.black.opacity(0.48) : Color.white.opacity(0.76)
    }

    var body: some View {
        if #available(iOS 26, *) {
            Capsule(style: .continuous)
                .fill(adaptiveWash)
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(isDarkArtwork ? 0.13 : 0.07))
                }
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(adaptiveWash)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(isDarkArtwork ? 0.13 : 0.07))
                }
        }
    }
}

private struct AIEqualizerArtworkStatusGlyph: View {
    let progress: Double?
    let isComplete: Bool
    let isEnabled: Bool
    let reduceMotion: Bool
    let foregroundColor: Color

    @ObservedObject private var performance = AriaPerformanceGovernor.shared

    private var animationFramesPerSecond: Int {
        switch performance.tier {
        case .high: return 16
        case .medium: return 9
        case .low: return 5
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(foregroundColor.opacity(isComplete ? 0.1 : 0.08))

            if let progress {
                Circle()
                    .stroke(foregroundColor.opacity(0.2), lineWidth: 1.1)

                Circle()
                    .trim(from: 0, to: min(1, max(0.02, progress)))
                    .stroke(
                        foregroundColor,
                        style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                TimelineView(
                    AppFrameRate.throttledTimeline(
                        maximumFramesPerSecond: animationFramesPerSecond,
                        paused: reduceMotion
                    )
                ) { timeline in
                    Canvas { context, size in
                        drawBars(
                            in: &context,
                            size: size,
                            time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                    .padding(5.5)
                }
            } else if isComplete {
                MonoIcon(icon: .sparkle, size: 11, color: foregroundColor)
            } else {
                MonoIcon(
                    icon: .sparkle,
                    size: 11,
                    color: foregroundColor.opacity(isEnabled ? 0.9 : 0.52)
                )

                if !isEnabled {
                    Path { path in
                        path.move(to: CGPoint(x: 7, y: 7))
                        path.addLine(to: CGPoint(x: 16, y: 16))
                    }
                    .stroke(
                        foregroundColor.opacity(0.68),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: 23, height: 23)
        .animation(.easeOut(duration: 0.2), value: progress)
    }

    private func drawBars(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let amplitudes = [0.58, 0.92, 0.7]
        let barWidth = max(1.5, size.width * 0.16)
        let gap = max(1.3, size.width * 0.1)
        let totalWidth = barWidth * 3 + gap * 2
        let startX = (size.width - totalWidth) * 0.5

        for index in 0..<3 {
            let motion = reduceMotion ? 0.72 : 0.58 + 0.42 * abs(sin(time * 2.5 + Double(index) * 1.15))
            let height = max(2.2, size.height * amplitudes[index] * motion)
            let rect = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: (size.height - height) * 0.5,
                width: barWidth,
                height: height
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth * 0.5),
                with: .color(foregroundColor)
            )
        }
    }
}
