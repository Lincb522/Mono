import Foundation
@preconcurrency import Combine

enum AIAgentTraceCategory: String, Codable, CaseIterable, Sendable {
    case conversation
    case reasoning
    case skill
}

/// Stable, machine-readable stages used by the developer detail screen.  The
/// visible event title remains free to be localized without breaking the
/// pipeline summary or forcing the UI to reverse-parse human copy.
enum AIAgentTraceStage: String, Codable, CaseIterable, Sendable {
    case configuration
    case skills
    case measurement
    case model
    case tool
    case validation
    case compilation
    case application
    case fallback
    case completion
}

enum AIAgentTraceLevel: String, Codable, Sendable {
    case info
    case success
    case warning
    case error
}

enum AIAgentTraceStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

struct AIAgentTraceEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: AIAgentTraceCategory
    let stage: AIAgentTraceStage?
    let durationSeconds: TimeInterval?
    let level: AIAgentTraceLevel
    let title: String
    let detail: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: AIAgentTraceCategory,
        stage: AIAgentTraceStage? = nil,
        durationSeconds: TimeInterval? = nil,
        level: AIAgentTraceLevel = .info,
        title: String,
        detail: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.stage = stage
        self.durationSeconds = durationSeconds
        self.level = level
        self.title = title
        self.detail = detail
        self.metadata = metadata
    }
}

struct AIAgentTraceSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let agentID: String
    let agentName: String
    let subject: String
    let provider: String
    let model: String
    let startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var status: AIAgentTraceStatus
    var failureMessage: String?
    var events: [AIAgentTraceEvent]

    /// Resolve actual execution from durable events, including histories whose
    /// initial configuration named a remote model before local inference won.
    private var executionIdentity: (provider: String, model: String) {
        let records: Set<String> = [
            "local-coreml-inference", "cached-tuning-result", "remote-model-request",
            "remote-model-output-decoded", "remote-model-failure"
        ]
        for event in events.reversed() {
            guard records.contains(event.metadata["recordType"] ?? "")
                || ((event.stage == .compilation || event.stage == .application) && event.level == .success),
                  let name = event.metadata["model"], !name.isEmpty else { continue }
            let isLocal = event.metadata["modelSource"] == "on-device-coreml"
                || name.hasPrefix("mono-resonance-") || name.hasPrefix("mono-audio-")
            return (isLocal ? "Core ML" : event.metadata["provider"] ?? provider, name)
        }
        let isLocal = model.hasPrefix("mono-resonance-") || model.hasPrefix("mono-audio-")
        return (isLocal ? "Core ML" : provider, isLocal ? String(model.split(separator: ":").first ?? "") : model)
    }

    var executionProvider: String { executionIdentity.provider }
    var executionModel: String { executionIdentity.model }
    var executionModelDisplayName: String {
        let name = executionModel
        if name.hasPrefix("mono-resonance-s2-") { return "共鸣 S2 · \(name)" }
        if name.hasPrefix("mono-resonance-") || name.hasPrefix("mono-audio-") {
            return "共鸣 S1 · \(name)"
        }
        return name
    }

    var duration: TimeInterval {
        (completedAt ?? updatedAt).timeIntervalSince(startedAt)
    }
}

private actor AIAgentTracePersistence {
    private var latestRevision: UInt64 = 0

    func save(_ sessions: [AIAgentTraceSession], to url: URL, revision: UInt64) {
        guard revision >= latestRevision else { return }
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: .atomic)
            latestRevision = revision
        } catch {
            AppLogger.error(
                "[AIAgentTraceStore] Failed to persist Agent traces error=\(error.localizedDescription)",
                step: "agent-trace.persist-failed"
            )
        }
    }
}

/// Developer-only observable history for model conversations, visible decision
/// stages and skill/tool invocations. It never attempts to reconstruct hidden
/// chain-of-thought that a provider did not return.
@MainActor
final class AIAgentTraceStore: ObservableObject {
    static let shared = AIAgentTraceStore()

    @Published private(set) var sessions: [AIAgentTraceSession]

    private static let maximumSessions = 60
    private static let maximumEventsPerSession = 160
    private static let maximumDetailCharacters = 18_000
    private static let maximumModelDetailCharacters = 160_000
    private let storageURL: URL?
    private let persistence = AIAgentTracePersistence()
    private var persistenceTask: Task<Void, Never>?
    private var persistenceRevision: UInt64 = 0

