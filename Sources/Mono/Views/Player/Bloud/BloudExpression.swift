import Foundation

// Eye geometry and spherical projection adapted from jeremy-prt/bloub (MIT).
// The bundled Bloub-LICENSE.txt preserves the upstream copyright and license.
enum BloudExpression: String, CaseIterable, Identifiable, Sendable {
    case calm, attentive, surprised, excited, happy, laughing, angry, sad
    case scared, suspicious, confused, curious, proud, shy, bored, sleepy
    case dreamy, playful, determined, tender, amazed, skeptical, blissful, wink

    var id: String { rawValue }
    var title: String {
        NSLocalizedString("player_bloud_expression_\(rawValue)", comment: "Bloud expression")
    }

    var pose: BloudFacePose {
        switch self {
        case .calm: return .pair(28.49, 28.62, -13, 15.46, 0.186, 0.412)
        case .attentive: return .pair(4, 5, -4, 16, 0.21, 0.44)
        case .surprised: return .pair(3, -3, 0, 19, 0.45, 0.47)
        case .excited: return .pair(6, -14, 0, 19.5, 0.4, 0.56, tilt: -10)
        case .happy: return .pair(5, 9, 0, 17, 0.27, 0.17, tilt: 14)
        case .laughing: return .pair(4, 14, 0, 18, 0.34, 0.13, tilt: 20)
        case .angry: return .pair(3, 7, 0, 17, 0.34, 0.15, tilt: 30)
        case .sad: return .pair(3, -13, 0, 16, 0.22, 0.4, tilt: -28)
        case .scared: return .pair(2, -20, 0, 20.5, 0.4, 0.6)
        case .suspicious:
            return .init(yaw: 12, pitch: 6, roll: -6, split: 16,
                         left: .init(width: 0.21, height: 0.4), right: .init(width: 0.22, height: 0.15))
        case .confused:
            return .init(yaw: -14, pitch: 3, roll: 8, split: 16.5,
                         left: .init(width: 0.2, height: 0.44, tilt: -18),
                         right: .init(width: 0.28, height: 0.17, tilt: 14))
        case .curious:
            return .init(yaw: 16, pitch: -9, roll: -15, split: 16.5,
                         left: .init(width: 0.24, height: 0.46, tilt: -8),
                         right: .init(width: 0.2, height: 0.38, tilt: -8))
        case .proud: return .pair(5, 17, 0, 17, 0.3, 0.15, tilt: 18)
        case .shy: return .pair(-19, -14, -7, 14, 0.17, 0.3)
        case .bored: return .pair(-22, 2, 0, 16, 0.3, 0.12)
        case .sleepy: return .pair(6, -9, -3, 16, 0.2, 0.42, open: 0.42)
        case .dreamy: return .pair(-8, -8, -4, 17, 0.26, 0.32, tilt: -6, open: 0.65)
        case .playful:
            return .init(yaw: 8, pitch: 6, roll: 4, split: 17,
                         left: .init(width: 0.3, height: 0.19, tilt: 12),
                         right: .init(width: 0.24, height: 0.35, tilt: -8))
        case .determined: return .pair(0, 5, 0, 18, 0.32, 0.21, tilt: 17)
        case .tender: return .pair(-5, -2, -3, 15, 0.24, 0.3, tilt: -12)
        case .amazed: return .pair(0, -12, 0, 20, 0.36, 0.54)
        case .skeptical:
            return .init(yaw: -10, pitch: 4, roll: 3, split: 17,
                         left: .init(width: 0.3, height: 0.15, tilt: 8),
                         right: .init(width: 0.23, height: 0.34, tilt: -15))
        case .blissful: return .pair(0, 11, 0, 17, 0.31, 0.16, tilt: 9, open: 0.75)
        case .wink:
            return .init(yaw: 4, pitch: 2, roll: -3, split: 17,
                         left: .init(width: 0.29, height: 0.1, tilt: 10),
                         right: .init(width: 0.24, height: 0.42, tilt: -4))
        }
    }
}

struct BloudEye: Equatable, Sendable {
    var width: Double
    var height: Double
    var tilt: Double = 0
    var open: Double = 1
}

struct BloudFacePose: Equatable, Sendable {
    var yaw: Double
    var pitch: Double
    var roll: Double
    var split: Double
    var left: BloudEye
    var right: BloudEye

