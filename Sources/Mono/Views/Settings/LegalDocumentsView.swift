import SwiftUI

struct MonoLegalSection: Identifiable {
    let title: String
    let paragraphs: [String]

    var id: String { title }
}

struct MonoLegalLink: Identifiable {
    let title: String
    let urlString: String

    var id: String { title }
    var url: URL? { URL(string: urlString) }
}

enum MonoLegalDocument: String, CaseIterable, Identifiable {
    case userAgreement
    case privacyPolicy
    case disclaimer
    case openSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userAgreement: return String(localized: "legal_user_agreement")
        case .privacyPolicy: return String(localized: "legal_privacy_policy")
        case .disclaimer: return String(localized: "legal_disclaimer")
        case .openSource: return String(localized: "legal_open_source")
        }
    }

    var summary: String {
        switch self {
        case .userAgreement: return String(localized: "legal_user_agreement_summary")
        case .privacyPolicy: return String(localized: "legal_privacy_policy_summary")
        case .disclaimer: return String(localized: "legal_disclaimer_summary")
        case .openSource: return String(localized: "legal_open_source_summary")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .userAgreement: return .infoCircle
        case .privacyPolicy: return .lock
        case .disclaimer: return .warning
        case .openSource: return .layers
        }
    }

    var effectiveDate: String {
        switch self {
        case .openSource:
            return String(localized: "legal_updated_date")
        default:
            return String(localized: "legal_effective_date")
        }
    }

    var sections: [MonoLegalSection] {
        isChinese ? chineseSections : englishSections
    }

    var links: [MonoLegalLink] {
        guard self == .openSource else { return [] }
        return [
            MonoLegalLink(title: "FFmpeg · LGPL-2.1-or-later", urlString: "https://ffmpeg.org/legal.html"),
            MonoLegalLink(title: "ZIPFoundation · MIT", urlString: "https://github.com/weichsel/ZIPFoundation/blob/development/LICENSE"),
            MonoLegalLink(title: "Lucide · ISC", urlString: "https://github.com/lucide-icons/lucide/blob/main/LICENSE"),
            MonoLegalLink(title: "NeteaseCloudMusicApi Enhanced · MIT", urlString: "https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/main/LICENSE"),
            MonoLegalLink(title: "QQMusicApi · GPL-3.0", urlString: "https://github.com/L-1124/QQMusicApi/blob/main/LICENSE"),
            MonoLegalLink(title: "KuGouMusicApi · MIT", urlString: "https://github.com/MakcRe/KuGouMusicApi/blob/main/LICENSE")
        ]
    }

    private var isChinese: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true
    }

    private var chineseSections: [MonoLegalSection] {
        switch self {
        case .userAgreement:
            return [
                MonoLegalSection(
                    title: "适用范围",
                    paragraphs: [
                        "本协议适用于 Mono iOS 应用及其配套服务。安装、登录或使用 Mono，即表示你已阅读并同意本协议与《隐私政策》。不同意其中任何内容时，请停止使用。",
                        "Mono 提供多平台音乐访问、本地播放、歌词、播放队列、音效、听歌统计、下载、云同步与一起听等功能。部分功能依赖第三方平台、自建服务或 AI 服务，实际可用范围以当前版本和所在地区为准。",
                        "通过 App Store 获取 Mono 时，Apple 的标准最终用户许可协议同时适用；本协议用于说明 Mono 自有功能和配套服务的具体规则。"
                    ]
                ),
                MonoLegalSection(
                    title: "账号与授权",
                    paragraphs: [
                        "你应确保第三方音乐平台账号来源合法，并遵守对应平台的用户协议、会员规则和地区限制。账号凭据、Cookie、Token 与授权状态仅用于完成登录、资料库读取、内容请求和播放。",
                        "因平台限制、风控、账号失效或授权撤销导致的功能中断，不视为 Mono 的服务承诺未履行。"
                    ]
                ),
                MonoLegalSection(
                    title: "使用规则",
                    paragraphs: [
                        "不得利用 Mono 侵犯版权、商标、隐私或其他合法权利；不得绕过付费、会员、地区或访问控制；不得批量抓取、传播受保护内容，或干扰服务器、房间和其他用户的正常使用。",
                        "一起听聊天不得发布违法、侮辱、色情、暴力、涉赌涉毒、侵犯隐私或其他不当内容。Mono 可以对滥用行为限制请求、关闭功能或终止服务访问。"
                    ]
                ),
                MonoLegalSection(
                    title: "下载与本地内容",
                    paragraphs: [
                        "下载、本地导入、字体和视频背景功能仅用于管理你有权使用的内容。你应自行确认来源和许可范围，并承担复制、保存、播放、展示或分享产生的责任。",
                        "删除 App、清理系统存储、关闭云同步或第三方平台变更，可能导致文件与记录无法恢复。重要内容应自行备份。"
                    ]
                ),
                MonoLegalSection(
                    title: "AI 与音频处理",
                    paragraphs: [
                        "Mono Audio Agent 和听歌报告中的 AI 内容由模型根据歌曲信息、音频特征或收听数据生成，仅供参考，结果可能不准确、不完整或不适合当前设备与听音环境。",
                        "你可以关闭智能调音、重新分析、切换方案或恢复原声。请避免在高音量下长时间试听或频繁切换音效。"
                    ]
                ),
                MonoLegalSection(
                    title: "服务与权利",
                    paragraphs: [
                        "第三方接口、平台政策、服务器状态、网络环境或系统版本变化可能导致功能调整、中断或停止。你可以随时停止使用，并删除本地记录、云端同步数据、调音方案或平台授权。",
                        "Mono 的名称、图标、界面、代码和自有内容归其权利人所有。第三方音乐、歌词、封面、视频、字体、商标与服务名称归各自权利人所有。法律规定不得排除或限制的消费者权利不受本协议影响。"
                    ]
                )
            ]

        case .privacyPolicy:
            return [
                MonoLegalSection(
                    title: "本地数据",
                    paragraphs: [
                        "主题、播放器、图标、字体、音质、音效、本地音乐、下载、歌词、封面、缓存、队列、播放记录、听歌统计、均衡器预设、AI 调音结果和调试日志通常保存在设备中。",
                        "除非你主动使用云同步、AI、一起听、反馈或外部服务，这些本地数据不会由 Mono 主动上传。"
                    ]
                ),
                MonoLegalSection(
                    title: "账号与资料库",
                    paragraphs: [
                        "登录 NCM、QCM、KCM 或授权 Apple Music 时，Mono 会处理完成请求所需的账号标识、授权状态、Cookie、Token、昵称、头像、歌单和资料库内容。敏感凭据优先保存在 iOS Keychain。",
                        "部分账号管理或播放线路会把必要的会话信息发送到你选择的服务端。Mono 不会要求或读取 Apple ID 密码。",
                        "Mono 可能生成随机的应用设备标识，用于配置分发、请求限制、安全防护、内容缓存和一起听身份。该标识不是广告标识符，不用于跨 App 跟踪。"
                    ]
                ),
                MonoLegalSection(
                    title: "云同步",
                    paragraphs: [
                        "开启云同步后，Mono 可以上传并恢复本地歌单、播放记录、听歌统计、下载记录元数据、播客订阅、个性化配色、AI 调音方案和自定义均衡器预设。音乐文件本身不会作为云同步数据上传。"
                    ]
                ),
                MonoLegalSection(
                    title: "AI 功能",
                    paragraphs: [
                        "使用智能调音或听歌报告 AI 分析时，Mono 会向配置的 AI 服务发送歌曲信息、必要的歌词片段、输出设备类型、音频测量特征、调音设置或聚合听歌统计。",
                        "调音服务可选择内置大模型、AI 接口或自研共鸣 S2 模型。共鸣 S2 在首次调音时下载模型并在本地运行；使用内置大模型或 AI 接口时，会向所选服务发送频谱、响度、动态、节奏和声场等数值特征，不上传采样得到的原始音频。"
                    ]
                ),
                MonoLegalSection(
                    title: "一起听与诊断",
                    paragraphs: [
                        "一起听会处理房间码、设备生成的用户标识、昵称、头像、聊天、房间歌单、播放进度和控制操作，并同步给同一房间的成员。",
                        "调试日志默认保存在设备中，只有在你主动复制、导出或提交反馈时才会离开设备。TestFlight 或系统诊断信息由 Apple 按其规则处理。"
                    ]
                ),
                MonoLegalSection(
                    title: "用途与共享",
                    paragraphs: [
                        "数据仅用于登录、内容请求、播放、状态恢复、云同步、AI 分析、一起听、安全防护和故障排查。Mono 不接入广告 SDK，不出售个人数据，也不使用跨 App 广告跟踪。",
                        "数据只会在对应功能需要时发送给音乐平台、Apple 系统服务、Mono 配套服务、DengDeng AI 或你选择的外部内容来源。第三方服务同时适用其自身隐私规则。"
                    ]
                ),
                MonoLegalSection(
                    title: "保存、删除与安全",
                    paragraphs: [
                        "本地数据保留到你主动删除、清理或卸载 App。你可以删除下载、播放记录、调音方案、自定义预设和云端快照，并在账号管理中退出或撤销授权。",
                        "Mono 使用 iOS Keychain、系统沙盒和 HTTPS 等方式保护数据，但任何存储与传输都无法保证绝对安全。请勿公开 Token、Cookie、房间码或调试日志。"
                    ]
                ),
                MonoLegalSection(
                    title: "你的选择",
                    paragraphs: [
                        "你可以不登录第三方账号，不启用云同步、AI 自动调音、一起听或下载。关闭功能不会影响与其无关的本地播放能力。未成年人应在监护人指导下使用账号、聊天和外部内容功能。"
                    ]
                )
            ]

        case .disclaimer:
            return [
                MonoLegalSection(
                    title: "内容与版权",
                    paragraphs: [
                        "Mono 是音乐播放与管理工具，不提供或销售音乐版权。歌曲、歌词、封面、视频、评论、字体、动态壁纸、商标和平台资料归各自权利人所有。",
                        "用户应仅访问、下载、导入、播放或展示自己有权使用的内容，并遵守所在地法律与对应平台条款。"
                    ]
                ),
                MonoLegalSection(
                    title: "第三方服务",
                    paragraphs: [
                        "音乐平台、Apple Music、AI、字体、视频背景和自建服务可能因网络、地区、会员状态、账号风控、接口调整或授权到期而不可用。",
                        "Mono 不保证第三方内容的准确性、完整性、合法性、音质、可用时间或持续兼容，也不代表与相关平台存在官方合作、认可或隶属关系。"
                    ]
                ),
                MonoLegalSection(
                    title: "AI 与音效",
                    paragraphs: [
                        "AI 调音和听歌报告不构成专业录音、母带、听力保护或事实核验意见。不同设备、音量和环境会产生不同结果。",
                        "请保持合理音量；出现不适、爆音或异常时，应立即停止使用相关音效并恢复原声。"
                    ]
                ),
                MonoLegalSection(
                    title: "数据与责任",
                    paragraphs: [
                        "系统清理、设备损坏、卸载、账号失效、第三方变更和网络故障都可能造成内容或记录无法恢复，重要文件与数据应自行备份。",
                        "在适用法律允许的范围内，Mono 按“现状”和“可用”状态提供，不承担超出法律强制规定的间接、附带或后果性损失。"
                    ]
                )
            ]

        case .openSource:
            return [
                MonoLegalSection(
                    title: "适用说明",
                    paragraphs: [
                        "Mono 使用以下开源软件。各项目仍由原作者和贡献者持有权利，并分别适用其原始许可证。本说明不改变任何第三方许可证。",
                        "Mono 本体代码、名称、图标和品牌资产未因第三方组件的开源许可而自动开放授权。"
                    ]
                ),
                MonoLegalSection(
                    title: "App 与音频组件",
                    paragraphs: [
                        "FFmpeg — LGPL-2.1-or-later。当前构建未启用 GPL 与 nonfree 组件。",
                        "FFmpegSwiftSDK — MIT。",
                        "ZIPFoundation — MIT。",
                        "Lucide — ISC；其中 Feather 衍生部分适用 MIT。"
                    ]
                ),
                MonoLegalSection(
                    title: "音乐服务与后端参考",
                    paragraphs: [
                        "NeteaseCloudMusicApi Enhanced — MIT。",
                        "QQMusicApi — GPL-3.0。",
                        "KuGouMusicApi — MIT。"
                    ]
                ),
                MonoLegalSection(
                    title: "许可义务",
                    paragraphs: [
                        "发行、修改或重新分发相关组件时，应满足对应许可证中的版权声明、源代码提供、修改说明及其他义务。若组件副本附带独立许可证文件，以该文件为准。"
                    ]
                )
            ]
        }
    }

    private var englishSections: [MonoLegalSection] {
        switch self {
        case .userAgreement:
            return [
                MonoLegalSection(title: "Scope", paragraphs: ["This agreement applies to the Mono iOS app and its supporting services. By installing, signing in to, or using Mono, you accept this agreement and the Privacy Policy.", "Mono provides multi-source music access, local playback, lyrics, audio processing, listening statistics, downloads, cloud sync, and listening rooms. Availability depends on the current version, region, network, and third-party services."]),
                MonoLegalSection(title: "Accounts and authorization", paragraphs: ["You must use lawfully obtained third-party accounts and comply with each platform's terms, membership rules, and regional restrictions. Credentials and authorization data are used only to complete account and media requests."]),
                MonoLegalSection(title: "Acceptable use", paragraphs: ["Do not infringe intellectual property or privacy rights, bypass access controls, redistribute protected content, disrupt services, or post illegal or abusive content. Mono may restrict abusive access."]),
                MonoLegalSection(title: "Downloads and AI", paragraphs: ["Only download, import, or display content you are entitled to use. AI tuning and generated content are provided for reference and may be inaccurate or unsuitable for a device or listening environment."]),
                MonoLegalSection(title: "Service and rights", paragraphs: ["Third-party changes may interrupt or remove features. Mono branding and original materials remain the property of their respective owner; third-party content remains the property of its rights holders. Mandatory consumer rights remain unaffected."])
            ]
        case .privacyPolicy:
            return [
                MonoLegalSection(title: "On-device data", paragraphs: ["Preferences, local music, downloads, caches, playback history, listening statistics, equalizer presets, tuning results, and debug logs are normally stored on your device."]),
                MonoLegalSection(title: "Accounts and sync", paragraphs: ["When you authorize a music service, Mono processes the identifiers, tokens, profile, playlists, and library data needed for that service. Sensitive local credentials are stored in iOS Keychain where applicable. Cloud sync uploads only the categories you enable; music files are not uploaded as sync data."]),
                MonoLegalSection(title: "AI features", paragraphs: ["AI requests may include track metadata, output-device type, measured audio features, tuning settings, aggregated listening statistics, or content prompts. Raw sampled audio is not uploaded for intelligent tuning."]),
                MonoLegalSection(title: "Listening rooms and diagnostics", paragraphs: ["Listening rooms process room identifiers, nickname, avatar, chat, queue, playback position, and controls. Debug logs remain on device unless you export or submit them."]),
                MonoLegalSection(title: "Use and control", paragraphs: ["Mono does not include advertising SDKs, sell personal data, or perform cross-app advertising tracking. You can decline account authorization and disable cloud sync, automatic AI tuning, listening rooms, or downloads."])
            ]
        case .disclaimer:
            return [
                MonoLegalSection(title: "Content", paragraphs: ["Mono is a playback and management tool and does not sell music rights. Music, lyrics, artwork, video, comments, fonts, wallpapers, trademarks, and platform data belong to their respective rights holders."]),
                MonoLegalSection(title: "External services", paragraphs: ["Third-party services may become unavailable because of network, region, account, API, authorization, or policy changes. Mono does not guarantee their accuracy, legality, quality, or continued availability."]),
                MonoLegalSection(title: "AI, audio, and data", paragraphs: ["AI and audio-processing results are not professional mastering, hearing-protection, or factual advice. Keep playback at a reasonable volume and restore the original sound if an issue occurs. Back up important local data."]),
                MonoLegalSection(title: "Liability", paragraphs: ["To the extent permitted by applicable law, Mono is provided as is and as available. Rights and liabilities that cannot legally be excluded remain unaffected."])
            ]
        case .openSource:
            return [
                MonoLegalSection(title: "Notice", paragraphs: ["Mono uses open-source software under each project's original license. Those licenses do not automatically license Mono source code, its name, icons, or brand assets."]),
                MonoLegalSection(title: "App and audio", paragraphs: ["FFmpeg — LGPL-2.1-or-later; the current build has GPL and nonfree components disabled.", "FFmpegSwiftSDK — MIT.", "ZIPFoundation — MIT.", "Lucide — ISC, with Feather-derived portions under MIT."]),
                MonoLegalSection(title: "Service references", paragraphs: ["NeteaseCloudMusicApi Enhanced — MIT.", "QQMusicApi — GPL-3.0.", "KuGouMusicApi — MIT."]),
                MonoLegalSection(title: "License obligations", paragraphs: ["Distribution, modification, or redistribution must comply with each license's notice, source, modification, and other requirements. A license file shipped with a component takes precedence."])
            ]
        }
    }
}

