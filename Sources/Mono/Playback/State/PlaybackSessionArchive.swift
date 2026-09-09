import Foundation

/// Cassette 风格的播放会话日志：完整队列使用双快照，播放位置使用独立轻量日志。
final class PlaybackSessionArchive: @unchecked Sendable {
    static let shared = PlaybackSessionArchive()

    struct SnapshotCandidate: Sendable {
        enum Source: String, Sendable, Equatable {
            case current
            case previous
            case legacy
        }

        let data: Data
        let source: Source
        let sequence: UInt64
        let savedAt: Date?
        let queueCount: Int
    }

    struct ProgressJournal: Codable, Sendable {
        let identity: String
        let currentTime: Double
        let duration: Double
        let wasPlaying: Bool
        let updatedAt: Date
    }

    struct HealthStatus: Sendable {
        let validSnapshots: Int
        let hasCurrentSnapshot: Bool
        let hasPreviousSnapshot: Bool
        let latestSequence: UInt64
        let latestQueueCount: Int
    }

    private struct SnapshotEnvelope: Codable {
        let version: Int
        let sequence: UInt64
        let savedAt: Date
        let reason: String
        let identity: String?
        let queueCount: Int
        let payloadByteCount: Int
        let checksum: UInt64
        let payload: Data
    }

    private let queue = DispatchQueue(
        label: "com.monologue.playback-session-archive",
        qos: .utility
    )
    private let directoryURL: URL
    private let currentURL: URL
    private let previousURL: URL
    private let progressURL: URL
    private var nextSequence: UInt64

    private init() {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        directoryURL = baseURL.appendingPathComponent("MonoPlaybackSession", isDirectory: true)
        currentURL = directoryURL.appendingPathComponent("current.json")
        previousURL = directoryURL.appendingPathComponent("previous.json")
        progressURL = directoryURL.appendingPathComponent("position.json")
        nextSequence = 1
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let latestSequence = [currentURL, previousURL].compactMap { url -> UInt64? in
            guard let data = try? Data(contentsOf: url),
                  let envelope = decodeEnvelope(data) else { return nil }
            return envelope.sequence
        }.max()
        if let latestSequence {
            nextSequence = latestSequence &+ 1
        }
    }

    func saveSnapshot<Value: Encodable & Sendable>(
        encoding value: Value,
        reason: String,
        identity: String?,
        queueCount: Int,
        synchronously: Bool
    ) {
        let operation: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            let data: Data
            do {
                data = try JSONEncoder().encode(value)
            } catch {
                AppLogger.error("[PlaybackSessionArchive] Snapshot encoding failed; previous snapshot retained", step: "storage.playback-snapshot-encode-failed")
                return
            }
            let fileManager = FileManager.default
            try? fileManager.createDirectory(
                at: self.directoryURL,
                withIntermediateDirectories: true
            )

            if let currentData = try? Data(contentsOf: self.currentURL),
               self.decodeEnvelope(currentData) != nil
            {
                try? fileManager.removeItem(at: self.previousURL)
                try? fileManager.copyItem(at: self.currentURL, to: self.previousURL)
            }

            let sequence = self.nextSequence
            self.nextSequence &+= 1
            let envelope = SnapshotEnvelope(
                version: 2,
                sequence: sequence,
                savedAt: Date(),
                reason: reason,
                identity: identity,
                queueCount: queueCount,
                payloadByteCount: data.count,
                checksum: self.checksum(data),
                payload: data
            )
            guard let encoded = try? JSONEncoder().encode(envelope) else { return }
            try? encoded.write(
                to: self.currentURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
        }

        if synchronously {
            queue.sync(execute: operation)
        } else {
            queue.async(execute: operation)
        }
    }

    func saveProgress(_ progress: ProgressJournal) {
        queue.async { [progressURL] in
            guard let data = try? JSONEncoder().encode(progress) else { return }
            try? data.write(
                to: progressURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
        }
    }

    /// 阻塞等待写入队列排空。进入后台前调用，确保挂起时不再持有文件句柄。
    func waitForPendingWrites() {
        queue.sync {}
    }

    func latestProgress() -> ProgressJournal? {
        queue.sync {
            guard let data = try? Data(contentsOf: progressURL) else { return nil }
            return try? JSONDecoder().decode(ProgressJournal.self, from: data)
        }
    }

    func snapshotCandidates() -> [SnapshotCandidate] {
        queue.sync {
            var candidates: [SnapshotCandidate] = []
            for (url, source) in [
                (currentURL, SnapshotCandidate.Source.current),
                (previousURL, SnapshotCandidate.Source.previous),
            ] {
                guard let data = try? Data(contentsOf: url) else { continue }
                if let envelope = decodeEnvelope(data) {
                    candidates.append(SnapshotCandidate(
                        data: envelope.payload,
                        source: source,
                        sequence: envelope.sequence,
                        savedAt: envelope.savedAt,
                        queueCount: envelope.queueCount
                    ))
                } else if (try? JSONSerialization.jsonObject(with: data)) != nil {
                    candidates.append(SnapshotCandidate(
                        data: data,
                        source: .legacy,
                        sequence: 0,
                        savedAt: nil,
                        queueCount: 0
                    ))
                }
            }
            return candidates.sorted { $0.sequence > $1.sequence }
        }
    }

    func healthStatus() -> HealthStatus {
        let candidates = snapshotCandidates()
        return HealthStatus(
            validSnapshots: candidates.count,
            hasCurrentSnapshot: candidates.contains { $0.source == .current },
            hasPreviousSnapshot: candidates.contains { $0.source == .previous },
            latestSequence: candidates.map(\.sequence).max() ?? 0,
            latestQueueCount: candidates.first?.queueCount ?? 0
        )
    }

    private func decodeEnvelope(_ data: Data) -> SnapshotEnvelope? {
        guard let envelope = try? JSONDecoder().decode(SnapshotEnvelope.self, from: data),
              envelope.version == 2,
              envelope.payloadByteCount == envelope.payload.count,
              envelope.checksum == checksum(envelope.payload) else { return nil }
        return envelope
    }

    private func checksum(_ data: Data) -> UInt64 {
        data.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
