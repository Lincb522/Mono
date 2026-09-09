import SwiftUI
import FFmpegSwiftSDK

@MainActor
struct AIEqualizerLabView: View {
    let isEmbedded: Bool
    @ObservedObject var player = CurrentSongPresentationModel.shared
    @ObservedObject var tuningServiceStore = AITuningServiceStore.shared
    @StateObject var agent = AIEqualizerAgent.shared
    @StateObject var eqManager = EQManager.shared
    @StateObject var coverColors = CoverColorExtractor()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.monoSoundCenterLayout) var centerLayout
    @Namespace var controlSelectionNamespace
    @State var expandedMeasurementGroups: Set<AIEqualizerMeasurementGroup> = []
    @State var isProposalParameterExpanded = false
    @State var isCalibrationExpanded = false
    @State var isTuningConfigurationExpanded = false
    @State var isShowingClearLearningConfirmation = false
    @State var isShowingClearAllProposalsConfirmation = false
    @State var comparisonProposal: AIEqualizerSavedProposal?
    @State var selectedWorkspace: AIEqualizerWorkspace = .tuning

    init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    var accent: Color { normalizedAIEqualizerAccent(coverColors.dominantColor) }
    var accentForeground: Color {
        ThemeColorCustomization.readableForegroundColor(
            on: accent,
            light: Color(hex: "111821"),
            dark: .white
        )
    }

    var currentOutputIdentity: String {
        eqManager.currentOutputName.isEmpty
            ? eqManager.currentOutputKind.rawValue
            : "\(eqManager.currentOutputKind.rawValue):\(eqManager.currentOutputName)"
    }

    var body: some View {
        presentationRoot
        .monoSheet(item: $comparisonProposal, preset: .detail) { historical in
            NavigationStack {
                AIEqualizerProposalComparisonRedesignView(
                    current: agent.proposal,
                    historical: historical,
                    accent: accent
                )
            }
        }
        .alert(
            String(localized: "ai_learning_clear_title"),
            isPresented: $isShowingClearLearningConfirmation
        ) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "ai_learning_clear_action"), role: .destructive) {
                agent.clearLearningHistory()
            }
        } message: {
            Text(String(localized: "ai_learning_clear_message"))
        }
        .alert(
            String(localized: "ai_lab_clear_all_proposals_title"),
            isPresented: $isShowingClearAllProposalsConfirmation
        ) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "ai_lab_clear_all_proposals"), role: .destructive) {
                agent.deleteAllSavedProposals()
            }
        } message: {
            Text(String(localized: "ai_lab_clear_all_proposals_message"))
        }
        .onAppear { refreshCoverAccent() }
        .onChange(of: player.currentSong?.id) { _, _ in
            refreshCoverAccent()
            selectedWorkspace = .tuning
            expandedMeasurementGroups.removeAll()
            isProposalParameterExpanded = false
            isCalibrationExpanded = false
        }
        .onChange(of: agent.proposal?.id) { _, _ in
            isProposalParameterExpanded = false
            isCalibrationExpanded = false
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.22),
            value: agent.phase.isWorking
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.24),
            value: agent.proposal?.id
        )
    }

    var presentationRoot: AnyView {
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

        return AnyView(MonoAudioCenterView(initialWorkspace: .ai))
    }
}
