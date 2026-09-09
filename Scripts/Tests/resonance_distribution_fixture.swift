import Foundation
@preconcurrency import Combine

@main
struct ResonanceDistributionFixture {
    @MainActor
    static func main() async throws {
        defer { FixtureDefaults.clear() }
        let settings = AITuningServiceStore.shared
        check(settings.settings == AITuningServiceSettings(), "New users default to the built-in service without downloading a model")
        let store = AIProviderConfigurationStore.shared
        async let first: Void = store.refreshRemoteConfigurationIfNeeded(force: true)
        async let second: Void = store.refreshRemoteConfigurationIfNeeded(force: true)
        _ = await (first, second)
        guard let descriptor = try store.distributedResonanceModel() else {
            fatalError("An ordinary user must receive the distributed model")
        }
        check(!AppConfig.DeveloperAccess.hasFullTools)
        check(descriptor.id == "model-first")
        check(descriptor.completeBranchSampleCounts["tenBand:standard"] == 64)
        let stats = try await statistics()
        check(stats["config"] == 1, "Concurrent refreshes must share one request")
        let setup = ProviderSelectionHarness()
        await setup.prepare()
        check(setup.context?.configuration.model == "fixture-built-in")
        check(setup.resolvedIdentity == nil)
        check(try await statistics()["downloads"] == 0, "Built-in tuning must not download a published Resonance model")
        settings.update(service: .resonance)
        await setup.prepare()
        check(setup.context?.requiresTrainedModel == true)
        check(setup.context?.configuration.wireProtocol == .appleIntelligence)

        let request = try store.resonanceDownloadRequest(for: descriptor)
        check(request.url?.path == "/base/_admin/api/public/audio-training/models/model-first/coreml")
        check(request.value(forHTTPHeaderField: "X-Admin-Token") == nil)
        let data = try await AudioTrainingModelDownloader.download(descriptor, request: request)
        check(data == Data(repeating: 31, count: descriptor.byteCount))
        for fault in ["unauthorized", "hash", "size", "schema", "redirect"] {
            var faulty = request
            faulty.setValue(fault, forHTTPHeaderField: "X-Fixture-Fault")
            do {
                _ = try await AudioTrainingModelDownloader.download(descriptor, request: faulty)
                fatalError("Must reject \(fault)")
            } catch { }
        }
        check(try await statistics()["redirected"] == 0, "Downloads must not forward tokens through redirects")
        var slow = request
        slow.setValue("slow", forHTTPHeaderField: "X-Fixture-Fault")
        let pending = Task { try await AudioTrainingModelDownloader.download(descriptor, request: slow) }
        for _ in 0..<100 {
            if try await statistics()["slow"] == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(try await statistics()["slow"] == 1)
        pending.cancel()
        do { _ = try await pending.value; fatalError("Cancelled downloads must not succeed") } catch { }

        var personal = AIPersonalProviderSettings()
        personal.isEnabled = true
        personal.configuration.baseURL = "https://fixture.invalid/v1"
        personal.configuration.model = "fixture-personal"
        try AIPersonalProviderStore.shared.save(personal)
        check(try store.distributedResonanceModel() != nil, "Published Resonance remains selectable while other AI features use a custom API")
        check(try store.requestContext().configuration.model == "fixture-personal")
        settings.update(service: .builtIn)
        let beforeProviderChoices = try await statistics()["downloads"]
        await setup.prepare()
        check(setup.context?.configuration.model == "fixture-built-in", "Built-in tuning bypasses the global custom provider")
        check(setup.context?.usageLimits != nil)
        settings.update(service: .custom)
        await setup.prepare()
        check(setup.context?.configuration.model == "fixture-personal")
        check(setup.context?.requiresTrainedModel == false)
        let snapshot = try store.tuningRequestContext(service: .custom)
        var otherEndpoint = snapshot
        otherEndpoint.configuration.baseURL = "https://another.fixture.invalid/v1"
        check(snapshot.cacheIdentity != otherEndpoint.cacheIdentity, "Identically named models on different endpoints must not share proposals")
        check(!snapshot.cacheIdentity.contains("fixture"), "Cache identity must not persist endpoint credentials")
        personal.isEnabled = false
        try AIPersonalProviderStore.shared.save(personal)
        await setup.prepare()
        check(setup.context?.configuration.model == "fixture-personal", "Tuning selection is independent of the switch for other AI features")
        check(try await statistics()["downloads"] == beforeProviderChoices)
        check(try store.requestContext().configuration.model == "fixture-built-in", "Other AI features keep their existing routing")
        var invalidPersonal = personal
        invalidPersonal.configuration.model = ""
        try AIPersonalProviderStore.shared.save(invalidPersonal)
        await setup.prepare()
        check(setup.context == nil, "An invalid custom service must not fall back to the built-in service")
        try AIPersonalProviderStore.shared.save(personal)
        settings.update(service: .resonance)

        let preparation = PreparationHarness()
        let before = try await statistics()["downloads"]!
        async let preparedA = preparation.prepareDistributedModel(descriptor, request: request)
        async let preparedB = preparation.prepareDistributedModel(descriptor, request: request)
        let identities = try await (preparedA, preparedB)
        check(identities.0 == identities.1)
        check(try await statistics()["downloads"] == before + 1)
        _ = try await preparation.prepareDistributedModel(descriptor, request: request)
        check(try await statistics()["downloads"] == before + 1, "Installed models must not download again")
        await preparation.clearDistributedAuthorization()
        check(await preparation.activeIdentity() == nil, "Ordinary users need an active distribution")

        let replacingCancelled = PreparationHarness()
        let cancelled = Task { try await replacingCancelled.prepareDistributedModel(descriptor, request: slow) }
        for _ in 0..<100 {
            if try await statistics()["slow"] == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(try await statistics()["slow"] == 2)
        cancelled.cancel()
        _ = try await replacingCancelled.prepareDistributedModel(descriptor, request: request)
        _ = await cancelled.result
        check(await replacingCancelled.activeIdentity() != nil, "A new run must not inherit an old cancelled task")

        var replacement = descriptor
        replacement.id = "model-second"
        replacement.version = "mono-resonance-s2-schema7-second"
        let replacementRequest = try store.resonanceDownloadRequest(for: replacement)
        await preparation.holdNextInstallation()
        let displaced = Task { try await preparation.prepareDistributedModel(replacement, request: replacementRequest) }
        for _ in 0..<100 {
            if await preparation.isInstallationHeld() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(await preparation.isInstallationHeld())
        _ = try await preparation.prepareDistributedModel(descriptor, request: request)
        await preparation.releaseInstallation()
        _ = await displaced.result
        check(try await preparation.activeStatus()?.id == descriptor.id, "Returning to an installed model must cancel the replacement")
        let replacingCompilation = PreparationHarness()
        await replacingCompilation.holdNextInstallation()
        let obsolete = Task { try await replacingCompilation.prepareDistributedModel(descriptor, request: request) }
        for _ in 0..<100 {
            if await replacingCompilation.isInstallationHeld() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(await replacingCompilation.isInstallationHeld())
        obsolete.cancel()
        let current = Task { try await replacingCompilation.prepareDistributedModel(replacement, request: replacementRequest) }
        await replacingCompilation.releaseInstallation()
        _ = await obsolete.result
        _ = try await current.value
        check(try await replacingCompilation.activeStatus()?.id == replacement.id)
        check(await replacingCompilation.maximumConcurrentInstallations == 1)
        var broken = request
        broken.setValue("hash", forHTTPHeaderField: "X-Fixture-Fault")
        do {
            _ = try await replacingCompilation.prepareDistributedModel(descriptor, request: broken)
            fatalError("Invalid replacement must fail")
        } catch { }
        check(try await replacingCompilation.activeStatus()?.id == replacement.id, "Failed downloads preserve the installed model")

        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.remoteConfiguration)) as! [String: Any]
        legacyJSON.removeValue(forKey: "resonance")
        let legacy = try JSONDecoder().decode(AIRemoteAIConfiguration.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        check(legacy.resonance == nil)
        for mutation in ["schema", "path", "hash", "size", "s1"] {
            var invalid = descriptor
            switch mutation {
            case "schema": invalid.targetSchemaVersion = 3
            case "path": invalid.id = "../other"
            case "hash": invalid.sha256 = "bad"
            case "size": invalid.byteCount = 536_870_913
            default: invalid.version = "mono-resonance-s1-schema6-test"
            }
            do { try invalid.validateDistribution(); fatalError("Invalid descriptor: \(mutation)") } catch { }
        }

        do { try await store.publishDraftConfiguration(); fatalError("Ordinary users cannot publish") } catch { }
        AppConfig.DeveloperAccess.hasFullTools = true
        store.tokenAdminCredential = "fixture-admin"
        await store.fetchPublishedResonanceModels()
        let staleCatalog = Task { await store.fetchPublishedResonanceModels() }
        for _ in 0..<100 {
            if try await statistics()["catalog"] == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(try await statistics()["catalog"] == 2)
        await store.fetchPublishedResonanceModels()
        await staleCatalog.value
        check(store.publishedResonanceModels.count == 2, "A slower pre-publication request must not replace the refreshed catalog")
        check(store.publishedResonanceModels.count == 2)
        store.resonanceEnabled = true
        store.resonanceModelID = "model-second"
        try await store.publishDraftConfiguration()
        check(try store.distributedResonanceModel()?.id == "model-second")
        await setup.prepare(preferInstalledModel: true)
        check(setup.resolvedIdentity?.hasPrefix(descriptor.version) == true, "Full-access training tests must retain their installed candidate")
        AppConfig.DeveloperAccess.hasFullTools = false
        await AIResonanceUpdateStore.shared.synchronize(remote: try store.distributedResonanceModel())
        await setup.prepare(preferInstalledModel: true)
        check(setup.context?.requiredDistributedModelIdentity == replacement.distributionIdentity, "Ordinary users cannot bypass the published selection")
        AppConfig.DeveloperAccess.hasFullTools = true
        store.distributionEnabled = false
        try await store.publishDraftConfiguration()
        check(try store.distributedResonanceModel() == nil)
        await setup.prepare()
        check(setup.context?.requiresTrainedModel == true, "Installed Resonance remains usable offline and must not switch to a cloud model")
        try await checkServiceControls(settings: settings, setup: setup)
        try await checkBundledUpdates(descriptor: descriptor)
        print("PASS: bundled offline first use, consent and refusal persistence, automatic update and changelog deduplication, update failure preservation; production configuration, latest catalog response, downloader, and preparation methods; ordinary access, coalesced refresh/download, installed reuse, cancelled-run replacement, serialized installation, failed-update preservation, explicit built-in/custom/Resonance selection, disabled service and stale-work cancellation, persistence and migration, global AI independence, legacy decoding, malformed descriptors, download verification, redirects, publication, and disabling")
    }

    @MainActor
    static func checkBundledUpdates(descriptor: AudioTrainingModelInstallDescriptor) async throws {
        let domain = "mono.resonance.updates.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AITuningServiceStore(defaults: defaults, customProviderEnabled: false)
        let runtime = PreparationHarness()
        func makeStore() -> AIResonanceUpdateStore {
            AIResonanceUpdateStore(
                defaults: defaults, services: settings,
                bundledModel: descriptor, bundledURL: FixtureBundle.url,
                prepare: { try await runtime.prepareDistributedModel($0, request: $1, bundledModelURL: $2) },
                installedIdentity: {
                    guard let model = try? await runtime.activeStatus() else { return nil }
                    return "\(model.id):\(model.sha256)"
                },
                request: { try AIProviderConfigurationStore.shared.resonanceDownloadRequest(for: $0) }
            )
        }
        var remote = descriptor
        remote.id = "model-second"
        remote.version = "mono-resonance-s2-schema7-second"
        var updates = makeStore()
        let before = try await statistics()["downloads"]!
        let beforePreview = defaults.dictionaryRepresentation() as NSDictionary
        let beforePreviewService = settings.settings
        updates.presentPreview(.introduction)
        check(updates.previewNotice?.kind == .introduction)
        updates.answerIntroduction(enable: true)
        check(updates.previewNotice == nil && settings.settings == beforePreviewService)
        check(beforePreview.isEqual(to: defaults.dictionaryRepresentation()), "Preview enable must not record a first-use choice")
        await updates.synchronize(remote: remote)
        check(updates.notice?.kind == .introduction)
        check(settings.settings.service == .builtIn)
        check(try await statistics()["downloads"] == before, "Offering bundled Resonance must not download")
        let pendingIntroduction = updates.notice
        updates.presentPreview(.updated)
        updates.dismissNotice()
        check(updates.notice == pendingIntroduction, "Closing a preview must preserve the pending real notice")
        updates.answerIntroduction(enable: false)
        updates = makeStore()
        await updates.synchronize(remote: remote)
        check(updates.notice == nil, "A declined introduction survives relaunch")
        check(settings.settings.service == .builtIn)
        settings.update(isEnabled: false)
        await updates.synchronize(remote: remote)
        updates = makeStore()
        settings.update(isEnabled: true)
        await updates.synchronize(remote: remote)
        check(updates.notice == nil, "Disabling and re-enabling must not erase a declined first-use choice")
        settings.update(service: .resonance)
        await updates.synchronize(remote: remote)
        check(updates.currentModel?.id == descriptor.id, "First activation must use the bundled model")
        check(try await statistics()["downloads"] == before, "First activation must remain offline even when a newer model exists")
        await updates.synchronize(remote: remote)
        check(updates.currentModel?.id == remote.id)
        check(updates.notice?.kind == .updated)
        check(try await statistics()["downloads"] == before + 1)
        updates.dismissNotice()
        await updates.synchronize(remote: remote)
        check(updates.notice == nil, "A seen version must not show again")
        updates = makeStore()
        await updates.synchronize(remote: remote)
        check(updates.notice == nil, "Seen version and installed descriptor persist across launch")
        var datedRemote = remote
        datedRemote.release = AudioTrainingModelRelease(publishedAt: "2026-09-10T00:00:00.000Z", summary: "", notes: "Full notes", changelog: "Full notes")
        await updates.synchronize(remote: datedRemote)
        var older = descriptor
        older.release = AudioTrainingModelRelease(publishedAt: "2026-09-09T00:00:00.000Z", summary: "", notes: "Old notes", changelog: "Old notes")
        let beforeOlder = try await statistics()["downloads"]!
        await updates.synchronize(remote: older)
        check(updates.currentModel?.id == remote.id, "Stale server selection must not downgrade an installed model")
        check(try await statistics()["downloads"] == beforeOlder)
        await runtime.removeInstallation()
        await updates.synchronize(remote: remote)
        check(try await runtime.activeStatus()?.id == remote.id, "Missing installation must be repaired automatically")
        let afterRepair = try await statistics()["downloads"]!
        settings.update(service: .custom)
        await updates.synchronize(remote: descriptor)
        check(updates.currentModel?.id == remote.id && updates.notice == nil)
        check(try await statistics()["downloads"] == afterRepair, "A custom-service user must not receive automatic downloads or switches")
        settings.update(service: .resonance)
        var invalid = descriptor
        invalid.sha256 = String(repeating: "0", count: 64)
        await updates.synchronize(remote: invalid)
        check(updates.notice?.kind == .failed)
        check(updates.currentModel?.id == remote.id, "Failed update must keep the previous descriptor")
        check(try await runtime.activeStatus()?.id == remote.id, "Failed update must keep installed files")
        _ = try await updates.prepareForTuning()
        check(await runtime.activeIdentity() != nil, "Previous model must remain usable after failed update")
        defaults.removePersistentDomain(forName: domain)
        let accepted = makeStore()
        settings.update(service: .builtIn)
        await accepted.synchronize(remote: nil)
        accepted.answerIntroduction(enable: true)
        check(settings.settings.service == .resonance && settings.settings.isEnabled)
        await accepted.synchronize(remote: nil)
        check(accepted.currentModel?.id == descriptor.id, "Offline consent must activate the bundled model")
        settings.update(isEnabled: false)
        await accepted.synchronize(remote: nil)
        let reopened = makeStore()
        settings.update(isEnabled: true, service: .builtIn)
        await reopened.synchronize(remote: nil)
        check(reopened.notice == nil, "Disabling Resonance, relaunching, and switching services must not repeat onboarding")
        let acceptedPreferences = defaults.dictionaryRepresentation() as NSDictionary
        let acceptedService = settings.settings
        let acceptedPreviewDownloads = try await statistics()["downloads"]
        for kind in [AIResonanceNotice.Kind.introduction, .updated, .failed] {
            reopened.presentPreview(kind)
            check(reopened.previewNotice?.kind == kind)
            reopened.dismissNotice()
            check(reopened.previewNotice == nil && reopened.notice == nil)
        }
        reopened.presentPreview(.introduction)
        reopened.answerIntroduction(enable: false)
        check(acceptedPreferences.isEqual(to: defaults.dictionaryRepresentation()), "Previews must not change consent, installed version, or read changelogs")
        check(settings.settings == acceptedService, "Preview actions must leave the chosen service unchanged")
        check(try await statistics()["downloads"] == acceptedPreviewDownloads, "Preview actions must not download models")
    }

    @MainActor
    static func checkServiceControls(settings: AITuningServiceStore, setup: ProviderSelectionHarness) async throws {
        let controls = ServiceControlsHarness()
        let obsoleteRun = UUID()
        controls.activeAnalysisRunID = obsoleteRun
        try controls.acceptGenerationResult(analysisRunID: obsoleteRun)
        let running = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        controls.analysisTask = running
        controls.activeAnalysisRunID = UUID()
        controls.activeAnalysisSongIdentifier = "current-song"
        controls.proposal = 1
        controls.appliedProposalID = UUID()
        controls.phase = .working
        let before = try await statistics()["downloads"]
        settings.update(isEnabled: false)
        check(running.isCancelled, "Turning tuning off must cancel the active task")
        check(controls.activeAnalysisRunID == nil && controls.proposal == nil && controls.appliedProposalID == nil)
        check(controls.scheduledCount == 0)
        do {
            try controls.acceptGenerationResult(analysisRunID: obsoleteRun)
            fatalError("A late generation result for the same song must be rejected after disabling")
        } catch is CancellationError { }
        check(EQManager.shared.restoreCount == 1, "Disabling uses the existing pre-AI restoration boundary")
        check(!controls.canApply(isManualAction: true), "Saved or late proposals cannot bypass the master switch")
        await setup.prepare()
        check(setup.context == nil)
        check(try await statistics()["downloads"] == before, "Disabled tuning cannot download")
        let restored = AITuningServiceStore(defaults: FixtureDefaults.value, customProviderEnabled: true)
        check(restored.settings == settings.settings, "The off state and selected service survive relaunch")
        settings.update(isEnabled: false)
        check(EQManager.shared.restoreCount == 1, "Saving unchanged settings must not interrupt playback")
        settings.update(isEnabled: true, service: .builtIn)
        check(controls.scheduledCount == 1 && controls.canApply(isManualAction: false))
        controls.activeAnalysisRunID = UUID()
        settings.update(service: .custom)
        check(controls.activeAnalysisRunID == nil && controls.scheduledCount == 2, "Switching service invalidates old results and reschedules automatic tuning")
        var personal = AIPersonalProviderStore.shared.settings
        personal.configuration.model = "fixture-updated"
        try AIPersonalProviderStore.shared.save(personal)
        check(controls.scheduledCount == 3, "Editing the active custom provider invalidates the current run")
        settings.update(service: .builtIn)
        do {
            try controls.acceptGenerationResult(analysisRunID: obsoleteRun)
            fatalError("Re-enabling must not revive a stale generation result")
        } catch is CancellationError { }
        let scheduled = controls.scheduledCount
        personal.configuration.model = "fixture-unrelated"
        try AIPersonalProviderStore.shared.save(personal)
        check(controls.scheduledCount == scheduled, "Unselected provider edits must not interrupt tuning")
        let name = "mono.tuning.migration.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let migrated = AITuningServiceStore(defaults: defaults, customProviderEnabled: true)
        check(migrated.settings.service == .custom, "Existing enabled custom configuration is preserved on migration")
        let reopened = AITuningServiceStore(defaults: defaults, customProviderEnabled: false)
        check(reopened.settings.service == .custom, "Migration runs once, not on every launch")

        let store = AIProviderConfigurationStore.shared
        store.distributionEnabled = true
        store.resonanceModelID = "model-first"
        try await store.publishDraftConfiguration()
        AppConfig.DeveloperAccess.hasFullTools = false
        settings.update(service: .resonance)
        await PreparationHarness.shared.holdNextInstallation()
        let preparing = Task { await AIResonanceUpdateStore.shared.synchronize(remote: try? store.distributedResonanceModel()) }
        controls.analysisTask = preparing
        for _ in 0..<100 {
            if await PreparationHarness.shared.isInstallationHeld() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(await PreparationHarness.shared.isInstallationHeld())
        settings.update(isEnabled: false)
        check(preparing.isCancelled)
        await PreparationHarness.shared.releaseInstallation()
        await preparing.value
        check(AIResonanceUpdateStore.shared.currentModel?.id == "model-second", "Switching off while updating must preserve the current descriptor")
        check(try await PreparationHarness.shared.activeStatus()?.id == "model-second", "Cancelled preparation preserves the previous installed version")
    }

    static func check(_ value: Bool, _ message: String = "Regression failed") {
        precondition(value, message)
    }

    static func statistics() async throws -> [String: Int] {
        let url = URL(string: CommandLine.arguments[1] + "/statistics")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
}

actor PreparationHarness {
    static let shared = PreparationHarness()
    // PREPARATION_STATE
    private var onDeviceSettings = AudioTrainingOnDeviceSettings.standard
    private var loadedModel: Int?
    private var loadedIdentity: String?
    private var loadedInputMean: [Float]?
    private var loadedConfidenceCalibration: Int?
    private var installed: AudioTrainingInstalledModelStatus?
    private var holdInstallation = false
    private var installationGate: CheckedContinuation<Void, Never>?
    private var concurrentInstallations = 0
    private(set) var maximumConcurrentInstallations = 0

    // PREPARATION_METHODS

    func activeStatus() throws -> AudioTrainingInstalledModelStatus? { installed }
    func removeInstallation() { installed = nil }
    private func rootDirectory() throws -> URL { FileManager.default.temporaryDirectory }
    private func persistSettings() throws {}
    private func loadActiveModel(status: AudioTrainingInstalledModelStatus, root: URL) throws -> Int { 0 }
    func holdNextInstallation() { holdInstallation = true }
    func isInstallationHeld() -> Bool { installationGate != nil }
    func releaseInstallation() {
        holdInstallation = false
        installationGate?.resume()
        installationGate = nil
    }

    private func installValidated(modelData: Data, descriptor: AudioTrainingModelInstallDescriptor) async throws -> AudioTrainingInstalledModelStatus {
        concurrentInstallations += 1
        maximumConcurrentInstallations = max(maximumConcurrentInstallations, concurrentInstallations)
        defer { concurrentInstallations -= 1 }
        if holdInstallation { await withCheckedContinuation { installationGate = $0 } }
        try Task.checkCancellation()
        let status = AudioTrainingInstalledModelStatus(
            id: descriptor.id, version: descriptor.version, sha256: descriptor.sha256,
            byteCount: descriptor.byteCount, featureSchemaVersion: descriptor.featureSchemaVersion,
            targetSchemaVersion: descriptor.targetSchemaVersion, completeSampleCount: descriptor.completeSampleCount,
            legacySampleCount: descriptor.legacySampleCount, installedAt: Date()
        )
        installed = status
        return status
    }
}

typealias AudioTrainingOnDeviceModelStore = PreparationHarness

@MainActor
final class ProviderSelectionHarness {
    enum Phase { case idle, failed(String) }
    enum Stage { case preparingModel }
    let tuningServiceStore = AITuningServiceStore.shared
    let providerStore = AIProviderConfigurationStore.shared
    var phase = Phase.idle
    var generationStage = Stage.preparingModel
    var activeAnalysisRunID: UUID?
    var context: AIProviderRequestContext?
    var resolvedIdentity: String?

    func isCurrentSong(_ song: Int) -> Bool { true }
    let client = AIProviderClient()
    var discoveredProviderModels: [String: String] = [:]
    // PROVIDER_CONTEXT

    func prepare(preferInstalledModel: Bool = false) async {
        context = nil
        resolvedIdentity = nil
        let trigger = AIEqualizerAnalysisTrigger.manual
        // SERVICE_ENABLED_GATE
        let song = 1
        let analysisRunID = UUID()
        activeAnalysisRunID = analysisRunID
        // PROVIDER_SELECTION
        context = requestContext
        resolvedIdentity = onDeviceModelIdentity
    }
}

@MainActor final class PlayerManager {
    static let shared = PlayerManager()
    var currentSong: Int? = 1
}
@MainActor final class EQManager {
    static let shared = EQManager()
    var restoreCount = 0
    func restoreProcessingBeforeAI(reason: String) { restoreCount += 1 }
}
@MainActor final class ServiceControlsHarness {
    enum Phase {
        case idle, working, failed(String)
        var isWorking: Bool { if case .working = self { return true }; return false }
    }
    let tuningServiceStore = AITuningServiceStore.shared
    var cancellables = Set<AnyCancellable>()
    var automaticTask: Task<Void, Never>?
    var automaticRetryTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var samplingRetryCount: [String: Int] = [:]
    var scheduledAutomaticRunID: UUID?
    var scheduledAutomaticSongIdentifier: String?
    var activeAnalysisRunID: UUID?
    var activeAnalysisSongIdentifier: String?
    var tuningStartedAt: Date?
    var generationStartedAt: Date?
    var activeLearningSession: Int?
    var currentLearningFeedback: Int?
    var proposal: Int?
    var appliedProposalID: UUID?
    var appliedSongIdentifier: String?
    var measuredFeatures: Int?
    var phase = Phase.idle
    var scheduledCount = 0
    init() {
        // SERVICE_SUBSCRIPTIONS
    }
    func scheduleAutomaticAnalysis() {
        if tuningServiceStore.settings.isEnabled { scheduledCount += 1 }
    }
    func discardPendingManualEqualizerLearning() {}
    func restoredMeasurement(for song: Int) -> Int? { nil }
    func isCurrentSong(_ song: Int) -> Bool { true }
    func acceptGenerationResult(analysisRunID: UUID) throws {
        let song = 1
        // GENERATION_RESULT_GATE
    }
    func canApply(isManualAction: Bool) -> Bool {
        // APPLY_ENABLED_GATE
        return true
    }
    // CONTROL_METHODS
}
