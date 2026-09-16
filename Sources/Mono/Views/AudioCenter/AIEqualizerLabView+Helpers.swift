import SwiftUI
import FFmpegSwiftSDK

extension AIEqualizerLabView {
    func erasedSection(title: String, content: AnyView) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.56))
                content
            }
        )
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(MonoSoundCenterStyle.surface)
    }

    var backdrop: some View {
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

    func refreshCoverAccent() {
        coverColors.extract(from: player.currentSong?.coverUrl?.sized(200).absoluteString)
    }

    func primaryAnalysisAction() {
        selectedWorkspace = .tuning
        agent.phase.isWorking ? agent.cancelAnalysis() : agent.analyzeCurrentSong()
    }

    func frequencyText(_ frequency: Float) -> String {
        frequency >= 1_000
            ? String(format: "%.2f kHz", frequency / 1_000)
            : String(format: "%.0f Hz", frequency)
    }

    func compactElapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func tuningDurationText(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "—" }
        if duration < 0.001 {
            return String(localized: "ai_tuning_less_than_millisecond")
        }
        if duration < 1 {
            return String(
                format: String(localized: "ai_tuning_milliseconds_format"),
                Int(ceil(duration * 1_000))
            )
        }
        let totalSeconds = max(0, Int(duration.rounded()))
        guard totalSeconds >= 60 else {
            return String(
                format: String(localized: "ai_tuning_seconds_format"),
                totalSeconds
            )
        }
        return String(
            format: String(localized: "ai_tuning_minutes_seconds_format"),
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}
