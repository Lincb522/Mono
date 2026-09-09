import SwiftUI
import Combine

// MARK: - 私信列表

struct MessageListView: View {
    @StateObject private var viewModel = MessageListViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    private var themeSecondaryText: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        return .monoTextSecondary
    }

    private var themeEmptyIcon: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted.opacity(0.42) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted.opacity(0.42) }
        return .monoTextSecondary.opacity(0.3)
    }
    
    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.messages.isEmpty {
                    Spacer()
                    MonoLoadingView(text: "LOADING MESSAGES")
                    Spacer()
                } else if viewModel.messages.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        MonoIcon(icon: .send, size: 40, color: themeEmptyIcon)
                        Text(LocalizedStringKey("message_empty"))
                            .font(SequoiaStyle.isActive ? SequoiaStyle.bodyFont(15, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .medium) : .system(size: 15, weight: .medium, design: .rounded)))
                            .foregroundColor(themeSecondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: ThemedPageStyle.listSpacing) {
                            ForEach(viewModel.messages) { msg in
                                NavigationLink(destination: ChatDetailView(userId: msg.userId, nickname: msg.nickname, avatarUrl: msg.avatarUrl)) {
                                    MessageRow(message: msg)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, ThemedPageStyle.horizontalInset)
                        .padding(.top, 8)
                        
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
        .onAppear { viewModel.fetchMessages() }
    }
}

// MARK: - 私信行

private struct MessageRow: View {
    let message: PrivateMessage

    private var text: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var secondaryText: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        return .monoTextSecondary
    }

    private var mutedText: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary.opacity(0.6)
    }

    private var accent: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        return .monoTextSecondary.opacity(0.5)
    }

    private var avatarFill: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoSeparator
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // 头像
            ZStack(alignment: .topTrailing) {
                if let url = message.avatarURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(avatarFill)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(avatarFill)
                        .frame(width: 50, height: 50)
                        .overlay(MonoIcon(icon: .profile, size: 22, color: accent))
                }
                
                // 未读标记
                if message.newMsgCount > 0 {
                    Text("\(min(message.newMsgCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.nickname)
                        .font(SequoiaStyle.isActive ? SequoiaStyle.bodyFont(15, weight: .semibold) : (NeumorphicStyle.isActive ? NeumorphicStyle.bodyFont(15, weight: .semibold) : .system(size: 15, weight: .semibold, design: .rounded)))
                        .foregroundColor(text)
                        .lineLimit(1)
                    Spacer()
                    Text(message.timeText)
                        .font(SequoiaStyle.isActive ? SequoiaStyle.labelFont(12) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(12, weight: .medium) : .system(size: 12, weight: .medium, design: .rounded)))
                        .foregroundColor(mutedText)
                }
                
                Text(message.lastMsg)
                    .font(SequoiaStyle.isActive ? SequoiaStyle.labelFont(13, weight: .regular) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(13, weight: .medium) : .system(size: 13, weight: .regular, design: .rounded)))
                    .foregroundColor(secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ThemedPageStyle.isActive ? 16 : 20)
        .padding(.vertical, 12)
        .themedOnlyPageSurface(cornerRadius: ThemedPageStyle.compactSurfaceCornerRadius, elevated: false)
        .contentShape(Rectangle())
    }
}

// MARK: - ViewModel

@MainActor
class MessageListViewModel: ObservableObject {
    @Published var messages: [PrivateMessage] = []
    @Published var isLoading = false
    
    private var request: AnyCancellable?
    
    func fetchMessages() {
        guard !isLoading else { return }
        isLoading = true
        request = APIService.shared.fetchPrivateMessages()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
            }, receiveValue: { [weak self] msgs in
                self?.messages = msgs
            })
    }
}
