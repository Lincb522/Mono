import SwiftUI

/// Only this thin orbit subscribes to playback time; the face has its own clock.
struct BloudProgressOrbit: View {
    let ink: Color
    let accent: Color
    let enabled: Bool
    @ObservedObject private var time = PlaybackTimePublisher.shared
    @State private var pending: Double?

    private var duration: Double { time.duration.isFinite ? max(0, time.duration) : 0 }
    private var progress: Double {
        if let pending { return pending }
        guard duration > 0, time.currentTime.isFinite else { return 0 }
        return min(1, max(0, time.currentTime / duration))
    }

    var body: some View {
        GeometryReader { proxy in
            let radius = max(1, min(proxy.size.width, proxy.size.height) / 2 - 22)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let angle = progress * .pi * 2 - .pi / 2
            ZStack {
                Circle().stroke(ink.opacity(0.15), lineWidth: 1)
                Circle().trim(from: 0, to: progress)
                    .stroke(ink, style: StrokeStyle(lineWidth: pending == nil ? 2 : 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(22)
            .overlay {
                Circle().fill(accent)
                    .overlay(Circle().stroke(ink, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    .allowsHitTesting(false)
            }
            .contentShape(BloudOrbitHitShape(), eoFill: true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled, duration > 0 else { return }
                        var angle = atan2(value.location.y - center.y, value.location.x - center.x) + .pi / 2
                        if angle < 0 { angle += .pi * 2 }
                        pending = min(1, max(0, angle / (.pi * 2)))
                    }
                    .onEnded { _ in
                        if let pending, enabled, duration > 0 {
                            PlayerManager.shared.seek(to: pending * duration)
                        }
                        pending = nil
                    }
            )
            .allowsHitTesting(enabled && duration > 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("player_bloud_seek"))
            .accessibilityValue(Text(BloudTrackTime.format(progress * duration)))
            .accessibilityAdjustableAction { direction in
                guard enabled, duration > 0 else { return }
                let delta: Double = direction == .increment ? 5 : -5
                PlayerManager.shared.seek(to: min(duration, max(0, progress * duration + delta)))
            }
        }
        .onChange(of: enabled) { _, _ in pending = nil }
    }
}

private struct BloudOrbitHitShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addEllipse(in: rect.insetBy(dx: 44, dy: 44))
        return path
    }
}

struct BloudTrackTime: View {
    let ink: Color
    let secondary: Color
    @ObservedObject private var time = PlaybackTimePublisher.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.format(time.currentTime)).foregroundStyle(ink)
            Text("/").accessibilityHidden(true)
            Text(Self.format(time.duration))
        }
        .font(.system(.subheadline, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(secondary)
        .accessibilityElement(children: .combine)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
