import Foundation

/// Large JSON records live outside the preferences domain. All file and legacy
/// preference access is serialized, including migration and background saves.
final class PreferenceDataArchive: @unchecked Sendable {
    static let shared = PreferenceDataArchive()

    enum Record: String, CaseIterable, Sendable {
        case equalizerProposals
        case equalizerProposalHistory
        case playerStateSnapshot

        var legacyKey: String {
            switch self {
            case .equalizerProposals: return "ai.eq.agent.proposal-cache.v1"
            case .equalizerProposalHistory: return "ai.eq.agent.proposal-history.v1"
            case .playerStateSnapshot: return AppConfig.StorageKeys.playerStateSnapshot
            }
        }
    }

    private let queue = DispatchQueue(label: "com.monologue.preference-data-archive", qos: .utility)
    private let directoryURL: URL?
    private let defaults: UserDefaults

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("MonoPreferenceArchives", isDirectory: true)
        self.defaults = defaults
    }

    func migrateLegacyRecords() {
        queue.sync {
            for record in Record.allCases {
                guard let data = defaults.data(forKey: record.legacyKey) else { continue }
                if let url = fileURL(for: record), FileManager.default.fileExists(atPath: url.path) {
                    continue
                }
                do {
                    // Validate the JSON container without instantiating playback
                    // or AI modules during early application initialization.
                    _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
                    try write(data, for: record)
                    logMigration(record, byteCount: data.count)
                } catch {
                    logFailure(error, record: record, operation: "migrate")
                }
            }
        }
    }

    func load<Value: Decodable>(_ type: Value.Type, for record: Record) throws -> Value? {
        try queue.sync {
            var archiveError: Error?
            if let url = fileURL(for: record), FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    let value = try JSONDecoder().decode(type, from: data)
                    removeLegacyRecord(record)
                    return value
                } catch {
                    archiveError = error
                    logFailure(error, record: record, operation: "read")
                }
            }

            guard let data = defaults.data(forKey: record.legacyKey) else {
                if let archiveError { throw archiveError }
                return nil
            }
            let value = try JSONDecoder().decode(type, from: data)
            do {
                try write(data, for: record)
                logMigration(record, byteCount: data.count)
            } catch {
                // The decoded value remains usable even when migration cannot
                // commit. Keep the original preference for the next attempt.
                logFailure(error, record: record, operation: "migrate")
            }
            return value
        }
    }

    func save(_ data: Data, for record: Record, synchronously: Bool = false) {
        let operation: @Sendable () -> Void = { [self] in
            do {
                try write(data, for: record)
            } catch {
                logFailure(error, record: record, operation: "save")
            }
        }
        if synchronously {
            queue.sync(execute: operation)
        } else {
            queue.async(execute: operation)
        }
    }

    func waitForPendingWrites() {
        queue.sync {}
    }

    /// Capture a value snapshot on its owner, then encode and write it in order.
    func save<Value: Encodable & Sendable>(
        encoding value: Value,
        for record: Record,
        synchronously: Bool = false
    ) {
        let operation: @Sendable () -> Void = { [self] in
            do {
                try write(JSONEncoder().encode(value), for: record)
            } catch {
                logFailure(error, record: record, operation: "encode/save")
            }
        }
        if synchronously {
            queue.sync(execute: operation)
        } else {
            queue.async(execute: operation)
        }
    }

    private func fileURL(for record: Record) -> URL? {
        directoryURL?.appendingPathComponent(record.rawValue + ".json", isDirectory: false)
    }

    private func write(_ data: Data, for record: Record) throws {
        guard let directoryURL, let url = fileURL(for: record) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        removeLegacyRecord(record)
    }

    private func removeLegacyRecord(_ record: Record) {
        if defaults.object(forKey: record.legacyKey) != nil {
            defaults.removeObject(forKey: record.legacyKey)
        }
    }

    private func logFailure(_ error: Error, record: Record, operation: String) {
        let error = error as NSError
        AppLogger.error(
            "[PreferenceDataArchive] \(operation) failed record=\(record.rawValue) domain=\(error.domain) code=\(error.code); original data retained, retry on next load/save",
            step: "storage.preferences-archive-failed"
        )
    }

    private func logMigration(_ record: Record, byteCount: Int) {
        AppLogger.info(
            "[PreferenceDataArchive] Migrated record=\(record.rawValue) bytes=\(byteCount)",
            step: "storage.preferences-migration"
        )
    }
}
