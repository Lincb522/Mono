// 统一持久化门面：内存中维护每个实体的规范对象表，
// save() 时通过快照 diff 找出变更并写入后端（SwiftData 或 Core Data）。

import Foundation
import Combine

@MainActor
final class MonoStore: ObservableObject {
    private var backend: MonoStoreBackend?
    @Published private(set) var saveError: String?

    var isAvailable: Bool { backend != nil }

    /// 每个实体一张表：uniqueKey -> (规范对象, 上次持久化的快照)
    private final class Row {
        let object: AnyObject
        var lastSnapshot: NSDictionary?

        init(object: AnyObject, lastSnapshot: NSDictionary?) {
            self.object = object
            self.lastSnapshot = lastSnapshot
        }
    }

    private var tables: [String: [String: Row]] = [:]
    private var loadedEntities: Set<String> = []
    private var hasPendingDeletes = false
    private var batchDepth = 0
    private var deferredSaveRequested = false

    init(backend: MonoStoreBackend? = nil) {
        self.backend = backend
    }

    func open(backend: MonoStoreBackend) {
        precondition(self.backend == nil)
        self.backend = backend
    }

    // MARK: - 加载

    private func ensureLoaded<T: MonoEntity>(_ type: T.Type) {
        guard let backend else { return }
        let name = T.monoEntityName
        guard !loadedEntities.contains(name) else { return }
        loadedEntities.insert(name)

        var table = tables[name] ?? [:]
        for snapshot in backend.loadAll(entityName: name) {
            let obj = T.monoMake(from: snapshot)
            let key = obj.monoUniqueKey
            // 已在内存中（先插入后加载的场景）时保留内存版本
            if table[key] == nil {
                table[key] = Row(object: obj, lastSnapshot: Self.bridge(snapshot))
            }
        }
        tables[name] = table
    }

    // MARK: - 查询

    func fetchAll<T: MonoEntity>(_ type: T.Type) -> [T] {
        ensureLoaded(type)
        let table = tables[T.monoEntityName] ?? [:]
        return table.values.compactMap { $0.object as? T }
    }

    func fetch<T: MonoEntity>(
        _ type: T.Type,
        where predicate: ((T) -> Bool)? = nil,
        sortBy areInIncreasingOrder: ((T, T) -> Bool)? = nil,
        limit: Int? = nil
    ) -> [T] {
        var results = fetchAll(type)
        if let predicate {
            results = results.filter(predicate)
        }
        if let areInIncreasingOrder {
            results.sort(by: areInIncreasingOrder)
        }
        if let limit, results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
    }

    func first<T: MonoEntity>(_ type: T.Type, where predicate: (T) -> Bool) -> T? {
        fetchAll(type).first(where: predicate)
    }

    func object<T: MonoEntity>(_ type: T.Type, uniqueKey: String) -> T? {
        ensureLoaded(type)
        return tables[T.monoEntityName]?[uniqueKey]?.object as? T
    }

    func count<T: MonoEntity>(_ type: T.Type, where predicate: ((T) -> Bool)? = nil) -> Int {
        if let predicate {
            return fetchAll(type).filter(predicate).count
        }
        return fetchAll(type).count
    }

    // MARK: - 写入

    func insert<T: MonoEntity>(_ object: T) {
        guard isAvailable else { return }
        ensureLoaded(T.self)
        let name = T.monoEntityName
        var table = tables[name] ?? [:]
        // lastSnapshot 为 nil 表示尚未持久化，save() 时必写
        table[object.monoUniqueKey] = Row(object: object, lastSnapshot: nil)
        tables[name] = table
    }

    func delete<T: MonoEntity>(_ object: T) {
        guard let backend else { return }
        ensureLoaded(T.self)
        let name = T.monoEntityName
        guard var table = tables[name] else { return }
        let key = object.monoUniqueKey
        if table.removeValue(forKey: key) != nil {
            backend.delete(entityName: name, uniqueKey: key)
            hasPendingDeletes = true
        }
        tables[name] = table
    }

    func deleteAll<T: MonoEntity>(_ type: T.Type, where predicate: ((T) -> Bool)? = nil) {
        guard let backend else { return }
        ensureLoaded(type)
        let name = T.monoEntityName

        if predicate == nil {
            tables[name] = [:]
            backend.deleteAll(entityName: name)
            hasPendingDeletes = true
            return
        }

        guard var table = tables[name], let predicate else { return }
        for (key, row) in table {
            if let obj = row.object as? T, predicate(obj) {
                table.removeValue(forKey: key)
                backend.delete(entityName: name, uniqueKey: key)
                hasPendingDeletes = true
            }
        }
        tables[name] = table
    }

