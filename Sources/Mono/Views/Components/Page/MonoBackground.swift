import Combine
import SwiftUI

// MARK: - 返回按钮组件
struct MonoBackButton: View {
    enum Style {
        case back   // < 返回
        case dismiss // 下拉关闭
    }

    var style: Style = .back
    var isDarkBackground: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var iconColor: Color {
        isDarkBackground ? .white : .primary
    }

    var body: some View {
        Button(action: {
            dismiss()
        }) {
            backIcon
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "action_back"))
    }

    @ViewBuilder
    private var backIcon: some View {
        if PetWhiteStyle.isActive, style == .dismiss {
            PetWhiteChevronIcon(direction: .down, size: 20, fallbackColor: iconColor)
        } else {
            MonoIcon(
                icon: style == .back ? .back : .chevronRight,
                size: 20,
                color: iconColor
            )
            .rotationEffect(style == .dismiss ? .degrees(90) : .zero)
        }
    }
}

/// 导航栏专用返回按钮。iOS 26 的 Toolbar 会自行提供玻璃背景，避免再套一层自绘胶囊。
struct MonoToolbarBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var iconColor: Color = .monoTextPrimary

    var body: some View {
        Button { dismiss() } label: {
            backLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "action_back"))
    }

    @ViewBuilder
    private var backLabel: some View {
        if GlobalThemeId.persistedOrDefault == .default {
            MonoIcon(icon: .back, size: 18, color: iconColor, lineWidth: 1.7)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } else if #available(iOS 26, *) {
            MonoIcon(icon: .back, size: 16, color: iconColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        } else {
            MonoIcon(icon: .back, size: 16, color: iconColor)
                .frame(width: 40, height: 40)
                .monoGlassCircle()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

private struct MonoNavigationBackButtonModifier: ViewModifier {
    let iconColor: Color

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MonoToolbarBackButton(iconColor: iconColor)
                }
            }
            // 返回手势必须通过 SwiftUI dismiss 更新 NavigationStack 的 path。
            // 不能直接调用底层 UINavigationController.popViewController，
            // 否则 SwiftUI 状态仍保留目标页，下一次导航栏布局会发生宿主错配。
            .monoEdgeSwipeToDismiss()
    }
}

extension View {
    /// Navigation chrome contains controls only; page titles belong to content.
    func monoNavigationBackButton(iconColor: Color = .monoTextPrimary) -> some View {
        modifier(MonoNavigationBackButtonModifier(iconColor: iconColor))
    }
}

