//  Immersive-stage settings designed specifically for the landscape canvas.

import SwiftUI

struct AriaLandscapeSettingsView: View {
    let palette: AriaPalette
    let onDismiss: () -> Void

    @AppStorage("showTranslation") private var showTranslation = true
    @AppStorage("ariaPosterShowTranslation") private var posterShowTranslation = false
    @AppStorage("ariaLyricEffect") private var lyricEffectRaw = AriaLyricEffect.classic.rawValue
    @AppStorage("ariaLyricFont") private var lyricFontRaw = AriaLyricFontChoice.system.rawValue
    @AppStorage("ariaCustomLyricFontID") private var customFontID = ""
    @AppStorage("ariaForeignLyricFont") private var foreignLyricFontRaw = MonoPlayerFont.followThemeRawValue
    @AppStorage("ariaForeignCustomLyricFontID") private var foreignCustomFontID = ""
    @AppStorage("ariaCanopyFragmentStage") private var canopyFragmentStage = false
    @AppStorage("ariaLyricAutoColor") private var lyricAutoColor = true
    @AppStorage("ariaLyricColorHex") private var lyricColorHex = "FFFFFF"
    @AppStorage("ariaLyricLayout") private var lyricLayoutRaw = AriaLyricLayoutChoice.center.rawValue
    @AppStorage("ariaLyricsFontScale") private var fontScale = 1.0
    @AppStorage("ariaGeometricBackground") private var ambientMotion = true
    @AppStorage("ariaBackgroundOpacity") private var backgroundOpacity = 0.75
    @AppStorage("ariaLyricDepthIntensity") private var lyricDepthIntensity = 0.68
    @AppStorage("ariaLyricMaterialStyle") private var lyricMaterialStyleRaw = AriaLyricMaterialStyle.solid.rawValue
    @AppStorage("ariaLyricOpacity") private var lyricOpacity = 1.0
    @AppStorage("ariaLyricGlowStrength") private var lyricGlowStrength = 0.0
    @AppStorage("ariaLyricParticleDensity") private var particleDensity = 0.58
    @AppStorage("ariaLyricParticleSize") private var particleSize = 1.15
    @AppStorage("ariaLyricParticleMotion") private var particleMotion = true
    @AppStorage("ariaLyricGlassIntensity") private var glassIntensity = 0.64
    @AppStorage("ariaVideoAdaptiveLyricGlass") private var videoAdaptiveLyricGlass = true
    @AppStorage("lyricsForceUppercaseEnglish") private var forceUppercaseEnglish = false
    @AppStorage("immersivePersistent") private var immersivePersistent = false
    @AppStorage("ariaLyricEmboss") private var lyricEmbossEnabled = true
    // 沉浸实验室
    @AppStorage("ariaHapticBeatEnabled") private var hapticBeatEnabled = false
    @AppStorage("ariaVocalBreathingWeight") private var vocalBreathingEnabled = false
    @AppStorage("ariaTensionSystemEnabled") private var tensionSystemEnabled = false
    @AppStorage("ariaGPUStageEnabled") private var gpuStageEnabled = false
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @State private var showVideoSheet = false
    @State private var effectHasMoreContent = false
    @State private var styleHasMoreContent = false
    @State private var stageHasMoreContent = false

    private var lyricEffect: AriaLyricEffect {
        AriaLyricEffect.resolveStored(lyricEffectRaw)
    }

    private var lyricFont: AriaLyricFontChoice {
        AriaLyricFontChoice(rawValue: lyricFontRaw) ?? .system
    }

    private var lyricMaterialStyle: AriaLyricMaterialStyle {
        AriaLyricMaterialStyle.resolveStored(lyricMaterialStyleRaw)
    }

