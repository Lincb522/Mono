import Foundation
@preconcurrency import Combine

enum AITuningService: String, Codable, CaseIterable, Identifiable, Sendable {
    case builtIn
    case custom
    case resonance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: return String(localized: "ai_tuning_service_builtin")
        case .custom: return String(localized: "ai_tuning_service_custom")
        case .resonance: return String(localized: "ai_tuning_service_resonance")
        }
    }

    var serviceCredit: String {
        switch self {
        case .builtIn: return String(localized: "ai_lab_service_credit_builtin")
        case .custom: return String(localized: "ai_lab_service_credit_custom")
        case .resonance: return String(localized: "ai_lab_service_credit")
        }
    }

    var availabilityNotice: String {
        switch self {
        case .builtIn: return String(localized: "ai_lab_result_notice")
        case .custom: return String(localized: "ai_lab_result_notice_custom")
        case .resonance: return String(localized: "ai_lab_result_notice_resonance")
        }
    }
}

struct AITuningServiceSettings: Codable, Equatable, Sendable {
    var isEnabled = true
    var service: AITuningService = .builtIn
}

@MainActor
final class AITuningServiceStore: ObservableObject {
    static let shared = AITuningServiceStore()
    @Published private(set) var settings: AITuningServiceSettings
    let changes = PassthroughSubject<Void, Never>()
    private let defaults: UserDefaults
    private static let settingsKey = "ai.tuning.service.settings"

    init(defaults: UserDefaults = .standard, customProviderEnabled: Bool? = nil) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AITuningServiceSettings.self, from: data) {
            settings = saved
        } else {
            let customEnabled = customProviderEnabled ?? AIPersonalProviderStore.shared.settings.isEnabled
            settings = AITuningServiceSettings(service: customEnabled ? .custom : .builtIn)
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: Self.settingsKey)
            }
        }
    }

    func update(isEnabled: Bool? = nil, service: AITuningService? = nil) {
        var value = settings
        if let isEnabled { value.isEnabled = isEnabled }
        if let service { value.service = service }
        guard value != settings, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.settingsKey)
        settings = value
        // Subscribers must see the committed selection when cancelling and rescheduling work.
        changes.send()
    }
}
