//  设置界面

import Combine
import SwiftUI

func settingsText(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func settingsFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: settingsText(key), locale: Locale.current, arguments: arguments)
}

func themedSettingsFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    if ClarityStyle.isActive {
        return ClarityStyle.body(size, weight: weight)
    }
    if MinimalWhiteStyle.isActive {
        return MinimalWhiteStyle.bodyFont(size, weight: weight)
    }
    if MangaStyle.isActive {
        return MangaStyle.comicFont(size, weight: weight == .regular ? .bold : weight)
    }
    if PetWhiteStyle.isActive {
        return PetWhiteStyle.labelFont(size, weight: weight == .bold ? .black : weight)
    }
    if NeumorphicStyle.isActive {
        return NeumorphicStyle.labelFont(size, weight: weight)
    }
    if SignalStyle.isActive {
        return SignalStyle.labelFont(size, weight: weight)
    }
    if BentoStyle.isActive {
        return BentoStyle.labelFont(size, weight: weight == .bold ? .heavy : weight)
    }
    if CapsuleStyle.isActive {
        return CapsuleStyle.labelFont(size, weight: weight == .bold ? .bold : weight)
    }
    if SequoiaStyle.isActive {
        return SequoiaStyle.labelFont(size, weight: weight == .bold ? .semibold : weight)
    }
    if MujiStyle.isActive {
        // 杂志正文用衬线
        return MujiStyle.bodyFont(size, weight: weight == .bold ? .medium : weight)
    }
    return .system(size: size, weight: weight, design: .rounded)
}

func themedSettingsPrimaryColor() -> Color {
    if ClarityStyle.isActive { return ClarityStyle.ink }
    if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
    if MangaStyle.isActive { return MangaStyle.ink }
    if PetWhiteStyle.isActive { return PetWhiteStyle.ink }
    if MujiStyle.isActive { return MujiStyle.ink }
    if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
    if CapsuleStyle.isActive { return CapsuleStyle.ink }
    if SequoiaStyle.isActive { return SequoiaStyle.ink }
    if SignalStyle.isActive { return SignalStyle.ink }
    if BentoStyle.isActive { return BentoStyle.ink }
    return .monoTextPrimary
}

func themedSettingsSecondaryColor() -> Color {
    if ClarityStyle.isActive { return ClarityStyle.inkSoft }
    if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
    if MangaStyle.isActive { return MangaStyle.inkSub }
    if PetWhiteStyle.isActive { return PetWhiteStyle.inkSoft }
    if MujiStyle.isActive { return MujiStyle.inkSoft }
    if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
    if CapsuleStyle.isActive { return CapsuleStyle.inkSoft }
    if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
    if SignalStyle.isActive { return SignalStyle.inkSoft }
    if BentoStyle.isActive { return BentoStyle.inkSoft }
    return .monoTextSecondary
}

enum SettingsNavigationDestination: Hashable {
    case appearance
    case playback
    case cloudSync
    case aiConfiguration
    case tuningService
    case storage
    case download
    case about
    case developerTools
    case developerPopupCatalog
    case debugLog
    case crashDiagnostics
    case agentTrace
    case aiProviderSettings
    case audioTraining
    case ffmpegCapabilityTest
    case platformAccountSwitching

    @MainActor
    @ViewBuilder
    var view: some View {
        switch self {
        case .appearance:
            AppearanceSettingsView()
        case .playback:
            PlaybackSettingsView()
        case .cloudSync:
            CloudSyncSettingsView()
        case .aiConfiguration:
            AIProviderSettingsView()
        case .tuningService:
            AITuningServiceSettingsView()
        case .storage:
            StorageManageView()
        case .download:
            DownloadManageView()
        case .about:
            AboutView()
        case .developerTools:
            DeveloperToolsView()
        case .developerPopupCatalog:
            if AppConfig.DeveloperAccess.hasFullTools {
                DeveloperPopupCatalogView()
            } else {
                DeveloperToolsView()
            }
        case .debugLog:
            DebugLogView()
        case .crashDiagnostics:
            CrashDiagnosticsView()
        case .agentTrace:
            AIAgentTraceDeveloperView()
        case .aiProviderSettings:
            if AppConfig.DeveloperAccess.hasFullTools {
                AIProviderDeveloperSettingsView()
            } else {
                DeveloperToolsView()
            }
        case .audioTraining:
            if AppConfig.DeveloperAccess.hasFullTools {
                AudioTrainingDeveloperView()
            } else {
                DeveloperToolsView()
            }
        case .ffmpegCapabilityTest:
            if AppConfig.DeveloperAccess.hasFullTools {
                FFmpegCapabilityTestView()
            } else {
                DeveloperToolsView()
            }
        case .platformAccountSwitching:
            if AppConfig.DeveloperAccess.hasFullTools {
                PlatformAccountSwitchingView()
            } else {
                DeveloperToolsView()
            }
        }
    }
}

struct SettingsNavigationLink<Label: View>: View {
    let destination: SettingsNavigationDestination
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            destination.view
        } label: {
            label()
        }
    }
}

struct ThemedSettingsBackground: View {
    var body: some View {
        ThemedPageBackground(useRenderLayer: true)
            .ignoresSafeArea()
    }
}

enum SettingsPageLayout {
    static let scrollCoordinateSpace = "mono.settings.detail.scroll"

    static var sectionSpacing: CGFloat {
        GlobalThemeId.persistedOrDefault == .default ? 16 : 20
    }

