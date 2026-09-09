import Foundation

// MARK: - 核心歌曲模型

/// 跨音乐平台共用的歌曲模型。
///
/// ncm 字段作为基础结构，qcm、qsm、Apple Music、本地文件与播客信息
/// Platform identity keeps numeric catalog IDs in their own namespaces.
struct Song: Identifiable, Codable, Hashable, Equatable, Sendable {
    static func == (lhs: Song, rhs: Song) -> Bool { lhs.identityKey == rhs.identityKey }
    func hash(into hasher: inout Hasher) { hasher.combine(identityKey) }

    var identityKey: String { "\(musicSource.rawValue):\(id)" }
    
    let id: Int
    let name: String
    let ar: [Artist]?
    let al: Album?
    let dt: Int?
    let fee: Int?
    let mv: Int?
    
    let h: SongQuality?
    let m: SongQuality?
    let l: SongQuality?
    let sq: SongQuality?
    let hr: SongQuality?
    
    let alia: [String]?
    var privilege: Privilege?
    
    /// 播客节目封面（非 API 字段，手动注入）
    var podcastCoverUrl: String?
    
    /// 播客电台 ID（非 API 字段，手动注入）
    var podcastRadioId: Int?
    
    /// 播客电台名称（非 API 字段，手动注入）
    var podcastRadioName: String?
    
    // MARK: - qcm 扩展字段
    /// 音乐来源平台
    var source: MusicSource?
    /// qcm 歌曲 mid（用于获取播放 URL）
    var qqMid: String?
    /// qcm 专辑 mid
    var qqAlbumMid: String?
    /// qcm 歌手 mid（用于跳转歌手详情页）
    var qqArtistMid: String?
    /// qcm 最高可用音质（从搜索结果 file 字段解析）
    var qqMaxQuality: QQMusicQuality?
    /// qcm 是否为数字专辑（需单独购买，VIP 也不能解锁）
    /// 仅当 `pay.pay_album == 1` 时置 true（勿用 price 字段，易误伤整列表）
    var qqIsDigitalAlbum: Bool?
    /// 本地导入音乐的相对文件路径
    var localRelativePath: String?
    /// 本地导入时间
    var localImportedAt: Date?
    
    // MARK: - 汽水音乐扩展字段
    /// 汽水音乐 track ID
    var qishuiTrackId: Int?

    // MARK: - 酷狗音乐扩展字段
    /// 酷狗文件 Hash，用于播放地址与歌词查询。
    var kugouHash: String?
    /// 酷狗专辑 ID。
    var kugouAlbumID: Int?
    /// 酷狗 MixSongID / album_audio_id。
    var kugouAlbumAudioID: Int?

