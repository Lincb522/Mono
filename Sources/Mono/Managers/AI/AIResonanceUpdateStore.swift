import Foundation
@preconcurrency import Combine

struct AIResonanceNotice: Identifiable, Equatable {
    enum Kind { case introduction, updated, failed }
    var kind: Kind
    var model: AudioTrainingModelInstallDescriptor
    var message: String? = nil
    var id: String { "\(kind)-\(model.distributionIdentity)" }
}

@MainActor
final class AIResonanceUpdateStore: ObservableObject {
    static let shared = AIResonanceUpdateStore()
    @Published private(set) var currentModel: AudioTrainingModelInstallDescriptor?
    @Published private(set) var notice: AIResonanceNotice?
    @Published private(set) var previewNotice: AIResonanceNotice?
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?
    let changes = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults
    private let services: AITuningServiceStore
    private let bundledModel: AudioTrainingModelInstallDescriptor?
    private let bundledURL: URL?
    private let prepare: @Sendable (AudioTrainingModelInstallDescriptor, URLRequest?, URL?) async throws -> String
    private let installedIdentity: @Sendable () async -> String?
    private let request: (AudioTrainingModelInstallDescriptor) throws -> URLRequest
    private var synchronization: (id: UUID, key: String, task: Task<Void, Never>)?
    // First-use history remains recorded when tuning is disabled or another service is selected.
    private static let decisionKey = "ai.resonance.introduction.answered"
    private static let currentKey = "ai.resonance.installed-descriptor"
    private static let seenKey = "ai.resonance.release.seen"

    var tuningModel: AudioTrainingModelInstallDescriptor? { currentModel ?? bundledModel }

