import XCTest
@testable import Mono

final class PreferenceDataArchiveTests: XCTestCase {
    private struct EncodingProbe: Encodable, Sendable {
        let index: Int

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(["index": index, "encodedOnMainThread": Thread.isMainThread ? 1 : 0])
        }
    }

    private struct InvalidSnapshot: Encodable, Sendable {
        func encode(to encoder: Encoder) throws {
            throw CocoaError(.coderInvalidValue)
        }
    }

    private func withStore(
        _ body: (PreferenceDataArchive, UserDefaults, URL) throws -> Void
    ) throws {
        let identifier = UUID().uuidString
        let suite = "PreferenceDataArchiveTests." + identifier
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        let store = PreferenceDataArchive(directoryURL: directory, defaults: defaults)
        defer {
            store.waitForPendingWrites()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(store, defaults, directory)
    }

    func testMigratesLegacyRecordsWithoutChangingBytesOrOtherPreferences() throws {
        try withStore { store, defaults, directory in
            defaults.set("clarity", forKey: "unrelated-theme")
            for record in PreferenceDataArchive.Record.allCases {
                let value = String(repeating: "legacy", count: 100_000)
                let data = try JSONEncoder().encode(value)
                defaults.set(data, forKey: record.legacyKey)

                XCTAssertEqual(try store.load(String.self, for: record), value)
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(record.rawValue + ".json")), data)
                XCTAssertNil(defaults.object(forKey: record.legacyKey))
            }
            XCTAssertEqual(defaults.string(forKey: "unrelated-theme"), "clarity")
        }
    }

    func testPayloadLargerThanPreferencesLimitOnlyWritesToFile() throws {
        try withStore { store, defaults, _ in
            let record = PreferenceDataArchive.Record.equalizerProposalHistory
            let value = String(repeating: "x", count: 5 * 1_024 * 1_024)
            let data = try JSONEncoder().encode(value)
            store.save(data, for: record, synchronously: true)

            XCTAssertEqual(try store.load(String.self, for: record), value)
            XCTAssertNil(defaults.object(forKey: record.legacyKey))
        }
    }

    func testStartupMigrationPreservesExistingFilesAndSkipsInvalidLegacyJSON() throws {
        try withStore { store, defaults, directory in
            let validRecord = PreferenceDataArchive.Record.equalizerProposals
            let existingRecord = PreferenceDataArchive.Record.playerStateSnapshot
            let invalidRecord = PreferenceDataArchive.Record.equalizerProposalHistory
            let validData = try JSONEncoder().encode(["kept": 1])
            let oldData = try JSONEncoder().encode(["contextIndex": 1])
            let latestData = try JSONEncoder().encode(["contextIndex": 2])
            let invalidData = Data("invalid-json".utf8)
            defaults.set(validData, forKey: validRecord.legacyKey)
            defaults.set(oldData, forKey: existingRecord.legacyKey)
            defaults.set(invalidData, forKey: invalidRecord.legacyKey)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let existingFile = directory.appendingPathComponent(existingRecord.rawValue + ".json")
            try latestData.write(to: existingFile)

            store.migrateLegacyRecords()

            XCTAssertNil(defaults.object(forKey: validRecord.legacyKey))
            XCTAssertEqual(try store.load([String: Int].self, for: validRecord), ["kept": 1])
            XCTAssertEqual(try Data(contentsOf: existingFile), latestData)
            XCTAssertEqual(defaults.data(forKey: existingRecord.legacyKey), oldData)
            XCTAssertEqual(defaults.data(forKey: invalidRecord.legacyKey), invalidData)
        }
    }

    func testFailedMigrationRetainsLegacyValueAndCanRetry() throws {
        try withStore { store, defaults, directory in
            let record = PreferenceDataArchive.Record.equalizerProposals
            let data = try JSONEncoder().encode(["retained": 42])
            defaults.set(data, forKey: record.legacyKey)
            try Data("blocks-directory".utf8).write(to: directory)

            XCTAssertEqual(try store.load([String: Int].self, for: record), ["retained": 42])
            XCTAssertEqual(defaults.data(forKey: record.legacyKey), data)
            store.save(try JSONEncoder().encode(["retained": 99]), for: record, synchronously: true)
            XCTAssertEqual(defaults.data(forKey: record.legacyKey), data)

            try FileManager.default.removeItem(at: directory)
            XCTAssertEqual(try store.load([String: Int].self, for: record), ["retained": 42])
            XCTAssertNil(defaults.object(forKey: record.legacyKey))
        }
    }

    func testCorruptFileRecoversFromValidLegacyValue() throws {
        try withStore { store, defaults, directory in
            let record = PreferenceDataArchive.Record.playerStateSnapshot
            let data = try JSONEncoder().encode(["contextIndex": 7])
            defaults.set(data, forKey: record.legacyKey)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("invalid-json".utf8).write(to: directory.appendingPathComponent(record.rawValue + ".json"))

            XCTAssertEqual(try store.load([String: Int].self, for: record), ["contextIndex": 7])
            XCTAssertNil(defaults.object(forKey: record.legacyKey))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(record.rawValue + ".json")), data)
        }
    }

    func testUndecodableDataIsNotDeletedOrOverwrittenDuringRestore() throws {
        try withStore { store, defaults, directory in
            let record = PreferenceDataArchive.Record.equalizerProposalHistory
            let data = Data("invalid-json".utf8)
            defaults.set(data, forKey: record.legacyKey)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(record.rawValue + ".json")
            try data.write(to: file)

            XCTAssertThrowsError(try store.load([String: Int].self, for: record))
            XCTAssertEqual(defaults.data(forKey: record.legacyKey), data)
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }

    func testQueuedWritesKeepLatestValueAcrossReopening() throws {
        try withStore { store, defaults, directory in
            let record = PreferenceDataArchive.Record.playerStateSnapshot
            for index in 0..<20 {
                store.save(try JSONEncoder().encode(index), for: record)
            }
            store.waitForPendingWrites()
            let reopened = PreferenceDataArchive(directoryURL: directory, defaults: defaults)

            XCTAssertEqual(try reopened.load(Int.self, for: record), 19)
            XCTAssertNil(defaults.object(forKey: record.legacyKey))
        }
    }

    @MainActor
    func testTypedSnapshotsEncodeOffMainThreadAndKeepSubmissionOrder() throws {
        try withStore { store, _, _ in
            for index in 0..<20 {
                store.save(encoding: EncodingProbe(index: index), for: .playerStateSnapshot)
            }
            store.waitForPendingWrites()
            XCTAssertEqual(
                try store.load([String: Int].self, for: .playerStateSnapshot),
                ["index": 19, "encodedOnMainThread": 0]
            )
        }
    }

    func testTypedSaveCapturesValueBeforeOwnerMutatesIt() throws {
        try withStore { store, _, _ in
            var value = ["songs": [1, 2, 3]]
            store.save(encoding: value, for: .playerStateSnapshot)
            value["songs"] = [4, 5, 6]
            store.waitForPendingWrites()
            XCTAssertEqual(try store.load([String: [Int]].self, for: .playerStateSnapshot), ["songs": [1, 2, 3]])
            store.save(encoding: value, for: .playerStateSnapshot, synchronously: true)
            XCTAssertEqual(try store.load([String: [Int]].self, for: .playerStateSnapshot), value)
        }
    }

    func testEncodingFailurePreservesLastSuccessfulSnapshot() throws {
        try withStore { store, _, _ in
            store.save(encoding: ["index": 7], for: .playerStateSnapshot)
            store.save(encoding: InvalidSnapshot(), for: .playerStateSnapshot)
            store.waitForPendingWrites()
            XCTAssertEqual(try store.load([String: Int].self, for: .playerStateSnapshot), ["index": 7])
        }
    }
}