    // MARK: - Apple Music 扩展字段
    /// Apple Music 目录歌曲 ID。保留字符串形式以兼容非数字 ID。
    var appleMusicID: String?
    /// Apple Music ISRC，用于目录恢复和跨来源精确匹配。
    var appleMusicISRC: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, ar, al, dt, fee, mv
        case h, m, l, sq, hr, alia, privilege
        case source, qqMid, qqAlbumMid, qqArtistMid, qqMaxQuality, qqIsDigitalAlbum
        case localRelativePath, localImportedAt
        case qishuiTrackId
        case kugouHash, kugouAlbumID, kugouAlbumAudioID
        case appleMusicID, appleMusicISRC
        case podcastCoverUrl
        case podcastRadioId
        case podcastRadioName
    }
    
    // MARK: - 辅助属性
    var artists: [Artist] { ar ?? [] }
    var album: Album? { al }
    
    private var inferredLegacySource: MusicSource? {
        if source == nil, let kugouHash, !kugouHash.isEmpty {
            return .kugou
        }

        if source == nil, let qishuiTrackId, qishuiTrackId > 0 {
            return .qishui
        }
        
        guard source == nil, let qqMid, !qqMid.isEmpty else { return nil }

        // 兼容旧本地歌单/导入数据：部分 qcm 歌缺少 source，但仍保留 qqMid 与 qcm CDN 封面。
        if let picUrl = al?.picUrl?.lowercased(),
           picUrl.contains("gtimg.cn") || picUrl.contains("qpic.cn") {
            return .qqmusic
        }

        let hasNeteaseStreamMetadata =
            h != nil || m != nil || l != nil || sq != nil || hr != nil || privilege != nil
        return hasNeteaseStreamMetadata ? nil : .qqmusic
    }

    /// 实际音乐来源（默认 ncm）
    var musicSource: MusicSource {
        if let s = source { return s }
        if let inferred = inferredLegacySource { return inferred }
        return .netease
    }
    
    /// 是否为 qcm 歌曲
    var isQQMusic: Bool { musicSource == .qqmusic }

    /// 是否为汽水音乐歌曲
    var isQishui: Bool { musicSource == .qishui }

    /// 是否为酷狗音乐歌曲
    var isKugou: Bool { musicSource == .kugou }

    /// 是否为 Apple Music 歌曲
    var isAppleMusic: Bool { musicSource == .appleMusic }

    var appleMusicCatalogID: String? {
        guard isAppleMusic else { return nil }
        if let appleMusicID, !appleMusicID.isEmpty {
            return appleMusicID
        }
        return String(id)
    }

    /// 是否为本地导入歌曲
    var isLocal: Bool { musicSource == .local }
    
    var artistName: String {
        (ar ?? []).map { $0.name }.joined(separator: ", ")
    }
    
    var artworkURLCandidates: [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ rawValue: String?) {
            guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            if value.hasPrefix("//") {
                value = "https:\(value)"
            } else if value.hasPrefix("http://") {
                value = "https://\(value.dropFirst("http://".count))"
            }
            guard let url = URL(string: value), seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }

        // QQ 接口的直接图片字段常只有 180/300px，甚至部分接口不返回图片字段。
        // 歌曲模型已经保留了专辑 MID，优先据此生成稳定的高清 CDN 地址。
        if isQQMusic {
            if let albumMid = qqAlbumMid?.trimmingCharacters(in: .whitespacesAndNewlines),
               !albumMid.isEmpty {
                append("https://y.gtimg.cn/music/photo_new/T002R800x800M000\(albumMid).jpg")
            }
            append(al?.picUrl)
            if let artistMid = qqArtistMid?.trimmingCharacters(in: .whitespacesAndNewlines),
               !artistMid.isEmpty {
                append("https://y.gtimg.cn/music/photo_new/T001R800x800M000\(artistMid).jpg")
            }
        }

        append(al?.picUrl)
        append(podcastCoverUrl)
        return urls
    }

    var coverUrl: URL? {
        artworkURLCandidates.first
    }

    var localFileURL: URL? {
        guard let localRelativePath, !localRelativePath.isEmpty else { return nil }
        let fileURL = LocalMusicLibraryManager.musicDirectory.appendingPathComponent(localRelativePath)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    var isVIP: Bool {
        return fee == 1
    }
    
    var maxQuality: SoundQuality {
        var candidates: [SoundQuality] = []

        if let p = privilege {
            candidates.append(contentsOf: [
                p.downloadMaxBrLevel,
                p.playMaxBrLevel,
                p.maxBrLevel,
                p.dlLevel,
                p.plLevel,
                p.flLevel
            ].compactMap { $0 })
        }

        if hr != nil {
            candidates.append(.hires)
        }
        if sq != nil {
            candidates.append(.lossless)
        }
        if h != nil {
            candidates.append(.exhigh)
        }
        if m != nil {
            candidates.append(.higher)
        }
        if l != nil {
            candidates.append(.standard)
        }
        if fee == 8 {
            candidates.append(.lossless)
        }

        return SoundQuality.highest(from: candidates) ?? .standard
    }
    
    var qualityBadge: String? {
        if isLocal {
            return nil
        }
        if isAppleMusic {
            return nil
        }
        if isQQMusic {
            return qqMaxQuality?.badgeText
        }
        return maxQuality.badgeText
    }
    
    /// 真正无版权（平台级别下架），VIP Cookie 也无法播放
    var isNoCopyright: Bool {
        if let st = privilege?.st, st < 0 { return true }
        return false
    }

    /// VIP 限制（需要会员才能播放），VIP Cookie 可以播放
    var isVIPRestricted: Bool {
        if let pl = privilege?.pl, pl == 0, let fee = privilege?.fee, fee != 0 {
            return true
        }
        return false
    }

    /// 数字专辑歌曲：
    /// - 网易云：`fee == 4` 或 `privilege.fee == 4`
    /// - qcm：由 `convertQQSongToSong` 在 `pay.pay_album == 1` 时写入 `qqIsDigitalAlbum`
    /// 数字专辑需要另外购买，VIP Cookie 也不能自动解锁。
    var isDigitalAlbum: Bool {
        if fee == 4 { return true }
        if let pfee = privilege?.fee, pfee == 4 { return true }
        if qqIsDigitalAlbum == true { return true }
        return false
    }

    /// 是否为"未购买"的数字专辑（即使是 VIP 也需单独购买）。
    /// - 网易云：数字专辑 + privilege 表明未购（payed == 0 或 pl == 0 或 st < 0）
    /// - qcm：`qqIsDigitalAlbum == true`（仅 pay_album）时标灰；其余数字专辑仍靠播放失败
    ///   由 `UnavailableSongsManager` 标灰。
    var isUnpurchasedDigitalAlbum: Bool {
        if qqIsDigitalAlbum == true { return true }
        guard isDigitalAlbum else { return false }
        guard let privilege else { return false }
        if let payed = privilege.payed, payed == 1 { return false }
        if let pl = privilege.pl, pl == 0 { return true }
        if let st = privilege.st, st < 0 { return true }
        if let payed = privilege.payed, payed == 0 { return true }
        return false
    }

    /// 判断歌曲是否不可用（无版权 或 VIP 限制 或 未购数字专辑）
    var isUnavailable: Bool {
        isNoCopyright || isVIPRestricted || isUnpurchasedDigitalAlbum
    }
}

