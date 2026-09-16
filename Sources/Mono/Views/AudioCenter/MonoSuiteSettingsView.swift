import SwiftUI
import UIKit

@MainActor
struct MonoSuiteSettingsView: View {
    private let isEmbedded: Bool
    @StateObject private var suite = MonoNextSuiteManager.shared
    @StateObject private var coverColors = CoverColorExtractor()
    @ObservedObject private var player = PlayerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.monoSoundCenterLayout) private var centerLayout

    @State private var expandedFeature: MonoNextFeature? = .spatialLive
    @State private var showsRecoveryHistory = false

    init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    private var accent: Color {
        normalizedMonoSystemAccent(coverColors.dominantColor)
    }

    private var accentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "101114"),
            dark: .white
        )
    }

    var body: some View {
        presentationRoot
        .onAppear { refreshCoverAccent() }
        .onChange(of: player.currentSong?.coverUrl?.absoluteString) { _, _ in refreshCoverAccent() }
        .fullScreenCover(isPresented: $showsRecoveryHistory) {
            MonoRecoveryHistoryView(accent: accent)
        }
    }

    private var presentationRoot: AnyView {
        if isEmbedded {
            return AnyView(
                playbackWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                .compatFontDesign(nil)
                .environment(\.colorScheme, .dark)
            )
        }

        return AnyView(MonoAudioCenterView(initialWorkspace: .enhancement))
    }

    private var monoBackdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)

            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) {
                    Color.clear
                }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.16)
                .blur(radius: 70)
                .saturation(0.72)
                .opacity(0.22)
                .clipped()
            }

            Color.black.opacity(0.58)
        }
        .ignoresSafeArea()
    }

    private var activeStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(activeFeatureCount > 0 ? accent : Color.white.opacity(0.28))
                .frame(width: 6, height: 6)

            Text(
                String(
                    format: String(localized: "mono_suite_running_count"),
                    activeFeatureCount,
                    managedFeatureCount
                )
            )
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
            .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.28))
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
    }

    private var currentTrackConsole: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                currentCover

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "mono_suite_title"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)

                    Text(player.currentSong?.name ?? String(localized: "mono_suite_no_track"))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(player.currentSong?.artistName ?? String(localized: "mono_suite_waiting_analysis"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                MonoSignalGlyph(
                    dna: suite.currentDNA,
                    accent: accent,
                    isActive: player.isPlaying && activeFeatureCount > 0
                )
                .frame(width: 58, height: 42)
                .accessibilityHidden(true)
            }

            trackMeasurements
        }
        .padding(.horizontal, 20)
        .padding(.top, 7)
        .padding(.bottom, 15)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var currentCover: some View {
        Group {
            if let url = player.currentSong?.coverUrl?.sized(280) {
                CachedAsyncImage(url: url, width: 74, height: 74) {
                    currentCoverPlaceholder
                }
                .aspectRatio(contentMode: .fill)
            } else {
                currentCoverPlaceholder
            }
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(accent.opacity(player.isPlaying ? 0.42 : 0.16), lineWidth: 1)
        }
    }

    private var currentCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                MonoIcon(icon: .musicNote, size: 23, color: .white.opacity(0.42))
            }
    }

    private var trackMeasurements: some View {
        HStack(spacing: 0) {
            measurementItem(
                title: String(localized: "mono_suite_metric_tempo"),
                value: suite.currentDNA.map { "\(Int($0.bpm.rounded()))" } ?? "—",
                unit: suite.currentDNA == nil ? nil : "BPM"
            )

            consoleDivider

            measurementItem(
                title: String(localized: "mono_suite_metric_key"),
                value: suite.currentDNA?.musicalKey ?? "—",
                unit: nil
            )

            consoleDivider

            measurementItem(
                title: String(localized: "mono_suite_metric_loudness"),
                value: suite.currentDNA.map { String(format: "%.1f", $0.loudnessLUFS) } ?? "—",
                unit: suite.currentDNA == nil ? nil : "LUFS"
            )

            consoleDivider

            measurementItem(
                title: String(localized: "mono_suite_metric_dynamics"),
                value: suite.currentDNA.map { String(format: "%.1f", $0.dynamicRange) } ?? "—",
                unit: suite.currentDNA == nil ? nil : "DR"
            )
        }
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func measurementItem(title: String, value: String, unit: String?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var consoleDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 25)
    }

    private var playbackWorkspace: some View {
        ScrollView {
            LazyVStack(spacing: centerLayout.isCompactHeight ? 10 : 13) {
                featureModule(
                    feature: .spatialLive,
                    icon: .headphones,
                    title: String(localized: "mono_spatial_title"),
                    description: String(localized: "mono_spatial_description"),
                    status: spatialModeTitle(suite.spatialConfiguration.mode)
                ) {
                    spatialControls
                }

                featureModule(
                    feature: .dna,
                    icon: .audioWave,
                    title: String(localized: "mono_dna_title"),
                    description: String(localized: "mono_dna_description"),
                    status: dnaStatus
                ) {
                    dnaControls
                }

                featureModule(
                    feature: .recovery,
                    icon: .refresh,
                    title: String(localized: "mono_recovery_title"),
                    description: String(localized: "mono_recovery_description"),
                    status: recoveryStatus
                ) {
                    recoveryControls
                }

                FloatingBarBottomSpacer()
            }
            .padding(.horizontal, centerLayout.horizontalInset)
            .padding(.bottom, centerLayout.isCompactHeight ? 20 : 28)
            .frame(maxWidth: centerLayout.workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func featureModule<Content: View>(
        feature: MonoNextFeature,
        icon: MonoIcon.IconType,
        title: String,
        description: String,
        status: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MonoIntelligenceModule(
            icon: icon,
            title: title,
            description: description,
            status: status,
            accent: accent,
            isEnabled: featureBinding(feature),
            isExpanded: expandedFeature == feature,
            toggleExpansion: {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expandedFeature = expandedFeature == feature ? nil : feature
                }
                UISelectionFeedbackGenerator().selectionChanged()
            },
            content: content
        )
    }

    @ViewBuilder
    private var dnaControls: some View {
        if let dna = suite.currentDNA {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    dnaMetric(String(localized: "mono_dna_energy"), dna.energy)
                    dnaMetric(String(localized: "mono_dna_brightness"), dna.brightness)
                    dnaMetric(String(localized: "mono_dna_rhythm"), dna.rhythmicDrive)
                    dnaMetric(String(localized: "mono_dna_vocal"), dna.vocalPresence)
                }

                moduleDivider

                VStack(alignment: .leading, spacing: 10) {
                    controlLabel(String(localized: "mono_dna_frequency_balance"))
                    energyBand(
                        String(localized: "mono_dna_low"),
                        value: dna.lowEnergy,
                        opacity: 0.72
                    )
                    energyBand(
                        String(localized: "mono_dna_mid"),
                        value: dna.midEnergy,
                        opacity: 0.86
                    )
                    energyBand(
                        String(localized: "mono_dna_high"),
                        value: dna.highEnergy,
                        opacity: 1
                    )
                }

                if !dna.genreHints.isEmpty || !dna.instrumentHints.isEmpty {
                    moduleDivider
                    FlowLayout(spacing: 7) {
                        ForEach(Array((dna.genreHints + dna.instrumentHints).prefix(8)), id: \.self) { hint in
                            Text(localizedDNAHint(hint))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.66))
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(Capsule().fill(Color.white.opacity(0.055)))
                        }
                    }
                }
            }
        } else {
            compactEmptyState(
                icon: .audioWave,
                text: String(localized: "mono_suite_waiting_analysis")
            )
        }
    }

    private var recoveryControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                showsRecoveryHistory = true
            } label: {
                HStack(spacing: 12) {
                    MonoIcon(icon: .history, size: 18, color: accent)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(accent.opacity(0.11))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "mono_recovery_history"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(
                            suite.recoverySnapshot.events.isEmpty
                                ? String(localized: "mono_recovery_ready")
                                : String(
                                    format: String(localized: "mono_recovery_summary"),
                                    suite.recoverySnapshot.events.count,
                                    suite.recoverySnapshot.consecutiveFailures
                                )
                        )
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer(minLength: 8)

                    MonoIcon(icon: .chevronRight, size: 13, color: .white.opacity(0.42))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 62)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            }
            .buttonStyle(.plain)

            if !suite.recoverySnapshot.events.isEmpty {
                secondaryAction(String(localized: "mono_recovery_clear")) {
                    suite.resetRecoveryHistory()
                }
            }
        }
    }

    private var spatialControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            MonoSpatialStageDiagram(
                configuration: suite.spatialConfiguration,
                accent: accent
            )
            .frame(height: centerLayout.isCompactHeight ? 118 : 154)
            .accessibilityHidden(true)

            HStack(spacing: 7) {
                ForEach(MonoSpatialLiveMode.allCases) { mode in
                    selectionButton(
                        title: spatialModeTitle(mode),
                        isSelected: suite.spatialConfiguration.mode == mode
                    ) {
                        if mode == .off {
                            suite.setEnabled(.spatialLive, enabled: false)
                        } else {
                            var configuration = suite.spatialConfiguration
                            configuration.mode = mode
                            suite.setSpatialConfiguration(configuration)
                        }
                    }
                }
            }

            moduleDivider

            spatialSlider(
                String(localized: "mono_spatial_width"),
                value: spatialValueBinding(\.stageWidth, range: 0.7...1.8),
                range: 0.7...1.8
            )
            spatialSlider(
                String(localized: "mono_spatial_depth"),
                value: spatialValueBinding(\.stageDepth, range: 0...1),
                range: 0...1
            )
            spatialSlider(
                String(localized: "mono_spatial_center"),
                value: spatialValueBinding(\.centerFocus, range: 0...1),
                range: 0...1
            )
            spatialSlider(
                String(localized: "mono_spatial_ambience"),
                value: spatialValueBinding(\.ambience, range: 0...0.6),
                range: 0...0.6
            )
        }
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? accentForeground : Color.white.opacity(0.18))
                    .frame(width: 5, height: 5)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? accentForeground : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.86) : Color.white.opacity(0.045))
            )
        }
        .buttonStyle(.plain)
    }

    private func dnaMetric(_ title: String, _ value: Float) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, value))))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 38, height: 38)
            .overlay {
                Text("\(Int(min(1, max(0, value)) * 100))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .monospacedDigit()
            }

            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func energyBand(_ title: String, value: Float, opacity: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 30, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent.opacity(opacity))
                            .frame(width: proxy.size.width * CGFloat(min(1, max(0, value))))
                    }
            }
            .frame(height: 6)
            Text("\(Int(min(1, max(0, value)) * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 34, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func spatialSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(accent)
        }
    }

    private func compactEmptyState(icon: MonoIcon.IconType, text: String) -> some View {
        HStack(spacing: 11) {
            MonoIcon(icon: icon, size: 17, color: accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
        }
    }

    private func secondaryAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    private var moduleDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private func featureBinding(_ feature: MonoNextFeature) -> Binding<Bool> {
        Binding(
            get: { suite.isEnabled(feature) },
            set: { enabled in
                suite.setEnabled(feature, enabled: enabled)
                if enabled {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        expandedFeature = feature
                    }
                }
            }
        )
    }

    private func spatialValueBinding(
        _ keyPath: WritableKeyPath<MonoSpatialLiveConfiguration, Float>,
        range: ClosedRange<Float>
    ) -> Binding<Double> {
        Binding(
            get: { Double(suite.spatialConfiguration[keyPath: keyPath]) },
            set: { value in
                var configuration = suite.spatialConfiguration
                configuration[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, Float(value)))
                suite.setSpatialConfiguration(configuration)
            }
        )
    }

    private var managedFeatureCount: Int { managedFeatures.count }

    private var activeFeatureCount: Int {
        managedFeatures.filter { suite.isEnabled($0) }.count
    }

    private var managedFeatures: [MonoNextFeature] { [.spatialLive, .dna, .recovery] }

    private var dnaStatus: String? {
        suite.currentDNA.map { "\(Int($0.bpm.rounded())) BPM · \($0.musicalKey)" }
    }

    private var recoveryStatus: String? {
        guard !suite.recoverySnapshot.events.isEmpty else {
            return String(localized: "mono_recovery_ready")
        }
        return String(
            format: String(localized: "mono_recovery_event_count"),
            recoveryActionTitle(suite.recoverySnapshot.lastAction),
            suite.recoverySnapshot.events.count
        )
    }

    private func spatialModeTitle(_ mode: MonoSpatialLiveMode) -> String {
        switch mode {
        case .off: return String(localized: "mono_spatial_off")
        case .fixedStage: return String(localized: "mono_spatial_fixed")
        case .headTracked: return String(localized: "mono_spatial_head_tracked")
        }
    }

    private func recoveryActionTitle(_ action: MonoRecoveryAction) -> String {
        switch action {
        case .none: return String(localized: "mono_recovery_ready")
        case .clearLoadingState: return String(localized: "mono_recovery_loading_reset")
        case .reactivateAudioSession: return String(localized: "mono_recovery_audio_restored")
        case .rebuildCurrentPipeline: return String(localized: "mono_recovery_pipeline_rebuilt")
        case .reloadCurrentTrack: return String(localized: "mono_recovery_track_reloaded")
        }
    }

    private func localizedDNAHint(_ hint: String) -> String {
        switch hint.lowercased() {
        case "electronic": return String(localized: "mono_hint_electronic")
        case "hiphop": return String(localized: "mono_hint_hiphop")
        case "rock": return String(localized: "mono_hint_rock")
        case "acoustic": return String(localized: "mono_hint_acoustic")
        case "ballad": return String(localized: "mono_hint_ballad")
        case "pop": return String(localized: "mono_hint_pop")
        case "drums": return String(localized: "mono_hint_drums")
        case "bass": return String(localized: "mono_hint_bass")
        case "vocals": return String(localized: "mono_hint_vocals")
        case "synth": return String(localized: "mono_hint_synth")
        case "guitar": return String(localized: "mono_hint_guitar")
        case "piano": return String(localized: "mono_hint_piano")
        case "strings": return String(localized: "mono_hint_strings")
        default: return hint
        }
    }

    private func refreshCoverAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(220).absoluteString)
    }
}

