import SwiftUI

/// 更新日志页面：从服务端拉取全部历史版本，
/// 以时间轴纵列展示；最新版本默认展开，旧版本点击展开。
struct ChangelogHistoryView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var releases: [AppChangelogRelease]?
    @State private var loadFailed = false
    @State private var reloadID = 0
    @State private var parsedNotes: [String: [ChangelogNoteSection]] = [:]
    @State private var expandedIDs: Set<String> = []

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
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

            content
        }
        .asideSettingsDetailChrome()
        // 版本号/日期用等宽字体，关掉全局 .rounded 覆盖
        .compatFontDesign(nil)
        .task(id: reloadID) { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsScrollablePageHeader(
                    title: String(localized: "更新日志"),
                    eyebrow: String(localized: "settings_eyebrow_changelog"),
                    icon: .history,
                    signalModule: .changelog
                )

                contentState
                FloatingBarBottomSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
        .themeRenderScrollLayer()
    }

    @ViewBuilder
    private var contentState: some View {
        if let releases {
            if releases.isEmpty {
                stateHint(String(localized: "暂无更新日志"))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                timeline(releases)
            }
        } else if loadFailed {
            VStack(spacing: 16) {
                stateHint(String(localized: "更新日志加载失败"))

                Button {
                    reloadID &+= 1
                } label: {
                    Text(String(localized: "action_retry"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .overlay(Capsule().stroke(hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(inkMuted)
                Text(String(localized: "正在加载"))
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundColor(inkMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    private func stateHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundColor(inkMuted)
    }

    // MARK: - 时间轴

    private func timeline(_ releases: [AppChangelogRelease]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                releaseEntry(
                    release,
                    isLast: index == releases.count - 1
                )
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding + 4)
        .iPadContentWidth(700)
    }

    private func releaseEntry(_ release: AppChangelogRelease, isLast: Bool) -> some View {
        let expanded = expandedIDs.contains(release.id)
        let isCurrent = release.build.trimmingCharacters(in: .whitespaces) == currentBuild

        return VStack(alignment: .leading, spacing: 0) {
            entryHeader(release, expanded: expanded, isCurrent: isCurrent)

            if expanded {
                notesBody(release)
                    .padding(.top, 14)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }

            Color.clear.frame(height: isLast ? 8 : 34)
        }
        .padding(.leading, 24)
        // 时间轴脊线：背景层会被提议整条条目的高度，竖线自然贯穿
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(hairline)
                    .frame(width: 0.8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 19)
                    .padding(.leading, 3.6)
            }
        }
        // 节点圆点：当前版本用主题色实心
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(isCurrent ? accent : Color.clear)
                .overlay(Circle().stroke(isCurrent ? accent : inkMuted, lineWidth: 1.2))
                .frame(width: 8, height: 8)
                .padding(.top, 7)
        }
    }

    private func entryHeader(
        _ release: AppChangelogRelease,
        expanded: Bool,
        isCurrent: Bool
    ) -> some View {
        Button {
            HapticManager.shared.light()
            if !expanded, parsedNotes[release.id] == nil {
                parsedNotes[release.id] = ChangelogNotesParser.parse(release.releaseNotes)
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                if expanded {
                    expandedIDs.remove(release.id)
                } else {
                    expandedIDs.insert(release.id)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(verbatim: displayVersion(release))
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(ink)

                        if isCurrent {
                            Text(String(localized: "当前版本"))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: 0.8))
                        }
                    }

                    Text(verbatim: publishedText(release))
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundColor(inkMuted)
                }

                Spacer(minLength: 8)

                MonoIcon(
                    icon: .chevronDown,
                    size: 12,
                    color: inkMuted,
                    lineWidth: 1.6
                )
                .rotationEffect(.degrees(expanded ? -180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.995, opacity: 0.75))
    }

    private func notesBody(_ release: AppChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(parsedNotes[release.id] ?? []) { section in
                VStack(alignment: .leading, spacing: 9) {
                    if let title = section.title {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(2)
                            .foregroundColor(inkSoft)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(verbatim: "·")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(inkMuted)

                                Text(verbatim: item)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundColor(ink.opacity(0.82))
                                    .lineSpacing(3.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 数据

    private func load() async {
        guard releases == nil, !Task.isCancelled else { return }
        loadFailed = false

        let fetched = await ChangelogManager.shared.fetchAllReleases()
        guard !Task.isCancelled else { return }
        guard let fetched else {
            loadFailed = true
            return
        }
        parsedNotes = [:]
        if let first = fetched.first {
            parsedNotes[first.id] = ChangelogNotesParser.parse(first.releaseNotes)
        }
        withAnimation(.easeOut(duration: 0.24)) {
            releases = fetched
            // 最新一条默认展开
            if let first = fetched.first {
                expandedIDs = [first.id]
            }
        }
    }

    // MARK: - 文案

    /// 服务端 version 形如「1.0（50）」，直接展示；为空时回退构建号
    private func displayVersion(_ release: AppChangelogRelease) -> String {
        let version = release.version.trimmingCharacters(in: .whitespaces)
        if version.isEmpty {
            return "Build \(release.build)"
        }
        return version
    }

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoParserPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private func publishedText(_ release: AppChangelogRelease) -> String {
        guard let raw = release.publishedAt else { return "" }
        let date = Self.isoParser.date(from: raw) ?? Self.isoParserPlain.date(from: raw)
        guard let date else { return raw }
        return Self.displayFormatter.string(from: date)
    }
}