/// 将同一歌曲在不同平台、不同专辑版本中的封面地址关联起来。
/// 图片 CDN 返回失效地址时，加载器可以只回退封面，不改变歌曲来源与播放身份。
final class SongArtworkFallbackRegistry: @unchecked Sendable {
    static let shared = SongArtworkFallbackRegistry()

    private let lock = NSLock()
    private let maximumIdentityCount = 2_500
    private var identityOrder: [String] = []
    private var candidatesByIdentity: [String: [URL]] = [:]
    private var identityByURLKey: [String: String] = [:]

    private init() {}

    func register(_ songs: [Song]) {
        guard !songs.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        for song in songs {
            guard let identity = Self.identity(for: song) else { continue }
            let candidates = song.artworkURLCandidates
            guard !candidates.isEmpty else { continue }

            if candidatesByIdentity[identity] == nil {
                candidatesByIdentity[identity] = []
                identityOrder.append(identity)
            }

            var existing = candidatesByIdentity[identity] ?? []
            var existingKeys = Set(existing.map { Self.urlKey(for: $0) })
            for candidate in candidates {
                let key = Self.urlKey(for: candidate)
                identityByURLKey[key] = identity
                guard existingKeys.insert(key).inserted else { continue }
                existing.append(candidate)
            }
            candidatesByIdentity[identity] = existing
        }

        trimIfNeeded()
    }

