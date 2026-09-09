import SwiftUI

@MainActor
struct MonoAudioAdaptiveLearningView: View {
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var agent = AIEqualizerAgent.shared
    @State private var selectedFilter: LearningRecordFilter = .all
    @State private var recordPage = 0
    @State private var showsClearConfirmation = false

    let accent: Color

    private static let recordsPerPage = 15

    var body: some View {
        GeometryReader { proxy in
            let layout = MonoSoundCenterLayout(size: proxy.size)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: layout.isCompactHeight ? 18 : 24) {
                            header(layout: layout)
                            learningSettings(layout: layout)
                            learningSources(layout: layout)
                            storageNotice
                            learningRecords(layout: layout) { page in
                                recordPage = page
                                DispatchQueue.main.async {
                                    scrollProxy.scrollTo(LearningRecordsAnchor.id, anchor: .top)
                                }
                            }
                            .id(LearningRecordsAnchor.id)
                        }
                        .padding(.horizontal, layout.horizontalInset)
                        .padding(.top, layout.isCompactHeight ? 8 : 12)
                        .padding(.bottom, layout.isCompactHeight ? 24 : 36)
                        .frame(width: layout.workspaceMaxWidth)
                    }
                }
                .frame(width: layout.contentMaxWidth)

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background { learningBackdrop }
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsClearConfirmation = true
                } label: {
                    MonoIcon(
                        icon: .trash,
                        size: 15,
                        color: agent.learningRecords.isEmpty ? .white.opacity(0.25) : .red
                    )
                    .frame(width: 44, height: 44)
                }
                .disabled(agent.learningRecords.isEmpty)
                .accessibilityLabel(String(localized: "ai_learning_clear_action"))
            }
        }
        .alert(
            String(localized: "ai_learning_clear_title"),
            isPresented: $showsClearConfirmation
        ) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "ai_learning_clear_action"), role: .destructive) {
                agent.clearLearningHistory()
            }
        } message: {
            Text(String(localized: "ai_learning_clear_message"))
        }
        .onChange(of: agent.learningRecords.count) { _, _ in
            recordPage = recordPageSnapshot.resolvedPage
        }
    }

    private func header(layout: MonoSoundCenterLayout) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(learningSummary)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(agent.adaptiveLearningEnabled
                 ? String(localized: "audio_agent_learning_enabled_status")
                 : String(localized: "settings_off"))
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(agent.adaptiveLearningEnabled ? accent : .white.opacity(0.42))
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Color.black.opacity(0.25), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.vertical, layout.isCompactHeight ? 2 : 4)
    }

    private func learningSettings(layout: MonoSoundCenterLayout) -> some View {
        settingsSection(
            title: String(localized: "audio_agent_learning_general"),
            layout: layout
        ) {
            toggleRow(
                icon: .sparkle,
                artwork: .learningEnabled,
                title: String(localized: "ai_learning_enabled"),
                detail: String(localized: "audio_agent_learning_enabled_detail"),
                isOn: $agent.adaptiveLearningEnabled,
                layout: layout
            )

            rowDivider

            menuRow(
                icon: .equalizer,
                artwork: .learningStrength,
                title: String(localized: "audio_agent_learning_strength"),
                detail: String(localized: "audio_agent_learning_strength_detail"),
                value: agent.learningStrength.localizedTitle,
                layout: layout
            ) {
                ForEach(AIEqualizerLearningStrength.allCases) { strength in
                    Button {
                        agent.learningStrength = strength
                    } label: {
                        if strength == agent.learningStrength {
                            Label(strength.localizedTitle, systemImage: "checkmark")
                        } else {
                            Text(strength.localizedTitle)
                        }
                    }
                }
            }
            .disabled(!agent.adaptiveLearningEnabled)
            .opacity(agent.adaptiveLearningEnabled ? 1 : 0.45)

            rowDivider

            menuRow(
                icon: .clock,
                artwork: .learningRetention,
                title: String(localized: "audio_agent_learning_retention"),
                detail: String(localized: "audio_agent_learning_retention_detail"),
                value: agent.learningRetention.localizedTitle,
                layout: layout
            ) {
                ForEach(AIEqualizerLearningRetention.allCases) { retention in
                    Button {
                        agent.learningRetention = retention
                    } label: {
                        if retention == agent.learningRetention {
                            Label(retention.localizedTitle, systemImage: "checkmark")
                        } else {
                            Text(retention.localizedTitle)
                        }
                    }
                }
            }
        }
    }

    private func learningSources(layout: MonoSoundCenterLayout) -> some View {
        settingsSection(
            title: String(localized: "audio_agent_learning_sources"),
            layout: layout
        ) {
            toggleRow(
                icon: .checkmark,
                artwork: .learningSourceFeedback,
                title: String(localized: "audio_agent_learning_source_feedback"),
                detail: String(localized: "audio_agent_learning_source_feedback_detail"),
                isOn: $agent.learnsFromExplicitFeedback,
                layout: layout
            )
            rowDivider
            toggleRow(
                icon: .playCircle,
                artwork: .learningSourceListening,
                title: String(localized: "audio_agent_learning_source_listening"),
                detail: String(localized: "audio_agent_learning_source_listening_detail"),
                isOn: $agent.learnsFromListeningBehavior,
                layout: layout
            )
            rowDivider
            toggleRow(
                icon: .refresh,
                artwork: .learningSourceAdjustments,
                title: String(localized: "audio_agent_learning_source_adjustments"),
                detail: String(localized: "audio_agent_learning_source_adjustments_detail"),
                isOn: $agent.learnsFromAdjustmentActions,
                layout: layout
            )
        }
        .disabled(!agent.adaptiveLearningEnabled)
        .opacity(agent.adaptiveLearningEnabled ? 1 : 0.45)
    }

    private var storageNotice: some View {
        HStack(alignment: .top, spacing: 11) {
            MonoIcon(icon: .storage, size: 16, color: accent)
                .monoIconArtwork(MonoGlyphSemantic.learningLocalStorage.rawValue)
                .frame(width: 22)
            Text(String(localized: "audio_agent_learning_storage_notice"))
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(sectionSurface)
    }

    private func learningRecords(
        layout: MonoSoundCenterLayout,
        onSelectPage: @escaping (Int) -> Void
    ) -> some View {
        let page = recordPageSnapshot

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(localized: "audio_agent_learning_records"))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer(minLength: 8)

                Text(
                    String(
                        format: String(localized: "audio_agent_learning_record_count"),
                        agent.learningRecords.count
                    )
                )
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            }

            filterBar

            VStack(spacing: 0) {
                if page.records.isEmpty {
                    emptyRecords
                } else {
                    ForEach(Array(page.records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink {
                            MonoAudioLearningRecordDetailView(recordID: record.id, accent: accent)
                        } label: {
                            recordRow(record, layout: layout)
                        }
                        .buttonStyle(.plain)

                        if index < page.records.count - 1 {
                            rowDivider
                        }
                    }

                    if page.pageCount > 1 {
                        rowDivider
                        recordPagination(page: page, onSelectPage: onSelectPage)
                    }
                }
            }
            .padding(.horizontal, layout.isCompactWidth ? 12 : 14)
            .background(sectionSurface)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LearningRecordFilter.allCases) { filter in
                    Button {
                        recordPage = 0
                        selectedFilter = filter
                    } label: {
                        Text(filter.localizedTitle)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(selectedFilter == filter ? .black.opacity(0.82) : .white.opacity(0.58))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 32)
                            .background(
                                selectedFilter == filter ? accent.opacity(0.9) : Color.white.opacity(0.055),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func recordPagination(
        page: LearningRecordPage,
        onSelectPage: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            paginationButton(
                icon: .chevronLeft,
                label: String(localized: "audio_agent_learning_previous_page"),
                isEnabled: page.resolvedPage > 0
            ) {
                onSelectPage(page.resolvedPage - 1)
            }

            Spacer(minLength: 0)

            Text(
                String(
                    format: String(localized: "audio_agent_learning_page_indicator"),
                    page.resolvedPage + 1,
                    page.pageCount
                )
            )
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.52))
            .monospacedDigit()

            Spacer(minLength: 0)

            paginationButton(
                icon: .chevronRight,
                label: String(localized: "audio_agent_learning_next_page"),
                isEnabled: page.resolvedPage + 1 < page.pageCount
            ) {
                onSelectPage(page.resolvedPage + 1)
            }
        }
        .padding(.vertical, 8)
    }

    private func paginationButton(
        icon: MonoIcon.IconType,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonoIcon(
                icon: icon,
                size: 13,
                color: isEnabled ? .white.opacity(0.78) : .white.opacity(0.22)
            )
            .frame(width: 38, height: 36)
            .background(Color.white.opacity(isEnabled ? 0.06 : 0.025), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var emptyRecords: some View {
        VStack(spacing: 10) {
            MonoIcon(icon: .history, size: 24, color: accent.opacity(0.85))
            Text(String(localized: "audio_agent_learning_empty_title"))
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
            Text(String(localized: "audio_agent_learning_empty_message"))
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.44))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    private func recordRow(
        _ record: AIEqualizerLearningRecord,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon: record.feedback.icon, size: 16, color: record.feedback.tint)
                .monoIconArtwork(record.feedback.monoGlyphSemantic.rawValue)
                .frame(width: 40, height: 40)
                .background(record.feedback.tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(record.displayTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    Text(record.feedback.localizedTitle)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(record.feedback.tint)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 20)
                        .background(record.feedback.tint.opacity(0.1), in: Capsule())
                }

                Text(record.secondaryText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)

                Text(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 5)
            MonoIcon(icon: .chevronRight, size: 11, color: .white.opacity(0.28))
        }
        .padding(.vertical, layout.isCompactHeight ? 11 : 13)
        .contentShape(Rectangle())
    }

    private func toggleRow(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        layout: MonoSoundCenterLayout
    ) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon: icon, size: 17, color: accent)
                .monoIconArtwork(artwork?.rawValue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
        .padding(.vertical, layout.isCompactHeight ? 11 : 13)
    }

    private func menuRow<MenuContent: View>(
        icon: MonoIcon.IconType,
        artwork: MonoGlyphSemantic? = nil,
        title: String,
        detail: String,
        value: String,
        layout: MonoSoundCenterLayout,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        Menu(content: menuContent) {
            HStack(spacing: 12) {
                MonoIcon(icon: icon, size: 17, color: accent)
                    .monoIconArtwork(artwork?.rawValue)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.82))
                    .multilineTextAlignment(.trailing)
                MonoIcon(icon: .chevronRight, size: 11, color: .white.opacity(0.3))
            }
            .padding(.vertical, layout.isCompactHeight ? 11 : 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func settingsSection<Content: View>(
        title: String,
        layout: MonoSoundCenterLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
            VStack(spacing: 0) { content() }
                .padding(.horizontal, layout.isCompactWidth ? 12 : 14)
                .background(sectionSurface)
        }
    }

    private var sectionSurface: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 34)
    }

    private var learningSummary: String {
        String(
            format: String(localized: "audio_agent_learning_summary"),
            agent.learningRecords.filter { $0.feedback == .positive }.count,
            agent.learningRecords.filter { $0.feedback == .negative }.count,
            agent.learningRecords.filter { $0.feedback == .manualEqualizer }.count,
            agent.learningRecords.filter { $0.feedback.isAutomatic }.count
        )
    }

    private var recordPageSnapshot: LearningRecordPage {
        let records = agent.learningRecords.filter(selectedFilter.includes)
        let pageCount = max(
            1,
            (records.count + Self.recordsPerPage - 1) / Self.recordsPerPage
        )
        let resolvedPage = min(max(0, recordPage), pageCount - 1)
        let start = resolvedPage * Self.recordsPerPage
        let end = min(start + Self.recordsPerPage, records.count)
        let visibleRecords = start < end ? Array(records[start..<end]) : []
        return LearningRecordPage(
            records: visibleRecords,
            resolvedPage: resolvedPage,
            pageCount: pageCount
        )
    }

    private var learningBackdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)

            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) { Color.clear }
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
}

