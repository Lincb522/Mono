import XCTest
import SwiftData
@testable import Mono

@MainActor
final class StorageRegressionTests: XCTestCase {
    private func song(source: String, name: String = "Fixture") throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data("""
        {"id":42,"name":"\(name)","source":"\(source)","kugouHash":"fixturehash","kugouAlbumID":7,"kugouAlbumAudioID":8}
        """.utf8))
    }

    func testFailedSaveKeepsInsertsUpdatesAndDeletesPending() throws {
        let backend = TestBackend()
        let store = MonoStore(backend: backend)
        let first = CachedSong(from: try song(source: "netease"))
        store.insert(first)
        XCTAssertTrue(store.save())
        backend.fail = true
        store.delete(first)
        let second = CachedSong(from: try song(source: "qqmusic"))
        store.insert(second)
        XCTAssertFalse(store.save())
        XCTAssertGreaterThan(store.pendingWriteCount, 0)
        XCTAssertEqual(backend.persisted["CachedSong"]?.count, 1)
        backend.fail = false
        XCTAssertTrue(store.save())
        XCTAssertEqual(store.pendingWriteCount, 0)
        XCTAssertNil(backend.persisted["CachedSong"]?[first.monoUniqueKey])
        XCTAssertNotNil(backend.persisted["CachedSong"]?[second.monoUniqueKey])
        second.name = "Updated fixture"
        backend.fail = true
        XCTAssertFalse(store.save())
        backend.fail = false
        XCTAssertTrue(store.save())
        XCTAssertEqual(backend.persisted["CachedSong"]?[second.monoUniqueKey]?["name"] as? String, second.name)
    }

    func testPlatformsRemainDistinctInCacheAndPlaylist() throws {
        let ncm = try song(source: "netease", name: "NCM")
        let qq = try song(source: "qqmusic", name: "QCM")
        XCTAssertNotEqual(ncm, qq)
        XCTAssertEqual(Set([ncm, qq]).count, 2)
        let store = MonoStore(backend: TestBackend())
        let repository = SongRepository(store: store)
        repository.save(songs: [ncm, qq, qq])
        XCTAssertEqual(repository.count(), 2)
        XCTAssertEqual(repository.getSong(id: 42, source: .netease)?.toSong().name, "NCM")
        XCTAssertEqual(repository.getSong(id: 42, source: .qqmusic)?.toSong().name, "QCM")
        let playlist = LocalPlaylist(name: "Fixture")
        playlist.addSong(ncm)
        playlist.addSong(qq)
        XCTAssertEqual(playlist.songs.count, 2)
        playlist.removeSong(qq)
        XCTAssertEqual(playlist.songs, [ncm])
    }

    func testTargetedSaveSnapshotsOnlySelectedRowsAndKeepsOtherChangesPending() {
        let backend = TestBackend()
        let store = MonoStore(backend: backend)
        let records = (0..<1_000).map { SnapshotCountingEntity(key: String($0)) }
        records.forEach { store.insert($0) }
        XCTAssertTrue(store.save())
        records.forEach { $0.snapshotCount = 0 }
        records[0].value = 10
        records[1].value = 20

        XCTAssertTrue(store.object(SnapshotCountingEntity.self, uniqueKey: "0") === records[0])
        XCTAssertTrue(store.save([records[0], records[0]]))
        XCTAssertEqual(records[0].snapshotCount, 1)
        XCTAssertTrue(records.dropFirst().allSatisfy { $0.snapshotCount == 0 })
        XCTAssertEqual(backend.persisted["SnapshotCountingEntity"]?["0"]?["value"] as? Int, 10)
        XCTAssertEqual(backend.persisted["SnapshotCountingEntity"]?["1"]?["value"] as? Int, 0)

        XCTAssertTrue(store.save())
        XCTAssertEqual(backend.persisted["SnapshotCountingEntity"]?["1"]?["value"] as? Int, 20)
    }

    func testTargetedSaveRetainsFailedWritesAndPendingDeletesForRetry() throws {
        let backend = TestBackend()
        let store = MonoStore(backend: backend)
        let first = CachedSong(from: try song(source: "netease"))
        let second = CachedSong(from: try song(source: "qqmusic"))
        store.insert(first)
        store.insert(second)
        XCTAssertTrue(store.save())
        store.delete(first)
        second.name = "Changed"
        backend.fail = true
        XCTAssertFalse(store.save([second]))
        XCTAssertNotNil(backend.persisted["CachedSong"]?[first.monoUniqueKey])
        XCTAssertGreaterThan(store.pendingWriteCount, 0)
        backend.fail = false
        XCTAssertTrue(store.save([second]))
        XCTAssertNil(backend.persisted["CachedSong"]?[first.monoUniqueKey])
        XCTAssertEqual(backend.persisted["CachedSong"]?[second.monoUniqueKey]?["name"] as? String, "Changed")
        XCTAssertEqual(store.pendingWriteCount, 0)
    }

    func testTargetedSaveDefersWithinBatchAndReconcilesRenamedKeys() {
        let backend = TestBackend()
        let store = MonoStore(backend: backend)
        let record = SnapshotCountingEntity(key: "before")
        store.insert(record)
        store.performBatch {
            record.value = 1
            XCTAssertFalse(store.save([record]))
            XCTAssertTrue(backend.persisted.isEmpty)
            record.value = 2
        }
        XCTAssertEqual(backend.persisted["SnapshotCountingEntity"]?["before"]?["value"] as? Int, 2)
        record.key = "after"
        XCTAssertTrue(store.save([record]))
        XCTAssertNil(backend.persisted["SnapshotCountingEntity"]?["before"])
        XCTAssertTrue(store.object(SnapshotCountingEntity.self, uniqueKey: "after") === record)
    }

    func testKugouFieldsSurviveCacheHistoryAndCloudRoundTrips() throws {
        let original = try song(source: "kugou")
        let cached = CachedSong.monoMake(from: CachedSong(from: original).monoSnapshot()).toSong()
        let history = PlayHistory.monoMake(from: PlayHistory(from: original).monoSnapshot())
        let cloud = try JSONDecoder().decode(CloudPlayHistoryRecord.self, from:
            JSONEncoder().encode(CloudPlayHistoryRecord(from: history))).makeLocalRecord().toSong()
        for restored in [cached, history.toSong(), cloud] {
            XCTAssertEqual(restored.kugouHash, original.kugouHash)
            XCTAssertEqual(restored.kugouAlbumID, original.kugouAlbumID)
            XCTAssertEqual(restored.kugouAlbumAudioID, original.kugouAlbumAudioID)
        }
    }

    func testCacheCleanupKeepsUserRecords() throws {
        let database = DatabaseManager(openBackend: { TestBackend() })
        database.store.insert(CachedSong(from: try song(source: "netease")))
        database.store.insert(PlayHistory(from: try song(source: "netease")))
        database.store.insert(SearchHistory(keyword: "Fixture"))
        database.store.insert(LocalPlaylist(name: "Fixture"))
        database.clearCacheData()
        XCTAssertEqual(database.store.count(CachedSong.self), 0)
        XCTAssertEqual(database.store.count(PlayHistory.self), 1)
        XCTAssertEqual(database.store.count(SearchHistory.self), 1)
        XCTAssertEqual(database.store.count(LocalPlaylist.self), 1)
    }

    func testOpeningFailureRemainsUnavailableUntilSuccessfulRetry() {
        let backend = TestBackend()
        backend.fail = true
        let database = DatabaseManager(openBackend: {
            if backend.fail { throw CocoaError(.fileReadNoPermission) }
            return backend
        })
        XCTAssertNotNil(database.initializationError)
        XCTAssertFalse(database.store.isAvailable)
        XCTAssertFalse(database.save())
        backend.fail = false
        database.retryInitialization()
        XCTAssertNil(database.initializationError)
        XCTAssertTrue(database.store.isAvailable)
    }

    func testCoreDataPersistsPlatformKeysAcrossReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.sqlite")
        try checkPersistence { try CoreDataBackend(entityTypes: DatabaseManager.allEntityTypes, storeURL: url) }
    }

    func testSwiftDataPersistsPlatformKeysAcrossReopen() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("SwiftData requires iOS 17") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        try checkPersistence { try SwiftDataBackend(storeURL: url) }
    }

    func testFailedDatabaseOpenKeepsOriginalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("synthetic unreadable database".utf8)
        let coreURL = directory.appendingPathComponent("fixture.sqlite")
        try original.write(to: coreURL)
        XCTAssertThrowsError(try CoreDataBackend(entityTypes: DatabaseManager.allEntityTypes, storeURL: coreURL))
        XCTAssertEqual(try Data(contentsOf: coreURL), original)
        if #available(iOS 17, *) {
            let swiftURL = directory.appendingPathComponent("fixture.store")
            try original.write(to: swiftURL)
            XCTAssertThrowsError(try SwiftDataBackend(storeURL: swiftURL))
            XCTAssertEqual(try Data(contentsOf: swiftURL), original)
        }
    }

    func testLyricsCacheIsolatedByPlatform() {
        let store = MonoStore(backend: TestBackend())
        let repository = HistoryRepository(store: store)
        repository.saveLyrics(songId: 42, source: .netease, lyrics: "NCM")
        repository.saveLyrics(songId: 42, source: .qqmusic, lyrics: "QCM")
        XCTAssertEqual(repository.getLyrics(songId: 42, source: .netease)?.lyrics, "NCM")
        repository.deleteLyrics(songId: 42, source: .qqmusic)
        XCTAssertNotNil(repository.getLyrics(songId: 42, source: .netease))
        XCTAssertNil(repository.getLyrics(songId: 42, source: .qqmusic))
    }

    func testCoreDataToSwiftDataMigrationCommitsAndReopens() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("SwiftData requires iOS 17") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.sqlite")
        let targetURL = directory.appendingPathComponent("target.store")
        let source = try CoreDataBackend(entityTypes: DatabaseManager.allEntityTypes, storeURL: sourceURL)
        let sourceStore = MonoStore(backend: source)
        let songs = try ["netease", "qqmusic", "kugou"].map { try song(source: $0) }
        for song in songs { sourceStore.insert(CachedSong(from: song)) }
        let playlist = LocalPlaylist(id: "fixture", name: "Migrated playlist")
        playlist.songs = songs
        sourceStore.insert(playlist)
        sourceStore.insert(PlayHistory(from: songs[0]))
        sourceStore.insert(CachedLyrics(songId: 42, lyrics: "Migrated lyrics"))
        XCTAssertTrue(sourceStore.save())
        let target = try SwiftDataBackend(storeURL: targetURL)
        try DatabaseManager.migrateStore(from: source, into: target,
                                        reopen: { try SwiftDataBackend(storeURL: targetURL) })
        let restored = MonoStore(backend: try SwiftDataBackend(storeURL: targetURL))
        XCTAssertEqual(restored.count(CachedSong.self), 3)
        XCTAssertEqual(restored.fetchAll(LocalPlaylist.self).first?.songs, songs)
        XCTAssertEqual(restored.count(PlayHistory.self), 1)
        XCTAssertEqual(restored.fetchAll(CachedLyrics.self).first?.lyrics, "Migrated lyrics")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(source.loadAll(entityName: "CachedSong").count, 3)
    }

    func testMigrationFailureRetainsSourceAndRetryPreservesNewerTargetRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.sqlite")
        let source = try CoreDataBackend(entityTypes: DatabaseManager.allEntityTypes, storeURL: sourceURL)
        let sourceStore = MonoStore(backend: source)
        sourceStore.insert(LocalPlaylist(id: "same", name: "Old title"))
        sourceStore.insert(LocalPlaylist(id: "missing", name: "Restored playlist"))
        XCTAssertTrue(sourceStore.save())
        let target = TestBackend()
        let targetStore = MonoStore(backend: target)
        targetStore.insert(LocalPlaylist(id: "same", name: "New title"))
        XCTAssertTrue(targetStore.save())
        target.fail = true
        XCTAssertThrowsError(try DatabaseManager.migrateStore(from: source, into: target, reopen: { target }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(source.loadAll(entityName: "LocalPlaylist").count, 2)
        target.fail = false
        try DatabaseManager.migrateStore(from: source, into: target, reopen: { target })
        XCTAssertEqual(target.persisted["LocalPlaylist"]?["same"]?["name"] as? String, "New title")
        XCTAssertEqual(target.persisted["LocalPlaylist"]?["missing"]?["name"] as? String, "Restored playlist")
        XCTAssertThrowsError(try DatabaseManager.migrateStore(from: source, into: target, reopen: { TestBackend() }))
    }

    func testPreviousSwiftDataSchemaMigratesWithoutLosingUserData() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("SwiftData requires iOS 17") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        try writeLegacyStore(at: url)
        let store = MonoStore(backend: try SwiftDataBackend(storeURL: url))
        XCTAssertEqual(store.first(CachedSong.self, where: { $0.id == 42 })?.toSong().name, "Legacy song")
        XCTAssertEqual(store.first(CachedLyrics.self, where: { $0.songId == 42 })?.lyrics, "Legacy lyrics")
        XCTAssertEqual(store.fetchAll(LocalPlaylist.self).first?.name, "Legacy playlist")
        store.insert(CachedSong(from: try song(source: "qqmusic")))
        store.insert(CachedLyrics(songId: 42, source: .qqmusic, lyrics: "QCM"))
        XCTAssertTrue(store.save())
        let reopened = MonoStore(backend: try SwiftDataBackend(storeURL: url))
        XCTAssertEqual(reopened.count(CachedSong.self), 3)
        XCTAssertEqual(reopened.count(CachedLyrics.self), 3)
        XCTAssertEqual(reopened.count(LocalPlaylist.self), 1)
    }

    @available(iOS 17, *)
    private func writeLegacyStore(at url: URL) throws {
        let schema = Schema([
            LegacySwiftDataSchema.CachedSong.self, LegacySwiftDataSchema.CachedPlaylist.self,
            LegacySwiftDataSchema.CachedArtist.self, LegacySwiftDataSchema.PlayHistory.self,
            LegacySwiftDataSchema.SearchHistory.self, LegacySwiftDataSchema.CachedLyrics.self,
            LegacySwiftDataSchema.DownloadedSong.self, LegacySwiftDataSchema.LocalPlaylist.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
        let context = ModelContext(container)
        let song = LegacySwiftDataSchema.CachedSong(id: 42)
        song.name = "Legacy song"
        song.sourceRaw = "netease"
        context.insert(song)
        let secondSong = LegacySwiftDataSchema.CachedSong(id: 43)
        secondSong.name = "Second legacy song"
        secondSong.sourceRaw = "qqmusic"
        secondSong.qqMid = "fixturemid43"
        context.insert(secondSong)
        let secondLyrics = LegacySwiftDataSchema.CachedLyrics(songId: 43)
        secondLyrics.lyrics = "Second legacy lyrics"
        context.insert(secondLyrics)
        let lyrics = LegacySwiftDataSchema.CachedLyrics(songId: 42)
        lyrics.lyrics = "Legacy lyrics"
        context.insert(lyrics)
        let playlist = LegacySwiftDataSchema.LocalPlaylist(id: "fixture")
        playlist.name = "Legacy playlist"
        context.insert(playlist)
        try context.save()
    }

    private func checkPersistence(_ makeBackend: () throws -> any MonoStoreBackend) throws {
        do {
            let store = MonoStore(backend: try makeBackend())
            for source in ["netease", "qqmusic", "kugou"] {
                store.insert(CachedSong(from: try song(source: source)))
            }
            XCTAssertTrue(store.save())
        }
        let restored = MonoStore(backend: try makeBackend()).fetchAll(CachedSong.self)
        XCTAssertEqual(Set(restored.map(\.monoUniqueKey)).count, 3)
        XCTAssertEqual(restored.first { $0.toSong().isKugou }?.toSong().kugouHash, "fixturehash")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class SnapshotCountingEntity: MonoEntity {
    static let monoEntityName = "SnapshotCountingEntity"
    static let monoAttributes = [MonoAttribute("key", .string), MonoAttribute("value", .int)]
    var key: String
    var value = 0
    var snapshotCount = 0
    var monoUniqueKey: String { key }

    init(key: String) { self.key = key }

    func monoSnapshot() -> [String: Any?] {
        snapshotCount += 1
        return ["key": key, "value": value]
    }

    static func monoMake(from snapshot: [String: Any?]) -> SnapshotCountingEntity {
        let record = SnapshotCountingEntity(key: MonoSnapshotValue.string(snapshot, "key"))
        record.value = MonoSnapshotValue.int(snapshot, "value")
        return record
    }
}

@MainActor
private final class TestBackend: MonoStoreBackend {
    var rows: [String: [String: [String: Any?]]] = [:]
    var persisted: [String: [String: [String: Any?]]] = [:]
    var fail = false
    func loadAll(entityName: String) -> [[String: Any?]] { Array(rows[entityName, default: [:]].values) }
    func upsert(entityName: String, uniqueKey: String, snapshot: [String: Any?]) {
        rows[entityName, default: [:]][uniqueKey] = snapshot
    }
    func delete(entityName: String, uniqueKey: String) { rows[entityName]?[uniqueKey] = nil }
    func deleteAll(entityName: String) { rows[entityName] = [:] }
    func flush() throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        persisted = rows
    }
    func storeSizeBytes() -> Int64 { 0 }
}
