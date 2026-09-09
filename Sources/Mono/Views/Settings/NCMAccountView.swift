import Combine
import SwiftUI

struct NCMAccountView: View {
    @State private var userProfile = HomeViewModel.shared.userProfile
    @ObservedObject private var loginIdentity = LoginIdentityManager.shared
    @State private var showLogoutConfirmation = false

    private var isLoggedIn: Bool {
        loginIdentity.isLoggedIn(to: .netease)
    }

    var body: some View {
        List {
            if SignalStyle.isActive {
                SignalNestedPageHeader(
                    title: "NCM 账号",
                    eyebrow: "ACCOUNT NODE",
                    icon: .personCircle,
                    module: .accounts
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("账号") {
                accountRow
            }
            .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)

            Section {
                NavigationLink {
                    PlatformLoginView(initialPlatform: .ncm)
                } label: {
                    Label(
                        isLoggedIn
                            ? String(localized: "ncm_account_relogin")
                            : String(localized: "ncm_account_login"),
                        systemImage: "person.crop.circle"
                    )
                }

                if isLoggedIn {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                }
            }
            .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)
        }
        .scrollContentBackground(.hidden)
        .claritySettingsListStyle()
        .background(ThemedPageBackground())
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton()
        .onReceive(HomeViewModel.shared.$userProfile.removeDuplicates()) {
            userProfile = $0
        }
        .confirmationDialog("退出 NCM 登录？", isPresented: $showLogoutConfirmation) {
            Button("退出登录", role: .destructive, action: logout)
            Button("取消", role: .cancel) {}
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            PlatformBadgeLabel(text: MusicSource.netease.shortName, source: .netease, fontSize: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(userProfile?.nickname ?? "NCM")
                    .font(SignalStyle.isActive ? SignalStyle.bodyFont(14, weight: .semibold) : .system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)

                Text(isLoggedIn ? "已登录" : "未登录")
                    .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
            }

            Spacer()

            if let avatar = userProfile?.avatarUrl.flatMap(URL.init(string:)) {
                CachedAsyncImage(url: avatar) {
                    avatarPlaceholder
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.monoSeparator)
            .overlay {
                MonoIcon(icon: .personCircle, size: 20, color: .monoTextSecondary)
            }
    }

    private func logout() {
        let publisher = UnsafeSendableBox(APIService.shared.logout())
        LoginIdentityManager.shared.accountDidLogOut(.netease)
        Task {
            do {
                _ = try await publisher.value.async()
            } catch {
                AppLogger.warning("NCM 远端退出失败，本地已退出: \(error)")
            }
        }
    }
}
