import SwiftUI
import SwiftPixelGrid

/// 播放器主题选择面板 — 毛玻璃背景 + 精致卡片预览
struct PlayerThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monoSheetDismiss) private var monoSheetDismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.monoSheetContext) private var monoSheetContext
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var themeManager = PlayerThemeManager.shared

    var body: some View {
        let _ = settings.globalThemeRevision

        VStack(spacing: 16) {
            if monoSheetContext == nil {
                Capsule()
                    .fill(Color.monoTextSecondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
            }

            // 标题
            Text("theme_title")
                .font(NeumorphicStyle.isActive ? NeumorphicStyle.titleFont(20, weight: .semibold) : .rounded(size: 20, weight: .bold))
                .foregroundColor(NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary)
                .padding(.bottom, 4)

            // 主题卡片网格 - 使用 ScrollView 确保内容可滚动
            ScrollView(.vertical) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    ForEach(PlayerTheme.allCases, id: \.self) { theme in
                        themeCard(theme)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .iPadContentWidth(600)
        .background(sheetBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private var sheetBackground: some View {
        Color.clear
    }

    private func themeCard(_ theme: PlayerTheme) -> some View {
        let isSelected = themeManager.currentTheme == theme

        return Button {
            themeManager.setTheme(theme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismissCurrentPresentation(systemDismiss: dismiss, monoSheetDismiss: monoSheetDismiss)
            }
        } label: {
            // 海报卡：主题名排进海报里，不再在卡片下方挂标签
            ZStack(alignment: .topTrailing) {
                themePreview(theme)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
                            .stroke(
                                previewStrokeColor(isSelected: isSelected),
                                lineWidth: isSelected ? (NeumorphicStyle.isActive ? 1.4 : 2) : 1
                            )
                    )
                    .shadow(
                        color: previewShadowColor(isSelected: isSelected),
                        radius: NeumorphicStyle.isActive ? 10 : 8,
                        x: 0,
                        y: NeumorphicStyle.isActive ? 6 : 4
                    )

                if isSelected {
                    ZStack {
                        Circle().fill(selectedTint)
                        MonoIcon(icon: .checkmark, size: 10, color: .white, lineWidth: 2.2)
                    }
                    .frame(width: 21, height: 21)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.1))
                    .shadow(color: selectedTint.opacity(0.35), radius: 5, y: 2)
                    .padding(7)
                }
            }
            .padding(NeumorphicStyle.isActive ? 10 : 0)
            .background {
                if NeumorphicStyle.isActive {
                    NeumorphicSurfaceBackground(
                        cornerRadius: 24,
                        elevated: !isSelected,
                        pressed: isSelected,
                        tint: isSelected ? selectedTint.opacity(0.18) : nil
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var previewCornerRadius: CGFloat {
        NeumorphicStyle.isActive ? 18 : 16
    }

    private var selectedTint: Color {
        NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoAccent
    }

    private func previewStrokeColor(isSelected: Bool) -> Color {
        if NeumorphicStyle.isActive {
            return isSelected ? NeumorphicStyle.accent.opacity(0.52) : NeumorphicStyle.separator.opacity(0.38)
        }
        return isSelected
            ? Color.monoAccent
            : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.monoSeparator)
    }

    private func previewShadowColor(isSelected: Bool) -> Color {
        if NeumorphicStyle.isActive {
            return isSelected ? NeumorphicStyle.darkShadow(colorScheme, intensity: 0.22) : .clear
        }
        return isSelected
            ? Color.monoAccent.opacity(colorScheme == .dark ? 0.3 : 0.15)
            : Color.clear
    }

    /// 每种主题的缩略预览
    @ViewBuilder
    private func themePreview(_ theme: PlayerTheme) -> some View {
        PlayerThemeStaticPreview(theme: theme)
    }
}

/// 主题缩略预览 — 海报卡：主题标志物放大铺满 + 左下角主题名题签。
/// 不再给每张卡挂同一套「进度条 + 三键」假控制台，识别度来自
/// 标志物、配色与题签排印本身。
private struct PlayerThemeStaticPreview: View {
    let theme: PlayerTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { isDark ? Color.white.opacity(0.92) : Color(hex: "141414") }
    private var muted: Color { isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.36) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewBackground

            motif
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 30)

            caption
                .padding(.horizontal, 11)
                .padding(.bottom, 10)
        }
        .clipped()
    }

    // MARK: - 题签（主题名排进海报）

    private var caption: some View {
        HStack(spacing: 5.5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(captionTint)
                .frame(width: 3, height: 10)

            Text(theme.displayName)
                .font(captionFont)
                .foregroundColor(captionInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var captionFont: Font {
        switch theme {
        case .typewriter, .folk, .muji:
            return .system(size: 11.5, weight: .semibold, design: .serif)
        case .pixel, .motoPager, .dotMatrix, .console:
            return .system(size: 11, weight: .bold, design: .monospaced)
        default:
            return .system(size: 11.5, weight: .bold, design: .rounded)
        }
    }

    /// 题签强调色（各主题的招牌色）
    private var captionTint: Color {
        switch theme {
        case .classic:        return ink
        case .vinyl:          return Color(hex: "D7B56D")
        case .lyricFocus:     return Color(hex: "7A8CFF")
        case .card:           return Color(hex: "FF7CA8")
        case .neumorphic:     return Color(hex: "4F8E86")
        case .poster:         return Color(hex: "EF2A2A")
        case .motoPager:      return isDark ? Color(hex: "A8B47B") : Color(hex: "5F6D3A")
        case .typewriter:     return Color(hex: "E9DCC8")
        case .pixel:          return isDark ? Color(hex: "30FF6A") : Color(hex: "1E8C43")
        case .aqua:           return Color(hex: "2E86C1")
        case .breathing:      return Color(hex: "58D7FF")
        case .bloud:          return ink
        case .cassette:       return ink
        case .radio:          return Color(hex: "DCC8FF")
        case .immersiveLyric: return ink
        case .folk:           return Color(hex: "B44A3B")
        case .game2048:       return Color(hex: "EDC22E")
        case .ipod:           return Color(hex: "6F8B68")
        case .liquidGlass:    return Color(hex: "86E7FF")
        case .tornPaper:      return Color(hex: "D96850")
        case .clarity:        return Color(hex: "2478D8")
        case .dotMatrix:      return Color(hex: "68F8CF")
        case .console:        return SignalStyle.accent
        case .muji:           return Color(hex: "A36D52")
        case .capsule:        return Color(hex: "6D5CE8")
        case .petWhite:       return Color(hex: "F28B54")
        case .minimalWhite:   return Color(hex: "111318")
        }
    }

    /// 题签文字色（保证在各自海报底色上可读）
    private var captionInk: Color {
        switch theme {
        case .typewriter:
            return Color(hex: "F3E8D2")
        case .radio:
            return .white.opacity(0.92)
        case .pixel:
            return isDark ? Color(hex: "30FF6A") : Color(hex: "17612F")
        case .game2048:
            return Color(hex: "F9F6F2")
        case .aqua:
            return isDark ? .white.opacity(0.92) : Color(hex: "175D86")
        case .tornPaper:
            return isDark ? Color(hex: "F1EEE6") : Color(hex: "181716")
        case .clarity:
            return isDark ? Color.white.opacity(0.94) : Color(hex: "11151A")
        case .dotMatrix:
            return Color(hex: "D9FFF5")
        case .console:
            return SignalStyle.ink
        case .muji:
            return isDark ? Color(hex: "F0E7D8") : Color(hex: "3F3830")
        case .capsule:
            return isDark ? Color.white.opacity(0.94) : Color(hex: "24202D")
        case .petWhite:
            return Color(hex: "433A35")
        case .minimalWhite:
            return Color(hex: "111318")
        default:
            return ink
        }
    }

    // MARK: - 主题意象

    @ViewBuilder
    private var motif: some View {
        switch theme {
        case .classic: classicMotif
        case .vinyl: vinylMotif
        case .lyricFocus: lyricFocusMotif
        case .card: cardMotif
        case .neumorphic: neumorphicMotif
        case .poster: posterMotif
        case .motoPager: motoPagerMotif
        case .typewriter: typewriterMotif
        case .pixel: pixelMotif
        case .aqua: aquaMotif
        case .breathing: breathingMotif
        case .bloud:
            BloudCharacterView(expression: .calm, isAnimating: false,
                               bodyColor: ink, eyeColor: isDark ? .black : .white)
                .frame(width: 88, height: 88)
        case .cassette: cassetteMotif
        case .radio: radioMotif
        case .immersiveLyric: immersiveLyricMotif
        case .folk: folkMotif
        case .game2048: game2048Motif
        case .ipod: ipodMotif
        case .liquidGlass: liquidGlassMotif
        case .tornPaper: tornPaperMotif
        case .clarity: clarityMotif
        case .dotMatrix: dotMatrixMotif
        case .console: consoleMotif
        case .muji: mujiMotif
        case .capsule: capsuleMotif
        case .petWhite: petWhiteMotif
        case .minimalWhite: minimalWhiteMotif
        }
    }

    private var mujiMotif: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "CCD8C7"), Color(hex: "C89779")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 62, height: 72)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(hex: "F3EBDD"))
                        .frame(width: 18, height: 18)
                        .overlay(MonoIcon(icon: .play, size: 7, color: Color(hex: "51473D"), lineWidth: 1.6))
                        .padding(7)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 5, y: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text("SIDE A")
                    .font(.system(size: 7, weight: .semibold, design: .serif))
                    .tracking(1.4)
                    .foregroundStyle(Color(hex: "A36D52"))

                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color(hex: "4C443C").opacity(0.82)).frame(width: 38, height: 3)
                    Capsule().fill(Color(hex: "4C443C").opacity(0.3)).frame(width: 29, height: 2)
                }

                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "A36D52")).frame(width: 5, height: 5)
                    Capsule().fill(Color(hex: "A36D52").opacity(0.28)).frame(width: 30, height: 2)
                }
            }
        }
    }

    private var capsuleMotif: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Capsule()
                    .fill(Color.white.opacity(0.82))
                    .frame(width: 23, height: 10)
                Capsule()
                    .fill(Color(hex: "6D5CE8"))
                    .frame(width: 62, height: 10)
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF9D7A"), Color(hex: "7D6EF0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)

                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "24202D"))
                        .frame(width: 29, height: 29)
                        .overlay(MonoIcon(icon: .play, size: 10, color: .white, lineWidth: 1.8))
                    HStack(spacing: 4) {
                        Capsule().fill(Color(hex: "6D5CE8").opacity(0.28)).frame(width: 16, height: 7)
                        Capsule().fill(Color(hex: "FF9D7A").opacity(0.42)).frame(width: 16, height: 7)
                    }
                }
            }
        }
    }

    private var petWhiteMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "FFF7ED"))
                .frame(width: 100, height: 76)
                .shadow(color: Color(hex: "8B6E5D").opacity(0.18), radius: 6, y: 4)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "B9E3D4"), Color(hex: "FFD58C")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 53, height: 53)
                .offset(x: -17)
                .overlay(MonoIcon(icon: .catLife, size: 20, color: Color(hex: "55483F"), lineWidth: 1.7).offset(x: -17))

            VStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "F28B54"))
                    .frame(width: 25, height: 25)
                    .overlay(MonoIcon(icon: .play, size: 8, color: .white, lineWidth: 1.8))
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "8CCBC2")).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: "F4C86A")).frame(width: 9, height: 9)
                }
            }
            .offset(x: 35)
        }
    }

    private var minimalWhiteMotif: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 9) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "E6E7E9"), Color(hex: "B9BDC4")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 57, height: 57)

                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color(hex: "111318")).frame(width: 40, height: 3)
                    Capsule().fill(Color(hex: "111318").opacity(0.26)).frame(width: 27, height: 2)
                    Circle()
                        .stroke(Color(hex: "111318"), lineWidth: 1.2)
                        .frame(width: 22, height: 22)
                        .overlay(MonoIcon(icon: .play, size: 7, color: Color(hex: "111318"), lineWidth: 1.7))
                        .padding(.top, 2)
                }
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "111318").opacity(0.13)).frame(width: 106, height: 2)
                Capsule().fill(Color(hex: "111318")).frame(width: 43, height: 2)
            }
        }
    }

    private var consoleMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SignalStyle.screen)
                .frame(width: 112, height: 82)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SignalStyle.separator.opacity(0.72), lineWidth: 0.8))

            VStack(spacing: 9) {
                HStack(spacing: 4) {
                    SignalBreathingIndicator(size: 6)
                }

                HStack(spacing: 4) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(index == 5 ? SignalStyle.accent : SignalStyle.inkMuted.opacity(0.34))
                            .frame(width: 5, height: CGFloat(4 + index % 4 * 3))
                    }
                }

                Circle()
                    .fill(SignalStyle.accent)
                    .frame(width: 21, height: 21)
                    .overlay(MonoIcon(icon: .play, size: 8, color: SignalStyle.onAccent, lineWidth: 1.8))
            }
        }
    }

    private var dotMatrixMotif: some View {
        ZStack {
            Canvas { context, size in
                let spacing: CGFloat = 10
                for y in stride(from: 5, through: size.height, by: spacing) {
                    for x in stride(from: 5, through: size.width, by: spacing) {
                        let distance = hypot(x - size.width * 0.5, y - size.height * 0.48)
                        let opacity = max(0.05, 0.18 - distance / 650)
                        let rect = CGRect(x: x, y: y, width: 1.8, height: 1.8)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity)))
                    }
                }
            }

            PixelGrid(
                preset: .aurora,
                bloom: PixelGridBloom(amount: 4, intensity: 0.38),
                cornerRadius: 1,
                isAnimating: !reduceMotion,
                scale: 4.2,
                accessibilityLabel: String(localized: "点阵")
            )
        }
    }

    private var clarityMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.08 : 0.46))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(Color.white.opacity(isDark ? 0.18 : 0.82), lineWidth: 0.9)
                )
                .frame(width: 105, height: 76)
                .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.09), radius: 10, y: 6)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "C5B8E8"), Color(hex: "70D8E8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 58)

            Circle()
                .fill(Color(hex: "11151A"))
                .frame(width: 25, height: 25)
                .overlay(MonoIcon(icon: .play, size: 9, color: .white, lineWidth: 1.7).offset(x: 0.5))
                .offset(x: 41, y: 24)
        }
    }

    /// 撕页：封面被纸口切开，前景主体越过边缘。
    private var tornPaperMotif: some View {
        ZStack {
            PickerTornPaperShape(variant: 1)
                .fill(isDark ? Color(hex: "302D28") : Color(hex: "FFFDF7"))
                .frame(width: 108, height: 82)
                .rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

            PickerTornPaperShape(variant: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "375B68"), Color(hex: "D96850")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 79, height: 61)
                .rotationEffect(.degrees(2))
                .offset(x: -7, y: -5)

            VStack(spacing: 0) {
                Circle()
                    .fill(Color(hex: "F4F0E7"))
                    .frame(width: 25, height: 25)
                PickerTornPaperShape(variant: 3)
                    .fill(Color(hex: "F4F0E7"))
                    .frame(width: 47, height: 35)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .offset(x: 17, y: 8)

            Rectangle()
                .fill(Color(hex: "D96850"))
                .frame(width: 4, height: 25)
                .rotationEffect(.degrees(-7))
                .offset(x: -46, y: 28)
        }
    }

    /// 经典：居中封面 + 真实曲名
    private var classicMotif: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color(hex: "3E4350"), Color(hex: "23262E")]
                            : [Color.white, Color(hex: "D8DCE3")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(ink.opacity(0.1), lineWidth: 0.7)
                )
                .overlay(MonoIcon(icon: .musicNote, size: 21, color: muted, lineWidth: 1.7))
                .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.1), radius: 7, y: 4)

            VStack(spacing: 1.5) {
                Text("晚风")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(ink.opacity(0.85))
                Text("Mono")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(muted)
            }
        }
    }

    /// 黑胶：唱片 + 唱臂
    private var vinylMotif: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "070707"), Color(hex: "2A2A2A"), Color(hex: "0A0A0A")],
                            center: .center,
                            startRadius: 3,
                            endRadius: 38
                        )
                    )

                ForEach([28, 43, 58], id: \.self) { diameter in
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                        .frame(width: CGFloat(diameter), height: CGFloat(diameter))
                }

                Circle().fill(Color(hex: "D7B56D")).frame(width: 19, height: 19)
                Circle().fill(Color.black.opacity(0.8)).frame(width: 4, height: 4)
            }
            .frame(width: 72, height: 72)
            .shadow(color: Color.black.opacity(0.32), radius: 7, y: 4)

            // 唱臂
            VStack(alignment: .trailing, spacing: 0) {
                Circle()
                    .fill(ink.opacity(0.3))
                    .frame(width: 8, height: 8)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [ink.opacity(0.55), ink.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: 44)
                    .rotationEffect(.degrees(-18), anchor: .top)
                    .offset(x: -2)
            }
        }
    }

    /// 歌词焦点：真实歌词行，当前句点亮
    private var lyricFocusMotif: some View {
        VStack(spacing: 6.5) {
            Text("夜色落进窗台")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(muted.opacity(0.75))

            Text("我们乘晚风而行")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(ink)
                .shadow(color: Color(hex: "7A8CFF").opacity(0.45), radius: 7, y: 1)

            Text("群星次第亮起")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(muted.opacity(0.75))
        }
    }

    /// 卡片：斜叠双卡
    private var cardMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                .frame(width: 66, height: 58)
                .rotationEffect(.degrees(-7))
                .offset(x: -11, y: 2)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.13) : Color.white)
                .frame(width: 68, height: 60)
                .rotationEffect(.degrees(3))
                .offset(x: 7)
                .shadow(color: Color.black.opacity(isDark ? 0.26 : 0.1), radius: 6, y: 4)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FF7CA8"), Color(hex: "8B78FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .offset(x: 7)
                )
        }
    }

    /// 新拟物：凸起圆钮
    private var neumorphicMotif: some View {
        let base = isDark ? Color(hex: "2B2D32") : Color(hex: "E9EDF4")

        return Circle()
            .fill(base)
            .frame(width: 64, height: 64)
            .shadow(color: isDark ? Color.black.opacity(0.42) : Color.black.opacity(0.13), radius: 6, x: 4.5, y: 4.5)
            .shadow(color: isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.9), radius: 6, x: -4.5, y: -4.5)
            .overlay(
                Circle()
                    .stroke(Color(hex: "4F8E86").opacity(0.5), lineWidth: 1.5)
                    .frame(width: 43, height: 43)
            )
            .overlay(
                Circle()
                    .fill(Color(hex: "4F8E86"))
                    .frame(width: 11, height: 11)
            )
    }

    /// 海报：大字标 + 红杠 + 刊号行
    private var posterMotif: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MUSIC")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(ink)

            Rectangle()
                .fill(Color(hex: "EF2A2A"))
                .frame(width: 42, height: 5.5)

            Text("NIGHT FLIGHT · 45 RPM")
                .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(ink.opacity(0.5))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
    }

    /// Moto 寻呼机：LCD 视窗 + 点阵字
    private var motoPagerMotif: some View {
        let shell = isDark ? Color(hex: "2E3122") : Color(hex: "D5D0A8")
        let lcd = isDark ? Color(hex: "39402A") : Color(hex: "AEB782")
        let lcdInk = isDark ? Color(hex: "C8D49A") : Color(hex: "2E3318")

        return RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(shell)
            .frame(width: 96, height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(lcd.opacity(0.78))
                    .frame(width: 74, height: 30)
                    .overlay(
                        VStack(alignment: .leading, spacing: 2) {
                            Text("♪ 晚风")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(lcdInk)
                            Text("23:47")
                                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(lcdInk.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 7)
                    )
                    .offset(y: -6)
            )
            .overlay(alignment: .bottom) {
                HStack(spacing: 5) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        Circle()
                            .fill(ink.opacity(index == 1 ? 0.4 : 0.2))
                            .frame(width: index == 1 ? 7.5 : 6, height: index == 1 ? 7.5 : 6)
                    }
                }
                .padding(.bottom, 7)
            }
            .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.12), radius: 5, y: 3)
    }

    /// 打字机：纸页真实打字行 + 键帽
    private var typewriterMotif: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDark ? Color(hex: "E5D2B3") : Color(hex: "FFF7E9"))
                .frame(width: 74, height: 44)
                .overlay(
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dear music,")
                            .font(.system(size: 8.5, weight: .semibold, design: .serif))
                            .foregroundColor(Color(hex: "2D241C"))

                        HStack(spacing: 1.5) {
                            Text("sing to me")
                                .font(.system(size: 8.5, weight: .semibold, design: .serif))
                                .foregroundColor(Color(hex: "2D241C").opacity(0.72))

                            Rectangle()
                                .fill(Color(hex: "2D241C").opacity(0.75))
                                .frame(width: 4.5, height: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 3)

            HStack(spacing: 5) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    Circle()
                        .fill(Color(hex: "E9DCC8"))
                        .frame(width: 9, height: 9)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, y: 1)
                }
            }
        }
    }

    /// 像素：CRT 均衡器
    private var pixelMotif: some View {
        let green = isDark ? Color(hex: "30FF6A") : Color(hex: "1E8C43")

        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                Rectangle().fill(green).frame(width: 9, height: 9)
                Text("NOW PLAYING")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
            }

            HStack(alignment: .bottom, spacing: 3.5) {
                ForEach(Array([13, 25, 17, 32, 10, 21, 27].enumerated()), id: \.offset) { _, height in
                    Rectangle()
                        .fill(green.opacity(height > 16 ? 0.9 : 0.45))
                        .frame(width: 6, height: CGFloat(height))
                }
            }
        }
    }

    /// 水波：玻璃气泡
    private var aquaMotif: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(isDark ? 0.3 : 0.66), Color(hex: "4BB6E0").opacity(0.12), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 42
                    )
                )
                .frame(width: 84, height: 84)

            HStack(spacing: 12) {
                aquaBubble(size: 16)
                aquaBubble(size: 34, icon: .play)
                aquaBubble(size: 16)
            }
        }
    }

    /// 呼吸：同心光环
    private var breathingMotif: some View {
        let cyan = Color(hex: "58D7FF")
        let violet = Color(hex: "8F7BFF")

        return ZStack {
            Circle().fill(violet.opacity(0.16)).frame(width: 82, height: 82).blur(radius: 11)
            Circle().stroke(cyan.opacity(0.3), lineWidth: 1).frame(width: 66, height: 66)
            Circle().stroke(cyan.opacity(0.16), lineWidth: 1).frame(width: 82, height: 82)

            Circle()
                .fill(LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay(MonoIcon(icon: .waveform, size: 14, color: .white.opacity(0.92), lineWidth: 1.6))
                .shadow(color: cyan.opacity(0.4), radius: 9)
        }
    }

    /// 磁带：卡带壳
    private var cassetteMotif: some View {
        let shell = isDark ? Color(hex: "2B2B31") : Color.white
        let label = isDark ? Color(hex: "E5E0D2") : Color(hex: "F6F1E6")

        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(shell)
            .frame(width: 94, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(label)
                    .frame(width: 76, height: 31)
                    .overlay(
                        HStack(spacing: 19) {
                            cassetteReel
                            cassetteReel
                        }
                    )
                    .overlay(alignment: .top) {
                        Text("MIXTAPE · A")
                            .font(.system(size: 4.8, weight: .heavy, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(Color(hex: "3A342A").opacity(0.55))
                            .padding(.top, 2.5)
                    }
                    .offset(y: -5)
            )
            .overlay(alignment: .bottom) {
                TrapezoidShape()
                    .fill(Color.black.opacity(isDark ? 0.26 : 0.09))
                    .frame(width: 44, height: 9)
                    .padding(.bottom, 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(ink.opacity(0.1), lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.1), radius: 5, y: 3)
    }

    /// 收音机：LED 面板 + 旋钮
    private var radioMotif: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isDark ? Color(hex: "312058") : Color(hex: "9272C8"))
            .frame(width: 96, height: 62)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(isDark ? Color(hex: "090711") : Color(hex: "1D1331"))
                    .frame(width: 76, height: 18)
                    .overlay(
                        HStack(spacing: 5) {
                            Text("FM 88.7")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "DCC8FF"))

                            HStack(spacing: 2.5) {
                                ForEach(0 ..< 5, id: \.self) { index in
                                    Circle()
                                        .fill(Color(hex: "DCC8FF").opacity(index < 3 ? 1 : 0.22))
                                        .frame(width: 2.5, height: 2.5)
                                }
                            }
                        }
                    )
                    .padding(.top, 8)
            }
            .overlay(alignment: .bottomLeading) {
                // 喇叭格栅
                HStack(spacing: 3) {
                    ForEach(0 ..< 5, id: \.self) { _ in
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2.2, height: 14)
                    }
                }
                .padding(.leading, 11)
                .padding(.bottom, 9)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 1.3, height: 6)
                            .offset(y: -3)
                    )
                    .padding([.bottom, .trailing], 9)
            }
            .shadow(color: Color.black.opacity(isDark ? 0.34 : 0.16), radius: 6, y: 4)
    }

    /// 沉浸歌词：左对齐真实大字行
    private var immersiveLyricMotif: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            Text("晚风吹过")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(ink)

            Text("山与海之间")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(ink.opacity(0.5))

            Text("也吹过我")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(ink.opacity(0.24))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
    }

    /// 民谣：拍立得 + 邮票 + 手写笺
    private var folkMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.22 : 0.9))
                .frame(width: 50, height: 60)
                .rotationEffect(.degrees(-6))
                .overlay(
                    Rectangle()
                        .fill(Color(hex: "B44A3B").opacity(0.16))
                        .frame(width: 37, height: 35)
                        .rotationEffect(.degrees(-6))
                        .offset(x: -1, y: -5)
                )
                .shadow(color: Color.black.opacity(0.13), radius: 3, y: 2)
                .offset(x: -18)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color(hex: "B44A3B").opacity(0.65), lineWidth: 1)
                .frame(width: 34, height: 20)
                .overlay(
                    Text("邮")
                        .font(.system(size: 8, weight: .medium, design: .serif))
                        .foregroundColor(Color(hex: "B44A3B").opacity(0.8))
                )
                .rotationEffect(.degrees(6))
                .offset(x: 30, y: -15)

            Text("晚风与信")
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .italic()
                .foregroundColor(ink.opacity(0.72))
                .rotationEffect(.degrees(-3))
                .offset(x: 28, y: 16)
        }
    }

    /// 2048：四格拼块
    private var game2048Motif: some View {
        VStack(spacing: 4.5) {
            HStack(spacing: 4.5) {
                gameTile("2048", fill: Color(hex: "EDC22E"))
                gameTile("8", fill: Color(hex: "F2B179"))
            }
            HStack(spacing: 4.5) {
                gameTile("2", fill: Color(hex: "EEE4DA"), textColor: Color(hex: "776E65"))
                gameTile("♪", fill: Color(hex: "CDC1B4"))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "A99B8E"))
        )
    }

    /// iPod：单色屏幕、转盘与实体按键
    private var ipodMotif: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDark ? Color(hex: "20242A") : Color(hex: "E9EDF1"))
                .frame(width: 60, height: 88)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isDark ? Color(hex: "1C302A") : Color(hex: "DCE8D3"))
                        .frame(width: 43, height: 30)
                        .overlay(
                            VStack(spacing: 2) {
                                Text("♪ NOW")
                                Text("PLAYING")
                            }
                            .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                            .foregroundColor(isDark ? Color(hex: "C7E6B9") : Color(hex: "2E492E"))
                        )
                        .padding(.top, 7)
                }
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(isDark ? Color(hex: "343940") : Color(hex: "F7F8F9"))
                        .frame(width: 33, height: 33)
                        .overlay(Circle().stroke(ink.opacity(0.14), lineWidth: 0.7))
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(ink.opacity(0.65))
                                .symbolRenderingMode(.monochrome)
                        )
                        .padding(.bottom, 7)
                }
                .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.12), radius: 4, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text("iPod")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                Text("♪  MUSIC")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "6F8B68"))
            }
        }
    }

    /// 液态玻璃：多层折射透镜与漂浮液滴
    private var liquidGlassMotif: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "63D8FF").opacity(0.34))
                .frame(width: 78, height: 78)
                .blur(radius: 10)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 96, height: 66)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.12), Color(hex: "9B8CFF").opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color(hex: "65DFFF").opacity(0.25), radius: 10, y: 5)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 35, height: 35)
                .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.8))
                .overlay(MonoIcon(icon: .play, size: 12, color: .white, lineWidth: 1.8))

            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(Color.white.opacity(0.76), lineWidth: 0.7))
                .offset(x: 45, y: -31)
        }
    }

    // MARK: - 小件

    private func aquaBubble(size: CGFloat, icon: MonoIcon.IconType? = nil) -> some View {
        Circle()
            .fill(Color.white.opacity(isDark ? 0.15 : 0.74))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(isDark ? 0.2 : 0.55), lineWidth: 0.8))
            .overlay {
                if let icon {
                    MonoIcon(
                        icon: icon,
                        size: size * 0.36,
                        color: isDark ? Color.white.opacity(0.75) : Color(hex: "2E86C1"),
                        lineWidth: 1.6
                    )
                    .offset(x: 1)
                }
            }
    }

    private var cassetteReel: some View {
        Circle()
            .fill(Color.black.opacity(0.13))
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
            .overlay(Circle().fill(Color.black.opacity(0.4)).frame(width: 4.5, height: 4.5))
    }

    private func gameTile(_ text: String, fill: Color, textColor: Color = .white) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(fill)
            .frame(width: 31, height: 23)
            .overlay(
                Text(text)
                    .font(.system(size: text.count > 2 ? 7.5 : 9.5, weight: .black, design: .rounded))
                    .foregroundStyle(textColor)
            )
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch theme {
        case .classic:
            LinearGradient(colors: isDark ? [Color(hex: "1B1D24"), Color(hex: "101218")] : [Color(hex: "F7F7F4"), Color(hex: "E9ECEF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .vinyl:
            LinearGradient(colors: isDark ? [Color(hex: "15120F"), Color(hex: "2B241B")] : [Color(hex: "F4F1EA"), Color(hex: "D8D0C2")], startPoint: .top, endPoint: .bottom)
        case .lyricFocus:
            LinearGradient(colors: isDark ? [Color(hex: "171B2B"), Color(hex: "07090F")] : [Color(hex: "F7F9FF"), Color(hex: "E9EEFB")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .card:
            LinearGradient(colors: isDark ? [Color(hex: "211429"), Color(hex: "3C2147")] : [Color(hex: "FFE5EF"), Color(hex: "DAD8FF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neumorphic:
            LinearGradient(colors: isDark ? [Color(hex: "2B2D32"), Color(hex: "1C1E22")] : [Color(hex: "EEF0F4"), Color(hex: "DDE2EA")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .poster:
            isDark ? Color.black : Color.white
        case .motoPager:
            LinearGradient(colors: isDark ? [Color(hex: "15160F"), Color(hex: "252714")] : [Color(hex: "E8E3C5"), Color(hex: "BDBA91")], startPoint: .top, endPoint: .bottom)
        case .typewriter:
            LinearGradient(colors: isDark ? [Color(hex: "221811"), Color(hex: "3A2B1F")] : [Color(hex: "B58A60"), Color(hex: "755436")], startPoint: .top, endPoint: .bottom)
        case .pixel:
            isDark ? Color(hex: "07101B") : Color(hex: "DDE7D5")
        case .aqua:
            LinearGradient(colors: isDark ? [Color(hex: "071A2C"), Color(hex: "0D4A69")] : [Color(hex: "F4FCFF"), Color(hex: "87C9E8")], startPoint: .top, endPoint: .bottom)
        case .breathing:
            RadialGradient(colors: isDark ? [Color(hex: "182A36"), Color(hex: "05070B")] : [Color(hex: "ECFAFF"), Color(hex: "F4F0FF")], center: .center, startRadius: 4, endRadius: 95)
        case .bloud:
            isDark ? Color(hex: "17191C") : Color(hex: "F7F8FA")
        case .cassette:
            isDark ? Color(hex: "19191D") : Color(hex: "E7E5DD")
        case .radio:
            LinearGradient(colors: isDark ? [Color(hex: "180F32"), Color(hex: "382061")] : [Color(hex: "BCA6E7"), Color(hex: "8869BE")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .immersiveLyric:
            LinearGradient(colors: isDark ? [Color(hex: "191526"), Color(hex: "0B0A11")] : [Color(hex: "FAF7FF"), Color(hex: "ECE9FA")], startPoint: .top, endPoint: .bottom)
        case .folk:
            LinearGradient(colors: isDark ? [Color(hex: "2C2118"), Color(hex: "15100C")] : [Color(hex: "F5E9D8"), Color(hex: "E4D1B8")], startPoint: .top, endPoint: .bottom)
        case .game2048:
            Color(hex: "BBADA0")
        case .ipod:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "171B1F"), Color(hex: "293238")]
                    : [Color(hex: "E5E9ED"), Color(hex: "C6D0D6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .liquidGlass:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "07131F"), Color(hex: "123751"), Color(hex: "251B4E")]
                    : [Color(hex: "DDF8FF"), Color(hex: "AFCFF5"), Color(hex: "C8BCFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .clarity:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "131C25"), Color(hex: "0D1218")]
                    : [Color(hex: "F7F8F8"), Color(hex: "E7F1F3"), Color(hex: "F1EAF7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .tornPaper:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "171615"), Color(hex: "38342F")]
                    : [Color(hex: "CBC6BC"), Color(hex: "EEE9DF")],
                startPoint: .top,
                endPoint: .bottom
            )
        case .dotMatrix:
            LinearGradient(
                colors: [Color(hex: "07110F"), Color(hex: "0B1F20"), Color(hex: "10162B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .console:
            LinearGradient(
                colors: [SignalStyle.base, SignalStyle.surface, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .muji:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "2C2925"), Color(hex: "1D1B19")]
                    : [Color(hex: "F4EFE6"), Color(hex: "E7DDCE")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .capsule:
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "211D2B"), Color(hex: "121017")]
                    : [Color(hex: "F1EEFF"), Color(hex: "E8E3F3")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .petWhite:
            pawcelainPreviewBackground
        case .minimalWhite:
            Color(hex: "FAFAF9")
        }
    }

    @ViewBuilder
    private var pawcelainPreviewBackground: some View {
        ZStack {
            PetWhiteRootBackdrop()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.58),
                    PetWhiteStyle.mint.opacity(isDark ? 0.12 : 0.18),
                    PetWhiteStyle.butter.opacity(isDark ? 0.08 : 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

}

private struct TrapezoidShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct PickerTornPaperShape: Shape {
    let variant: Int

    func path(in rect: CGRect) -> Path {
        let steps = 9
        let amplitude = min(rect.width, rect.height) * 0.045
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + offset(0, amplitude)))
            for index in 1...steps {
                let p = CGFloat(index) / CGFloat(steps)
                path.addLine(to: CGPoint(x: rect.minX + rect.width * p, y: rect.minY + offset(index, amplitude)))
            }
            for index in 1...steps {
                let p = CGFloat(index) / CGFloat(steps)
                path.addLine(to: CGPoint(x: rect.maxX + offset(index + 17, amplitude), y: rect.minY + rect.height * p))
            }
            for index in 1...steps {
                let p = CGFloat(index) / CGFloat(steps)
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * p, y: rect.maxY + offset(index + 31, amplitude)))
            }
            for index in 1...steps {
                let p = CGFloat(index) / CGFloat(steps)
                path.addLine(to: CGPoint(x: rect.minX + offset(index + 47, amplitude), y: rect.maxY - rect.height * p))
            }
            path.closeSubpath()
        }
    }

    private func offset(_ index: Int, _ amplitude: CGFloat) -> CGFloat {
        CGFloat(sin(Double(index * 41 + variant * 67))) * amplitude
    }
}
