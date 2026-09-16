import Foundation

/// PAW has its own expressions and geometry, authored in the dog's 120-point canvas.
enum PawExpression: String, CaseIterable, Identifiable, Sendable {
    case soft, bright, beaming, delighted, curious, listening, hopeful, bashful
    case cozy, drowsy, sleeping, puzzled, pout, pleading, unimpressed, sulky
    case astonished, alert, playful, wink, blep, proud, dreamy, affectionate

    var id: String { rawValue }
    var title: String { NSLocalizedString("player_paw_expression_\(rawValue)", comment: "PAW expression") }

    var pose: PawFacePose {
        switch self {
        case .soft:
            return .init()
        case .bright:
            return .init(left: .init(closed: 0.28, curve: 0.55, shine: 0.4), right: .init(closed: 0.28, curve: 0.55, shine: 0.4), smile: 0.75, blush: 0.7)
        case .beaming:
            return .init(left: .init(closed: 0.94, curve: 1), right: .init(closed: 0.94, curve: 1), smile: 1, blush: 0.8)
        case .delighted:
            return .init(left: .init(width: 11, closed: 0.88, curve: 1), right: .init(width: 11, closed: 0.88, curve: 1), earLeft: -0.1, earRight: -0.1, smile: 1, open: 0.75, blush: 0.8)
        case .curious:
            return .init(left: .init(height: 11.8, shine: 0.35), right: .init(height: 10.2, shine: 0.35), browLeft: -1.2, earLeft: -0.15, earRight: 0.18, smile: 0.15, tilt: -3.5, lookX: -0.12)
        case .listening:
            return .init(left: .init(width: 9.8, height: 11.6, shine: 0.2), right: .init(width: 9.8, height: 11.6, shine: 0.2), browLeft: -0.5, browRight: -0.5, earLeft: -0.18, earRight: -0.18, smile: 0.1)
        case .hopeful:
            return .init(left: .init(width: 11.6, height: 12.4, lift: -0.6, shine: 1), right: .init(width: 11.6, height: 12.4, lift: -0.6, shine: 1), browLeft: -1.4, browRight: -1.4, smile: 0.45, blush: 0.65, lookY: -0.1)
        case .bashful:
            return .init(left: .init(width: 9.5, closed: 0.42, curve: 0.55), right: .init(width: 9.5, closed: 0.42, curve: 0.55), earLeft: 0.18, earRight: 0.18, smile: 0.4, blush: 1, tilt: 2, lookX: 0.12, lookY: 0.1)
        case .cozy:
            return .init(left: .init(closed: 0.82, curve: 0.85), right: .init(closed: 0.82, curve: 0.85), earLeft: 0.22, earRight: 0.22, smile: 0.6, blush: 0.6)
        case .drowsy:
            return .init(left: .init(closed: 0.64, curve: -0.2), right: .init(closed: 0.72, curve: -0.2), browLeft: 0.6, browRight: 0.6, earLeft: 0.32, earRight: 0.38, smile: 0.05, tilt: 2)
        case .sleeping:
            return .init(left: .init(closed: 1, curve: -0.55), right: .init(closed: 1, curve: -0.55), browLeft: 0.8, browRight: 0.8, earLeft: 0.42, earRight: 0.42, smile: 0.1, blush: 0.3, tilt: 2.5)
        case .puzzled:
            return .init(left: .init(height: 11.8, shine: 0.3), right: .init(closed: 0.3, tilt: -3), browLeft: -1.8, browRight: 0.4, earLeft: -0.1, earRight: 0.3, smile: -0.1, skew: 0.5, tilt: 3)
        case .pout:
            return .init(left: .init(width: 10, height: 11.6, tilt: -3, shine: 0.65), right: .init(width: 10, height: 11.6, tilt: 3, shine: 0.65), browLeft: -0.7, browRight: -0.7, earLeft: 0.35, earRight: 0.35, smile: -0.65, blush: 0.65)
        case .pleading:
            return .init(left: .init(width: 12, height: 12.8, tilt: -2, shine: 1), right: .init(width: 12, height: 12.8, tilt: 2, shine: 1), browLeft: -1.6, browRight: -1.6, earLeft: 0.15, earRight: 0.15, smile: -0.15, blush: 0.85, tilt: -2, lookY: -0.12)
        case .unimpressed:
            return .init(left: .init(closed: 0.4, curve: -0.15), right: .init(closed: 0.53, curve: -0.15), browRight: 0.5, earRight: 0.2, smile: -0.2, skew: 0.7, lookX: 0.18)
        case .sulky:
            return .init(left: .init(closed: 0.45, tilt: 4), right: .init(closed: 0.45, tilt: -4), browLeft: 0.4, browRight: 0.4, earLeft: 0.22, earRight: 0.22, smile: -0.55, skew: -0.4, blush: 0.8, tilt: -2, lookX: -0.15)
        case .astonished:
            return .init(left: .init(width: 11.6, height: 12.4, shine: 0.65), right: .init(width: 11.6, height: 12.4, shine: 0.65), browLeft: -1.8, browRight: -1.8, earLeft: -0.15, earRight: -0.15, open: 0.55, round: 1, blush: 0.35)
        case .alert:
            return .init(left: .init(width: 10, height: 12, shine: 0.5), right: .init(width: 10, height: 12, shine: 0.5), browLeft: -1, browRight: -1, earLeft: -0.22, earRight: -0.22, smile: 0.2, tilt: 1.5, lookX: 0.1)
        case .playful:
            return .init(left: .init(closed: 0.65, curve: 0.9), right: .init(height: 11.4, shine: 0.65), earLeft: 0.15, earRight: -0.12, smile: 0.8, blush: 0.8, tongue: 0.45, tilt: -3)
        case .wink:
            return .init(left: .init(closed: 1, curve: 0.85), right: .init(width: 10.8, height: 11.6, shine: 0.65), browLeft: 0.4, browRight: -0.5, smile: 0.65, blush: 0.7, tilt: 2)
        case .blep:
            return .init(left: .init(closed: 0.08, shine: 0.3), right: .init(closed: 0.08, shine: 0.3), smile: 0.45, blush: 0.7, tongue: 0.8)
        case .proud:
            return .init(left: .init(closed: 0.58, curve: 0.7), right: .init(closed: 0.58, curve: 0.7), browLeft: -0.5, browRight: -0.5, earLeft: -0.12, earRight: -0.12, smile: 0.65, skew: 0.4, tilt: -1.5)
        case .dreamy:
            return .init(left: .init(closed: 0.25, lift: -0.3, shine: 0.8), right: .init(closed: 0.25, lift: -0.3, shine: 0.8), earLeft: 0.08, earRight: 0.08, smile: 0.2, blush: 0.5, tilt: -2, lookX: -0.12, lookY: -0.16)
        case .affectionate:
            return .init(left: .init(closed: 0.72, curve: 0.9), right: .init(closed: 0.72, curve: 0.9), earLeft: 0.2, earRight: 0.2, smile: 0.8, blush: 1, tilt: 2.5)
        }
    }
}