    func registerResolvedArtwork(_ url: URL, for song: Song) {
        guard let identity = Self.identity(for: song) else { return }

        lock.lock()
        defer { lock.unlock() }

        if candidatesByIdentity[identity] == nil {
            candidatesByIdentity[identity] = []
            identityOrder.append(identity)
        }

        let key = Self.urlKey(for: url)
        identityByURLKey[key] = identity
        var candidates = candidatesByIdentity[identity] ?? []
        if !candidates.contains(where: { Self.urlKey(for: $0) == key }) {
            candidates.insert(url, at: 0)
            candidatesByIdentity[identity] = candidates
        }
        trimIfNeeded()
    }

    func fallbackCandidates(for failedURL: URL) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        let failedKey = Self.urlKey(for: failedURL)
        guard let identity = identityByURLKey[failedKey],
              let candidates = candidatesByIdentity[identity] else { return [] }
        return candidates.filter { Self.urlKey(for: $0) != failedKey }
    }

    private func trimIfNeeded() {
        guard identityOrder.count > maximumIdentityCount else { return }
        let overflow = identityOrder.count - maximumIdentityCount
        let removed = identityOrder.prefix(overflow)
        identityOrder.removeFirst(overflow)
        for identity in removed {
            candidatesByIdentity.removeValue(forKey: identity)
            identityByURLKey = identityByURLKey.filter { $0.value != identity }
        }
    }

    private static func identity(for song: Song) -> String? {
        let title = normalizedIdentityText(song.name)
        let artist = normalizedIdentityText(song.artistName)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return "\(title)|\(artist)"
    }

    private static func normalizedIdentityText(_ value: String) -> String {
        let compatible = value.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return compatible.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func urlKey(for url: URL) -> String {
        var value = url.absoluteString
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.host?.lowercased().contains("music.126.net") == true {
            components.host = "music.126.net"
            components.scheme = "https"
            components.queryItems = components.queryItems?.filter { $0.name != "param" }
            value = components.url?.absoluteString ?? value
        }
        value = value.replacingOccurrences(
            of: #"R\d+x\d+"#,
            with: "R_SIZE_",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"/w/\d+/h/\d+"#,
            with: "/w/_/h/_",
            options: .regularExpression
        )
        return value
    }
}

struct SongQuality: Codable, Sendable {
    let br: Int
    let fid: Int?
    let size: Int?
    let vd: Double?
    let sr: Int?
}

struct Privilege: Codable, Sendable {
    let id: Int?
    let fee: Int?
    let payed: Int?
    let st: Int?
    let pl: Int?
    let dl: Int?
    let sp: Int?
    let cp: Int?
    let subp: Int?
    let cs: Bool?
    let maxbr: Int?
    let fl: Int?
    let toast: Bool?
    let flag: Int?
    let preSell: Bool?
    let playMaxBr: Int?
    let downloadMaxBr: Int?
    
    let maxBrLevel: SoundQuality?
    let playMaxBrLevel: SoundQuality?
    let downloadMaxBrLevel: SoundQuality?
    let plLevel: SoundQuality?
    let dlLevel: SoundQuality?
    let flLevel: SoundQuality?
    
    let rscl: Int?
    let freeTrialPrivilege: FreeTrialPrivilege?
    let chargeInfoList: [ChargeInfo]?
}

struct FreeTrialPrivilege: Codable, Sendable {
    let resConsumable: Bool
    let userConsumable: Bool
    let listenType: Int?
}

struct ChargeInfo: Codable, Sendable {
    let rate: Int
    let chargeUrl: String?
    let chargeMessage: String?
    let chargeType: Int
}

struct Artist: Codable, Sendable {
    let id: Int
    let name: String
}

struct Album: Codable, Sendable {
    let id: Int
    let name: String
    let picUrl: String?
}

struct SongDetail: Codable {
    let id: Int
    let name: String
    let artists: [Artist]?
    let ar: [Artist]?
    let album: Album?
    let al: Album?
    let duration: Int?
    let dt: Int?
    let fee: Int?
    let mvid: Int?
    
