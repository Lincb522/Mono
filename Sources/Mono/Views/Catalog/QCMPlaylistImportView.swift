import SwiftUI
import Combine
import QQMusicKit

struct QQPlaylistImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = LocalPlaylistManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @AppStorage("qqImportUin") private var savedUin = ""
    @State private var uin = ""
    @State private var isLoading = false
    @State private var playlists: [QQUserPlaylist] = []
    @State private var selectedIds: Set<Int> = []
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var importedCount = 0
    @State private var searchedUsers: [QQSearchedUser] = []
    
    private var qqClient: QQMusicClient { APIService.shared.qqClient }
    
    var body: some View {
        let _ = settings.globalThemeRevision

        NavigationStack {
            ZStack {
                ThemedPageBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if SignalStyle.isActive {
                        SignalNestedPageHeader(
                            title: String(localized: "QCM歌单导入"),
                            eyebrow: "QCM DATA IMPORT",
                            icon: .download,
                            module: .importData
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    if playlists.isEmpty && !isLoading {
                        inputSection
                    } else if isLoading && playlists.isEmpty {
                        loadingSection
                    } else {
                        playlistListSection
                    }
                }
            }

            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .monoNavigationBackButton()
            .toolbar {
                if !selectedIds.isEmpty && !isImporting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await importSelected() }
                        } label: {
                            Text("导入 (\(selectedIds.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        ScrollView {
            VStack(spacing: 28) {
                if SignalStyle.isActive {
                    SignalSectionTitle(title: "USER LOOKUP", detail: "QCM")
                        .padding(.horizontal, 24)
                } else {
                    Spacer().frame(height: 40)

                    ZStack {
                        RoundedRectangle(cornerRadius: importIconRadius, style: .continuous)
                            .fill(MangaStyle.isActive ? MangaStyle.bubbleBlue : (MujiStyle.isActive ? MujiStyle.surfaceRaised : (NeumorphicStyle.isActive ? NeumorphicStyle.surface : Color.monoGlassTint)))
                            .frame(width: 80, height: 80)
                            .background {
                                if NeumorphicStyle.isActive {
                                    NeumorphicSurfaceBackground(cornerRadius: importIconRadius, elevated: true)
                                        .frame(width: 80, height: 80)
                                }
                            }
                            .overlay {
                                if MangaStyle.isActive {
                                    RoundedRectangle(cornerRadius: importIconRadius, style: .continuous)
                                        .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth)
                                } else if MujiStyle.isActive {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(MujiStyle.hairline.opacity(0.45), lineWidth: 0.6)
                                }
                            }
                        MonoIcon(icon: .musicNoteList, size: 32, color: NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary.opacity(0.5))
                    }

                    VStack(spacing: 8) {
                        Text("导入 QCM歌单")
                            .font(MangaStyle.isActive ? MangaStyle.titleFont(21, weight: .black) : (MujiStyle.isActive ? MujiStyle.titleFont(20, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(21, weight: .semibold) : .system(size: 20, weight: .bold, design: .rounded))))
                            .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary)
                        Text("输入 QCM 号或用户名可添加用户歌单")
                            .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(13, weight: .medium) : .system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                HStack(spacing: 12) {
                    HStack {
                        MonoIcon(icon: .search, size: 16, color: NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary)
                        TextField(String(localized: "QCM 号 / 用户名"), text: $uin)
                            .font(SignalStyle.isActive ? SignalStyle.bodyFont(15, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(16, weight: .medium) : .system(size: 16, weight: .medium, design: .rounded)))
                            .foregroundStyle(SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary)
                            .monoTextInputBehavior()
                            .submitLabel(.search)
                            .monoOnSubmit(text: $uin) { _ in
                                Task { await smartSearch() }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .themedPageSurface(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 2 : 14, elevated: false)
                    
                    Button {
                        MonoTextInputCommitter.commit(text: $uin) { _ in
                            Task { await smartSearch() }
                        }
                    } label: {
                        MonoIcon(icon: .search, size: 18, color: NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextPrimary)
                            .frame(width: 48, height: 48)
                            .themedPageSurface(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 2 : (NeumorphicStyle.isActive ? 18 : 14), elevated: true, mangaTint: MangaStyle.labelYellow)
                    }
                    .buttonStyle(MonoBouncingButtonStyle())
                    .disabled(uin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 24)
                
                if !searchedUsers.isEmpty {
                    userSearchResultsSection
                }
                
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        MonoIcon(icon: .warning, size: 14, color: .red.opacity(0.8))
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        .onAppear {
            if !savedUin.isEmpty { uin = savedUin }
        }
    }
    
    // MARK: - Loading Section
    
    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在获取歌单...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.monoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - User Search Results
    
    private var userSearchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择用户")
                .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(14, weight: .semibold) : .system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary)
                .padding(.horizontal, 28)
            
            ForEach(Array(searchedUsers), id: \.musicid) { user in
                userRow(user)
            }
        }
    }
    
    private func userRow(_ user: QQSearchedUser) -> some View {
        let uid = user.musicid
        let avatar = user.avatarURL
        let name = user.nickname
        let songs = user.songCount
        
        return Button {
            searchedUsers = []
            isLoading = true
            Task {
                await fetchPlaylistsByUin(String(uid))
                if playlists.isEmpty {
                    errorMessage = String(localized: "该用户没有公开歌单")
                }
                isLoading = false
            }
        } label: {
            HStack(spacing: 12) {
                if let url = avatar {
                    CachedAsyncImage(url: url) {
                        Circle()
                            .fill(Color.monoGlassTint)
                            .frame(width: 40, height: 40)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.monoGlassTint)
                        .frame(width: 40, height: 40)
                        .overlay {
                            MonoIcon(icon: .profile, size: 16, color: .monoTextSecondary.opacity(0.5))
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .semibold) : .system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary)
                        .lineLimit(1)
                    if songs > 0 {
                        Text("\(songs) 首歌曲")
                            .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary)
                    }
                }
                
                Spacer()
                
                MonoIcon(icon: .chevronRight, size: 14, color: NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary.opacity(0.5))
            }
            .padding(12)
            .themedPageSurface(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 2 : (NeumorphicStyle.isActive ? 18 : 14), elevated: false)
        }
        .buttonStyle(MonoBouncingButtonStyle())
        .padding(.horizontal, 24)
    }
    
    // MARK: - Playlist List
    
    private var playlistListSection: some View {
        VStack(spacing: 0) {
            if isImporting {
                importProgressBar
            }
            
            HStack {
                Button {
                    withAnimation { playlists = []; selectedIds = []; searchedUsers = []; errorMessage = nil }
                } label: {
                    HStack(spacing: 4) {
                        MonoIcon(icon: .back, size: 12, color: .monoTextSecondary)
                    Text("重新输入")
                            .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(13, weight: .medium) : .system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary)
                    }
                }
                
                Spacer()
                
                Button {
                    if selectedIds.count == playlists.count {
                        selectedIds.removeAll()
                    } else {
                        selectedIds = Set(playlists.map(\.id))
                    }
                } label: {
                    Text(selectedIds.count == playlists.count ? String(localized: "取消全选") : String(localized: "全选"))
                        .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(13, weight: .semibold) : .system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            ScrollView {
                LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                    ForEach(playlists) { playlist in
                        Button {
                            toggleSelection(playlist.id)
                        } label: {
                            qqPlaylistRow(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                .padding(.top, ThemedPageStyle.isActive ? 6 : 4)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
        }
        .disabled(isImporting)
        .opacity(isImporting ? 0.6 : 1)
    }
    
    private func qqPlaylistRow(_ playlist: QQUserPlaylist) -> some View {
        let isSelected = selectedIds.contains(playlist.id)
        return HStack(spacing: 14) {
            ZStack {
                if let url = playlist.coverURL {
                    CachedAsyncImage(url: url) {
                        RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                            .fill(NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : Color.monoGlassTint)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: coverRadius, style: .continuous))
                    .overlay(coverStroke)
                } else {
                    RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                        .fill(NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : Color.monoGlassTint)
                        .frame(width: 52, height: 52)
                        .overlay {
                            MonoIcon(icon: .musicNote, size: 20, color: NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoTextSecondary.opacity(0.4))
                        }
                        .overlay(coverStroke)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .semibold) : .system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary)
                    .lineLimit(1)
                Text("\(playlist.songCount) 首")
                    .font(NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary)
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(isSelected ? MusicSource.qqmusic.themedBadgeColor : Color.monoTextSecondary.opacity(0.3), lineWidth: MangaStyle.isActive ? 2.2 : 2)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Circle()
                        .fill(MusicSource.qqmusic.themedBadgeColor)
                        .frame(width: 24, height: 24)
                    MonoIcon(icon: .checkmark, size: 12, color: MangaStyle.isActive ? MangaStyle.ink : (NeumorphicStyle.isActive ? Color(light: .white, dark: .black) : .white))
                }
            }
        }
        .padding(12)
        .themedPageSurface(
            cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 2 : (NeumorphicStyle.isActive ? 18 : 14),
            elevated: isSelected,
            mangaTint: isSelected ? MangaStyle.bubblePink : MangaStyle.bubbleWhite
        )
    }

    private var importIconRadius: CGFloat {
        NeumorphicStyle.isActive ? 26 : (MangaStyle.isActive ? MangaStyle.cardRadius + 4 : 24)
    }

    private var coverRadius: CGFloat {
        NeumorphicStyle.isActive ? 14 : 10
    }

    @ViewBuilder
    private var coverStroke: some View {
        if NeumorphicStyle.isActive {
            RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
                .stroke(NeumorphicStyle.separator.opacity(0.5), lineWidth: 0.7)
        }
    }
    
    private var importProgressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(importProgress.current), total: Double(max(importProgress.total, 1)))
                .tint(.accentColor)
            Text("正在导入 \(importProgress.current)/\(importProgress.total)...")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.monoTextSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    private func smartSearch() async {
        let trimmed = uin.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        errorMessage = nil
        searchedUsers = []
        isLoading = true
        
        let isNumericOnly = trimmed.allSatisfy(\.isNumber)
        
        if isNumericOnly {
            // 纯数字：先尝试作为 uin 直接获取歌单
            await fetchPlaylistsByUin(trimmed)
            if !playlists.isEmpty {
                isLoading = false
                return
            }
        }
        
        // 非纯数字，或纯数字但直接获取失败 → 搜索用户
        do {
            let searchResult = try await qqClient.search(
                keyword: trimmed,
                type: .user,
                num: 10,
                page: 1,
                highlight: false
            )
            let results = searchResult["user"]?.arrayValue
                ?? searchResult["body"]?["item_user"]?.arrayValue
                ?? searchResult["item_user"]?.arrayValue
                ?? APIService.extractJSONArray(from: searchResult)
            AppLogger.info("[QQImport] 用户搜索返回 \(results.count) 条")
            
            var users: [QQSearchedUser] = []
            for item in results {
                let parsed = Self.parseSearchedUser(item)
                if let user = parsed {
                    users.append(user)
                }
            }
            
            if users.count == 1 {
                // 只有一个结果，直接获取歌单
                await fetchPlaylistsByUin(String(users[0].musicid))
            } else if !users.isEmpty {
                searchedUsers = users
            } else if playlists.isEmpty {
                errorMessage = String(localized: "未找到匹配用户，请检查输入")
            }
        } catch {
            if playlists.isEmpty {
                errorMessage = L10n.format("search_failed_format", error.localizedDescription)
            }
            AppLogger.error("[QQImport] 用户搜索失败: \(error)")
        }
        
        isLoading = false
    }
    
    private func fetchPlaylistsByUin(_ uinStr: String) async {
        guard !uinStr.isEmpty else { return }
        
        do {
            let rawResult = try await qqClient.createdSonglist(uin: uinStr)
            // 新版 API: { playlists: [{ id, dirid, title, picurl, songnum }], total }
            let results = rawResult["playlists"]?.arrayValue
                ?? rawResult["v_playlist"]?.arrayValue
                ?? rawResult.arrayValue ?? []
            AppLogger.info("[QQImport] uin=\(uinStr), 返回 \(results.count) 条")
            
            var parsed: [QQUserPlaylist] = []
            for item in results {
                if let playlist = Self.parseQQPlaylistItem(item) {
                    parsed.append(playlist)
                }
            }
            
            if !parsed.isEmpty {
                savedUin = uinStr
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    playlists = parsed
                }
            }
        } catch {
            AppLogger.warning("[QQImport] uin=\(uinStr) 获取失败: \(error)")
        }
    }
    
    private static func parseQQPlaylistItem(_ item: JSON) -> QQUserPlaylist? {
        let source: JSON
        if let basic = item["basic"] {
            source = basic
        } else if let dirinfo = item["dirinfo"] {
            source = dirinfo
        } else {
            source = item
        }
        
        var tid: Int?
        tid = source["tid"]?.intValue
        if tid == nil { tid = source["id"]?.intValue }
        if tid == nil { tid = source["dissid"]?.intValue }
        if tid == nil { tid = source["songlist_id"]?.intValue }
        if tid == nil { tid = item["tid"]?.intValue }
        if tid == nil { tid = item["id"]?.intValue }
        
        var name: String?
        name = source["dirName"]?.stringValue
        if name == nil { name = source["title"]?.stringValue }
        if name == nil { name = source["diss_name"]?.stringValue }
        if name == nil { name = source["name"]?.stringValue }
        if name == nil { name = item["dirName"]?.stringValue }
        if name == nil { name = item["title"]?.stringValue }
        
        guard let tid = tid, let name = name, !name.isEmpty else {
            AppLogger.warning("[QQImport] 解析失败, keys: \(source.objectValue?.keys.sorted().joined(separator: ", ") ?? String(localized: "非对象"))")
            return nil
        }
        
        var cover: String?
        cover = source["picUrl"]?.stringValue
        if cover == nil { cover = source["picurl"]?.stringValue }
        if cover == nil { cover = source["bigpicUrl"]?.stringValue }
        if cover == nil { cover = source["bigpic_url"]?.stringValue }
        if cover == nil { cover = source["diss_cover"]?.stringValue }
        if cover == nil { cover = source["logo"]?.stringValue }
        if cover == nil { cover = source["coverImgUrl"]?.stringValue }
        if cover == nil { cover = source["cover"]?.stringValue }
        if cover == nil { cover = item["picUrl"]?.stringValue }
        
        var songCount: Int = 0
        if let c = source["songNum"]?.intValue { songCount = c }
        else if let c = source["songnum"]?.intValue { songCount = c }
        else if let c = source["song_cnt"]?.intValue { songCount = c }
        else if let c = source["song_count"]?.intValue { songCount = c }
        else if let c = source["total_song_num"]?.intValue { songCount = c }
        else if let c = source["cur_song_num"]?.intValue { songCount = c }
        else if let c = item["songNum"]?.intValue { songCount = c }
        
        var dirid = source["dirId"]?.intValue ?? 0
        if dirid == 0 { dirid = source["dirid"]?.intValue ?? 0 }
        
        return QQUserPlaylist(
            id: tid,
            name: name,
            coverUrl: cover,
            songCount: songCount,
            dirid: dirid
        )
    }
    
    private func importSelected() async {
        let toImport = playlists.filter { selectedIds.contains($0.id) }
        guard !toImport.isEmpty else { return }
        
        isImporting = true
        importProgress = (0, toImport.count)
        importedCount = 0
        
        for playlist in toImport {
            importProgress.current += 1
            
            do {
                var allSongs: [Song] = []
                var page = 1
                var hasMore = true
                
                while hasMore {
                    let songs: [Song] = try await withCheckedThrowingContinuation { continuation in
                        var resumed = false
                        var cancellable: AnyCancellable?
                        cancellable = APIService.shared.fetchQQPlaylistSongs(playlistId: playlist.id, page: page, num: 50)
                            .sink(receiveCompletion: { completion in
                                if case .failure(let error) = completion, !resumed {
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
                    if songs.count < 50 { hasMore = false }
                    page += 1
                }
                
                if !allSongs.isEmpty {
                    await MainActor.run {
                        manager.importPlaylist(name: playlist.name, songs: allSongs)
                        importedCount += 1
                    }
                }
                AppLogger.info("[QQImport] 导入歌单「\(playlist.name)」成功: \(allSongs.count) 首")
            } catch {
                AppLogger.error("[QQImport] 导入歌单「\(playlist.name)」失败: \(error)")
            }
        }
        
        isImporting = false
        if importedCount > 0 {
            dismiss()
        } else {
            errorMessage = String(localized: "导入失败，请稍后重试")
        }
    }
}

// MARK: - Model

struct QQUserPlaylist: Identifiable {
    let id: Int
    let name: String
    let coverUrl: String?
    let songCount: Int
    let dirid: Int
    
    var coverURL: URL? {
        guard let str = coverUrl, !str.isEmpty else { return nil }
        return URL(string: str)
    }
}

struct QQSearchedUser: Identifiable {
    let musicid: Int
    let nickname: String
    let avatarUrl: String?
    let songCount: Int
    
    var id: Int { musicid }
    
    var avatarURL: URL? {
        guard let str = avatarUrl, !str.isEmpty else { return nil }
        return URL(string: str)
    }
}

// MARK: - User Search Parsing

extension QQPlaylistImportView {
    static func parseSearchedUser(_ item: JSON) -> QQSearchedUser? {
        var musicid: Int?
        musicid = item["uin"]?.intValue
        if musicid == nil { musicid = item["musicid"]?.intValue }
        if musicid == nil { musicid = item["docid"]?.intValue }
        if musicid == nil { musicid = item["creator"]?["musicid"]?.intValue }
        if musicid == nil, let uidStr = item["uin"]?.stringValue { musicid = Int(uidStr) }
        
        var nickname: String?
        nickname = item["title"]?.stringValue
        if nickname == nil { nickname = item["nick"]?.stringValue }
        if nickname == nil { nickname = item["nickname"]?.stringValue }
        if nickname == nil { nickname = item["name"]?.stringValue }
        if nickname == nil { nickname = item["creator"]?["nick"]?.stringValue }
        
        guard let musicid = musicid, let nickname = nickname, !nickname.isEmpty else {
            if let keys = item.objectValue?.keys {
                AppLogger.warning("[QQImport] 用户解析失败, keys: \(keys.sorted().joined(separator: ", "))")
            }
            return nil
        }
        
        // 清理高亮标签
        let cleanName = nickname
            .replacingOccurrences(of: "<em>", with: "")
            .replacingOccurrences(of: "</em>", with: "")
        
        var avatar: String?
        avatar = item["pic"]?.stringValue
        if avatar == nil { avatar = item["avatar"]?.stringValue }
        if avatar == nil { avatar = item["pic_url"]?.stringValue }
        if avatar == nil { avatar = item["creator"]?["avatar"]?.stringValue }
        
        let songCount = item["song_num"]?.intValue
            ?? item["songnum"]?.intValue
            ?? 0
        
        return QQSearchedUser(
            musicid: musicid,
            nickname: cleanName,
            avatarUrl: avatar,
            songCount: songCount
        )
    }
}
