import SwiftUI

extension SettingsView {
    // MARK: - 通透设置主页

    @ViewBuilder
    var claritySettingsContent: some View {
        claritySettingsHeader
        ClarityShell(cornerRadius: 32) {
            VStack(spacing: 0) {
                clarityThemeModeSelector
                claritySettingsDivider
                claritySettingsRoute(
                    icon: .playerTheme,
                    title: settingsText("settings_navigation_appearance_title"),
                    subtitle: settingsText("settings_navigation_appearance_subtitle"),
                    destination: .appearance
                )
                claritySettingsDivider
                claritySettingsRoute(
                    icon: .soundQuality,
                    title: settingsText("settings_navigation_playback_title"),
                    subtitle: settingsText("settings_navigation_playback_subtitle"),
                    destination: .playback
                )
                claritySettingsDivider
                claritySettingsRoute(
                    icon: .cloud,
                    title: settingsText("settings_navigation_cloud_sync_title"),
                    subtitle: hasToken ? playlistSyncStatusText : settingsText("settings_navigation_cloud_sync_disabled"),
                    destination: .cloudSync
                )
                claritySettingsDivider
                claritySettingsRoute(
                    icon: .storage,
                    title: String(localized: "settings_storage_manage"),
                    subtitle: String(localized: "settings_storage_manage_desc"),
                    value: cacheSize,
                    destination: .storage
                )
                if AppConfig.Features.downloadEnabled {
                    claritySettingsDivider
                    claritySettingsRoute(
                        icon: .download,
                        title: String(localized: "settings_download_manage"),
                        subtitle: nil,
                        destination: .download
                    )
                }
                claritySettingsDivider
                claritySettingsRoute(
                    icon: .infoCircle,
                    title: String(localized: "settings_about"),
                    subtitle: nil,
                    value: appVersion,
                    destination: .about
                )
            }
            .padding(.horizontal, 12)
        }

        clarityAccessPanel

        if qqDevMode {
            otherSection
        }
    }

    var claritySettingsHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings_title"))
                    .font(ClarityStyle.title(24, weight: .semibold))
                    .foregroundStyle(ClarityStyle.ink)
                Text(settingsText("settings_navigation_appearance_subtitle"))
                    .font(ClarityStyle.body(11.5))
                    .foregroundStyle(ClarityStyle.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            NavigationLink {
                AboutView()
            } label: {
                MonoIcon(icon: .infoCircle, size: 17, color: ClarityStyle.ink, lineWidth: 1.5)
                    .frame(width: 42, height: 42)
                    .background(ClarityMembrane(shape: Circle(), strength: .regular))
            }
            .buttonStyle(ClarityPressStyle())
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .monoPageHeaderCollapse()
    }

    var clarityThemeModeSelector: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(String(localized: "settings_theme_mode"))
                .font(ClarityStyle.body(13, weight: .semibold))
                .foregroundStyle(ClarityStyle.ink)

            HStack(spacing: 6) {
                clarityThemeModeButton("system", title: String(localized: "settings_theme_auto"), icon: .sparkle)
                clarityThemeModeButton("light", title: String(localized: "settings_theme_light"), icon: .sun)
                clarityThemeModeButton("dark", title: String(localized: "settings_theme_dark"), icon: .moon)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
    }

    func clarityThemeModeButton(_ value: String, title: String, icon: MonoIcon.IconType) -> some View {
        Button {
            guard settings.themeMode != value else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                settings.themeMode = value
            }
        } label: {
            HStack(spacing: 6) {
                MonoIcon(
                    icon: icon,
                    size: 13,
                    color: settings.themeMode == value ? ClarityStyle.onSelection : ClarityStyle.inkSoft,
                    lineWidth: 1.45
                )
                Text(title)
                    .font(ClarityStyle.body(10.5, weight: settings.themeMode == value ? .semibold : .regular))
                    .foregroundStyle(settings.themeMode == value ? ClarityStyle.onSelection : ClarityStyle.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                if settings.themeMode == value {
                    ClaritySelectionLens(shape: Capsule())
                } else {
                    ClarityMembrane(shape: Capsule(), strength: .quiet)
                }
            }
        }
        .buttonStyle(ClarityPressStyle())
    }

    var claritySettingsDivider: some View {
        Rectangle()
            .fill(ClarityStyle.line)
            .frame(height: 1)
            .padding(.leading, 52)
    }

