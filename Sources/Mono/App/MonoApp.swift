import SwiftUI
import HiconIcons
import UserNotifications
import FFmpegSwiftSDK

// MARK: - AppDelegate（控制设备方向 + 场景配置）

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.allowedOrientations
    }
    
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        // 指派自定义 scene delegate 以接收 Quick Actions / shortcutItem 回调
        config.delegateClass = MonoSceneDelegate.self
        return config
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // 不执行 UserDefaults、数据库、音频管线或云端 I/O。播放状态已在
        // didEnterBackground 保存；终止路径必须立即返回，避免 process-exit watchdog。
    }
}

@main
@MainActor
struct MonoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var styleManager = StyleManager.shared
    @StateObject private var settings = SettingsManager.shared
    
    init() {
        if ProcessInfo.processInfo.environment["MONO_UNIT_TESTS"] == "1" { return }
        PreferenceDataArchive.shared.migrateLegacyRecords()
        FFmpegDiagnosticLog.setHandler { event in
            switch event.level {
            case .debug:
                AppLogger.debug(
                    event.message,
                    category: .audio,
                    event: "ffmpeg-sdk",
                    file: event.file,
                    line: event.line,
                    function: event.function
                )
            case .info:
                AppLogger.info(
                    event.message,
                    category: .audio,
                    event: "ffmpeg-sdk",
                    file: event.file,
                    line: event.line,
                    function: event.function
                )
            case .warning:
                AppLogger.warning(
                    event.message,
                    category: .audio,
                    event: "ffmpeg-sdk",
                    file: event.file,
                    line: event.line,
                    function: event.function
                )
            case .error:
                AppLogger.error(
                    event.message,
                    category: .audio,
                    event: "ffmpeg-sdk",
                    file: event.file,
                    line: event.line,
                    function: event.function
                )
            case .success:
                AppLogger.success(
                    event.message,
                    category: .audio,
                    event: "ffmpeg-sdk",
                    file: event.file,
                    line: event.line,
                    function: event.function
                )
            }
        }

        // 检测是否为全新安装（删除 App 后 UserDefaults 会被清除，Keychain 不会）
        // 如果是重新安装，清除上次残留的 Keychain 数据
        Self.cleanupKeychainIfNeeded()

        // 所有可重建内存缓存统一由 MonoMemory Engine 分配预算并响应
        // 内存警告、热状态和前后台切换，避免各模块重复监听和无上限增长。
        MonoMemoryEngine.shared.start()
        // CPU/GPU 统一预算：实际 CPU 采样 + GPU 工作量治理，集中控制
        // 帧率、渲染分辨率、粒子密度、着色器和后台计算并发。
        MonoComputeEngine.shared.start()
        ThemeColorCustomization.installMemoryManagement()
        
        _ = EQManager.shared
        _ = AIEqualizerAgent.shared
        _ = MonoNextSuiteManager.shared
        _ = MonoSessionManager.shared
        _ = CustomFontManager.shared
        
        // iOS 26: 系统 TabView 自动使用 Liquid Glass 浮动标签栏，不再需要自定义外观
        
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.shadowColor = .clear
        navBarAppearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        
        UIPageControl.appearance().backgroundColor = .clear
        UIPageControl.appearance().pageIndicatorTintColor = .clear
        UIPageControl.appearance().currentPageIndicatorTintColor = .clear
        
        UIScrollView.appearance().backgroundColor = .clear
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        
        // List 内部的 UITableView / UICollectionView 也隐藏滚动条
        UITableView.appearance().showsVerticalScrollIndicator = false
        UITableView.appearance().showsHorizontalScrollIndicator = false
        UICollectionView.appearance().showsVerticalScrollIndicator = false
        UICollectionView.appearance().showsHorizontalScrollIndicator = false
        
        UICollectionView.appearance().backgroundColor = .clear
    }
    
    /// App 根层只跟随用户选择的深浅色模式。
    /// 封面亮度只用于播放器/背景内部的前景色判断，不能反向驱动整棵视图树切换
    /// `.preferredColorScheme`，否则封面取色波动时会导致页面背景在深浅色之间闪烁。
    private var effectiveColorScheme: ColorScheme? {
        return settings.preferredColorScheme
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["MONO_UNIT_TESTS"] == "1" {
                Color.clear
            } else {
            DatabaseRootView {
            ContentView()
                .compatFontDesign(.rounded)
                .preferredColorScheme(effectiveColorScheme)
                .onAppear {
                    guard DatabaseManager.shared.store.isAvailable else { return }
                    CrashDiagnosticsStore.shared.start()
                    AppFrameRate.lockConnectedScenesToPreferredFrameRate(reason: "app root appear")
                    if UIApplication.shared.applicationState == .active {
                        MonoNextSuiteManager.shared.activateHeadTrackingRuntimeIfNeeded()
                        AirPodsExperienceManager.shared.activateRuntimeIfNeeded()
                    }

                    // 冷启动本地预加载必须先于 Token、登录态和任何在线服务判断。
                    // 它只读取本机缓存，不依赖账号状态。
                    GlobalRefreshManager.shared.triggerAppLaunchPreload()

                    let hasStoredToken = OnlineAccessManager.shared.hasStoredToken

                    AlertWindow.shared.setup()
                    LocalNotificationService.shared.setup()

                    // 多线路：应用上次线路并启动健康探测/繁忙分流
                    ServerLineManager.shared.start()

                    // 双重风控前置探测入口
                    RiskControlManager.shared.performRiskCheck()
                    
                    if hasStoredToken {
                        OnlineAccessManager.shared.refreshOnLaunch(showInvalidAlert: false)
                        GlobalRefreshManager.shared.triggerAuthenticatedAppLaunchRefresh()
                        Task { @MainActor in
                            await AIProviderConfigurationStore.shared.refreshRemoteConfigurationIfNeeded(force: true)
                        }
                        Task {
                            _ = await AppAgentConfigurationStore.shared.configuration(forceRefresh: true)
                        }
                    } else {
                        AppLogger.info("未配置 Token，跳过在线启动刷新")
                    }
                    
                    Task { @MainActor in
                        MonoQuickActionsManager.refreshAsync()
                    }
                    // 冷启动只恢复 UI 状态（歌曲信息+进度），不自动加载播放
                    // 用户点击播放按钮时 togglePlayPause 会触发 restorePlaybackSessionIfNeeded
                    
                    Task { @MainActor in
                        await OptimizedCacheManager.shared.cleanupExpiredData()
                    }

                    guard hasStoredToken else { return }

                    // 检测管理员 qcm 登录状态（登录有效期约 3 天）
                    KCMDailyMembershipEngine.shared.checkIfNeeded()
                    Task {
                        do {
                            let status = try await APIService.shared.qqClient.authStatus()
                            await MainActor.run {
                                UserDefaults.standard.set(status.loggedIn, forKey: AppConfig.StorageKeys.qqMusicLoggedIn)
                                if !status.loggedIn {
                                    AppLogger.warning("[QQMusic] 管理员登录已过期")
                                    LocalNotificationService.shared.sendCookieExpiredNotification()
                                }
                            }
                        } catch {
                            AppLogger.warning("[QQMusic] 管理员登录状态检测失败: \(error.localizedDescription)")
                        }
                    }

                    // 检测用户 qcm 登录状态
                    Task { @MainActor in
                        let session = QQUserSession.shared
                        if session.isLoggedIn || session.hasStoredCredentials {
                            await session.refresh()
                            if !session.isLoggedIn {
                                AppLogger.warning("[QQMusic] 用户登录已过期")
                                AlertManager.shared.show(
                                    title: String(localized: "qq_session_expired_title"),
                                    message: String(localized: "qq_session_expired_message"),
                                    primaryButtonTitle: String(localized: "common_ok"),
                                    primaryAction: {}
                                )
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    guard DatabaseManager.shared.store.isAvailable else { return }
                    AppFrameRate.lockConnectedScenesToPreferredFrameRate(reason: "application did become active")
                    MonoNextSuiteManager.shared.activateHeadTrackingRuntimeIfNeeded()
                    AirPodsExperienceManager.shared.activateRuntimeIfNeeded()

                    ServerLineManager.shared.kickRefresh(trigger: .foreground)

                    if settings.themeMode == "system" {
                        DispatchQueue.main.async {
                            settings.refreshSystemThemeIfNeeded()
                        }
                    }
                    if OnlineAccessManager.shared.hasStoredToken {
                        OnlineAccessManager.shared.refreshOnLaunch(showInvalidAlert: true)
                        Task { @MainActor in
                            await AIProviderConfigurationStore.shared.refreshRemoteConfigurationIfNeeded()
                        }
                        Task {
                            _ = await AppAgentConfigurationStore.shared.configuration()
                        }
                    }
                    KCMDailyMembershipEngine.shared.checkIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // 暂时失焦不等于进入后台，只保存轻量播放位置；完整队列由
                    // didEnterBackground 的受保护事务统一落盘，避免连续写两份快照。
                    PlayerManager.shared.savePlaybackProgressIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    Self.persistStateForSuspension()
                }
            }
            }
        }
    }
    
    /// 进入后台时的持久化必须在系统挂起前彻底落盘：
    /// 挂起瞬间若仍持有 SQLite/文件锁（异步写盘队列未排空），
    /// RunningBoard 会以 0xdead10cc 直接杀掉进程。这里用后台任务
    /// 抵住挂起窗口，等档案/磁盘缓存队列排空后再允许挂起。
    private static func persistStateForSuspension() {
        final class TaskHandle: @unchecked Sendable {
            var id: UIBackgroundTaskIdentifier = .invalid
        }
        guard DatabaseManager.shared.store.isAvailable else { return }
        let application = UIApplication.shared
        let handle = TaskHandle()
        handle.id = application.beginBackgroundTask(withName: "Mono.PersistOnBackground") {
            DispatchQueue.main.async {
                guard handle.id != .invalid else { return }
                application.endBackgroundTask(handle.id)
                handle.id = .invalid
            }
        }

        // 最终快照必须同步完成；否则“立即保存”只会把写入排进串行队列，
        // 后台任务可能在真正写盘前就结束。
        PlayerManager.shared.saveStateImmediately(synchronously: true)
        DatabaseManager.shared.save()

        guard handle.id != .invalid else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            PlaybackSessionArchive.shared.waitForPendingWrites()
            PreferenceDataArchive.shared.waitForPendingWrites()
            AIEqualizerLearningStore.waitForPendingWrites()
            AIEqualizerProposalCacheStore.waitForPendingTrainingSampleWrites()
            CacheManager.shared.waitForPendingDiskWrites()
            DispatchQueue.main.async {
                guard handle.id != .invalid else { return }
                application.endBackgroundTask(handle.id)
                handle.id = .invalid
            }
        }
    }

    /// 检测 App 是否为重新安装，若是则清除上次残留的 Keychain 数据
    private static func cleanupKeychainIfNeeded() {
        let hasLaunchedKey = "mono_has_launched_before"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            // 根据要求，永久不删残留 Keychain 数据以保留设备 UDID 等标识
            // KeychainHelper.deleteAll()
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            #if DEBUG
            print("[App] 检测到全新安装，保留原有 Keychain 数据")
            #endif
        }
    }
    
}