    let h: SongQuality?
    let m: SongQuality?
    let l: SongQuality?
    let sq: SongQuality?
    let hr: SongQuality?
    
    func toSong() -> Song {
        return Song(
            id: id,
            name: name,
            ar: ar ?? artists,
            al: al ?? album,
            dt: dt ?? duration,
            fee: fee,
            mv: mvid,
            h: h,
            m: m,
            l: l,
            sq: sq,
            hr: hr,
            alia: nil
        )
    }
}

// MARK: - Extensions

extension URL {
    /// qcm CDN 只支持固定尺寸，将请求的尺寸向上取到最近的可用值
    private static let qqCDNSizes = [150, 180, 300, 500, 800]

    private static func nearestQQSize(_ requested: Int) -> Int {
        qqCDNSizes.first { $0 >= requested } ?? 800
    }

    func sized(_ size: Int) -> URL {
        resizedArtworkURL(pixelSize: size, preserveLargerRequest: false)
    }

    /// 图片视图按点布局、CDN 按像素返回。加载器调用此方法保证现有 URL
    /// 至少达到目标像素，不会把调用方已经请求的高清图反向降级。
    func artworkURL(atLeastPixelSize size: Int) -> URL {
        resizedArtworkURL(pixelSize: size, preserveLargerRequest: true)
    }

    private func resizedArtworkURL(pixelSize requestedSize: Int, preserveLargerRequest: Bool) -> URL {
        if isFileURL {
            return self
        }

        let targetSize = max(requestedSize, 1)
        var normalizedURL = self
        if scheme == "http", var components = URLComponents(url: self, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            normalizedURL = components.url ?? self
        }

        let str = normalizedURL.absoluteString
        let host = normalizedURL.host?.lowercased() ?? ""

        // qcm MV 的 T015 封面只提供固定的 16:9 尺寸。把 640x360 改成
        // 通用封面的正方形尺寸会直接得到 404，因此必须保留服务端原始规格。
        if str.contains("y.gtimg.cn/music/photo_new/T015R") {
            return normalizedURL
        }

        // qcm CDN: 替换路径中的 R{w}x{h} 尺寸段（T001/T002/T003 等）
        if str.contains("y.gtimg.cn/music/photo_new/"),
           let range = str.range(of: #"R\d+x\d+"#, options: .regularExpression) {
            let currentSize = String(str[range])
                .dropFirst()
                .split(separator: "x")
                .first
                .flatMap { Int($0) } ?? 0
            let requested = preserveLargerRequest ? max(targetSize, currentSize) : targetSize
            let s = Self.nearestQQSize(requested)
            let replaced = str.replacingCharacters(in: range, with: "R\(s)x\(s)")
            return URL(string: replaced) ?? normalizedURL
        }

        // KCM 搜索接口经常返回 /150、/240 这种列表缩略图。酷狗图片 CDN
        // 支持同路径切换尺寸，统一提升到稳定档位，避免歌手/专辑/歌单被放大后模糊。
        let isKugouArtwork = host.hasSuffix(".kugou.com")
        if isKugouArtwork,
           let range = str.range(of: #"/(?:100|120|150|160|180|240|300|400|480|500|640|800|1000)/"#, options: .regularExpression) {
            let currentSize = Int(str[range].dropFirst().dropLast()) ?? 0
            let requested = preserveLargerRequest ? max(targetSize, currentSize) : targetSize
            let size: Int
            if requested <= 400 {
                size = 400
            } else if requested <= 800 {
                size = 800
            } else {
                size = 1000
            }
            return URL(string: str.replacingCharacters(in: range, with: "/\(size)/")) ?? normalizedURL
        }

        // qcm歌单封面 CDN 主要提供 /300 与 /600 两档。
        if str.contains("qpic.cn") {
            guard let range = str.range(of: #"/\d{2,4}(?=[?&/]|$)"#, options: .regularExpression) else {
                return normalizedURL
            }
            let currentSize = Int(str[range].dropFirst()) ?? 0
            let requested = preserveLargerRequest ? max(targetSize, currentSize) : targetSize
            let s = requested > 300 ? 600 : 300
            return URL(string: str.replacingCharacters(in: range, with: "/\(s)")) ?? normalizedURL
        }

        // qcm 新版推荐歌单使用 imageView2/4/w/300/h/300 参数。
        if host == "music-file.y.qq.com",
           let range = str.range(of: #"/w/\d+/h/\d+"#, options: .regularExpression) {
            let segment = String(str[range])
            let currentSize = segment
                .split(separator: "/")
                .compactMap { Int($0) }
                .max() ?? 0
            let requested = preserveLargerRequest ? max(targetSize, currentSize) : targetSize
            let s = min(requested, 1200)
            return URL(string: str.replacingCharacters(in: range, with: "/w/\(s)/h/\(s)")) ?? normalizedURL
        }

        // qcm其他 CDN（pic.ugcimg.cn 等带 /N 尺寸路径）
        if str.contains("gtimg.cn") || str.contains("ugcimg.cn") {
            var result = str
            if let range = result.range(of: #"/\d{2,4}(?=[?&/]|$)"#, options: .regularExpression) {
                let currentSize = Int(result[range].dropFirst()) ?? 0
                let size = preserveLargerRequest ? max(targetSize, currentSize) : targetSize
                result = result.replacingCharacters(in: range, with: "/\(size)")
            }
            return URL(string: result) ?? normalizedURL
        }

        // ncm CDN。分类歌单接口会返回类似：
        // ?imageView=1&thumbnail=800y800&...|imageView=1&thumbnail=140y140
        // 的复合处理链。若仅在末尾追加 param，CDN 仍可能先按最后一段
        // thumbnail 输出 140px 小图，放到歌单大卡片后就会明显模糊。
        guard host.contains("music.126.net"),
              var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false) else {
            return normalizedURL
        }
        var queryItems = components.queryItems ?? []
        let currentSize: Int = queryItems
            .first(where: { $0.name == "param" })?
            .value?
            .split(separator: "y")
            .first
            .flatMap { Int($0) } ?? 0
        let size = preserveLargerRequest ? max(targetSize, currentSize) : targetSize