    private init() {
        storageURL = Self.makeStorageURL()
        if let storageURL,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([AIAgentTraceSession].self, from: data) {
            sessions = Array(
                decoded.map { session in
                    var restored = session
                    if restored.status == .running {
                        restored.status = .cancelled
                        restored.completedAt = restored.updatedAt
                        restored.failureMessage = "App 上次结束前任务尚未完成"
                    }
                    return restored
                }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(Self.maximumSessions)
            )
        } else {
            sessions = []
        }
    }

    @discardableResult
    func begin(
        agentID: String,
        agentName: String,
        subject: String,
        provider: String,
        model: String
    ) -> UUID {
        let now = Date()
        let session = AIAgentTraceSession(
            id: UUID(),
            agentID: agentID,
            agentName: agentName,
            subject: Self.sanitized(subject),
            provider: Self.sanitized(provider),
            model: Self.sanitized(model),
            startedAt: now,
            updatedAt: now,
            completedAt: nil,
            status: .running,
            failureMessage: nil,
            events: []
        )
        sessions.insert(session, at: 0)
        trimIfNeeded()
        schedulePersistence()
        return session.id
    }

    func append(
        _ sessionID: UUID,
        category: AIAgentTraceCategory,
        level: AIAgentTraceLevel = .info,
        stage: AIAgentTraceStage? = nil,
        title: String,
        detail: String,
        durationSeconds: TimeInterval? = nil,
        metadata: [String: String] = [:]
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let safeMetadata = metadata.reduce(into: [String: String]()) { result, item in
            result[Self.sanitized(item.key, maximumLength: 80)] = Self.sanitized(item.value, maximumLength: 500)
        }
        let detailLimit = metadata["recordType"] == nil
            ? Self.maximumDetailCharacters
            : Self.maximumModelDetailCharacters
        sessions[index].events.append(
            AIAgentTraceEvent(
                category: category,
                stage: stage,
                durationSeconds: durationSeconds.flatMap { value in
                    value.isFinite && value >= 0 ? value : nil
                },
                level: level,
                title: Self.sanitized(title, maximumLength: 120),
                detail: Self.sanitized(detail, maximumLength: detailLimit),
                metadata: safeMetadata
            )
        )
        if sessions[index].events.count > Self.maximumEventsPerSession {
            sessions[index].events.removeFirst(
                sessions[index].events.count - Self.maximumEventsPerSession
            )
        }
        sessions[index].updatedAt = Date()
        schedulePersistence()
    }

    func finish(
        _ sessionID: UUID,
        status: AIAgentTraceStatus,
        message: String? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let now = Date()
        sessions[index].status = status
        sessions[index].updatedAt = now
        sessions[index].completedAt = now
        sessions[index].failureMessage = message.map { Self.sanitized($0, maximumLength: 2_000) }
        schedulePersistence(immediate: true)
    }

    func clear() {
        sessions.removeAll(keepingCapacity: false)
        schedulePersistence(immediate: true)
    }

    private func trimIfNeeded() {
        if sessions.count > Self.maximumSessions {
            sessions.removeLast(sessions.count - Self.maximumSessions)
        }
    }

    private func schedulePersistence(immediate: Bool = false) {
        guard let storageURL else { return }
        persistenceTask?.cancel()
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let snapshot = sessions
        persistenceTask = Task { [persistence] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(280))
            }
            guard !Task.isCancelled else { return }
            await persistence.save(snapshot, to: storageURL, revision: revision)
        }
    }

    private static func sanitized(_ value: String, maximumLength: Int = maximumDetailCharacters) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)(authorization\s*[:=]\s*)(bearer\s+)?[^\s,\"}]+"#, "$1<redacted>"),
            (#"(?i)((?:api[_-]?key|token|cookie|password|secret)\s*[\"']?\s*[:=]\s*[\"']?)[^\s,\"'}]+"#, "$1<redacted>"),
            (#"\bsk-[A-Za-z0-9_-]{12,}\b"#, "<redacted>")
        ]
        for (pattern, replacement) in replacements {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        guard result.count > maximumLength else { return result }
        let end = result.index(result.startIndex, offsetBy: maximumLength)
        return String(result[..<end]) + "\n…（已截断）"
    }

    private static func makeStorageURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent("Mono", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent("agent-traces-v1.json", isDirectory: false)
        } catch {
            AppLogger.error(
                "[AIAgentTraceStore] Trace storage directory unavailable error=\(error.localizedDescription)",
                step: "agent-trace.storage-failed"
            )
            return nil
        }
    }
}
