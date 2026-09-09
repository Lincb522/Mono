import SwiftUI
import UIKit

struct AppleMusicAccountView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var service = AppleMusicService.shared
    @State private var isRequestingAuthorization = false
    @State private var authorizationMessage = ""
    @State private var showAuthorizationAlert = false

    var body: some View {
        List {
            if SignalStyle.isActive {
                SignalNestedPageHeader(
                    title: "Apple Music",
                    eyebrow: "MEDIA ACCESS",
                    icon: .personCircle,
                    module: .accounts
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("授权") {
                HStack(spacing: 12) {
                    PlatformBadgeLabel(
                        text: MusicSource.appleMusic.shortName,
                        source: .appleMusic,
                        fontSize: 10
                    )

                    Text("Apple Music")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.monoTextPrimary)

                    Spacer()

                    Text(service.authorizationStateText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.monoTextSecondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)

            if !service.isAuthorized {
                Section {
                    Button {
                        handleAuthorizationButton()
                    } label: {
                        if isRequestingAuthorization {
                            ProgressView()
                        } else {
                            Text(service.authorizationRequiresSettings ? "前往系统设置" : "授权")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isRequestingAuthorization)
                }
                .listRowBackground(SignalStyle.isActive ? SignalStyle.surface : nil)
            }
        }
        .scrollContentBackground(.hidden)
        .claritySettingsListStyle()
        .background(ThemedPageBackground())
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton()
        .onAppear {
            service.refreshAuthorizationStatus()
        }
        .alert("Apple Music 授权", isPresented: $showAuthorizationAlert) {
            if service.authorizationRequiresSettings {
                Button("前往设置") {
                    openSystemSettings()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(authorizationMessage)
        }
    }

    private func handleAuthorizationButton() {
        if service.authorizationRequiresSettings {
            openSystemSettings()
        } else if service.authorizationIsRestricted {
            authorizationMessage = "此设备限制了 Apple Music 访问，请检查系统的屏幕使用时间或设备管理设置。"
            showAuthorizationAlert = true
        } else {
            requestAuthorization()
        }
    }

    private func requestAuthorization() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        Task { @MainActor in
            let authorized = await service.requestAuthorizationIfNeeded(
                refreshesSubscription: true
            )
            isRequestingAuthorization = false
            guard !authorized else { return }

            service.refreshAuthorizationStatus()
            if service.authorizationRequiresSettings {
                authorizationMessage = "Apple Music 访问已被关闭，请在系统设置中允许 Mono 访问媒体与 Apple Music。"
            } else if service.authorizationIsRestricted {
                authorizationMessage = "此设备限制了 Apple Music 访问，请检查系统的屏幕使用时间或设备管理设置。"
            } else {
                authorizationMessage = "未能完成 Apple Music 授权，请稍后重试。"
            }
            showAuthorizationAlert = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