struct LegalDocumentsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    private var ink: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var inkMuted: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary.opacity(0.68)
    }

    private var hairline: Color { ink.opacity(0.12) }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "legal_center_title"),
                        eyebrow: "MONO",
                        icon: .infoCircle,
                        signalModule: .legal
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(localized: "legal_center_date"))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(inkMuted)
                            .padding(.bottom, 22)

                        ForEach(Array(MonoLegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                            NavigationLink {
                                LegalDocumentDetailView(document: document)
                            } label: {
                                documentRow(document)
                            }
                            .buttonStyle(MonoBouncingButtonStyle(scale: 0.99, opacity: 0.72))

                            if index < MonoLegalDocument.allCases.count - 1 {
                                Rectangle()
                                    .fill(hairline.opacity(0.72))
                                    .frame(height: 0.5)
                            }
                        }

                        Text(String(localized: "legal_center_footer"))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(inkMuted)
                            .lineSpacing(3)
                            .padding(.top, 28)

                        FloatingBarBottomSpacer()
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding + 4)
                    .iPadContentWidth(700)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .compatFontDesign(nil)
    }

    @ViewBuilder
    private var background: some View {
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
    }

    private func documentRow(_ document: MonoLegalDocument) -> some View {
        HStack(spacing: 14) {
            MonoIcon(icon: document.icon, size: 20, color: ink, lineWidth: 1.55)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(ink)

                Text(document.summary)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            MonoIcon(icon: .chevronRight, size: 12, color: inkMuted, lineWidth: 1.6)
        }
        .padding(.vertical, 17)
        .contentShape(Rectangle())
    }
}

