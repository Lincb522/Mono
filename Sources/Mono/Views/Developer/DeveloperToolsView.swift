import SwiftUI
import Combine

struct DeveloperDiagnosticStyleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var developerDiagnosticStyle: Bool {
        get { self[DeveloperDiagnosticStyleKey.self] }
        set { self[DeveloperDiagnosticStyleKey.self] = newValue }
    }
}

@MainActor
final class DeveloperDiagnosticTabBarVisibilityCoordinator {
    static let shared = DeveloperDiagnosticTabBarVisibilityCoordinator()

    private var owners: Set<UUID> = []
    private var previouslyHidden = false
    private var hasActiveLeaseSession = false
    private var pendingRestoreTask: Task<Void, Never>?

    func acquire(_ owner: UUID) {
        pendingRestoreTask?.cancel()
        pendingRestoreTask = nil
        guard owners.insert(owner).inserted else { return }
        if !hasActiveLeaseSession {
            previouslyHidden = PlayerManager.shared.isTabBarHidden
            hasActiveLeaseSession = true
        }
        PlayerManager.shared.isTabBarHidden = true
    }

    func release(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        pendingRestoreTask?.cancel()
        pendingRestoreTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, self.owners.isEmpty else { return }
            PlayerManager.shared.isTabBarHidden = self.previouslyHidden
            self.hasActiveLeaseSession = false
            self.pendingRestoreTask = nil
        }
    }
}

@MainActor
struct DeveloperDiagnosticTabBarHiddenModifier: ViewModifier {
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                DeveloperDiagnosticTabBarVisibilityCoordinator.shared.acquire(owner)
            }
            .onDisappear {
                DeveloperDiagnosticTabBarVisibilityCoordinator.shared.release(owner)
            }
    }
}

struct DeveloperDiagnosticBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.027, blue: 0.034)

            RadialGradient(
                colors: [Color.cyan.opacity(0.1), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )

            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct DeveloperDiagnosticStatus: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct DeveloperDiagnosticPageModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .dark)
            .environment(\.developerDiagnosticStyle, true)
            .compatFontDesign(nil)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .monoNavigationBackButton(iconColor: .white)
            .modifier(DeveloperDiagnosticTabBarHiddenModifier())
    }
}

extension View {
    @MainActor
    func developerDiagnosticPageChrome(title: String) -> some View {
        modifier(DeveloperDiagnosticPageModifier(title: title))
    }
}

// MARK: - 开发者模式

