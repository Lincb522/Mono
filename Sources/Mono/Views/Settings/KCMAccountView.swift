import Combine
import SwiftUI

@MainActor
struct KCMAccountView: View {
    @State private var isLoggedIn = KCMMusicService.shared.isAuthenticated
    @State private var profile: KCMAccountProfile?
    @State private var isLoadingProfile = false
    @State private var isProcessingVIP = false
    @State private var statusMessage: String?
    @State private var showLogoutConfirmation = false
    @State private var profileRequestID: UUID?
    @State private var membershipRequestID: UUID?

    var body: some View {
        List {
            if SignalStyle.isActive {
                SignalNestedPageHeader(
                    title: "KCM 账号",
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
                    PlatformLoginView(initialPlatform: .kcm)
                } label: {
                    Label(isLoggedIn ? "重新登录" : "扫码登录", systemImage: "qrcode")
                }
            }
            .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)

            if isLoggedIn {
                Section("概念版会员") {
                    membershipRow(title: "当前状态", value: membershipDisplayName)

                    if let expiration = profile?.membershipExpiration {
                        membershipRow(title: "有效期至", value: expiration.formatted(date: .abbreviated, time: .shortened))
                    }

                    Button {
                        claimDailyVIP()
                    } label: {
                        HStack {
                            Label {
                                Text("领取今日会员")
                            } icon: {
                                MonoSemanticIcon(semantic: .gift, fallback: .sparkle)
                            }
                            Spacer()
                            if isProcessingVIP {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isProcessingVIP)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.monoTextSecondary)
                    }
                }
                .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)

                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                }
                .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)
            }
        }
        .scrollContentBackground(.hidden)
        .claritySettingsListStyle()
        .background(ThemedPageBackground())
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton()
        .task { await refreshAccount() }
        .refreshable { await refreshAccount() }
        .confirmationDialog("退出 KCM 登录？", isPresented: $showLogoutConfirmation) {
            Button("退出登录", role: .destructive, action: logout)
            Button("取消", role: .cancel) {}
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .kcmSessionDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            handleSessionDidChange()
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: profile?.avatarURL) {
                avatarPlaceholder
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                PlatformBadgeLabel(text: "KCM", source: .kugou, fontSize: 7)
                    .offset(x: 4, y: 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.nickname ?? "KCM")
                    .font(SignalStyle.isActive ? SignalStyle.bodyFont(14, weight: .semibold) : .system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)
                    .lineLimit(1)

                if let userID = profile?.userID ?? KCMMusicService.shared.currentUserID {
                    Text("ID \(userID)")
                        .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
                } else {
                    Text(isLoggedIn ? "已登录" : "未登录")
                        .font(SignalStyle.isActive ? SignalStyle.labelFont(10, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
                }
            }

            Spacer(minLength: 8)

            if isLoadingProfile {
                ProgressView()
            } else if isLoggedIn {
                Text(membershipDisplayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        profile?.membershipLevel == KCMMembershipLevel.none
                            ? Color.monoTextSecondary
                            : MusicSource.kugou.themedBadgeColor
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(MusicSource.kugou.themedBadgeColor.opacity(0.12))
            .overlay {
                MonoIcon(icon: .personCircle, size: 20, color: .monoTextSecondary)
            }
    }

    private var membershipDisplayName: String {
        guard let profile else { return isLoggedIn ? "查询中" : "无会员" }
        switch profile.membershipLevel {
        case .none:
            return "无会员"
        case .full:
            return "正式会员"
        case .trial:
            return profile.conceptProductType == "svip" ? "畅听会员" : "体验会员"
        }
    }

    private func membershipRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.monoTextPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.monoTextSecondary)
        }
    }

    private func refreshAccount(
        ifCurrentSession expectedSession: KCMMusicService.SessionSnapshot? = nil
    ) async {
        let service = KCMMusicService.shared
        let requestedSession = expectedSession ?? service.sessionSnapshot
        guard service.isCurrentSession(requestedSession) else { return }
        let requestID = UUID()
        profileRequestID = requestID
        isLoggedIn = requestedSession.isAuthenticated
        guard requestedSession.isAuthenticated else {
            profile = nil
            return
        }

        isLoadingProfile = true
        defer {
            if profileRequestID == requestID {
                isLoadingProfile = false
            }
        }
        do {
            let refreshedProfile = try await service.fetchAccountProfile(
                ifCurrentSession: requestedSession
            )
            guard profileRequestID == requestID,
                  service.isCurrentSession(requestedSession) else { return }
            profile = refreshedProfile
            if let refreshedProfile {
                await service.synchronizeCurrentAccount(
                    profile: refreshedProfile,
                    ifCurrentSession: requestedSession
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard profileRequestID == requestID,
                  service.isCurrentSession(requestedSession) else { return }
            statusMessage = error.localizedDescription
            AppLogger.warning("KCM 账号信息获取失败: \(error)")
        }
    }

    private func claimDailyVIP() {
        guard !isProcessingVIP else { return }
        let service = KCMMusicService.shared
        let requestedSession = service.sessionSnapshot
        guard requestedSession.isAuthenticated,
              service.isCurrentSession(requestedSession) else { return }
        if KCMDailyMembershipEngine.shared.hasCompletedToday(
            ifCurrentSession: requestedSession
        ) {
            statusMessage = "今日会员已领取"
            HapticManager.shared.success()
            return
        }
        let requestID = UUID()
        membershipRequestID = requestID
        isProcessingVIP = true
        statusMessage = nil
        Task { @MainActor in
            defer {
                if membershipRequestID == requestID {
                    isProcessingVIP = false
                }
            }
            do {
                let claimResult = try await service.claimDailyLiteVIP(
                    ifCurrentSession: requestedSession
                )
                guard membershipRequestID == requestID,
                      service.isCurrentSession(requestedSession) else { return }
                let claimText = switch claimResult {
                case .claimed: "领取成功"
                case .alreadyClaimed: "今日会员已领取"
                }
                KCMDailyMembershipEngine.shared.recordCompletion(
                    ifCurrentSession: requestedSession
                )

                let resultMessage: String
                do {
                    let upgraded = try await service.upgradeDailyLiteVIP(
                        ifCurrentSession: requestedSession
                    )
                    resultMessage = upgraded ? "\(claimText)，升级成功" : "\(claimText)，升级未完成"
                } catch {
                    guard service.isCurrentSession(requestedSession) else { return }
                    resultMessage = "\(claimText)，\(error.localizedDescription)"
                }
                guard membershipRequestID == requestID,
                      service.isCurrentSession(requestedSession) else { return }
                await refreshAccount(ifCurrentSession: requestedSession)
                guard membershipRequestID == requestID,
                      service.isCurrentSession(requestedSession) else { return }
                statusMessage = resultMessage
                HapticManager.shared.success()
            } catch is CancellationError {
                return
            } catch {
                guard membershipRequestID == requestID,
                      service.isCurrentSession(requestedSession) else { return }
                statusMessage = error.localizedDescription
            }
        }
    }

    private func logout() {
        KCMMusicService.shared.logout {
            LoginIdentityManager.shared.accountDidLogOut(.kugou)
        }
        profileRequestID = nil
        membershipRequestID = nil
        isLoadingProfile = false
        isProcessingVIP = false
        isLoggedIn = false
        profile = nil
        statusMessage = nil
    }

    private func handleSessionDidChange() {
        profileRequestID = nil
        membershipRequestID = nil
        isLoadingProfile = false
        isProcessingVIP = false
        profile = nil
        statusMessage = nil

        let service = KCMMusicService.shared
        let session = service.sessionSnapshot
        isLoggedIn = session.isAuthenticated
        guard session.isAuthenticated,
              service.isCurrentSession(session) else { return }
        Task { @MainActor in
            await refreshAccount(ifCurrentSession: session)
        }
    }
}
