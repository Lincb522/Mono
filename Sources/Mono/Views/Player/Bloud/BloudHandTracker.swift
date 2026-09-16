import AVFoundation
import SwiftUI
import Vision

/// Camera gaze is optional; touch remains the higher-priority input in the player.
@MainActor
final class BloudHandTracker: ObservableObject {
    @Published private(set) var point: CGPoint?
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var failure: BloudCameraFailure?
    private var capture: BloudHandCapture?
    private var orientation: AVCaptureVideoOrientation = .portrait
    private var generation = UUID()

    var isAuthorized: Bool { authorization == .authorized }
    var needsSettings: Bool { authorization == .denied || authorization == .restricted }

    func refreshAuthorization() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAuthorization() async {
        refreshAuthorization()
        guard authorization == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        refreshAuthorization()
    }

    func updateOrientation(_ value: UIInterfaceOrientation) {
        let next: AVCaptureVideoOrientation
        switch value {
        case .portrait: next = .portrait
        case .portraitUpsideDown: next = .portraitUpsideDown
        case .landscapeLeft: next = .landscapeLeft
        case .landscapeRight: next = .landscapeRight
        default: return
        }
        guard next != orientation else { return }
        orientation = next
        capture?.updateOrientation(next)
    }

    func stop() {
        generation = UUID()
        capture?.stop()
        capture = nil
        point = nil
    }

    func track(active: Bool) async {
        guard !Task.isCancelled else { return }
        let token = UUID()
        generation = token
        capture?.stop()
        capture = nil
        point = nil
        guard active, isAuthorized, !Task.isCancelled else { return }
        let camera = BloudHandCapture()
        capture = camera
        camera.start(orientation: orientation)
        defer {
            camera.stop()
            if generation == token {
                capture = nil
                point = nil
            }
        }
        for await event in camera.events {
            guard !Task.isCancelled, generation == token else { break }
            switch event {
            case .point(let next):
                if failure != nil { failure = nil }
                if point != next { point = next }
            case .failed(let reason):
                failure = reason
                point = nil
            }
        }
    }
}

enum BloudCameraFailure: String, Sendable {
    case unavailable = "player_bloud_camera_unavailable"
    case failed = "player_bloud_camera_failed"
    case interrupted = "player_bloud_camera_interrupted"
}

/// Vision receives already rotated, mirrored pixels; only its bottom-left origin needs conversion.
struct BloudHandFocus {
    private var lastPoint: CGPoint?
    private var lastSeen: TimeInterval = -.infinity

    mutating func update(visionPoint: CGPoint?, confidence: Float, at time: TimeInterval) -> CGPoint? {
        if let visionPoint, confidence >= 0.35,
           visionPoint.x.isFinite, visionPoint.y.isFinite {
            let next = CGPoint(x: min(1, max(0, visionPoint.x)), y: min(1, max(0, 1 - visionPoint.y)))
            lastSeen = time
            if let lastPoint, hypot(next.x - lastPoint.x, next.y - lastPoint.y) < 0.0015 {
                return lastPoint
            }
            lastPoint = next
        } else if time - lastSeen > 0.45 {
            lastPoint = nil
        }
        return lastPoint
    }
}

