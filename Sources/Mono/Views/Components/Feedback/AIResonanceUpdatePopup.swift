import SwiftUI

struct AIResonanceUpdatePopupHost: View {
    let isReady: Bool
    @ObservedObject private var updates = AIResonanceUpdateStore.shared
    @ObservedObject private var services = AITuningServiceStore.shared
    @ObservedObject private var providers = AIProviderConfigurationStore.shared
    @ObservedObject private var changelog = ChangelogManager.shared
    @ObservedObject private var announcements = AnnouncementCenter.shared
    @ObservedObject private var reports = ListeningReportCenter.shared
    @ObservedObject private var greetings = SpecialGreetingManager.shared
    @ObservedObject private var alerts = AlertManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retryID = UUID()

    private var canPresent: Bool {
        isReady && scenePhase == .active && changelog.pendingRelease == nil
            && announcements.pendingAnnouncement == nil && reports.pending == nil
            && greetings.pending == nil && !alerts.isPresented
    }

    private var refreshKey: String {
        let model = try? providers.distributedResonanceModel()
        return "\(isReady):\(scenePhase == .active):\(services.settings.isEnabled):\(services.settings.service.rawValue):\(model?.distributionIdentity ?? "offline"):\(providers.remoteLastFetchedAt?.timeIntervalSince1970 ?? 0):\(retryID)"
    }

    private var displayedNotice: AIResonanceNotice? {
        updates.previewNotice ?? updates.notice
    }

    var body: some View {
        ZStack {
            if canPresent, let notice = displayedNotice {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { updates.dismissNotice() }
                    .accessibilityHidden(true)
                    .transition(.opacity)

                AIResonanceUpdatePopup(
                    notice: notice,
                    onEnable: { updates.answerIntroduction(enable: true) },
                    onDismiss: { updates.dismissNotice() },
                    onRetry: {
                        let isPreview = updates.previewNotice != nil
                        updates.dismissNotice()
                        if !isPreview { retryID = UUID() }
                    }
                )
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
            }
        }
            .animation(
                reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.86),
                value: canPresent ? displayedNotice?.id : nil
            )
            .task(id: isReady && scenePhase == .active) {
                guard isReady, scenePhase == .active else { return }
                // Check for newly published models while the app remains in the foreground.
                while !Task.isCancelled {
                    await providers.refreshRemoteConfigurationIfNeeded(force: true)
                    do { try await Task.sleep(for: .seconds(15 * 60)) }
                    catch { return }
                }
            }
            .task(id: refreshKey) {
                guard isReady, scenePhase == .active else { return }
                await updates.synchronize(remote: try? providers.distributedResonanceModel())
            }
    }
}

struct AIResonanceUpdatePopup: View {
    let notice: AIResonanceNotice
    let onEnable: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var titleSize = 24.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 13.5
    @ScaledMetric(relativeTo: .body) private var buttonSize = 15.5
    @ScaledMetric(relativeTo: .caption) private var versionSize = 12.5
    @ScaledMetric(relativeTo: .caption2) private var metadataSize = 11.0

    private var title: String {
        switch notice.kind {
        case .introduction: return String(localized: "ai_resonance_introduction_title")
        case .updated: return String(localized: "ai_resonance_updated_title")
        case .failed: return String(localized: "ai_resonance_update_failed_title")
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(0, proxy.size.height - 32)
            let scrollsHeader = dynamicTypeSize.isAccessibilitySize || availableHeight < 460

            VStack(spacing: 0) {
                if !scrollsHeader { header }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if scrollsHeader { header }
                        content
                            .padding(.horizontal, 22)
                            .padding(.top, 4)
                            .padding(.bottom, 22)
                    }
                }
                .frame(maxHeight: scrollsHeader ? nil : min(420, availableHeight * 0.46))
                .mask(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                    }
                }

