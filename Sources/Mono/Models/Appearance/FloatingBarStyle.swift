import Foundation

/// 悬浮栏样式枚举
enum FloatingBarStyle: String, Codable, CaseIterable, Identifiable {
    case unified     // 统一悬浮栏 - MiniPlayer + TabBar 合一
    case classic     // 经典模式 - 贴底不悬浮
    case minimal     // 极简模式 - 仅 MiniPlayer，无 TabBar（手势切换页面）
    case floatingBall // 悬浮球 - 黑胶唱片悬浮球 + 抽屉式 Tab
    case flux        // 云雾模式 - GPU 雾化彩色材质 TabBar（保留 rawValue 兼容旧设置）
    case liquid      // 液态模式 - 播放进度以有黏性的液体形态推进
    case vinylNeedle // 黑胶唱针 - 旋转黑胶与唱针轨迹
    case cassette    // 双轮磁带 - 磁带轮与带体进度
    case orbit       // 星环轨道 - 星体与轨道进度
    case waveform    // 实时声纹 - 播放声纹与进度
    case filmstrip   // 电影胶片 - 胶片格与时间码
    case studioMeter // 金属仪表 - VU 指针与机械刻度
    
    var id: String { rawValue }

    var isSignatureStyle: Bool {
        switch self {
        case .vinylNeedle, .cassette, .orbit, .waveform, .filmstrip, .studioMeter: true
        default: false
        }
    }

    
    var displayName: String {
        switch self {
        case .unified:      return NSLocalizedString("floating_bar_unified", comment: "")
        case .classic:      return NSLocalizedString("floating_bar_classic", comment: "")
        case .minimal:      return NSLocalizedString("floating_bar_minimal", comment: "")
        case .floatingBall: return NSLocalizedString("floating_bar_ball", comment: "")
        case .flux:         return NSLocalizedString("floating_bar_flux", comment: "")
        case .liquid:       return NSLocalizedString("floating_bar_liquid", comment: "")
        case .vinylNeedle:  return NSLocalizedString("floating_bar_vinyl", comment: "")
        case .cassette:     return NSLocalizedString("floating_bar_cassette", comment: "")
        case .orbit:        return NSLocalizedString("floating_bar_orbit", comment: "")
        case .waveform:     return NSLocalizedString("floating_bar_waveform", comment: "")
        case .filmstrip:    return NSLocalizedString("floating_bar_filmstrip", comment: "")
        case .studioMeter:  return NSLocalizedString("floating_bar_meter", comment: "")
        }
    }
    
    var description: String {
        switch self {
        case .unified:      return NSLocalizedString("floating_bar_unified_desc", comment: "")
        case .classic:      return NSLocalizedString("floating_bar_classic_desc", comment: "")
        case .minimal:      return NSLocalizedString("floating_bar_minimal_desc", comment: "")
        case .floatingBall: return NSLocalizedString("floating_bar_ball_desc", comment: "")
        case .flux:         return NSLocalizedString("floating_bar_flux_desc", comment: "")
        case .liquid:       return NSLocalizedString("floating_bar_liquid_desc", comment: "")
        case .vinylNeedle:  return NSLocalizedString("floating_bar_vinyl_desc", comment: "")
        case .cassette:     return NSLocalizedString("floating_bar_cassette_desc", comment: "")
        case .orbit:        return NSLocalizedString("floating_bar_orbit_desc", comment: "")
        case .waveform:     return NSLocalizedString("floating_bar_waveform_desc", comment: "")
        case .filmstrip:    return NSLocalizedString("floating_bar_filmstrip_desc", comment: "")
        case .studioMeter:  return NSLocalizedString("floating_bar_meter_desc", comment: "")
        }
    }
    
    var iconType: MonoIcon.IconType {
        switch self {
        case .unified:      return .layers
        case .classic:      return .tabBar
        case .minimal:      return .minimalBar
        case .floatingBall: return .floatingBall
        case .flux:         return .waveform
        case .liquid:       return .audioWave
        case .vinylNeedle:  return .album
        case .cassette:     return .musicNoteList
        case .orbit:        return .catStar
        case .waveform:     return .waveform
        case .filmstrip:    return .mv
        case .studioMeter:  return .equalizer
        }
    }
}