@MainActor
struct DeveloperToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var onlineAccess = OnlineAccessManager.shared
    @ObservedObject private var aiProvider = AIProviderConfigurationStore.shared
    private let agentTraces = AIAgentTraceStore.shared
    private let crashDiagnostics = CrashDiagnosticsStore.shared
    @State private var agentTraceCount = AIAgentTraceStore.shared.sessions.count
    @State private var crashCount = CrashDiagnosticsStore.shared.records.count

    var body: some View {
        let _ = settings.globalThemeRevision
        let _ = onlineAccess.lastTokenStatus
        let hasFullAccess = AppConfig.DeveloperAccess.hasFullTools

        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                VStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                    DeveloperDiagnosticStatus(status: String(
                            localized: hasFullAccess
                                ? "dev_mode_access_full"
                                : "dev_mode_access_basic"
                        ))
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)

                    VStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                        SettingsSection(title: String(localized: "developer_tools_section_diagnostics")) {
                            SettingsRouteLinkRow(
                                icon: .history,
                                title: String(localized: "agent_trace_title"),
                                value: "\(agentTraceCount)",
                                destination: .agentTrace
                            )

                            Divider()
                                .padding(.leading, 58)

                            DeveloperLogCountRow()

                            Divider()
                                .padding(.leading, 58)

                            SettingsRouteLinkRow(
                                icon: .warning,
                                title: String(localized: "crash_diagnostics_title"),
                                value: "\(crashCount)",
                                destination: .crashDiagnostics
                            )
                        }

                        if hasFullAccess {
                            SettingsSection(title: String(localized: "developer_tools_section_accounts")) {
                                SettingsRouteLinkRow(
                                    icon: .personCircle,
                                    title: String(localized: "developer_platform_switching"),
                                    value: "NCM · QCM · KCM",
                                    destination: .platformAccountSwitching
                                )
                            }

                            SettingsSection(title: String(localized: "developer_tools_section_testing")) {
                                SettingsRouteLinkRow(
                                    icon: .sparkle,
                                    title: String(localized: "ai_provider_settings_title"),
                                    value: aiProvider.wireProtocol.title,
                                    destination: .aiProviderSettings
                                )

                                Divider()
                                    .padding(.leading, 58)

                                SettingsRouteLinkRow(
                                    icon: .chart,
                                    title: String(localized: "audio_training_title"),
                                    value: String(localized: "audio_training_scope_value"),
                                    destination: .audioTraining
                                )

                                Divider()
                                    .padding(.leading, 58)

                                SettingsRouteLinkRow(
                                    icon: .waveform,
                                    title: String(localized: "developer_audio_lab"),
                                    value: "FFmpeg",
                                    destination: .ffmpegCapabilityTest
                                )

                                Divider()
                                    .padding(.leading, 58)

                                SettingsRouteLinkRow(
                                    icon: .gridSquare,
                                    title: String(localized: "dev_popup_catalog_title"),
                                    value: "\(DeveloperPopupCatalogView.previewCount)",
                                    destination: .developerPopupCatalog
                                )
                            }

                            SettingsSection(title: String(localized: "developer_tools_section_access")) {
                                SettingsInfoRow(
                                    icon: .unlock,
                                    title: String(localized: "dev_mode_title"),
                                    value: String(localized: "dev_mode_access_full")
                                )

                                Divider()
                                    .padding(.leading, 58)

                                SettingsButtonRow(
                                    icon: .lock,
                                    title: String(localized: "dev_mode_disable_action"),
                                    titleColor: .red,
                                    action: confirmDisableDeveloperMode
                                )
                            }
                        }

                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
        }
        .onReceive(agentTraces.$sessions.map(\.count).removeDuplicates()) { agentTraceCount = $0 }
        .onReceive(crashDiagnostics.$records.map(\.count).removeDuplicates()) { crashCount = $0 }
        .developerDiagnosticPageChrome(title: String(localized: "dev_mode_title"))
    }

    private func confirmDisableDeveloperMode() {
        AlertManager.shared.show(
            title: String(localized: "dev_mode_disable"),
            message: "",
            primaryButtonTitle: String(localized: "dev_mode_confirm"),
            secondaryButtonTitle: String(localized: "dev_mode_cancel"),
            primaryAction: {
                UserDefaults.standard.set(false, forKey: AppConfig.StorageKeys.developerModeEnabled)
                HapticManager.shared.success()
                dismiss()
            }
        )
    }
}

// MARK: - 开发者弹窗预览

@MainActor
struct DeveloperPopupCatalogView: View {
    private enum PreviewGroup: String, CaseIterable, Identifiable {
        case alerts
        case launch
        case feature

        var id: String { rawValue }

        var title: String {
            switch self {
            case .alerts: return String(localized: "dev_popup_group_alerts")
            case .launch: return String(localized: "dev_popup_group_launch")
            case .feature: return String(localized: "dev_popup_group_features")
            }
        }
    }

    private enum PopupPreview: String, CaseIterable, Identifiable {
        case informationAlert
        case confirmationAlert
        case textInputAlert
        case secureInputAlert
        case changelog
        case resonanceIntroduction
        case resonanceUpdate
        case resonanceFailure
        case greetingDaily
        case greetingSolarBirthday
        case greetingLunarBirthday
        case reportWeekly
        case reportMonthly
        case musicQueue
        case podcastQueue
        case soundQuality
        case qishuiQuality
        case equalizer
        case playerTheme
        case backgroundAudio
        case sleepTimer
        case podcastSpeed
        case lyricSource
        case immersiveBackground
        case addToPlaylist
        case downloadQuality

        var id: String { rawValue }

        var group: PreviewGroup {
            switch self {
            case .informationAlert, .confirmationAlert, .textInputAlert, .secureInputAlert:
                return .alerts
            case .changelog, .resonanceIntroduction, .resonanceUpdate, .resonanceFailure,
                 .greetingDaily, .greetingSolarBirthday, .greetingLunarBirthday,
                 .reportWeekly, .reportMonthly:
                return .launch
            default:
                return .feature
            }
        }

        var title: String {
            L10n.dynamic("dev_popup_\(rawValue)")
        }

