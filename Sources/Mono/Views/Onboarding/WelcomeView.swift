import ShibaWelcome
import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsManager.shared

    @Binding var isPresented: Bool
    let onForceEnter: (WelcomeDiagnosticsContext) -> Void
    @AppStorage("isLoggedIn") private var isAppLoggedIn = false

    @State private var animationCompleted = false
    @State private var isDismissing = false
    @State private var showsForceEntryButton = false
    @State private var preloadTask: Task<Void, Never>?
    @State private var forceEntryTask: Task<Void, Never>?
    @State private var welcomeStartedAt = Date()
    @State private var preloadCompleted = false
    @State private var isWaitingForInitialHomeContent = false
    @State private var initialContentRetryCount = 0

    private enum Timing {
        static let preloadStartDelay: TimeInterval = 0.08
        static let staticPoseDuration: TimeInterval = 1.2
        static let forceEntryDelay: TimeInterval = 7.0
        static let initialContentWaitLimit: TimeInterval = 30.0
        static let initialContentPollInterval: TimeInterval = 0.12
        static let initialContentRetryInterval: TimeInterval = 2.0
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max(120, min(300, geometry.size.width - 48, geometry.size.height - 156))

            ScrollView {
                VStack(spacing: 24) {
                    ShibaMascotView(action: .welcome) {
                        animationCompleted = true
                    }
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)

                    MonoWordmarkImage(height: 32)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsForceEntryButton, !isDismissing {
                Button(action: forceEnter) {
                    Text(LocalizedStringKey("welcome_force_enter"))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(forceEntryForeground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 8)
                        .background(forceEntryBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .background(welcomeBaseColor.ignoresSafeArea())
        .opacity(isDismissing ? 0 : 1)
        .onAppear(perform: startWelcome)
        .task(id: animationCompleted) {
            guard animationCompleted else { return }
            do {
                if usesStaticPose {
                    try await sleep(seconds: Timing.staticPoseDuration)
                }
                await waitForInitialHomeContentIfNeeded()
                try Task.checkCancellation()
                guard isPresented else { return }
                await dismissWelcome()
            } catch {
                return
            }
        }
        .onDisappear {
            preloadTask?.cancel()
            forceEntryTask?.cancel()
        }
    }

    private var usesStaticPose: Bool {
        if #available(iOS 17.0, *) { return reduceMotion }
        return true
    }

    private var welcomeBaseColor: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.125, blue: 0.106)
            : Color(red: 1, green: 0.969, blue: 0.914)
    }

    private var forceEntryBackground: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.769, blue: 0.408)
            : Color(red: 0.169, green: 0.141, blue: 0.110)
    }

    private var forceEntryForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private func startWelcome() {
        welcomeStartedAt = Date()
        let isLoggedIn = isAppLoggedIn
        preloadTask = Task(priority: .utility) { @MainActor in
            do {
                try await sleep(seconds: Timing.preloadStartDelay)
                try Task.checkCancellation()
                await loadDataInBackground(isLoggedIn: isLoggedIn)
            } catch {
                return
            }
        }

        forceEntryTask = Task { @MainActor in
            do {
                try await sleep(seconds: Timing.forceEntryDelay)
                guard isPresented, !isDismissing else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                    showsForceEntryButton = true
                }
            } catch {
                return
            }
        }
    }

    private func loadDataInBackground(isLoggedIn: Bool) async {
        defer { preloadCompleted = true }

        await MainActor.run {
            _ = HomeViewModel.shared
            _ = PodcastViewModel.shared
        }

        await OptimizedCacheManager.shared.quickPreload()
        await MainActor.run {
            HomeViewModel.shared.reloadHomeCacheIfUseful(reason: "welcome quick preload")
        }

        guard OnlineAccessManager.shared.hasStoredToken else { return }

        if isLoggedIn {
            do {
                _ = try await APIService.shared.fetchLoginStatus().async()
            } catch {
                AppLogger.warning("登录状态检查失败: \(error)")
            }
        }

        let refreshPlan = await MainActor.run {
            (
                home: GlobalRefreshManager.shared.checkDailyRefreshNeeded(for: .home),
                podcast: GlobalRefreshManager.shared.checkDailyRefreshNeeded(for: .podcast)
            )
        }
        await MainActor.run {
            let shouldLoadHome = refreshPlan.home || !HomeViewModel.shared.hasDisplayableHomeContent
            if shouldLoadHome {
                HomeViewModel.shared.fetchData(forceDaily: refreshPlan.home || !HomeViewModel.shared.hasDisplayableHomeContent)
            }
            PodcastViewModel.shared.preloadIfNeeded(
                forceDaily: refreshPlan.podcast,
                reason: "welcome preload"
            )
            GlobalRefreshManager.shared.refreshLibraryPublisher.send(false)
            GlobalRefreshManager.shared.refreshProfilePublisher.send(false)
        }
    }

    private func waitForInitialHomeContentIfNeeded() async {
        let shouldWait = await MainActor.run {
            OnlineAccessManager.shared.hasStoredToken
        }
        guard shouldWait else { return }

        isWaitingForInitialHomeContent = true
        defer { isWaitingForInitialHomeContent = false }

        let waitStartedAt = Date()
        var lastRetry = Date.distantPast
        while true {
            if Task.isCancelled { return }

            if Date().timeIntervalSince(waitStartedAt) >= Timing.initialContentWaitLimit {
                AppLogger.warning(
                    "[Welcome] Initial home content wait timed out",
                    category: .interface,
                    event: "welcome_content_wait_timeout",
                    context: welcomeDiagnosticContext().logContext
                )
                return
            }

            let isReady = await MainActor.run {
                HomeViewModel.shared.reloadHomeCacheIfUseful(reason: "welcome before dismiss")
                return HomeViewModel.shared.hasDisplayableHomeContent
            }
            if isReady { return }

            if Date().timeIntervalSince(lastRetry) >= Timing.initialContentRetryInterval {
                lastRetry = Date()
                initialContentRetryCount += 1
                await MainActor.run {
                    if HomeViewModel.shared.isLoading {
                        HomeViewModel.shared.ensureHomeDataLoaded(reason: "welcome waiting for initial content")
                    } else {
                        HomeViewModel.shared.fetchData(forceDaily: true)
                    }
                }
            }

            try? await sleep(seconds: Timing.initialContentPollInterval)
        }
    }

    private func dismissWelcome() async {
        guard !isDismissing else { return }
        forceEntryTask?.cancel()
        showsForceEntryButton = false

        let duration = reduceMotion ? 0.18 : 0.42
        withAnimation(.easeInOut(duration: duration)) {
            isDismissing = true
        }
        do {
            try await sleep(seconds: duration)
            isPresented = false
        } catch {
            return
        }
    }

    private func forceEnter() {
        guard !isDismissing else { return }

        let context = welcomeDiagnosticContext()
        AppLogger.warning(
            "[Welcome] Force entry requested",
            category: .interface,
            event: "welcome_force_entry",
            context: context.logContext
        )
        preloadTask?.cancel()
        forceEntryTask?.cancel()
        onForceEnter(context)
    }

    private func welcomeDiagnosticContext() -> WelcomeDiagnosticsContext {
        WelcomeDiagnosticsContext(
            capturedAt: Date(),
            elapsedSeconds: Date().timeIntervalSince(welcomeStartedAt),
            themeID: settings.globalThemeId.rawValue,
            isLoggedIn: isAppLoggedIn,
            hasStoredToken: OnlineAccessManager.shared.hasStoredToken,
            preloadCompleted: preloadCompleted,
            isWaitingForInitialHomeContent: isWaitingForInitialHomeContent,
            initialContentRetryCount: initialContentRetryCount,
            homeIsLoading: HomeViewModel.shared.isLoading,
            homeHasDisplayableContent: HomeViewModel.shared.hasDisplayableHomeContent,
            reduceMotionEnabled: reduceMotion
        )
    }

    private func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