private enum LearningRecordsAnchor {
    static let id = "mono-audio-learning-records"
}

private struct LearningRecordPage {
    let records: [AIEqualizerLearningRecord]
    let resolvedPage: Int
    let pageCount: Int
}

@MainActor
private struct MonoAudioLearningRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var player = CurrentSongPresentationModel.shared
    @StateObject private var agent = AIEqualizerAgent.shared
    @State private var showsDeleteConfirmation = false

    let recordID: UUID
    let accent: Color

    private var record: AIEqualizerLearningRecord? {
        agent.learningRecords.first { $0.id == recordID }
    }

    var body: some View {
        let viewportWidth = DeviceLayout.viewportWidth

        ZStack(alignment: .topLeading) {
            detailBackdrop

            if let record {
                List {
                    detailHeader(record)
                    summarySection(record)
                    contextSection(record)
                    parameterSection(record)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .frame(width: viewportWidth, alignment: .topLeading)
            } else {
                Text(String(localized: "audio_agent_learning_record_missing"))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(width: viewportWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: viewportWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .compatFontDesign(nil)
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .monoNavigationBackButton(iconColor: .white)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsDeleteConfirmation = true
                } label: {
                    MonoIcon(icon: .trash, size: 15, color: record == nil ? .white.opacity(0.25) : .red)
                        .frame(width: 44, height: 44)
                }
                .disabled(record == nil)
                .accessibilityLabel(String(localized: "audio_agent_learning_delete_record"))
            }
        }
        .alert(
            String(localized: "audio_agent_learning_delete_record_title"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "delete"), role: .destructive) {
                agent.deleteLearningRecord(id: recordID)
                dismiss()
            }
        } message: {
            Text(String(localized: "audio_agent_learning_delete_record_message"))
        }
    }

    private func detailHeader(_ record: AIEqualizerLearningRecord) -> some View {
        HStack(spacing: 14) {
            MonoIcon(icon: record.feedback.icon, size: 20, color: record.feedback.tint)
                .monoIconArtwork(record.feedback.monoGlyphSemantic.rawValue)
                .frame(width: 48, height: 48)
                .background(record.feedback.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.feedback.localizedTitle)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(record.feedback.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func summarySection(_ record: AIEqualizerLearningRecord) -> some View {
        Section {
            detailField(String(localized: "audio_agent_learning_record_artist"), record.artist)
            detailField(String(localized: "audio_agent_learning_record_source"), record.songIdentifier)
            detailField(String(localized: "audio_agent_learning_record_output"), record.displayOutput)
            detailField(
                String(localized: "audio_agent_learning_record_feedback"),
                record.feedback.localizedTitle
            )
            if record.feedback != .manualEqualizer {
                detailField(
                    String(localized: "audio_agent_learning_record_listened"),
                    record.listenedSeconds.localizedDuration
                )
            }
            detailField(
                String(localized: "audio_agent_learning_record_time"),
                record.recordedAt.formatted(date: .abbreviated, time: .shortened)
            )
        } header: {
            detailSectionHeader(String(localized: "audio_agent_learning_record_summary"))
        }
    }

    @ViewBuilder
    private func contextSection(_ record: AIEqualizerLearningRecord) -> some View {
        if !record.genreHints.isEmpty || !record.instrumentHints.isEmpty {
            Section {
                if !record.genreHints.isEmpty {
                    detailField(
                        String(localized: "audio_agent_learning_record_genres"),
                        record.genreHints.joined(separator: " · ")
                    )
                }
                if !record.instrumentHints.isEmpty {
                    detailField(
                        String(localized: "audio_agent_learning_record_instruments"),
                        record.instrumentHints.joined(separator: " · ")
                    )
                }
            } header: {
                detailSectionHeader(String(localized: "audio_agent_learning_record_context"))
            }
        }
    }

    private func parameterSection(_ record: AIEqualizerLearningRecord) -> some View {
        Section {
            equalizerGrid(
                String(localized: "audio_agent_learning_record_eq_curve"),
                labels: record.graphicEQMode.frequencyLabels,
                tint: .white.opacity(0.84),
                value: record.gainText(at:)
            )
            if record.feedback == .manualEqualizer {
                equalizerGrid(
                    String(localized: "audio_agent_learning_record_manual_offsets"),
                    labels: record.graphicEQMode.frequencyLabels,
                    tint: accent.opacity(0.9),
                    value: record.learnedAdjustmentText(at:)
                )
            } else {
                tuningParameterGrid(record)
            }
        } header: {
            detailSectionHeader(String(localized: "audio_agent_learning_record_parameters"))
        }
    }

    private func detailField(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(detailRowBackground)
        .listRowSeparatorTint(Color.white.opacity(0.07))
    }

    private func equalizerGrid(
        _ title: String,
        labels: [String],
        tint: Color,
        value: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            LazyVGrid(columns: equalizerColumns, spacing: 8) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    VStack(spacing: 4) {
                        Text(label)
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                        Text(value(index))
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(detailRowBackground)
        .listRowSeparatorTint(Color.white.opacity(0.07))
    }

    private func tuningParameterGrid(_ record: AIEqualizerLearningRecord) -> some View {
        let parameters = [
            (String(localized: "audio_agent_learning_record_bass"), record.bassGain.decibelText),
            (String(localized: "audio_agent_learning_record_treble"), record.trebleGain.decibelText),
            (String(localized: "audio_agent_learning_record_surround"), record.surroundLevel.decimalText),
            (String(localized: "audio_agent_learning_record_reverb"), record.reverbLevel.decimalText),
            (String(localized: "audio_agent_learning_record_width"), record.stereoWidth.decimalText),
            (String(localized: "audio_agent_learning_record_processing"), record.processingIntensity.decimalText)
        ]

        return LazyVGrid(columns: tuningColumns, spacing: 8) {
            ForEach(Array(parameters.enumerated()), id: \.offset) { _, parameter in
                VStack(alignment: .leading, spacing: 5) {
                    Text(parameter.0)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.44))
                    Text(parameter.1)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(detailRowBackground)
        .listRowSeparatorTint(Color.white.opacity(0.07))
    }

    private func detailSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white.opacity(0.58))
            .textCase(nil)
    }

    private var equalizerColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : (horizontalSizeClass == .regular ? 5 : 3)
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: count)
    }

    private var tuningColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (horizontalSizeClass == .regular ? 3 : 2)
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: count)
    }

    private var detailRowBackground: Color {
        Color.black.opacity(0.28)
    }

    private var detailBackdrop: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.048)
            if let url = player.currentSong?.coverUrl?.sized(720) {
                CachedAsyncImage(url: url) { Color.clear }
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
}

