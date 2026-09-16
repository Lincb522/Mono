import Foundation

/// 播放器主题枚举
enum PlayerTheme: String, Codable, CaseIterable, Identifiable {
    case classic     // 经典 - 大封面居中
    case vinyl       // 黑胶唱片 - 旋转唱片效果
    case lyricFocus  // 歌词 - 歌词瀑布流 + 打字机风格
    case card        // 卡片 - 圆形封面 + 白色卡片 + 渐变背景
    case neumorphic        // 新拟物 - 柔和阴影立体感
    case poster            // 海报 - 全屏封面海报风格
    case motoPager         // 寻呼机 - 复古小票打印风格
    case typewriter        // 打字机 - 纸页与机械键帽
    case pixel             // 像素 - 8-bit 复古游戏风格
    case aqua              // 水韵 - 水波纹沉浸式播放器
    case breathing         // 呼吸体 - 没有常规控件的声音核心
    case bloud             // 圆形角色与随音乐变化的表情
    case cassette          // 磁带 - 精致复古纯平几何像素风
    case radio             // 收音机 - 横向卡片式复古收音机
    case immersiveLyric    // 沉浸歌词 - 顶部小图大字纯净版
    case folk              // 民谣 - 旅行手记笔记本风格
    case game2048          // 2048 - 数字方块游戏风格
    case ipod              // iPod - 单色屏幕与实体转盘
    case liquidGlass       // 液态玻璃 - 全玻璃材质与封面动态取色
    case tornPaper         // 撕页 - 系统主体抠图与撕纸拼贴
    case clarity           // 通透 - 空气光层、漂浮封面与独立控制界面
    case dotMatrix         // 点阵 - 动态九点信号与分段式播放控制
    case console           // 控制台 - 黑绿终端与实时信号灯
    case muji              // 无印良品全局主题播放器
    case capsule           // Capsule OS 全局主题播放器
    case petWhite          // 白绒爪印全局主题播放器
    case minimalWhite      // 纯白极简全局主题播放器
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .classic:    return String(localized: "经典")
        case .vinyl:      return String(localized: "黑胶")
        case .lyricFocus: return String(localized: "歌词")
        case .card:       return String(localized: "卡片")
        case .neumorphic: return String(localized: "新拟物")
        case .poster:     return String(localized: "海报")
        case .motoPager:  return String(localized: "寻呼机")
        case .typewriter: return String(localized: "打字机")
        case .pixel:      return String(localized: "像素")
        case .aqua:       return String(localized: "水韵")
        case .breathing:  return String(localized: "呼吸体")
        case .bloud:      return "BLOUD"
        case .cassette:   return String(localized: "磁带")
        case .radio:      return String(localized: "收音机")
        case .immersiveLyric: return String(localized: "沉浸歌词")
        case .folk:       return String(localized: "信笺")
        case .game2048:   return String(localized: "2048")
        case .ipod:       return "iPod"
        case .liquidGlass: return String(localized: "液态玻璃")
        case .tornPaper: return String(localized: "撕页")
        case .clarity: return String(localized: "通透")
        case .dotMatrix: return String(localized: "点阵")
        case .console: return String(localized: "player_theme_console_name")
        case .muji: return String(localized: "无印良品")
        case .capsule: return "Capsule OS"
        case .petWhite: return String(localized: "global_theme_pet_white_name")
        case .minimalWhite: return String(localized: "global_theme_minimal_white_name")
        }
    }
    
    var iconName: String {
        switch self {
        case .classic:    return "square.fill"
        case .vinyl:      return "record.circle"
        case .lyricFocus: return "text.quote"
        case .card:       return "rectangle.portrait.fill"
        case .neumorphic: return "circle.circle"
        case .poster:     return "photo.fill"
        case .motoPager:  return "printer.fill"
        case .typewriter: return "keyboard.fill"
        case .pixel:      return "square.grid.3x3.fill"
        case .aqua:       return "drop.fill"
        case .breathing:  return "dot.radiowaves.left.and.right"
        case .bloud:      return "face.smiling"
        case .cassette:   return "play.rectangle.fill"
        case .radio:      return "radio.fill"
        case .immersiveLyric: return "music.note.list"
        case .folk:       return "envelope.fill"
        case .game2048:   return "square.grid.2x2.fill"
        case .ipod:       return "ipod"
        case .liquidGlass: return "drop.circle.fill"
        case .tornPaper: return "doc.richtext.fill"
        case .clarity: return "circle.hexagongrid.fill"
        case .dotMatrix: return "circle.grid.3x3.fill"
        case .console: return "terminal.fill"
        case .muji: return "leaf.fill"
        case .capsule: return "capsule.fill"
        case .petWhite: return "pawprint.fill"
        case .minimalWhite: return "circle.dotted"
        }
    }
    
    var description: String {
        switch self {
        case .classic:    return String(localized: "大封面居中，经典播放器布局")
        case .vinyl:      return String(localized: "黑胶唱片旋转效果，复古氛围")
        case .lyricFocus: return String(localized: "歌词瀑布流，打字机风格，逐字高亮")
        case .card:       return String(localized: "圆形封面卡片，渐变背景")
        case .neumorphic: return String(localized: "新拟物化设计，柔和阴影立体感")
        case .poster:     return String(localized: "全屏封面海报，沉浸式视觉体验")
        case .motoPager:  return String(localized: "复古寻呼机，打印小票式歌词显示")
        case .typewriter: return String(localized: "复古打字机，纸页歌词与机械键帽控制")
        case .pixel:      return String(localized: "8-bit 像素风格，复古游戏机界面")
        case .aqua:       return String(localized: "水波纹沉浸式，如水杯般宁静流动")
        case .breathing:  return "No controls, just a living audio core"
        case .bloud:      return String(localized: "player_bloud_description")
        case .cassette:   return String(localized: "复古扁平磁带，极其精致的纯平几何重构")
        case .radio:      return String(localized: "复古收音机，横向卡片式 LED 点阵与扬声器")
        case .immersiveLyric: return String(localized: "沉浸歌词，顶部小图大字纯净版")
        case .folk:       return String(localized: "诗集信笺，非常规打字机逐行出现的打字信件")
        case .game2048:   return String(localized: "2048 方块游戏，滑动切歌点击方块控制")
        case .ipod:       return "单色屏幕、实体转盘与硬件播放器布局"
        case .liquidGlass: return String(localized: "全液态玻璃界面，随歌曲封面动态折射取色")
        case .tornPaper: return String(localized: "从封面提取主体，以撕纸拼贴重新组织歌曲与歌词")
        case .clarity: return String(localized: "空气光层、漂浮封面与独立控制界面")
        case .dotMatrix: return String(localized: "动态点阵信号、分段进度与独立控制界面")
        case .console: return String(localized: "player_theme_console_description")
        case .muji: return String(localized: "极简纸质感，温暖呼吸感")
        case .capsule: return String(localized: "胶囊模块化音乐系统")
        case .petWhite: return String(localized: "global_theme_pet_white_description")
        case .minimalWhite: return String(localized: "global_theme_minimal_white_description")
        }
    }
    
    /// 是否自带自定义的不透明背景。自带背景的主题将不受全局封面亮度控制影响。
    var hasCustomBackground: Bool {
        switch self {
        case .classic, .vinyl, .lyricFocus, .poster, .breathing, .immersiveLyric:
            return false // 依赖全局模糊封面背景
        case .card, .neumorphic, .motoPager, .typewriter, .pixel, .aqua, .bloud, .cassette, .radio, .folk, .game2048, .ipod, .liquidGlass, .tornPaper, .clarity, .dotMatrix, .console, .muji, .capsule, .petWhite, .minimalWhite:
            return true  // 自带不透明的自定义背景
        }
    }
}