        let ncmImageProcessingQueryNames: Set<String> = [
            "param",
            "imageview",
            "imageview2",
            "thumbnail",
            "enlarge",
            "watermark",
            "type",
            "image",
            "dx",
            "dy",
            "blur",
            "quality",
        ]
        queryItems.removeAll {
            ncmImageProcessingQueryNames.contains($0.name.lowercased())
        }
        queryItems.append(URLQueryItem(name: "param", value: "\(size)y\(size)"))
        components.queryItems = queryItems
        return components.url ?? normalizedURL
    }
}

// MARK: - Personalized New Song

struct PersonalizedNewSongResult: Codable {
    let id: Int
    let name: String
    let song: SongDetail
}

// MARK: - Recent Song

struct RecentSongItem: Codable {
    let data: Song
    let playTime: Int?
}

// MARK: - FM Song

struct FMSong: Codable {
    let id: Int
    let name: String?
    let album: Album?
    let al: Album?
    let artists: [Artist]?
    let ar: [Artist]?
    let duration: Int?
    let dt: Int?
    let fee: Int?
    let mvid: Int?
    
    let h: SongQuality?
    let m: SongQuality?
    let l: SongQuality?
    let sq: SongQuality?
    let hr: SongQuality?
    let privilege: Privilege?
    
    func toSong() -> Song {
        return Song(
            id: id,
            name: name ?? "Unknown Song",
            ar: ar ?? artists,
            al: al ?? album,
            dt: dt ?? duration,
            fee: fee,
            mv: mvid ?? 0,
            h: h,
            m: m,
            l: l,
            sq: sq,
            hr: hr,
            alia: nil,
            privilege: privilege
        )
    }
}
