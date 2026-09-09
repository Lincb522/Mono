import Combine
import SwiftUI

@MainActor
struct PlatformAccountManagementView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var userProfile = HomeViewModel.shared.userProfile
    @ObservedObject private var qcmSession = QQUserSession.shared
    @ObservedObject private var appleMusicService = AppleMusicService.shared
    @ObservedObject private var loginIdentity = LoginIdentityManager.shared
    @State private var refreshedNCMProfile: UserProfile?
    @State private var refreshedNCMSession: APIService.NCMSessionSnapshot?
    @State private var kcmProfile: KCMAccountProfile?
    @State private var kcmProfileSession: KCMMusicService.SessionSnapshot?
    @State private var isRefreshing = false
    @State private var refreshRequestID: UUID?

    var body: some View {
        ZStack {
            ThemedSettingsBackground()

            ScrollView {
                VStack(spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "platform_account_management"),
                        eyebrow: String(localized: "settings_eyebrow_accounts"),
                        icon: .personCircle,
                        signalModule: .accounts
                    )

                    SettingsSection(title: String(localized: "login_identity_section")) {
                        ForEach(
                            Array(LoginIdentityManager.supportedSources.enumerated()),
                            id: \.element.rawValue
                        ) { index, source in
                            identitySelectionControl(source)

                            if index < LoginIdentityManager.supportedSources.count - 1 {
                                rowDivider
                            }
                        }
                    }

                    SettingsSection(title: String(localized: "platform_account_music_services")) {
                        NavigationLink {
                            NCMAccountView()
                        } label: {
                            platformRow(
                                source: .netease,
                                platformName: "NCM",
                                displayName: ncmProfile?.nickname ?? "NCM",
                                detail: ncmMembershipText,
                                isConnected: isNCMLoggedIn,
                                avatarURL: normalizedNCMAvatarURL
                            )
                        }
                        .buttonStyle(.plain)

                        rowDivider

                        NavigationLink {
                            QCMAccountView()
                        } label: {
                            platformRow(
                                source: .qqmusic,
                                platformName: "QCM",
                                displayName: qcmSession.nickname ?? "QCM",
                                detail: qcmSession.isVIP ? "VIP" : nil,
                                isConnected: qcmSession.isLoggedIn,
                                avatarURL: qcmSession.avatarURL
                            )
                        }
                        .buttonStyle(.plain)

                        rowDivider

                        NavigationLink {
                            KCMAccountView()
                        } label: {
                            platformRow(
                                source: .kugou,
                                platformName: "KCM",
                                displayName: currentKCMProfile?.nickname ?? "KCM",
                                detail: currentKCMProfile?.membershipLevel.displayName,
                                isConnected: isKCMLoggedIn,
                                avatarURL: currentKCMProfile?.avatarURL
                            )
                        }
                        .buttonStyle(.plain)

                        rowDivider

                        NavigationLink {
                            AppleMusicAccountView()
                        } label: {
                            platformRow(
                                source: .appleMusic,
                                platformName: "Apple Music",
                                displayName: "Apple Music",
                                detail: nil,
                                isConnected: appleMusicService.isAuthorized,
                                avatarURL: nil,
                                connectedText: String(localized: "platform_account_authorized"),
                                disconnectedText: String(localized: "platform_account_unauthorized")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    FloatingBarBottomSpacer()
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                .padding(.bottom, 44)
                .iPadContentWidth(SettingsPageLayout.contentWidth)
            }
            .scrollIndicators(.hidden)
            .refreshable { await refreshAccounts() }
        }
        .asideSettingsDetailChrome()
        .task { await refreshAccounts() }
        .onReceive(HomeViewModel.shared.$userProfile.removeDuplicates()) {
            userProfile = $0
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didLogin)
                .merge(with: NotificationCenter.default.publisher(for: .didLogout))
                .receive(on: DispatchQueue.main)
        ) { _ in
            refreshedNCMProfile = nil
            refreshedNCMSession = nil
            restartAccountRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .kcmSessionDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            kcmProfile = nil
            kcmProfileSession = nil
            restartAccountRefresh()
        }
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.4)
            .padding(.leading, 72)
    }

    private var normalizedNCMAvatarURL: URL? {
        guard var value = ncmProfile?.avatarUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if value.lowercased().hasPrefix("http://") {
            value = "https://" + String(value.dropFirst("http://".count))
        }
        return URL(string: value)
    }

    private var ncmMembershipText: String? {
        guard let vipType = ncmProfile?.vipType, vipType > 0 else { return nil }
        return "VIP"
    }

    private var ncmProfile: UserProfile? {
        let apiService = APIService.shared
        let session = apiService.ncmSessionSnapshot
        guard isNCMLoggedIn,
              apiService.isLoggedIn,
              let userID = session.userID else { return nil }
        if refreshedNCMSession == session,
           refreshedNCMProfile?.userId == userID {
            return refreshedNCMProfile
        }
        return userProfile.flatMap {
            $0.userId == userID ? $0 : nil
        }
    }

    private var currentKCMProfile: KCMAccountProfile? {
        let service = KCMMusicService.shared
        let session = service.sessionSnapshot
        guard session.isAuthenticated,
              let userID = session.userID,
              kcmProfileSession == session,
              kcmProfile?.userID == userID else { return nil }
        return kcmProfile
    }

    private var isKCMLoggedIn: Bool {
        KCMMusicService.shared.sessionSnapshot.isAuthenticated
    }

    private var isNCMLoggedIn: Bool {
        loginIdentity.isLoggedIn(to: .netease)
    }

    @ViewBuilder
    private func identitySelectionControl(_ source: MusicSource) -> some View {
        if loginIdentity.isLoggedIn(to: source) {
            Button {
                guard loginIdentity.select(source) else { return }
                HapticManager.shared.selection()
            } label: {
                identitySelectionRow(source, isConnected: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PlatformLoginView(initialPlatform: loginPlatform(for: source))
            } label: {
                identitySelectionRow(source, isConnected: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func identitySelectionRow(_ source: MusicSource, isConnected: Bool) -> some View {
        let isActive = isConnected && loginIdentity.activeSource == source
        return HStack(spacing: 13) {
            PlatformBadgeLabel(text: source.shortName, source: source, fontSize: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.monoTextPrimary)

                Text(
                    LocalizedStringKey(
                        isActive
                            ? "login_identity_active"
                            : (isConnected ? "login_identity_select" : "login_identity_sign_in")
                    )
                )
                .font(.caption)
                .foregroundStyle(Color.monoTextSecondary)
            }

            Spacer(minLength: 8)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(source.themedBadgeColor)
                    .accessibilityHidden(true)
            } else {
                MonoIcon(icon: .chevronRight, size: 12, color: .monoTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func loginPlatform(for source: MusicSource) -> PlatformLoginSource {
        switch source {
        case .netease: return .ncm
        case .qqmusic: return .qcm
        case .kugou: return .kcm
        case .qishui, .appleMusic, .local: return .ncm
        }
    }

    private func platformRow(
        source: MusicSource,
        platformName: String,
        displayName: String,
        detail: String?,
        isConnected: Bool,
        avatarURL: URL?,
        connectedText: String = String(localized: "platform_account_connected"),
        disconnectedText: String = String(localized: "platform_account_disconnected")
    ) -> some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 0) {
            HStack(spacing: 13) {
                platformAvatar(source: source, avatarURL: avatarURL)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.monoTextPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        detail.map { "\(platformName) · \($0)" }
                            ?? platformName
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.monoTextSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    platformConnectionLabel(
                        source: source,
                        isConnected: isConnected,
                        connectedText: connectedText,
                        disconnectedText: disconnectedText
                    )
                    MonoIcon(icon: .chevronRight, size: 12, color: .monoTextSecondary)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    platformConnectionLabel(
                        source: source,
                        isConnected: isConnected,
                        connectedText: connectedText,
                        disconnectedText: disconnectedText
                    )
                    Spacer(minLength: 8)
                    MonoIcon(icon: .chevronRight, size: 12, color: .monoTextSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func platformConnectionLabel(
        source: MusicSource,
        isConnected: Bool,
        connectedText: String,
        disconnectedText: String
    ) -> some View {
        Text(isConnected ? connectedText : disconnectedText)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(
                isConnected
                    ? ThemeColorCustomization.visibleTintColor(
                        source.themedBadgeColor,
                        darkFallback: Color.monoTextPrimary
                    )
                    : Color.monoTextSecondary
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private func platformAvatar(source: MusicSource, avatarURL: URL?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            CachedAsyncImage(url: avatarURL) {
                Circle()
                    .fill(source.themedBadgeColor.opacity(0.12))
                    .overlay {
                        PlatformBadgeLabel(text: source.shortName, source: source, fontSize: 9)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 46, height: 46)
            .clipShape(Circle())

            if avatarURL != nil {
                PlatformBadgeLabel(text: source.shortName, source: source, fontSize: 7)
                    .padding(2)
                    .background(Color.monoBackground)
                    .clipShape(Capsule())
                    .offset(x: 3, y: 2)
            }
        }
        .frame(width: 49, height: 48)
    }

    private func refreshAccounts() async {
        let requestID = UUID()
        refreshRequestID = requestID
        let ncmSession = APIService.shared.ncmSessionSnapshot
        let kcmSession = KCMMusicService.shared.sessionSnapshot
        isRefreshing = true
        defer {
            if refreshRequestID == requestID {
                isRefreshing = false
            }
        }
        appleMusicService.refreshAuthorizationStatus()

        async let ncmRefresh = fetchNCMProfile(ifCurrentSession: ncmSession)
        async let identityRefresh: Void = loginIdentity.refreshAvailableIdentities()

        let nextNCMProfile = await ncmRefresh
        await identityRefresh
        guard !Task.isCancelled, refreshRequestID == requestID else { return }

        let apiService = APIService.shared
        if apiService.isCurrentNCMSession(ncmSession),
           nextNCMProfile?.userId == ncmSession.userID {
            refreshedNCMProfile = nextNCMProfile
            refreshedNCMSession = ncmSession
        } else {
            refreshedNCMProfile = nil
            refreshedNCMSession = nil
        }

        let service = KCMMusicService.shared
        if service.isCurrentSession(kcmSession),
           loginIdentity.kcmProfile?.userID == kcmSession.userID {
            kcmProfile = loginIdentity.kcmProfile
            kcmProfileSession = kcmSession
        } else {
            kcmProfile = nil
            kcmProfileSession = nil
        }
    }

    private func fetchNCMProfile(
        ifCurrentSession session: APIService.NCMSessionSnapshot
    ) async -> UserProfile? {
        let apiService = APIService.shared
        guard isNCMLoggedIn,
              apiService.isLoggedIn,
              let userID = session.userID,
              apiService.isCurrentNCMSession(session) else { return nil }

        let localProfile = userProfile.flatMap {
            $0.userId == userID ? $0 : nil
        }
        do {
            let loginStatus = try await UnsafeSendableBox(apiService.fetchLoginStatus()).value.async()
            guard apiService.isCurrentNCMSession(session) else { return nil }
            guard let profile = loginStatus.data.profile,
                  profile.userId == userID else { return localProfile }

            let detail = try? await UnsafeSendableBox(
                apiService.fetchUserDetail(uid: userID)
            ).value.async()
            guard apiService.isCurrentNCMSession(session) else { return nil }
            if let detailProfile = detail?.profile, detailProfile.userId == userID {
                return detailProfile
            }
            return profile
        } catch {
            guard apiService.isCurrentNCMSession(session) else { return nil }
            AppLogger.warning("NCM 账号信息获取失败，使用本地资料: \(error)")
            return localProfile
        }
    }

    private func restartAccountRefresh() {
        refreshRequestID = nil
        isRefreshing = false
        Task { @MainActor in
            await refreshAccounts()
        }
    }
}
