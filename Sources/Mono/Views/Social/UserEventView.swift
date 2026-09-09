import SwiftUI
import Combine

// MARK: - 用户动态

private enum EventThemePalette {
    static var accent: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoAccent
    }

    static var accentForeground: Color {
        if NeumorphicStyle.isActive {
            return ThemeColorCustomization.readableForegroundColor(
                on: NeumorphicStyle.accent,
                light: Color(hex: "172026"),
                dark: .white
            )
        }
        return .monoIconForeground
    }

    static var primaryText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary
    }

    static var secondaryText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkSoft : .monoTextSecondary
    }

    static var mutedText: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : .monoTextSecondary
    }

    static var pressedSurface: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : .monoSeparator
    }
}

struct UserEventView: View {
    @StateObject private var viewModel = UserEventViewModel()
    private let playerManager = PlayerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    Spacer()
                    MonoLoadingView(text: "LOADING EVENTS")
                    Spacer()
                } else if viewModel.events.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        MonoIcon(icon: .send, size: 40, color: EventThemePalette.mutedText.opacity(0.36))
                        Text(LocalizedStringKey("event_empty"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(EventThemePalette.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.events) { event in
                                EventCard(event: event) {
                                    if let song = event.song {
                                        playerManager.play(song: song, in: [song])
                                    }
                                }
                            }
                            
                            // 加载更多
                            if viewModel.hasMore {
                                Button(action: { viewModel.loadMore() }) {
                                    Text(LocalizedStringKey("event_load_more"))
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(EventThemePalette.secondaryText)
                                        .padding(.vertical, 12)
                                }
                            } else if !viewModel.events.isEmpty {
                                NoMoreDataView()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        FloatingBarBottomSpacer()
                    }
                    .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                }
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear { viewModel.fetchEvents() }
    }
}

// MARK: - 动态卡片

private struct EventCard: View {
    let event: UserEvent
    let onPlaySong: () -> Void
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        let _ = settings.globalThemeRevision

        VStack(alignment: .leading, spacing: 12) {
            // 用户信息 + 时间
            HStack(spacing: 10) {
                if let url = event.userAvatarURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(EventThemePalette.pressedSurface)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(EventThemePalette.pressedSurface)
                        .frame(width: 38, height: 38)
                        .overlay(MonoIcon(icon: .profile, size: 16, color: EventThemePalette.mutedText.opacity(0.55)))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.userName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(EventThemePalette.primaryText)
                    
                    HStack(spacing: 6) {
                        if !event.actName.isEmpty {
                            Text(event.actName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(EventThemePalette.accentForeground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EventThemePalette.accent.opacity(NeumorphicStyle.isActive ? 0.95 : 0.5))
                                .clipShape(Capsule())
                        }
                        Text(event.timeText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(EventThemePalette.mutedText.opacity(0.72))
                    }
                }
                
                Spacer()
            }
            
            // 动态内容
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(EventThemePalette.primaryText)
                    .lineLimit(5)
            }
            
            // 关联歌曲
            if let song = event.song {
                Button(action: onPlaySong) {
                    HStack(spacing: 10) {
                        CachedAsyncImage(url: song.coverUrl) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(EventThemePalette.pressedSurface)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(EventThemePalette.primaryText)
                                .lineLimit(1)
                            Text(song.artistName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(EventThemePalette.secondaryText)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        MonoIcon(icon: .play, size: 14, color: NeumorphicStyle.isActive ? EventThemePalette.accent : EventThemePalette.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(EventThemePalette.pressedSurface)
                            .clipShape(Circle())
                    }
                    .padding(10)
                    .background {
                        if NeumorphicStyle.isActive {
                            NeumorphicSurfaceBackground(cornerRadius: 12, elevated: false, pressed: true, lightweight: true)
                        } else {
                            Color.monoSeparator.opacity(0.5)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.98))
            }
        }
        .padding(16)
        .themedPageSurface(cornerRadius: 18, elevated: true, mangaTint: MangaStyle.bubbleWhite)
        .clipShape(RoundedRectangle(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 4 : 16, style: .continuous))
    }
}

// MARK: - ViewModel

@MainActor
class UserEventViewModel: ObservableObject {
    @Published var events: [UserEvent] = []
    @Published var isLoading = false
    @Published var hasMore = false
    
    private var lasttime: Int = -1
    private var cancellables = Set<AnyCancellable>()
    
    func fetchEvents() {
        guard let uid = APIService.shared.currentUserId else { return }
        isLoading = true
        lasttime = -1
        
        APIService.shared.fetchUserEvents(uid: uid, lasttime: -1)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
            }, receiveValue: { [weak self] result in
                self?.events = result.events
                self?.lasttime = result.lasttime
                self?.hasMore = result.more
            })
            .store(in: &cancellables)
    }
    
    func loadMore() {
        guard let uid = APIService.shared.currentUserId, hasMore else { return }
        
        APIService.shared.fetchUserEvents(uid: uid, lasttime: lasttime)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] result in
                self?.events.append(contentsOf: result.events)
                self?.lasttime = result.lasttime
                self?.hasMore = result.more
            })
            .store(in: &cancellables)
    }
}
