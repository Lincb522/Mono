import Combine
import QQMusicKit
import SwiftUI
import UniformTypeIdentifiers

extension ScrollableLibraryExperience {
    func selectTab(_ tab: LibraryViewModel.LibraryTab, index: Int) {
        tabIndex = index
        viewModel.currentTab = tab
        load(tab)
    }

    func syncTabFromViewModel() {
        if let index = tabs.firstIndex(of: viewModel.currentTab), index != tabIndex {
            tabIndex = index
        }
    }

    func loadCurrentTab() {
        load(selectedTab)
    }

    func load(_ tab: LibraryViewModel.LibraryTab) {
        switch tab {
        case .my:
            viewModel.fetchPlaylists()
            if selectedMyLibraryColumn == .qcmPlaylists {
                loadQQUserPlaylistsIfNeeded()
            }
            if subManager.subscribedRadios.isEmpty {
                subManager.fetchSubscribedRadios()
            }
        case .square:
            viewModel.fetchSquareForSelectedSource()
        case .artists:
            viewModel.fetchArtistsForSelectedSource()
        case .charts:
            viewModel.fetchChartsForSelectedSource()
        }
    }

    func loadQQUserPlaylistsIfNeeded(force: Bool = false) {
        let session = qqSession.sessionSnapshot
        guard force || !hasLoadedQQUserPlaylists else { return }
        guard !isLoadingQQUserPlaylists else { return }
        guard session.isLoggedIn, let mid = session.musicID else {
            qqUserPlaylists = []
            hasLoadedQQUserPlaylists = true
            return
        }

        let request = qqPlaylistRequest.begin()
        isLoadingQQUserPlaylists = true
        qqPlaylistRequest.task = Task { @MainActor in
            guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request) else { return }
            defer {
                if qqPlaylistRequest.isCurrent(request), qqSession.isCurrentSession(session) {
                    isLoadingQQUserPlaylists = false
                    qqPlaylistRequest.finish(request)
                }
            }

            do {
                let result: JSON = try await QQUserSession.shared.withUserSession { client in
                    try await client.createdSonglist(uin: String(mid))
                }
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                qqUserPlaylists = Self.parseQQUserPlaylists(result)
                hasLoadedQQUserPlaylists = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, qqPlaylistRequest.isCurrent(request),
                      qqSession.isCurrentSession(session) else { return }
                AppLogger.error("[Library] 加载 QCM 歌单失败: \(error)")
            }
        }
    }

    static func parseQQUserPlaylists(_ result: JSON) -> [Playlist] {
        // 新版 API: { playlists: [{ id, dirid, title, picurl, songnum }], total }
        let list = result["playlists"]?.arrayValue
            ?? result["v_playlist"]?.arrayValue
            ?? result.arrayValue ?? []
        return list.compactMap { json in
            guard let obj = json.objectValue else { return nil }
            let tid = obj["id"]?.intValue ?? obj["tid"]?.intValue ?? 0
            let name = obj["title"]?.stringValue ?? obj["dirName"]?.stringValue ?? obj["diss_name"]?.stringValue ?? ""
            let cover = obj["picurl"]?.stringValue ?? obj["picUrl"]?.stringValue ?? obj["logo"]?.stringValue ?? ""
            let songCount = obj["songnum"]?.intValue ?? obj["songNum"]?.intValue ?? obj["song_cnt"]?.intValue ?? 0
            guard !name.isEmpty else { return nil }
            return Playlist(
                id: tid,
                name: name,
                coverImgUrl: cover,
                picUrl: nil,
                trackCount: songCount,
                playCount: nil,
                subscribedCount: nil,
                shareCount: nil,
                commentCount: nil,
                creator: nil,
                description: nil,
                tags: nil,
                source: .qqmusic
            )
        }
    }

    func createLocalPlaylist() {
        AlertManager.shared.showInput(
            title: String(localized: "lib_create_playlist"),
            message: "",
            placeholder: String(localized: "lib_playlist_name"),
            primaryButtonTitle: String(localized: "lib_create"),
            secondaryButtonTitle: String(localized: "alert_cancel"),
            onConfirm: { name in
                guard !name.isEmpty else { return }
                _ = localManager.createPlaylist(name: name)
            }
        )
    }

    func showImportLinkPrompt() {
        viewModel.navigationPath.append(
            LibraryViewModel.NavigationDestination.externalPlaylistImport
        )
    }

    func importPlaylistFromFile(url: URL) {
        isImporting = true
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let parsed = try LocalPlaylistManager.parseExportFile(url: url)
            let ids = parsed.songIds
            let name = parsed.name
            guard !ids.isEmpty else {
                AlertManager.shared.show(
                    title: String(localized: "lib_import_failed"),
                    message: String(localized: "lib_import_no_songs"),
                    primaryButtonTitle: String(localized: "lib_confirm"),
                    primaryAction: {}
                )
                isImporting = false
                return
            }

            Task {
                var allSongs: [Song] = []
                for i in stride(from: 0, to: ids.count, by: 50) {
                    let batch = Array(ids[i ..< min(i + 50, ids.count)])
                    do {
                        let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                            var cancellable: AnyCancellable?
                            cancellable = APIService.shared.fetchSongDetails(ids: batch)
                                .sink(receiveCompletion: { completion in
                                    if case let .failure(error) = completion {
                                        continuation.resume(throwing: error)
                                    }
                                    cancellable?.cancel()
                                }, receiveValue: { songs in
                                    continuation.resume(returning: songs)
                                    cancellable?.cancel()
                                })
                        }
                        allSongs.append(contentsOf: songs)
                    } catch {
                        AppLogger.error("导入歌单批次获取失败: \(error)")
                    }
                }

                await MainActor.run {
                    if allSongs.isEmpty {
                        AlertManager.shared.show(
                            title: String(localized: "lib_import_failed"),
                            message: String(localized: "lib_import_fetch_failed"),
                            primaryButtonTitle: String(localized: "lib_confirm"),
                            primaryAction: {}
                        )
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            }
        } catch {
            AlertManager.shared.show(
                title: String(localized: "lib_import_failed"),
                message: error.localizedDescription,
                primaryButtonTitle: String(localized: "lib_confirm"),
                primaryAction: {}
            )
            isImporting = false
        }
    }

    func importPlaylistFromURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isImporting = true

        if let qqId = extractQQPlaylistId(from: trimmed) {
            importQQPlaylist(id: qqId)
        } else if let ncmId = extractNCMPlaylistId(from: trimmed) {
            importNCMPlaylist(id: ncmId)
        } else {
            AlertManager.shared.show(
                title: String(localized: "lib_import_failed"),
                message: String(localized: "无法识别的歌单链接"),
                primaryButtonTitle: String(localized: "lib_confirm"),
                primaryAction: {}
            )
            isImporting = false
        }
    }

    func extractQQPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist/(\d+)"#, options: .regularExpression) {
            return Int(url[range].replacingOccurrences(of: "playlist/", with: ""))
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("y.qq.com") {
            return Int(String(url[range]).replacingOccurrences(of: "id=", with: ""))
        }
        return nil
    }

    func extractNCMPlaylistId(from url: String) -> Int? {
        if let range = url.range(of: #"playlist\?id=(\d+)"#, options: .regularExpression) {
            return Int(String(url[range]).replacingOccurrences(of: "playlist?id=", with: ""))
        }
        if let range = url.range(of: #"id=(\d+)"#, options: .regularExpression), url.contains("music.163.com") {
            return Int(String(url[range]).replacingOccurrences(of: "id=", with: ""))
        }
        return nil
    }

    func importQQPlaylist(id: Int) {
        Task {
            do {
                let detail = try await APIService.shared.qqClient.songlistDetail(songlistId: id, num: 1, page: 1)
                let name = detail["dirinfo"]?["title"]?.stringValue ?? String(localized: "QCM歌单")
                var allSongs: [Song] = []
                var page = 1
                var hasMore = true

                while hasMore {
                    let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                        var resumed = false
                        var cancellable: AnyCancellable?
                        cancellable = APIService.shared.fetchQQPlaylistSongs(playlistId: id, page: page, num: 50)
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion, !resumed {
                                    resumed = true
                                    continuation.resume(throwing: error)
                                }
                                cancellable?.cancel()
                            }, receiveValue: { songs in
                                guard !resumed else { return }
                                resumed = true
                                continuation.resume(returning: songs)
                                cancellable?.cancel()
                            })
                    }
                    allSongs.append(contentsOf: songs)
                    hasMore = songs.count >= 50
                    page += 1
                }

                await MainActor.run {
                    if allSongs.isEmpty {
                        AlertManager.shared.show(
                            title: String(localized: "lib_import_failed"),
                            message: String(localized: "playlist_empty_or_load_failed"),
                            primaryButtonTitle: String(localized: "lib_confirm"),
                            primaryAction: {}
                        )
                    } else {
                        localManager.importPlaylist(name: name, songs: allSongs)
                    }
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    AlertManager.shared.show(
                        title: String(localized: "lib_import_failed"),
                        message: L10n.format(
                            "qcm_playlist_import_failed_format",
                            error.localizedDescription
                        ),
                        primaryButtonTitle: String(localized: "lib_confirm"),
                        primaryAction: {}
                    )
                    isImporting = false
                }
            }
        }
    }

    func importNCMPlaylist(id: Int) {
        Task {
            var allSongs: [Song] = []
            var offset = 0
            let limit = 50
            var hasMore = true

            while hasMore {
                do {
                    let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                        var resumed = false
                        var cancellable: AnyCancellable?
                        cancellable = APIService.shared.fetchPlaylistTracks(id: id, limit: limit, offset: offset)
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion, !resumed {
                                    resumed = true
                                    continuation.resume(throwing: error)
                                }
                                cancellable?.cancel()
                            }, receiveValue: { songs in
                                guard !resumed else { return }
                                resumed = true
                                continuation.resume(returning: songs)
                                cancellable?.cancel()
                            })
                    }
                    allSongs.append(contentsOf: songs)
                    hasMore = songs.count >= limit
                    offset += limit
                } catch {
                    hasMore = false
                }
            }

            await MainActor.run {
                if allSongs.isEmpty {
                    AlertManager.shared.show(
                        title: String(localized: "lib_import_failed"),
                        message: String(localized: "playlist_empty_or_load_failed"),
                        primaryButtonTitle: String(localized: "lib_confirm"),
                        primaryAction: {}
                    )
                } else {
                    localManager.importPlaylist(name: String(localized: "NCM歌单"), songs: allSongs)
                }
                isImporting = false
            }
        }
    }

    func chartDestination(_ list: TopList) -> LibraryViewModel.NavigationDestination {
        .playlist(list.playlist())
    }

    func qqChartDestination(_ item: QQTopListItem) -> LibraryViewModel.NavigationDestination {
        .playlist(Playlist(
            id: item.topId,
            name: item.title,
            coverImgUrl: item.coverUrl,
            picUrl: nil,
            trackCount: nil,
            playCount: nil,
            subscribedCount: nil,
            shareCount: nil,
            commentCount: nil,
            creator: nil,
            description: item.intro.isEmpty ? nil : item.intro,
            tags: nil,
            source: .qqmusic,
            isTopList: true
        ))
    }

}
