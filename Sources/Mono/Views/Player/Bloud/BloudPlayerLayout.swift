import SwiftUI

/// A circular listening companion with a separate transport key and a seek orbit.
/// The track owns its expression; rhythm animates the eyelids, and hand input steers its gaze.
struct BloudPlayerLayout: View {
    var isPresented = true
    @State private var isVisible = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ObservedObject private var playback = FloatingBarPlaybackModel.shared
    @ObservedObject private var songPresentation = CurrentSongPresentationModel.shared
    @ObservedObject private var listening = BloudListeningModel.shared
    @ObservedObject private var likes = LikeManager.shared
    @StateObject private var colors = CoverColorExtractor()
    @StateObject private var handTracker = BloudHandTracker()
    @AppStorage("playerBloudCharacter") private var character: BloudCharacter = .bloud
    @AppStorage("playerBloudCustomColor") private var bloudCustomHex = ""
    @AppStorage("playerPawCatCustomColor") private var catCustomHex = ""
    @AppStorage("playerPawCustomColor") private var pawCustomHex = ""
    @AppStorage("playerBloudCameraHandTracking") private var cameraHandTracking = false
    @AppStorage("playerCharacterFeatureColors") private var featureColorsJSON = "{}"
    @AppStorage("playerCharacterCoverColors") private var coverColorsJSON = "{}"
    @State private var cameraRetry = 0
    @State private var gazePoint: CGPoint?
    @State private var gazeIsTouching = false
    @State private var gazeEvent = 0
    @GestureState private var characterTouch: BloudPawTouch?
    @State private var showsExpressions = false
    @State private var editsColors = true
    @State private var selectedColorPart: BloudColorPart = .body
    @State private var presentedColorPart: BloudColorPart?
    @State private var showsQueue = false
    @State private var showsLyrics = false
    @State private var showsMore = false
    @State private var showsQuality = false
    @State private var showsEQ = false
    @State private var showsTheme = false

