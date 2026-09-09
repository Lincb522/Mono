import AVFoundation
@preconcurrency import Combine
@preconcurrency import CoreMotion
import FFmpegSwiftSDK
import Foundation

enum AirPodsDeviceModel: String, CaseIterable, Identifiable, Sendable {
    case airPods2
    case airPods3
    case airPods4
    case airPodsPro1
    case airPodsPro2
    case airPodsPro3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airPods2: "AirPods 2"
        case .airPods3: "AirPods 3"
        case .airPods4: "AirPods 4"
        case .airPodsPro1: "AirPods Pro 1"
        case .airPodsPro2: "AirPods Pro 2"
        case .airPodsPro3: "AirPods Pro 3"
        }
    }

    var subtitle: String {
        switch self {
        case .airPods2: String(localized: "airpods_model_2_desc")
        case .airPods3: String(localized: "airpods_model_3_desc")
        case .airPods4: String(localized: "airpods_model_4_desc")
        case .airPodsPro1: String(localized: "airpods_model_pro1_desc")
        case .airPodsPro2: String(localized: "airpods_model_pro2_desc")
        case .airPodsPro3: String(localized: "airpods_model_pro3_desc")
        }
    }

    /// Conservative Mono listening baselines, not manufacturer measurement
    /// claims. Values follow the app's fixed 10-band order and remain small so
    /// per-track analysis keeps authority over the final result.
    private var referenceGainsDB: [Float] {
        switch self {
        case .airPods2:
            return [1.15, 0.85, 0.35, -0.20, -0.25, 0.05, 0.30, 0.35, -0.15, 0.30]
        case .airPods3:
            return [0.80, 0.55, 0.15, -0.20, -0.15, 0.05, 0.20, -0.30, -0.10, 0.25]
        case .airPods4:
            return [0.55, 0.30, 0.05, -0.15, -0.10, 0.05, 0.15, -0.20, 0.10, 0.20]
        case .airPodsPro1:
            return [-0.25, -0.20, -0.10, 0.05, 0.10, 0.15, 0.35, 0.20, 0.20, 0.15]
        case .airPodsPro2:
            return [-0.20, -0.15, -0.05, 0.05, 0.10, 0.12, 0.18, -0.10, 0.15, 0.15]
        case .airPodsPro3:
            return [-0.12, -0.10, -0.05, 0.03, 0.08, 0.10, 0.15, -0.08, 0.12, 0.12]
        }
    }

    var aiTuningTarget: AIEqualizerDeviceTuningTarget {
        let fit: String
        let spatial: String
        switch self {
        case .airPods2:
            fit = "open-fit earbuds with limited acoustic seal"
            spatial = "Keep the center stable and use restrained width; do not compensate seal variation with excessive sub-bass."
        case .airPods3:
            fit = "open-fit earbuds with spatial-audio capability"
            spatial = "Use moderate stage width and preserve center focus; keep ambience controlled for an open fit."
        case .airPods4:
            fit = "current-generation open-fit earbuds"
            spatial = "Prefer a coherent front stage with moderate depth and avoid excessive high-frequency spatial energy."
        case .airPodsPro1:
            fit = "sealed in-ear earbuds with active noise control"
            spatial = "Keep bass centered, preserve vocal presence, and use conservative ambience behind the sealed presentation."
        case .airPodsPro2:
            fit = "sealed in-ear earbuds with active noise control and strong spatial capability"
            spatial = "Use precise center anchoring and controlled width; avoid stacking low-frequency lift with the device baseline."
        case .airPodsPro3:
            fit = "latest-generation sealed in-ear earbuds with active noise control"
            spatial = "Favor minimal correction, stable center imaging, and measured depth; preserve the device's existing balance."
        }
        return AIEqualizerDeviceTuningTarget(
            identifier: "airpods:\(rawValue):baseline-v1",
            displayName: title,
            fitDescription: fit,
            referenceGainsDB: referenceGainsDB,
            spatialGuidance: spatial
        )
    }
}

enum AirPodsListeningProfile: String, CaseIterable, Identifiable, Sendable {
    case natural
    case immersive
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: String(localized: "airpods_profile_natural")
        case .immersive: String(localized: "airpods_profile_immersive")
        case .focus: String(localized: "airpods_profile_focus")
        }
    }

    var subtitle: String {
        switch self {
        case .natural: String(localized: "airpods_profile_natural_desc")
        case .immersive: String(localized: "airpods_profile_immersive_desc")
        case .focus: String(localized: "airpods_profile_focus_desc")
        }
    }
}

