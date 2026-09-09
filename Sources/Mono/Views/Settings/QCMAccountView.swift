import SwiftUI
import QQMusicKit

struct QCMAccountView: View {
    @ObservedObject private var userSession = QQUserSession.shared
    @State private var isChecking = false
    @State private var refreshRequestID: UUID?
    @State private var showLogoutConfirmation = false

    var body: some View {
        List {
            if SignalStyle.isActive {
                SignalNestedPageHeader(
                    title: "QCM 账号",
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
                    PlatformLoginView(initialPlatform: .qcm)
                } label: {
                    Label(userSession.isLoggedIn ? "重新登录" : "扫码登录", systemImage: "qrcode")
                }

                if userSession.isLoggedIn {
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
        .task { await refreshAccount() }
        .confirmationDialog("退出 QCM 登录？", isPresented: $showLogoutConfirmation) {
            Button("退出登录", role: .destructive, action: logout)
            Button("取消", role: .cancel) {}
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: userSession.avatarURL) {
                avatarPlaceholder
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                PlatformBadgeLabel(text: "QCM", source: .qqmusic, fontSize: 7)
                    .offset(x: 4, y: 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(userSession.nickname ?? "QCM")
                    .font(SignalStyle.isActive ? SignalStyle.bodyFont(14, weight: .semibold) : .system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)

                Text(userSession.isLoggedIn ? "已登录" : "未登录")
                    .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
            }

            Spacer()

            if isChecking {
                ProgressView()
            } else if userSession.isVIP {
                Text("VIP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(MusicSource.qqmusic.themedBadgeColor)
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

    @MainActor
    private func refreshAccount() async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        refreshRequestID = requestID
        isChecking = true
        defer {
            if refreshRequestID == requestID {
                isChecking = false
            }
        }

        await userSession.refresh()
    }

    private func logout() {
        userSession.onLogout()
        LoginIdentityManager.shared.accountDidLogOut(.qqmusic)
    }
}

typealias QQAccountView = QCMAccountView
