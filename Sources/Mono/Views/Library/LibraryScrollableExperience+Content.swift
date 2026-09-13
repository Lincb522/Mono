import Combine
import QQMusicKit
import SwiftUI
import UniformTypeIdentifiers

extension ScrollableLibraryExperience {
    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .my:
            myLibraryPage
        case .square:
            playlistSquarePage
        case .artists:
            artistsPage
        case .charts:
            chartsPage
        }
    }

    var myLibraryPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            myLibraryControlPanel
            myLibraryColumnContent
        }
    }

    @ViewBuilder
    var myLibraryControlPanel: some View {
        if PetWhiteStyle.isActive {
            petWhiteLibraryControlPanel
        } else if CapsuleStyle.isActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "浏览分区"))
                            .font(CapsuleStyle.titleFont(16, weight: .bold))
                            .foregroundStyle(CapsuleStyle.ink)

                        Text(selectedMyLibraryColumn.title)
                            .font(CapsuleStyle.labelFont(11, weight: .semibold))
                            .foregroundStyle(tint(for: selectedMyLibraryColumn))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isLibraryActionsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            MonoIcon(
                                icon: isLibraryActionsExpanded ? .close : .more,
                                size: 13,
                                color: isLibraryActionsExpanded ? CapsuleStyle.readableLabel(on: defaultAccent) : CapsuleStyle.inkSoft,
                                lineWidth: 1.8
                            )
                            Text(String(localized: "工具"))
                                .font(CapsuleStyle.labelFont(11, weight: .bold))
                                .foregroundStyle(isLibraryActionsExpanded ? CapsuleStyle.readableLabel(on: defaultAccent) : CapsuleStyle.inkSoft)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(isLibraryActionsExpanded ? defaultAccent : Color.clear)
                                .overlay(
                                    Capsule()
                                        .stroke(isLibraryActionsExpanded ? Color.clear : CapsuleStyle.separator.opacity(0.5), lineWidth: 0.9)
                                )
                        )
                    }
                    .buttonStyle(CapsulePressStyle())
                }

                columnStrip

                LibraryDisclosureReveal(isExpanded: isLibraryActionsExpanded) {
                    actionStrip
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
        } else if NeumorphicStyle.isActive {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "浏览分区"))
                            .font(NeumorphicStyle.titleFont(16, weight: .semibold))
                            .foregroundStyle(NeumorphicStyle.ink)

                        Text(selectedMyLibraryColumn.title)
                            .font(NeumorphicStyle.labelFont(11, weight: .medium))
                            .foregroundStyle(tint(for: selectedMyLibraryColumn))
                    }

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            isLibraryActionsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            MonoIcon(icon: isLibraryActionsExpanded ? .close : .more, size: 14, color: isLibraryActionsExpanded ? defaultAccent : NeumorphicStyle.inkSoft, lineWidth: 1.7)
                            Text(String(localized: "工具"))
                                .font(NeumorphicStyle.labelFont(11, weight: .semibold))
                                .foregroundStyle(isLibraryActionsExpanded ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            NeumorphicSurfaceBackground(
                                cornerRadius: 15,
                                elevated: isLibraryActionsExpanded,
                                pressed: !isLibraryActionsExpanded,
                                tint: isLibraryActionsExpanded ? defaultAccent.opacity(0.15) : NeumorphicStyle.surface,
                                lightweight: true
                            )
                        )
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
                }

                columnStrip

                LibraryDisclosureReveal(isExpanded: isLibraryActionsExpanded) {
                    actionStrip
                        .padding(10)
                        .background(
                            NeumorphicSurfaceBackground(
                                cornerRadius: 20,
                                elevated: false,
                                pressed: true,
                                lightweight: true
                            )
                        )
                }
            }
            .padding(13)
            .background(NeumorphicSurfaceBackground(cornerRadius: 24, elevated: true, lightweight: true))
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    columnStrip.layoutPriority(1)

                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            isLibraryActionsExpanded.toggle()
                        }
                    } label: {
                        MonoIcon(icon: isLibraryActionsExpanded ? .close : .more, size: 16, color: isLibraryActionsExpanded ? selectedChipText : secondaryText, lineWidth: 1.8)
                            .frame(width: 42, height: 42)
                            .background(panelBackground(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isLibraryActionsExpanded ? defaultAccent.opacity(0.14) : .clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
                }

                LibraryDisclosureReveal(isExpanded: isLibraryActionsExpanded) {
                    actionStrip
                        .padding(10)
                        .background(panelBackground(cornerRadius: 18))
                }
            }
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
        }
    }

    var petWhiteLibraryControlPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    PetWhiteIconBadge(icon: selectedMyLibraryColumn.icon, tint: tint(for: selectedMyLibraryColumn), size: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "音乐库分区"))
                            .font(PetWhiteStyle.titleFont(15, weight: .black))
                            .foregroundStyle(PetWhiteStyle.ink)
                            .lineLimit(1)

                        Text(selectedMyLibraryColumn.title)
                            .font(PetWhiteStyle.labelFont(10, weight: .semibold))
                            .foregroundStyle(PetWhiteStyle.inkSoft)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isLibraryActionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        PetWhitePackIcon(
                            icon: isLibraryActionsExpanded ? .close : .more,
                            size: 14,
                            visualScale: 1.05,
                            fallbackColor: PetWhiteStyle.ink,
                            lineWidth: 1.75
                        )
                        Text(String(localized: "工具"))
                            .font(PetWhiteStyle.labelFont(10, weight: .black))
                            .foregroundStyle(PetWhiteStyle.ink)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        PetWhiteSurfaceBackground(
                            cornerRadius: 13,
                            elevated: isLibraryActionsExpanded,
                            tint: isLibraryActionsExpanded ? tint(for: selectedMyLibraryColumn).opacity(0.22) : PetWhiteStyle.surfacePressed,
                            accent: tint(for: selectedMyLibraryColumn)
                        )
                    )
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
            }

            columnStrip

            LibraryDisclosureReveal(isExpanded: isLibraryActionsExpanded) {
                actionStrip
                    .padding(8)
                    .background(
                        PetWhiteSurfaceBackground(
                            cornerRadius: 20,
                            elevated: false,
                            tint: PetWhiteStyle.surfacePressed,
                            accent: tint(for: selectedMyLibraryColumn)
                        )
                    )
            }
        }
        .padding(9)
        .background(
            PetWhiteSurfaceBackground(
                cornerRadius: 21,
                elevated: true,
                tint: PetWhiteStyle.surfaceRaised,
                accent: tint(for: selectedMyLibraryColumn)
            )
        )
        .padding(.horizontal, contentHorizontalPadding)
    }

    var columnStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: PetWhiteStyle.isActive ? 6 : 8) {
                ForEach(MyLibraryColumn.allCases, id: \.self) { column in
                    let selected = selectedMyLibraryColumn == column
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selectedMyLibraryColumn = column
                        }
                        if column == .qcmPlaylists {
                            loadQQUserPlaylistsIfNeeded()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if PetWhiteStyle.isActive {
                                PetWhitePackIcon(
                                    icon: column.icon,
                                    size: 13,
                                    visualScale: selected ? 1.08 : 1,
                                    fallbackColor: selected ? PetWhiteStyle.ink : PetWhiteStyle.inkSoft,
                                    lineWidth: selected ? 1.9 : 1.55
                                )
                            } else {
                                MonoIcon(icon: column.icon, size: 14, color: selected ? selectedChipText : secondaryText, lineWidth: selected ? 2 : 1.6)
                            }
                            Text(column.title)
                                .font(chipFont(selected: selected))
                                .foregroundColor(selected ? selectedChipText : secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, PetWhiteStyle.isActive ? 10 : 12)
                        .frame(minHeight: PetWhiteStyle.isActive ? 34 : 42)
                        .background(chipBackground(selected: selected, tint: tint(for: column), capsule: true))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                }
            }
            .padding(.horizontal, 1)
            .padding(.top, PetWhiteStyle.isActive ? 1 : 2)
            .padding(.bottom, PetWhiteStyle.isActive ? 4 : 6)
        }
        .padding(.top, PetWhiteStyle.isActive ? -1 : -2)
        .padding(.bottom, PetWhiteStyle.isActive ? -4 : -6)
        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
    }

    @ViewBuilder
    var myLibraryColumnContent: some View {
        switch selectedMyLibraryColumn {
        case .localPlaylists: localPlaylistsSection
        case .ncmPlaylists: ncmPlaylistsSection
        case .qcmPlaylists: qcmPlaylistsSection
        case .kcmPlaylists: kcmPlaylistsSection
        case .appleMusic:
            AppleMusicLibraryView(embeddedInParentScroll: true)
                .padding(.horizontal, contentHorizontalPadding)
        case .localPodcasts: localPodcastsSection
        case .ncmPodcasts: ncmPodcastsSection
        }
    }

    var actionStrip: some View {
        LazyVGrid(columns: actionColumns, spacing: 9) {
            actionChip(title: String(localized: "lib_create"), icon: .add, tint: defaultAccent) {
                createLocalPlaylist()
            }

            actionChip(title: String(localized: "lib_import_playlist"), icon: .download, tint: secondaryAccent, isLoading: isImporting) {
                showFileImporter = true
            }
            .disabled(isImporting)

            actionChip(title: String(localized: "从链接导入"), icon: .share, tint: tertiaryAccent, isLoading: isImporting) {
                showImportLinkPrompt()
            }
            .disabled(isImporting)

            actionChip(title: String(localized: "QCM歌单"), icon: .musicNoteList, tint: MusicSource.qqmusic.themedBadgeColor) {
                showQQImport = true
            }
        }
    }

    var localPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.localPlaylists.title)

            if localManager.playlists.isEmpty {
                ThemedLibraryEmptyState(icon: .musicNoteList, title: String(localized: "lib_no_local_playlists"), tint: defaultAccent)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(localManager.playlists, id: \.id) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.localPlaylist(playlist.id)) {
                            LocalPlaylistRow(summary: localManager.summary(for: playlist))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var ncmPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.ncmPlaylists.title)

            if viewModel.userPlaylists.isEmpty {
                ThemedLibraryEmptyState(icon: .list, title: String(localized: "empty_no_playlists"), tint: MusicSource.netease.themedBadgeColor)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.userPlaylists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            LibraryPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var qcmPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.qcmPlaylists.title)

            if isLoadingQQUserPlaylists && qqUserPlaylists.isEmpty {
                LibraryLoadingStateView()
            } else if !qqSession.isLoggedIn {
                ThemedLibraryEmptyState(icon: .musicNoteList, title: String(localized: "qcm_login_required"), tint: MusicSource.qqmusic.themedBadgeColor)
                    .padding(.horizontal, contentHorizontalPadding)
            } else if qqUserPlaylists.isEmpty {
                ThemedLibraryEmptyState(icon: .list, title: String(localized: "暂无 QCM 歌单"), tint: MusicSource.qqmusic.themedBadgeColor)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(qqUserPlaylists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            LibraryPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var kcmPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.kcmPlaylists.title)

            if !KCMMusicService.shared.isAuthenticated {
                ThemedLibraryEmptyState(icon: .musicNoteList, title: "请先登录 KCM", tint: MusicSource.kugou.themedBadgeColor)
                    .padding(.horizontal, contentHorizontalPadding)
            } else if viewModel.kugouUserPlaylists.isEmpty {
                ThemedLibraryEmptyState(icon: .list, title: "暂无 KCM 歌单", tint: MusicSource.kugou.themedBadgeColor)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.kugouUserPlaylists) { playlist in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.playlist(playlist)) {
                            LibraryPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var localPodcastsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.localPodcasts.title)

            if subManager.localSubscribedRadios.isEmpty {
                ThemedLibraryEmptyState(icon: .radio, title: String(localized: "暂无本地收藏"), tint: tertiaryAccent)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(subManager.localSubscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            ThemedLibraryPodcastRow(radio: radio, tint: tertiaryAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var ncmPodcastsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemedLibrarySectionHeader(title: MyLibraryColumn.ncmPodcasts.title)

            if subManager.isLoadingRadios && subManager.subscribedRadios.isEmpty {
                LibraryLoadingStateView()
            } else if subManager.subscribedRadios.isEmpty {
                ThemedLibraryEmptyState(icon: .radio, title: String(localized: "lib_no_podcasts"), tint: secondaryAccent)
                    .padding(.horizontal, contentHorizontalPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(subManager.subscribedRadios) { radio in
                        NavigationLink(value: LibraryViewModel.NavigationDestination.radioDetail(radio.id)) {
                            ThemedLibraryPodcastRow(radio: radio, tint: secondaryAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
            }
        }
    }

    var playlistSquarePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            sourceStrip(selected: viewModel.squareSource) { source in
                viewModel.squareSource = source
                viewModel.fetchSquareForSelectedSource()
            }
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)

            if viewModel.squareSource == .qq {
                qqCategoryBar
                playlistGrid(playlists: viewModel.qqSquarePlaylists, isLoading: viewModel.isLoadingQQSquare, emptyTitle: String(localized: "暂无QCM推荐歌单"))

                if viewModel.hasMoreQQSquare && !viewModel.qqSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreQQSquarePlaylists() }
                }
            } else if viewModel.squareSource == .kugou {
                kugouCategoryBar
                playlistGrid(playlists: viewModel.kugouSquarePlaylists, isLoading: viewModel.isLoadingKugouSquare, emptyTitle: "暂无KCM推荐歌单")

                if viewModel.hasMoreKugouSquare && !viewModel.kugouSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreKugouSquarePlaylists() }
                }
            } else if viewModel.squareSource == .appleMusic {
                playlistGrid(playlists: viewModel.appleMusicSquarePlaylists, isLoading: viewModel.isLoadingAppleMusicSquare, emptyTitle: String(localized: "empty_no_playlists"))

                if viewModel.hasMoreAppleMusicSquare && !viewModel.appleMusicSquarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreAppleMusicSquarePlaylists() }
                }
            } else {
                ncmCategoryBar
                playlistGrid(playlists: viewModel.squarePlaylists, isLoading: viewModel.isLoadingSquare, emptyTitle: String(localized: "empty_no_playlists"))

                if viewModel.hasMoreSquarePlaylists && !viewModel.squarePlaylists.isEmpty {
                    loadMoreButton { viewModel.loadMoreSquarePlaylists() }
                }
            }
        }
    }

    var artistsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                sourceStrip(selected: viewModel.artistSource, sources: [.ncm, .qq, .kugou, .appleMusic]) { source in
                    viewModel.artistSource = source
                    viewModel.fetchArtistsForSelectedSource(reset: true)
                }

                Spacer(minLength: 0)

                Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            isArtistFiltersExpanded.toggle()
                        }
                    } label: {
                        if PetWhiteStyle.isActive {
                            HStack(spacing: 6) {
                                PetWhitePackIcon(
                                    icon: isArtistFiltersExpanded ? .close : .filter,
                                    size: 14,
                                    visualScale: 1.05,
                                    fallbackColor: PetWhiteStyle.ink,
                                    lineWidth: 1.75
                                )
                                Text(isArtistFiltersExpanded ? String(localized: "收起") : String(localized: "筛选"))
                                    .font(PetWhiteStyle.labelFont(11, weight: .black))
                                    .foregroundStyle(PetWhiteStyle.ink)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                PetWhiteSurfaceBackground(
                                    cornerRadius: 14,
                                    elevated: isArtistFiltersExpanded,
                                    tint: isArtistFiltersExpanded ? PetWhiteStyle.mint.opacity(0.22) : PetWhiteStyle.surfacePressed,
                                    accent: PetWhiteStyle.mint
                                )
                            )
                        } else if NeumorphicStyle.isActive {
                            HStack(spacing: 6) {
                                MonoIcon(icon: isArtistFiltersExpanded ? .close : .filter, size: 14, color: isArtistFiltersExpanded ? defaultAccent : NeumorphicStyle.inkSoft, lineWidth: 1.7)
                                Text(isArtistFiltersExpanded ? String(localized: "收起") : String(localized: "筛选"))
                                    .font(NeumorphicStyle.labelFont(11, weight: .semibold))
                                    .foregroundStyle(isArtistFiltersExpanded ? NeumorphicStyle.ink : NeumorphicStyle.inkSoft)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                NeumorphicSurfaceBackground(
                                    cornerRadius: 15,
                                    elevated: isArtistFiltersExpanded,
                                    pressed: !isArtistFiltersExpanded,
                                    tint: isArtistFiltersExpanded ? defaultAccent.opacity(0.15) : NeumorphicStyle.surface,
                                    lightweight: true
                                )
                            )
                        } else {
                            HStack(spacing: 6) {
                                MonoIcon(icon: isArtistFiltersExpanded ? .close : .filter, size: 14, color: isArtistFiltersExpanded ? selectedChipText : secondaryText, lineWidth: 1.8)
                                Text(isArtistFiltersExpanded ? String(localized: "收起") : String(localized: "筛选"))
                                    .font(chipFont(selected: isArtistFiltersExpanded))
                                    .foregroundColor(isArtistFiltersExpanded ? selectedChipText : secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(panelBackground(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isArtistFiltersExpanded ? defaultAccent.opacity(0.14) : .clear)
                            )
                        }
                    }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.94))
            }
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)

            LibraryDisclosureReveal(isExpanded: isArtistFiltersExpanded) {
                VStack(spacing: 10) {
                    if viewModel.artistSource == .qq {
                        qqArtistFilterBars
                    } else if viewModel.artistSource == .kugou {
                        kugouArtistFilterBars
                    } else if viewModel.artistSource == .appleMusic {
                        appleMusicArtistFilterBar
                    } else if viewModel.artistSource == .ncm {
                        ncmArtistFilterBars
                    }
                }
                .padding(.top, 4) // Prevents first row top outline clipping in LibraryDisclosureReveal
                .padding(.bottom, 6) // Prevents last row bottom shadow clipping in LibraryDisclosureReveal
            }

            if viewModel.artistSource == .qq {
                artistGrid(artists: viewModel.qqArtists, isLoading: viewModel.isLoadingQQArtists, tint: MusicSource.qqmusic.themedBadgeColor)
                if viewModel.hasMoreQQArtists && !viewModel.qqArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreQQArtists() }
                }
            } else if viewModel.artistSource == .kugou {
                artistGrid(artists: viewModel.kugouArtists, isLoading: viewModel.isLoadingKugouArtists, tint: MusicSource.kugou.themedBadgeColor)
            } else if viewModel.artistSource == .appleMusic {
                artistGrid(artists: viewModel.appleMusicArtists, isLoading: viewModel.isLoadingAppleMusicArtists, tint: MusicSource.appleMusic.themedBadgeColor)
                if viewModel.hasMoreAppleMusicArtists && !viewModel.appleMusicArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreAppleMusicArtists() }
                }
            } else {
                artistGrid(artists: viewModel.topArtists, isLoading: viewModel.isLoadingArtists, tint: tertiaryAccent)
                if viewModel.hasMoreArtists && !viewModel.topArtists.isEmpty {
                    loadMoreButton { viewModel.loadMoreArtists() }
                }
            }
        }
    }

    var chartsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceStrip(selected: viewModel.chartsSource, sources: [.ncm, .qq, .kugou, .appleMusic]) { source in
                viewModel.chartsSource = source
                viewModel.fetchChartsForSelectedSource()
            }
            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)

            if viewModel.chartsSource == .qq {
                qqChartsContent
            } else {
                if viewModel.isLoadingDisplayedCharts && viewModel.displayedTopLists.isEmpty {
                    LibraryLoadingStateView()
                } else if viewModel.displayedTopLists.isEmpty {
                    ThemedLibraryEmptyState(icon: .chart, title: String(localized: "empty_no_charts"), tint: secondaryAccent)
                        .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
                } else {
                    let officialIds: Set<Int> = [19_723_756, 3_779_629, 2_884_035, 3_778_678]
                    let official = viewModel.displayedTopLists.filter { officialIds.contains($0.id) }
                    let others = viewModel.displayedTopLists.filter { !officialIds.contains($0.id) }

                    if !official.isEmpty {
                        ThemedLibrarySectionHeader(title: String(localized: "charts_official"))
                        ScrollView(.horizontal) {
                            HStack(spacing: 14) {
                                ForEach(official) { list in
                                    NavigationLink(value: chartDestination(list)) {
                                        OfficialChartCard(list: list)
                                    }
                                    .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                                }
                            }
                            .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
                        }
                        .scrollIndicators(.hidden)
                        .themeRenderScrollLayer()
                    }

                    if !others.isEmpty {
                        ThemedLibrarySectionHeader(title: String(localized: "charts_more"))
                        LazyVGrid(columns: artistColumns, spacing: 16) {
                            ForEach(others) { list in
                                NavigationLink(value: chartDestination(list)) {
                                    CompactChartCard(list: list)
                                }
                                .buttonStyle(MonoBouncingButtonStyle(scale: 0.95))
                            }
                        }
                        .padding(.horizontal, DeviceLayout.libraryHorizontalPadding)
                    }
                }
            }
        }
    }

}
