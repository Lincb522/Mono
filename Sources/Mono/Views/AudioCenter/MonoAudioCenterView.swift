import SwiftUI
import UIKit

struct MonoSoundCenterLayout: Equatable {
    let availableSize: CGSize
    let horizontalInset: CGFloat
    let contentMaxWidth: CGFloat
    let workspaceMaxWidth: CGFloat
    let coverSize: CGFloat
    let primaryTabHeight: CGFloat
    let isCompactWidth: Bool
    let isCompactHeight: Bool

    init(size: CGSize) {
        let width = max(1, size.width)
        let height = max(1, size.height)
        availableSize = CGSize(width: width, height: height)
        isCompactWidth = width < 390
        isCompactHeight = height < 720
        horizontalInset = width < 350 ? 12 : (width < 700 ? 16 : 22)
        contentMaxWidth = min(width, width >= 700 ? 760 : width)
        workspaceMaxWidth = min(contentMaxWidth, width >= 700 ? 720 : contentMaxWidth)
        coverSize = isCompactHeight ? 46 : (width >= 700 ? 62 : 54)
        primaryTabHeight = isCompactHeight ? 34 : 38
    }

    static let fallback = MonoSoundCenterLayout(size: CGSize(width: 390, height: 844))
}

private struct MonoSoundCenterLayoutKey: EnvironmentKey {
    static let defaultValue = MonoSoundCenterLayout.fallback
}

extension EnvironmentValues {
    var monoSoundCenterLayout: MonoSoundCenterLayout {
        get { self[MonoSoundCenterLayoutKey.self] }
        set { self[MonoSoundCenterLayoutKey.self] = newValue }
    }
}