                footer
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 348, maxHeight: scrollsHeader ? availableHeight : nil)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.5), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.28), radius: 40, x: 0, y: 18)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onDismiss)
        }
        .tint(.monoAccent)
        .onAppear { titleFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    MonoIcon(icon: notice.kind == .failed ? .warning : .waveform, size: 11, color: .monoAccent)
                        .accessibilityHidden(true)
                    Text(verbatim: "Resonance")
                        .font(.system(size: metadataSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.monoTextPrimary)
                }
                .foregroundStyle(Color.monoAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(Color.monoAccent.opacity(0.14))
                        .overlay { Capsule().stroke(Color.monoAccent.opacity(0.3), lineWidth: 0.8) }
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    MonoIcon(icon: .close, size: 11, color: .monoTextSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.monoSeparator.opacity(0.4)))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: reduceMotion ? 1 : 0.88))
                .accessibilityLabel(String(localized: "common_close"))
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.monoTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(String(format: String(localized: "ai_lab_service_version_format"),
                            AudioTrainingModelPresentation.versionText(notice.model.version)))
                    .font(.system(size: versionSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.monoTextSecondary)
                if let release = notice.model.release {
                    Text(String(format: String(localized: "ai_resonance_published_at"), release.publicationDateText))
                        .font(.system(size: metadataSize, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.monoTextSecondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.monoAccent.opacity(colorScheme == .dark ? 0.34 : 0.2), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                if !reduceTransparency {
                    Circle()
                        .fill(Color.monoAccent.opacity(colorScheme == .dark ? 0.3 : 0.18))
                        .frame(width: 130, height: 130)
                        .blur(radius: 46)
                        .offset(x: -30, y: -58)
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch notice.kind {
            case .introduction:
                Text(String(localized: "ai_resonance_introduction_body"))
                information(String(localized: "ai_resonance_availability_title"),
                            String(localized: "ai_resonance_availability_notice"))
                information(String(localized: "ai_resonance_training_title"),
                            String(localized: "ai_resonance_training_notice"))
            case .updated:
                let notes = notice.model.release?.notes ?? notice.model.release?.changelog
                    ?? String(localized: "audio_training_release_notes_empty")
                ForEach(ChangelogNotesParser.parse(notes)) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = section.title { sectionHeading(title) }
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(Color.monoAccent.opacity(0.85))
                                    .frame(width: 4.5, height: 4.5)
                                    .padding(.top, 6.5)
                                    .accessibilityHidden(true)
                                Text(item).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            case .failed:
                Text(String(localized: "ai_resonance_update_failed_body"))
                if let message = notice.message { Text(message).foregroundStyle(Color.monoTextSecondary) }
            }
        }
        .font(.system(size: bodySize, weight: .regular, design: .rounded))
        .foregroundStyle(Color.monoTextPrimary.opacity(0.84))
        .lineSpacing(3.5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func information(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(title)
            Text(text)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.monoAccent)
                .frame(width: 4, height: 13)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: bodySize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.monoTextPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if notice.kind == .introduction {
                action(String(localized: "ai_resonance_enable"), prominent: true, onEnable)
                action(String(localized: "ai_resonance_keep_service"), prominent: false, onDismiss)
            } else if notice.kind == .failed {
                action(String(localized: "ai_resonance_retry"), prominent: true, onRetry)
                action(String(localized: "common_ok"), prominent: false, onDismiss)
            } else {
                action(String(localized: "common_ok"), prominent: true, onDismiss)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func action(_ title: String, prominent: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: buttonSize, weight: prominent ? .bold : .medium, design: .rounded))
                .foregroundStyle(prominent ? Color.monoAccentForeground : Color.monoTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: prominent ? 48 : 44)
                .background {
                    if prominent {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.monoAccent)
                    }
                }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: reduceMotion ? 1 : 0.97))
    }

    private var cardBackground: some View {
        ZStack {
            if reduceTransparency {
                Color.monoBackground
            } else {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(Color.monoGlassTint.opacity(0.5))
            }
        }
    }
}
