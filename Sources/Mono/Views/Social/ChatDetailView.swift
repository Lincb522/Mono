import SwiftUI
import Combine

// MARK: - 聊天详情

struct ChatDetailView: View {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    
    @StateObject private var viewModel = ChatDetailViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 消息列表
                if viewModel.isLoading && viewModel.messages.isEmpty {
                    Spacer()
                    MonoLoadingView(text: "LOADING CHAT")
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.messages) { msg in
                                    ChatBubble(
                                        message: msg,
                                        isMe: msg.fromUserId == APIService.shared.currentUserId
                                    )
                                    .id(msg.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollIndicators(.hidden)
            .themeRenderScrollLayer()
                        .onChange(of: viewModel.messages.count) {
                            if let last = viewModel.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                
                // 输入栏
                HStack(spacing: 12) {
                    TextField(String(localized: "message_input_placeholder"), text: $inputText)
                        .font(chatInputFont)
                        .monoTextInputBehavior()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ThemedPageStyle.isActive ? Color.clear : Color.monoGlassTint)
                        .themedOnlyPageSurface(cornerRadius: 20, elevated: false)
                        .clipShape(Capsule())
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .monoOnSubmit(text: $inputText) { _ in
                            sendMessage()
                        }
                    
                    Button {
                        MonoTextInputCommitter.commit(text: $inputText) { _ in
                            sendMessage()
                        }
                    } label: {
                        MonoIcon(icon: .send, size: 20, color: inputText.isEmpty ? chatMutedText.opacity(0.58) : chatAccent)
                            .frame(width: 40, height: 40)
                            .background(chatButtonFill)
                            .clipShape(Circle())
                    }
                    .disabled(inputText.isEmpty)
                    .buttonStyle(MonoBouncingButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .themedPageSurface(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 4 : 16, elevated: false)
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton()
        .onAppear { viewModel.fetchHistory(uid: userId) }
    }

    private var chatInputFont: Font {
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(15, weight: .medium) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(15, weight: .medium) }
        return .system(size: 15, design: .rounded)
    }

    private var chatAccent: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.accent }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        return .monoTextPrimary
    }

    private var chatMutedText: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkMuted }
        return .monoTextSecondary
    }

    private var chatButtonFill: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoGlassTint
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendText(userIds: [userId], msg: text)
    }
}

// MARK: - 聊天气泡

private struct ChatBubble: View {
    let message: ChatMessage
    let isMe: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMe { Spacer(minLength: 60) }
            
            if !isMe {
                if let url = message.fromAvatarURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(avatarFill)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(avatarFill)
                        .frame(width: 36, height: 36)
                }
            }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                Text(message.msg)
                    .font(bubbleFont)
                    .foregroundColor(bubbleTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: MangaStyle.isActive ? MangaStyle.cardRadius + 2 : 16, style: .continuous))
                    .overlay {
                        if MangaStyle.isActive {
                            RoundedRectangle(cornerRadius: MangaStyle.cardRadius + 2, style: .continuous)
                                .stroke(MangaStyle.strokeInk, lineWidth: MangaStyle.strokeWidth)
                        } else if MujiStyle.isActive {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(MujiStyle.hairline.opacity(0.35), lineWidth: 0.6)
                        } else if SequoiaStyle.isActive {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(SequoiaStyle.separator, lineWidth: 0.65)
                        } else if NeumorphicStyle.isActive {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(NeumorphicStyle.separator.opacity(0.42), lineWidth: 0.7)
                        }
                    }
                    .monoGlass(cornerRadius: 16)
                
                Text(message.timeText)
                    .font(SequoiaStyle.isActive ? SequoiaStyle.labelFont(10, weight: .medium) : (NeumorphicStyle.isActive ? NeumorphicStyle.labelFont(10, weight: .medium) : .system(size: 10, weight: .medium, design: .rounded)))
                    .foregroundColor(SequoiaStyle.isActive ? SequoiaStyle.inkMuted : (NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : .monoTextSecondary.opacity(0.5)))
            }
            
            if !isMe { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: Color {
        if MangaStyle.isActive {
            return isMe ? MangaStyle.bubblePink : MangaStyle.bubbleWhite
        } else if MujiStyle.isActive {
            return isMe ? MujiStyle.clay : MujiStyle.surfaceRaised
        } else if SequoiaStyle.isActive {
            return isMe ? SequoiaStyle.selectedWash : SequoiaStyle.materialList.opacity(0.78)
        } else if NeumorphicStyle.isActive {
            return isMe ? NeumorphicStyle.accent.opacity(0.18) : NeumorphicStyle.surfacePressed.opacity(0.74)
        } else {
            return isMe ? Color.monoAccent.opacity(0.15) : Color.monoGlassTint
        }
    }

    private var bubbleTextColor: Color {
        if MangaStyle.isActive {
            return MangaStyle.ink
        } else if MujiStyle.isActive {
            return isMe ? MujiStyle.paper : .monoTextPrimary
        } else if SequoiaStyle.isActive {
            return isMe ? SequoiaStyle.accent : SequoiaStyle.ink
        } else if NeumorphicStyle.isActive {
            return isMe ? NeumorphicStyle.accent : NeumorphicStyle.ink
        } else {
            return isMe ? .white : .monoTextPrimary
        }
    }

    private var bubbleFont: Font {
        if MangaStyle.isActive { return MangaStyle.comicFont(14, weight: .medium) }
        if MujiStyle.isActive { return MujiStyle.bodyFont(14, weight: .regular) }
        if SequoiaStyle.isActive { return SequoiaStyle.bodyFont(14, weight: .regular) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.bodyFont(14, weight: .medium) }
        return .system(size: 14, weight: .regular, design: .rounded)
    }

    private var avatarFill: Color {
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        return Color.monoSeparator
    }
}

// MARK: - ViewModel

@MainActor
class ChatDetailViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    
    private var cancellables = Set<AnyCancellable>()
    private var historyRequest: AnyCancellable?
    private var historyRequestID = 0
    
    func fetchHistory(uid: Int) {
        historyRequestID += 1
        let requestID = historyRequestID
        historyRequest?.cancel()
        isLoading = true
        historyRequest = APIService.shared.fetchPrivateHistory(uid: uid)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                guard let self, self.historyRequestID == requestID else { return }
                self.isLoading = false
            }, receiveValue: { [weak self] msgs in
                guard let self, self.historyRequestID == requestID else { return }
                self.messages = msgs.reversed()
            })
    }
    
    func sendText(userIds: [Int], msg: String) {
        APIService.shared.sendTextMessage(userIds: userIds, msg: msg)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] _ in
                // 发送成功后刷新
                if let uid = userIds.first {
                    self?.fetchHistory(uid: uid)
                }
            })
            .store(in: &cancellables)
    }
}
