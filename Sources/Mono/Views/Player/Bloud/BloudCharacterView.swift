import SwiftUI

/// The player supplies touch coordinates; the character never owns transport gestures.
struct BloudCharacterView: View {
    var expression: BloudExpression = .calm
    var character: BloudCharacter = .bloud
    var isAnimating: Bool
    var bodyColor: Color
    var eyeColor: Color
    var featureColors: BloudFeatureColors? = nil
    var samplesAudio = false
    var gazePoint: CGPoint? = nil
    var cameraGaze: CGPoint? = nil
    var pawTouch: BloudPawTouch? = nil
    var pawExpression: PawExpression = .soft

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date()
    @State private var pausedAt: Date?
    @State private var suspendedDuration: TimeInterval = 0
    @State private var initialized = false
    @State private var isVisible = false
    @State private var oldPose = BloudExpression.calm.pose
    @State private var targetPose = BloudExpression.calm.pose
    @State private var poseDate = Date.distantPast
    @State private var gazeSpring = BloudGazeSpring()
    @State private var audioMotion = BloudAudioMotion()
    @State private var pawMotion = BloudPawMotion()
    @State private var oldPawPose = PawExpression.soft.pose
    @State private var targetPawPose = PawExpression.soft.pose
    @State private var pawPoseDate = Date.distantPast

    private var running: Bool { isVisible && isAnimating && !reduceMotion && scenePhase == .active }
    private var shouldSample: Bool { running && samplesAudio }
    private var ticking: Bool { running }