private enum LearningRecordFilter: String, CaseIterable, Identifiable {
    case all
    case positive
    case negative
    case manual
    case automatic

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return String(localized: "audio_agent_learning_filter_all")
        case .positive: return String(localized: "audio_agent_learning_filter_positive")
        case .negative: return String(localized: "audio_agent_learning_filter_negative")
        case .manual: return String(localized: "audio_agent_learning_filter_manual")
        case .automatic: return String(localized: "audio_agent_learning_filter_automatic")
        }
    }

    func includes(_ record: AIEqualizerLearningRecord) -> Bool {
        switch self {
        case .all: return true
        case .positive: return record.feedback == .positive
        case .negative: return record.feedback == .negative
        case .manual: return record.feedback == .manualEqualizer
        case .automatic: return record.feedback.isAutomatic
        }
    }
}

private extension AIEqualizerLearningStrength {
    var localizedTitle: String {
        switch self {
        case .cautious: return String(localized: "audio_agent_learning_strength_cautious")
        case .balanced: return String(localized: "audio_agent_learning_strength_balanced")
        case .responsive: return String(localized: "audio_agent_learning_strength_responsive")
        }
    }
}

private extension AIEqualizerLearningRetention {
    var localizedTitle: String {
        switch self {
        case .thirtyDays: return String(localized: "audio_agent_learning_retention_30")
        case .ninetyDays: return String(localized: "audio_agent_learning_retention_90")
        case .oneYear: return String(localized: "audio_agent_learning_retention_365")
        }
    }
}