struct LegalDocumentDetailView: View {
    let document: MonoLegalDocument
    @ObservedObject private var settings = SettingsManager.shared

    private var ink: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var inkMuted: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary.opacity(0.68)
    }

    private var hairline: Color { ink.opacity(0.12) }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsScrollablePageHeader(
                        title: document.title,
                        eyebrow: "MONO",
                        icon: document.icon,
                        signalModule: .legal
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(document.effectiveDate)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(inkMuted)
                            .padding(.bottom, 28)

                        ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(ink)

                                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(ink.opacity(0.86))
                                        .lineSpacing(5)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }

                            if index < document.sections.count - 1 {
                                Rectangle()
                                    .fill(hairline)
                                    .frame(height: 0.5)
                                    .padding(.vertical, 24)
                            }
                        }

                        if !document.links.isEmpty {
                            Rectangle()
                                .fill(hairline)
                                .frame(height: 0.5)
                                .padding(.vertical, 24)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(localized: "legal_original_licenses"))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(ink)
                                    .padding(.bottom, 10)

                                ForEach(document.links) { item in
                                    if let url = item.url {
                                        Link(destination: url) {
                                            HStack(spacing: 12) {
                                                Text(item.title)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundColor(ink)

                                                Spacer(minLength: 10)

                                                MonoIcon(icon: .chevronRight, size: 11, color: inkMuted, lineWidth: 1.5)
                                            }
                                            .padding(.vertical, 12)
                                            .contentShape(Rectangle())
                                        }
                                    }
                                }
                            }
                        }

                        if let websiteURL = URL(string: "https://mono.zijiu522.cn") {
                            Link(destination: websiteURL) {
                                Text(String(localized: "legal_contact_website"))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(inkMuted)
                            }
                            .padding(.top, 30)
                        }

                        FloatingBarBottomSpacer()
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding + 4)
                    .iPadContentWidth(700)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .compatFontDesign(nil)
    }

    @ViewBuilder
    private var background: some View {
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
    }
}

