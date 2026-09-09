import Foundation
import QQMusicKit

/// qcm独立音质体系
/// 包装 QQMusicKit 的 SongFileType，提供 UI 显示信息
enum QQMusicQuality: String, CaseIterable, Codable, Sendable {
    case master = "MASTER"         // 臻品母带 24Bit 192kHz
    case dtsx = "DTS_X"            // DTS:X 臻品音效
    case atmos71 = "ATMOS_71"      // 臻品全景声 7.1
    case atmos2 = "ATMOS_2"        // 臻品全景声 16Bit 44.1kHz
    case atmos51 = "ATMOS_51"      // 臻品音质 16Bit 44.1kHz
    case nac = "NAC"               // 腾讯 AICodec
    case vinyl = "VINYL"           // 黑胶
    case flac = "FLAC"             // FLAC 无损 16Bit~24Bit
    case ogg640 = "OGG_640"        // OGG 640kbps
    case ogg320 = "OGG_320"        // OGG 320kbps
    case ogg192 = "OGG_192"        // OGG 192kbps
    case ogg96 = "OGG_96"          // OGG 96kbps
    case mp3_320 = "MP3_320"       // MP3 320kbps
    case mp3_128 = "MP3_128"       // MP3 128kbps
    case aac192 = "ACC_192"        // AAC 192kbps
    case aac96 = "ACC_96"          // AAC 96kbps
    case aac48 = "ACC_48"          // AAC 48kbps
    
    /// 对应的 QQMusicKit SongFileType
    var fileType: SongFileType {
        switch self {
        case .master:  return .master
        case .dtsx:    return .dtsx
        case .atmos71: return .atmos71
        case .atmos2:  return .atmos2
        case .atmos51: return .atmos51
        case .nac:     return .nac
        case .vinyl:   return .vinyl
        case .flac:    return .flac
        case .ogg640:  return .ogg640
        case .ogg320:  return .ogg320
        case .ogg192:  return .ogg192
        case .ogg96:   return .ogg96
        case .mp3_320: return .mp3_320
        case .mp3_128: return .mp3_128
        case .aac192:  return .aac192
        case .aac96:   return .aac96
        case .aac48:   return .aac48
        }
    }
    
    var displayName: String {
        switch self {
        case .master:  return String(localized: "臻品母带")
        case .dtsx:    return String(localized: "DTS:X 臻品音效")
        case .atmos71: return String(localized: "臻品全景声 7.1")
        case .atmos2:  return String(localized: "臻品全景声 2.0")
        case .atmos51: return String(localized: "臻品全景声 5.1")
        case .nac:     return String(localized: "腾讯 AICodec")
        case .vinyl:   return String(localized: "黑胶")
        case .flac:    return String(localized: "FLAC 无损")
        case .ogg640:  return String(localized: "OGG 臻品")
        case .ogg320:  return String(localized: "OGG 超品")
        case .ogg192:  return String(localized: "OGG 高品")
        case .ogg96:   return String(localized: "OGG 标准")
        case .mp3_320: return String(localized: "MP3 高品")
        case .mp3_128: return String(localized: "MP3 标准")
        case .aac192:  return String(localized: "AAC 高品")
        case .aac96:   return String(localized: "AAC 标准")
        case .aac48:   return String(localized: "AAC 流畅")
        }
    }
    
    var subtitle: String {
        switch self {
        case .master:  return "24Bit 192kHz"
        case .dtsx:    return String(localized: "多声道空间音频")
        case .atmos71: return String(localized: "7.1 声道空间音频")
        case .atmos2:  return String(localized: "2.0 声道空间音频")
        case .atmos51: return String(localized: "5.1 声道空间音频")
        case .nac:     return String(localized: "AI 增强解码")
        case .vinyl:   return String(localized: "原始模拟质感")
        case .flac:    return String(localized: "16Bit~24Bit 无损")
        case .ogg640:  return "640kbps"
        case .ogg320:  return "320kbps"
        case .ogg192:  return "192kbps"
        case .ogg96:   return "96kbps"
        case .mp3_320: return "320kbps"
        case .mp3_128: return "128kbps"
        case .aac192:  return "192kbps"
        case .aac96:   return "96kbps"
        case .aac48:   return "48kbps"
        }
    }
    