    static func pair(_ yaw: Double, _ pitch: Double, _ roll: Double, _ split: Double,
                     _ width: Double, _ height: Double, tilt: Double = 0, open: Double = 1) -> Self {
        .init(yaw: yaw, pitch: pitch, roll: roll, split: split,
              left: .init(width: width, height: height, tilt: tilt, open: open),
              right: .init(width: width, height: height, tilt: -tilt, open: open))
    }

    func blended(to other: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        if t == 0 { return self }
        if t == 1 { return other }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func eye(_ a: BloudEye, _ b: BloudEye) -> BloudEye {
            .init(width: mix(a.width, b.width), height: mix(a.height, b.height),
                  tilt: mix(a.tilt, b.tilt), open: mix(a.open, b.open))
        }
        return .init(yaw: mix(yaw, other.yaw), pitch: mix(pitch, other.pitch),
                     roll: mix(roll, other.roll), split: mix(split, other.split),
                     left: eye(left, other.left), right: eye(right, other.right))
    }
}

/// Specific provider style/mood tags win over broad labels such as Pop.
enum BloudTagExpression {
    static func resolve(_ tags: [String]) -> BloudExpression? {
        let normalized = SongGenreMetadata.clean(tags).map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "‑", with: "-")
        }
        let rules: [(BloudExpression, [String])] = [
            (.dreamy, ["dream pop", "shoegaze", "梦幻", "夢幻"]),
            (.playful, ["funk", "disco", "ska", "童趣"]),
            (.determined, ["workout", "motivational", "励志", "勵志", "运动", "運動"]),
            (.amazed, ["epic", "壮阔", "壯闊"]),
            (.skeptical, ["satire", "sarcastic", "讽刺", "諷刺"]),
            (.wink, ["cheeky", "俏皮"]),
            (.scared, ["dark ambient", "horror", "恐怖", "惊悚", "驚悚"]),
            (.angry, ["metal", "hardcore", "金属", "金屬", "硬核"]),
            (.suspicious, ["trip-hop", "trip hop", "诡谲", "詭譎"]),
            (.confused, ["experimental", "avant-garde", "实验", "實驗", "前卫", "前衛"]),
            (.sleepy, ["ambient", "meditation", "sleep", "氛围", "氛圍", "冥想", "睡眠", "助眠"]),
            (.bored, ["lofi", "lo-fi", "lo fi", "慵懒", "慵懶"]),
            (.proud, ["hiphop", "hip-hop", "hip hop", "rap", "trap", "嘻哈", "说唱", "說唱"]),
            (.excited, ["electronic", "electronica", "edm", "dance", "house", "techno", "trance", "dubstep",
                        "rock", "punk", "电子", "電子", "电音", "電音", "舞曲", "摇滚", "搖滾", "动感", "動感"]),
            (.curious, ["jazz", "爵士"]),
            (.attentive, ["classical", "orchestral", "piano", "instrumental", "acoustic", "folk",
                         "古典", "钢琴", "鋼琴", "纯音乐", "純音樂", "民谣", "民謠", "国风", "國風"]),
            (.surprised, ["soundtrack", "cinematic", "ost", "影视原声", "影視原聲", "电影原声", "电影配乐", "史诗", "史詩"]),
            (.laughing, ["comedy", "搞笑", "欢乐", "歡樂"]),
            (.sad, ["blues", "sad", "melancholy", "蓝调", "藍調", "悲伤", "悲傷", "伤感", "傷感", "失恋", "失戀"]),
            (.shy, ["ballad", "rnb", "r&b", "soul", "romantic", "情歌", "思念", "爱情", "愛情", "浪漫"]),
            (.tender, ["tender", "温柔", "溫柔", "温暖", "溫暖"]),
            (.blissful, ["chillout", "relax", "放松", "放鬆", "惬意", "愜意"]),
            (.calm, ["calm", "easy listening", "轻音乐", "輕音樂", "安静", "安靜", "治愈", "治癒"]),
            (.happy, ["pop", "mandopop", "cantopop", "k-pop", "j-pop", "cpop", "kpop", "jpop", "流行", "欢快", "歡快"])
        ]
        for (expression, aliases) in rules {
            if normalized.contains(where: { tag in aliases.contains(where: { matches($0, in: tag) }) }) {
                return expression
            }
        }
        return nil
    }

    private static func matches(_ alias: String, in tag: String) -> Bool {
        if alias.unicodeScalars.contains(where: { $0.value > 127 }) { return tag.contains(alias) }
        let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: alias) + "(?![a-z0-9])"
        return tag.range(of: pattern, options: .regularExpression) != nil
    }
}
