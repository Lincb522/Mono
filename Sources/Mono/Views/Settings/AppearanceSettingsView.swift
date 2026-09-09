//  外观与歌词设置子页面

import PhotosUI
import SwiftUI

func appearanceSettingsFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    if ClarityStyle.isActive {
        return ClarityStyle.body(size, weight: weight)
    }
    if MinimalWhiteStyle.isActive {
        return MinimalWhiteStyle.bodyFont(size, weight: weight)
    }
    if MangaStyle.isActive {
        return MangaStyle.comicFont(size, weight: weight == .regular ? .bold : weight)
    }
    if NeumorphicStyle.isActive {
        return NeumorphicStyle.labelFont(size, weight: weight)
    }
    if SignalStyle.isActive {
        return SignalStyle.labelFont(size, weight: weight)
    }
    if BentoStyle.isActive {
        return BentoStyle.labelFont(size, weight: weight == .bold ? .heavy : weight)
    }
    if MujiStyle.isActive {
        return MujiStyle.labelFont(size, weight: weight == .bold ? .semibold : weight)
    }
    return .system(size: size, weight: weight, design: .rounded)
}

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isGlobalThemeExpanded = false
    @State private var isAppBrandStyleExpanded = false
    @State private var isThemeColorExpanded = false

    var body: some View {
        ZStack {
            ThemedSettingsBackground()

            ScrollView {
                LazyVStack(spacing: SettingsPageLayout.sectionSpacing) {
                    SettingsScrollablePageHeader(
                        title: String(localized: "settings_navigation_appearance_title"),
                        eyebrow: String(localized: "settings_eyebrow_appearance"),
                        icon: .playerTheme,
                        signalModule: .appearance
                    )
                    .monoIconArtwork("themeStyle")

                    LazyVStack(spacing: SettingsPageLayout.sectionSpacing) {
                        globalThemeSection
                        if ThemeColorCustomization.supports(settings.globalThemeId) {
                            themeColorCustomizationSection
                        }
                        appIconSection
                        layoutSection
                        contentExperienceSection
                        dynamicBackgroundSection
                        FloatingBarBottomSpacer()
                    }
                    .padding(.horizontal, DeviceLayout.settingsSectionHorizontalPadding)
                    .padding(.bottom, 44)
                    .iPadContentWidth(SettingsPageLayout.contentWidth)
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: SettingsPageLayout.scrollCoordinateSpace)
            .themeRenderScrollLayer()
        }
        .asideSettingsDetailChrome()
        .onAppear {
            settings.enforceCoverBackgroundPolicyForCurrentTheme()
        }
    }

    // MARK: - 外观

    @ViewBuilder
    private var themeColorCustomizationSection: some View {
        ThemeColorCustomizationSection(
            theme: settings.globalThemeId,
            isExpanded: $isThemeColorExpanded
        )
    }

    private var appIconSection: some View {
        SettingsSection(title: String(localized: "settings_appearance_app_icon_section")) {
            VStack(spacing: 0) {
                SettingsAppBrandRow(
                    title: String(localized: "settings_app_brand_title"),
                    selection: settings.appBrandStyle,
                    appearance: settings.appBrandAppearance,
                    isExpanded: $isAppBrandStyleExpanded,
                    onSelect: { style in
                        Task {
                            await settings.selectAppBrandStyle(style)
                        }
                    },
                    onSelectAppearance: { appearance in
                        Task {
                            await settings.selectAppBrandAppearance(appearance)
                        }
                    }
                )

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsInterfaceIconSetRow(
                    title: String(localized: "settings_interface_icon_set_title"),
                    selection: Binding(
                        get: { settings.interfaceIconSet },
                        set: { settings.interfaceIconSet = $0 }
                    )
                )
            }
        }
    }

    private var layoutSection: some View {
        SettingsSection(title: String(localized: "settings_appearance_layout_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .tabBar,
                    title: String(localized: "settings_system_tab_bar"),
                    subtitle: nil,
                    isOn: $settings.useSystemTabBar
                )
                .monoIconArtwork("systemTabBar")

                if settings.useSystemTabBar {
                    Divider().padding(.leading, 56)
                    SettingsSystemTabBarRow(selection: Binding(
                        get: { settings.systemTabBarStyle },
                        set: { settings.systemTabBarStyle = $0 }
                    ))
                } else {
                    Divider()
                        .padding(.leading, 56)

                    SettingsFloatingBarRow(
                        icon: .layers,
                        title: String(localized: "settings_floating_bar"),
                        selection: Binding(
                            get: { settings.floatingBarStyle },
                            set: { settings.floatingBarStyle = $0 }
                        )
                    )
                    .monoIconArtwork("floatingBarStyle")

                    if settings.globalThemeId == .default {
                        Divider()
                            .padding(.leading, 56)

                        SettingsToggleRow(
                            icon: .sparkle,
                            title: String(localized: "settings_default_liquid_glass_tabbar"),
                            subtitle: nil,
                            isOn: $settings.defaultThemeUsesLiquidGlassTabBar
                        )
                        .monoIconArtwork("liquidGlass")
                    }
                }
            }
        }
    }

    private var contentExperienceSection: some View {
        SettingsSection(title: String(localized: "settings_appearance_content_feedback_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .hitokoto,
                    title: String(localized: "settings_hitokoto"),
                    subtitle: String(localized: "settings_hitokoto_desc"),
                    isOn: $settings.hitokotoEnabled
                )

                if settings.hitokotoEnabled {
                    Divider()
                        .padding(.leading, 56)

                    SettingsHitokotoTypeRow(
                        icon: .filter,
                        title: String(localized: "settings_hitokoto_type"),
                        selection: $settings.hitokotoType
                    )
                }

                Divider()
                    .opacity(0.4)
                    .padding(.leading, 62)

                SettingsToggleRow(
                    icon: .haptic,
                    title: String(localized: "settings_haptic"),
                    subtitle: String(localized: "settings_haptic_desc"),
                    isOn: $settings.hapticFeedback
                )
            }
        }
    }

    private var dynamicBackgroundSection: some View {
        let paletteAccent = GlobalThemeManager.shared.colors.accent

        return SettingsSection(title: String(localized: "settings_appearance_dynamic_background_section")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: .playerTheme,
                    title: String(localized: "settings_dynamic_artwork"),
                    subtitle: String(localized: "settings_dynamic_artwork_desc"),
                    isOn: animatedArtworkBinding
                )
                .monoIconArtwork("dynamicArtwork")

                if settings.globalThemeId.supportsArtworkColoring
                    || settings.globalThemeId.supportsCoverBackgrounds {

                    Divider()
                        .opacity(0.4)
                        .padding(.leading, 62)

                    if settings.globalThemeId == .default {
                        SettingsToggleRow(
                            icon: .sparkle,
                            title: String(localized: "settings_aside_fluid_background"),
                            subtitle: String(localized: "settings_aside_fluid_background_desc"),
                            isOn: $settings.asideMusicFluidBackgroundEnabled
                        )
                        .monoIconArtwork("fluidBackground")

                        Divider()
                            .opacity(0.4)
                            .padding(.leading, 62)
                    }

                    SettingsToggleRow(
                        icon: .layers,
                        title: String(localized: "settings_cover_bg_global"),
                        subtitle: String(localized: "settings_cover_bg_global_desc"),
                        isOn: $settings.coverBgGlobal,
                        isEnabled: !settings.locksCoverBackgroundSettings
                    )
                    .monoIconArtwork("backgroundGlobal")

                    Divider()
                        .opacity(0.4)
                        .padding(.leading, 62)

                    SettingsToggleRow(
                        icon: .layers,
                        title: String(localized: "settings_cover_bg_playlist"),
                        subtitle: String(localized: "settings_cover_bg_playlist_desc"),
                        isOn: $settings.coverBgPlaylist,
                        isEnabled: !settings.locksCoverBackgroundSettings
                    )
                    .monoIconArtwork("backgroundPlaylist")

                    Divider()
                        .opacity(0.4)
                        .padding(.leading, 62)

                    SettingsToggleRow(
                        icon: .layers,
                        title: String(localized: "settings_cover_bg_player"),
                        subtitle: String(localized: "settings_cover_bg_player_desc"),
                        isOn: $settings.coverBgPlayer,
                        isEnabled: !settings.locksCoverBackgroundSettings
                    )
                    .monoIconArtwork("backgroundPlayer")

                    if settings.globalThemeId.supportsArtworkColoring {
                        Divider()
                            .opacity(0.4)
                            .padding(.leading, 62)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                SettingsIconBadge(icon: .sparkle)
                                    .monoIconArtwork("colorEngine")

                                Text(String(localized: "color_engine_title"))
                                    .font(appearanceSettingsFont(14, weight: .semibold))
                                    .foregroundStyle(Color.monoTextPrimary)
                            }

                            UnifiedColorEngineSettingsControls(accent: paletteAccent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var animatedArtworkBinding: Binding<Bool> {
        Binding(
            get: { settings.animatedArtworkEnabled },
            set: { isEnabled in
                settings.animatedArtworkEnabled = isEnabled
                PlayerManager.shared.refreshDynamicArtworkPreference()
            }
        )
    }

    // MARK: - 全局主题

    private var globalThemePreviewColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: DeviceLayout.usesExpandedLayout ? 176 : 148, maximum: DeviceLayout.usesExpandedLayout ? 218 : 186),
                spacing: 12
            ),
        ]
    }

    private var globalThemeSection: some View {
        SettingsSection(title: String(localized: "settings_appearance_global_theme_section")) {
            VStack(spacing: 0) {
                Button {
                    isGlobalThemeExpanded.toggle()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(icon: .playerTheme)
                            .monoIconArtwork("themeStyle")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings_appearance_theme_style"))
                                .font(appearanceSettingsFont(15, weight: .medium))
                                .foregroundColor(.monoTextPrimary)

                            Text(settings.globalThemeId.displayName)
                                .font(appearanceSettingsFont(11, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        PetWhiteDisclosureChevron(isExpanded: isGlobalThemeExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                SettingsDisclosureReveal(isExpanded: isGlobalThemeExpanded) {
                    LazyVGrid(columns: globalThemePreviewColumns, spacing: 12) {
                        ForEach(GlobalThemeId.allCases) { themeId in
                            Button {
                                applyGlobalTheme(themeId)
                            } label: {
                                GlobalThemeOptionCard(
                                    themeId: themeId,
                                    isSelected: settings.globalThemeId == themeId
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func applyGlobalTheme(_ themeId: GlobalThemeId) {
        settings.selectGlobalTheme(themeId)
        if let playerTheme = GlobalThemeManager.shared.provider(for: themeId).suggestedPlayerTheme {
            PlayerThemeManager.shared.setTheme(playerTheme)
        }
    }

    // 歌词颜色设置已迁移到播放器右上角三点菜单 →「歌词外观」（MonoFontPicker.swift）
}