    // MARK: - 保存

    /// 将所有内存变更（新增 / 属性修改 / 删除）落盘
    @discardableResult
    func save() -> Bool {
        guard let backend else { return false }
        if batchDepth > 0 {
            deferredSaveRequested = true
            return false
        }

        var committedSnapshots: [(Row, NSDictionary)] = []
        for name in loadedEntities {
            guard var table = tables[name] else { continue }
            for (key, row) in table {
                guard let entity = row.object as? any MonoEntity else { continue }
                let snapshot = entity.monoSnapshot()
                let bridged = Self.bridge(snapshot)
                let currentKey = entity.monoUniqueKey
                if row.lastSnapshot == nil || !bridged.isEqual(row.lastSnapshot) || currentKey != key {
                    backend.upsert(entityName: name, uniqueKey: currentKey, snapshot: snapshot)
                    committedSnapshots.append((row, bridged))
                }
                // uniqueKey 属性本身被修改的场景：重新挂到新 key 下
                if currentKey != key {
                    table.removeValue(forKey: key)
                    table[currentKey] = row
                    backend.delete(entityName: name, uniqueKey: key)
                    hasPendingDeletes = true
                }
            }
            tables[name] = table
        }
        return commitSnapshots(committedSnapshots)
    }

    /// Cache updates know their exact rows; avoid snapshotting every loaded
    /// entity on each track change. Other dirty objects remain pending for save().
    @discardableResult
    func save<T: MonoEntity>(_ objects: [T]) -> Bool {
        guard let backend else { return false }
        if batchDepth > 0 {
            deferredSaveRequested = true
            return false
        }
        let table = tables[T.monoEntityName] ?? [:]
        // Renamed or noncanonical objects require the full reconciliation path.
        guard objects.allSatisfy({ table[$0.monoUniqueKey]?.object === $0 }) else {
            return save()
        }

        var committedSnapshots: [(Row, NSDictionary)] = []
        var visitedKeys: Set<String> = []
        for object in objects {
            let key = object.monoUniqueKey
            guard visitedKeys.insert(key).inserted, let row = table[key] else { continue }
            let snapshot = object.monoSnapshot()
            let bridged = Self.bridge(snapshot)
            if row.lastSnapshot == nil || !bridged.isEqual(row.lastSnapshot) {
                backend.upsert(entityName: T.monoEntityName, uniqueKey: key, snapshot: snapshot)
                committedSnapshots.append((row, bridged))
            }
        }
        return commitSnapshots(committedSnapshots)
    }

    private func commitSnapshots(_ committedSnapshots: [(Row, NSDictionary)]) -> Bool {
        guard let backend else { return false }
        if !committedSnapshots.isEmpty || hasPendingDeletes {
            do {
                try backend.flush()
            } catch {
                saveError = error.localizedDescription
                AppLogger.error("Database commit failed: \(error.localizedDescription)")
                return false
            }
            for (row, snapshot) in committedSnapshots {
                row.lastSnapshot = snapshot
            }
            hasPendingDeletes = false
        }
        saveError = nil
        return true
    }

    /// 将一组写入合并为一次底层 flush。即使旧业务代码在闭包内部调用 save，
    /// 也只会标记待保存，不会反复触发 SwiftData/Core Data I/O。
    func performBatch(_ operations: () -> Void) {
        batchDepth += 1
        defer {
            batchDepth = max(0, batchDepth - 1)
            if batchDepth == 0, deferredSaveRequested {
                deferredSaveRequested = false
                save()
            }
        }
        operations()
        deferredSaveRequested = true
    }

    var pendingWriteCount: Int {
        var count = hasPendingDeletes ? 1 : 0
        for name in loadedEntities {
            guard let table = tables[name] else { continue }
            count += table.values.reduce(into: 0) { partial, row in
                guard let entity = row.object as? any MonoEntity else { return }
                if row.lastSnapshot == nil || !Self.bridge(entity.monoSnapshot()).isEqual(row.lastSnapshot) {
                    partial += 1
                }
            }
        }
        return count
    }

    var loadedEntityNames: [String] {
        loadedEntities.sorted()
    }

    // MARK: - 其他

    func storeSizeBytes() -> Int64 {
        backend?.storeSizeBytes() ?? 0
    }

    /// 快照桥接为 NSDictionary（nil -> NSNull），用于变更对比
    private static func bridge(_ snapshot: [String: Any?]) -> NSDictionary {
        let dict = NSMutableDictionary()
        for (key, value) in snapshot {
            dict[key] = value ?? NSNull()
        }
        return dict
    }
}
