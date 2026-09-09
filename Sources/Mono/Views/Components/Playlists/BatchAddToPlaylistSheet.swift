import SwiftUI

/// 批量收藏到本地歌单
struct BatchAddToPlaylistSheet: View {
    let songs: [Song]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss
    @ObservedObject private var manager = LocalPlaylistManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var activeOperationID: String?

    private enum OperationKey {
        static let favorite = "favorite"
        static let create = "create"

        static func localPlaylist(_ id: String) -> String {
            "local_\(id)"
        }
    }

    private var trimmedPlaylistName: String {
        newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localPlaylists: [LocalPlaylist] {
        manager.playlists.filter { !$0.isDownload && !$0.isFavorite }
    }

    private var isBusy: Bool {
        activeOperationID != nil
    }

    private var favoriteExistingCount: Int {
        songs.reduce(0) { partial, song in
            partial + (manager.isFavorite(songId: song.id, source: song.musicSource) ? 1 : 0)
        }
    }

    private var favoriteAddableCount: Int {
        max(0, songs.count - favoriteExistingCount)
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    quickActionsSection
                    localPlaylistSection
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .iPadContentWidth(520)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
            .background {
                MonoSheetAwareBackground {
                    ThemedPageBackground()
                }
            }
            .navigationTitle("")
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("alert_cancel")) {
                        dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss)
                    }
                    .disabled(isBusy)
                }
            }
            .alert(LocalizedStringKey("add_to_playlist_create"), isPresented: $showCreateAlert) {
                TextField(LocalizedStringKey("add_to_playlist_name"), text: $newPlaylistName)
                    .monoTextInputBehavior()
                Button(LocalizedStringKey("lib_create")) {
                    guard !trimmedPlaylistName.isEmpty else { return }
                    Task { await createPlaylist() }
                }
                Button(LocalizedStringKey("alert_cancel"), role: .cancel) {}
            }
        }
    }

    private var summaryCard: some View {
        PlaylistPickerContainerCard {
            HStack(spacing: 14) {
                summaryArtwork

                VStack(alignment: .leading, spacing: 6) {
                    Text(batchSummaryTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.monoTextPrimary)
                        .lineLimit(2)

                    Text(batchSummarySubtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.monoTextSecondary)
                        .lineLimit(2)

                    Text(String(localized: "playlist_picker_choose_destination"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.monoTextSecondary.opacity(0.8))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var quickActionsSection: some View {
        PlaylistPickerSection(
            title: LocalizedStringKey("playlist_picker_quick_actions"),
            subtitle: String(localized: "playlist_picker_quick_actions_subtitle")
        ) {
            PlaylistPickerActionCard(
                icon: .liked,
                title: String(localized: "playlist_picker_liked"),
                subtitle: String(localized: "playlist_picker_liked_subtitle"),
                tint: .red,
                statusText: favoriteStatusText,
                statusTint: favoriteAddableCount == 0 ? .red : .monoTextSecondary,
                isLoading: activeOperationID == OperationKey.favorite,
                isDisabled: favoriteAddableCount == 0 || isBusy
            ) {
                Task { await addSongsToFavorite() }
            }

            PlaylistPickerActionCard(
                icon: .add,
                title: String(localized: "add_to_playlist_new"),
                subtitle: String(localized: "playlist_picker_local_create_subtitle"),
                tint: .monoAccentBlue,
                isLoading: activeOperationID == OperationKey.create,
                isDisabled: isBusy
            ) {
                    newPlaylistName = ""
                showCreateAlert = true
            }
        }
    }

    private var localPlaylistSection: some View {
        PlaylistPickerSection(
            title: LocalizedStringKey("local_playlist_section"),
            subtitle: String(localized: "playlist_picker_local_section_subtitle")
        ) {
            if localPlaylists.isEmpty {
                PlaylistPickerEmptyStateCard(
                    icon: .musicNoteList,
                    message: String(localized: "playlist_picker_empty_local")
                )
            } else {
                ForEach(localPlaylists, id: \.id) { playlist in
                    let summary = manager.summary(for: playlist)
                    let addableCount = manager.addableSongCount(songs, for: playlist)

                    PlaylistPickerPlaylistRow(
                        title: summary.name,
                        subtitle: songsCountText(summary.trackCount),
                        coverURL: summary.displayCoverUrl,
                        placeholderIcon: .musicNoteList,
                        statusText: statusText(for: addableCount),
                        statusTint: addableCount == 0 ? .monoTextSecondary : .monoAccentBlue,
                        isLoading: activeOperationID == OperationKey.localPlaylist(playlist.id),
                        isDisabled: addableCount == 0 || isBusy
                    ) {
                        Task { await addSongs(to: playlist) }
                    }
                }
            }
        }
    }

    private var summaryArtwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let firstSong = songs.first, let coverURL = firstSong.coverUrl {
                    CachedAsyncImage(url: coverURL.sized(200)) {
                        summaryArtworkPlaceholder
                    }
                    .aspectRatio(contentMode: .fill)
                } else {
                    summaryArtworkPlaceholder
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))

            PlaylistPickerStatusBadge(
                text: "\(songs.count)",
                tint: .monoAccentBlue
            )
            .offset(x: 6, y: 6)
        }
    }

    private var summaryArtworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.monoGlassTint)

            MonoIcon(icon: .musicNoteList, size: 20, color: .monoTextSecondary.opacity(0.45))
        }
    }

    private var batchSummaryTitle: String {
        String(
            format: NSLocalizedString("playlist_picker_batch_summary_format", comment: ""),
            songs.count
        )
    }

    private var batchSummarySubtitle: String {
        if songs.isEmpty {
            return String(localized: "playlist_picker_empty_local")
        }

        let previewNames = songs.prefix(3).map(\.name).joined(separator: "、")
        if songs.count > 3 {
            return "\(previewNames)…"
        }
        return previewNames
    }

    private var favoriteStatusText: String? {
        statusText(for: favoriteAddableCount)
    }

    @MainActor
    private func addSongsToFavorite() async {
        guard favoriteAddableCount > 0 else { return }

        activeOperationID = OperationKey.favorite
        defer { activeOperationID = nil }

        if let favorite = manager.favoritePlaylist {
            manager.addSongs(songs, to: favorite)
        }

        dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss)
    }

    @MainActor
    private func addSongs(to playlist: LocalPlaylist) async {
        guard manager.addableSongCount(songs, for: playlist) > 0 else { return }

        activeOperationID = OperationKey.localPlaylist(playlist.id)
        defer { activeOperationID = nil }

        manager.addSongs(songs, to: playlist)

        dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss)
    }

    @MainActor
    private func createPlaylist() async {
        let name = trimmedPlaylistName
        guard !name.isEmpty else { return }

        activeOperationID = OperationKey.create
        defer {
            activeOperationID = nil
            newPlaylistName = ""
        }

        _ = manager.importPlaylist(name: name, songs: songs)
        dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss)
    }

    private func statusText(for addableCount: Int) -> String? {
        if addableCount == 0 {
            return String(localized: "playlist_picker_contains_all")
        }
        if addableCount < songs.count {
            return String(
                format: NSLocalizedString("playlist_picker_will_add_count", comment: ""),
                addableCount
            )
        }
        return nil
    }

    private func songsCountText(_ count: Int) -> String {
        String(format: NSLocalizedString("songs_count_format", comment: ""), count)
    }
}