    private var song: Song? { songPresentation.currentSong }
    private var customHex: String {
        get {
            switch character {
            case .bloud: bloudCustomHex
            case .paw: pawCustomHex
            case .pawCat: catCustomHex
            }
        }
        nonmutating set {
            switch character {
            case .bloud: bloudCustomHex = newValue
            case .paw: pawCustomHex = newValue
            case .pawCat: catCustomHex = newValue
            }
        }
    }
    private var allFeatureColors: [String: [String: String]] {
        (try? JSONDecoder().decode([String: [String: String]].self, from: Data(featureColorsJSON.utf8))) ?? [:]
    }
    private var featureOverrides: [String: String] { allFeatureColors[character.rawValue] ?? [:] }
    private var followsCover: Bool {
        get { ((try? JSONDecoder().decode([String: Bool].self, from: Data(coverColorsJSON.utf8))) ?? [:])[character.rawValue] ?? false }
        nonmutating set {
            var values = (try? JSONDecoder().decode([String: Bool].self, from: Data(coverColorsJSON.utf8))) ?? [:]
            values[character.rawValue] = newValue
            if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) { coverColorsJSON = json }
        }
    }
    private func setColor(_ part: BloudColorPart, hex: String?) {
        if part == .body { customHex = hex ?? ""; return }
        var values = allFeatureColors
        var selected = featureOverrides
        selected[part.rawValue] = hex
        values[character.rawValue] = selected
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) { featureColorsJSON = json }
    }
    private func partColor(_ part: BloudColorPart) -> Color {
        switch part {
        case .body: palette.body
        case .eyes: palette.eyes
        default: palette.features[part]
        }
    }
    private var palette: BloudPalette {
        BloudPalette(character: character, customHex: customHex, dark: colorScheme == .dark, coverAccent: colors.dominantColor, followsCover: followsCover, overrides: featureOverrides)
    }
    private var ink: Color { palette.ink }
    private var paper: Color { palette.paper }
    private var accent: Color { palette.accent }
    private var menuPalette: MonoMoreMenuPalette {
        MonoMoreMenuPalette(text: ink, secondary: palette.secondary, surface: paper,
                            accent: accent, onAccent: palette.onAccent)
    }
    private var controlFill: Color { character == .bloud && customHex.isEmpty && !followsCover ? ink : palette.accent }
    private var controlInk: Color { character == .bloud && customHex.isEmpty && !followsCover ? paper : palette.onAccent }
    private var expression: BloudExpression { listening.expression(for: song) }
    private var pawExpression: PawExpression { character == .pawCat ? listening.catExpression(for: song) : listening.pawExpression(for: song) }
    private var followsSong: Bool {
        switch character {
        case .bloud: listening.manualExpression == nil
        case .paw: listening.manualPawExpression == nil
        case .pawCat: listening.manualCatExpression == nil
        }
    }
    private var unobscured: Bool {
        !showsExpressions && !showsQueue && !showsLyrics && !showsMore && !showsQuality && !showsEQ && !showsTheme
            && !likes.showPlaylistPicker
    }
    private var active: Bool { isPresented && isVisible && scenePhase == .active && unobscured }
    private var shouldTrackHands: Bool {
        cameraHandTracking && handTracker.isAuthorized && active
    }
    private var cameraRequest: String { "\(shouldTrackHands)|\(cameraRetry)" }
    private var metadataRequest: [String] { [song?.identityKey ?? "none"] + (song?.genreTags ?? []) }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 660 && proxy.size.width > proxy.size.height && !dynamicType.isAccessibilitySize
            let diameter = min(wide ? proxy.size.height - 84 : proxy.size.width - 40, 420)
            let cameraPoint = shouldTrackHands ? handTracker.point : nil
            VStack(spacing: 0) {
                toolbar
                ScrollView(showsIndicators: false) {
                    if wide {
                        HStack(spacing: 36) {
                            companion(diameter: max(210, diameter), cameraPoint: cameraPoint)
                            trackDetails
                                .frame(maxWidth: 360)
                        }
                        .frame(maxWidth: 940)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 22) {
                            companion(diameter: max(220, diameter), cameraPoint: cameraPoint)
                            trackDetails
                                .frame(maxWidth: 460)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, proxy.size.height - 84), alignment: .center)
                        .padding(.bottom, 20)
                    }
                }
                .scrollDisabled(characterTouch != nil)
                .padding(.horizontal, 20)
            }
            .background(paper.ignoresSafeArea())
            .background {
                BloudTouchObserver(isEnabled: active,
                                   onOrientation: { handTracker.updateOrientation($0) }) { location, pressed in
                    gazePoint = location
                    if gazeIsTouching != pressed {
                        gazeIsTouching = pressed
                        gazeEvent += 1
                    }
                }
            }
            .coordinateSpace(name: "bloudPlayer")
            .playerMoreMenuOverlay { anchor in
                if showsMore {
                    PlayerMoreMenu(isPresented: $showsMore, anchorFrame: anchor,
                                   isDarkBackground: colorScheme == .dark,
                                   onQuality: { showsQuality = true }, onEQ: { showsEQ = true },
                                   onTheme: { showsTheme = true }, bloudGazeControl: gazeMenuControl, palette: menuPalette)
                }
            }
        }
        .foregroundStyle(ink)
        .tint(accent)
        .task(id: cameraHandTracking && active) {
            if cameraHandTracking && active { await handTracker.requestAuthorization() }
        }
        .task(id: cameraRequest) { await handTracker.track(active: shouldTrackHands) }
        .task(id: metadataRequest) { await listening.prepare(song: song) }
        .task(id: gazeEvent) {
            guard !gazeIsTouching else { return }
            do { try await Task.sleep(nanoseconds: 900_000_000) } catch { return }
            gazePoint = nil
        }
        .onAppear {
            isVisible = true
            refreshPalette()
        }
        .onDisappear {
            isVisible = false
            suspendTracking()
        }
        .onChange(of: active) { _, visible in
            if !visible { suspendTracking() }
        }
        .onChange(of: song?.coverUrl?.absoluteString) { _, _ in refreshPalette() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handTracker.refreshAuthorization() }
            if phase != .active {
                gazeIsTouching = false
                gazePoint = nil
            }
        }
        .monoSheet(isPresented: $likes.showPlaylistPicker, preset: .standard) {
            if let pendingSong = likes.pendingLikeSong { AddToPlaylistSheet(song: pendingSong) }
        }
        .monoSheet(isPresented: $showsExpressions, preset: .custom(height: .maximumRatio(0.92), maxContentWidth: 720)) { expressionPicker }
        .monoSheet(isPresented: $showsQueue, preset: .standard) { PlaylistPopupView() }
        .monoSheet(isPresented: $showsTheme, preset: .themePicker) { PlayerThemePickerSheet() }
        .monoSheet(isPresented: $showsQuality, preset: .standard) { qualitySheet }
        .fullScreenCover(isPresented: $showsEQ) { NavigationStack { MonoAudioCenterView() } }
        .fullScreenCover(isPresented: $showsLyrics) {
            if let song {
                LyricsView(song: song) { showsLyrics = false }
                    .background(paper.ignoresSafeArea())
            }
        }
    }

    private func suspendTracking() {
        handTracker.stop()
        gazeIsTouching = false
        gazePoint = nil
        gazeEvent += 1
    }

    private var toolbar: some View {
        HStack {
            iconButton(.chevronDown, label: String(localized: "收起")) {
                isVisible = false
                suspendTracking()
                dismiss()
            }
            Spacer()
            Text(character.title)
                .font(.system(.title3, design: .rounded, weight: .heavy))
            Spacer()
            iconButton(.more, label: String(localized: "更多")) { showsMore = true }
                .playerMoreMenuAnchor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func companion(diameter: CGFloat, cameraPoint: CGPoint?) -> some View {
        ZStack {
            BloudCharacterView(expression: expression, character: character, isAnimating: active,
                               bodyColor: palette.body, eyeColor: palette.eyes, featureColors: palette.features,
                               samplesAudio: playback.isPlaying && !playback.isLoading && song != nil && song?.isAppleMusic != true,
                               gazePoint: gazeIsTouching || cameraPoint == nil ? gazePoint : nil,
                               cameraGaze: gazeIsTouching ? nil : cameraPoint,
                               pawTouch: character.isAnimal ? characterTouch : nil, pawExpression: pawExpression)
                .padding(44)
                .id((song?.identityKey ?? "none") + character.rawValue)
            BloudProgressOrbit(ink: ink, accent: accent, enabled: song != nil)
                .id(song?.identityKey)
            // Direct character coordinates drive PAW contact and gaze even if the window
            // observer yields to this gesture. GestureState also releases on cancellation.
            Color.clear
                .frame(width: diameter - 88, height: diameter - 88)
                .contentShape(Circle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($characterTouch) { value, touch, _ in
                            let half = max(1, (diameter - 88) / 2)
                            touch = BloudPawTouch(
                                origin: SIMD2(Double((value.startLocation.x - half) / half),
                                              Double((value.startLocation.y - half) / half)),
                                location: SIMD2(Double((value.location.x - half) / half),
                                                Double((value.location.y - half) / half)),
                                translation: SIMD2(Double(value.translation.width / half),
                                                   Double(value.translation.height / half))
                            )
                        }
                )
                .allowsHitTesting(scenePhase == .active && unobscured)
                .accessibilityHidden(true)
        }
        .frame(width: diameter, height: diameter)
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(song?.name ?? String(localized: "player_bloud_empty"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let song {
                    Text(song.artistName)
                        .font(.body)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                BloudTrackTime(ink: ink, secondary: palette.secondary)
                Spacer(minLength: 8)
                BloudLikeButton(song: song, ink: ink)
            }
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    playControl
                    skipControls
                }
            } else {
                HStack(spacing: 14) {
                    playControl
                    Spacer(minLength: 0)
                    skipControls
                }
            }
            HStack(spacing: 18) { secondaryActions }
        }
        .padding(.horizontal, 6)
    }

    private var playControl: some View {
        Button { playback.togglePlayPause() } label: {
            HStack(spacing: 10) {
                if playback.isLoading {
                    ProgressView().tint(controlInk)
                } else {
                    MonoIcon(icon: playback.isPlaying ? .pause : .play, size: 22, color: controlInk)
                        .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
                }
                Text(playback.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .foregroundStyle(controlInk)
            .background(controlFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(song == nil)
        .opacity(song == nil ? 0.4 : 1)
    }

    private var skipControls: some View {
        HStack(spacing: 10) {
            iconButton(.previous, label: String(localized: "上一首")) { playback.previous() }
            iconButton(.next, label: String(localized: "playback_next_track")) { playback.next() }
        }
        .disabled(song == nil)
    }

    @ViewBuilder private var secondaryActions: some View {
        Button { showsExpressions = true } label: {
            BloudCharacterView(expression: .attentive, character: character, isAnimating: false,
                               bodyColor: palette.body, eyeColor: palette.eyes, featureColors: palette.features, pawExpression: .listening)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("player_bloud_companion"))
        iconButton(.musicNoteList, label: String(localized: "歌词")) { showsLyrics = true }
            .disabled(song == nil)
        iconButton(.list, label: String(localized: "player_queue")) { showsQueue = true }
        BloudPlaybackModeButton(ink: ink)
            .disabled(song == nil)
    }

    private func iconButton(_ icon: MonoIcon.IconType, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MonoIcon(icon: icon, size: 21, color: ink)
                .frame(width: 48, height: 48).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var gazeMenuControl: BloudGazeMenuControl {
        BloudGazeMenuControl(isEnabled: $cameraHandTracking,
                            needsSettings: handTracker.needsSettings,
                            failure: handTracker.failure, palette: menuPalette) {
            showsMore = false
            if handTracker.needsSettings {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } else {
                cameraRetry += 1
            }
        }
    }

    private var expressionPicker: some View {
      NavigationStack {
        GeometryReader { sheet in
          VStack(spacing: 0) {
            Picker("player_bloud_character", selection: $character) {
              ForEach(BloudCharacter.allCases) { option in
                Text(option.title).tag(option)
              }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            BloudCharacterView(
              expression: expression, character: character,
              isAnimating: showsExpressions && scenePhase == .active,
              bodyColor: palette.body, eyeColor: palette.eyes, featureColors: palette.features,
              pawExpression: pawExpression
            )
            .frame(height: min(144, max(64, sheet.size.height * 0.23)))
            .padding(.vertical, 8)
            .accessibilityHidden(true)
            Picker("player_character_editor", selection: $editsColors) {
              Text("player_character_colors").tag(true)
              Text("player_bloud_follow_song").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            ScrollView {
              VStack(spacing: 18) {
                if editsColors {
                  appearanceControls
                } else {
                Button {
                  if character == .pawCat {
                    listening.selectCat(nil, for: song)
                  } else if character == .paw {
                    listening.selectPaw(nil, for: song)
                  } else {
                    listening.select(nil, for: song)
                  }
                } label: {
                  HStack {
                    Text("player_bloud_follow_song")
                    Spacer()
                    if followsSong { MonoIcon(icon: .checkmark, size: 18, color: ink) }
                  }.padding(16)
                }
                LazyVGrid(
                  columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 128 : 84))],
                  spacing: 18
                ) {
                  if character.isAnimal {
                    ForEach(PawExpression.allCases) { item in
                      expressionChoice(
                        title: item.title, selected: pawExpression == item,
                        face: BloudCharacterView(
                          character: character, isAnimating: false,
                          bodyColor: palette.body, eyeColor: palette.eyes,
                          featureColors: palette.features, pawExpression: item)
                      ) {
                        if character == .pawCat {
                          listening.selectCat(item, for: song)
                        } else {
                          listening.selectPaw(item, for: song)
                        }
                      }
                    }
                  } else {
                    ForEach(BloudExpression.allCases) { item in
                      expressionChoice(
                        title: item.title, selected: expression == item,
                        face: BloudCharacterView(
                          expression: item, isAnimating: false,
                          bodyColor: palette.body, eyeColor: palette.eyes,
                          featureColors: palette.features)
                      ) {
                        listening.select(item, for: song)
                      }
                    }
                  }
                }
                }
              }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .id(character)
          }
          .background(paper.ignoresSafeArea())
          .foregroundStyle(ink)
          .tint(accent)
          .toolbarBackground(paper, for: .navigationBar)
          .toolbarBackground(.visible, for: .navigationBar)
          .navigationTitle(String(localized: "player_bloud_companion"))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button(String(localized: "完成")) { showsExpressions = false }
            }
          }
        }
      }
      .sheet(item: $presentedColorPart) { part in
          BloudColorEditor(title: part.title, selection: Binding(
              get: { partColor(part) },
              set: { setColor(part, hex: $0.toHex()) }
          ))
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
          .preferredColorScheme(colorScheme)
      }
      .preferredColorScheme(colorScheme)
      .toolbarColorScheme(colorScheme, for: .navigationBar)
      .monoSheetSurface(id: "bloud-character-" + character.rawValue + "-" + paper.toHex()) { paper }
    }

    private func expressionChoice(title: String, selected: Bool, face: BloudCharacterView,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                face.frame(height: 76).accessibilityHidden(true)
                Text(title).font(.caption)
                MonoIcon(icon: .checkmark, size: 14, color: ink).opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var editingColorPart: BloudColorPart {
        BloudColorPart.parts(for: character).contains(selectedColorPart) ? selectedColorPart : .body
    }

    private var appearanceControls: some View {
        VStack(spacing: 16) {
            Toggle("player_color_cover", isOn: Binding(get: { followsCover }, set: { followsCover = $0 }))
                .font(.subheadline)
                .frame(minHeight: 44)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 112 : 72), spacing: 8)], spacing: 8) {
                ForEach(BloudColorPart.parts(for: character)) { part in
                    Button { selectedColorPart = part } label: {
                        VStack(spacing: 7) {
                            Circle()
                                .fill(partColor(part))
                                .frame(width: 32, height: 32)
                                .overlay { Circle().strokeBorder(ink.opacity(colorScheme == .dark ? 0.38 : 0.18), lineWidth: 1) }
                                .padding(4)
                                .overlay {
                                    Circle().strokeBorder(ink, lineWidth: 2)
                                        .opacity(editingColorPart == part ? 1 : 0)
                                }
                            Text(part.title)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .top)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(part.title))
                    .accessibilityAddTraits(editingColorPart == part ? .isSelected : [])
                }
            }
            HStack(spacing: 12) {
                Button { presentedColorPart = editingColorPart } label: {
                    HStack {
                        Text(editingColorPart.title).font(.subheadline.weight(.medium))
                        Spacer()
                        Circle()
                            .fill(partColor(editingColorPart))
                            .frame(width: 28, height: 28)
                            .overlay { Circle().strokeBorder(ink.opacity(0.3), lineWidth: 1) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button("player_color_reset") { setColor(editingColorPart, hex: nil) }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .disabled(editingColorPart == .body ? customHex.isEmpty : featureOverrides[editingColorPart.rawValue] == nil)
                    .accessibilityLabel(Text(String(format: String(localized: "player_color_reset_part"), editingColorPart.title)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ink.opacity(colorScheme == .dark ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 16))
            .disabled(followsCover)
        }
    }

    private func refreshPalette() {
        colors.extract(from: song?.coverUrl?.sized(200).absoluteString)
    }

    private var qualitySheet: some View {
        let player = PlayerManager.shared
        return SoundQualitySheet(
            currentQuality: player.soundQuality, currentQQQuality: player.qqMusicQuality,
            isQQMusic: song?.isQQMusic == true,
            onSelectNetease: { player.switchQuality($0); showsQuality = false },
            onSelectQQ: { player.switchQQMusicQuality($0); showsQuality = false },
            songMid: song?.qqMid, songId: song?.id, isQishui: song?.isQishui == true,
            qishuiTrackId: song?.qishuiTrackId,
            onSelectQishui: { player.switchQishuiQuality($0); showsQuality = false }
        )
    }
}

private struct BloudPlaybackModeButton: View {
    let ink: Color
    @ObservedObject private var player = PlayerManager.shared

    var body: some View {
        Button { player.switchMode() } label: {
            MonoIcon(icon: player.mode.monoIcon, size: 21, color: ink)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(player.mode.displayName))
    }
}