    // All animation integrators share a clock that excludes time spent off screen.
    private func motionDate(_ date: Date = Date()) -> Date {
        (pausedAt ?? date).addingTimeInterval(-suspendedDuration)
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !ticking)) { timeline in
                let date = motionDate(timeline.date)
                let t = date.timeIntervalSince(epoch)
                let pose = reduceMotion ? expression.pose : interpolatedPose(at: date)
                let gaze = reduceMotion ? gazeSpring.target : gazeSpring.sample(at: date.timeIntervalSinceReferenceDate).position
                Canvas { context, size in
                    draw(in: &context, size: size, pose: pose, gaze: gaze, time: t, date: date)
                }
            }
            .allowsHitTesting(false)
            .onAppear {
                follow(gazePoint, in: proxy.frame(in: .named("bloudPlayer")))
            }
            .onChange(of: gazePoint) { _, point in
                follow(point, in: proxy.frame(in: .named("bloudPlayer")))
            }
            .onChange(of: cameraGaze) { _, _ in
                follow(gazePoint, in: proxy.frame(in: .named("bloudPlayer")))
            }
            .onChange(of: proxy.frame(in: .named("bloudPlayer"))) { _, frame in
                follow(gazePoint, in: frame)
            }
            .onChange(of: expression) { _, _ in
                follow(gazePoint, in: proxy.frame(in: .named("bloudPlayer")))
            }
            .onChange(of: pawTouch) { previous, next in
                guard isAnimating, scenePhase == .active else { return }
                pawMotion.follow(next, at: motionDate().timeIntervalSinceReferenceDate)
                if previous == nil, next != nil { HapticManager.shared.soft() }
                follow(gazePoint, in: proxy.frame(in: .named("bloudPlayer")))
            }

        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(character.title))
        .accessibilityValue(Text(character.isAnimal ? pawExpression.title : expression.title))
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if character.isAnimal {
                Button("player_paw_pet") {
                    guard isAnimating, scenePhase == .active else { return }
                    let time = motionDate().timeIntervalSinceReferenceDate
                    pawMotion.follow(BloudPawTouch(origin: SIMD2(0, -0.5), location: SIMD2(0, -0.5), translation: .zero), at: time)
                    pawMotion.follow(nil, at: time)
                    HapticManager.shared.light()
                }
            }
        }
        .onAppear {
            if !initialized {
                initialized = true
                epoch = motionDate()
                oldPose = expression.pose
                targetPose = expression.pose
                oldPawPose = pawExpression.pose
                targetPawPose = pawExpression.pose
            }
            isVisible = true
            updateMotionClock(active: isAnimating && !reduceMotion && scenePhase == .active)
        }
        .onChange(of: expression) { _, next in
            oldPose = interpolatedPose(at: motionDate())
            targetPose = next.pose
            poseDate = motionDate()
        }
        .onChange(of: pawExpression) { _, next in
            oldPawPose = interpolatedPawPose(at: motionDate())
            targetPawPose = next.pose
            pawPoseDate = motionDate()
        }
        .onChange(of: running) { _, active in
            updateMotionClock(active: active)
        }
        .onDisappear {
            isVisible = false
            updateMotionClock(active: false)
        }
        .task(id: shouldSample) {
            guard shouldSample else { return }
            let analyzer = PlayerManager.shared.analysisSpectrumAnalyzer
            let pipe = AsyncStream<BloudAudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = analyzer.addAnalysisObserver(minimumInterval: 0.05) { values, rate, rms in
                if let frame = BloudAudioFrame.measure(values, rate: rate, rms: rms,
                                                       time: Date.timeIntervalSinceReferenceDate) {
                    pipe.continuation.yield(frame)
                }
            }
            defer {
                analyzer.removeAnalysisObserver(token)
                pipe.continuation.finish()
            }
            for await frame in pipe.stream {
                guard !Task.isCancelled else { break }
                audioMotion.ingest(BloudAudioFrame(time: motionDate().timeIntervalSinceReferenceDate,
                                                  rmsDB: frame.rmsDB, bass: frame.bass))
            }
        }
    }

    private func updateMotionClock(active: Bool) {
        let now = Date()
        if active {
            guard let pausedAt else { return }
            suspendedDuration += now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
            // Resume from the frozen pose and smoothly release stale contact.
            let time = motionDate(now).timeIntervalSinceReferenceDate
            pawMotion.follow(nil, at: time)
            gazeSpring.follow(.zero, at: time, returning: true)
        } else if pausedAt == nil {
            pausedAt = now
        }
    }

    private func interpolatedPose(at date: Date) -> BloudFacePose {
        let fraction = min(1, max(0, date.timeIntervalSince(poseDate) / 0.65))
        return oldPose.blended(to: targetPose, fraction: fraction * fraction * (3 - 2 * fraction))
    }

    private func interpolatedPawPose(at date: Date) -> PawFacePose {
        let fraction = min(1, max(0, date.timeIntervalSince(pawPoseDate) / 0.55))
        return oldPawPose.blended(to: targetPawPose, fraction: fraction * fraction * (3 - 2 * fraction))
    }

    private func follow(_ point: CGPoint?, in frame: CGRect) {
        guard isAnimating, scenePhase == .active else { return }
        let touching = pawTouch != nil || point != nil || cameraGaze != nil
        let target: SIMD2<Double>
        if let pawTouch {
            target = SIMD2(min(1, max(-1, pawTouch.location.x)) * 38,
                           -min(1, max(-1, pawTouch.location.y)) * 30)
        } else if let point {
            let half = max(1, min(frame.width, frame.height) / 2)
            let x = Double(min(1, max(-1, (point.x - frame.midX) / half)))
            let y = Double(min(1, max(-1, (point.y - frame.midY) / half)))
            target = SIMD2(x * 38 - (character == .bloud ? expression.pose.yaw : 0),
                           -y * 30 - (character == .bloud ? expression.pose.pitch : 0))
        } else if let cameraGaze {
            target = BloudCameraGaze.target(for: cameraGaze)
        } else {
            target = .zero
        }
        gazeSpring.follow(target, at: motionDate().timeIntervalSinceReferenceDate, returning: pawTouch == nil && point == nil && cameraGaze == nil)
        if touching { gazeSpring.response = 19 }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize,
                      pose: BloudFacePose, gaze: SIMD2<Double>, time: Double, date: Date) {
        let audioEyes = !reduceMotion
            ? audioMotion.eyeOpenness(at: date.timeIntervalSinceReferenceDate) : SIMD2<Double>(repeating: 1)
        let cat = character == .pawCat
        let blinkPeriod = cat ? 8.7 : 4.7
        let blinkDuration = cat ? 0.8 : 0.22
        let blinkPhase = time.truncatingRemainder(dividingBy: blinkPeriod)
        let restingLid = !reduceMotion && blinkPhase > blinkPeriod - blinkDuration
            ? pow(cos((blinkPhase - blinkPeriod + blinkDuration) / blinkDuration * .pi), 2) : 1
        let animalEyes = cat ? SIMD2(1 - max(0, 1 - audioEyes.x) * 0.2,
                                    1 - max(0, 1 - audioEyes.y) * 0.2) : audioEyes
        if character.isAnimal {
            BloudPawArtwork.draw(in: &context, size: size, pose: reduceMotion ? pawExpression.pose : interpolatedPawPose(at: date),
                                 gaze: reduceMotion ? .zero : gaze,
                                 openness: animalEyes * restingLid, fur: bodyColor, eyeInk: eyeColor,
                                 isCat: character == .pawCat, colors: featureColors,
                                 motion: pawMotion.sample(at: date.timeIntervalSinceReferenceDate,
                                                          idleTime: reduceMotion ? nil : time, expression: pawExpression,
                                                          reducedMotion: reduceMotion, isCat: cat))
            return
        }
        let radius = min(size.width, size.height) * 0.445
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(bodyColor))
        context.clip(to: circle)
        var face = pose
        // Only gaze changes head direction. Music affects eyelids, never the round body.
        face.yaw = min(48, max(-48, pose.yaw + gaze.x))
        face.pitch = min(38, max(-38, pose.pitch + gaze.y))
        for (index, eye) in [face.left, face.right].enumerated() {
            let projection = BloudEyeProjection.project(pose: face, side: index == 0 ? -1 : 1)
            guard projection.depth > 0.02 else { continue }
            let width = eye.width * radius
            let height = eye.height * radius
            let local = Path(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                             cornerRadius: min(width, height) / 2, style: .circular)
            let phi = eye.tilt * .pi / 180
            let c = cos(phi), s = sin(phi)
            let blink = 0.06 + 0.94 * restingLid * audioEyes[index] * eye.open
            let matrix = CGAffineTransform(
                a: projection.a * c + projection.c * s,
                b: (projection.b * c + projection.d * s) * blink,
                c: -projection.a * s + projection.c * c,
                d: (-projection.b * s + projection.d * c) * blink,
                tx: center.x + projection.x * radius,
                ty: center.y + projection.y * radius
            )
            context.fill(local.applying(matrix), with: .color(eyeColor))
        }
    }
}

/// Orthographic tangent frames keep eyes attached to the round head as it turns.
private enum BloudEyeProjection {
    struct Projection {
        let x: Double, y: Double, a: Double, b: Double, c: Double, d: Double, depth: Double
    }

    static func project(pose: BloudFacePose, side: Double) -> Projection {
        func spin(_ u: SIMD3<Double>, _ v: SIMD3<Double>, _ degrees: Double) -> (SIMD3<Double>, SIMD3<Double>) {
            let angle = degrees * .pi / 180
            return (u * cos(angle) + v * sin(angle), v * cos(angle) - u * sin(angle))
        }
        var forward = SIMD3<Double>(0, 0, 1)
        var right = SIMD3<Double>(1, 0, 0)
        var down = SIMD3<Double>(0, 1, 0)
        (forward, right) = spin(forward, right, pose.yaw)
        (down, forward) = spin(down, forward, pose.pitch)
        (right, down) = spin(right, down, pose.roll)
        let (normal, tangent) = spin(forward, right, pose.split * side)
        return .init(x: normal.x, y: normal.y, a: tangent.x, b: tangent.y,
                     c: down.x, d: down.y, depth: normal.z)
    }
}