// MARK: - 弥散背景组件
struct MonoBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var themeManager = GlobalThemeManager.shared
    @State private var coverURL = PlayerManager.shared.currentSong?.coverUrl?.sized(200)

    private var useCoverBg: Bool {
        !useAsideFluidBackground
            && !MinimalWhiteStyle.isActive
            && settings.usesGlobalCoverBackground
            && coverURL != nil
    }

    private var useAsideFluidBackground: Bool {
        themeId == .default
            && settings.asideMusicFluidBackgroundEnabled
    }

    /// 当前全局主题 ID
    private var themeId: GlobalThemeId {
        themeManager.currentThemeId
    }

    var body: some View {
        ZStack {
            // 根据全局主题决定底层背景
            themeAwareBackground
                .opacity(useCoverBg || useAsideFluidBackground ? 0 : 1)

            if let coverUrl = coverURL,
               settings.usesGlobalCoverBackground,
               !useAsideFluidBackground {
                PlaylistColorBackground(
                    coverUrl: coverUrl,
                    onBrightnessChanged: { isDark in
                        if settings.globalCoverIsDark != isDark {
                            settings.globalCoverIsDark = isDark
                        }
                    }
                )
                .opacity(useCoverBg ? 1 : 0)
                .transition(.opacity)
            }

            if useAsideFluidBackground {
                AsideMusicFluidBackground(
                    artworkURL: coverURL?.absoluteString,
                    onBrightnessChanged: { isDark in
                        if settings.globalCoverIsDark != isDark {
                            settings.globalCoverIsDark = isDark
                        }
                    }
                )
                .opacity(useAsideFluidBackground ? 1 : 0)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: useCoverBg)
        .animation(.easeInOut(duration: 0.6), value: useAsideFluidBackground)
        .onChange(of: useCoverBg || useAsideFluidBackground) { _, active in
            if !active && settings.globalCoverIsDark {
                settings.globalCoverIsDark = false
            }
        }
        .onReceive(
            PlayerManager.shared.$currentSong
                .map { $0?.coverUrl?.sized(200) }
                .removeDuplicates()
        ) { coverURL in
            self.coverURL = coverURL
        }
    }

    // MARK: - 主题感知的默认背景

    @ViewBuilder
    private var themeAwareBackground: some View {
        switch themeId {
        case .muji:
            mujiBackground
        case .manga:
            mangaBackground
        case .petWhite:
            petWhiteBackground
        case .minimalWhite:
            MinimalWhiteRootBackdrop()
        case .neumorphic:
            neumorphicBackground
        case .capsule:
            CapsuleRootBackdrop()
        case .signal:
            SignalRootBackdrop()
        case .clarity:
            ClarityBackdrop()
        case .default:
            defaultBackground
        }
    }

    // MARK: - 无印良品背景

    private var mujiBackground: some View {
        ZStack {
            MujiRootBackdrop()

            Canvas { context, size in
                let w = size.width
                let h = size.height
                if colorScheme == .dark {
                    fillGlow(context, center: CGPoint(x: w * 0.16, y: h * 0.1), radius: w * 0.48,
                             color: MujiStyle.clay, opacity: 0.12)
                    fillGlow(context, center: CGPoint(x: w * 0.82, y: h * 0.38), radius: w * 0.42,
                             color: MujiStyle.tea, opacity: 0.12)
                } else {
                    fillGlow(context, center: CGPoint(x: w * 0.16, y: h * 0.06), radius: w * 0.5,
                             color: MujiStyle.straw, opacity: 0.16)
                    fillGlow(context, center: CGPoint(x: w * 0.82, y: h * 0.44), radius: w * 0.42,
                             color: MujiStyle.tea, opacity: 0.1)
                    fillGlow(context, center: CGPoint(x: w * 0.44, y: h * 0.8), radius: w * 0.48,
                             color: MujiStyle.indigo, opacity: 0.055)
                }
            }
            .padding(-80)
            .blur(radius: 58)
            .ignoresSafeArea()
            .drawingGroup()
        }
    }

    // MARK: - 白绒爪印背景

    private var petWhiteBackground: some View {
        ZStack {
            PetWhiteRootBackdrop()

            Canvas { context, size in
                let w = size.width
                let h = size.height
                if colorScheme == .dark {
                    fillGlow(context, center: CGPoint(x: w * 0.16, y: h * 0.10), radius: w * 0.40, color: PetWhiteStyle.mint, opacity: 0.08)
                    fillGlow(context, center: CGPoint(x: w * 0.82, y: h * 0.34), radius: w * 0.42, color: PetWhiteStyle.dogOrange, opacity: 0.08)
                } else {
                    fillGlow(context, center: CGPoint(x: w * 0.16, y: h * 0.07), radius: w * 0.44, color: PetWhiteStyle.mint, opacity: 0.16)
                    fillGlow(context, center: CGPoint(x: w * 0.82, y: h * 0.34), radius: w * 0.40, color: PetWhiteStyle.dogOrange, opacity: 0.12)
                    fillGlow(context, center: CGPoint(x: w * 0.46, y: h * 0.84), radius: w * 0.48, color: PetWhiteStyle.sky, opacity: 0.08)
                }
            }
            .padding(-90)
            .blur(radius: 56)
            .ignoresSafeArea()
            .drawingGroup()
        }
    }

    // MARK: - 漫画风背景

    private var mangaBackground: some View {
        MangaRootBackdrop()
    }

    // MARK: - 新拟物背景

    private var neumorphicBackground: some View {
        ThemeRenderBackdrop(theme: .neumorphic)
    }

    // MARK: - 默认背景

    private var defaultBackground: some View {
        ThemeBackgroundImageReader(theme: .default, isEnabled: ThemeColorCustomization.usesImageBackground(for: .default)) { wallpaper in
            ThemeBackgroundImageReader(
                theme: .default,
                dark: true,
                isEnabled: colorScheme == .dark && ThemeColorCustomization.usesDarkImageBackground(for: .default)
            ) { darkWallpaper in
                defaultBackground(wallpaper: wallpaper, darkWallpaper: darkWallpaper)
            }
        }
    }

    @ViewBuilder
    private func defaultBackground(wallpaper: UIImage?, darkWallpaper: UIImage?) -> some View {
        if colorScheme == .dark,
           ThemeColorCustomization.usesDarkImageBackground(for: .default),
           let wallpaper = darkWallpaper {
            wallpaperFillBackground(
                wallpaper,
                baseHex: ThemeColorCustomization.darkBackgroundSolidHex(for: .default)
            )
        } else if colorScheme == .dark,
                  ThemeColorCustomization.usesDarkGradientBackground(for: .default) {
            let accent = Color(hex: ThemeColorCustomization.darkAccentHex(for: .default))
            ThemeCustomDiffuseBackground(
                theme: .default,
                fallbackHexes: [],
                opacity: 1,
                colorsOverride: ThemeColorCustomization.darkBackgroundGradientColors(
                    for: .default
                ),
                accentColorsOverride: [accent, accent],
                gradientStyleOverride: ThemeColorCustomization.darkBackgroundGradientStyle(
                    for: .default
                )
            )
            .ignoresSafeArea()
        } else if colorScheme == .dark, ThemeColorCustomization.usesDarkSolidBackground(for: .default) {
            Color(hex: ThemeColorCustomization.darkBackgroundSolidHex(for: .default))
                .ignoresSafeArea()
        } else if ThemeColorCustomization.usesImageBackground(for: .default),
                  let wallpaper {
            wallpaperFillBackground(
                wallpaper,
                baseHex: ThemeColorCustomization.hex(
                    .default,
                    .background,
                    "solid",
                    fallback: ThemeColorCustomization.defaultBackgroundStartHex(for: .default)
                )
            )
        } else if ThemeColorCustomization.usesCustomBackground(for: .default) {
            ZStack {
                ThemeCustomDiffuseBackground(
                    theme: .default,
                    fallbackHexes: [
                        ThemeColorCustomization.defaultBackgroundStartHex(for: .default),
                        ThemeColorCustomization.defaultBackgroundEndHex(for: .default),
                    ],
                    accentFallbackHexes: [ThemeColorCustomization.defaultAccentHex(for: .default)],
                    opacity: 0.92
                )
                .ignoresSafeArea()

                if ThemeColorCustomization.usesDefaultCatPawPreset() {
                    DefaultPawPrintTexture(opacity: colorScheme == .dark ? 0.032 : 0.055)
                }
            }
        } else {
            defaultSystemBackground
        }
    }

    /// 参考系统壁纸：整张图缩放填满屏幕，超出部分裁切
    private func wallpaperFillBackground(_ wallpaper: UIImage, baseHex: String) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: baseHex)

                Image(uiImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }

    private var defaultSystemBackground: some View {
        GeometryReader { proxy in
            Image("default_theme_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(defaultImageAtmosphere)
        }
        .ignoresSafeArea()
    }

    private var defaultImageAtmosphere: some View {
        ZStack {
            Color.monoBackground.opacity(colorScheme == .dark ? 0.04 : 0.06)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.monoBackground.opacity(colorScheme == .dark ? 0.06 : 0.08), location: 0.32),
                    .init(color: Color.monoBackground.opacity(colorScheme == .dark ? 0.2 : 0.18), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fillGlow(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.3), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius
        ))
    }
}