struct PawEyePose: Equatable, Sendable {
    var width: Double = 10.5
    var height: Double = 11
    var closed: Double = 0
    var curve: Double = 0
    var tilt: Double = 0
    var lift: Double = 0
    var shine: Double = 0

    func blended(to other: Self, fraction t: Double) -> Self {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return .init(width: mix(width, other.width), height: mix(height, other.height),
                     closed: mix(closed, other.closed), curve: mix(curve, other.curve),
                     tilt: mix(tilt, other.tilt), lift: mix(lift, other.lift), shine: mix(shine, other.shine))
    }
}

struct PawFacePose: Equatable, Sendable {
    var left: PawEyePose = .init()
    var right: PawEyePose = .init()
    var browLeft: Double = 0
    var browRight: Double = 0
    var earLeft: Double = 0
    var earRight: Double = 0
    var smile: Double = 0.2
    var open: Double = 0
    var round: Double = 0
    var skew: Double = 0
    var blush: Double = 0.45
    var tongue: Double = 0
    var tilt: Double = 0
    var lookX: Double = 0
    var lookY: Double = 0

    func blended(to other: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        if t == 0 { return self }
        if t == 1 { return other }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return .init(left: left.blended(to: other.left, fraction: t), right: right.blended(to: other.right, fraction: t),
                     browLeft: mix(browLeft, other.browLeft), browRight: mix(browRight, other.browRight),
                     earLeft: mix(earLeft, other.earLeft), earRight: mix(earRight, other.earRight),
                     smile: mix(smile, other.smile), open: mix(open, other.open), round: mix(round, other.round),
                     skew: mix(skew, other.skew), blush: mix(blush, other.blush), tongue: mix(tongue, other.tongue),
                     tilt: mix(tilt, other.tilt), lookX: mix(lookX, other.lookX), lookY: mix(lookY, other.lookY))
    }
}

