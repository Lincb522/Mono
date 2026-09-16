import AVFoundation
import Foundation

/// Provider tags and embedded genre fields only; titles and prose are not genre evidence.
enum SongGenreMetadata {
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ";；、·\n\0")) }
            .compactMap { raw in
                let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty, tag.count <= 80, seen.insert(tag.lowercased()).inserted else { return nil }
                return tag
            }
    }

    static func neteaseTags(in body: [String: Any]) -> [String] {
        guard let data = body["data"] as? [String: Any],
              let blocks = data["blocks"] as? [[String: Any]] else { return [] }
        var tags: [String] = []
        for block in blocks where block["code"] as? String == "SONG_PLAY_ABOUT_SONG_BASIC" {
            for creative in block["creatives"] as? [[String: Any]] ?? [] {
                guard let kind = creative["creativeType"] as? String,
                      kind == "songTag" || kind == "songBizTag" else { continue }
                for resource in creative["resources"] as? [[String: Any]] ?? [] {
                    guard let ui = resource["uiElement"] as? [String: Any],
                          let title = ui["mainTitle"] as? [String: Any],
                          let text = title["title"] as? String else { continue }
                    tags.append(text)
                }
            }
        }
        return clean(tags)
    }

    static func tags(in detail: PlatformSongDetail) -> [String] {
        let tagSections: Set<String> = ["qcm-tags", "qsm-tags", "kcm-tags", "apple-music-genres"]
        return clean(detail.sections.filter { tagSections.contains($0.id) }.map(\.body))
    }

    @MainActor
    static func localTags(at url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.metadata)
        return await localTags(in: metadata)
    }

    // Keep AVMetadataItem references on the local library's actor; only tags cross it.
    @MainActor
    static func localTags(in metadata: [AVMetadataItem]) async -> [String] {
        let identifiers: Set<AVMetadataIdentifier> = [
            .id3MetadataContentType, .iTunesMetadataUserGenre,
            .quickTimeUserDataGenre, .quickTimeMetadataGenre
        ]
        var tags: [String] = []
        for item in metadata {
            if item.identifier == .iTunesMetadataPredefinedGenre {
                if let number = try? await item.load(.numberValue) {
                    tags += predefinedGenre(number.intValue)
                } else if let data = try? await item.load(.dataValue), data.count == 2 {
                    tags += predefinedGenre(data.reduce(0) { ($0 << 8) | Int($1) })
                }
                continue
            }
            let isGenre = item.identifier.map { identifiers.contains($0) } == true
                || (item.key as? String)?.lowercased() == "genre"
            guard isGenre, let value = try? await item.load(.stringValue) else { continue }
            tags += id3Tags(value)
        }
        return clean(tags)
    }

    /// ID3 TCON references are zero-based and may precede a textual refinement.
    static func id3Tags(_ value: String) -> [String] {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(text) { return id3Genres.indices.contains(index) ? [id3Genres[index]] : [] }
        var tags: [String] = []
        while text.first == "(", let end = text.firstIndex(of: ")"),
              let index = Int(text[text.index(after: text.startIndex)..<end]) {
            if id3Genres.indices.contains(index) { tags.append(id3Genres[index]) }
            text = String(text[text.index(after: end)...])
        }
        if !text.isEmpty { tags.append(text) }
        return clean(tags)
    }

    /// MP4 `gnre` stores the ID3 genre index plus one (zero means unspecified).
    /// https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mov.c
    static func predefinedGenre(_ number: Int) -> [String] {
        guard number > 0, number <= id3Genres.count else { return [] }
        return [id3Genres[number - 1]]
    }

    // ID3v1 / Winamp genre table: https://id3.org/id3v2.3.0#Appendix_A_-_Genre_List_from_ID3v1
    private static let id3Genres: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk",
        "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies",
        "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
        "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
        "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House",
        "Game", "Sound Clip", "Gospel", "Noise", "AlternRock", "Bass",
        "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
        "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
        "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret",
        "New Wave", "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
        "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical",
        "Rock & Roll", "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing",
        "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic", "Bluegrass",
        "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock",
        "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech",
        "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass",
        "Primus", "Porn Groove", "Satire", "Slow Jam", "Club", "Tango",
        "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
        "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall",
        "Goa", "Drum & Bass", "Club-House", "Hardcore Techno", "Terror", "Indie",
        "BritPop", "Negerpunk", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal",
        "Black Metal", "Crossover", "Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
        "Thrash Metal", "Anime", "Jpop", "Synthpop",
    ]
}
