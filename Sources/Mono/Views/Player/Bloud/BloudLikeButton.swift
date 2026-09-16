import SwiftUI

struct BloudLikeButton: View {
    let song: Song?
    let ink: Color
    @ObservedObject private var likes = LikeManager.shared
    @ObservedObject private var playlists = LocalPlaylistManager.shared

    private var isLiked: Bool {
        guard let song else { return false }
        return playlists.isFavorite(songId: song.id, source: song.musicSource)
    }

    var body: some View {
        Button {
            guard let song else { return }
            likes.toggleLike(songId: song.id, isQQMusic: song.isQQMusic, song: song)
        } label: {
            MonoIcon(icon: isLiked ? .liked : .like, size: 24, color: ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(song == nil)
        .accessibilityLabel(Text(isLiked ? String(localized: "player_bloud_unlike") : String(localized: "player_bloud_like")))
        .accessibilityAddTraits(isLiked ? .isSelected : [])
    }
}
