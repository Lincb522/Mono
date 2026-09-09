import SwiftUI

// MARK: - Settings Icon Badge

struct SettingsIconBadge: View {
    let icon: MonoIcon.IconType
    var artwork: MonoGlyphSemantic? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    var body: some View {
        let _ = settings.globalThemeRevision
        Group {
            if developerDiagnosticStyle {
                MonoIcon(
                icon: icon,
                size: 14,
                color: .cyan,
                lineWidth: 1.6
                )
                .frame(width: 32, height: 32)
                .background(Color.cyan.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                }
            } else if ClarityStyle.isActive {
                MonoIcon(
                icon: icon,
                size: 15,
                color: ClarityStyle.ink,
                lineWidth: 1.5
                )
                .frame(width: 34, height: 34)
                .background(ClarityMembrane(shape: Circle(), strength: .quiet))
            } else if MinimalWhiteStyle.isActive {
                MonoIcon(
                icon: icon,
                size: 14,
                color: MinimalWhiteStyle.inkSoft,
                lineWidth: 1.55
                )
                .frame(width: 32, height: 32)
                .background(
                    MinimalWhiteSurfaceBackground(
                        cornerRadius: MinimalWhiteStyle.compactRadius,
                        elevated: false,
                        tint: MinimalWhiteStyle.controlGlassFill
                    )
                )
            } else if MangaStyle.isActive {
            // 周刊印刷：单色墨线图标，不再上彩色底章
            MonoIcon(
                icon: icon,
                size: 15,
                color: MangaStyle.ink,
                lineWidth: 1.8
            )
            .frame(width: 32, height: 32)
            } else if NeumorphicStyle.isActive {
            NeumorphicIconBadge(icon: icon, tint: NeumorphicStyle.accent, size: 32)
            } else if SignalStyle.isActive {
            MonoIcon(icon: icon, size: 15, color: SignalStyle.accent, lineWidth: 1.6)
                .frame(width: 32, height: 32)
            } else if CapsuleStyle.isActive {
            CapsuleIconBadge(icon: icon, tint: CapsuleStyle.accent, size: 32)
            } else if PetWhiteStyle.isActive {
            PetWhiteIconBadge(icon: icon, tint: petWhiteSettingsIconTint, size: 36)
            } else if BentoStyle.isActive {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(BentoStyle.tomato.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    MonoIcon(icon: icon, size: 15, color: BentoStyle.tomato, lineWidth: 1.65)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(BentoStyle.hairline.opacity(0.58), lineWidth: 0.65)
                )
            } else if SequoiaStyle.isActive {
            SequoiaIconBadge(icon: icon, tint: SequoiaStyle.accent, size: 32)
            } else if MujiStyle.isActive {
            Circle()
                .fill(MujiStyle.wash(MujiStyle.clay, strength: 1.25))
                .frame(width: 31, height: 31)
                .overlay(
                    MonoIcon(
                        icon: icon,
                        size: 14,
                        color: ThemeColorCustomization.visibleTintColor(MujiStyle.clay, darkFallback: MujiStyle.ink),
                        lineWidth: 1.5
                    )
                )
            } else if GlobalThemeId.persistedOrDefault == .default {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.monoAccent.opacity(0.1))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.monoAccent.opacity(0.18), lineWidth: 0.7)
                MonoIcon(
                    icon: icon,
                    size: 14,
                    color: ThemeColorCustomization.visibleTintColor(
                        Color.monoAccent,
                        darkFallback: Color.monoTextPrimary
                    ),
                    lineWidth: 1.6
                )
            }
            .frame(width: 34, height: 34)
            } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.monoAccent.opacity(0.14))
                    .frame(width: 30, height: 30)
                MonoIcon(
                    icon: icon,
                    size: 14,
                    color: ThemeColorCustomization.visibleTintColor(
                        Color.monoAccent,
                        darkFallback: Color.monoTextPrimary
                    ),
                    lineWidth: 1.6
                )
            }
            }
        }
        .monoIconArtwork(artwork?.rawValue)
    }

    private var petWhiteSettingsIconTint: Color {
        switch icon {
        case .settings, .sparkle:
            return PetWhiteStyle.mint
        case .playerTheme, .tabBar, .gridSquare:
            return PetWhiteStyle.butter
        case .download, .storage, .cloud:
            return PetWhiteStyle.sky
        default:
            return PetWhiteStyle.sky
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    /// aside 默认主题（编辑部风格分支）
    private var isAsideTheme: Bool {
        GlobalThemeId.persistedOrDefault == .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if MujiStyle.isActive {
                    // Muji：双色圆点眉标
                    MujiDotMark()
                }

                Text(developerDiagnosticStyle
                    ? title
                    : ((ClarityStyle.isActive || MinimalWhiteStyle.isActive || isAsideTheme) ? title : title.uppercased()))
                    .font(developerDiagnosticStyle
                        ? .system(size: 11.5, weight: .bold, design: .rounded)
                        : sectionTitleFont)
                    .foregroundColor(developerDiagnosticStyle
                        ? .white.opacity(0.48)
                        : sectionTitleColor)
                    .tracking(developerDiagnosticStyle
                        ? 0
                        : ((MinimalWhiteStyle.isActive || isAsideTheme) ? 0 : (MujiStyle.isActive || NeumorphicStyle.isActive || SequoiaStyle.isActive || BentoStyle.isActive ? 1.0 : 0.4)))
            }
            .padding(.leading, developerDiagnosticStyle || isAsideTheme || ClarityStyle.isActive || SignalStyle.isActive ? 0 : 16)

            VStack(spacing: 0) {
                content
            }
            .background {
                if developerDiagnosticStyle {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.045, green: 0.05, blue: 0.061))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 0.65)
                        }
                } else if ClarityStyle.isActive {
                    ClaritySettingsSectionPlane()
                } else if MangaStyle.isActive {
                    // 去卡片化：设置分组用上下规则线围合，内容直接排在纸上
                    VStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(MangaStyle.ink.opacity(0.72))
                                .frame(height: 1.6)
                            Rectangle()
                                .fill(MangaStyle.ink.opacity(0.26))
                                .frame(height: 0.8)
                        }
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(MangaStyle.strokeInk.opacity(0.22))
                            .frame(height: 1)
                    }
                } else if MujiStyle.isActive {
                    // Muji：清新水洗底，柔圆角不描边
                    RoundedRectangle(cornerRadius: MujiStyle.cardRadius, style: .continuous)
                        .fill(MujiStyle.wash(MujiStyle.clay, strength: 0.7))
                } else if NeumorphicStyle.isActive {
                    NeumorphicSurfaceBackground(cornerRadius: 22, elevated: true, lightweight: true)
                } else if CapsuleStyle.isActive {
                    CapsuleSurfaceBackground(cornerRadius: 22, elevated: true, tint: CapsuleStyle.surface.opacity(0.9))
                } else if SequoiaStyle.isActive {
                    SequoiaSurfaceBackground(cornerRadius: 18, elevated: false, role: .list)
                } else if SignalStyle.isActive {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(SignalStyle.separator.opacity(0.76))
                            .frame(height: 0.65)
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(SignalStyle.separator.opacity(0.48))
                            .frame(height: 0.65)
                    }
                } else if BentoStyle.isActive {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(BentoStyle.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(BentoStyle.hairline.opacity(0.56), lineWidth: 0.7)
                        )
                } else if isAsideTheme {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.monoGlassTint.opacity(0.54))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.monoSeparator.opacity(0.52), lineWidth: 0.8)
                        }
                }
            }
            .monoGlassConditionalForSettings(
                cornerRadius: developerDiagnosticStyle ? 16 : (isAsideTheme ? 14 : 22),
                disabled: developerDiagnosticStyle
            )
            .claritySettingsSectionClip(cornerRadius: ClarityStyle.settingsSectionRadius)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ClarityStyle.isActive
                        ? ClarityStyle.settingsSectionRadius
                        : (developerDiagnosticStyle ? 16 : (isAsideTheme ? 14 : 22)),
                    style: .continuous
                )
            )
        }
    }

    private var sectionTitleFont: Font {
        if ClarityStyle.isActive { return ClarityStyle.body(12, weight: .semibold) }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.labelFont(12, weight: .semibold) }
        if MangaStyle.isActive { return MangaStyle.labelFont(12, weight: .black) }
        if MujiStyle.isActive { return MujiStyle.labelFont(11, weight: .semibold) }
        if NeumorphicStyle.isActive { return NeumorphicStyle.labelFont(11, weight: .semibold) }
        if CapsuleStyle.isActive { return CapsuleStyle.labelFont(11, weight: .bold) }
        if SequoiaStyle.isActive { return SequoiaStyle.labelFont(11, weight: .semibold) }
        if SignalStyle.isActive { return SignalStyle.labelFont(11, weight: .bold) }
        if BentoStyle.isActive { return BentoStyle.labelFont(11, weight: .heavy) }
        if isAsideTheme { return .system(size: 12, weight: .bold) }
        return .system(size: 12, weight: .bold, design: .rounded)
    }

    private var sectionTitleColor: Color {
        if ClarityStyle.isActive { return ClarityStyle.inkSoft }
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.inkMuted }
        if MangaStyle.isActive { return MangaStyle.ink }
        if MujiStyle.isActive { return MujiStyle.inkSoft }
        if NeumorphicStyle.isActive { return NeumorphicStyle.inkSoft }
        if CapsuleStyle.isActive { return CapsuleStyle.inkMuted }
        if SequoiaStyle.isActive { return SequoiaStyle.inkMuted }
        if SignalStyle.isActive { return SignalStyle.inkSoft }
        if BentoStyle.isActive { return BentoStyle.inkMuted }
        if isAsideTheme { return Color.monoTextSecondary.opacity(0.82) }
        return Color.secondary
    }
}