/// All capture, Vision, and focus state is confined to queue, including delegate callbacks.
/// Only immutable Sendable events cross to the main actor; pixels are never retained or exported.
private final class BloudHandCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case point(CGPoint?)
        case failed(BloudCameraFailure)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    // Start/stop across replacement captures share an ordering boundary.
    private static let captureQueue = DispatchQueue(label: "mono.bloud.hand-camera", qos: .userInitiated)
    private let queue = BloudHandCapture.captureQueue
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanHandPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private var activeTip: VNHumanHandPoseObservation.JointName?
    private var lastHandSeen: TimeInterval = -.infinity
    private var lastFaceTime: TimeInterval = -.infinity
    private var facePoint: CGPoint?
    private var faceConfidence: Float = 0
    private var notificationTokens: [NSObjectProtocol] = []
    private var focus = BloudHandFocus()
    private var lastFrameTime: TimeInterval = -.infinity
    private var delivering = false

    override init() {
        let pipe = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pipe.stream
        continuation = pipe.continuation
        super.init()
    }

    func start(orientation: AVCaptureVideoOrientation) {
        queue.async { [self] in
            do {
                try configure(orientation: orientation)
                delivering = true
                observeSession()
                session.startRunning()
                if !session.isRunning { fail(.failed) }
            } catch ConfigurationFailure.noFrontCamera {
                fail(.unavailable)
            } catch {
                fail(.failed)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            delivering = false
            output.setSampleBufferDelegate(nil, queue: nil)
            for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
            notificationTokens.removeAll()
            if session.isRunning { session.stopRunning() }
            continuation.finish()
        }
    }

    func updateOrientation(_ orientation: AVCaptureVideoOrientation) {
        queue.async { [self] in
            applyOrientation(orientation)
            focus = BloudHandFocus()
            activeTip = nil
            lastHandSeen = -.infinity
            lastFaceTime = -.infinity
            facePoint = nil
            continuation.yield(.point(nil))
        }
    }

    private func configure(orientation: AVCaptureVideoOrientation) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw ConfigurationFailure.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        guard session.canSetSessionPreset(.vga640x480) else { throw ConfigurationFailure.unsupportedSession }
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw ConfigurationFailure.unsupportedSession
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        request.maximumHandCount = 1
        applyOrientation(orientation)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
    }

    private func applyOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func observeSession() {
        for (name, failure) in [
            (AVCaptureSession.runtimeErrorNotification, BloudCameraFailure.failed),
            (AVCaptureSession.wasInterruptedNotification, BloudCameraFailure.interrupted)
        ] {
            let token = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    guard delivering else { return }
                    fail(failure)
                }
            }
            notificationTokens.append(token)
        }
    }

    private func fail(_ reason: BloudCameraFailure) {
        delivering = false
        continuation.yield(.failed(reason))
        continuation.finish()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard delivering else { return }
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastFrameTime >= 1.0 / 35.0 else { return }
        lastFrameTime = time
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
            try handler.perform([request])
            let hand = try handTarget(request.results?.first)
            let next: CGPoint?
            if let hand {
                lastHandSeen = time
                next = focus.update(visionPoint: hand.location, confidence: hand.confidence, at: time)
            } else if time - lastHandSeen < 0.18 {
                next = focus.update(visionPoint: nil, confidence: 0, at: time)
            } else {
                if time - lastFaceTime >= 1.0 / 15.0 {
                    try handler.perform([faceRequest])
                    lastFaceTime = time
                    let face = faceRequest.results?.max { a, b in
                        a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
                    }
                    facePoint = face.map(Self.faceTarget)
                    faceConfidence = face?.confidence ?? 0
                }
                next = focus.update(visionPoint: facePoint, confidence: faceConfidence, at: time)
            }
            continuation.yield(.point(next))
        } catch {
            fail(.failed)
        }
    }

    private func handTarget(_ hand: VNHumanHandPoseObservation?) throws -> VNRecognizedPoint? {
        guard let hand else { activeTip = nil; return nil }
        let pairs: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexMCP), (.middleTip, .middleMCP), (.thumbTip, .thumbMP),
            (.ringTip, .ringMCP), (.littleTip, .littleMCP)
        ]
        var best: (name: VNHumanHandPoseObservation.JointName, point: VNRecognizedPoint, score: Double)?
        for (tipName, baseName) in pairs {
            let tip = try hand.recognizedPoint(tipName)
            guard tip.confidence >= 0.35 else { continue }
            let base = try hand.recognizedPoint(baseName)
            let reach = base.confidence >= 0.3 ? hypot(tip.location.x - base.location.x, tip.location.y - base.location.y) : 0.04
            let continuity = tipName == activeTip ? 1.2 : 1.0
            let score = Double(reach) * Double(tip.confidence) * continuity
            if best == nil || score > (best?.score ?? 0) { best = (tipName, tip, score) }
        }
        if let best { activeTip = best.name; return best.point }
        activeTip = nil
        let palm = try hand.recognizedPoint(.middleMCP)
        return palm.confidence >= 0.45 ? palm : nil
    }

    private static func faceTarget(_ face: VNFaceObservation) -> CGPoint {
        let eyes = [face.landmarks?.leftEye, face.landmarks?.rightEye].compactMap { $0 }
        let points = eyes.flatMap { Array($0.normalizedPoints) }
        let center: CGPoint
        if points.isEmpty {
            center = CGPoint(x: 0.5, y: 0.65)
        } else {
            center = CGPoint(x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
                             y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count))
        }
        return CGPoint(x: face.boundingBox.minX + center.x * face.boundingBox.width,
                       y: face.boundingBox.minY + center.y * face.boundingBox.height)
    }

    private enum ConfigurationFailure: Error {
        case noFrontCamera
        case unsupportedSession
    }
}