private extension AIEqualizerLearningFeedback {
    var localizedTitle: String {
        switch self {
        case .positive: return String(localized: "audio_agent_learning_feedback_positive")
        case .negative: return String(localized: "audio_agent_learning_feedback_negative")
        case .retained: return String(localized: "audio_agent_learning_feedback_retained")
        case .reset: return String(localized: "audio_agent_learning_feedback_reset")
        case .regenerated: return String(localized: "audio_agent_learning_feedback_regenerated")
        case .manualEqualizer: return String(localized: "audio_agent_learning_feedback_manual_equalizer")
        }
    }

    var isAutomatic: Bool {
        self == .retained || self == .reset || self == .regenerated
    }

    var tint: Color {
        switch self {
        case .positive: return .green
        case .negative: return .orange
        case .retained: return .cyan
        case .reset: return .red
        case .regenerated: return .purple
        case .manualEqualizer: return .blue
        }
    }

    var icon: MonoIcon.IconType {
        switch self {
        case .positive: return .checkmark
        case .negative: return .heartSlash
        case .retained: return .playCircle
        case .reset: return .refresh
        case .regenerated: return .sparkle
        case .manualEqualizer: return .equalizer
        }
    }

    var monoGlyphSemantic: MonoGlyphSemantic {
        switch self {
        case .positive: return .learningFeedbackPositive
        case .negative: return .learningFeedbackNegative
        case .retained: return .learningFeedbackRetained
        case .reset: return .learningFeedbackReset
        case .regenerated: return .learningFeedbackRegenerated
        case .manualEqualizer: return .learningFeedbackManualEQ
        }
    }
}

private extension AIEqualizerLearningRecord {
    var displayTitle: String {
        guard let songTitle, !songTitle.isEmpty else {
            return String(localized: "audio_agent_learning_unknown_track")
        }
        return songTitle
    }

    var secondaryText: String {
        [artist, displayOutput]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var displayOutput: String {
        let baseIdentity = outputIdentity.split(separator: "|", maxSplits: 1).first.map(String.init)
            ?? outputIdentity
        let parts = baseIdentity.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 && !parts[1].isEmpty ? parts[1] : baseIdentity
    }

    func gainText(at index: Int) -> String {
        guard gains.indices.contains(index) else { return "—" }
        return gains[index].decibelText
    }

    func learnedAdjustmentText(at index: Int) -> String {
        guard learnedBandAdjustments.indices.contains(index) else { return "—" }
        return learnedBandAdjustments[index].decibelText
    }
}

private extension Float {
    var decibelText: String {
        String(format: "%+.1f dB", self)
    }

    var decimalText: String {
        String(format: "%.2f", self)
    }
}

private extension TimeInterval {
    var localizedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: max(0, self)) ?? "—"
    }
}