private struct DefaultPawPrintTexture: View {
    var opacity: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let pawColor = (colorScheme == .dark ? Color(hex: "FFE4D3") : Color(hex: "8A5F4B")).opacity(opacity)
            let stepX: CGFloat = 92
            let stepY: CGFloat = 128

            var y: CGFloat = -24
            var row = 0
            while y < size.height + stepY {
                var x: CGFloat = row.isMultiple(of: 2) ? 18 : 62
                while x < size.width + stepX {
                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .degrees(row.isMultiple(of: 2) ? -9 : 12))
                        drawPaw(in: &layer, color: pawColor)
                    }
                    x += stepX
                }
                row += 1
                y += stepY
            }
        }
        .blendMode(colorScheme == .dark ? .screen : .multiply)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPaw(in context: inout GraphicsContext, color: Color) {
        let pad = Path(ellipseIn: CGRect(x: 8, y: 13, width: 17, height: 12))
        context.fill(pad, with: .color(color))

        let toes = [
            CGRect(x: 1, y: 6, width: 7, height: 8),
            CGRect(x: 8, y: 1, width: 7, height: 8),
            CGRect(x: 17, y: 1, width: 7, height: 8),
            CGRect(x: 24, y: 6, width: 7, height: 8),
        ]

        toes.forEach { rect in
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

// MARK: - Liquid Glass 叠加层
struct LiquidGlassOverlay: View {
    var body: some View {
        Rectangle()
            .fill(Color.monoGlassTint)
            .monoGlass(cornerRadius: 16)
            .opacity(0.3)
    }
}

// MARK: - Liquid Glass 卡片
struct MonoLiquidGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let useMetal: Bool
    let content: Content

    init(
        cornerRadius: CGFloat = 20,
        useMetal: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.useMetal = useMetal
        self.content = content()
    }

    var body: some View {
        if MinimalWhiteStyle.isActive {
            content
                .background(
                    MinimalWhiteSurfaceBackground(
                        cornerRadius: min(cornerRadius, MinimalWhiteStyle.cardRadius),
                        elevated: false
                    )
                )
        } else if MangaStyle.isActive {
            content
                .background(MangaCardBackground(cornerRadius: min(cornerRadius, 18), elevated: true))
        } else if PureWhiteStyle.isActive {
            content
                .background(PureWhiteSurfaceBackground(cornerRadius: min(max(cornerRadius, 16), 26), elevated: true))
        } else if MujiStyle.isActive {
            content
                .background(MujiPaperCardBackground(cornerRadius: min(cornerRadius, 16), elevated: true))
        } else if NeumorphicStyle.isActive {
            content
                .background(NeumorphicSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 28), elevated: true))
        } else if SequoiaStyle.isActive {
            content
                .background(SequoiaSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 28), elevated: true))
        } else if SignalStyle.isActive {
            content
                .background(SignalSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 28), elevated: true, fill: SignalStyle.device))
        } else {
            content
                .background(
                    SwiftUIGlassBackground(cornerRadius: cornerRadius)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(
                    color: .black.opacity(0.08),
                    radius: 10,
                    x: 0,
                    y: 5
                )
        }
    }
}

