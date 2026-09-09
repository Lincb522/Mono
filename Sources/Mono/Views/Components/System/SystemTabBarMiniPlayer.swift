import SwiftUI

@available(iOS 26.0, *)
struct TabViewBottomMiniPlayer: View {
    @Binding var playlistPresented: Bool
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MonoNavigationPlayer(layout: .native, isInline: placement == .inline, showsQueue: $playlistPresented)
            // The native glass follows the window appearance, not cover-derived page contrast.
            .environment(\.colorScheme, settings.activeColorScheme)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The older system tab bar uses the same controls in a regular material surface.
struct CompactMiniPlayerView: View {
    @State private var showsQueue = false

    var body: some View {
        MonoNavigationPlayer(layout: .native, showsQueue: $showsQueue)
            .modifier(MonoNavigationSurface(radius: 24))
            .monoSheet(isPresented: $showsQueue, preset: .standard) {
                if FloatingBarPlaybackModel.shared.isPlayingPodcast {
                    PodcastPlaylistPopupView()
                } else {
                    PlaylistPopupView()
                }
            }
    }
}
