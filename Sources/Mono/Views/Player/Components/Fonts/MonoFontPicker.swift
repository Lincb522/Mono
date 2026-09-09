import SwiftUI
import UIKit

enum MonoFontPickerLayout {
    case horizontal
    case grid(columns: Int)
}

/// 导入字体在选择器里的可见范围
enum MonoCustomFontScope {
    /// 全部导入字体
    case all
    /// 仅含中文字形的导入字体（中文歌词字体选择器用，
    /// 纯外语字体自动归到外语字体选择器）
    case cjkCapable
}

struct MonoFontPicker: View {
    @Binding var selectionRaw: String
    @Binding var customFontID: String

    let accent: Color
    var layout: MonoFontPickerLayout = .horizontal
    var includesFollowTheme = false
    var followLabel = String(localized: "跟随主题")
    var customFontScope: MonoCustomFontScope = .all

    @ObservedObject private var fontManager = CustomFontManager.shared
    @State private var showImporter = false
    @State private var showOnlineLibrary = false
    @State private var importError: String?

    private var builtInChoices: [AriaLyricFontChoice] {
        AriaLyricFontChoice.allCases.filter { $0 != .custom }
    }

    private var visibleCustomFonts: [ImportedFontRecord] {
        switch customFontScope {
        case .all:
            return fontManager.fonts
        case .cjkCapable:
            return fontManager.fonts.filter(\.isCJKCapable)
        }
    }

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pickerContent
                    }
                }
            case .grid(let count):
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 7),
                        count: max(2, count)
                    ),
                    spacing: 7
                ) {
                    pickerContent
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: CustomFontManager.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fullScreenCover(isPresented: $showOnlineLibrary) {
            OnlineFontLibraryView(accent: accent) { record in
                customFontID = record.id
                selectionRaw = AriaLyricFontChoice.custom.rawValue
            }
        }
        .alert(
            String(localized: "字体导入失败"),
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button(String(localized: "common_confirm"), role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if includesFollowTheme {
            selectionButton(
                id: MonoPlayerFont.followThemeRawValue,
                name: followLabel,
                previewFont: .system(size: 18, weight: .bold, design: .rounded),
                selected: selectionRaw == MonoPlayerFont.followThemeRawValue
            ) {
                selectionRaw = MonoPlayerFont.followThemeRawValue
            }
        }

        ForEach(builtInChoices, id: \.rawValue) { choice in
            selectionButton(
                id: choice.rawValue,
                name: choice.label,
                previewFont: choice.font(size: 18, weight: .bold),
                selected: selectionRaw == choice.rawValue
            ) {
                selectionRaw = choice.rawValue
            }
        }

        ForEach(visibleCustomFonts) { record in
            selectionButton(
                id: record.id,
                name: record.displayName,
                previewFont: .custom(record.postScriptName, size: 18),
                selected: selectionRaw == AriaLyricFontChoice.custom.rawValue
                    && customFontID == record.id
            ) {
                customFontID = record.id
                selectionRaw = AriaLyricFontChoice.custom.rawValue
            }
            .contextMenu {
                Button(role: .destructive) {
                    fontManager.delete(record)
                } label: {
                    Label(String(localized: "删除字体"), systemImage: "trash")
                }
            }
        }

        onlineButton
        importButton
    }

    private func selectionButton(
        id: String,
        name: String,
        previewFont: Font,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 3) {
                Text("永Aa")
                    .font(previewFont)
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                    .lineLimit(1)

                Text(name)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 0.84 : 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: layoutUsesGrid ? .infinity : nil)
            .frame(width: layoutUsesGrid ? nil : 82, height: 54)
            .padding(.horizontal, layoutUsesGrid ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.1 : 0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected ? accent.opacity(0.62) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(id)
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            VStack(spacing: 4) {
                MonoIcon(icon: .add, size: 16, color: accent)
                Text(String(localized: "导入字体"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: layoutUsesGrid ? .infinity : nil)
            .frame(width: layoutUsesGrid ? nil : 82, height: 54)
            .padding(.horizontal, layoutUsesGrid ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        accent.opacity(0.24),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "导入字体"))
    }

    private var onlineButton: some View {
        Button {
            showOnlineLibrary = true
        } label: {
            VStack(spacing: 4) {
                MonoIcon(icon: .download, size: 16, color: accent)
                Text(String(localized: "在线字体"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: layoutUsesGrid ? .infinity : nil)
            .frame(width: layoutUsesGrid ? nil : 82, height: 54)
            .padding(.horizontal, layoutUsesGrid ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.075))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "在线字体"))
    }

    private var layoutUsesGrid: Bool {
        if case .grid = layout {
            return true
        }
        return false
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let imported = try fontManager.importFonts(from: urls)
                if let first = imported.first {
                    customFontID = first.id
                    selectionRaw = AriaLyricFontChoice.custom.rawValue
                }
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - 外语歌词字体（紧凑单行菜单）

/// 外语歌词字体选择：一行搞定，不再整块重复中文字体选择器。
/// 只列「纯外语字体」（依据字形检测）；想用中文字体就选「复用中文字体」。
struct MonoForeignFontMenuRow: View {
    @Binding var selectionRaw: String
    @Binding var customFontID: String

    let accent: Color
    var reuseLabel = String(localized: "复用中文字体")

    @ObservedObject private var fontManager = CustomFontManager.shared

    /// 外语菜单只保留拉丁字形合适的系统字体，
    /// 泼墨/手书/宋体这类中文装饰字体不进外语列表。
    private var builtInChoices: [AriaLyricFontChoice] {
        [.system, .serif]
    }

    private var latinOnlyFonts: [ImportedFontRecord] {
        fontManager.fonts.filter { !$0.isCJKCapable }
    }

    /// 单值选择：内置字体用 rawValue，导入字体用 "custom:<id>"
    private var combinedSelection: Binding<String> {
        Binding(
            get: {
                selectionRaw == AriaLyricFontChoice.custom.rawValue
                    ? "custom:\(customFontID)"
                    : selectionRaw
            },
            set: { newValue in
                if newValue.hasPrefix("custom:") {
                    customFontID = String(newValue.dropFirst(7))
                    selectionRaw = AriaLyricFontChoice.custom.rawValue
                } else {
                    selectionRaw = newValue
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
    }

    private var currentName: String {
        if selectionRaw == MonoPlayerFont.followThemeRawValue {
            return reuseLabel
        }
        if selectionRaw == AriaLyricFontChoice.custom.rawValue {
            return fontManager.record(withID: customFontID)?.displayName
                ?? String(localized: "自定义字体")
        }
        return (AriaLyricFontChoice(rawValue: selectionRaw) ?? .system).label
    }

    var body: some View {
        Menu {
            Picker("", selection: combinedSelection) {
                Text(reuseLabel).tag(MonoPlayerFont.followThemeRawValue)

                Section(String(localized: "内置字体")) {
                    ForEach(builtInChoices, id: \.rawValue) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }

                if !latinOnlyFonts.isEmpty {
                    Section(String(localized: "导入的外语字体")) {
                        ForEach(latinOnlyFonts) { record in
                            Text(record.displayName).tag("custom:\(record.id)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(String(localized: "外语歌词字体"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer(minLength: 8)

                Text(currentName)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                MonoIcon(icon: .chevronDown, size: 10, color: .white.opacity(0.4), lineWidth: 1.6)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PlayerTypographySettingsView: View {
    @AppStorage("playerDisplayFont") private var selectionRaw = MonoPlayerFont.followThemeRawValue
    @AppStorage("playerCustomFontID") private var customFontID = ""
    @AppStorage("playerFontScale") private var fontScale = 1.0
    @AppStorage("lyricsForceUppercaseEnglish") private var forceUppercaseEnglish = false
    @AppStorage(KaraokeWordStyle.storageKey) private var karaokeStyleRaw = KaraokeWordStyle.defaultStyle.rawValue
    @AppStorage(LyricSource.storageKey) private var defaultLyricSourceRaw = LyricSource.followSongRawValue
    @AppStorage(LyricSource.appleMusicStorageKey) private var appleMusicLyricSourceRaw = LyricSource.netease.rawValue

    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var coverColors = CoverColorExtractor()
    @State private var selectedWorkspace: PlayerTypographyWorkspace = .display

    private var accent: Color {
        normalizedEQAccent(coverColors.dominantColor)
    }

    private var previewFont: Font {
        MonoPlayerFont.font(
            selectionRaw: selectionRaw,
            customFontID: customFontID,
            size: 29 * CGFloat(fontScale),
            weight: .bold,
            fallback: .system(size: 29 * CGFloat(fontScale), weight: .bold, design: .rounded)
        )
    }

    private var selectedFontName: String {
        if selectionRaw == MonoPlayerFont.followThemeRawValue {
            return String(localized: "跟随播放器主题")
        }
        if selectionRaw == AriaLyricFontChoice.custom.rawValue {
            return CustomFontManager.shared.record(withID: customFontID)?.displayName
                ?? String(localized: "自定义字体")
        }
        return (AriaLyricFontChoice(rawValue: selectionRaw) ?? .system).label
    }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                PlayerSettingsWorkspaceBar(
                    selection: $selectedWorkspace,
                    items: PlayerTypographyWorkspace.allCases.map {
                        PlayerSettingsWorkspaceItem(value: $0, title: $0.title, icon: $0.icon)
                    },
                    accent: accent
                )

                workspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        .onAppear {
            coverColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
        }
        .onChange(of: player.currentSong?.id) { _, _ in
            coverColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
        }
        .onChange(of: defaultLyricSourceRaw) { _, newValue in
            guard newValue == LyricSource.followSongRawValue || LyricSource(rawValue: newValue) != nil else {
                defaultLyricSourceRaw = LyricSource.followSongRawValue
                return
            }

            UISelectionFeedbackGenerator().selectionChanged()
            if let song = player.currentSong, !song.isAppleMusic {
                LyricViewModel.shared.useGlobalSource(for: song)
            }
        }
        .onChange(of: appleMusicLyricSourceRaw) { _, newValue in
            guard LyricSource(rawValue: newValue) != nil else {
                appleMusicLyricSourceRaw = LyricSource.netease.rawValue
                return
            }

            UISelectionFeedbackGenerator().selectionChanged()
            if let song = player.currentSong, song.isAppleMusic {
                LyricViewModel.shared.useGlobalSource(for: song)
            }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedWorkspace {
                case .display:
                    lyricSourceSection
                    appleMusicLyricSourceSection
                    behaviorSection
                case .type:
                    preview
                    fontSection
                case .karaoke:
                    karaokeSection
                case .color:
                    lyricColorSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 44)
            .iPadContentWidth(720)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            Text(forceUppercaseEnglish ? "MIDNIGHT RADIO · 春风" : "Midnight Radio · 春风")
                .font(previewFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(selectedFontName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.24), lineWidth: 1)
        }
        .id("\(selectionRaw)|\(customFontID)|\(fontScale)|\(forceUppercaseEnglish)")
    }

    private var fontSection: some View {
        section(title: String(localized: "字体")) {
            VStack(spacing: 14) {
                MonoFontPicker(
                    selectionRaw: $selectionRaw,
                    customFontID: $customFontID,
                    accent: accent,
                    layout: .grid(columns: 3),
                    includesFollowTheme: true
                )

                VStack(spacing: 6) {
                    HStack {
                        controlLabel(String(localized: "字号"))
                        Spacer()
                        Text(String(format: "%.2f×", fontScale))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Slider(value: $fontScale, in: 0.75...1.5)
                        .tint(accent)
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private var lyricSourceSection: some View {
        section(title: String(localized: "lyric_source_default_title")) {
            Picker("", selection: $defaultLyricSourceRaw) {
                Text(String(localized: "lyric_source_automatic")).tag(LyricSource.followSongRawValue)
                ForEach(LyricSource.allCases) { source in
                    Text(source.shortName).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(14)
            .background(cardBackground)
        }
    }

    private var appleMusicLyricSourceSection: some View {
        section(title: String(localized: "apple_music_lyric_source_title")) {
            Picker("", selection: $appleMusicLyricSourceRaw) {
                ForEach(LyricSource.allCases) { source in
                    Text(source.shortName).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(14)
            .background(cardBackground)
        }
    }

    // MARK: - 逐字效果

    private var karaokeSection: some View {
        section(title: String(localized: "逐字效果")) {
            VStack(spacing: 14) {
                KaraokeStylePreviewStrip(
                    style: KaraokeWordStyle.resolve(karaokeStyleRaw),
                    accent: accent
                )

                karaokeStyleGrid
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private var karaokeStyleGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(KaraokeWordStyle.allCases) { style in
                let isSelected = KaraokeWordStyle.resolve(karaokeStyleRaw) == style
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        karaokeStyleRaw = style.rawValue
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(style.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                        Text(style.caption)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.68) : .white.opacity(0.34))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.32) : Color.white.opacity(0.05))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 歌词颜色（由外观设置迁入）

    private var lyricColorSection: some View {
        section(title: String(localized: "settings_lyric_color")) {
            VStack(spacing: 14) {
                Picker("", selection: $settings.lyricColorMode) {
                    Text(String(localized: "settings_lyric_color_mode_default")).tag("default")
                    Text(String(localized: "自动")).tag("auto")
                    Text(String(localized: "settings_lyric_color_mode_solid")).tag("solid")
                    Text(String(localized: "settings_lyric_color_mode_gradient")).tag("gradient")
                }
                .pickerStyle(.segmented)

                if settings.lyricColorMode == "solid" {
                    lyricColorRow(
                        title: String(localized: "settings_lyric_color"),
                        hex: $settings.lyricSolidColorHex
                    )
                }

                if settings.lyricColorMode == "gradient" {
                    lyricColorRow(
                        title: String(localized: "settings_lyric_color_start"),
                        hex: $settings.lyricGradientStartHex
                    )
                    lyricColorRow(
                        title: String(localized: "settings_lyric_color_end"),
                        hex: $settings.lyricGradientEndHex
                    )
                }

                if settings.lyricColorMode != "default" {
                    lyricColorPreview
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func lyricColorRow(title: String, hex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: hex.wrappedValue))
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            controlLabel(title)

            Spacer()

            ColorPicker("", selection: Binding(
                get: { Color(hex: hex.wrappedValue) },
                set: { hex.wrappedValue = $0.toHex() }
            ), supportsOpacity: false)
                .labelsHidden()
        }
    }

    private var lyricColorPreview: some View {
        Group {
            if settings.lyricColorMode == "auto" {
                Text(String(localized: "settings_lyric_preview"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: Array(coverColors.palette.prefix(6)),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            } else if settings.lyricColorMode == "gradient" {
                Text(String(localized: "settings_lyric_preview"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: settings.lyricGradientStartHex),
                                Color(hex: settings.lyricGradientEndHex),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            } else {
                Text(String(localized: "settings_lyric_preview"))
                    .font(.rounded(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: settings.lyricSolidColorHex))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var behaviorSection: some View {
        section(title: String(localized: "歌词显示")) {
            Toggle(isOn: $forceUppercaseEnglish) {
                Text(String(localized: "英文歌词强制大写"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .tint(accent)
            .padding(14)
            .background(cardBackground)
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
            content()
        }
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }

    private var backdrop: some View {
        ZStack {
            PlaylistColorBackground(
                coverUrl: player.currentSong?.coverUrl?.sized(720)
            )
            .saturation(0.78)

            Color.black.opacity(0.48)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.54),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private enum PlayerTypographyWorkspace: String, CaseIterable, Identifiable {
    case display
    case type
    case karaoke
    case color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return String(localized: "显示")
        case .type: return String(localized: "字体")
        case .karaoke: return String(localized: "逐字")
        case .color: return String(localized: "颜色")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .display: return .musicNote
        case .type: return .album
        case .karaoke: return .sparkle
        case .color: return .equalizer
        }
    }
}

struct PlayerSettingsWorkspaceItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let icon: MonoIcon.IconType

    var id: Value { value }
}

struct PlayerSettingsWorkspaceBar<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [PlayerSettingsWorkspaceItem<Value>]
    let accent: Color

    private var foreground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "111821"),
            dark: .white
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = selection == item.value
                Button {
                    guard !isSelected else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        selection = item.value
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 6) {
                        MonoIcon(
                            icon: item.icon,
                            size: 13,
                            color: isSelected ? foreground : .white.opacity(0.46)
                        )
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(isSelected ? foreground : .white.opacity(0.52))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(0.86))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .iPadContentWidth(720)
    }
}