    func claritySettingsRoute(
        icon: MonoIcon.IconType,
        title: String,
        subtitle: String?,
        value: String? = nil,
        destination: SettingsNavigationDestination
    ) -> some View {
        NavigationLink {
            destination.view
        } label: {
            HStack(spacing: 12) {
                MonoIcon(icon: icon, size: 17, color: ClarityStyle.ink, lineWidth: 1.5)
                    .frame(width: 38, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ClarityStyle.body(13.5, weight: .semibold))
                        .foregroundStyle(ClarityStyle.ink)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(ClarityStyle.body(10.5))
                            .foregroundStyle(ClarityStyle.inkSoft)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(ClarityStyle.body(10.5, weight: .medium))
                        .foregroundStyle(ClarityStyle.inkFaint)
                        .lineLimit(1)
                }
                MonoIcon(icon: .chevronRight, size: 12, color: ClarityStyle.inkFaint, lineWidth: 1.4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClarityPressStyle())
    }

    /// 通透主题自己的访问与服务面板。它保留 Token、线路和开发者联系能力，
    /// 但不再把其他主题的开发者卡片直接嵌进设置主页。
    var clarityAccessPanel: some View {
        ClarityShell(cornerRadius: 32) {
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    Image("WeChatAvatar")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.88), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ZIJIU522")
                            .font(ClarityStyle.body(15, weight: .semibold))
                            .foregroundStyle(ClarityStyle.ink)
                        Text(settingsText("settings_developer_status"))
                            .font(ClarityStyle.body(10.5))
                            .foregroundStyle(ClarityStyle.inkSoft)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        apiTokenInput = SecureConfig.apiToken ?? apiTokenInput
                        isHeaderCardExpanded.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(tokenStatusColor)
                                .frame(width: 7, height: 7)
                            Text(tokenStatusText)
                                .font(ClarityStyle.body(10.5, weight: .semibold))
                                .foregroundStyle(ClarityStyle.ink)
                                .lineLimit(1)
                            MonoIcon(
                                icon: .chevronDown,
                                size: 10,
                                color: ClarityStyle.inkFaint,
                                lineWidth: 1.4
                            )
                            .rotationEffect(.degrees(isHeaderCardExpanded ? 180 : 0))
                            .animation(.easeInOut(duration: 0.18), value: isHeaderCardExpanded)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(ClarityMembrane(shape: Capsule(), strength: .quiet))
                    }
                    .buttonStyle(ClarityPressStyle())
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 16)

                SettingsHeaderReveal(isExpanded: isHeaderCardExpanded) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(ClarityStyle.line)
                            .frame(height: 1)
                            .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            HStack(spacing: 9) {
                                MonoIcon(icon: .unlock, size: 14, color: ClarityStyle.ink, lineWidth: 1.45)
                                TextField(settingsText("access_token_input_placeholder"), text: $apiTokenInput)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ClarityStyle.ink)
                                    .monoTextInputBehavior()
                                    .submitLabel(.done)
                                    .monoOnSubmit(text: $apiTokenInput) { _ in submitAPIToken() }

                                Button {
                                    MonoTextInputCommitter.commit(text: $apiTokenInput) { _ in submitAPIToken() }
                                } label: {
                                    Text(settingsText("common_save"))
                                        .font(ClarityStyle.body(11, weight: .semibold))
                                        .foregroundStyle(ClarityStyle.onAccent)
                                        .padding(.horizontal, 13)
                                        .frame(height: 32)
                                        .background(Capsule().fill(ClarityStyle.accent))
                                }
                                .buttonStyle(ClarityPressStyle())
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(ClarityMembrane(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), strength: .quiet))

                            HStack(spacing: 10) {
                                Button {
                                    PlatformPasteboard.copy("Fallin-Out0122")
                                    HapticManager.shared.success()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { wechatCopied = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { wechatCopied = false }
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        MonoIcon(
                                            icon: wechatCopied ? .checkmark : .layers,
                                            size: 13,
                                            color: wechatCopied ? .green : ClarityStyle.ink,
                                            lineWidth: 1.5
                                        )
                                        Text(wechatCopied ? settingsText("settings_contact_copied") : "Fallin-Out0122")
                                            .font(ClarityStyle.body(11, weight: .semibold))
                                            .foregroundStyle(wechatCopied ? Color.green : ClarityStyle.ink)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(ClarityMembrane(shape: Capsule(), strength: .quiet))
                                }
                                .buttonStyle(ClarityPressStyle())

                                Button {
                                    PlatformPasteboard.copy("Fallin-Out0122")
                                    HapticManager.shared.success()
                                    if let url = URL(string: "weixin://dl/contacts") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        MonoIcon(icon: .send, size: 13, color: ClarityStyle.ink, lineWidth: 1.5)
                                        Text(settingsText("settings_open_wechat"))
                                            .font(ClarityStyle.body(11, weight: .semibold))
                                            .foregroundStyle(ClarityStyle.ink)
                                            .lineLimit(1)
                                    }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(ClarityMembrane(shape: Capsule(), strength: .quiet))
                                }
                                .buttonStyle(ClarityPressStyle())
                            }

                            if ServerLineManager.isBackupConfigured {
                                ServerLineSelectorView()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

}