extension View {
    @ViewBuilder
    func claritySettingsSectionClip(cornerRadius: CGFloat) -> some View {
        if ClarityStyle.isActive {
            clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
        }
    }

    @ViewBuilder
    func monoGlassConditionalForSettings(cornerRadius: CGFloat, disabled: Bool = false) -> some View {
        if disabled || ClarityStyle.isActive || MangaStyle.isActive || PetWhiteStyle.isActive || MujiStyle.isActive || NeumorphicStyle.isActive || CapsuleStyle.isActive || SequoiaStyle.isActive || SignalStyle.isActive || BentoStyle.isActive {
            self
        } else {
            monoGlass(cornerRadius: cornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func themedSettingsStandaloneCard(cornerRadius: CGFloat, tint: Color = MangaStyle.bubbleWhite) -> some View {
        if ClarityStyle.isActive {
            let clarityRadius = min(max(cornerRadius, 20), 30)
            background(
                ClarityMembrane(
                    shape: RoundedRectangle(cornerRadius: clarityRadius, style: .continuous),
                    strength: .strong
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: clarityRadius, style: .continuous))
        } else if MinimalWhiteStyle.isActive {
            background(
                MinimalWhiteSurfaceBackground(
                    cornerRadius: min(max(cornerRadius, MinimalWhiteStyle.compactRadius), MinimalWhiteStyle.chromeRadius),
                    elevated: true,
                    tint: MinimalWhiteStyle.glassFill
                )
            )
        } else if MangaStyle.isActive {
            // 设置页唯一焦点分格：开发者卡保留厚墨框错版投影
            background(MangaCardBackground(cornerRadius: cornerRadius, elevated: true, tint: tint, poster: true))
        } else if PetWhiteStyle.isActive {
            background(
                PetWhiteSurfaceBackground(
                    cornerRadius: min(max(cornerRadius, 16), 28),
                    elevated: true,
                    tint: PetWhiteStyle.surfaceRaised,
                    accent: tint
                )
            )
        } else if MujiStyle.isActive {
            // Muji：清新水洗底，柔圆角不描边
            background(
                RoundedRectangle(cornerRadius: MujiStyle.cardRadius, style: .continuous)
                    .fill(MujiStyle.wash(MujiStyle.clay, strength: 0.7))
            )
        } else if NeumorphicStyle.isActive {
            background(NeumorphicSurfaceBackground(cornerRadius: min(max(cornerRadius, 18), 26), elevated: true, lightweight: true))
        } else if CapsuleStyle.isActive {
            background(
                CapsuleSurfaceBackground(
                    cornerRadius: min(max(cornerRadius, 18), 26),
                    elevated: true,
                    tint: CapsuleStyle.surface.opacity(0.9)
                )
            )
        } else if SequoiaStyle.isActive {
            background(SequoiaSurfaceBackground(cornerRadius: min(max(cornerRadius, 16), 24), elevated: true, role: .chrome))
        } else if SignalStyle.isActive {
            background {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(SignalStyle.separator.opacity(0.76))
                        .frame(height: 0.65)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(SignalStyle.separator.opacity(0.48))
                        .frame(height: 0.65)
                }
            }
        } else if BentoStyle.isActive {
            background(
                RoundedRectangle(cornerRadius: min(max(cornerRadius, 18), 26), style: .continuous)
                    .fill(BentoStyle.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: min(max(cornerRadius, 18), 26), style: .continuous)
                            .stroke(BentoStyle.hairline.opacity(0.58), lineWidth: 0.7)
                    )
            )
        } else {
            monoGlass(cornerRadius: cornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
    }
}

// MARK: - Settings Rows

struct SettingsSwitchToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle
    @Environment(\.isEnabled) private var isEnabled

    private var offTrackColor: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.controlGlassFill }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfacePressed }
        if CapsuleStyle.isActive { return CapsuleStyle.surfaceTint.opacity(0.8) }
        if SequoiaStyle.isActive { return SequoiaStyle.materialPressed }
        if SignalStyle.isActive { return SignalStyle.controlPressed }
        if BentoStyle.isActive { return BentoStyle.paperWarm }
        return Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.2))
    }

    private var offStrokeColor: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.hairline }
        if NeumorphicStyle.isActive { return NeumorphicStyle.separator.opacity(0.45) }
        if CapsuleStyle.isActive { return CapsuleStyle.separator.opacity(0.48) }
        if SequoiaStyle.isActive { return SequoiaStyle.separator.opacity(0.72) }
        if SignalStyle.isActive { return SignalStyle.separator.opacity(0.52) }
        if BentoStyle.isActive { return BentoStyle.hairline.opacity(0.62) }
        return Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.14))
    }

    private func knobColor(isOn: Bool) -> Color {
        if MinimalWhiteStyle.isActive {
            return isOn ? MinimalWhiteStyle.onAccent : MinimalWhiteStyle.paper
        }
        if NeumorphicStyle.isActive {
            return isOn ? NeumorphicStyle.surfaceRaised : NeumorphicStyle.surface
        }
        if SequoiaStyle.isActive {
            return isOn ? SequoiaStyle.onAccent : SequoiaStyle.materialRaised
        }
        if CapsuleStyle.isActive {
            return isOn ? CapsuleStyle.onAccent : CapsuleStyle.surfaceRaised
        }
        if SignalStyle.isActive {
            return isOn ? SignalStyle.accent : SignalStyle.deviceRaised
        }
        if BentoStyle.isActive {
            return isOn ? BentoStyle.onAccent : BentoStyle.surface
        }
        if isOn {
            return colorScheme == .dark ? .black : .white
        }
        return .white
    }

    private func strokeColor(isOn: Bool) -> Color {
        if isOn {
            if MinimalWhiteStyle.isActive {
                return MinimalWhiteStyle.ink.opacity(0.08)
            }
            if SequoiaStyle.isActive {
                return SequoiaStyle.accent.opacity(colorScheme == .dark ? 0.28 : 0.16)
            }
            if BentoStyle.isActive {
                return BentoStyle.tomato.opacity(0.22)
            }
            if CapsuleStyle.isActive {
                return CapsuleStyle.accent.opacity(0.28)
            }
            return Color.monoToggleTint.opacity(colorScheme == .dark ? 0.24 : 0.08)
        }
        return offStrokeColor
    }

    var trackSize: CGSize {
        CGSize(width: 52, height: 32)
    }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if ElasticSettingsSwitch.isActiveForCurrentTheme && !developerDiagnosticStyle {
            Button {
                configuration.isOn.toggle()
            } label: {
                ElasticSettingsSwitch(isOn: configuration.isOn)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ElasticSettingsSwitchButtonStyle())
            .opacity(isEnabled ? 1 : 0.5)
        } else {
            themedSwitch(configuration: configuration)
        }
    }

    private func themedSwitch(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? activeTrackColor : offTrackColor)
                    .overlay {
                        Capsule()
                            .stroke(strokeColor(isOn: configuration.isOn), lineWidth: 1)
                    }
                    .frame(width: trackSize.width, height: trackSize.height)

                Circle()
                    .fill(knobColor(isOn: configuration.isOn))
                    .frame(width: 28, height: 28)
                    .padding(2)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 6, x: 0, y: 2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.84), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }

    private var activeTrackColor: Color {
        if MinimalWhiteStyle.isActive { return MinimalWhiteStyle.ink }
        return NeumorphicStyle.isActive ? NeumorphicStyle.accent : (CapsuleStyle.isActive ? CapsuleStyle.accent : (BentoStyle.isActive ? BentoStyle.tomato : (SequoiaStyle.isActive ? SequoiaStyle.accent : Color.monoToggleTint)))
    }
}