@MainActor
private struct MonoRecoveryHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var suite = MonoNextSuiteManager.shared

    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(1, proxy.size.width), 760)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    header

                    if suite.recoverySnapshot.events.isEmpty {
                        emptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        records
                    }
                }
                .frame(width: contentWidth, height: proxy.size.height, alignment: .top)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background { recoveryBackdrop }
        .environment(\.colorScheme, .dark)
    }

    private var recoveryBackdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)
            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 430
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                MonoIcon(icon: .chevronLeft, size: 16, color: .white)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common_back"))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "mono_recovery_history"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(
                    String(
                        format: String(localized: "mono_recovery_summary"),
                        suite.recoverySnapshot.events.count,
                        suite.recoverySnapshot.consecutiveFailures
                    )
                )
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            }

            Spacer(minLength: 8)

            if !suite.recoverySnapshot.events.isEmpty {
                Button {
                    suite.resetRecoveryHistory()
                } label: {
                    Text(String(localized: "mono_recovery_clear"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
        }
    }

    private var records: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(suite.recoverySnapshot.events.reversed())) { event in
                    recoveryRow(event)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MonoIcon(icon: .history, size: 24, color: accent)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(accent.opacity(0.11))
                )
            Text(String(localized: "mono_recovery_history_empty"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func recoveryRow(_ event: MonoRecoveryEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(recoveryEventTitle(event.kind))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(event.kind == .failure ? Color.red.opacity(0.88) : .white)

                Spacer(minLength: 8)

                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
            }

            if let song = event.songIdentity {
                Text("\(song.title) · \(song.artist)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                recoveryMetadata(
                    String(localized: "mono_recovery_engine_state"),
                    event.engineState
                )
                recoveryMetadata(
                    String(localized: "mono_recovery_output_route"),
                    event.route
                )
                Spacer(minLength: 0)
                Text("\(formatTime(event.position)) / \(formatTime(event.duration))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 0.6)
        }
    }

    private func recoveryMetadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
    }

    private func recoveryEventTitle(_ kind: MonoRecoveryEventKind) -> String {
        switch kind {
        case .request: return String(localized: "mono_recovery_event_request")
        case .resolving: return String(localized: "mono_recovery_event_resolving")
        case .buffering: return String(localized: "mono_recovery_event_buffering")
        case .playing: return String(localized: "mono_recovery_event_playing")
        case .paused: return String(localized: "mono_recovery_event_paused")
        case .seeking: return String(localized: "mono_recovery_event_seeking")
        case .transition: return String(localized: "mono_recovery_event_transition")
        case .routeChange: return String(localized: "mono_recovery_event_route")
        case .interruption: return String(localized: "mono_recovery_event_interruption")
        case .failure: return String(localized: "mono_recovery_event_failure")
        case .recovered: return String(localized: "mono_recovery_event_recovered")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MonoIntelligenceModule<Content: View>: View {
    @Environment(\.monoSoundCenterLayout) private var centerLayout
    let icon: MonoIcon.IconType
    let title: String
    let description: String
    let status: String?
    let accent: Color
    @Binding var isEnabled: Bool
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    @ViewBuilder let content: Content

    init(
        icon: MonoIcon.IconType,
        title: String,
        description: String,
        status: String?,
        accent: Color,
        isEnabled: Binding<Bool>,
        isExpanded: Bool,
        toggleExpansion: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.status = status
        self.accent = accent
        _isEnabled = isEnabled
        self.isExpanded = isExpanded
        self.toggleExpansion = toggleExpansion
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: toggleExpansion) {
                    HStack(spacing: 12) {
                        MonoIcon(
                            icon: icon,
                            size: centerLayout.isCompactHeight ? 16 : 18,
                            color: isEnabled ? accent : .white.opacity(0.36)
                        )
                        .frame(
                            width: centerLayout.isCompactHeight ? 34 : 38,
                            height: centerLayout.isCompactHeight ? 34 : 38
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isEnabled ? accent.opacity(0.12) : Color.white.opacity(0.045))
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(title)
                                    .font(.system(size: centerLayout.isCompactHeight ? 13.5 : 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(displayStatus)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isEnabled ? accent : .white.opacity(0.46))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }

                            Text(description)
                                .font(.system(size: centerLayout.isCompactHeight ? 10.5 : 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 2)

                        MonoIcon(
                            icon: .chevronDown,
                            size: 11,
                            color: isExpanded ? accent : .white.opacity(0.3)
                        )
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle(title, isOn: $isEnabled)
                    .labelsHidden()
                    .tint(accent)
                    .controlSize(centerLayout.isCompactHeight ? .mini : .regular)
            }
            .padding(.horizontal, centerLayout.isCompactWidth ? 11 : 14)
            .padding(.vertical, centerLayout.isCompactHeight ? 10 : 13)

            if isExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                Group {
                    if isEnabled {
                        content
                    } else {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text(String(localized: "mono_suite_module_disabled"))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.54))
                            Spacer()
                        }
                    }
                }
                .padding(centerLayout.isCompactHeight ? 11 : 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isExpanded
                        ? accent.opacity(isEnabled ? 0.25 : 0.1)
                        : Color.white.opacity(0.075),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    private var displayStatus: String {
        if !isEnabled {
            return String(localized: "mono_suite_status_off")
        }
        if let status, !status.isEmpty {
            return status
        }
        return String(localized: "mono_suite_status_active")
    }
}

private struct MonoSignalGlyph: View {
    let dna: MonoTrackDNA?
    let accent: Color
    let isActive: Bool

    private var values: [CGFloat] {
        if let dna {
            return [
                CGFloat(dna.lowEnergy),
                CGFloat(dna.rhythmicDrive),
                CGFloat(dna.vocalPresence),
                CGFloat(dna.energy),
                CGFloat(dna.brightness),
                CGFloat(dna.midEnergy),
                CGFloat(dna.highEnergy),
            ]
        }
        return [0.22, 0.42, 0.3, 0.56, 0.36, 0.46, 0.25]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(isActive ? accent.opacity(0.62 + Double(index % 3) * 0.12) : Color.white.opacity(0.16))
                    .frame(width: 4, height: max(7, 36 * min(1, max(0.12, value))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct MonoSpatialStageDiagram: View {
    let configuration: MonoSpatialLiveConfiguration
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
            let width = size.width * 0.28 * CGFloat(configuration.stageWidth)
            let depth = 26 + size.height * 0.28 * CGFloat(configuration.stageDepth)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Ellipse()
                        .stroke(
                            Color.white.opacity(0.055 + Double(index) * 0.025),
                            lineWidth: 1
                        )
                        .frame(
                            width: width + CGFloat(index) * 46,
                            height: depth + CGFloat(index) * 25
                        )
                        .position(center)
                }

                Capsule()
                    .fill(accent.opacity(0.18 + Double(configuration.ambience)))
                    .frame(width: max(42, width * 0.92), height: 6)
                    .blur(radius: 6)
                    .position(center)

                Circle()
                    .fill(accent)
                    .frame(
                        width: 13 + 8 * CGFloat(configuration.centerFocus),
                        height: 13 + 8 * CGFloat(configuration.centerFocus)
                    )
                    .position(center)

                HStack(spacing: max(64, width * 0.72)) {
                    speaker
                    speaker
                }
                .position(x: center.x, y: center.y - depth * 0.18)

                MonoIcon(icon: .headphones, size: 19, color: .white.opacity(0.72))
                    .position(x: center.x, y: size.height - 18)
            }
            .frame(width: size.width, height: size.height)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var speaker: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: 16, height: 26)
            .overlay {
                VStack(spacing: 3) {
                    Circle().fill(accent.opacity(0.72)).frame(width: 5, height: 5)
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: 7, height: 7)
                }
            }
    }
}

private extension MonoDNASection.Kind {
    static var allCasesForInterface: [Self] {
        [.opening, .body, .peak, .release]
    }
}

private func normalizedMonoSystemAccent(_ color: Color) -> Color {
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
        return Color(red: 0.48, green: 0.7, blue: 1)
    }

    return Color(
        hue: Double(hue),
        saturation: Double(saturation < 0.08 ? 0.18 : min(0.74, saturation)),
        brightness: Double(max(0.82, brightness)),
        opacity: Double(alpha)
    )
}