struct TokenAgreementAuthorizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAgree: () -> Void
    let onDecline: () -> Void

    private var ink: Color { .monoTextPrimary }
    private var inkMuted: Color { .monoTextSecondary.opacity(0.72) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "服务授权"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(ink)

                    Text(String(localized: "Token 验证成功。启用在线服务前，请阅读并同意以下协议与说明。"))
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(inkMuted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(MonoLegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                            NavigationLink {
                                LegalDocumentDetailView(document: document)
                            } label: {
                                HStack(spacing: 14) {
                                    MonoIcon(icon: document.icon, size: 19, color: ink, lineWidth: 1.55)
                                        .frame(width: 26, height: 26)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(document.title)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(ink)

                                        Text(document.summary)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundColor(inkMuted)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 12)

                                    MonoIcon(icon: .chevronRight, size: 11, color: inkMuted, lineWidth: 1.5)
                                }
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < MonoLegalDocument.allCases.count - 1 {
                                Rectangle()
                                    .fill(Color.monoSeparator.opacity(0.62))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                    .padding(.top, 24)

                    Text(String(localized: "点击任一文件即可直接查看全文。同意后，Token 才会保存并启用在线功能。"))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(inkMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                        .padding(.bottom, 120)
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding + 4)
                .padding(.top, 30)
                .iPadContentWidth(660)
            }
            .scrollIndicators(.hidden)
            .background(ThemedSettingsBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text(String(localized: "不同意"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .monoGlassCard(cornerRadius: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.monoSeparator.opacity(0.8), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))

                    Button {
                        onAgree()
                        dismiss()
                    } label: {
                        Text(String(localized: "同意并继续"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Color.monoAccentForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.monoAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                }
                .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .interactiveDismissDisabled()
    }
}