enum AirPodsMotionState: String, Sendable {
    case unavailable
    case stationary
    case walking
    case running
    case unknown

    var title: String {
        switch self {
        case .unavailable: String(localized: "airpods_motion_unavailable")
        case .stationary: String(localized: "airpods_motion_stationary")
        case .walking: String(localized: "airpods_motion_walking")
        case .running: String(localized: "airpods_motion_running")
        case .unknown: String(localized: "airpods_motion_unknown")
        }
    }
}

struct AirPodsConnectionSnapshot: Equatable, Sendable {
    var isConnected = false
    var deviceName = ""
    var supportsHeadTracking = false
    var systemSpatialAudioEnabled = false

    static let disconnected = AirPodsConnectionSnapshot()
}

/// AirPods-only orchestration around public AVAudioSession and Core Motion APIs.
/// It never attempts to read battery, ear-detection, noise-control, or other
/// private accessory state that iOS doesn't expose to third-party apps.
@MainActor
final class AirPodsExperienceManager: ObservableObject {
    static let shared = AirPodsExperienceManager()

    @Published private(set) var connection: AirPodsConnectionSnapshot = .disconnected
    @Published private(set) var motionState: AirPodsMotionState = .unavailable
    @Published private(set) var isEnabled: Bool
    @Published private(set) var autoApplyOnConnect: Bool
    @Published private(set) var adaptsToMotion: Bool
    @Published private(set) var selectedProfile: AirPodsListeningProfile
    @Published private(set) var selectedDeviceModel: AirPodsDeviceModel
    @Published private(set) var modelAwareAITuningEnabled: Bool

    private enum StorageKey {
        static let enabled = "airpodsExperience.enabled"
        static let autoApply = "airpodsExperience.autoApply"
        static let adaptiveMotion = "airpodsExperience.adaptiveMotion"
        static let profile = "airpodsExperience.profile"
        static let deviceModel = "airpodsExperience.deviceModel"
        static let modelAwareAITuning = "airpodsExperience.modelAwareAITuning"
    }