// MARK: - SwiftUI 毛玻璃回退方案
struct SwiftUIGlassBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            if MinimalWhiteStyle.isActive {
                MinimalWhiteSurfaceBackground(
                    cornerRadius: min(cornerRadius, MinimalWhiteStyle.cardRadius),
                    elevated: false
                )
            } else if MangaStyle.isActive {
                MangaCardBackground(cornerRadius: min(cornerRadius, 18), elevated: true)
            } else if PureWhiteStyle.isActive {
                PureWhiteSurfaceBackground(cornerRadius: min(max(cornerRadius, 16), 26), elevated: true)
            } else if MujiStyle.isActive {
                MujiPaperCardBackground(cornerRadius: min(cornerRadius, 16), elevated: true)
            } else if SequoiaStyle.isActive {
                SequoiaSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 28), elevated: true)
            } else if SignalStyle.isActive {
                SignalSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 28), elevated: true, fill: SignalStyle.device)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.monoGlassTint)
                    .monoGlass(cornerRadius: cornerRadius)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.4))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.08)
                                ]
                                : [
                                    Color.white.opacity(0.6),
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.3)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isDark ? 0.5 : 1
                    )

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.04 : 0.15),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
            }
        }
    }
}

// MARK: - View 修饰器
extension View {
    func monoBackground() -> some View {
        self.background(MonoBackground())
    }
}