/// Song tags choose a canine mood directly, without mapping another character's expressions.
enum PawTagExpression {
    static func resolve(_ tags: [String]) -> PawExpression? {
        let tags = SongGenreMetadata.clean(tags).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "‑", with: "-") }
        let rules: [(PawExpression, [String])] = [
            (.hopeful, ["motivational", "uplifting", "励志", "勵志"]),
            (.wink, ["cheeky", "俏皮"]),
            (.unimpressed, ["satire", "sarcastic", "讽刺", "諷刺"]),
            (.sleeping, ["sleep", "睡眠", "助眠"]),
            (.dreamy, ["dream pop", "shoegaze", "梦幻", "夢幻"]),
            (.cozy, ["ambient", "meditation", "chillout", "relax", "氛围", "氛圍", "冥想", "放松", "放鬆", "轻音乐", "輕音樂"]),
            (.drowsy, ["lofi", "lo-fi", "lo fi", "慵懒", "慵懶"]),
            (.alert, ["metal", "hardcore", "workout", "horror", "恐怖", "惊悚", "驚悚", "金属", "金屬", "硬核", "运动", "運動"]),
            (.puzzled, ["experimental", "avant-garde", "trip-hop", "trip hop", "实验", "實驗", "前卫", "前衛", "诡谲", "詭譎"]),
            (.delighted, ["funk", "disco", "comedy", "欢乐", "歡樂", "搞笑"]),
            (.playful, ["electronic", "electronica", "ska", "童趣", "edm", "dance", "house", "techno", "trance", "dubstep", "电子", "電子", "电音", "電音", "舞曲", "动感", "動感"]),
            (.proud, ["hip-hop", "hip hop", "hiphop", "rap", "trap", "嘻哈", "说唱", "說唱"]),
            (.curious, ["jazz", "爵士"]),
            (.listening, ["classical", "orchestral", "piano", "instrumental", "acoustic", "folk", "古典", "钢琴", "鋼琴", "纯音乐", "純音樂", "民谣", "民謠", "国风", "國風"]),
            (.astonished, ["soundtrack", "cinematic", "ost", "epic", "电影原声", "电影配乐", "壮阔", "壯闊", "影视原声", "影視原聲", "史诗", "史詩"]),
            (.pout, ["blues", "sad", "melancholy", "悲伤", "悲傷", "伤感", "傷感", "失恋", "失戀", "蓝调", "藍調"]),
            (.affectionate, ["ballad", "rnb", "r&b", "soul", "romantic", "情歌", "思念", "爱情", "愛情", "浪漫", "tender", "温柔", "溫柔", "温暖", "溫暖"]),
            (.bright, ["pop", "mandopop", "cantopop", "k-pop", "j-pop", "cpop", "kpop", "jpop", "rock", "punk", "流行", "摇滚", "搖滾", "欢快", "歡快"]),
            (.soft, ["calm", "easy listening", "安静", "安靜", "治愈", "治癒"])
        ]
        for (expression, aliases) in rules {
            if tags.contains(where: { tag in aliases.contains(where: { alias in
                if alias.unicodeScalars.contains(where: { $0.value > 127 }) { return tag.contains(alias) }
                let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: alias) + "(?![a-z0-9])"
                return tag.range(of: pattern, options: .regularExpression) != nil
            }) }) { return expression }
        }
        return nil
    }
}
