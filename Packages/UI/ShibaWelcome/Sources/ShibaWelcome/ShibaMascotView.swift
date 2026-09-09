import SwiftUI

/// A complete character image with continuous head, neck and body deformation.
/// Plays once on appearance. Change `action` or increment `replayToken` to replay.
@MainActor
public struct ShibaMascotView: View {
    public var action: ShibaAction
    public var replayToken: Int
    private let onCompletion: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playback = ShibaPlayback()
    @State private var isVisible = false

    public init(
        action: ShibaAction = .welcome,
        replayToken: Int = 0,
        onCompletion: @escaping () -> Void = {}
    ) {
        self.action = action
        self.replayToken = replayToken
        self.onCompletion = onCompletion
    }

    private var usesStaticPose: Bool {
        if #available(iOS 17.0, macOS 14.0, *) { return reduceMotion }
        return true
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playback.isRunning)) { _ in
            let elapsed = usesStaticPose
                ? action.duration
                : playback.elapsed(at: ProcessInfo.processInfo.systemUptime, duration: action.duration)
            let pose = ShibaMotion.pose(for: action, at: elapsed)

            GeometryReader { geometry in
                let side = max(1, min(geometry.size.width, geometry.size.height))
                character(side: side, pose: pose)
                    .scaleEffect(
                        CGFloat(pose.scale),
                        anchor: UnitPoint(x: 0.5, y: 0.91)
                    )
                    .offset(y: side * CGFloat(pose.offsetY))
                    .opacity(Double(pose.opacity))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .onChange(of: elapsed >= action.duration) { ended in
                // A replay may have started since this frame was evaluated.
                let current = playback.elapsed(
                    at: ProcessInfo.processInfo.systemUptime,
                    duration: action.duration
                )
                if ended && current >= action.duration {
                    complete()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小柴犬")
        .accessibilityAddTraits(.isImage)
        .onAppear {
            isVisible = true
            restart()
        }
        .onDisappear {
            isVisible = false
            playback.pause(at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: action) { _ in restart() }
        .onChange(of: replayToken) { _ in restart() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && isVisible && !usesStaticPose {
                playback.resume(at: ProcessInfo.processInfo.systemUptime)
            } else {
                playback.pause(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        .onChange(of: reduceMotion) { enabled in
            if enabled { complete() }
        }
    }

    private func restart() {
        if usesStaticPose {
            playback.restart(at: ProcessInfo.processInfo.systemUptime, running: false)
            complete()
        } else {
            playback.restart(
                at: ProcessInfo.processInfo.systemUptime,
                running: isVisible && scenePhase == .active
            )
        }
    }

    private func complete() {
        guard !playback.isFinished else { return }
        playback.finish(duration: action.duration)
        onCompletion()
    }

    @ViewBuilder
    private func character(side: CGFloat, pose: ShibaPose) -> some View {
        let image = Image("ShibaCharacter", bundle: .module)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
        if #available(iOS 17.0, macOS 14.0, *) {
            image.distortionEffect(
                shader(side: side, pose: pose),
                maxSampleOffset: CGSize(width: side * 0.16, height: side * 0.16),
                isEnabled: !usesStaticPose
            )
        } else {
            image
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func shader(side: CGFloat, pose: ShibaPose) -> Shader {
        Shader(
            function: ShaderFunction(library: .bundle(.module), name: "shibaDeform"),
            arguments: [
                .float2(Float(side), Float(side)),
                .float(pose.tilt),
                .float(pose.nod),
                .float(pose.breath),
                .float(pose.blink),
                .float(pose.tail)
            ]
        )
    }
}