    private let defaults: UserDefaults
    private let motionProbe = CMHeadphoneMotionManager()
    private let activityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Mono.AirPods.activity"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var routeObserver: NSObjectProtocol?
    private var spatialObserver: NSObjectProtocol?
    private var activityRuntime: AnyObject?
    private var activityOutputUID: String?
    private var activitySessionID = 0
    private var pendingMotionState: AirPodsMotionState?
    private var motionTransitionTask: Task<Void, Never>?
    private var runtimeReady = false
    private var experienceApplied = false
    private var baselineSpatialEnabled = false
    private var baselineSpatialConfiguration: MonoSpatialLiveConfiguration?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: StorageKey.enabled) as? Bool ?? false
        autoApplyOnConnect = defaults.object(forKey: StorageKey.autoApply) as? Bool ?? true
        adaptsToMotion = defaults.object(forKey: StorageKey.adaptiveMotion) as? Bool ?? true
        selectedProfile = AirPodsListeningProfile(
            rawValue: defaults.string(forKey: StorageKey.profile) ?? ""
        ) ?? .immersive
        selectedDeviceModel = AirPodsDeviceModel(
            rawValue: defaults.string(forKey: StorageKey.deviceModel) ?? ""
        ) ?? .airPodsPro2
        modelAwareAITuningEnabled = defaults.object(forKey: StorageKey.modelAwareAITuning) as? Bool ?? true

        installObservers()
        refreshConnection(reason: "initial")
    }

    var connectionTitle: String {
        connection.isConnected
            ? connection.deviceName
            : String(localized: "airpods_not_connected")
    }

    var supportsAdaptiveMotion: Bool {
        guard #available(iOS 18.0, *) else { return false }
        return connection.isConnected && activityManagerIsAvailable
    }

    var activeAITuningTarget: AIEqualizerDeviceTuningTarget? {
        guard modelAwareAITuningEnabled, connection.isConnected else { return nil }
        return selectedDeviceModel.aiTuningTarget
    }

    /// Resolves the current AirPods tuning identity without touching `shared`.
    ///
    /// AIEqualizerAgent restores its cached measurement while its singleton is
    /// still being initialized. Reading `AirPodsExperienceManager.shared` from
    /// that path can form a re-entrant singleton cycle through
    /// MonoNextSuiteManager, so initialization-time callers use this snapshot
    /// based only on persisted preferences and the current audio route.
    static func currentAITuningTargetSnapshot(
        defaults: UserDefaults = .standard
    ) -> AIEqualizerDeviceTuningTarget? {
        let modelAwareEnabled = defaults.object(forKey: StorageKey.modelAwareAITuning) as? Bool ?? true
        guard modelAwareEnabled else { return nil }
        guard AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: isAirPodsOutput) else {
            return nil
        }
        let model = AirPodsDeviceModel(
            rawValue: defaults.string(forKey: StorageKey.deviceModel) ?? ""
        ) ?? .airPodsPro2
        return model.aiTuningTarget
    }

    func activateRuntimeIfNeeded() {
        guard !runtimeReady else { return }
        runtimeReady = true
        refreshConnection(reason: "runtime active")
        updateActivityRuntime()
        if isEnabled,
           connection.isConnected,
           autoApplyOnConnect,
           !experienceApplied {
            applyCurrentExperience(reason: "runtime active")
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: StorageKey.enabled)
        updateActivityRuntime()
        if enabled {
            applyCurrentExperience(reason: "enabled by user")
        } else {
            restoreSpatialBaseline(reason: "disabled by user")
        }
    }

    func setAutoApplyOnConnect(_ enabled: Bool) {
        autoApplyOnConnect = enabled
        defaults.set(enabled, forKey: StorageKey.autoApply)
    }

    func setAdaptsToMotion(_ enabled: Bool) {
        guard adaptsToMotion != enabled else { return }
        adaptsToMotion = enabled
        defaults.set(enabled, forKey: StorageKey.adaptiveMotion)
        updateActivityRuntime()
        if isEnabled {
            applyCurrentExperience(reason: "motion adaptation changed")
        }
    }

    func selectProfile(_ profile: AirPodsListeningProfile) {
        guard selectedProfile != profile else { return }
        selectedProfile = profile
        defaults.set(profile.rawValue, forKey: StorageKey.profile)
        if isEnabled {
            applyCurrentExperience(reason: "profile changed")
        }
    }

    func selectDeviceModel(_ model: AirPodsDeviceModel) {
        guard selectedDeviceModel != model else { return }
        selectedDeviceModel = model
        defaults.set(model.rawValue, forKey: StorageKey.deviceModel)
        if isEnabled {
            applyCurrentExperience(reason: "device model changed")
        }
        AIEqualizerAgent.shared.handleOutputTuningTargetChanged()
    }

    func setModelAwareAITuningEnabled(_ enabled: Bool) {
        guard modelAwareAITuningEnabled != enabled else { return }
        modelAwareAITuningEnabled = enabled
        defaults.set(enabled, forKey: StorageKey.modelAwareAITuning)
        AIEqualizerAgent.shared.handleOutputTuningTargetChanged()
    }

    func applyNow() {
        applyCurrentExperience(reason: "manual apply")
    }

    func recenterHeadTracking() {
        MonoNextSuiteManager.shared.recenterHeadTracking()
    }

    private func installObservers() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor [weak self] in
                self?.refreshConnection(reason: String(describing: reason))
            }
        }

        spatialObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshConnection(reason: "spatial capability changed")
            }
        }
    }

    private func refreshConnection(reason: String) {
        let previous = connection
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first(where: Self.isAirPodsOutput)
        let outputChanged = activityOutputUID != output?.uid
        if outputChanged {
            activityOutputUID = output?.uid
            stopActivityRuntime()
        }
        if let output {
            connection = AirPodsConnectionSnapshot(
                isConnected: true,
                deviceName: output.portName.isEmpty ? "AirPods" : output.portName,
                supportsHeadTracking: motionProbe.isDeviceMotionAvailable,
                systemSpatialAudioEnabled: output.isSpatialAudioEnabled
            )
        } else {
            connection = .disconnected
        }

        guard previous != connection || outputChanged else { return }
        AppLogger.info(
            "[AirPodsExperience] route changed connected=\(connection.isConnected) device=\(connection.deviceName) headTracking=\(connection.supportsHeadTracking) systemSpatial=\(connection.systemSpatialAudioEnabled) reason=\(reason)",
            step: "airpods.route"
        )
        updateActivityRuntime()

        if previous.isConnected, !connection.isConnected {
            restoreSpatialBaseline(reason: "AirPods disconnected")
        }

        if !previous.isConnected,
           connection.isConnected,
           runtimeReady,
           isEnabled,
           autoApplyOnConnect {
            applyCurrentExperience(reason: "AirPods connected")
        } else if outputChanged, connection.isConnected, experienceApplied {
            applyCurrentExperience(reason: "AirPods output changed")
        }
    }

    private static func isAirPodsOutput(_ output: AVAudioSessionPortDescription) -> Bool {
        let isBluetooth = output.portType == .bluetoothA2DP
            || output.portType == .bluetoothLE
            || output.portType == .bluetoothHFP
        guard isBluetooth else { return false }
        return output.portName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased().contains("airpods")
    }

    private func applyCurrentExperience(reason: String) {
        guard isEnabled else {
            AppLogger.debug(
                "[AirPodsExperience] Apply skipped because experience is disabled reason=\(reason)",
                step: "airpods.apply-skipped",
                category: .audio,
                event: "airpods.apply-skipped"
            )
            return
        }
        guard connection.isConnected else {
            AppLogger.debug(
                "[AirPodsExperience] Apply skipped because AirPods route is not connected reason=\(reason)",
                step: "airpods.apply-skipped",
                category: .audio,
                event: "airpods.apply-skipped"
            )
            return
        }

        let suite = MonoNextSuiteManager.shared
        if !experienceApplied {
            baselineSpatialEnabled = suite.isEnabled(.spatialLive)
            baselineSpatialConfiguration = suite.spatialConfiguration
            experienceApplied = true
        }

        var configuration = baseConfiguration(
            for: selectedProfile,
            deviceModel: selectedDeviceModel
        )
        if adaptsToMotion {
            configuration = adapt(configuration, for: motionState)
        }

        suite.setSpatialConfiguration(configuration, enabled: true)
        let effects = PlayerManager.shared.audioEffects
        AppLogger.info(
            "[AirPodsExperience] applied model=\(selectedDeviceModel.rawValue) profile=\(selectedProfile.rawValue) motion=\(motionState.rawValue) mode=\(configuration.mode.rawValue) requestedWidth=\(String(format: "%.3f", configuration.stageWidth)) requestedDepth=\(String(format: "%.3f", configuration.stageDepth)) committedSurround=\(String(format: "%.3f", effects.surroundLevel)) committedReverb=\(String(format: "%.3f", effects.reverbLevel)) committedWidth=\(String(format: "%.3f", effects.stereoWidth)) reason=\(reason)",
            step: "airpods.profile",
            category: .audio,
            event: "airpods.profile"
        )
    }

    private func restoreSpatialBaseline(reason: String) {
        guard experienceApplied else { return }
        let suite = MonoNextSuiteManager.shared
        suite.setSpatialConfiguration(
            baselineSpatialConfiguration ?? .init(),
            enabled: baselineSpatialEnabled
        )
        experienceApplied = false
        baselineSpatialConfiguration = nil
        AppLogger.info(
            "[AirPodsExperience] restored previous spatial settings reason=\(reason)",
            step: "airpods.restore"
        )
    }

    private func baseConfiguration(
        for profile: AirPodsListeningProfile,
        deviceModel: AirPodsDeviceModel
    ) -> MonoSpatialLiveConfiguration {
        let modelWidthOffset: Float
        let modelDepthOffset: Float
        switch deviceModel {
        case .airPods2:
            modelWidthOffset = -0.08
            modelDepthOffset = -0.08
        case .airPods3:
            modelWidthOffset = -0.03
            modelDepthOffset = -0.03
        case .airPods4:
            modelWidthOffset = 0
            modelDepthOffset = 0
        case .airPodsPro1:
            modelWidthOffset = -0.025
            modelDepthOffset = 0
        case .airPodsPro2:
            modelWidthOffset = 0.025
            modelDepthOffset = 0.035
        case .airPodsPro3:
            modelWidthOffset = 0.04
            modelDepthOffset = 0.05
        }
        switch profile {
        case .natural:
            return MonoSpatialLiveConfiguration(
                mode: .fixedStage,
                stageWidth: 1.12 + modelWidthOffset,
                stageDepth: 0.20 + modelDepthOffset,
                centerFocus: 0.62,
                ambience: 0.06
            )
        case .immersive:
            return MonoSpatialLiveConfiguration(
                mode: connection.supportsHeadTracking ? .headTracked : .fixedStage,
                stageWidth: 1.36 + modelWidthOffset,
                stageDepth: 0.56 + modelDepthOffset,
                centerFocus: 0.50,
                ambience: 0.18
            )
        case .focus:
            return MonoSpatialLiveConfiguration(
                mode: .fixedStage,
                stageWidth: 1.04 + modelWidthOffset,
                stageDepth: 0.14 + modelDepthOffset,
                centerFocus: 0.84,
                ambience: 0.035
            )
        }
    }

    private func adapt(
        _ configuration: MonoSpatialLiveConfiguration,
        for motion: AirPodsMotionState
    ) -> MonoSpatialLiveConfiguration {
        var result = configuration
        switch motion {
        case .walking:
            result.mode = .fixedStage
            result.stageWidth = min(result.stageWidth, 1.14)
            result.stageDepth = min(result.stageDepth, 0.22)
            result.centerFocus = max(result.centerFocus, 0.70)
            result.ambience = min(result.ambience, 0.07)
        case .running:
            result.mode = .fixedStage
            result.stageWidth = min(result.stageWidth, 1.06)
            result.stageDepth = min(result.stageDepth, 0.12)
            result.centerFocus = max(result.centerFocus, 0.86)
            result.ambience = min(result.ambience, 0.035)
        case .stationary, .unknown, .unavailable:
            break
        }
        return result
    }

    private var activityManagerIsAvailable: Bool {
        guard #available(iOS 18.0, *) else { return false }
        let manager = (activityRuntime as? CMHeadphoneActivityManager) ?? CMHeadphoneActivityManager()
        return manager.isActivityAvailable
    }

    private func updateActivityRuntime() {
        guard runtimeReady,
              isEnabled,
              adaptsToMotion,
              connection.isConnected else {
            stopActivityRuntime()
            return
        }
        guard #available(iOS 18.0, *) else {
            motionState = .unavailable
            return
        }
        let authorization = CMHeadphoneActivityManager.authorizationStatus()
        guard authorization != .denied,
              authorization != .restricted else {
            motionState = .unavailable
            stopActivityRuntime()
            return
        }

        let manager: CMHeadphoneActivityManager
        if let existing = activityRuntime as? CMHeadphoneActivityManager {
            manager = existing
        } else {
            manager = CMHeadphoneActivityManager()
            activityRuntime = manager
        }
        guard manager.isActivityAvailable else {
            stopActivityRuntime()
            return
        }
        guard !manager.isActivityActive else { return }
        activitySessionID &+= 1
        manager.startActivityUpdates(
            to: activityQueue,
            withHandler: Self.makeActivityHandler(owner: self, sessionID: activitySessionID)
        )
    }

    private func stopActivityRuntime() {
        activitySessionID &+= 1
        cancelMotionTransition()
        if #available(iOS 18.0, *),
           let manager = activityRuntime as? CMHeadphoneActivityManager,
           manager.isActivityActive {
            manager.stopActivityUpdates()
        }
        motionState = .unavailable
    }

    private func cancelMotionTransition() {
        motionTransitionTask?.cancel()
        motionTransitionTask = nil
        pendingMotionState = nil
    }

    private func receiveMotionState(_ state: AirPodsMotionState, sessionID: Int) {
        guard activitySessionID == sessionID,
              experienceApplied, isEnabled, adaptsToMotion, connection.isConnected else { return }
        guard state == .walking || state == .running || state == .stationary,
              state != motionState else {
            // Uncertain classifications must not reopen the immersive stage.
            cancelMotionTransition()
            return
        }
        guard pendingMotionState != state else { return }
        cancelMotionTransition()
        pendingMotionState = state
        // Require a stable classification; returning to head tracking needs
        // a longer dwell than narrowing the stage while moving.
        let dwell: UInt64 = state == .stationary ? 4_000_000_000 : 2_000_000_000
        motionTransitionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: dwell)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.activitySessionID == sessionID,
                  self.pendingMotionState == state,
                  self.experienceApplied, self.isEnabled,
                  self.adaptsToMotion, self.connection.isConnected else { return }
            self.motionTransitionTask = nil
            self.pendingMotionState = nil
            self.motionState = state
            self.applyCurrentExperience(reason: "stable headphone activity changed")
        }
    }

    @available(iOS 18.0, *)
    nonisolated private static func makeActivityHandler(
        owner: AirPodsExperienceManager,
        sessionID: Int
    ) -> CMHeadphoneActivityManager.ActivityHandler {
        return { [weak owner] activity, error in
            let errorText = error?.localizedDescription
            let state: AirPodsMotionState
            if let activity {
                if activity.running {
                    state = .running
                } else if activity.walking {
                    state = .walking
                } else if activity.stationary {
                    state = .stationary
                } else {
                    state = .unknown
                }
            } else {
                state = .unknown
            }
            Task { @MainActor [weak owner] in
                guard let owner, owner.activitySessionID == sessionID else { return }
                if let errorText {
                    AppLogger.warning(
                        "[AirPodsExperience] motion update failed error=\(errorText)",
                        step: "airpods.motion-error"
                    )
                    owner.motionState = .unavailable
                    owner.stopActivityRuntime()
                    return
                }
                owner.receiveMotionState(state, sessionID: sessionID)
            }
        }
    }
}