struct SettingsToggleRow: View {
    let icon: MonoIcon.IconType
    var artwork: MonoGlyphSemantic? = nil
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var isEnabled: Bool = true
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    private var usesElasticSwitch: Bool {
        ElasticSettingsSwitch.isActiveForCurrentTheme && !developerDiagnosticStyle
    }

    var body: some View {
        Group {
            if usesElasticSwitch {
                Toggle(isOn: $isOn) {
                    rowLabel
                }
                .toggleStyle(ElasticSettingsRowToggleStyle())
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(subtitle ?? ""))
            } else {
                Button {
                    isOn.toggle()
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: icon, artwork: artwork)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(developerDiagnosticStyle
                        ? .system(size: 15, weight: .semibold, design: .rounded)
                        : themedSettingsFont(15, weight: .medium))
                    .foregroundColor(developerDiagnosticStyle ? .white : themedSettingsPrimaryColor())

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(developerDiagnosticStyle
                            ? .system(size: 11, weight: .medium, design: .rounded)
                            : themedSettingsFont(11, weight: .regular))
                        .foregroundColor(developerDiagnosticStyle
                            ? .white.opacity(0.45)
                            : themedSettingsSecondaryColor())
                }
            }

            Spacer()

            if developerDiagnosticStyle {
                Toggle("", isOn: .constant(isOn))
                    .labelsHidden()
                    .tint(.cyan)
                    .allowsHitTesting(false)
            } else if usesElasticSwitch {
                ElasticSettingsSwitch(isOn: isOn)
            } else {
                Toggle("", isOn: .constant(isOn))
                    .labelsHidden()
                    .toggleStyle(SettingsSwitchToggleStyle())
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct SettingsNavigationRow: View {
    let icon: MonoIcon.IconType
    var artwork: MonoGlyphSemantic?
    let title: String
    var subtitle: String?
    var subtitleColor: Color?
    var value: String?
    let action: () -> Void
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    init(icon: MonoIcon.IconType, artwork: MonoGlyphSemantic? = nil, title: String, value: String, action: @escaping () -> Void) {
        self.icon = icon
        self.artwork = artwork
        self.title = title
        self.value = value
        self.action = action
    }

    init(icon: MonoIcon.IconType, artwork: MonoGlyphSemantic? = nil, title: String, subtitle: String? = nil, subtitleColor: Color? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.artwork = artwork
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIconBadge(icon: icon, artwork: artwork)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(developerDiagnosticStyle
                            ? .system(size: 15, weight: .semibold, design: .rounded)
                            : themedSettingsFont(15, weight: .medium))
                        .foregroundColor(developerDiagnosticStyle ? .white : themedSettingsPrimaryColor())

                    if let subtitle {
                        if let subtitleColor {
                            Text(subtitle)
                                .font(themedSettingsFont(11, weight: .regular))
                                .foregroundColor(subtitleColor)
                        } else {
                            Text(subtitle)
                                .font(themedSettingsFont(11, weight: .regular))
                                .foregroundColor(developerDiagnosticStyle
                                    ? .white.opacity(0.45)
                                    : themedSettingsSecondaryColor())
                        }
                    }
                }

                Spacer()

                if let value {
                    Text(value)
                        .font(themedSettingsFont(14, weight: .regular))
                        .foregroundColor(developerDiagnosticStyle
                            ? .white.opacity(0.45)
                            : themedSettingsSecondaryColor())
                }

                MonoIcon(
                    icon: .chevronRight,
                    size: 11,
                    color: developerDiagnosticStyle ? .white.opacity(0.35) : themedSettingsSecondaryColor()
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsRouteLinkRow: View {
    let icon: MonoIcon.IconType
    var artwork: MonoGlyphSemantic? = nil
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    let destination: SettingsNavigationDestination
    /// 相对默认行略增高入口卡片（设置主页「外观/播放」等）
    var verticalPadding: CGFloat = 13
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    var body: some View {
        NavigationLink {
            destination.view
        } label: {
            HStack(spacing: 12) {
                SettingsIconBadge(icon: icon, artwork: artwork)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(developerDiagnosticStyle
                            ? .system(size: 15, weight: .semibold, design: .rounded)
                            : themedSettingsFont(15, weight: .medium))
                        .foregroundColor(developerDiagnosticStyle ? .white : themedSettingsPrimaryColor())

                    if let subtitle {
                        Text(subtitle)
                            .font(themedSettingsFont(11, weight: .regular))
                            .foregroundColor(developerDiagnosticStyle
                                ? .white.opacity(0.45)
                                : themedSettingsSecondaryColor())
                    }
                }

                Spacer()

                if let value {
                    Text(value)
                        .font(themedSettingsFont(13, weight: .medium))
                        .foregroundColor(developerDiagnosticStyle
                            ? .white.opacity(0.45)
                            : themedSettingsSecondaryColor())
                }

                MonoIcon(
                    icon: .chevronRight,
                    size: 11,
                    color: developerDiagnosticStyle ? .white.opacity(0.35) : themedSettingsSecondaryColor()
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsLinkRow<Destination: View>: View {
    let icon: MonoIcon.IconType
    var artwork: MonoGlyphSemantic? = nil
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    let destination: Destination
    /// 相对默认行略增高入口卡片（设置主页「外观/播放」等）
    var verticalPadding: CGFloat = 13

    var body: some View {
        NavigationLink(
            destination: destination
        ) {
            HStack(spacing: 12) {
                SettingsIconBadge(icon: icon, artwork: artwork)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(themedSettingsFont(15, weight: .medium))
                        .foregroundColor(themedSettingsPrimaryColor())

                    if let subtitle {
                        Text(subtitle)
                            .font(themedSettingsFont(11, weight: .regular))
                            .foregroundColor(themedSettingsSecondaryColor())
                    }
                }

                Spacer()

                if let value {
                    Text(value)
                        .font(themedSettingsFont(13, weight: .medium))
                        .foregroundColor(themedSettingsSecondaryColor())
                }

                MonoIcon(icon: .chevronRight, size: 11, color: themedSettingsSecondaryColor())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsInfoRow: View {
    let icon: MonoIcon.IconType
    let title: String
    let value: String
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(icon: icon)

            Text(title)
                .font(developerDiagnosticStyle
                    ? .system(size: 15, weight: .semibold, design: .rounded)
                    : themedSettingsFont(15, weight: .medium))
                .foregroundColor(developerDiagnosticStyle ? .white : themedSettingsPrimaryColor())

            Spacer()

            Text(value)
                .font(themedSettingsFont(14, weight: .regular))
                .foregroundColor(developerDiagnosticStyle
                    ? .white.opacity(0.45)
                    : themedSettingsSecondaryColor())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct SettingsButtonRow: View {
    let icon: MonoIcon.IconType
    let title: String
    var titleColor: Color? = nil
    let action: () -> Void
    @Environment(\.developerDiagnosticStyle) private var developerDiagnosticStyle

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIconBadge(icon: icon)

                Text(title)
                    .font(developerDiagnosticStyle
                        ? .system(size: 15, weight: .semibold, design: .rounded)
                        : themedSettingsFont(15, weight: .medium))
                    .foregroundColor(titleColor
                        ?? (developerDiagnosticStyle ? .white : themedSettingsPrimaryColor()))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}
