import SwiftUI

/// 关于页面 — 版权页（Colophon）式排版：
/// 左对齐的文字层级 + 发丝线分隔 + 大号构建号做唯一的图形元素，
/// 不用图标胶囊、渐变卡片和特性宫格。
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsManager.shared
    @State private var mastheadVisible = false
    @State private var bodyVisible = false
    @State private var tapCount = 0
    @State private var versionTapCount = 0
    @AppStorage(AppConfig.StorageKeys.developerModeEnabled) private var qqDevMode = false
    @AppStorage(ChangelogPreferenceKeys.autoPresent) private var changelogAutoPresent = true

    private var versionNumber: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - 主题墨色

    private var ink: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var inkSoft: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkSoft }
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        return .monoTextSecondary
    }

    private var inkMuted: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary.opacity(0.58)
    }

    private var accent: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        return .monoAccent
    }

    private var hairline: Color { ink.opacity(0.12) }

    var body: some View {
        ZStack {
            Group {
                if settings.globalThemeId == .default {
                    ThemedSettingsBackground()
                } else if MinimalWhiteStyle.isActive {
                    MinimalWhiteRootBackdrop()
                } else {
                    ThemedPageBackground()
                }
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "关于"),
                        eyebrow: "MONO",
                        icon: .infoCircle,
                        signalModule: .about
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .opacity(mastheadVisible ? 1 : 0)
                            .offset(y: mastheadVisible ? 0 : 10)

                        statement
                            .padding(.top, 34)

                        Group {
                            sectionHeader(String(localized: "链接"))
                                .padding(.top, 44)

                            changelogRow
                            rowDivider
                            websiteRow
                            rowDivider
                            legalDocumentsRow
                            rowDivider
                            updateReminderRow

                            sectionHeader(String(localized: "制作信息"))
                                .padding(.top, 36)

                            factRow(String(localized: "developer_tools_title"), "ZIJIU522")
                            rowDivider
                            factRow(
                                String(localized: "播放引擎"),
                                String(localized: "Mono播放引擎"),
                                detail: String(localized: "基于 FFmpeg + AVAudioEngine 深度定制")
                            )
                            rowDivider
                            intelligentSystemFactRow
                            rowDivider
                            factRow(
                                String(localized: "架构"),
                                String(localized: "全原生自研"),
                                detail: String(localized: "SwiftUI + Combine · 原生 MVVM 架构")
                            )
                            rowDivider
                            factRow(
                                String(localized: "设计"),
                                String(localized: "Mono 设计语言"),
                                detail: String(localized: "丰富的主题、图标与播放器个性化设置")
                            )
                            rowDivider
                            factRow(String(localized: "发行"), "2024 — 2026")
                        }

                        footer
                            .padding(.top, 44)

                        FloatingBarBottomSpacer()
                    }
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: bodyVisible ? 0 : 14)
                    .padding(.top, 18)
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding + 4)
                    .iPadContentWidth(700)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        // 版权页排版依赖衬线/等宽对比，关掉全局 .rounded 覆盖
        .compatFontDesign(nil)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) {
                mastheadVisible = true
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.18)) {
                bodyVisible = true
            }
        }
    }

    // MARK: - 刊头

    private var masthead: some View {
        ZStack(alignment: .topTrailing) {
            // 唯一的图形元素：本次构建号，像书页角落的版次编号
            Text(buildNumber)
                .font(.system(size: 104, weight: .ultraLight))
                .monospacedDigit()
                .foregroundColor(ink.opacity(0.08))
                .offset(y: -18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ink.opacity(0.05))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(settings.appLogoAssetName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(hairline, lineWidth: 0.8)
                    }
                    .onTapGesture {
                        tapCount += 1
                        registerDeveloperModeTap()
                    }

                VStack(alignment: .leading, spacing: 9) {
                    MonoWordmarkImage(height: 22, preferredColorScheme: colorScheme)

                    Text(verbatim: "VERSION \(versionNumber) · BUILD \(buildNumber)")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(inkMuted)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: registerDeveloperModeTap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 题记

    private var statement: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("welcome_slogan"))
                .font(.system(size: 21, weight: .medium, design: .serif))
                .foregroundColor(ink)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey("welcome_slogan_short"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2.6)
                .foregroundColor(inkMuted)
        }
    }

    // MARK: - 链接区

    private var changelogRow: some View {
        NavigationLink {
            ChangelogHistoryView()
        } label: {
            HStack(spacing: 10) {
                Text(String(localized: "更新日志"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(ink)

                Spacer(minLength: 8)

                Text(String(localized: "历来版本"))
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)

                MonoIcon(icon: .chevronRight, size: 12, color: inkMuted, lineWidth: 1.6)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.72))
    }

    private var websiteRow: some View {
        Button {
            guard let url = URL(string: "https://mono.zijiu522.cn") else { return }
            HapticManager.shared.light()
            PlatformApplication.openURL(url)
        } label: {
            HStack(spacing: 10) {
                Text(String(localized: "官方网站"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(ink)

                Spacer(minLength: 8)

                Text(verbatim: "mono.zijiu522.cn")
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundColor(inkMuted)

                MonoIcon(icon: .chevronRight, size: 12, color: inkMuted, lineWidth: 1.6)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.72))
    }

    private var updateReminderRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "新版本更新提醒"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(ink)

                Text(String(localized: "版本更新后启动时弹出更新内容"))
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
            }

            Spacer(minLength: 8)

            Toggle(String(localized: "新版本更新提醒"), isOn: $changelogAutoPresent)
                .labelsHidden()
                .toggleStyle(SettingsSwitchToggleStyle())
        }
        .padding(.vertical, 12)
    }

    private var legalDocumentsRow: some View {
        NavigationLink {
            LegalDocumentsView()
        } label: {
            HStack(spacing: 10) {
                Text(String(localized: "legal_center_title"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(ink)

                Spacer(minLength: 8)

                Text(String(localized: "legal_center_row_detail"))
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)

                MonoIcon(icon: .chevronRight, size: 12, color: inkMuted, lineWidth: 1.6)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.72))
    }

    // MARK: - 制作信息区

    private func factRow(_ label: String, _ value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .foregroundColor(inkSoft)
                .fixedSize()

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(ink)

                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(inkMuted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private var intelligentSystemFactRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(localized: "智能系统"))
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .foregroundColor(inkSoft)
                .fixedSize()

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Mono Audio Agent")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(ink)
                    .lineLimit(1)

                Text(String(localized: "首创自研智能调音Agent"))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(verbatim: "共鸣 · Resonance")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text(String(localized: "自研调音模型"))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: "AI 服务由 DengDeng 提供"))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    // MARK: - 区块小标 / 分隔线

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundColor(inkMuted)
                .fixedSize()

            Rectangle()
                .fill(hairline)
                .frame(height: 0.5)
        }
        .padding(.bottom, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(hairline.opacity(0.7))
            .frame(height: 0.5)
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "仅供学习交流 · 请支持正版音乐"))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(inkMuted)

            Text(verbatim: "© 2024-2026 Mono. All Rights Reserved.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(inkMuted.opacity(0.8))

            if tapCount >= 7 {
                Text(String(localized: "你发现了彩蛋！你是一个有好奇心的人。"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(accent)
                    .transition(.scale.combined(with: .opacity))
            }

        }
        .animation(.spring, value: tapCount)
        .animation(.easeOut(duration: 0.2), value: qqDevMode)
    }

    // MARK: - 开发者模式

    private func registerDeveloperModeTap() {
        versionTapCount += 1
        HapticStyle.light.trigger()

        guard versionTapCount >= 5 else { return }
        versionTapCount = 0
        showDevModePrompt()
    }

    private func showDevModePrompt() {
        if qqDevMode {
            AlertManager.shared.show(
                title: String(localized: "dev_mode_title"),
                message: String(localized: "dev_mode_disable"),
                primaryButtonTitle: String(localized: "dev_mode_confirm"),
                secondaryButtonTitle: String(localized: "dev_mode_cancel"),
                primaryAction: {
                    qqDevMode = false
                    HapticManager.shared.success()
                }
            )
        } else {
            AlertManager.shared.show(
                title: String(localized: "dev_mode_title"),
                message: String(localized: "dev_mode_enable_message"),
                primaryButtonTitle: String(localized: "dev_mode_confirm"),
                secondaryButtonTitle: String(localized: "dev_mode_cancel"),
                primaryAction: {
                    qqDevMode = true
                    HapticManager.shared.success()
                }
            )
        }
    }
}
