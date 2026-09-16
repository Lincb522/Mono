import Combine
import Foundation

extension APIService {
    /// Uses the song's own provider identity; no cross-provider or title-based guesses.
    func fetchSongGenreTags(song: Song) -> AnyPublisher<[String], Error> {
        switch song.musicSource {
        case .netease:
            return ncm.publisher { [ncm] in
                let response = try await ncm.songWikiSummary(id: song.id)
                return SongGenreMetadata.neteaseTags(in: response.body)
            }
        case .qqmusic:
            return fetchQQSongGenreTags(song: song)
        case .qishui:
            return fetchQishuiSongPlatformDetail(song: song)
                .map { SongGenreMetadata.tags(in: $0) }.eraseToAnyPublisher()
        case .kugou:
            return fetchKugouSongPlatformDetail(song: song)
                .map { SongGenreMetadata.tags(in: $0) }.eraseToAnyPublisher()
        case .appleMusic:
            return asyncToPublisher { @MainActor in
                let detail = try await AppleMusicService.shared.platformSongDetail(for: song)
                return SongGenreMetadata.tags(in: detail)
            }
        case .local:
            guard let url = song.localFileURL else {
                return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            return asyncToPublisher { try await SongGenreMetadata.localTags(at: url) }
        }
    }
}
