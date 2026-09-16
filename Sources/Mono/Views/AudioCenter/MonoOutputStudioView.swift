import SwiftUI
import Combine
import FFmpegSwiftSDK

@MainActor
struct MonoOutputStudioView: View {
    let accent: Color
    enum Section: String, CaseIterable, Identifiable {
        case devices
        case monitor
        case hearing
        case airPods

        var id: String { rawValue }

        var title: String {
            switch self {
            case .devices: return String(localized: "sound_output_section_devices")
            case .monitor: return String(localized: "sound_output_section_monitor")
            case .hearing: return String(localized: "sound_output_section_hearing")
            case .airPods: return "AirPods"
            }
        }
    }

    @Environment(\.monoSoundCenterLayout) private var layout
    @State private var section: Section = .devices

    var body: some View {
        VStack(spacing: 0) {
            sectionSelector
            Group {
                switch section {
                case .devices:
                    MonoAcousticCatalogView()
                case .monitor:
                    MonoAudioMonitorView()
                case .hearing:
                    MonoHearingStudioView()
                case .airPods:
                    AirPodsSettingsView(isEmbedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sectionSelector: some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases) { item in
                Button {
                    section = item
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(item.title)
                        .font(.system(size: layout.isCompactWidth ? 10 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(section == item ? accent : MonoSoundCenterStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(section == item ? accent : .clear)
                                .frame(height: 1.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, layout.horizontalInset)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }
}

@MainActor
private struct MonoAcousticCatalogView: View {
    @ObservedObject private var catalog = MonoAcousticProfileEngine.shared
    @ObservedObject private var eq = EQManager.shared
    @Environment(\.monoSoundCenterLayout) private var layout

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                currentOutput
                searchBar
                catalogStatus
                ForEach(catalog.filteredProfiles) { profile in
                    profileRow(profile)
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
                attribution
                FloatingBarBottomSpacer()
            }
            .padding(.horizontal, layout.horizontalInset)
            .frame(maxWidth: layout.workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear { catalog.refreshIfNeeded() }
    }

    private var currentOutput: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MonoIcon(icon: .headphones, size: 22, color: .white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(eq.currentOutputName.isEmpty ? eq.currentOutputKind.title : eq.currentOutputName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(activeProfileName)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                Spacer()
                if eq.selectedHeadphoneProfileID != "off" {
                    Button(String(localized: "sound_output_disable_profile")) {
                        eq.selectedHeadphoneProfileID = "off"
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.vertical, 14)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "sound_output_auto_switch"))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(String(localized: "sound_output_auto_switch_desc"))
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { eq.isAutomaticOutputProfileSelectionEnabled },
                    set: { eq.setAutomaticOutputProfileSelectionEnabled($0) }
                ))
                .labelsHidden()
                .tint(.white.opacity(0.78))
                .scaleEffect(0.84)
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            MonoIcon(icon: .search, size: 14, color: .white.opacity(0.38))
            TextField(String(localized: "sound_output_search_placeholder"), text: $catalog.query)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !catalog.query.isEmpty {
                Button {
                    catalog.query = ""
                } label: {
                    MonoIcon(icon: .close, size: 12, color: .white.opacity(0.38))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
    }

    private var catalogStatus: some View {
        HStack(spacing: 8) {
            Text(String(format: String(localized: "sound_output_catalog_count"), catalog.catalogCount))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
            Spacer()
            if catalog.isRefreshing {
                ProgressView().tint(.white).scaleEffect(0.7)
            }
            Button {
                catalog.refresh()
            } label: {
                HStack(spacing: 5) {
                    MonoIcon(icon: .refresh, size: 12, color: .white.opacity(0.68))
                    Text(String(localized: "sound_output_refresh_catalog"))
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
            }
            .buttonStyle(.plain)
            .disabled(catalog.isRefreshing)
        }
        .padding(.vertical, 11)
    }

    private func profileRow(_ profile: MonoAcousticProfile) -> some View {
        let isApplied = eq.selectedHeadphoneProfileID == "opra:\(profile.id)"
            || (eq.isAutomaticOutputProfileSelectionEnabled && eq.activeOutputProfileName == profile.displayName)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                catalog.apply(profile)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if !profile.subtype.isEmpty {
                                Text(profile.subtype)
                            }
                            Text(profile.author)
                            Text(String(format: "%+.1f dB", profile.preampDB))
                        }
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if isApplied {
                        MonoIcon(icon: .checkmark, size: 14, color: .white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    } else {
                        Text(String(localized: "sound_output_apply_profile"))
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(minWidth: 38, minHeight: 28)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                catalog.toggleFavorite(profile)
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                MonoIcon(
                    icon: catalog.isFavorite(profile) ? .liked : .like,
                    size: 14,
                    color: catalog.isFavorite(profile) ? .white : .white.opacity(0.34)
                )
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                catalog.isFavorite(profile)
                    ? String(localized: "sound_output_remove_favorite")
                    : String(localized: "sound_output_add_favorite")
            )
        }
        .padding(.vertical, 8)
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let error = catalog.errorMessage {
                Text(error)
                    .foregroundStyle(Color.red.opacity(0.82))
            }
            Text(String(localized: "sound_output_opra_attribution"))
                .foregroundStyle(.white.opacity(0.34))
        }
        .font(.system(size: 9.5, weight: .regular, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
    }

    private var activeProfileName: String {
        if eq.isAutomaticOutputProfileSelectionEnabled {
            return eq.activeOutputProfileName.map {
                String(format: String(localized: "sound_output_auto_profile_value"), $0)
            } ?? String(localized: "sound_output_auto_profile_waiting")
        }
        if eq.selectedHeadphoneProfileID == "off" {
            return String(localized: "sound_output_no_profile")
        }
        return eq.headphoneProfiles.first(where: { $0.id == eq.selectedHeadphoneProfileID })?.name
            ?? String(localized: "sound_output_auto_profile")
    }
}

@MainActor
private struct MonoAudioMonitorView: View {
    private let monitor = MonoAudioMonitorEngine.shared
    @ObservedObject private var loudness = MonoLoudnessEngine.shared
    @ObservedObject private var eq = EQManager.shared
    @ObservedObject private var history = MonoDSPHistoryEngine.shared
    @Environment(\.monoSoundCenterLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                spectrumSection
                meterSection
                chainSection
                loudnessSection
                FloatingBarBottomSpacer()
            }
            .padding(.horizontal, layout.horizontalInset)
            .padding(.top, 12)
            .frame(maxWidth: layout.workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var spectrumSection: some View {
        MonoMonitorValueReader(initial: (monitor.inputSpectrum, monitor.outputSpectrum), updates: Publishers.CombineLatest(monitor.$inputSpectrum, monitor.$outputSpectrum).eraseToAnyPublisher()) { inputSpectrum, outputSpectrum in
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(String(localized: "sound_monitor_spectrum"))
                MonoSpectrumGraph(
                    primary: outputSpectrum,
                    secondary: inputSpectrum,
                    primaryColor: .white,
                    secondaryColor: .cyan.opacity(0.6)
                )
                .frame(height: layout.isCompactHeight ? 118 : 150)

                HStack(spacing: 16) {
                    graphLegend(color: .cyan.opacity(0.8), title: String(localized: "sound_monitor_input"))
                    graphLegend(color: .white, title: String(localized: "sound_monitor_output"))
                    Spacer()
                    Button {
                        eq.toggleLoudnessMatchedReference()
                    } label: {
                        Text(eq.isAuditioningReference ? "B" : "A")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 28)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var meterSection: some View {
        MonoMonitorValueReader(initial: monitor.meters, updates: monitor.$meters.eraseToAnyPublisher()) { meters in
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    sectionHeading(String(localized: "sound_monitor_meters"))
                    Spacer()
                    if meters.clippingRatio > 0 {
                        HStack(spacing: 4) {
                            MonoIcon(icon: .warning, size: 10, color: .orange)
                            Text(String(localized: "sound_monitor_clipping"))
                        }
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    }
                    Button(String(localized: "sound_monitor_reset")) {
                        monitor.resetMeters()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    metric("LUFS-M", meters.momentaryLUFS, "LUFS")
                    metric("LUFS-S", meters.shortTermLUFS, "LUFS")
                    metric("TRUE PEAK", meters.estimatedTruePeakDBTP, "dBTP")
                    metric(String(localized: "sound_monitor_phase"), meters.phaseCorrelation, "")
                    metric(String(localized: "sound_monitor_mono"), meters.monoCompatibility * 100, "%")
                    metric(String(localized: "sound_monitor_width"), meters.stereoWidth, "")
                }
            }
        }
    }

    private var chainSection: some View {
        MonoMonitorValueReader(initial: monitor.chain, updates: monitor.$chain.eraseToAnyPublisher()) { chain in
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(String(localized: "sound_monitor_chain"))
                MonoCurveGraph(
                    frequencies: chain.mode.centerFrequencies,
                    curves: [chain.userCurve, chain.deviceCurve, chain.combinedCurve]
                )
                .frame(height: 112)

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(Array(chain.activeStages.enumerated()), id: \.offset) { index, stage in
                            Text(stage)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                            if index < chain.activeStages.count - 1 {
                                MonoIcon(icon: .chevronRight, size: 8, color: .white.opacity(0.26))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                HStack {
                    Text(chain.deviceName)
                    Spacer()
                    Text(String(format: String(localized: "sound_monitor_headroom_value"), chain.estimatedHeadroomDB))
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))

                HStack(spacing: 16) {
                    Button(String(localized: "sound_history_checkpoint")) { history.checkpoint() }
                    Button(String(localized: "sound_history_undo")) { history.undo() }
                        .disabled(!history.canUndo)
                    Button(String(localized: "sound_history_redo")) { history.redo() }
                        .disabled(!history.canRedo)
                    Spacer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
            }
        }
    }

    private var loudnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeading(String(localized: "sound_loudness_title"))
                Spacer()
                Toggle("", isOn: $loudness.isEnabled)
                    .labelsHidden()
                    .tint(.white.opacity(0.76))
            }
            Picker(String(localized: "sound_loudness_mode"), selection: $loudness.mode) {
                Text(String(localized: "sound_loudness_track")).tag(MonoLoudnessMode.track)
                Text(String(localized: "sound_loudness_album")).tag(MonoLoudnessMode.album)
            }
            .pickerStyle(.segmented)
            .disabled(!loudness.isEnabled)

            HStack {
                Text(String(localized: "sound_loudness_target"))
                Slider(value: $loudness.targetLUFS, in: -20 ... -10, step: 1)
                    .tint(.white.opacity(0.74))
                Text(String(format: "%.0f", loudness.targetLUFS))
                    .frame(width: 28, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .disabled(!loudness.isEnabled)

            HStack {
                Text(String(format: String(localized: "sound_loudness_records"), loudness.recordCount))
                Spacer()
                Text(String(format: String(localized: "sound_loudness_applied"), loudness.appliedGainDB))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.38))
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func metric(_ title: String, _ value: Float, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.36))
                .lineLimit(1)
            Text(String(format: value.magnitude >= 100 ? "%.0f%@" : "%.1f%@", value, unit))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func graphLegend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
        }
    }
}

@MainActor
private struct MonoHearingStudioView: View {
    @ObservedObject private var hearing = MonoHearingProfileEngine.shared
    @ObservedObject private var environment = MonoListeningEnvironmentEngine.shared
    @ObservedObject private var eq = EQManager.shared
    @Environment(\.monoSoundCenterLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hearingSection
                exposureSection
                environmentSection
                FloatingBarBottomSpacer()
            }
            .padding(.horizontal, layout.horizontalInset)
            .padding(.top, 14)
            .frame(maxWidth: layout.workspaceMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var hearingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                title(String(localized: "sound_hearing_audiogram"))
                Spacer()
                if hearing.isLoading || hearing.isRequestingAuthorization {
                    ProgressView().tint(.white).scaleEffect(0.72)
                }
            }

            if hearing.points.isEmpty {
                Text(String(localized: "sound_hearing_audiogram_empty"))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                actionButton(String(localized: "sound_hearing_connect_health"), icon: .like) {
                    hearing.requestAccessAndRefresh()
                }
            } else {
                MonoCurveGraph(
                    frequencies: GraphicEQMode.tenBand.centerFrequencies,
                    curves: [hearing.leftCorrection, hearing.rightCorrection],
                    colors: [.cyan, .pink]
                )
                .frame(height: 128)
                HStack {
                    legend(.cyan, String(localized: "sound_hearing_left"))
                    legend(.pink, String(localized: "sound_hearing_right"))
                    Spacer()
                    if let date = hearing.audiogramDate {
                        Text(date.formatted(date: .numeric, time: .omitted))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
                HStack(spacing: 10) {
                    actionButton(
                        eq.isHearingCorrectionEnabled
                            ? String(localized: "sound_hearing_disable")
                            : String(localized: "sound_hearing_apply"),
                        icon: eq.isHearingCorrectionEnabled ? .close : .checkmark
                    ) {
                        if eq.isHearingCorrectionEnabled {
                            hearing.removeCorrection()
                        } else {
                            hearing.applyCorrection()
                        }
                    }
                    actionButton(String(localized: "sound_hearing_refresh"), icon: .refresh) {
                        hearing.refresh()
                    }
                }
            }

            if let error = hearing.errorMessage {
                Text(error)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            title(String(localized: "sound_hearing_exposure"))
            HStack(alignment: .lastTextBaseline) {
                Text(hearing.averageExposureDBASPL.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("dBA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text(String(format: String(localized: "sound_hearing_exposure_hours"), hearing.exposureDurationHours))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Text(String(localized: "sound_hearing_exposure_period"))
                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(String(localized: "sound_environment_title"))
            Text(String(localized: "sound_environment_description"))
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)

            if environment.isMeasuring {
                ProgressView(value: environment.progress)
                    .tint(.white.opacity(0.8))
                Button(String(localized: "cancel")) { environment.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            } else if let measurement = environment.measurement {
                MonoCurveGraph(
                    frequencies: GraphicEQMode.tenBand.centerFrequencies,
                    curves: [measurement.bandLevelsDBFS, measurement.suggestedMaskingCurve],
                    colors: [.orange, .white]
                )
                .frame(height: 120)
                HStack {
                    Text(String(format: String(localized: "sound_environment_noise_floor"), measurement.noiseFloorDBFS))
                    Spacer()
                    Button(
                        eq.isEnvironmentCompensationEnabled
                            ? String(localized: "sound_environment_disable")
                            : String(localized: "sound_environment_apply")
                    ) {
                        if eq.isEnvironmentCompensationEnabled {
                            eq.setEnvironmentCompensationEnabled(false)
                        } else {
                            environment.applySuggestion()
                        }
                    }
                    .buttonStyle(.plain)
                    .fontWeight(.bold)
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                HStack(spacing: 10) {
                    actionButton(String(localized: "sound_environment_measure_again"), icon: .microphone) {
                        environment.start()
                    }
                    Button(String(localized: "sound_environment_clear")) {
                        environment.clearMeasurement()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                }
            } else {
                actionButton(String(localized: "sound_environment_start"), icon: .microphone) {
                    environment.start()
                }
            }

            if let error = environment.errorMessage {
                Text(error)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func actionButton(_ text: String, icon: MonoIcon.IconType, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                MonoIcon(icon: icon, size: 13, color: .white)
                Text(text)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
        }
    }
}

private struct MonoSpectrumGraph: View {
    let primary: [Float]
    let secondary: [Float]
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)
            drawSpectrum(secondary, color: secondaryColor, context: &context, size: size)
            drawSpectrum(primary, color: primaryColor, context: &context, size: size)
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for step in 1..<4 {
            let y = size.height * CGFloat(step) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
    }

    private func drawSpectrum(_ values: [Float], color: Color, context: inout GraphicsContext, size: CGSize) {
        guard values.count > 1 else { return }
        let converted = values.map { value -> CGFloat in
            let db = value > 0 ? 20 * log10(max(value, 0.000_1)) : value
            return CGFloat(min(1, max(0, (db + 80) / 80)))
        }
        var path = Path()
        for index in converted.indices {
            let x = size.width * CGFloat(index) / CGFloat(max(converted.count - 1, 1))
            let y = size.height * (1 - converted[index])
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
    }
}

private struct MonoCurveGraph: View {
    let frequencies: [Float]
    let curves: [[Float]]
    var colors: [Color] = [.cyan, .white.opacity(0.5), .white]

    var body: some View {
        Canvas { context, size in
            let zeroY = size.height / 2
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: zeroY))
            zero.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(zero, with: .color(.white.opacity(0.1)), lineWidth: 1)

            for (curveIndex, curve) in curves.enumerated() where curve.count > 1 {
                let count = min(curve.count, frequencies.count)
                guard count > 1 else { continue }
                var path = Path()
                for index in 0..<count {
                    let x = size.width * CGFloat(index) / CGFloat(count - 1)
                    let gain = min(12, max(-12, curve[index]))
                    let y = zeroY - CGFloat(gain / 12) * zeroY * 0.86
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(
                    path,
                    with: .color(colors[curveIndex % colors.count]),
                    style: StrokeStyle(lineWidth: curveIndex == curves.count - 1 ? 1.8 : 1.1, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


/// Observes one monitor output without invalidating the surrounding controls.
private struct MonoMonitorValueReader<Value, Content: View>: View {
    @State private var snapshot: Value
    private let updates: AnyPublisher<Value, Never>
    private let content: (Value) -> Content

    init(initial: Value, updates: AnyPublisher<Value, Never>, @ViewBuilder content: @escaping (Value) -> Content) {
        _snapshot = State(initialValue: initial)
        self.updates = updates
        self.content = content
    }

    var body: some View {
        content(snapshot)
            .onReceive(updates) { snapshot = $0 }
    }
}
