import Foundation

// MARK: - 歌手详情模型

/// 跨平台歌手详情；封面按详情图、头像、一比一图片和普通图片依次回退。
struct ArtistInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let picUrl: String?
    let img1v1Url: String?
    let cover: String?       // 新版 artistDetail 接口返回的封面字段
    let avatar: String?      // 新版 artistDetail 接口返回的头像字段
    let musicSize: Int?
    let albumSize: Int?
    let mvSize: Int?
    let briefDesc: String?
    let alias: [String]?
    let followed: Bool?
    let accountId: Int?
    
    // MARK: - 跨平台扩展字段
    var source: MusicSource?
    var qqMid: String?
    var appleMusicID: String?
    var kugouID: String?

    init(
        id: Int,
        name: String,
        picUrl: String?,
        img1v1Url: String?,
        cover: String?,
        avatar: String?,
        musicSize: Int?,
        albumSize: Int?,
        mvSize: Int?,
        briefDesc: String?,
        alias: [String]?,
        followed: Bool?,
        accountId: Int?,
        source: MusicSource? = nil,
        qqMid: String? = nil,
        appleMusicID: String? = nil,
        kugouID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
        self.img1v1Url = img1v1Url
        self.cover = cover
        self.avatar = avatar
        self.musicSize = musicSize
        self.albumSize = albumSize
        self.mvSize = mvSize
        self.briefDesc = briefDesc
        self.alias = alias
        self.followed = followed
        self.accountId = accountId
        self.source = source
        self.qqMid = qqMid
        self.appleMusicID = appleMusicID
        self.kugouID = kugouID
    }
    
    var coverUrl: URL? {
        if let urlStr = cover ?? avatar ?? img1v1Url ?? picUrl {
            return URL(string: urlStr)
        }
        return nil
    }
    
    var isQQMusic: Bool { source == .qqmusic }

    var navigationIdentity: String {
        let source = source ?? .netease
        let providerID: String?
        switch source {
        case .qqmusic: providerID = qqMid
        case .appleMusic: providerID = appleMusicID
        case .kugou: providerID = kugouID
        default: providerID = nil
        }
        if let providerID, !providerID.isEmpty {
            return "\(source.rawValue):provider:\(providerID)"
        }
        return "\(source.rawValue):id:\(id)"
    }
}

struct ArtistDetailResponse: Codable {
    let code: Int
    let data: ArtistDetailData?
}

struct ArtistDetailData: Codable {
    let artist: ArtistInfo?
}

struct ArtistSongsResponse: Codable {
    let code: Int
    let songs: [Song]?
    let total: Int?
    let more: Bool?
}

struct ArtistAlbumsResponse: Codable {
    let code: Int
    let hotAlbums: [AlbumInfo]?
    let more: Bool?
}

/// 跨平台专辑摘要，包含展示所需的发行信息与平台专用标识。
struct AlbumInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let picUrl: String?
    let publishTime: Int?
    let size: Int?
    let artist: ArtistInfo?
    let artists: [Artist]?
    let description: String?
    let company: String?
    let subType: String?
    var qqAlbumMid: String?
    var source: MusicSource? = nil
    var appleMusicID: String? = nil
    var kugouID: String? = nil
    
    var coverUrl: URL? {
        if let urlStr = picUrl {
            return URL(string: urlStr)
        }
        return nil
    }
    
    var artistName: String {
        if let artists = artists, !artists.isEmpty {
            return artists.map { $0.name }.joined(separator: " / ")
        }
        return artist?.name ?? ""
    }
    
    var publishDateText: String {
        guard let ts = publishTime else { return "" }
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        return Self.dateFormatter.string(from: date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct AlbumDetailResponse: Codable {
    let code: Int
    let album: AlbumInfo?
    let songs: [Song]?
}

// MARK: - Artist Description

struct ArtistDescSection: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct ArtistDescResult {
    let briefDesc: String?
    let sections: [ArtistDescSection]
}

// MARK: - Album Detail Result

struct AlbumDetailResult {
    let album: AlbumInfo?
    let songs: [Song]
}