@MainActor
struct MonoAudioCenterView: View {
    enum Workspace: String, CaseIterable, Identifiable {
        case ai
        case custom
        case enhancement
        case output

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ai: return String(localized: "mono_audio_workspace_ai")
            case .custom: return String(localized: "mono_audio_workspace_custom")
            case .enhancement: return String(localized: "mono_audio_workspace_enhancement")
            case .output: return String(localized: "mono_audio_workspace_output")
            }
        }

        var icon: MonoIcon.IconType {
            switch self {
            case .ai: return .sparkle
            case .custom: return .equalizer
            case .enhancement: return .audioWave
            case .output: return .headphones
            }
        }

        var monoGlyphSemantic: MonoGlyphSemantic {
            switch self {
            case .ai: return .soundWorkspaceAI
            case .custom: return .soundWorkspaceCustomEQ
            case .enhancement: return .soundWorkspaceEnhancement
            case .output: return .soundWorkspaceOutput
            }
        }
    }

    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var agent = AIEqualizerAgent.shared
    @StateObject private var eqManager = EQManager.shared
    @StateObject private var suite = MonoNextSuiteManager.shared
    @StateObject private var airPods = AirPodsExperienceManager.shared
    @StateObject private var coverColors = CoverColorExtractor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var workspaceNamespace
    @State private var workspace: Workspace
    @State private var showsAgentSettings = false

    init(initialWorkspace: Workspace = .ai) {
        _workspace = State(initialValue: initialWorkspace)
    }

    private var accent: Color {
        normalizedMonoAudioAccent(coverColors.dominantColor)
    }

    private var accentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "101114"),
            dark: .white
        )
    }

    private var isProtectedAppleMusicPlayback: Bool {
        player.currentSong?.isAppleMusic == true
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MonoSoundCenterLayout(size: proxy.size)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    sharedTrackHeader(layout: layout)
                    primaryWorkspaceSwitcher(layout: layout)
                    selectedWorkspace
                        .frame(width: layout.workspaceMaxWidth)
                        .frame(maxHeight: .infinity)
                        .clipped()
                }
                // Use a concrete viewport width here. Several workspaces contain
                // horizontally scrolling controls whose ideal width is wider than
                // an iPhone. A max-width-only frame lets that ideal size leak up
                // the tree and can push the entire sound center off screen.
                .frame(
                    width: layout.contentMaxWidth,
                    height: proxy.size.height,
                    alignment: .top
                )
                .clipped()

                Spacer(minLength: 0)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
            .environment(\.monoSoundCenterLayout, layout)
        }
        .background { backdrop }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton(iconColor: .white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    workspaceStatus
                    Button { showsAgentSettings = true } label: {
                        MonoIcon(icon: .settings, size: 16, color: .white)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "audio_agent_settings_title"))
                }
            }
        }
        .navigationDestination(isPresented: $showsAgentSettings) {
            MonoAudioAgentSettingsView()
        }
        .onAppear(perform: refreshAccent)
        .onChange(of: player.currentSong?.id) { _, _ in
            refreshAccent()
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: workspace
        )
    }

    private var backdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)

            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) {
                    Color.clear
                }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.16)
                .blur(radius: 70)
                .saturation(0.72)
                .opacity(0.22)
                .clipped()
            }

            Color.black.opacity(0.58)
        }
        .ignoresSafeArea()
    }

    private func sharedTrackHeader(layout: MonoSoundCenterLayout) -> some View {
        HStack(spacing: layout.isCompactWidth ? 10 : 13) {
            Group {
                if let url = player.currentSong?.coverUrl?.sized(240) {
                    CachedAsyncImage(
                        url: url,
                        width: layout.coverSize,
                        height: layout.coverSize
                    ) {
                        coverPlaceholder
                    }
                    .aspectRatio(contentMode: .fill)
                } else {
                    coverPlaceholder
                }
            }
            .frame(width: layout.coverSize, height: layout.coverSize)
            .clipShape(RoundedRectangle(cornerRadius: layout.isCompactHeight ? 10 : 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: layout.isCompactHeight ? 10 : 12, style: .continuous)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: layout.isCompactHeight ? 2 : 4) {
                Text(player.currentSong?.name ?? String(localized: "mono_suite_no_track"))
                    .font(.system(size: layout.isCompactHeight ? 15.5 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(player.currentSong?.artistName ?? String(localized: "mono_suite_waiting_analysis"))
                    .font(.system(size: layout.isCompactHeight ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            currentModeBadge(layout: layout)
        }
        .padding(.horizontal, layout.horizontalInset)
        .padding(.top, layout.isCompactHeight ? 3 : 6)
        .padding(.bottom, layout.isCompactHeight ? 7 : 10)
        .frame(width: layout.contentMaxWidth)
        .background(Color.black.opacity(0.14))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                MonoIcon(icon: .musicNote, size: 21, color: .white.opacity(0.48))
            }
    }

    private func currentModeBadge(layout: MonoSoundCenterLayout) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            MonoIcon(
                icon: workspace.icon,
                size: layout.isCompactHeight ? 14 : 16,
                color: accent
            )
            .monoIconArtwork(workspace.monoGlyphSemantic.rawValue)
            if !layout.isCompactWidth {
                Text(workspace.title)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: layout.isCompactWidth ? 24 : 44)
    }

    private func primaryWorkspaceSwitcher(layout: MonoSoundCenterLayout) -> some View {
        HStack(spacing: 4) {
            ForEach(Workspace.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        workspace = item
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 6) {
                        MonoIcon(
                            icon: item.icon,
                            size: layout.isCompactWidth ? 11 : 12,
                            color: workspace == item ? accentForeground : .white.opacity(0.5)
                        )
                        .monoIconArtwork(item.monoGlyphSemantic.rawValue)
                        Text(item.title)
                            .font(.system(size: layout.isCompactWidth ? 9.5 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(workspace == item ? accentForeground : .white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        if workspaceHasActivity(item) {
                            Circle()
                                .fill(workspace == item ? accentForeground.opacity(0.8) : accent)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.primaryTabHeight)
                    .background {
                        if workspace == item {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(0.88))
                                .matchedGeometryEffect(id: "mono-audio-workspace", in: workspaceNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(workspace == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
        .padding(.horizontal, layout.horizontalInset)
        .padding(.vertical, layout.isCompactHeight ? 7 : 9)
        .frame(width: layout.contentMaxWidth)
    }

    @ViewBuilder
    private var selectedWorkspace: some View {
        if isProtectedAppleMusicPlayback, workspace != .output {
            VStack(spacing: 14) {
                MonoIcon(
                    icon: .musicNote,
                    size: 34,
                    color: accent,
                    lineWidth: 1.7
                )
                Text(String(localized: "apple_music_protected_audio"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "apple_music_sound_center_unavailable"))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
        } else {
            switch workspace {
            case .ai:
                AIEqualizerLabView(isEmbedded: true)
            case .custom:
                EQSettingsView(isEmbedded: true)
            case .enhancement:
                MonoSuiteSettingsView(isEmbedded: true)
            case .output:
                MonoOutputStudioView()
            }
        }
    }

    private var workspaceStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(workspaceHasActivity(workspace) ? accent : Color.white.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(workspaceStatusText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.28))
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
    }

    private var workspaceStatusText: String {
        if isProtectedAppleMusicPlayback, workspace != .output {
            return String(localized: "apple_music_protected_audio")
        }
        switch workspace {
        case .ai:
            if agent.phase.isWorking {
                return String(localized: "mono_audio_tuning")
            }
            return agent.proposal?.profileName ?? String(localized: "ai_lab_not_analyzed")
        case .custom:
            guard eqManager.isEnabled else { return String(localized: "settings_off") }
            guard !eqManager.isAIManagedPresetActive else {
                return String(localized: "eq_custom")
            }
            return eqManager.currentPreset?.name ?? String(localized: "eq_custom")
        case .enhancement:
            let managed: [MonoNextFeature] = [.spatialLive, .dna, .recovery]
            let active = managed.filter { suite.isEnabled($0) }.count
            return String(format: String(localized: "mono_suite_running_count"), active, managed.count)
        case .output:
            if eqManager.isHearingCorrectionEnabled {
                return String(localized: "sound_hearing_enabled")
            }
            if eqManager.selectedHeadphoneProfileID != "off" {
                return String(localized: "sound_output_profile_active")
            }
            return airPods.connection.isConnected
                ? airPods.selectedDeviceModel.title
                : eqManager.currentOutputKind.title
        }
    }

    private func workspaceHasActivity(_ item: Workspace) -> Bool {
        switch item {
        case .ai:
            return agent.phase.isWorking || agent.proposal != nil
        case .custom:
            return eqManager.isEnabled && !eqManager.isAIManagedPresetActive
        case .enhancement:
            return [MonoNextFeature.spatialLive, .dna, .recovery]
                .contains { suite.isEnabled($0) }
        case .output:
            return eqManager.selectedHeadphoneProfileID != "off"
                || eqManager.isHearingCorrectionEnabled
                || MonoLoudnessEngine.shared.isEnabled
                || (airPods.connection.isConnected
                    && (airPods.isEnabled || airPods.modelAwareAITuningEnabled))
        }
    }

    private func refreshAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(220).absoluteString)
    }
}

private func normalizedMonoAudioAccent(_ color: Color) -> Color {
    let uiColor = UIColor(color)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 1

    guard uiColor.getHue(
        &hue,
        saturation: &saturation,
        brightness: &brightness,
        alpha: &alpha
    ) else {
        return Color(red: 0.48, green: 0.7, blue: 1)
    }

    return Color(
        hue: Double(hue),
        saturation: Double(saturation < 0.08 ? 0.18 : min(0.74, saturation)),
        brightness: Double(max(0.82, brightness)),
        opacity: Double(alpha)
    )
}
