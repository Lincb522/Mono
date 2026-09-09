// 可配置主题组件与固定主题组件并存，配置由 AppIntent 持久化。

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 主题 AppEnum

extension WidgetTheme: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "主题")
    }

    /// App Intents 编译期只接受穷举字典字面量，不能由 `allCases` 动态构造；
    /// 展示文案需与 `displayName` 保持一致。
    static let caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .polaroid: "拍立得",
        .vinyl: "黑胶",
        .vinylDark: "黑胶（深色）",
        .poster: "海报",
        .magazine: "杂志",
        .aperture: "圆窗唱片",
        .pager: "寻呼机（深色）",
        .pagerLight: "寻呼机（浅色）",
        .radio: "收音机",
        .dashboard: "仪表盘",
        .soundwave: "声波",
        .typewriter: "打字机",
        .lyrics: "歌词排版",
        .lyricsDark: "歌词排版（深色）",
        .lyricsCover: "专辑封面",
    ]
}

// MARK: - 配置 Intent

/// 保存单个 Widget 实例选择的主题。
struct NowPlayingThemeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择主题"
    static let description = IntentDescription("选择这个小组件使用的主题")

    @Parameter(title: "主题", default: .polaroid)
    var theme: WidgetTheme
}

// MARK: - 时间线提供器

/// 将实例配置的主题转交给统一的当前播放时间线提供器。
struct SelectableNowPlayingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry.preview(theme: .polaroid)
    }

    func snapshot(
        for configuration: NowPlayingThemeIntent,
        in context: Context
    ) async -> NowPlayingEntry {
        NowPlayingProvider(theme: configuration.theme).snapshotEntry(in: context)
    }

    func timeline(
        for configuration: NowPlayingThemeIntent,
        in context: Context
    ) async -> Timeline<NowPlayingEntry> {
        NowPlayingProvider(theme: configuration.theme).makeTimeline(in: context)
    }
}

// MARK: - 可配置主题组件

/// 允许每个 Widget 实例独立选择当前播放主题。
struct SelectableNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "zijiu.Monologue.com.widget.nowplaying.selectable",
            intent: NowPlayingThemeIntent.self,
            provider: SelectableNowPlayingProvider()
        ) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Mono · 自选主题")
        .description("长按编辑小组件可切换主题")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
