import PhotosUI
import SwiftUI
import MonoGlyphIcons

struct SettingsAppBrandRow: View {
    let title: String
    let selection: AppBrandStyle
    let appearance: AppBrandAppearance
    @Binding var isExpanded: Bool
    let onSelect: (AppBrandStyle) -> Void
    let onSelectAppearance: (AppBrandAppearance) -> Void

    private var brandPreviewColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 104, maximum: 148), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    SettingsIconBadge(icon: .sparkle)
                        .monoIconArtwork("appBrand")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(appearanceSettingsFont(15, weight: .medium))
                            .foregroundColor(.monoTextPrimary)

                        Text(selectionSummary)
                            .font(appearanceSettingsFont(11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    PetWhiteDisclosureChevron(isExpanded: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDisclosureReveal(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: brandPreviewColumns, spacing: 10) {
                        ForEach(AppBrandStyle.allCases) { style in
                            Button {
                                onSelect(style)
                            } label: {
                                AppBrandOptionCard(
                                    style: style,
                                    appearance: appearance,
                                    isSelected: selection == style
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(AppBrandAppearance.allCases) { item in
                            Button {
                                onSelectAppearance(item)
                            } label: {
                                Text(item.displayName)
                                    .font(appearanceSettingsFont(12, weight: appearance == item ? .semibold : .regular))
                                    .foregroundStyle(appearance == item ? Color.monoIconForeground : Color.monoTextSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(appearance == item ? Color.monoIconBackground : Color.monoSeparator.opacity(0.42))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private var selectionSummary: String {
        let name = selection.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? appearance.displayName : "\(name) · \(appearance.displayName)"
    }
}

struct SettingsInterfaceIconSetRow: View {
    let title: String
    @Binding var selection: AppInterfaceIconSet
    @State private var isExpanded = false
    @AppStorage(AppInterfaceIconSet.zappiconStyleKey) private var zappiconStyleRaw: String = ZappiconIconStyle.light.rawValue
    @AppStorage(AppInterfaceIconSet.solarStyleKey) private var solarStyleRaw: String = SolarIconStyle.line.rawValue
    @AppStorage(AppInterfaceIconSet.monoGlyphStyleKey) private var monoGlyphStyleRaw: String = MonoGlyphIconStyle.classic.rawValue

    private var iconSetPreviewColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118, maximum: 168), spacing: 8)]
    }

    private var zappiconStyle: ZappiconIconStyle {
        ZappiconIconStyle(rawValue: zappiconStyleRaw) ?? .light
    }

    private var solarStyle: SolarIconStyle {
        SolarIconStyle(rawValue: solarStyleRaw) ?? .line
    }

    private var monoGlyphStyle: MonoGlyphIconStyle {
        MonoGlyphIconStyle(rawValue: monoGlyphStyleRaw) ?? .classic
    }

    private var subtitle: String {
        switch selection {
        case .zappicon:
            return "\(selection.displayName) · \(zappiconStyle.displayName)"
        case .solar:
            return "\(selection.displayName) · \(solarStyle.displayName)"
        case .monoGlyph:
            return "\(selection.displayName) · \(monoGlyphStyle.displayName)"
        default:
            return selection.displayName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    SettingsIconBadge(icon: .gridSquare)
                        .monoIconArtwork("interfaceIconSet")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(appearanceSettingsFont(15, weight: .medium))
                            .foregroundColor(.monoTextPrimary)

                        Text(subtitle)
                            .font(appearanceSettingsFont(11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    PetWhiteDisclosureChevron(isExpanded: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDisclosureReveal(isExpanded: isExpanded) {
                VStack(spacing: 10) {
                    LazyVGrid(columns: iconSetPreviewColumns, spacing: 8) {
                        ForEach(AppInterfaceIconSet.allCases) { iconSet in
                            Button {
                                selection = iconSet
                            } label: {
                                InterfaceIconSetOptionCard(
                                    iconSet: iconSet,
                                    isSelected: selection == iconSet,
                                    monoGlyphStyle: monoGlyphStyle
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)

                    // Zappicon 风格选择
                    if selection == .zappicon {
                        IconStylePicker(
                            label: "风格",
                            items: ZappiconIconStyle.allCases,
                            selected: zappiconStyle,
                            onSelect: { style in
                                zappiconStyleRaw = style.rawValue
                                AppInterfaceIconSet.setZappiconStyle(style)
                            }
                        )
                        .padding(.horizontal, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if selection == .monoGlyph {
                        IconStylePicker(
                            label: String(localized: "settings_mono_glyph_style"),
                            items: MonoGlyphIconStyle.allCases,
                            selected: monoGlyphStyle,
                            onSelect: { style in
                                monoGlyphStyleRaw = style.rawValue
                                AppInterfaceIconSet.setMonoGlyphStyle(style)
                            }
                        )
                        .padding(.horizontal, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Solar 风格选择
                    if selection == .solar {
                        IconStylePicker(
                            label: "风格",
                            items: SolarIconStyle.allCases,
                            selected: solarStyle,
                            onSelect: { style in
                                solarStyleRaw = style.rawValue
                                AppInterfaceIconSet.setSolarStyle(style)
                            }
                        )
                        .padding(.horizontal, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
            }
        }
    }
}

/// Shared style picker for icon families with multiple variants.
struct IconStylePicker<Item: Identifiable & CaseIterable & Hashable>: View where Item.AllCases: RandomAccessCollection {
    let label: String
    let items: Item.AllCases
    let selected: Item
    let onSelect: (Item) -> Void
    let displayName: (Item) -> String

    @Environment(\.colorScheme) private var colorScheme

    private var styleColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 66, maximum: 118), spacing: 6)]
    }

    init(label: String, items: Item.AllCases, selected: Item, onSelect: @escaping (Item) -> Void) where Item: RawRepresentable, Item.RawValue == String {
        self.label = label
        self.items = items
        self.selected = selected
        self.onSelect = onSelect
        // 通过协议获取 displayName
        displayName = { item in
            if let z = item as? ZappiconIconStyle { return z.displayName }
            if let s = item as? SolarIconStyle { return s.displayName }
            if let g = item as? MonoGlyphIconStyle { return g.displayName }
            return "\(item)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(appearanceSettingsFont(11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)

            LazyVGrid(columns: styleColumns, spacing: 6) {
                ForEach(Array(items), id: \.self) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        Text(displayName(item))
                            .font(appearanceSettingsFont(11, weight: selected == item ? .bold : .medium))
                            .foregroundColor(selected == item ? .monoTextPrimary : .monoTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if selected == item {
                                    Capsule().fill(Color.monoTextPrimary.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                } else {
                                    Capsule().stroke(Color.monoTextSecondary.opacity(0.3), lineWidth: 0.6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == item ? .isSelected : [])
                }
            }
        }
    }
}

struct InterfaceIconSetOptionCard: View {
    let iconSet: AppInterfaceIconSet
    let isSelected: Bool
    let monoGlyphStyle: MonoGlyphIconStyle
    @Environment(\.colorScheme) private var colorScheme

    private let samples: [MonoIcon.IconType] = [
        .homeFilled,
        .play,
        .profileFilled,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(samples.indices, id: \.self) { index in
                    previewIcon(samples[index])
                }
            }

            HStack(spacing: 6) {
                Text(iconSet.displayName)
                    .font(appearanceSettingsFont(12, weight: .semibold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isSelected {
                    MonoIcon(icon: .checkmark, size: 10, color: checkColor, lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .background(checkBackground, in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(cardStroke, lineWidth: isSelected ? 1.4 : 0.8)
        }
    }

    @ViewBuilder
    private func previewIcon(_ icon: MonoIcon.IconType) -> some View {
        if iconSet.usesOriginalArtwork {
            Image(uiImage: originalArtwork(for: icon))
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: previewIconSize, height: previewIconSize)
                .scaleEffect(originalArtworkScale(for: icon))
                .frame(width: 26, height: 26)
                .background(previewIconBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(uiImage: iconSet.image(for: icon))
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: previewIconSize, height: previewIconSize)
                .foregroundStyle(previewIconColor)
                .frame(width: 26, height: 26)
                .background(previewIconBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func originalArtwork(for icon: MonoIcon.IconType) -> UIImage {
        if iconSet == .monoGlyph {
            return icon.monoGlyphImage(
                assetId: nil,
                prefersLightOutline: colorScheme == .dark,
                style: monoGlyphStyle
            )
        }
        return iconSet.image(for: icon, prefersLightOutline: colorScheme == .dark)
    }

    private var previewIconSize: CGFloat {
        switch iconSet {
        case .doodlePop, .pawPrint, .dotDogSnake, .minimalWhiteIcons, .pulseBloom, .monoGlyph:
            return 18
        case .blobIcons:
            return 17
        case .hicon, .sfSymbols, .zappicon, .lucide, .solar:
            return 15
        }
    }

    private func originalArtworkScale(for icon: MonoIcon.IconType) -> CGFloat {
        switch iconSet {
        case .minimalWhiteIcons:
            return 1.02
        case .pulseBloom, .monoGlyph:
            return 1
        case .doodlePop, .pawPrint, .dotDogSnake:
            switch icon {
            case .karaoke:
                return 1.18
            case .translate:
                return 1.12
            default:
                return 1.08
            }
        case .hicon, .sfSymbols, .zappicon, .lucide, .solar, .blobIcons:
            return 1
        }
    }

    private var previewIconColor: Color {
        if MangaStyle.isActive { return MangaStyle.ink }
        if MujiStyle.isActive { return MujiStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var previewIconBackground: Color {
        if MangaStyle.isActive { return isSelected ? MangaStyle.labelYellow.opacity(0.85) : MangaStyle.paperCool.opacity(0.9) }
        if MujiStyle.isActive { return MujiStyle.surface.opacity(isSelected ? 0.88 : 0.58) }
        if NeumorphicStyle.isActive { return isSelected ? NeumorphicStyle.surfaceRaised : NeumorphicStyle.surfacePressed }
        return isSelected ? Color.monoIconBackground.opacity(0.16) : Color.monoSeparator.opacity(0.35)
    }

    private var titleColor: Color {
        if MangaStyle.isActive { return MangaStyle.ink }
        if MujiStyle.isActive { return MujiStyle.ink }
        if NeumorphicStyle.isActive { return NeumorphicStyle.ink }
        return .monoTextPrimary
    }

    private var checkColor: Color {
        if MangaStyle.isActive { return MangaStyle.strokeInk }
        if MujiStyle.isActive { return MujiStyle.onTint }
        if NeumorphicStyle.isActive { return NeumorphicStyle.accent }
        return .white
    }

    private var checkBackground: Color {
        if MangaStyle.isActive { return MangaStyle.labelYellow }
        if MujiStyle.isActive { return MujiStyle.clay }
        if NeumorphicStyle.isActive { return NeumorphicStyle.surfaceRaised }
        return .monoAccent
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        if MangaStyle.isActive { return isSelected ? MangaStyle.bubbleBlue.opacity(0.38) : MangaStyle.bubbleWhite.opacity(0.72) }
        if MujiStyle.isActive { return isSelected ? MujiStyle.surfaceRaised.opacity(0.82) : MujiStyle.surface.opacity(0.5) }
        if NeumorphicStyle.isActive { return isSelected ? NeumorphicStyle.surfaceRaised.opacity(0.92) : NeumorphicStyle.surface.opacity(0.6) }
        return isSelected ? Color.monoIconBackground.opacity(0.12) : Color.monoSeparator.opacity(0.28)
    }

    private var cardStroke: Color {
        if MangaStyle.isActive { return isSelected ? MangaStyle.strokeInk : MangaStyle.strokeInk.opacity(0.22) }
        if MujiStyle.isActive { return isSelected ? MujiStyle.clay.opacity(0.5) : MujiStyle.hairline.opacity(0.32) }
        if NeumorphicStyle.isActive { return isSelected ? NeumorphicStyle.accent.opacity(0.45) : NeumorphicStyle.separator.opacity(0.32) }
        return isSelected ? Color.monoAccent.opacity(0.42) : Color.clear
    }
}
