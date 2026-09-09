import WidgetKit
import SwiftUI

// MARK: - Widget 主题

/// Widget 支持的主题集合及其稳定 kind、展示名称与尺寸能力。
///
/// `Sendable` 必须在定义处声明，以满足跨文件 `AppEnum` 的并发一致性要求。
enum WidgetTheme: String, CaseIterable, Hashable, Sendable {
    case polaroid
    case vinyl
    case vinylDark
    case poster
    case magazine
    case aperture
    case pager
    case pagerLight
    case radio
    case dashboard
    case soundwave
    case typewriter
    case lyrics
    case lyricsDark
    case lyricsCover

    var displayName: String {
        switch self {
        case .polaroid: return "拍立得"
        case .vinyl: return "黑胶"
        case .vinylDark: return "黑胶（深色）"
        case .poster: return "海报"
        case .magazine: return "杂志"
        case .aperture: return "圆窗唱片"
        case .pager: return "寻呼机（深色）"
        case .pagerLight: return "寻呼机（浅色）"
        case .radio: return "收音机"
        case .dashboard: return "仪表盘"
        case .soundwave: return "声波"
        case .typewriter: return "打字机"
        case .lyrics: return "歌词排版"
        case .lyricsDark: return "歌词排版（深色）"
        case .lyricsCover: return "专辑封面"
        }
    }

    var widgetKind: String {
        // 拍立得保留原始 kind，避免迁移后已安装的组件失效。
        if self == .polaroid {
            return "zijiu.Monologue.com.widget.nowplaying"
        }
        return "zijiu.Monologue.com.widget.nowplaying.\(rawValue)"
    }

    var configurationDisplayName: String {
        "Mono · \(displayName)"
    }

    var configurationDescription: String {
        "显示\(displayName)主题的当前歌曲与播放控制"
    }

    var supportedFamilies: [WidgetFamily] {
        let homeScreenFamilies: [WidgetFamily] = [
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ]
        if self == .polaroid {
            return homeScreenFamilies + [
                .accessoryCircular,
                .accessoryRectangular,
            ]
        }
        return homeScreenFamilies
    }
}