    private var lyricTypography: AriaLyricTypographyConfiguration {
        AriaLyricTypographyConfiguration(
            style: lyricMaterialStyle,
            opacity: lyricOpacity,
            glowStrength: lyricGlowStrength,
            particleDensity: particleDensity,
            particleSize: particleSize,
            particleMotion: particleMotion,
            glassIntensity: glassIntensity
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: lyricColorHex) },
            set: { color in
                lyricColorHex = color.toHex()
                lyricAutoColor = false
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = min(max(proxy.size.width * 0.215, 166), 232)

            ZStack {
                backdrop

                VStack(spacing: 12) {
                    header

                    HStack(alignment: .top, spacing: 12) {
                        effectPanel
                            .frame(width: sideWidth)

                        stylePanel
                            .frame(maxWidth: .infinity)

                        stagePanel
                            .frame(width: sideWidth)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .contentShape(Rectangle())
        }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .fullScreenCover(isPresented: $showVideoSheet) {
            ImmersiveBackgroundLandscapeView(palette: palette)
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black.opacity(0.82)
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.16),
                    Color.black.opacity(0.12),
                    palette.primary.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.32)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                MonoIcon(icon: .back, size: 17, color: .white.opacity(0.92))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(MonoBouncingButtonStyle())

            Text(String(localized: "沉浸模式设置"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(player.currentSong?.name ?? String(localized: "not_playing"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
    }

    private var effectPanel: some View {
        panel(showsDownIndicator: effectHasMoreContent) {
            VStack(alignment: .leading, spacing: 10) {
                panelTitle(String(localized: "字幕特效"))

                AriaLandscapePanelScrollView(hasMoreContent: $effectHasMoreContent) {
                    LazyVStack(spacing: 7) {
                        ForEach(AriaLyricEffect.allCases, id: \.rawValue) { effect in
                            effectButton(effect)
                        }
                    }
                }
            }
        }
    }

    private func effectButton(_ effect: AriaLyricEffect) -> some View {
        let selected = lyricEffect == effect

        return Button {
            withAnimation(.smooth(duration: 0.22)) {
                lyricEffectRaw = effect.rawValue
            }
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(selected ? palette.accent : Color.white.opacity(0.12))
                    .frame(width: 7, height: 7)
                    .shadow(color: palette.accent.opacity(selected ? 0.55 : 0), radius: 6)

                Text(effect.label)
                    .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.55))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.1 : 0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected ? palette.accent.opacity(0.34) : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var stylePanel: some View {
        panel(showsDownIndicator: styleHasMoreContent) {
            AriaLandscapePanelScrollView(hasMoreContent: $styleHasMoreContent) {
                VStack(alignment: .leading, spacing: 14) {
                    fontPreview
                    fontGrid
                    materialGrid
                    typographyControls
                    fontScaleControl

                    if !lyricEffect.usesFullStage {
                        layoutControl
                    }

                    colorControls
                }
            }
        }
    }

    private var fontPreview: some View {
        VStack(spacing: 4) {
            AriaLyricTypographyPreview(
                text: "春风又绿江南岸  Midnight Radio",
                fontChoice: lyricFont,
                fontSize: 27,
                configuration: lyricTypography,
                palette: palette
            )
            .id(
                "\(lyricFont.cacheIdentity)|\(customFontID)|\(lyricMaterialStyle.rawValue)|\(lyricTypography)"
            )

            Text(lyricFont.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var fontGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoFontPicker(
                selectionRaw: $lyricFontRaw,
                customFontID: $customFontID,
                accent: palette.accent,
                layout: .grid(columns: 3),
                customFontScope: .cjkCapable
            )

            // 外语歌整首生效；中文歌里的英文始终用主字体的拉丁字形
            MonoForeignFontMenuRow(
                selectionRaw: $foreignLyricFontRaw,
                customFontID: $foreignCustomFontID,
                accent: palette.accent
            )
        }
    }

    private var materialGrid: some View {
        VStack(alignment: .leading, spacing: 7) {
            controlLabel(String(localized: "字体材质"))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(AriaLyricMaterialStyle.allCases, id: \.rawValue) { style in
                    materialButton(style)
                }
            }
        }
    }

    private func materialButton(_ style: AriaLyricMaterialStyle) -> some View {
        let selected = lyricMaterialStyle == style

        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                lyricMaterialStyleRaw = style.rawValue
            }
        } label: {
            Text(style.label)
                .font(.system(size: 10, weight: selected ? .bold : .medium, design: .rounded))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.44))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.1 : 0.035))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            selected ? palette.accent.opacity(0.5) : Color.white.opacity(0.05),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private var typographyControls: some View {
        VStack(spacing: 10) {
            landscapeSlider(
                title: String(localized: "透明度"),
                value: $lyricOpacity,
                range: 0.2...1,
                display: "\(Int(lyricOpacity * 100))%"
            )
            landscapeSlider(
                title: String(localized: "辉光"),
                value: $lyricGlowStrength,
                range: 0...1,
                display: "\(Int(lyricGlowStrength * 100))%"
            )

            if lyricMaterialStyle == .particle {
                landscapeSlider(
                    title: String(localized: "粒子密度"),
                    value: $particleDensity,
                    range: 0.15...1,
                    display: "\(Int(particleDensity * 100))%"
                )
                landscapeSlider(
                    title: String(localized: "粒子尺寸"),
                    value: $particleSize,
                    range: 0.55...2.4,
                    display: String(format: "%.2f×", particleSize)
                )
                landscapeToggle(String(localized: "粒子流动"), isOn: $particleMotion)
            }

            if lyricMaterialStyle == .glass {
                landscapeSlider(
                    title: String(localized: "玻璃质感"),
                    value: $glassIntensity,
                    range: 0.15...1,
                    display: "\(Int(glassIntensity * 100))%"
                )
            }
        }
    }

    private var fontScaleControl: some View {
        VStack(spacing: 5) {
            HStack {
                controlLabel(String(localized: "字号"))
                Spacer()
                controlValue(String(format: "%.2f×", fontScale))
            }
            Slider(value: $fontScale, in: 0.7...1.6)
                .tint(palette.accent)
                .controlSize(.small)
        }
    }

    private var layoutControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            controlLabel(String(localized: "字幕排版"))

            HStack(spacing: 4) {
                ForEach(AriaLyricLayoutChoice.allCases, id: \.rawValue) { choice in
                    let selected = lyricLayoutRaw == choice.rawValue

                    Button {
                        lyricLayoutRaw = choice.rawValue
                    } label: {
                        Text(choice.label)
                            .font(.system(size: 11, weight: selected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.44))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.white.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
        }
    }

    private var colorControls: some View {
        VStack(spacing: 9) {
            landscapeToggle(String(localized: "自动取色"), isOn: $lyricAutoColor)

            if lyricAutoColor {
                CoverPaletteSettingsControls(accent: palette.accent)
            }

            HStack {
                controlLabel(String(localized: "自定义颜色"))
                Spacer()
                ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
            .opacity(lyricAutoColor ? 0.48 : 1)

            if lyricEffect == .canopy {
                landscapeToggle(
                    String(localized: "巨幕碎幕律动"),
                    isOn: $canopyFragmentStage
                )
            }
            landscapeToggle(
                String(localized: "显示翻译"),
                isOn: lyricEffect == .poster ? $posterShowTranslation : $showTranslation
            )
            landscapeToggle(
                String(localized: "英文歌词强制大写"),
                isOn: $forceUppercaseEnglish
            )
        }
    }

    private var stagePanel: some View {
        panel(showsDownIndicator: stageHasMoreContent) {
            AriaLandscapePanelScrollView(hasMoreContent: $stageHasMoreContent) {
                VStack(alignment: .leading, spacing: 13) {
                    panelTitle(String(localized: "舞台背景"))
                    coverPreview
                    backgroundOpacityControl
                    landscapeSlider(
                        title: String(localized: "歌词景深"),
                        value: $lyricDepthIntensity,
                        range: 0.2...1,
                        display: "\(Int(lyricDepthIntensity * 100))%"
                    )
                    landscapeToggle(String(localized: "立体浮雕"), isOn: $lyricEmbossEnabled)
                    landscapeToggle(String(localized: "动态色彩呼吸"), isOn: $ambientMotion)
                    landscapeToggle(
                        String(localized: "常驻沉浸模式"),
                        isOn: $immersivePersistent
                    )

                    panelTitle(String(localized: "沉浸实验室"))
                    if AriaHapticBeat.supportsHaptics {
                        landscapeToggle(String(localized: "节拍触觉"), isOn: $hapticBeatEnabled)
                    }
                    landscapeToggle(String(localized: "人声呼吸字重"), isOn: $vocalBreathingEnabled)
                    landscapeToggle(String(localized: "副歌预判张力"), isOn: $tensionSystemEnabled)
                    if #available(iOS 17.0, *) {
                        landscapeToggle(String(localized: "GPU 着色器舞台"), isOn: $gpuStageEnabled)
                    }
                    landscapeToggle(
                        String(localized: "immersive_bg_adaptive_glass_lyrics"),
                        isOn: $videoAdaptiveLyricGlass
                    )
                    videoButton
                }
            }
        }
    }

    private var coverPreview: some View {
        CachedAsyncImage(url: player.currentSong?.coverUrl?.sized(300)) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .overlay(
                    MonoIcon(icon: .album, size: 28, color: .white.opacity(0.2))
                )
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var backgroundOpacityControl: some View {
        VStack(spacing: 5) {
            HStack {
                controlLabel(String(localized: "背景压暗"))
                Spacer()
                controlValue("\(Int(backgroundOpacity * 100))%")
            }
            Slider(value: $backgroundOpacity, in: 0.45...0.95)
                .tint(palette.accent)
                .controlSize(.small)
        }
    }

    private var videoButton: some View {
        Button {
            showVideoSheet = true
        } label: {
            HStack(spacing: 8) {
                MonoIcon(icon: .mv, size: 14, color: palette.accent)
                Text(String(localized: "视频背景"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                MonoIcon(icon: .chevronRight, size: 11, color: .white.opacity(0.32))
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
    }

    private func panel<Content: View>(
        showsDownIndicator: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                if showsDownIndicator {
                    MonoIcon(
                        icon: .chevronDown,
                        size: 8,
                        color: .white.opacity(0.38),
                        lineWidth: 1.7
                    )
                    .frame(width: 24, height: 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.34))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                            }
                    )
                    .offset(y: 7)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.16), value: showsDownIndicator)
    }

    private func panelTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.48))
            .textCase(.uppercase)
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func controlValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.44))
    }

    private func landscapeSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                controlLabel(title)
                Spacer()
                controlValue(display)
            }
            Slider(value: value, in: range)
                .tint(palette.accent)
                .controlSize(.small)
        }
    }

    private func landscapeToggle(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        // 开关轨道会比布局宽度多画 2~3pt，贴着 ScrollView 右缘会被裁；
        // 预留内边距，且不用 controlSize（iOS 上无效且加剧宽度偏差）。
        Toggle(isOn: isOn) {
            controlLabel(title)
        }
        .tint(palette.accent)
        .padding(.trailing, 3)
    }
}

private struct AriaLandscapePanelBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 单独测量每个板块的内容底边。只有底边仍在可视区域下方时，
/// 外层板块才显示向下提示；滚到底或内容本身不足一屏时自动隐藏。
private struct AriaLandscapePanelScrollView<Content: View>: View {
    @Binding var hasMoreContent: Bool
    @State private var coordinateSpaceName = UUID()
    private let content: Content

    init(
        hasMoreContent: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        _hasMoreContent = hasMoreContent
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    content

                    GeometryReader { marker in
                        Color.clear.preference(
                            key: AriaLandscapePanelBottomPreferenceKey.self,
                            value: marker.frame(in: .named(coordinateSpaceName)).maxY
                        )
                    }
                    .frame(height: 1)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(AriaLandscapePanelBottomPreferenceKey.self) { bottomY in
                let hasRoomBelow = bottomY > viewport.size.height + 2
                if hasMoreContent != hasRoomBelow {
                    hasMoreContent = hasRoomBelow
                }
            }
        }
    }
}