        var icon: MonoIcon.IconType {
            switch self {
            case .informationAlert: return .infoCircle
            case .confirmationAlert: return .warning
            case .textInputAlert: return .save
            case .secureInputAlert: return .lock
            case .changelog: return .history
            case .resonanceIntroduction: return .waveform
            case .resonanceUpdate: return .refresh
            case .resonanceFailure: return .warning
            case .greetingDaily, .greetingSolarBirthday, .greetingLunarBirthday: return .emoji
            case .reportWeekly, .reportMonthly: return .chart
            case .musicQueue: return .musicNoteList
            case .podcastQueue: return .podcast
            case .soundQuality, .qishuiQuality, .downloadQuality: return .soundQuality
            case .equalizer: return .equalizer
            case .playerTheme: return .playerTheme
            case .backgroundAudio: return .headphones
            case .sleepTimer: return .clock
            case .podcastSpeed: return .waveform
            case .lyricSource: return .translate
            case .immersiveBackground: return .immersive
            case .addToPlaylist: return .addToQueue
            }
        }

        var sheetPreset: MonoSheetPreset {
            switch self {
            case .equalizer, .immersiveBackground:
                return .large
            case .playerTheme:
                return .themePicker
            case .podcastSpeed, .lyricSource, .downloadQuality:
                return .compact
            default:
                return .standard
            }
        }

        var isSheet: Bool {
            group == .feature
        }
    }

    @ObservedObject private var settings = SettingsManager.shared
    @State private var presentedSheet: PopupPreview?
    @State private var previewNeteaseQuality: SoundQuality = .lossless
    @State private var previewQQQuality: QQMusicQuality = .flac
    @State private var previewQishuiQuality = "lossless"

    static var previewCount: Int { PopupPreview.allCases.count }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            DeveloperDiagnosticBackdrop()

            ScrollView {
                LazyVStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                    DeveloperDiagnosticStatus(status: "\(Self.previewCount)")
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)

