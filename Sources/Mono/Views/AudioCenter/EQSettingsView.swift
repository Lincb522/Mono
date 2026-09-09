// 均衡器设置界面

import SwiftUI
import FFmpegSwiftSDK

@MainActor
struct EQSettingsView: View {
    private let isEmbedded: Bool
    @StateObject private var eqManager = EQManager.shared
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var coverColors = CoverColorExtractor()
    @Environment(\.monoSoundCenterLayout) private var centerLayout
    @State private var showSaveSheet = false
    @State private var customPresetName = ""
    @State private var isCustomEditingEnabled = false
    @State private var selectedWorkspace: EQSettingsWorkspace = .presets
    @Namespace private var workspaceSelectionNamespace

    init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }
    
    // 音效旋钮值（0~1 范围）
    @State private var bassValue: CGFloat = 0.5
    @State private var trebleValue: CGFloat = 0.5
    @State private var surroundValue: CGFloat = 0.0
    @State private var reverbValue: CGFloat = 0.0
    @State private var stereoWidthValue: CGFloat = 1.0
    
    // 变调（半音数，-12 ~ +12）
    @State private var pitchValue: Float = 0
    
    private var displayGains: [Float] {
        if let preset = eqManager.currentPreset, preset.id != "custom" {
            return preset.gains(in: eqManager.graphicEQMode)
        }
        return eqManager.customGains
    }

    private var eqAccent: Color {
        normalizedEQAccent(coverColors.dominantColor)
    }

    private var eqAccentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: eqAccent,
            light: Color(hex: "111821"),
            dark: .white
        )
    }

    private var eqPrimaryText: Color {
        .white
    }

    private var eqSecondaryText: Color {
        .white.opacity(0.5)
    }

    private var eqMutedText: Color {
        .white.opacity(0.38)
    }

    private var eqSeparator: Color {
        .white.opacity(0.07)
    }

    private var eqPressedSurface: Color {
        .white.opacity(0.06)
    }

    private var displayedPresetName: String {
        guard eqManager.isEnabled else {
            return NSLocalizedString("eq_original_output", comment: "")
        }
        guard !eqManager.isAIManagedPresetActive else {
            return NSLocalizedString("eq_custom", comment: "")
        }
        return eqManager.currentPreset?.name ?? NSLocalizedString("eq_custom", comment: "")
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        presentationRoot
        .monoSheet(
            isPresented: $showSaveSheet,
            preset: .custom(height: .fixed(280), maxContentWidth: 520, showsHandle: false)
        ) {
            savePresetSheet
        }
        .onAppear {
            syncKnobsFromGains()
            syncSelectedPresetCategory()
            refreshCoverAccent()
        }
        .onChange(of: player.currentSong?.id) { _, _ in refreshCoverAccent() }
        .onChange(of: eqManager.isEnabled) {
            // 当均衡器关闭时，同步 UI 旋钮到重置状态
            if !eqManager.isEnabled {
                selectedWorkspace = .presets
                syncKnobsFromGains()
            }
        }
        .onChange(of: eqManager.currentPreset?.id) {
            // 当预设变化时，同步旋钮（环绕预设会自动设置环绕参数）
            if eqManager.currentPreset?.id != "custom" {
                isCustomEditingEnabled = false
            }
            syncKnobsFromGains()
            syncSelectedPresetCategory()
        }
        .animation(.easeOut(duration: 0.2), value: eqManager.isEnabled)
    }

    private var presentationRoot: AnyView {
        if isEmbedded {
            return AnyView(
                VStack(spacing: 0) {
                    workspaceSwitcher
                    workspaceContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .compatFontDesign(nil)
                .environment(\.colorScheme, .dark)
            )
        }

        return AnyView(MonoAudioCenterView(initialWorkspace: .custom))
    }

    private var workspaceSwitcher: some View {
        HStack(spacing: 12) {
            ForEach(EQSettingsWorkspace.allCases) { workspace in
                let isAvailable = eqManager.isEnabled || workspace == .presets
                Button {
                    guard isAvailable else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedWorkspace = workspace
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 5) {
                            MonoIcon(
                                icon: workspace.icon,
                                size: centerLayout.isCompactWidth ? 10.5 : 12,
                                color: selectedWorkspace == workspace
                                    ? eqAccent
                                    : .white.opacity(isAvailable ? 0.38 : 0.18)
                            )
                            Text(workspace.title)
                                .font(.system(size: centerLayout.isCompactWidth ? 10 : 11.5, weight: .bold))
                                .foregroundStyle(
                                    selectedWorkspace == workspace
                                        ? .white.opacity(0.94)
                                        : .white.opacity(isAvailable ? 0.46 : 0.22)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        Capsule()
                            .fill(selectedWorkspace == workspace ? eqAccent : .clear)
                            .frame(height: 2)
                            .matchedGeometryEffect(
                                id: "eq-workspace-selection",
                                in: workspaceSelectionNamespace,
                                isSource: selectedWorkspace == workspace
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: centerLayout.isCompactHeight ? 34 : 40, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .accessibilityAddTraits(selectedWorkspace == workspace ? .isSelected : [])
            }
        }
        .padding(.horizontal, centerLayout.horizontalInset)
        .padding(.bottom, centerLayout.isCompactHeight ? 7 : 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.065))
                .frame(height: 1)
        }
        .frame(maxWidth: centerLayout.workspaceMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var workspaceContent: AnyView {
        switch selectedWorkspace {
        case .presets:
            return presetsWorkspace
        case .equalizer:
            return equalizerWorkspace
        case .effects:
            return effectsWorkspace
        case .calibration:
            return calibrationWorkspace
        }
    }

    private var presetsWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    controlDeck
                    if eqManager.isEnabled {
                        presetScrollSection
                        if !eqManager.customPresets.isEmpty {
                            customPresetsSection
                        }
                    }
                }
            )
        )
    }

    private var equalizerWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    equalizerSection
                    saveButton
                }
            )
        )
    }

    private var effectsWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    knobSection
                    pitchSection
                }
            )
        )
    }

    private var calibrationWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    calibrationSection
                }
            )
        )
    }

    private func workspaceScroll(_ content: AnyView) -> AnyView {
        AnyView(
            ScrollView(showsIndicators: false) {
                content
                    .padding(.horizontal, centerLayout.horizontalInset)
                    .padding(.bottom, centerLayout.isCompactHeight ? 28 : 44)
                    .frame(maxWidth: centerLayout.workspaceMaxWidth)
                    .frame(maxWidth: .infinity)
            }
        )
    }

    private var calibrationSection: some View {
        section(title: String(localized: "eq_mono_calibration")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "eq_preamp"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(eqPrimaryText)
                    Spacer()
                    Text(String(format: "%.1f dB", eqManager.preampDB))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(eqManager.preampDB < -0.05 ? eqAccent : eqSecondaryText)
                }

                effectDivider

                compactCalibrationToggle(
                    title: "eq_loudness_matching",
                    subtitle: "eq_loudness_matching_desc",
                    isOn: $eqManager.isLoudnessMatchingEnabled
                )

                effectDivider

                compactCalibrationToggle(
                    title: "eq_smart_song",
                    subtitle: "eq_smart_song_desc",
                    isOn: $eqManager.isSmartSongCompensationEnabled
                )

                effectDivider

                NavigationLink {
                    EQProfessionalSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey("eq_professional_mode"))
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(eqPrimaryText)
                            Text(eqManager.currentOutputName.isEmpty ? eqManager.currentOutputKind.title : eqManager.currentOutputName)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(eqSecondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        MonoIcon(icon: .chevronRight, size: 13, color: eqMutedText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func compactCalibrationToggle(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.rounded(size: 14.5, weight: .semibold))
                    .foregroundColor(eqPrimaryText)
                Text(subtitle)
                    .font(.rounded(size: 11.5, weight: .medium))
                    .foregroundColor(eqSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(eqAccent)
        }
    }

    // MARK: - 主控制台

    private var controlDeck: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MonoIcon(
                    icon: .equalizer,
                    size: centerLayout.isCompactHeight ? 17 : 20,
                    color: eqManager.isEnabled ? eqAccent : eqSecondaryText
                )
                .frame(
                    width: centerLayout.isCompactHeight ? 38 : 44,
                    height: centerLayout.isCompactHeight ? 38 : 44
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(eqManager.isEnabled ? eqAccent.opacity(0.13) : eqPressedSurface.opacity(0.55))
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("eq_toggle_title"))
                        .font(.system(size: centerLayout.isCompactHeight ? 16 : 18, weight: .bold, design: .rounded))
                        .foregroundColor(eqPrimaryText)
                    Text(displayedPresetName)
                        .font(.rounded(size: 12, weight: .medium))
                        .foregroundColor(eqSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if eqManager.isEnabled {
                    Button(action: resetAll) {
                        Text(String(localized: "eq_reset"))
                            .font(.rounded(size: 12, weight: .semibold))
                            .foregroundStyle(eqSecondaryText)
                            .padding(.horizontal, 10)
                            .frame(height: centerLayout.isCompactHeight ? 28 : 32)
                            .background(
                                Capsule()
                                    .fill(eqPressedSurface)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Toggle("", isOn: $eqManager.isEnabled)
                    .labelsHidden()
                    .tint(eqAccent)
                    .controlSize(centerLayout.isCompactHeight ? .mini : .regular)
            }
            .padding(centerLayout.isCompactHeight ? 12 : 16)

        }
        .background(cardBackground)
    }

    // MARK: - 音效旋钮区

    private var knobSection: some View {
        section(title: String(localized: "eq_effects")) {
            VStack(alignment: .leading, spacing: 14) {
                effectSlider(
                label: NSLocalizedString("eq_bass", comment: ""),
                value: $bassValue,
                range: 0...1,
                valueText: String(format: "%+.1f dB", Float(bassValue) * 24 - 12),
                onChange: applyBassKnob
                )
                effectDivider
                effectSlider(
                label: NSLocalizedString("eq_treble", comment: ""),
                value: $trebleValue,
                range: 0...1,
                valueText: String(format: "%+.1f dB", Float(trebleValue) * 24 - 12),
                onChange: applyTrebleKnob
                )
                effectDivider
                effectSlider(
                label: NSLocalizedString("eq_surround", comment: ""),
                value: $surroundValue,
                range: 0...1,
                valueText: "\(Int(surroundValue * 100))%",
                onChange: applySurroundKnob
                )
                effectDivider
                effectSlider(
                label: NSLocalizedString("eq_reverb", comment: ""),
                value: $reverbValue,
                range: 0...1,
                valueText: "\(Int(reverbValue * 100))%",
                onChange: applyReverbKnob
                )
                effectDivider
                effectSlider(
                label: String(localized: "ai_lab_stereo_width"),
                value: $stereoWidthValue,
                range: 0...2,
                valueText: String(format: "%.2fx", stereoWidthValue),
                onChange: applyStereoWidth
                )
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func effectSlider(
        label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        valueText: String,
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.rounded(size: 13.5, weight: .semibold))
                    .foregroundColor(eqPrimaryText)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(eqSecondaryText)
            }

            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: {
                        value.wrappedValue = $0
                        onChange($0)
                    }
                ),
                in: range
            )
            .tint(eqAccent)
        }
    }

    private var effectDivider: some View {
        Divider().overlay(eqSeparator).opacity(0.5)
    }

    // MARK: - 变调控制

    private var pitchSection: some View {
        section(title: String(localized: "eq_pitch")) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Text(pitchDisplayText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(pitchValue == 0 ? eqSecondaryText : eqAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                pitchValue == 0
                                    ? eqPressedSurface
                                    : eqAccent.opacity(0.12)
                            )
                        )
                        .fixedSize()
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("-12")
                        Spacer()
                        Text("0")
                        Spacer()
                        Text("+12")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(eqMutedText.opacity(0.7))

                    GeometryReader { geo in
                        let width = geo.size.width
                        let normalized = CGFloat((pitchValue + 12) / 24)
                        let centerX = width * 0.5
                        let thumbX = width * normalized

                        ZStack(alignment: .leading) {
                            Capsule().fill(eqSeparator).frame(height: 4)

                            Rectangle()
                                .fill(eqMutedText.opacity(0.38))
                                .frame(width: 2, height: 12)
                                .position(x: centerX, y: geo.size.height / 2)

                            let barStart = min(centerX, thumbX)
                            let barWidth = abs(thumbX - centerX)
                            if barWidth > 1 {
                                Capsule()
                                    .fill(eqAccent.opacity(0.66))
                                    .frame(width: barWidth, height: 4)
                                    .offset(x: barStart)
                            }

                            Circle()
                                .fill(eqAccent)
                                .frame(width: 20, height: 20)
                                .shadow(color: eqAccent.opacity(0.3), radius: 4, y: 2)
                                .position(x: thumbX, y: geo.size.height / 2)
                        }
                        .contentShape(Rectangle().inset(by: -12))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let ratio = min(max(value.location.x / width, 0), 1)
                                    let snapped = roundf(Float(ratio) * 24 - 12)
                                    pitchValue = snapped
                                    PlayerManager.shared.setPitch(snapped)
                                }
                        )
                    }
                    .frame(height: 28)

                    HStack(spacing: 8) {
                        ForEach([-3, -1, 0, 1, 3], id: \.self) { semitone in
                            let value = Float(semitone)
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    pitchValue = value
                                    PlayerManager.shared.setPitch(value)
                                }
                            } label: {
                                Text(semitone > 0 ? "+\(semitone)" : "\(semitone)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(pitchValue == value ? eqAccentForeground : eqSecondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background {
                                        if pitchValue == value {
                                            Capsule().fill(eqAccent)
                                        } else {
                                            Capsule().fill(Color.white.opacity(0.045))
                                                .overlay(Capsule().strokeBorder(eqSeparator, lineWidth: 1))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private var pitchDisplayText: String {
        let v = Int(pitchValue)
        if v == 0 { return NSLocalizedString("eq_original_key", comment: "") }
        return String(format: NSLocalizedString("eq_semitone", comment: ""), v > 0 ? "+\(v)" : "\(v)")
    }

    // MARK: - 均衡器区域（曲线 + 滑块合一）

    private var equalizerSection: some View {
        section(title: String(localized: "eq_equalizer")) {
            VStack(spacing: 12) {
                graphicModePicker
                customEditingToggle

                if eqManager.graphicEQMode == .thirtyTwoBand {
                    ScrollView(.horizontal, showsIndicators: false) {
                        equalizerGraph
                            .frame(width: 896)
                    }
                } else {
                    equalizerGraph
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private var graphicModePicker: some View {
        HStack(spacing: 4) {
            graphicModeButton(.tenBand, title: String(localized: "eq_ten_band"))
            graphicModeButton(.thirtyTwoBand, title: String(localized: "eq_thirty_two_band"))
        }
        .padding(4)
        .background(eqPressedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var customEditingToggle: some View {
        HStack(spacing: 10) {
            MonoIcon(
                icon: isCustomEditingEnabled ? .unlock : .lock,
                size: 14,
                color: isCustomEditingEnabled ? eqAccent : eqMutedText
            )

            Text(String(localized: "eq_custom"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(eqPrimaryText)

            Spacer()

            Toggle(String(localized: "eq_custom"), isOn: customEditingBinding)
                .labelsHidden()
                .tint(eqAccent)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }

    private var customEditingBinding: Binding<Bool> {
        Binding(
            get: { isCustomEditingEnabled },
            set: { enabled in
                withAnimation(.easeOut(duration: 0.18)) {
                    if enabled {
                        switchToCustomIfNeeded()
                    }
                    isCustomEditingEnabled = enabled
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
    }

    private func graphicModeButton(_ mode: GraphicEQMode, title: String) -> some View {
        let isSelected = eqManager.graphicEQMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCustomEditingEnabled = false
                eqManager.setGraphicEQMode(mode)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? eqAccentForeground : eqSecondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? eqAccent : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var equalizerGraph: some View {
        let graphHeight: CGFloat = centerLayout.isCompactHeight ? 170 : 220

        return VStack(spacing: 12) {
            // 曲线 + 滑块叠加
            ZStack(alignment: .bottom) {
                // 频谱曲线填充
                spectrumFill
                    .frame(height: graphHeight)

                // dB 参考标签
                VStack {
                    Text("+12")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("-12")
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(eqMutedText.opacity(0.55))
                .padding(.vertical, 2)
                .frame(height: graphHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

                // 垂直滑块
                sliderOverlay
                    .frame(height: graphHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            frequencyLabels
        }
    }

    // 频谱曲线填充（渐变）
    private var spectrumFill: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let gains = displayGains
            let count = gains.count
            let divisor = max(count - 1, 1)
            let points = gains.enumerated().map { (i, gain) -> CGPoint in
                let x = w * CGFloat(i) / CGFloat(divisor)
                let y = h * (1 - CGFloat((gain + 12) / 24))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // 水平参考线
                ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                    Path { path in
                        let y = h * CGFloat(ratio)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(eqSeparator, lineWidth: 0.5)
                }

                if points.count >= 2 {
                    // 填充区域
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            let prev = points[i - 1]
                            let curr = points[i]
                            let midX = (prev.x + curr.x) / 2
                            path.addCurve(to: curr,
                                          control1: CGPoint(x: midX, y: prev.y),
                                          control2: CGPoint(x: midX, y: curr.y))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(eqAccent.opacity(0.11))

                    // 曲线描边
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            let prev = points[i - 1]
                            let curr = points[i]
                            let midX = (prev.x + curr.x) / 2
                            path.addCurve(to: curr,
                                          control1: CGPoint(x: midX, y: prev.y),
                                          control2: CGPoint(x: midX, y: curr.y))
                        }
                    }
                    .stroke(eqAccent.opacity(0.68), lineWidth: 2)
                }
            }
            .animation(.easeOut(duration: 0.15), value: displayGains)
        }
    }

    // 垂直滑块叠加层
    private var sliderOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = displayGains.count
            let spacing = w / CGFloat(count)

            let sliders = ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let gain = displayGains[index]
                    let normalized = CGFloat((gain + 12) / 24)
                    let centerX = spacing * CGFloat(index) + spacing / 2
                    let thumbY = h * (1 - normalized)
                    let centerY = h * 0.5

                    // 轨道线
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(eqMutedText.opacity(isCustomEditingEnabled ? 0.26 : 0.16))
                        .frame(width: 3, height: h)
                        .position(x: centerX, y: h / 2)

                    // 增益条（从中线到拇指）
                    let barHeight = abs(thumbY - centerY)
                    let barMidY = min(thumbY, centerY) + barHeight / 2
                    if barHeight > 1 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill((isCustomEditingEnabled ? eqAccent : eqMutedText).opacity(0.56))
                            .frame(width: 3, height: barHeight)
                            .position(x: centerX, y: barMidY)
                    }

                    // 拇指
                    Capsule()
                        .fill(isCustomEditingEnabled ? eqAccent : eqMutedText.opacity(0.7))
                        .frame(width: 8, height: 24)
                        .shadow(
                            color: isCustomEditingEnabled ? eqAccent.opacity(0.3) : .clear,
                            radius: 4,
                            y: 2
                        )
                        .position(x: centerX, y: thumbY)
                }
            }

            if isCustomEditingEnabled {
                sliders
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                                let spacing = w / CGFloat(count)
                                let index = Int((value.location.x / spacing).rounded(.down))
                                let clampedIndex = min(max(index, 0), count - 1)
                                let ratio = 1 - (value.location.y / h)
                                let clamped = min(max(ratio, 0), 1)
                                let newGain = Float(clamped) * 24 - 12
                                eqManager.setCustomGain(newGain, at: clampedIndex)
                            }
                    )
            } else {
                sliders
                    .allowsHitTesting(false)
            }
        }
    }

    // 频率标签
    private var frequencyLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(eqManager.graphicBandLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: eqManager.graphicEQMode == .thirtyTwoBand ? 8 : 9, weight: .medium, design: .monospaced))
                    .foregroundColor(eqSecondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 内置预设

    private var presetScrollSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "eq_builtin_presets_title"))
                    .font(.system(size: centerLayout.isCompactHeight ? 22 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(eqPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: "eq_builtin_presets_description"))
                    .font(.rounded(size: 13, weight: .medium))
                    .foregroundStyle(eqSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(presetCategories, id: \.rawValue) { category in
                        categoryTab(category)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(eqManager.presets(for: selectedCategory)) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    @State private var selectedCategory: EQPresetCategory = .genre

    private var presetCategories: [EQPresetCategory] {
        [.genre, .surround, .scene, .vocal]
    }

    private func categoryTab(_ category: EQPresetCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        }) {
            HStack(spacing: 5) {
                MonoIcon(icon: category.icon, size: 13,
                          color: isSelected ? eqAccentForeground : eqSecondaryText)
                Text(category.rawValue)
                    .font(.rounded(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? eqAccentForeground : eqSecondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(eqAccent)
                } else {
                    Capsule()
                        .fill(eqPrimaryText.opacity(0.045))
                        .overlay {
                            Capsule().strokeBorder(eqSeparator.opacity(0.55), lineWidth: 0.8)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func presetCard(_ preset: EQPreset) -> some View {
        let isSelected = eqManager.currentPreset?.id == preset.id
        let barColor = isSelected ? eqAccentForeground.opacity(0.92) : eqAccent.opacity(0.62)
        // The selected card uses a translucent accent surface, so keep its
        // copy on the stable primary text color for contrast in every theme.
        let nameColor = eqPrimaryText

        return Button(action: {
            withAnimation(.easeOut(duration: 0.2)) {
                isCustomEditingEnabled = false
                eqManager.applyPreset(preset)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(preset.name)
                            .font(.rounded(size: 16, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(nameColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(preset.description)
                            .font(.rounded(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? eqPrimaryText.opacity(0.68) : eqSecondaryText)
                            .lineSpacing(2)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    if isSelected {
                        MonoIcon(icon: .checkmark, size: 11, color: nameColor)
                            .frame(width: 18, height: 18)
                    }
                }

                HStack(alignment: .bottom, spacing: 2.5) {
                    ForEach(Array(preset.gains(in: .tenBand).enumerated()), id: \.offset) { _, gain in
                        Capsule()
                            .fill(barColor)
                            .frame(width: 3, height: 4 + CGFloat((gain + 12) / 24) * 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22, alignment: .bottom)
            }
            .padding(16)
            .frame(
                maxWidth: .infinity,
                minHeight: centerLayout.isCompactHeight ? 148 : 164,
                alignment: .topLeading
            )
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(eqAccent.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(eqAccent.opacity(0.75), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(eqPrimaryText.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(eqSeparator.opacity(0.5), lineWidth: 0.8)
                        )
                }
            }
            .shadow(color: isSelected ? eqAccent.opacity(0.22) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
    }

    // MARK: - 自定义预设

    private var customPresetsSection: some View {
        section(title: String(localized: "eq_my_presets")) {
            VStack(spacing: 0) {
                ForEach(Array(eqManager.customPresets.enumerated()), id: \.element.id) { index, preset in
                    customPresetRow(preset)

                    if index < eqManager.customPresets.count - 1 {
                        Divider()
                            .overlay(eqSeparator)
                            .opacity(0.5)
                            .padding(.leading, 30)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private func customPresetRow(_ preset: EQPreset) -> some View {
        let isSelected = eqManager.currentPreset?.id == preset.id

        return HStack(spacing: 12) {
            Button(action: {
                isCustomEditingEnabled = false
                eqManager.applyPreset(preset)
            }) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(isSelected ? eqAccent : eqSeparator)
                        .frame(width: 7, height: 7)

                    Text(preset.name)
                        .font(.rounded(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(eqPrimaryText)

                    Spacer()

                    if isSelected {
                        MonoIcon(icon: .checkmark, size: 14, color: eqAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { eqManager.deleteCustomPreset(preset) }) {
                MonoIcon(icon: .trash, size: 15, color: eqMutedText.opacity(0.72))
                    .padding(8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 保存按钮

    private var saveButton: some View {
        Button(action: { showSaveSheet = true }) {
            HStack(spacing: 8) {
                MonoIcon(icon: .save, size: 16, color: eqAccentForeground)
                Text(LocalizedStringKey("eq_save_preset"))
                    .font(.rounded(size: 15, weight: .semibold))
                    .foregroundColor(eqAccentForeground)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(eqAccent)
            )
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
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

    private func refreshCoverAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
    }

    // MARK: - 保存预设 Sheet

    private var savePresetSheet: some View {
        NavigationStack {
            ZStack {
                MonoSheetAwareBackground {
                    ThemedPageBackground(useRenderLayer: true)
                        .ignoresSafeArea()
                }

                VStack(spacing: 24) {
                    Text(LocalizedStringKey("eq_save_custom"))
                        .font(.rounded(size: 18, weight: .semibold))
                        .foregroundColor(eqPrimaryText)

                    TextField(NSLocalizedString("eq_preset_name", comment: ""), text: $customPresetName)
                        .font(.rounded(size: 16))
                        .monoTextInputBehavior()
                        .padding(14)
                        .themedPageSurface(cornerRadius: 12, elevated: false)

                    Button(action: {
                        guard !customPresetName.isEmpty else { return }
                        eqManager.saveCustomPreset(name: customPresetName)
                        customPresetName = ""
                        showSaveSheet = false
                    }) {
                        Text(LocalizedStringKey("eq_save"))
                            .font(.rounded(size: 16, weight: .semibold))
                            .foregroundColor(eqAccentForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(eqAccent))
                    }
                    .buttonStyle(.plain)
                    .disabled(customPresetName.isEmpty)
                    .opacity(customPresetName.isEmpty ? 0.5 : 1)

                    Spacer()
                }
                .padding(20)
            }
        }
    }

    // MARK: - 旋钮 ↔ AudioEffects 同步

    /// 从当前 AudioEffects 状态反推旋钮位置
    private func syncKnobsFromGains() {
        let effects = PlayerManager.shared.audioEffects
        bassValue = CGFloat((effects.bassGain + 12) / 24)
        trebleValue = CGFloat((effects.trebleGain + 12) / 24)
        surroundValue = CGFloat(effects.surroundLevel)
        reverbValue = CGFloat(effects.reverbLevel)
        stereoWidthValue = CGFloat(effects.stereoWidth)
        pitchValue = PlayerManager.shared.pitchSemitones
    }

    private func syncSelectedPresetCategory() {
        guard let category = eqManager.currentPreset?.category,
              presetCategories.contains(category)
        else { return }
        selectedCategory = category
    }

    /// 全部重置：EQ 增益 + 音效旋钮 + 变调
    private func resetAll() {
        isCustomEditingEnabled = false
        // 重置 EQ 均衡器
        eqManager.applyFlat()
        eqManager.professionalProcessingIntensity = 1.3
        eqManager.isOutputCalibrationEnabled = true
        eqManager.isLoudnessMatchingEnabled = true
        eqManager.isSmartSongCompensationEnabled = true
        eqManager.isDynamicEQEnabled = true
        eqManager.dynamicEQBands = DynamicEQBand.monoDefaults
        eqManager.isMultibandDynamicsEnabled = true
        eqManager.multibandConfiguration = MultibandDynamicsConfiguration(isEnabled: true)
        eqManager.isParametricEQEnabled = false
        eqManager.parametricBands = []
        eqManager.selectedHeadphoneProfileID = "off"
        
        // 重置音效参数
        PlayerManager.shared.audioEffects.setBassGain(0)
        PlayerManager.shared.audioEffects.setTrebleGain(0)
        PlayerManager.shared.audioEffects.setSurroundLevel(0)
        PlayerManager.shared.audioEffects.setReverbLevel(0)
        PlayerManager.shared.audioEffects.setStereoWidth(1)
        EQManager.shared.saveAudioEffectsState()
        
        // 重置变调
        PlayerManager.shared.setPitch(0)
        
        // 同步旋钮 UI
        syncKnobsFromGains()
    }

    private func applyBassKnob(_ val: CGFloat) {
        let db = Float(val) * 24 - 12
        PlayerManager.shared.audioEffects.setBassGain(db)
        EQManager.shared.updateSafetyLimiter()
        EQManager.shared.saveAudioEffectsState()
    }

    private func applyTrebleKnob(_ val: CGFloat) {
        let db = Float(val) * 24 - 12
        PlayerManager.shared.audioEffects.setTrebleGain(db)
        EQManager.shared.updateSafetyLimiter()
        EQManager.shared.saveAudioEffectsState()
    }

    private func applySurroundKnob(_ val: CGFloat) {
        PlayerManager.shared.audioEffects.setSurroundLevel(Float(val))
        EQManager.shared.saveAudioEffectsState()
    }

    private func applyReverbKnob(_ val: CGFloat) {
        PlayerManager.shared.audioEffects.setReverbLevel(Float(val))
        EQManager.shared.saveAudioEffectsState()
    }

    private func applyStereoWidth(_ val: CGFloat) {
        PlayerManager.shared.audioEffects.setStereoWidth(Float(val))
        EQManager.shared.updateSafetyLimiter()
        EQManager.shared.saveAudioEffectsState()
    }

    private func switchToCustomIfNeeded() {
        if eqManager.currentPreset?.id != "custom" {
            if let preset = eqManager.currentPreset {
                eqManager.customGains = preset.gains(in: eqManager.graphicEQMode)
            }
            eqManager.currentPreset = EQPreset(
                id: "custom",
                name: NSLocalizedString("eq_custom", comment: ""),
                category: .custom,
                description: "",
                gains: eqManager.customGains,
                isCustom: true,
                presetType: eqManager.graphicEQMode == .tenBand ? .standard10 : .graphic32
            )
        }
    }
}

private enum EQSettingsWorkspace: String, CaseIterable, Identifiable {
    case presets
    case equalizer
    case effects
    case calibration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: return String(localized: "eq_workspace_presets")
        case .equalizer: return String(localized: "eq_workspace_equalizer")
        case .effects: return String(localized: "eq_workspace_effects")
        case .calibration: return String(localized: "eq_workspace_calibration")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .presets: return .musicNoteList
        case .equalizer: return .equalizer
        case .effects: return .soundQuality
        case .calibration: return .headphones
        }
    }
}

struct EQImmersiveTrackHeader: View {
    let accent: Color

    @ObservedObject private var player = CurrentSongPresentationModel.shared

    var body: some View {
        Group {
            if let song = player.currentSong {
                HStack(spacing: 12) {
                    CachedAsyncImage(
                        url: song.coverUrl?.sized(240),
                        width: 66,
                        height: 66
                    ) {
                        coverPlaceholder
                    }
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(song.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(song.artistName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 12) {
                    coverPlaceholder
                        .frame(width: 58, height: 58)

                    Text(String(localized: "not_playing"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                MonoIcon(
                    icon: .musicNote,
                    size: 21,
                    color: .white.opacity(0.42)
                )
            )
    }
}

func normalizedEQAccent(_ color: Color) -> Color {
    let uiColor = UIColor(color)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 1

    guard uiColor.getHue(
        &hue,
        saturation: &saturation,
        brightness: &brightness,
        alpha: &alpha
    ) else {
        return Color(red: 0.53, green: 0.62, blue: 1)
    }

    let adjustedSaturation = saturation < 0.08 ? saturation : min(saturation, 0.82)
    let candidate = Color(
        hue: Double(hue),
        saturation: Double(adjustedSaturation),
        brightness: Double(max(brightness, 0.82)),
        opacity: Double(alpha)
    )
    let background = Color(red: 0.055, green: 0.055, blue: 0.072)

    guard ThemeColorCustomization.contrastRatio(between: candidate, and: background) < 3 else {
        return candidate
    }

    return Color(
        hue: Double(hue),
        saturation: Double(saturation < 0.08 ? saturation : min(saturation, 0.56)),
        brightness: 0.96,
        opacity: Double(alpha)
    )
}

// MARK: - Mono 专业模式

private enum EQProfessionalWorkspace: String, CaseIterable, Identifiable {
    case processing
    case mastering
    case spatial
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processing: return String(localized: "eq_workspace_professional_processing")
        case .mastering: return String(localized: "eq_workspace_professional_mastering")
        case .spatial: return String(localized: "eq_workspace_professional_spatial")
        case .advanced: return String(localized: "eq_workspace_professional_advanced")
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .processing: return .sparkle
        case .mastering: return .soundQuality
        case .spatial: return .headphones
        case .advanced: return .equalizer
        }
    }
}

private struct EQProfessionalSettingsView: View {
    @StateObject private var manager = EQManager.shared
    @StateObject private var coverColors = CoverColorExtractor()
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedWorkspace: EQProfessionalWorkspace = .processing
    @Namespace private var workspaceSelectionNamespace

    private var primary: Color { .white }
    private var secondary: Color { .white.opacity(0.52) }
    private var accent: Color { normalizedEQAccent(coverColors.dominantColor) }
    private var separator: Color { .white.opacity(0.07) }

    var body: some View {
        let _ = settings.globalThemeRevision
        ZStack {
            professionalBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EQImmersiveTrackHeader(
                    accent: accent
                )
                workspaceSwitcher
                workspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton(iconColor: .white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            manager.handleAudioRouteChanged()
            refreshCoverAccent()
        }
        .onChange(of: player.currentSong?.id) { _, _ in
            refreshCoverAccent()
        }
        .onDisappear { manager.stopLoudnessMatchedReferenceAudition() }
    }

    private var workspaceSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(EQProfessionalWorkspace.allCases) { workspace in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedWorkspace = workspace
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 6) {
                        MonoIcon(
                            icon: workspace.icon,
                            size: 13,
                            color: selectedWorkspace == workspace
                                ? accentForeground
                                : .white.opacity(0.46)
                        )
                        Text(workspace.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(
                                selectedWorkspace == workspace
                                    ? accentForeground
                                    : .white.opacity(0.52)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if selectedWorkspace == workspace {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(0.86))
                                .matchedGeometryEffect(
                                    id: "professional-workspace-selection",
                                    in: workspaceSelectionNamespace
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedWorkspace == workspace ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .iPadContentWidth(720)
    }

    private var accentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "111821"),
            dark: .white
        )
    }

    private var workspaceContent: AnyView {
        switch selectedWorkspace {
        case .processing:
            return processingWorkspace
        case .mastering:
            return masteringWorkspace
        case .spatial:
            return spatialWorkspace
        case .advanced:
            return advancedWorkspace
        }
    }

    private var processingWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    outputSummary
                    automaticSection
                    preampSection
                }
            )
        )
    }

    private var masteringWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    masteringSection
                }
            )
        )
    }

    private var spatialWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    headphoneSection
                }
            )
        )
    }

    private var advancedWorkspace: AnyView {
        workspaceScroll(
            AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    advancedFeatureSection
                    if manager.isDynamicEQEnabled { dynamicEQSection }
                    if manager.isMultibandDynamicsEnabled { multibandSection }
                    if manager.isParametricEQEnabled { parametricSection }
                }
            )
        )
    }

    private func workspaceScroll(_ content: AnyView) -> AnyView {
        AnyView(
            ScrollView(showsIndicators: false) {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
                    .iPadContentWidth(720)
            }
        )
    }

    private var outputSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                MonoIcon(icon: .headphones, size: 19, color: accent)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.currentOutputName.isEmpty ? manager.currentOutputKind.title : manager.currentOutputName)
                        .font(.rounded(size: 16, weight: .bold))
                        .foregroundColor(primary)
                        .lineLimit(1)
                    Text(
                        "\(manager.currentOutputKind.title) · \(manager.graphicEQMode == .thirtyTwoBand ? String(localized: "eq_thirty_two_band") : String(localized: "eq_ten_band"))"
                    )
                        .font(.rounded(size: 11.5, weight: .medium))
                        .foregroundColor(secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.1f dB", manager.preampDB))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(manager.preampDB < -0.05 ? accent : secondary)
                    Text(LocalizedStringKey("eq_preamp"))
                        .font(.rounded(size: 10.5, weight: .medium))
                        .foregroundColor(secondary)
                }
            }

            Divider().overlay(separator).opacity(0.55)

            Button { manager.toggleLoudnessMatchedReference() } label: {
                HStack {
                    Text(manager.isAuditioningReference ? LocalizedStringKey("eq_ab_return") : LocalizedStringKey("eq_ab_reference"))
                        .font(.rounded(size: 13.5, weight: .semibold))
                    Spacer()
                    Text(manager.isAuditioningReference ? "B" : "A")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(accent.opacity(0.13)))
                }
                .foregroundColor(accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(professionalCardBackground)
    }

    private var automaticSection: some View {
        professionalSection("eq_automatic_processing") {
            parameterSlider(
                title: String(localized: "eq_processing_intensity"),
                value: $manager.professionalProcessingIntensity,
                range: 0.6...2.1,
                step: 0.05,
                valueText: String(format: "%.0f%%", manager.professionalProcessingIntensity * 100)
            )
            sectionDivider
            switchRow("eq_output_calibration", detail: manager.currentOutputKind.title, isOn: $manager.isOutputCalibrationEnabled)
            sectionDivider
            switchRow("eq_loudness_matching", detail: String(localized: "eq_loudness_matching_desc"), isOn: $manager.isLoudnessMatchingEnabled)
            sectionDivider
            switchRow("eq_smart_song", detail: String(localized: "eq_smart_song_desc"), isOn: $manager.isSmartSongCompensationEnabled)
        }
    }

    private var advancedFeatureSection: some View {
        professionalSection("eq_workspace_professional_advanced") {
            switchRow(
                "eq_dynamic_eq",
                detail: String(localized: "eq_dynamic_eq_desc"),
                isOn: $manager.isDynamicEQEnabled
            )
            sectionDivider
            switchRow(
                "eq_multiband",
                detail: String(localized: "eq_multiband_desc"),
                isOn: $manager.isMultibandDynamicsEnabled
            )
            sectionDivider
            switchRow(
                "eq_parametric_eq",
                detail: String(localized: "eq_parametric_eq_desc"),
                isOn: $manager.isParametricEQEnabled
            )
        }
    }

    private var preampSection: some View {
        professionalSection("eq_preset_preamp") {
            parameterSlider(
                title: String(localized: "eq_preamp"),
                value: Binding(
                    get: { manager.currentPresetPreampDB },
                    set: { manager.setCurrentPresetPreampDB($0) }
                ),
                range: -18...0,
                step: 0.1,
                valueText: String(format: "%.1f dB", manager.currentPresetPreampDB)
            )
        }
    }

    private var masteringSection: some View {
        professionalSection("eq_mastering") {
            switchRow(
                "eq_final_limiter",
                detail: String(format: "%.1f dBFS", manager.monoEffectTuning.finalLimiterCeilingDB),
                isOn: monoEffectBoolBinding(\.finalLimiterEnabled)
            )
            if manager.monoEffectTuning.finalLimiterEnabled {
                parameterSlider(
                    title: String(localized: "eq_output_ceiling"),
                    value: monoEffectFloatBinding(\.finalLimiterCeilingDB),
                    range: -3 ... -0.2,
                    step: 0.1,
                    valueText: String(format: "%.1f dBFS", manager.monoEffectTuning.finalLimiterCeilingDB)
                )
            }
        }
    }

    private var headphoneSection: some View {
        professionalSection("eq_headphone_correction") {
            Picker("", selection: $manager.selectedHeadphoneProfileID) {
                Text(LocalizedStringKey("eq_headphone_off")).tag("off")
                Text(LocalizedStringKey("eq_headphone_auto")).tag("auto")
                ForEach(manager.headphoneProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(accent)

            if manager.selectedHeadphoneProfileID != "off",
               manager.selectedHeadphoneProfileID != "auto",
               let profile = manager.headphoneProfiles.first(where: { $0.id == manager.selectedHeadphoneProfileID }) {
                sectionDivider
                correctionSliders(profile)
                sectionDivider
                Button(role: .destructive) {
                    manager.deleteHeadphoneProfile(id: profile.id)
                } label: {
                    Text(LocalizedStringKey("eq_delete_headphone_profile"))
                        .font(.rounded(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            } else {
                sectionDivider
                Button {
                    manager.createHeadphoneProfileForCurrentOutput()
                } label: {
                    HStack {
                        Text(LocalizedStringKey("eq_create_headphone_profile"))
                            .font(.rounded(size: 14, weight: .semibold))
                            .foregroundColor(accent)
                        Spacer()
                        MonoIcon(icon: .add, size: 13, color: accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func correctionSliders(_ profile: MonoHeadphoneCorrectionProfile) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(EQBand.allCases.enumerated()), id: \.element.rawValue) { index, band in
                HStack(spacing: 10) {
                    Text(band.label)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(secondary)
                        .frame(width: 30, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { profile.gains[index] },
                            set: { manager.setHeadphoneCorrectionGain($0, at: index) }
                        ),
                        in: -6...6,
                        step: 0.1
                    )
                    .tint(accent)
                    Text(String(format: "%+.1f", profile.gains[index]))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(primary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var dynamicEQSection: some View {
        professionalSection("eq_dynamic_eq") {
            ForEach(manager.dynamicEQBands.indices, id: \.self) { index in
                if index > 0 { sectionDivider }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(format: String(localized: "eq_dynamic_band_format"), formatFrequency(manager.dynamicEQBands[index].frequency)))
                            .font(.rounded(size: 14, weight: .semibold))
                            .foregroundColor(primary)
                        Spacer()
                        Toggle("", isOn: $manager.dynamicEQBands[index].isEnabled)
                            .labelsHidden()
                            .tint(accent)
                    }
                    parameterSlider(
                        title: String(localized: "eq_frequency"),
                        value: logarithmicFrequencyBinding($manager.dynamicEQBands[index].frequency),
                        range: 0...1,
                        step: 0.001,
                        valueText: formatFrequency(manager.dynamicEQBands[index].frequency)
                    )
                    parameterSlider(
                        title: "Q",
                        value: $manager.dynamicEQBands[index].q,
                        range: 0.2...10,
                        step: 0.05,
                        valueText: String(format: "%.2f", manager.dynamicEQBands[index].q)
                    )
                    parameterSlider(
                        title: String(localized: "eq_threshold"),
                        value: $manager.dynamicEQBands[index].thresholdDB,
                        range: -45...(-6),
                        step: 0.5,
                        valueText: String(format: "%.1f dB", manager.dynamicEQBands[index].thresholdDB)
                    )
                    parameterSlider(
                        title: String(localized: "eq_ratio"),
                        value: $manager.dynamicEQBands[index].ratio,
                        range: 1...6,
                        step: 0.05,
                        valueText: String(format: "%.2f:1", manager.dynamicEQBands[index].ratio)
                    )
                    parameterSlider(
                        title: String(localized: "eq_max_reduction"),
                        value: $manager.dynamicEQBands[index].maxReductionDB,
                        range: 0...6,
                        step: 0.1,
                        valueText: String(format: "%.1f dB", manager.dynamicEQBands[index].maxReductionDB)
                    )
                    parameterSlider(
                        title: String(localized: "eq_attack"),
                        value: $manager.dynamicEQBands[index].attackMS,
                        range: 1...150,
                        step: 1,
                        valueText: String(format: "%.0f ms", manager.dynamicEQBands[index].attackMS)
                    )
                    parameterSlider(
                        title: String(localized: "eq_release"),
                        value: $manager.dynamicEQBands[index].releaseMS,
                        range: 20...600,
                        step: 5,
                        valueText: String(format: "%.0f ms", manager.dynamicEQBands[index].releaseMS)
                    )
                }
            }
        }
    }

    private var multibandSection: some View {
        professionalSection("eq_multiband") {
            parameterSlider(
                title: String(localized: "eq_low_crossover"),
                value: multibandScalarBinding(\.lowCrossoverHz),
                range: 60...600,
                step: 5,
                valueText: formatFrequency(manager.multibandConfiguration.lowCrossoverHz)
            )
            parameterSlider(
                title: String(localized: "eq_high_crossover"),
                value: multibandScalarBinding(\.highCrossoverHz),
                range: 1_200...10_000,
                step: 50,
                valueText: formatFrequency(manager.multibandConfiguration.highCrossoverHz)
            )
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { sectionDivider }
                parameterSlider(
                    title: [String(localized: "eq_low_band"), String(localized: "eq_mid_band"), String(localized: "eq_high_band")][index],
                    value: multibandBinding(index: index, keyPath: \.thresholdsDB),
                    range: -36...(-4),
                    step: 0.5,
                    valueText: String(format: "%.1f dB", manager.multibandConfiguration.thresholdsDB[index])
                )
                parameterSlider(
                    title: String(localized: "eq_ratio"),
                    value: multibandBinding(index: index, keyPath: \.ratios),
                    range: 1...4,
                    step: 0.05,
                    valueText: String(format: "%.2f:1", manager.multibandConfiguration.ratios[index])
                )
                parameterSlider(
                    title: String(localized: "eq_max_reduction"),
                    value: multibandBinding(index: index, keyPath: \.maxReductionDB),
                    range: 0...6,
                    step: 0.1,
                    valueText: String(format: "%.1f dB", manager.multibandConfiguration.maxReductionDB[index])
                )
            }
            sectionDivider
            parameterSlider(
                title: String(localized: "eq_attack"),
                value: multibandScalarBinding(\.attackMS),
                range: 1...150,
                step: 1,
                valueText: String(format: "%.0f ms", manager.multibandConfiguration.attackMS)
            )
            parameterSlider(
                title: String(localized: "eq_release"),
                value: multibandScalarBinding(\.releaseMS),
                range: 20...800,
                step: 5,
                valueText: String(format: "%.0f ms", manager.multibandConfiguration.releaseMS)
            )
        }
    }

    private var parametricSection: some View {
        professionalSection("eq_parametric_eq") {
            ForEach(manager.parametricBands.indices, id: \.self) { index in
                if index > 0 { sectionDivider }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("", selection: $manager.parametricBands[index].type) {
                            ForEach(ParametricEQFilterType.allCases, id: \.rawValue) { type in
                                Text(type.eqDisplayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(primary)
                        Spacer()
                        Toggle("", isOn: $manager.parametricBands[index].isEnabled)
                            .labelsHidden()
                            .tint(accent)
                        Button(role: .destructive) {
                            manager.removeParametricBand(id: manager.parametricBands[index].id)
                        } label: {
                            MonoIcon(icon: .trash, size: 13, color: secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    parameterSlider(
                        title: String(localized: "eq_frequency"),
                        value: logarithmicFrequencyBinding($manager.parametricBands[index].frequency),
                        range: 0...1,
                        step: 0.001,
                        valueText: formatFrequency(manager.parametricBands[index].frequency)
                    )
                    if manager.parametricBands[index].type != .lowPass,
                       manager.parametricBands[index].type != .highPass,
                       manager.parametricBands[index].type != .notch {
                        parameterSlider(
                            title: String(localized: "eq_gain"),
                            value: $manager.parametricBands[index].gainDB,
                            range: -18...18,
                            step: 0.1,
                            valueText: String(format: "%+.1f dB", manager.parametricBands[index].gainDB)
                        )
                    }
                    parameterSlider(
                        title: "Q",
                        value: $manager.parametricBands[index].q,
                        range: 0.1...12,
                        step: 0.05,
                        valueText: String(format: "%.2f", manager.parametricBands[index].q)
                    )
                }
            }
            Button { manager.addParametricBand() } label: {
                HStack {
                    Text(LocalizedStringKey("eq_add_filter"))
                        .font(.rounded(size: 14, weight: .semibold))
                    Spacer()
                    MonoIcon(icon: .add, size: 13, color: accent)
                }
                .foregroundColor(accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func professionalSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.rounded(size: 12, weight: .bold))
                .foregroundColor(secondary)
            content()
        }
        .padding(16)
        .background(professionalCardBackground)
    }

    private func switchRow(
        _ title: LocalizedStringKey,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.rounded(size: 14.5, weight: .semibold))
                    .foregroundColor(primary)
                Text(detail)
                    .font(.rounded(size: 11.5, weight: .medium))
                    .foregroundColor(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
    }

    private func parameterSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        valueText: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.rounded(size: 12, weight: .medium))
                    .foregroundColor(secondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(primary)
            }
            Slider(value: value, in: range, step: step)
                .tint(accent)
        }
    }

    private var sectionDivider: some View {
        Divider().overlay(separator).opacity(0.55)
    }

    private var professionalCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }

    private var professionalBackdrop: some View {
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

    private func refreshCoverAccent() {
        coverColors.extract(
            from: player.currentSong?.coverUrl?.sized(200).absoluteString
        )
    }

    private func multibandBinding(
        index: Int,
        keyPath: WritableKeyPath<MultibandDynamicsConfiguration, [Float]>
    ) -> Binding<Float> {
        Binding(
            get: { manager.multibandConfiguration[keyPath: keyPath][index] },
            set: { value in
                var configuration = manager.multibandConfiguration
                configuration[keyPath: keyPath][index] = value
                manager.multibandConfiguration = configuration
            }
        )
    }

    private func monoEffectBoolBinding(
        _ keyPath: WritableKeyPath<MonoEffectTuningConfiguration, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { manager.monoEffectTuning[keyPath: keyPath] },
            set: { value in
                var configuration = manager.monoEffectTuning
                configuration[keyPath: keyPath] = value
                manager.monoEffectTuning = configuration
            }
        )
    }

    private func monoEffectFloatBinding(
        _ keyPath: WritableKeyPath<MonoEffectTuningConfiguration, Float>
    ) -> Binding<Float> {
        Binding(
            get: { manager.monoEffectTuning[keyPath: keyPath] },
            set: { value in
                var configuration = manager.monoEffectTuning
                configuration[keyPath: keyPath] = value
                manager.monoEffectTuning = configuration
            }
        )
    }

    private func multibandScalarBinding(
        _ keyPath: WritableKeyPath<MultibandDynamicsConfiguration, Float>
    ) -> Binding<Float> {
        Binding(
            get: { manager.multibandConfiguration[keyPath: keyPath] },
            set: { value in
                var configuration = manager.multibandConfiguration
                configuration[keyPath: keyPath] = value
                manager.multibandConfiguration = configuration
            }
        )
    }

    private func logarithmicFrequencyBinding(_ frequency: Binding<Float>) -> Binding<Float> {
        let minimum: Float = 20
        let maximum: Float = 20_000
        let span = logf(maximum / minimum)
        return Binding(
            get: { logf(max(frequency.wrappedValue, minimum) / minimum) / span },
            set: { frequency.wrappedValue = minimum * expf(min(max($0, 0), 1) * span) }
        )
    }

    private func formatFrequency(_ frequency: Float) -> String {
        frequency >= 1_000
            ? String(format: "%.2g kHz", frequency / 1_000)
            : String(format: "%.0f Hz", frequency)
    }
}

private extension ParametricEQFilterType {
    var eqDisplayName: String {
        switch self {
        case .peak: return String(localized: "eq_filter_peak")
        case .lowShelf: return String(localized: "eq_filter_low_shelf")
        case .highShelf: return String(localized: "eq_filter_high_shelf")
        case .lowPass: return String(localized: "eq_filter_low_pass")
        case .highPass: return String(localized: "eq_filter_high_pass")
        case .notch: return String(localized: "eq_filter_notch")
        }
    }
}

// MARK: - 圆形旋钮组件

struct CircularKnob: View {
    @Binding var value: CGFloat // 0~1
    var onChange: ((CGFloat) -> Void)?
    @ObservedObject private var settings = SettingsManager.shared

    private let lineWidth: CGFloat = 6

    private var trackColor: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.surfacePressed : .monoSeparator
    }

    private var activeColor: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.accent : .monoAccent
    }

    private var valueColor: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.ink : .monoTextPrimary
    }

    private var tickColor: Color {
        return NeumorphicStyle.isActive ? NeumorphicStyle.inkMuted : .monoTextSecondary
    }

    // 弧线参数：从左下 (225°) 顺时针到右下 (315°)，跨越 270°
    // SwiftUI trim 参数：startTrim = 0.125 (45°/360°), 总弧 = 0.75 (270°/360°)
    // 旋转 90° 使 trim(0) 在底部
    // 刻度/指示点角度：屏幕坐标从顶部顺时针 = 180° + trim * 360°

    var body: some View {
        let _ = settings.globalThemeRevision

        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let arcDiameter = size - lineWidth
            let tickRadius = arcDiameter / 2 - lineWidth / 2 - 4.5

            ZStack {
                // 内圈刻度
                ForEach(0..<11, id: \.self) { i in
                    let frac = CGFloat(i) / 10
                    let trim = 0.125 + 0.75 * frac
                    let lit = frac <= value + 0.001
                    Capsule()
                        .fill(lit ? activeColor.opacity(0.85) : tickColor.opacity(0.28))
                        .frame(width: 1.5, height: i % 5 == 0 ? 6 : 3.5)
                        .offset(y: -tickRadius + (i % 5 == 0 ? 0 : 1))
                        .rotationEffect(.degrees(180 + 360 * Double(trim)))
                }

                // 背景轨道
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: arcDiameter, height: arcDiameter)

                // 活跃弧线
                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * value)
                    .stroke(activeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: arcDiameter, height: arcDiameter)

                // 端点指示
                Circle()
                    .fill(Color.white)
                    .frame(width: lineWidth - 2.6, height: lineWidth - 2.6)
                    .offset(y: -arcDiameter / 2)
                    .rotationEffect(.degrees(180 + 360 * Double(0.125 + 0.75 * value)))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)

                // 中心百分比
                Text("\(Int(value * 100))")
                    .font(.system(size: size * 0.23, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(valueColor)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let dx = drag.location.x - center.x
                        let dy = drag.location.y - center.y
                        
                        // atan2 返回 -π~π，转换为 0~2π（从正右方逆时针）
                        var angle = atan2(-dy, dx) // 标准数学坐标系角度
                        if angle < 0 { angle += 2 * .pi }
                        
                        // 弧线从 225°(5π/4) 顺时针经过 0° 到 315°(7π/4)
                        // 在数学坐标系中：225° = 5π/4 ≈ 3.927
                        // 死区：从 315°(5.498) 到 225°(3.927) 的短弧（底部 90°）
                        
                        // 将角度转换为从起始点(225°)开始的顺时针偏移
                        // 顺时针 = 角度减小方向
                        let startAngle: CGFloat = 5.0 * .pi / 4.0  // 225° = 3.927 rad
                        
                        // 从起始角顺时针的偏移量
                        var offset = startAngle - angle
                        if offset < 0 { offset += 2 * .pi }
                        
                        // 总弧度 270° = 3π/2
                        let totalArc: CGFloat = 3.0 * .pi / 2.0  // 4.712 rad
                        
                        // 如果偏移超过总弧度，说明在死区
                        if offset > totalArc {
                            // 在死区内，吸附到最近的端点
                            let distToStart = 2 * .pi - offset
                            let distToEnd = offset - totalArc
                            if distToStart < distToEnd {
                                value = 0
                            } else {
                                value = 1
                            }
                        } else {
                            value = min(max(offset / totalArc, 0), 1)
                        }
                        
                        onChange?(value)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