    static var deepSectionSpacing: CGFloat {
        GlobalThemeId.persistedOrDefault == .default ? 16 : 22
    }

    static var contentWidth: CGFloat {
        GlobalThemeId.persistedOrDefault == .default ? 720 : 700
    }
}

struct AsideSettingsDetailChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .monoNavigationBackButton()
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(SignalStyle.isActive ? SignalStyle.accent : nil)
            .preferredColorScheme(SignalStyle.isActive ? .dark : nil)
    }
}

extension View {
    func asideSettingsDetailChrome() -> some View {
        modifier(AsideSettingsDetailChromeModifier())
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var onlineAccess = OnlineAccessManager.shared
    @State var playlistSyncStatusMessage = LocalPlaylistCloudSyncManager.shared.lastStatusMessage
    @State var playlistLastSyncedAt = LocalPlaylistCloudSyncManager.shared.lastSyncedAt
    @State var cacheSizeTask: Task<Void, Never>?
    @State var cacheSize: String = .init(localized: "settings_calculating")
    @AppStorage(AppConfig.StorageKeys.developerModeEnabled) var qqDevMode = false
    @State var apiTokenInput = ""
    @State var tokenSaved = false
    @State var isHeaderCardExpanded = false
    @State var isShowingTokenAgreement = false

    @State var wechatCopied = false

    var body: some View {
        settingsRoot
            .preferredColorScheme(settings.preferredColorScheme)
    }

    /// 使用 `AnyView` 截断不透明类型链，规避 Swift 6.3 Release 的 SILGen 无限替换。
    var settingsRoot: AnyView {
        AnyView(
            ZStack {
                ThemedSettingsBackground()

                ScrollView {
                    LazyVStack(spacing: themedSettingsSpacing) {
                        settingsContent
                        AITuningServiceSettingsEntry()
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, settingsOuterHorizontalPadding)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
                .scrollIndicators(.hidden)
                .themeRenderScrollLayer()
            }
            .monoNavigationBackButton()
            .toolbarBackground(.hidden, for: .navigationBar)
            .monoSheet(isPresented: $isShowingTokenAgreement, onDismiss: {
                onlineAccess.declinePendingTokenAuthorization()
            }, preset: .standard) {
                TokenAgreementAuthorizationSheet(
                    onAgree: acceptPendingTokenAuthorization,
                    onDecline: declinePendingTokenAuthorization
                )
            }
            .onReceive(LocalPlaylistCloudSyncManager.shared.$lastStatusMessage.removeDuplicates()) {
                playlistSyncStatusMessage = $0
            }
            .onReceive(LocalPlaylistCloudSyncManager.shared.$lastSyncedAt.removeDuplicates()) {
                playlistLastSyncedAt = $0
            }
            .onDisappear {
                cacheSizeTask?.cancel()
                cacheSizeTask = nil
            }
            .onAppear {
                updateCacheSize()
                apiTokenInput = SecureConfig.apiToken ?? ""
                isHeaderCardExpanded = false
            }
        )
    }

    var themedSettingsSpacing: CGFloat {
        if MangaStyle.isActive { return 16 }
        if PetWhiteStyle.isActive { return 16 }
        if NeumorphicStyle.isActive { return 18 }
        if SignalStyle.isActive { return 17 }
        if CapsuleStyle.isActive { return 16 }
        if SequoiaStyle.isActive { return 16 }
        if MujiStyle.isActive { return 18 }
        return 16
    }

    var settingsOuterHorizontalPadding: CGFloat {
        DeviceLayout.settingsSectionHorizontalPadding
    }

    /// 擦除各主题分支形成的巨型 `_ConditionalContent`，避免 Release 构建阶段
    /// 类型替换崩溃；每个分支仍用相同间距的 `VStack` 保持布局一致。
    var settingsContent: AnyView {
        let spacing = themedSettingsSpacing
        if ClarityStyle.isActive {
            return AnyView(VStack(spacing: spacing) { claritySettingsContent })
        } else if MangaStyle.isActive {
            return AnyView(VStack(spacing: spacing) { mangaSettingsContent })
        } else if PetWhiteStyle.isActive {
            return AnyView(VStack(spacing: spacing) { petWhiteSettingsContent })
        } else if NeumorphicStyle.isActive {
            return AnyView(VStack(spacing: spacing) { neumorphicSettingsContent })
        } else if SignalStyle.isActive {
            return AnyView(VStack(spacing: spacing) { signalSettingsContent })
        } else if BentoStyle.isActive {
            return AnyView(VStack(spacing: spacing) { bentoSettingsContent })
        } else if CapsuleStyle.isActive {
            return AnyView(VStack(spacing: spacing) { capsuleSettingsContent })
        } else if SequoiaStyle.isActive {
            return AnyView(VStack(spacing: spacing) { sequoiaSettingsContent })
        } else if LiquidGlassStyle.isActive {
            return AnyView(VStack(spacing: spacing) { liquidGlassSettingsContent })
        } else if MujiStyle.isActive {
            return AnyView(VStack(spacing: spacing) { mujiSettingsContent })
        } else {
            return AnyView(VStack(spacing: spacing) { defaultSettingsContent })
        }
    }

    @ViewBuilder
    var defaultSettingsContent: some View {
        asideSettingsMasthead
        settingsHeaderCard
        asidePersonalizationSection
        asidePlaybackSection
        asideDataSection
        if qqDevMode {
            otherSection
        }
    }

}