    init(
        defaults: UserDefaults = .standard,
        services: AITuningServiceStore = .shared,
        bundle: Bundle = .main,
        bundledModel: AudioTrainingModelInstallDescriptor? = nil,
        bundledURL: URL? = nil,
        prepare: @escaping @Sendable (AudioTrainingModelInstallDescriptor, URLRequest?, URL?) async throws -> String = {
            try await AudioTrainingOnDeviceModelStore.shared.prepareDistributedModel(
                $0, request: $1, bundledModelURL: $2
            )
        },
        installedIdentity: @escaping @Sendable () async -> String? = {
            guard let status = try? await AudioTrainingOnDeviceModelStore.shared.activeStatus() else { return nil }
            return "\(status.id):\(status.sha256)"
        },
        request: @escaping (AudioTrainingModelInstallDescriptor) throws -> URLRequest = {
            try AIProviderConfigurationStore.shared.resonanceDownloadRequest(for: $0)
        }
    ) {
        self.defaults = defaults
        self.services = services
        self.prepare = prepare
        self.installedIdentity = installedIdentity
        self.request = request
        let manifest = bundle.url(forResource: "ResonanceS2", withExtension: "json")
        let bundled = bundledModel ?? manifest.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(AudioTrainingModelInstallDescriptor.self, from: $0) }
        self.bundledModel = bundled.flatMap { model in
            (try? model.validateDistribution()) != nil ? model : nil
        }
        self.bundledURL = bundledURL ?? bundle.url(forResource: "ResonanceS2.mlmodel", withExtension: "bytes")
        currentModel = defaults.data(forKey: Self.currentKey)
            .flatMap { try? JSONDecoder().decode(AudioTrainingModelInstallDescriptor.self, from: $0) }
            .flatMap { model in (try? model.validateDistribution()) != nil ? model : nil }
    }

    func answerIntroduction(enable: Bool) {
        if previewNotice != nil { previewNotice = nil; return }
        defaults.set(true, forKey: Self.decisionKey)
        notice = nil
        if enable { services.update(isEnabled: true, service: .resonance) }
    }

    func dismissNotice() {
        if previewNotice != nil { previewNotice = nil; return }
        if let notice, notice.kind == .introduction {
            answerIntroduction(enable: false)
            return
        }
        if let notice, notice.kind == .updated {
            defaults.set(notice.model.distributionIdentity, forKey: Self.seenKey)
        }
        notice = nil
    }

    func presentPreview(_ kind: AIResonanceNotice.Kind) {
        guard let model = tuningModel else { return }
        previewNotice = AIResonanceNotice(kind: kind, model: model)
    }

    func synchronize(remote: AudioTrainingModelInstallDescriptor?) async {
        let key = "\(services.settings.isEnabled):\(services.settings.service.rawValue):\(remote?.distributionIdentity ?? "offline")"
        if let previous = synchronization {
            if previous.key == key, !previous.task.isCancelled {
                await previous.task.value
                return
            }
            previous.task.cancel()
            await previous.task.value
            guard !Task.isCancelled else { return }
            if let current = synchronization, current.id != previous.id {
                await synchronize(remote: remote)
                return
            }
        }
        let id = UUID()
        let task = Task { await performSynchronization(remote: remote) }
        synchronization = (id, key, task)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        if synchronization?.id == id { synchronization = nil }
    }

    private func performSynchronization(remote: AudioTrainingModelInstallDescriptor?) async {
        guard !Task.isCancelled else { return }
        guard services.settings.isEnabled else { notice = nil; return }
        guard services.settings.service == .resonance else {
            errorMessage = nil
            if !defaults.bool(forKey: Self.decisionKey), let model = bundledModel {
                notice = AIResonanceNotice(kind: .introduction, model: model)
            } else { notice = nil }
            return
        }
        defaults.set(true, forKey: Self.decisionKey)
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil
        do {
            // Retain an existing distributed installation when upgrading the App.
            if currentModel == nil, let remote,
               await installedIdentity() == remote.distributionIdentity {
                try Task.checkCancellation()
                commit(remote)
                defaults.set(remote.distributionIdentity, forKey: Self.seenKey)
            }
            let firstInstallation = currentModel == nil
            do {
                _ = try await prepareInstalledModel()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A removed installation must not prevent downloading its replacement.
                if !firstInstallation, let remote {
                    _ = try await prepare(remote, try request(remote), nil)
                    try Task.checkCancellation()
                    guard isSelected else { return }
                    commit(remote)
                } else {
                    throw error
                }
            }
            // First use is entirely local; online updates start on a later refresh.
            if firstInstallation, let model = currentModel {
                defaults.set(model.distributionIdentity, forKey: Self.seenKey)
                notice = nil
                return
            }
            if let remote, shouldInstallUpdate(remote) {
                try remote.validateDistribution()
                _ = try await prepare(remote, try request(remote), nil)
                try Task.checkCancellation()
                guard isSelected else { return }
                commit(remote)
            } else if let remote, remote.distributionIdentity == currentModel?.distributionIdentity {
                commit(remote)
            }
            if let model = currentModel,
               defaults.string(forKey: Self.seenKey) != model.distributionIdentity {
                notice = AIResonanceNotice(kind: .updated, model: model)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isSelected else { return }
            errorMessage = error.localizedDescription
            if let model = tuningModel {
                notice = AIResonanceNotice(kind: .failed, model: model, message: error.localizedDescription)
            }
        }
    }

    func prepareForTuning() async throws -> String {
        if let synchronization { await synchronization.task.value }
        try Task.checkCancellation()
        return try await prepareInstalledModel()
    }

    private func prepareInstalledModel() async throws -> String {
        guard isSelected, let model = tuningModel else { throw AIResonanceDistributionError.modelUnavailable }
        let localURL = model.distributionIdentity == bundledModel?.distributionIdentity ? bundledURL : nil
        let identity = try await prepare(model, nil, localURL)
        try Task.checkCancellation()
        guard isSelected else { throw CancellationError() }
        if currentModel == nil { commit(model) }
        return identity
    }

    private var isSelected: Bool { services.settings.isEnabled && services.settings.service == .resonance }

    private func shouldInstallUpdate(_ model: AudioTrainingModelInstallDescriptor) -> Bool {
        guard let current = currentModel else { return true }
        guard model.distributionIdentity != current.distributionIdentity else { return false }
        if let available = model.release?.publishedAt ?? model.createdAt,
           let installed = current.release?.publishedAt ?? current.createdAt,
           let availableDate = AudioTrainingModelPresentation.parseDate(available),
           let installedDate = AudioTrainingModelPresentation.parseDate(installed) {
            return availableDate > installedDate
        }
        return true
    }

    private func commit(_ model: AudioTrainingModelInstallDescriptor) {
        let changed = currentModel != nil && currentModel?.distributionIdentity != model.distributionIdentity
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: Self.currentKey)
        currentModel = model
        if changed { changes.send() }
    }
}