    var badgeText: String? {
        switch self {
        case .master:
            return String(localized: "eq_workspace_professional_mastering")
        case .dtsx:
            return "DTS"
        case .atmos71, .atmos2:
            return String(localized: "全景声")
        case .atmos51, .nac:
            return String(localized: "臻品")
        case .vinyl:
            return String(localized: "黑胶")
        case .flac, .ogg640:
            return "SQ"
        case .ogg320, .mp3_320, .aac192:
            return "HQ"
        case .ogg192:
            return "OGG 192"
        case .ogg96:
            return "OGG 96"
        case .mp3_128:
            return "MP3 128"
        case .aac96:
            return "AAC 96"
        case .aac48:
            return "AAC 48"
        }
    }
    
    var level: Int {
        switch self {
        case .dtsx:    return 18
        case .master:  return 15
        case .atmos71: return 14
        case .atmos2:  return 12
        case .atmos51: return 11
        case .nac:     return 10
        case .vinyl:   return 9
        case .flac:    return 8
        case .ogg640:  return 7
        case .ogg320:  return 6
        case .mp3_320: return 5
        case .ogg192:  return 4
        case .aac192:  return 3
        case .mp3_128: return 2
        case .ogg96:   return 1
        case .aac96:   return 0
        case .aac48:   return -1
        }
    }
    
    /// 对应的加密文件类型（仅高级音质有加密版本）
    var encryptedFileType: EncryptedSongFileType? {
        switch self {
        case .master:  return .master
        case .dtsx:    return .dtsx
        case .atmos71: return .atmos71
        case .atmos2:  return .atmos2
        case .atmos51: return .atmos51
        case .nac:     return .nac
        case .vinyl:   return .vinyl
        case .flac:    return .flac
        case .ogg640:  return .ogg640
        case .ogg320:  return .ogg320
        case .ogg192:  return .ogg192
        case .ogg96:   return .ogg96
        default:       return nil
        }
    }
    
    /// 是否为加密音质（需要 ekey 解密）
    var isEncrypted: Bool {
        switch self {
        case .dtsx, .master, .atmos71, .atmos2, .atmos51, .nac, .vinyl:
            return true
        default:
            return false
        }
    }
    
    /// 常用音质选项（供快速选择使用）
    static var commonOptions: [QQMusicQuality] {
        [.master, .atmos2, .atmos51, .flac, .ogg640, .ogg320, .mp3_320, .mp3_128, .aac96]
    }
    
    static let descendingPreferenceOrder: [QQMusicQuality] = [
        .master, .atmos2, .atmos51, .flac, .ogg640, .ogg320,
        .mp3_320, .ogg192, .aac192, .mp3_128, .ogg96, .aac96, .aac48
    ]
    
    static func fallbackCandidates(from preferred: QQMusicQuality?) -> [QQMusicQuality] {
        // 普通播放直链不依赖 QMC 解密，Cookie 风控状态不能在这里提前删掉
        // 高音质候选。风控只用于决定普通直链全部失败后是否进入加密兜底。
        let order = descendingPreferenceOrder
        
        guard let preferred else {
            return order
        }
        
        // 未知档位回到完整的从高到低候选链。
        guard let startIndex = order.firstIndex(of: preferred) else {
            return order
        }
        
        return Array(order[startIndex...])
    }
    
    static func nextLower(than quality: QQMusicQuality) -> QQMusicQuality? {
        let candidates = fallbackCandidates(from: quality)
        guard candidates.count > 1 else { return nil }
        return candidates[1]
    }
}
