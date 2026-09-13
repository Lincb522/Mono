import SwiftUI

struct FluxPlaybackIndicator: View {
    let isActive: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var levels = FluxAudioLevels.silence

    private var shouldSample: Bool {
        isActive && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            bar(levels.bass)
            bar(levels.mid)
            bar(levels.treble)
        }
        .frame(width: 10, height: 12)
        .foregroundStyle(color)
        .accessibilityHidden(true)
        .task(id: shouldSample) {
            levels = .silence
            guard shouldSample else { return }
            let analyzer = PlayerManager.shared.spectrumAnalyzer
            let pipe = AsyncStream<FluxAudioLevels>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = analyzer.addAnalysisObserver(minimumInterval: 1.0 / 15.0) { values, rate, rms in
                pipe.continuation.yield(FluxAudioLevels.measure(values, sampleRate: rate, rms: rms))
            }
            defer {
                analyzer.removeAnalysisObserver(token)
                pipe.continuation.finish()
            }
            for await next in pipe.stream {
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    levels = next
                }
            }
        }
    }

    private func bar(_ value: Double) -> some View {
        Capsule()
            .frame(width: 2, height: 2 + 10 * (shouldSample ? value : 0))
    }
}