                    LazyVStack(spacing: SettingsPageLayout.deepSectionSpacing) {
                        ForEach(PreviewGroup.allCases) { group in
                            previewSection(group)
                        }

                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
        }
        .developerDiagnosticPageChrome(title: String(localized: "dev_popup_catalog_title"))
        .monoSheet(
            item: $presentedSheet,
            preset: presentedSheet?.sheetPreset ?? .standard
        ) { preview in
            sheetContent(for: preview)
        }
    }

    private func previewSection(_ group: PreviewGroup) -> some View {
        let previews = PopupPreview.allCases.filter { $0.group == group }

        return SettingsSection(title: group.title) {
            ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                SettingsNavigationRow(
                    icon: preview.icon,
                    title: preview.title,
                    action: { present(preview) }
                )

                if index < previews.count - 1 {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
    }

    private func present(_ preview: PopupPreview) {
        HapticManager.shared.light()

        switch preview {
        case .informationAlert:
            AlertManager.shared.show(
                title: String(localized: "dev_popup_sample_info_title"),
                message: String(localized: "dev_popup_sample_info_message"),
                primaryButtonTitle: String(localized: "common_ok"),
                primaryAction: {}
            )

        case .confirmationAlert:
            AlertManager.shared.show(
                title: String(localized: "dev_popup_sample_confirm_title"),
                message: String(localized: "dev_popup_sample_confirm_message"),
                primaryButtonTitle: String(localized: "confirm"),
                secondaryButtonTitle: String(localized: "alert_cancel"),
                primaryAction: {}
            )

        case .textInputAlert:
            AlertManager.shared.showInput(
                title: String(localized: "dev_popup_sample_input_title"),
                message: "",
                placeholder: String(localized: "dev_popup_sample_input_placeholder"),
                primaryButtonTitle: String(localized: "common_submit"),
                secondaryButtonTitle: String(localized: "alert_cancel"),
                onConfirm: { _ in }
            )

        case .secureInputAlert:
            AlertManager.shared.showInput(
                title: String(localized: "dev_popup_sample_secure_title"),
                message: "",
                placeholder: String(localized: "dev_mode_password"),
                isSecure: true,
                primaryButtonTitle: String(localized: "common_submit"),
                secondaryButtonTitle: String(localized: "alert_cancel"),
                onConfirm: { _ in }
            )

        case .changelog:
            ChangelogManager.shared.presentPreview(previewRelease)

        case .resonanceIntroduction:
            AIResonanceUpdateStore.shared.presentPreview(.introduction)

        case .resonanceUpdate:
            AIResonanceUpdateStore.shared.presentPreview(.updated)

        case .resonanceFailure:
            AIResonanceUpdateStore.shared.presentPreview(.failed)

        case .greetingDaily:
            presentGreeting(.daily(
                dayCount: SpecialGreetingManager.dayCount(),
                message: "今天也给自己留一点从容，让喜欢的歌慢慢把心情照亮。"
            ))

        case .greetingSolarBirthday:
            presentGreeting(.birthday(
                dayCount: SpecialGreetingManager.dayCount(),
                isLunar: false,
                message: "愿新一岁的日子有喜欢的旋律，也有被认真收藏的小小快乐。"
            ))

        case .greetingLunarBirthday:
            presentGreeting(.birthday(
                dayCount: SpecialGreetingManager.dayCount(),
                isLunar: true,
                message: "愿新一岁的日子有喜欢的旋律，也有被认真收藏的小小快乐。"
            ))

        case .reportWeekly:
            ListeningReportCenter.shared.presentPreview(kind: .week)

        case .reportMonthly:
            ListeningReportCenter.shared.presentPreview(kind: .month)

        default:
            guard preview.isSheet else { return }
            presentedSheet = preview
        }
    }

    private func presentGreeting(_ greeting: SpecialGreetingManager.Greeting) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            SpecialGreetingManager.shared.pending = greeting
        }
    }

    private var previewRelease: AppChangelogRelease {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        return AppChangelogRelease(
            id: "developer-preview-\(build)",
            version: version,
            build: build,
            title: String(localized: "dev_popup_changelog_title"),
            channel: "TestFlight",
            summary: nil,
            releaseNotes: String(localized: "dev_popup_changelog_notes"),
            publishedAt: nil
        )
    }

    private var previewSong: Song {
        var song = PreviewMocks.song
        song.source = .qqmusic
        song.qqMid = nil
        song.qqAlbumMid = nil
        return song
    }

    private func sheetContent(for preview: PopupPreview) -> AnyView {
        switch preview {
        case .musicQueue:
            return AnyView(PlaylistPopupView())

        case .podcastQueue:
            return AnyView(PodcastPlaylistPopupView())

        case .soundQuality:
            return AnyView(
                SoundQualitySheet(
                    currentQuality: previewNeteaseQuality,
                    currentQQQuality: previewQQQuality,
                    isQQMusic: false,
                    onSelectNetease: { quality in
                        previewNeteaseQuality = quality
                        presentedSheet = nil
                    },
                    onSelectQQ: { quality in
                        previewQQQuality = quality
                        presentedSheet = nil
                    }
                )
            )

        case .qishuiQuality:
            return AnyView(
                QishuiQualityPickerSheet(
                    currentQuality: previewQishuiQuality,
                    onSelect: { quality in
                        previewQishuiQuality = quality
                        presentedSheet = nil
                    }
                )
            )

        case .equalizer:
            return AnyView(NavigationStack { EQSettingsView() })

        case .playerTheme:
            return AnyView(PlayerThemePickerSheet())

        case .backgroundAudio:
            return AnyView(BackgroundAudioPolicySheet())

        case .sleepTimer:
            return AnyView(PodcastTimerSheet())

        case .podcastSpeed:
            return AnyView(PodcastSpeedSheet())

        case .lyricSource:
            return AnyView(CurrentSongLyricSourceSheet())

        case .immersiveBackground:
            return AnyView(ImmersiveBackgroundSheet())

        case .addToPlaylist:
            return AnyView(AddToPlaylistSheet(song: previewSong))

        case .downloadQuality:
            return AnyView(
                DownloadQualitySheet(song: previewSong) {
                    presentedSheet = nil
                }
            )

        default:
            return AnyView(EmptyView())
        }
    }
}


private struct DeveloperLogCountRow: View {
    @State private var count = AppLogger.logCount

    var body: some View {
        SettingsRouteLinkRow(
            icon: .logDebug,
            title: String(localized: "settings_debug_log"),
            value: "\(count)",
            destination: .debugLog
        )
        .onReceive(NotificationCenter.default.publisher(for: .appLoggerDidChange)
            .map { _ in AppLogger.logCount }.removeDuplicates()) { count = $0 }
        .onAppear { count = AppLogger.logCount }
    }
}
