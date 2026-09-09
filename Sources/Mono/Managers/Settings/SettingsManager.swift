import Combine
import SwiftUI

/// 全局设置管理器
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - 外观设置

    /// 全局主题 ID
    @AppStorage("globalThemeId") var globalThemeIdRaw: String = GlobalThemeId.appDefault.rawValue

    @Published private(set) var globalThemeRevision: Int = 0
    @Published private(set) var globalThemeApplicationRevision: Int = 0

    var globalThemeId: GlobalThemeId {
        get {
            Self.resolveStoredTheme(globalThemeIdRaw)
        }
        set {
            selectGlobalTheme(newValue)
        }
    }

    func selectGlobalTheme(_ themeId: GlobalThemeId) {
        let previousId = globalThemeId
        let isSameTheme = previousId == themeId

        AppLogger.info("[ThemeSwitch] from=\(previousId.rawValue) to=\(themeId.rawValue) sameTheme=\(isSameTheme)")
        applyGlobalThemeSelection(
            themeId,
            bumpRevision: true,
            bumpApplicationRevision: true,
            applyPreferredIconSet: !isSameTheme
        )
    }

    func synchronizeGlobalThemeAfterLaunch(reason: String) {
        let storedRaw = UserDefaults.standard.string(forKey: GlobalThemeId.storageKey)
        let resolvedId = GlobalThemeId.resolvedStoredTheme(storedRaw ?? globalThemeIdRaw)

        AppLogger.info("[ThemeLaunchSync] reason=\(reason) persistedThemeId=\(storedRaw ?? "nil") finalThemeId=\(resolvedId.rawValue)")
        applyGlobalThemeSelection(
            resolvedId,
            bumpRevision: true,
            // 启动同步只校正持久化主题与颜色 token，不是一次用户主动切换。
            // 这里递增 application revision 会让已挂载的导航根误判为需要整树重建。
            bumpApplicationRevision: false,
            applyPreferredIconSet: false
        )
    }

    private static func resolveStoredTheme(_ raw: String) -> GlobalThemeId {
        GlobalThemeId.resolvedStoredTheme(raw)
    }

    /// 悬浮栏样式
    @AppStorage("floatingBarStyle") var floatingBarStyleRaw: String = FloatingBarStyle.unified.rawValue

    /// 悬浮栏样式（类型安全访问）
    var floatingBarStyle: FloatingBarStyle {
        // 已下线的样式会自然回落到现有云雾样式，避免升级后突然切回默认悬浮栏。
        get { FloatingBarStyle(rawValue: floatingBarStyleRaw) ?? .flux }
        set {
            guard floatingBarStyleRaw != newValue.rawValue else { return }
            objectWillChange.send()
            floatingBarStyleRaw = newValue.rawValue
        }
    }

    /// 默认主题下自定义 TabBar 是否使用液态玻璃；关闭时使用更稳定的毛玻璃底。
    @AppStorage("defaultThemeUsesLiquidGlassTabBar") var defaultThemeUsesLiquidGlassTabBar: Bool = false

    /// AsideMusic 默认主题的全屏封面取色流体背景。
    @AppStorage("asideMusicFluidBackgroundEnabled") var asideMusicFluidBackgroundEnabled: Bool = false {
        didSet {
            guard asideMusicFluidBackgroundEnabled != oldValue else { return }
            globalThemeRevision &+= 1
        }
    }

    @AppStorage("petWhiteUsesIllustratedBackground") var petWhiteUsesIllustratedBackground: Bool = false {
        didSet {
            globalThemeRevision &+= 1
        }
    }

    /// 主题模式: "system" 跟随系统, "light" 浅色, "dark" 深色
    @AppStorage("themeMode") var themeMode: String = "system" {
        didSet {
            guard themeMode != oldValue else { return }
            applyTheme()
        }
    }

    /// 实际生效的 ColorScheme，始终有明确值
    @Published var activeColorScheme: ColorScheme = .light {
        didSet {
            guard activeColorScheme != oldValue else { return }
            UserDefaults.standard.set(activeColorScheme == .dark ? "dark" : "light", forKey: "themeResolvedColorScheme")
            GlobalThemeManager.shared.refreshCurrentThemeTokens()
            globalThemeRevision &+= 1
        }
    }

    /// 根据设置返回对应的 ColorScheme（用于 .preferredColorScheme 修饰符）
    var preferredColorScheme: ColorScheme? {
        if globalThemeId.requiresDarkAppearance { return .dark }

        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil // 跟随系统
        }
    }

    /// 返回未被全局封面影响的“真实”系统/用户预设色彩模式
    var nativeColorScheme: ColorScheme {
        if globalThemeId.requiresDarkAppearance { return .dark }

        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default:
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    /// 应用主题到所有窗口（确保 fullScreenCover 等独立层级也能实时生效）
    func applyTheme() {
        let style: UIUserInterfaceStyle
        let effectiveMode = globalThemeId.requiresDarkAppearance ? "dark" : themeMode
        switch effectiveMode {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified // 跟随系统
        }

        // 先读取系统实际样式，避免 `.unspecified` 刚写回窗口时拿到短暂的未知/旧值。
        let resolvedSystemStyle = resolveSystemInterfaceStyle(fallback: activeColorScheme)

        // 遍历所有窗口场景，只在需要时刷新 overrideUserInterfaceStyle，减少整棵窗口树重复失效。
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    if window.overrideUserInterfaceStyle != style {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }

        AppFrameRate.lockConnectedScenesToPreferredFrameRate(reason: "apply theme")

        // 更新 activeColorScheme
        if style == .dark {
            activeColorScheme = .dark
        } else if style == .light {
            activeColorScheme = .light
        } else {
            activeColorScheme = (resolvedSystemStyle == .dark) ? .dark : .light
        }
    }

    /// 前台恢复时仅在系统明暗外观确实变化后刷新窗口，避免重复触发整棵主题视图更新。
    func refreshSystemThemeIfNeeded() {
        guard !globalThemeId.requiresDarkAppearance, themeMode == "system" else { return }
        let resolved: ColorScheme = UIScreen.main.traitCollection.userInterfaceStyle == .dark
            ? .dark
            : .light
        guard resolved != activeColorScheme else { return }
        applyTheme()
    }

    private func resolveSystemInterfaceStyle(fallback: ColorScheme) -> UIUserInterfaceStyle {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }

            let orderedWindows = windowScene.windows.sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow {
                    return lhs.isKeyWindow
                }
                return lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
            }

            for window in orderedWindows {
                let style = window.traitCollection.userInterfaceStyle
                if style == .dark || style == .light {
                    return style
                }
            }
        }

        let screenStyle = UIScreen.main.traitCollection.userInterfaceStyle
        if screenStyle == .dark || screenStyle == .light {
            return screenStyle
        }

        return fallback == .dark ? .dark : .light
    }

    // MARK: - 播放设置

    /// 音质设置（旧，保留兼容）
    @AppStorage("soundQuality") var soundQuality: String = "standard"

    /// 是否优先请求歌曲支持的最高音质
    @AppStorage(AppConfig.StorageKeys.preferHighestPlaybackQuality)
    var preferHighestPlaybackQuality: Bool = true

    /// 是否启用下一首无缝切歌预加载
    @AppStorage(AppConfig.StorageKeys.gaplessPlaybackEnabled)
    var gaplessPlaybackEnabled: Bool = true

    /// 是否在无缝切歌边界启用双路 PCM 交叉淡化
    @AppStorage(AppConfig.StorageKeys.crossfadePlaybackEnabled)
    var crossfadePlaybackEnabled: Bool = false

    /// 后台音频策略
    @AppStorage(AppConfig.StorageKeys.backgroundAudioPolicy)
    var backgroundAudioPolicyRaw: String = BackgroundAudioPolicy.automatic.rawValue

    /// 后台音频策略（类型安全访问）
    var backgroundAudioPolicy: BackgroundAudioPolicy {
        get { BackgroundAudioPolicy(rawValue: backgroundAudioPolicyRaw) ?? .automatic }
        set { backgroundAudioPolicyRaw = newValue.rawValue }
    }

    // MARK: - 游戏模式

    /// 游戏模式开关（主开关）
    @AppStorage(AppConfig.StorageKeys.gameModeEnabled)
    var gameModeEnabled: Bool = false

    /// 游戏出枪声等提示时自动降低音乐音量
    @AppStorage(AppConfig.StorageKeys.gameModeAutoDucking)
    var gameModeAutoDucking: Bool = true

    /// 游戏模式下自动降低音质（节省 CPU/电量）
    @AppStorage(AppConfig.StorageKeys.gameModeLowerQuality)
    var gameModeLowerQuality: Bool = true

    /// 检测到游戏退出后自动关闭游戏模式
    @AppStorage(AppConfig.StorageKeys.gameModeAutoExit)
    var gameModeAutoExit: Bool = false

    /// 游戏模式下隐藏锁屏 / 灵动岛的播放信息
    @AppStorage(AppConfig.StorageKeys.gameModeDisableLiveActivity)
    var gameModeSilentNowPlaying: Bool = false

    /// 【实验性】当 `gameModeSilentNowPlaying` 为 true 时，是否保留最小锁屏信息（仅歌名，无封面 / 歌手 / 时间）
    /// - false（默认）→ 完全清空 NowPlayingInfo（iOS 把 App 从锁屏/灵动岛移除）
    /// - true → 保留「歌名」作为唯一 now playing 信息，不提供其他内容也不参与播放控制
    @AppStorage(AppConfig.StorageKeys.gameModeMinimalNowPlaying)
    var gameModeMinimalNowPlaying: Bool = false

    /// 游戏模式自动播放的本地歌单 ID（空字符串表示禁用）
    @AppStorage(AppConfig.StorageKeys.gameModeAutoPlaylistLocalId)
    var gameModeAutoPlaylistLocalId: String = ""

    /// 游戏模式首选音质（空字符串 = 使用"降音质"的默认行为，即 .standard）
    @AppStorage(AppConfig.StorageKeys.gameModePreferredQuality)
    var gameModePreferredQualityRaw: String = ""

    var gameModePreferredQuality: SoundQuality? {
        get { SoundQuality(rawValue: gameModePreferredQualityRaw) }
        set { gameModePreferredQualityRaw = newValue?.rawValue ?? "" }
    }

    /// 应用图标 / Logo 风格。Paw 是新安装默认图标；主 AppIcon 文件名保持不变。
    @AppStorage(AppConfig.StorageKeys.appBrandStyle)
    var appBrandStyleRaw: String = AppBrandStyle.paw.rawValue

    var appBrandStyle: AppBrandStyle {
        get { AppBrandStyle(rawValue: appBrandStyleRaw) ?? .paw }
        set { appBrandStyleRaw = newValue.rawValue }
    }

    @AppStorage(AppConfig.StorageKeys.appBrandAppearance)
    var appBrandAppearanceRaw: String = AppBrandAppearance.light.rawValue

    var appBrandAppearance: AppBrandAppearance {
        get { AppBrandAppearance(rawValue: appBrandAppearanceRaw) ?? .light }
        set { appBrandAppearanceRaw = newValue.rawValue }
    }

    /// 界面图标库风格
    @AppStorage(AppConfig.StorageKeys.interfaceIconSet)
    var interfaceIconSetRaw: String = AppInterfaceIconSet.hicon.rawValue

    var interfaceIconSet: AppInterfaceIconSet {
        get { AppInterfaceIconSet.selectedFromDefaults }
        set {
            setInterfaceIconSet(newValue, bumpRevision: true)
        }
    }

    var appLogoAssetName: String {
        appBrandStyle.logoAssetName(for: appBrandAppearance)
    }

    var supportsAlternateAppIcons: Bool {
        #if os(iOS)
            UIApplication.shared.supportsAlternateIcons
        #else
            false
        #endif
    }

    @AppStorage(AppConfig.StorageKeys.playlistSyncAutoEnabled)
    var playlistSyncAutoEnabled: Bool = true

    @AppStorage(AppConfig.StorageKeys.playlistSyncDeleteCloudSnapshot)
    var playlistSyncDeleteCloudSnapshot: Bool = false

    /// 默认播放音质
    @AppStorage("defaultPlaybackQuality") var defaultPlaybackQuality: String = "standard"

    /// KCM 默认播放音质
    @AppStorage(AppConfig.StorageKeys.defaultKugouPlaybackQuality)
    var defaultKugouPlaybackQuality: String = SoundQuality.standard.rawValue

    /// qcm默认播放音质
    @AppStorage(AppConfig.StorageKeys.qqMusicQuality)
    var defaultQQPlaybackQuality: String = QQMusicQuality.mp3_320.rawValue

    /// QSM 默认播放音质
    @AppStorage("mono_qishui_quality")
    var defaultQishuiPlaybackQuality: String = "highest"

    /// 全部播放时是否将整张列表插入当前播放队列
    @AppStorage(AppConfig.StorageKeys.insertPlaybackContext)
    var insertPlaybackContext: Bool = false

    /// 播客默认播放顺序（false：最新一期优先；true：最早一期优先）
    @AppStorage(AppConfig.StorageKeys.podcastSortAscending)
    var podcastSortAscending: Bool = false

    /// 默认下载音质
    @AppStorage("defaultDownloadQuality") var defaultDownloadQuality: String = "standard"

    // MARK: - 缓存设置

    /// 最大缓存大小 (MB)
    @AppStorage("maxCacheSize") var maxCacheSize: Int = 500

    // MARK: - 听歌报告

    /// 日报 / 周报 / 月报 / 年报功能总开关（关闭后隐藏入口且不再弹窗）
    @AppStorage("listeningReportsEnabled") var listeningReportsEnabled: Bool = true

    /// 新的一周开始后自动弹出上周听歌报告
    @AppStorage("listeningReportWeeklyPopupEnabled") var listeningReportWeeklyPopupEnabled: Bool = true

    /// 新的一月开始后自动弹出上月听歌报告
    @AppStorage("listeningReportMonthlyPopupEnabled") var listeningReportMonthlyPopupEnabled: Bool = true

    // MARK: - 每日一言

    /// 每日一言开关
    @AppStorage("hitokotoEnabled") var hitokotoEnabled: Bool = true

    /// 每日一言类型 (a=动画 b=漫画 c=游戏 d=文学 e=原创 f=来自网络 g=其他 h=影视 i=诗词 j=ncm k=哲学 l=抖机灵)
    @AppStorage("hitokotoType") var hitokotoType: String = ""

    // MARK: - 其他设置

    /// 触感反馈
    @AppStorage("hapticFeedback") var hapticFeedback: Bool = true

    /// 喜欢同步到ncm（点喜欢时同时调用ncm API）
    @AppStorage("syncLikeToNetease") var syncLikeToNetease: Bool = true

    /// 喜欢时选择歌单（点喜欢新歌时弹出歌单选择器，而非直接加入「我喜欢」）
    @AppStorage("likeToChoosePlaylist") var likeToChoosePlaylist: Bool = false

    /// QMC 解密开关（qcm加密流解密，默认关闭）
    @AppStorage("qmcDecryptEnabled") var qmcDecryptEnabled: Bool = false

    @AppStorage("useSystemTabBar") var useSystemTabBar: Bool = false
    @AppStorage("systemTabBarStyle") var systemTabBarStyleRaw = SystemTabBarStyle.native.rawValue

    var systemTabBarStyle: SystemTabBarStyle {
        get { SystemTabBarStyle(rawValue: systemTabBarStyleRaw) ?? .native }
        set {
            guard systemTabBarStyleRaw != newValue.rawValue else { return }
            objectWillChange.send()
            systemTabBarStyleRaw = newValue.rawValue
        }
    }


    // MARK: - 封面背景设置

    /// 播放器动态专辑封面。优先使用歌曲所属平台的资源，
    /// 并允许其他平台的歌曲匹配 Apple Music 动态封面。
    @AppStorage("animatedArtworkEnabled") var animatedArtworkEnabled: Bool = true

    /// 全局动态封面背景（首页/资料库/搜索等跟随当前播放歌曲封面）
    @AppStorage("coverBgGlobal") var coverBgGlobal: Bool = false

    /// 歌单/专辑详情页封面模糊背景
    @AppStorage("coverBgPlaylist") var coverBgPlaylist: Bool = true

    /// 播放器封面模糊背景
    @AppStorage("coverBgPlayer") var coverBgPlayer: Bool = true

    /// 全局封面背景是否为深色（由亮度检测自动更新）
    @Published var globalCoverIsDark: Bool = false

    var locksCoverBackgroundSettings: Bool {
        !globalThemeId.supportsCoverBackgrounds
    }

    var usesGlobalCoverBackground: Bool {
        globalThemeId.supportsCoverBackgrounds && coverBgGlobal
    }

    var usesPlaylistCoverBackground: Bool {
        globalThemeId.supportsCoverBackgrounds && coverBgPlaylist
    }

    var usesPlayerCoverBackground: Bool {
        globalThemeId.supportsCoverBackgrounds && coverBgPlayer
    }

    // MARK: - 歌词设置

    /// 歌词颜色模式: "default" / "solid" / "gradient"
    @AppStorage("lyricColorMode") var lyricColorMode: String = "default"

    /// 纯色 hex
    @AppStorage("lyricSolidColorHex") var lyricSolidColorHex: String = "007AFF"

    /// 渐变起始色 hex
    @AppStorage("lyricGradientStartHex") var lyricGradientStartHex: String = "FF6B6B"

    /// 渐变结束色 hex
    @AppStorage("lyricGradientEndHex") var lyricGradientEndHex: String = "4ECDC4"

    private init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: AppConfig.StorageKeys.gaplessPlaybackEnabledMigrationV2) {
            gaplessPlaybackEnabled = true
            defaults.set(true, forKey: AppConfig.StorageKeys.gaplessPlaybackEnabledMigrationV2)
        }

        let storedRaw = defaults.string(forKey: GlobalThemeId.storageKey)
        let resolved = GlobalThemeId.resolvedStoredTheme(storedRaw ?? globalThemeIdRaw)

        if let storedIconSetRaw = defaults.string(forKey: AppConfig.StorageKeys.interfaceIconSet),
           AppInterfaceIconSet(rawValue: storedIconSetRaw) == nil {
            let fallbackIconSet = resolved.preferredInterfaceIconSet
            defaults.set(fallbackIconSet.rawValue, forKey: AppConfig.StorageKeys.interfaceIconSet)
            interfaceIconSetRaw = fallbackIconSet.rawValue
        }

        // 仅迁移通透主题过去的 SF Symbols 默认值。其他主题继续使用各自的
        // 默认图标包，也不覆盖用户已经主动选择的其他图标包。
        if !defaults.bool(forKey: AppConfig.StorageKeys.clarityPulseBloomDefaultMigrationV1) {
            let storedIconSet = defaults.string(forKey: AppConfig.StorageKeys.interfaceIconSet)
            if resolved == .clarity,
               storedIconSet == nil || storedIconSet == AppInterfaceIconSet.sfSymbols.rawValue {
                defaults.set(
                    AppInterfaceIconSet.pulseBloom.rawValue,
                    forKey: AppConfig.StorageKeys.interfaceIconSet
                )
            }
            defaults.set(
                true,
                forKey: AppConfig.StorageKeys.clarityPulseBloomDefaultMigrationV1
            )
        }

        let hasStoredInterfaceIconSet = defaults.object(forKey: AppConfig.StorageKeys.interfaceIconSet) != nil

        if storedRaw == nil || resolved.rawValue != globalThemeIdRaw {
            defaults.set(resolved.rawValue, forKey: GlobalThemeId.storageKey)
            globalThemeIdRaw = resolved.rawValue
        }

        AppLogger.info("[ThemeInit] persistedThemeId=\(storedRaw ?? "nil") appDefault=\(GlobalThemeId.appDefault.rawValue) finalThemeId=\(resolved.rawValue) hasStoredIconSet=\(hasStoredInterfaceIconSet)")
        applyGlobalThemeSelection(
            resolved,
            bumpRevision: false,
            bumpApplicationRevision: false,
            applyPreferredIconSet: !hasStoredInterfaceIconSet
        )
        enforceCoverBackgroundPolicyForCurrentTheme()
        // 启动时应用一次主题
        applyTheme()
    }

    private func applyGlobalThemeSelection(
        _ themeId: GlobalThemeId,
        bumpRevision: Bool,
        bumpApplicationRevision: Bool,
        applyPreferredIconSet: Bool
    ) {
        let resolvedThemeId = themeId == .manga ? GlobalThemeId.appDefault : themeId
        let previousThemeId = GlobalThemeManager.shared.currentThemeId

        if globalThemeIdRaw != resolvedThemeId.rawValue {
            globalThemeIdRaw = resolvedThemeId.rawValue
        }
        UserDefaults.standard.set(resolvedThemeId.rawValue, forKey: GlobalThemeId.storageKey)

        GlobalThemeManager.shared.switchTheme(to: resolvedThemeId)
        if previousThemeId == resolvedThemeId, bumpRevision {
            GlobalThemeManager.shared.refreshCurrentThemeTokens()
        }
        let iconSetChanged = applyPreferredIconSet
            ? applyPreferredInterfaceIconSet(for: resolvedThemeId)
            : false
        enforceCoverBackgroundPolicyForCurrentTheme()
        if bumpRevision || bumpApplicationRevision {
            applyTheme()
        }

        if bumpApplicationRevision {
            globalThemeApplicationRevision &+= 1
        }
        if bumpRevision || iconSetChanged {
            globalThemeRevision &+= 1
        }
        AppLogger.info("[ApplyTheme] themeId=\(resolvedThemeId.rawValue) savedThemeId=\(UserDefaults.standard.string(forKey: GlobalThemeId.storageKey) ?? "nil") previousManagerThemeId=\(previousThemeId.rawValue) bumpRevision=\(bumpRevision) appRevision=\(globalThemeApplicationRevision) applyPreferredIconSet=\(applyPreferredIconSet) revision=\(globalThemeRevision)")
    }

    @discardableResult
    private func applyPreferredInterfaceIconSet(for themeId: GlobalThemeId) -> Bool {
        setInterfaceIconSet(themeId.preferredInterfaceIconSet, bumpRevision: false)
    }

    @discardableResult
    private func setInterfaceIconSet(_ iconSet: AppInterfaceIconSet, bumpRevision: Bool) -> Bool {
        let storedRaw = UserDefaults.standard.string(forKey: AppConfig.StorageKeys.interfaceIconSet)
        guard storedRaw != iconSet.rawValue else { return false }

        objectWillChange.send()
        interfaceIconSetRaw = iconSet.rawValue

        if bumpRevision {
            globalThemeRevision &+= 1
        }

        return true
    }

    func enforceCoverBackgroundPolicyForCurrentTheme() {
        guard locksCoverBackgroundSettings else { return }
        if coverBgGlobal { coverBgGlobal = false }
        if coverBgPlaylist { coverBgPlaylist = false }
        if coverBgPlayer { coverBgPlayer = false }
        if globalCoverIsDark { globalCoverIsDark = false }
    }

    func notifyThemeCustomizationChanged() {
        GlobalThemeManager.shared.refreshCurrentThemeTokens()
        globalThemeRevision &+= 1
    }

    func selectAppBrandStyle(_ style: AppBrandStyle) async {
        guard appBrandStyle != style else { return }

        appBrandStyle = style
        await applySelectedAlternateIcon()
    }

    func selectAppBrandAppearance(_ appearance: AppBrandAppearance) async {
        guard appBrandAppearance != appearance else { return }

        appBrandAppearance = appearance
        await applySelectedAlternateIcon()
    }

    private func applySelectedAlternateIcon() async {
        #if os(iOS)
            guard UIApplication.shared.supportsAlternateIcons else {
                AppLogger.info("[AppBrand] 当前环境不支持桌面图标切换，仅更新应用内 Logo")
                return
            }

            let iconName = appBrandStyle.alternateIconName(for: appBrandAppearance)
            guard UIApplication.shared.alternateIconName != iconName else { return }

            do {
                try await setAlternateIconName(iconName)
                AppLogger.info("[AppBrand] 已切换图标风格: \(appBrandStyle.rawValue)-\(appBrandAppearance.rawValue)")
            } catch {
                AppLogger.warning("[AppBrand] 图标切换失败: \(error.localizedDescription)")
            }
        #endif
    }

    #if os(iOS)
        private func setAlternateIconName(_ iconName: String?) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                UIApplication.shared.setAlternateIconName(iconName) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    #endif
}
