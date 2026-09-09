import Foundation
import Combine

class CacheManager: @unchecked Sendable {
    static let shared = CacheManager()
    
    private let memoryCache = NSCache<NSString, AnyObject>()
    private let memoryMetadataLock = NSLock()
    private struct MemoryEntryMetadata {
        let cost: Int
        var lastAccess: UInt64
    }
    private var memoryEntries: [String: MemoryEntryMetadata] = [:]
    private var memoryAccessSequence: UInt64 = 0
    private var memoryCountLimit = 200
    
    /// 串行队列保护磁盘 I/O，避免并发写入冲突
    private let diskQueue = DispatchQueue(label: "zijiu.Monologue.com.cache.disk", qos: .utility)
    private let diskQueueKey = DispatchSpecificKey<UInt8>()

    /// TTL 与数据保存在同一个文件中，避免将高频缓存元数据写入 UserDefaults。
    private static let diskRecordMagic = Data([0x4D, 0x4F, 0x4E, 0x4F, 0x43, 0x48, 0x45, 0x32]) // MONOCHE2
    private static let diskRecordHeaderSize = 16
    
    private var diskCacheURL: URL {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("MonoCache")
        }
        let cacheDirectory = base.appendingPathComponent("MonoCache")
        
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        return cacheDirectory
    }
    
    private let memoryLimit = AppConfig.Cache.memoryLimit
    private let diskLimit = AppConfig.Cache.diskLimit
    private let defaultExpiration: TimeInterval = AppConfig.Cache.defaultTTL
    
    /// 磁盘缓存命中/未命中统计（用于调优，使用锁保护线程安全）
    private let statsLock = NSLock()
    private var _diskHitCount: Int = 0
    private var _diskMissCount: Int = 0
    
    init() {
        memoryCache.totalCostLimit = memoryLimit
        memoryCache.countLimit = 200 // 提高内存缓存条目上限
        diskQueue.setSpecific(key: diskQueueKey, value: 1)
        diskQueue.async {
            self.cleanExpiredDiskCache()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            MonoMemoryEngine.shared.registerResource(
                id: "cache.encoded-data",
                priority: .recreatable,
                budgetWeight: 0.18,
                minimumBudgetBytes: 12 * 1_024 * 1_024,
                applyBudget: { [weak self] bytes in
                    self?.applyMemoryBudget(bytes)
                },
                trim: { [weak self] context in
                    self?.trimMemory(context) ?? .none
                },
                measureUsage: { [weak self] in
                    self?.memoryUsage() ?? .unknown
                }
            )
        }
    }

    private func setMemoryData(_ data: Data, forKey key: String) {
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        memoryMetadataLock.lock()
        memoryAccessSequence &+= 1
        memoryEntries[key] = MemoryEntryMetadata(
            cost: data.count,
            lastAccess: memoryAccessSequence
        )
        let evictedKeys = overflowKeysLocked(protecting: key)
        for evictedKey in evictedKeys {
            memoryEntries.removeValue(forKey: evictedKey)
        }
        memoryMetadataLock.unlock()
        for evictedKey in evictedKeys {
            memoryCache.removeObject(forKey: evictedKey as NSString)
        }
    }

    private func memoryData(forKey key: String) -> Data? {
        guard let object = memoryCache.object(forKey: key as NSString) as? NSData else {
            memoryMetadataLock.lock()
            memoryEntries.removeValue(forKey: key)
            memoryMetadataLock.unlock()
            return nil
        }
        memoryMetadataLock.lock()
        memoryAccessSequence &+= 1
        if var metadata = memoryEntries[key] {
            metadata.lastAccess = memoryAccessSequence
            memoryEntries[key] = metadata
        }
        memoryMetadataLock.unlock()
        return object as Data
    }

    private func overflowKeysLocked(protecting protectedKey: String? = nil) -> [String] {
        let overflow = memoryEntries.count - memoryCountLimit
        guard overflow > 0 else { return [] }
        return memoryEntries
            .filter { $0.key != protectedKey }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(overflow)
            .map(\.key)
    }

    private func removeMemoryObject(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        memoryMetadataLock.lock()
        memoryEntries.removeValue(forKey: key)
        memoryMetadataLock.unlock()
    }

    private func clearMemoryCache() -> (count: Int, bytes: Int) {
        memoryCache.removeAllObjects()
        memoryMetadataLock.lock()
        let count = memoryEntries.count
        let bytes = memoryEntries.values.reduce(0) { $0 + $1.cost }
        memoryEntries.removeAll(keepingCapacity: false)
        memoryMetadataLock.unlock()
        return (count, bytes)
    }

    private func applyMemoryBudget(_ bytes: Int) {
        let budget = max(8 * 1_024 * 1_024, bytes)
        let countLimit = max(48, min(320, budget / (192 * 1_024)))
        memoryMetadataLock.lock()
        memoryCountLimit = countLimit
        let evictedKeys = overflowKeysLocked()
        for key in evictedKeys { memoryEntries.removeValue(forKey: key) }
        memoryMetadataLock.unlock()
        memoryCache.totalCostLimit = budget
        memoryCache.countLimit = countLimit
        for key in evictedKeys { memoryCache.removeObject(forKey: key as NSString) }
    }

    private func trimMemory(_ context: MonoMemoryEngine.TrimContext) -> MonoMemoryEngine.TrimResult {
        guard context.level >= .background else { return .none }
        let released = clearMemoryCache()
        return .init(
            releasedItemCount: released.count,
            estimatedReleasedBytes: released.bytes,
            preservedItemCount: 0
        )
    }

    private func memoryUsage() -> MonoMemoryEngine.ResourceUsage {
        memoryMetadataLock.lock()
        let result = MonoMemoryEngine.ResourceUsage(
            itemCount: memoryEntries.count,
            estimatedBytes: memoryEntries.values.reduce(0) { $0 + $1.cost }
        )
        memoryMetadataLock.unlock()
        return result
    }
    
    /// 阻塞等待磁盘写入队列排空。进入后台前调用，确保挂起时不再持有文件句柄。
    func waitForPendingDiskWrites() {
        guard DispatchQueue.getSpecific(key: diskQueueKey) == nil else { return }
        diskQueue.sync {}
    }

    // MARK: - 通用数据缓存
    
    func setObject<T: Codable>(_ object: T, forKey key: String, ttl: TimeInterval? = nil) {
        if let encoded = try? JSONEncoder().encode(object) {
            setMemoryData(encoded, forKey: key)
            
            diskQueue.async {
                self.saveToDisk(data: encoded, key: key, ttl: ttl)
            }
        }
    }

    /// Large value snapshots must not be serialized on the UI thread.
    func setObjectInBackground<T: Encodable & Sendable>(
        _ object: T,
        forKey key: String,
        ttl: TimeInterval? = nil
    ) {
        diskQueue.async {
            do {
                let encoded = try JSONEncoder().encode(object)
                self.setMemoryData(encoded, forKey: key)
                self.saveToDisk(data: encoded, key: key, ttl: ttl)
            } catch {
                AppLogger.error("[CacheManager] Snapshot encoding failed; cached data retained", step: "storage.cache-encode-failed")
            }
        }
    }
    
    func getObject<T: Codable>(forKey key: String, type: T.Type) -> T? {
        if let data = memoryData(forKey: key) {
            if let object = try? JSONDecoder().decode(T.self, from: data) {
                return object
            }
        }
        
        if let data = loadFromDisk(key: key) {
            statsLock.lock(); _diskHitCount += 1; statsLock.unlock()
            setMemoryData(data, forKey: key)
            
            if let object = try? JSONDecoder().decode(T.self, from: data) {
                return object
            }
        } else {
            statsLock.lock(); _diskMissCount += 1; statsLock.unlock()
        }
        
        return nil
    }
    
    /// 获取原始数据（用于预热缓存）
    func getData(forKey key: String) -> Data? {
        if let data = memoryData(forKey: key) {
            return data
        }
        
        if let data = loadFromDisk(key: key) {
            setMemoryData(data, forKey: key)
            return data
        }
        
        return nil
    }

    /// Reads encoded cache data without making the caller wait on the serial
    /// disk queue. UI entry points use this path so an existing write or cache
    /// cleanup cannot stall the first rendered frame.
    func getDataAsync(forKey key: String) async -> Data? {
        if let data = memoryData(forKey: key) {
            return data
        }

        return await withCheckedContinuation { continuation in
            diskQueue.async {
                let data = self.loadFromDiskOnDiskQueue(key: key)
                if let data {
                    self.statsLock.lock()
                    self._diskHitCount += 1
                    self.statsLock.unlock()
                    self.setMemoryData(data, forKey: key)
                } else {
                    self.statsLock.lock()
                    self._diskMissCount += 1
                    self.statsLock.unlock()
                }
                continuation.resume(returning: data)
            }
        }
    }
    
    // MARK: - 图片缓存
    
    func setImageData(_ data: Data, forKey key: String) {
        setMemoryData(data, forKey: key)
        diskQueue.async {
            self.saveToDisk(data: data, key: key, ttl: nil)
        }
    }
    
    func getImageData(forKey key: String) -> Data? {
        if let data = memoryData(forKey: key) {
            return data
        }
        if let data = loadFromDisk(key: key) {
            setMemoryData(data, forKey: key)
            return data
        }
        return nil
    }
    
    func getImageDataAsync(forKey key: String, completion: @escaping @Sendable (Data?) -> Void) {
        if let data = memoryData(forKey: key) {
            completion(data)
            return
        }
        
        diskQueue.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            let data = self.loadFromDiskOnDiskQueue(key: key)
            if let data = data {
                self.setMemoryData(data, forKey: key)
            }
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }
    
    func removeObject(forKey key: String) {
        performDiskSync {
            removeMemoryObject(forKey: key)
            removeFromDiskOnDiskQueue(key: key)
        }
    }
    
    func clearAll() {
        performDiskSync {
            // Pending encoders may repopulate memory; clear after they finish.
            _ = clearMemoryCache()
            let url = diskCacheURL
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 缓存信息
    
    func calculateCacheSize() -> String {
        performDiskSync {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: .skipsHiddenFiles) else {
                return "0 MB"
            }

            var size: Int64 = 0
            for url in urls {
                if let resourceValues = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                   let allocatedSize = resourceValues.totalFileAllocatedSize {
                    size += Int64(allocatedSize)
                }
            }

            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
    
    func clearCache(completion: @escaping @Sendable () -> Void) {
        diskQueue.async {
            self.clearAll()
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    // MARK: - 缓存统计
    
    /// 获取缓存命中率（用于调优）
    var hitRate: Double {
        statsLock.lock()
        let hits = _diskHitCount
        let misses = _diskMissCount
        statsLock.unlock()
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
    
    // MARK: - 磁盘操作
    
    private func saveToDisk(data: Data, key: String, ttl: TimeInterval?) {
        let cacheFileName = key.cacheFileName
        let fileURL = diskCacheURL.appendingPathComponent(cacheFileName)
        do {
            let expirationDate = Date().addingTimeInterval(ttl ?? defaultExpiration)
            try writeDiskRecord(data: data, to: fileURL, expirationDate: expirationDate)
        } catch {
            AppLogger.error("磁盘缓存写入失败: \(error)")
        }
    }
    
    private func loadFromDisk(key: String) -> Data? {
        performDiskSync {
            loadFromDiskOnDiskQueue(key: key)
        }
    }

    private func loadFromDiskOnDiskQueue(key: String) -> Data? {
        let cacheFileName = key.cacheFileName
        let fileURL = diskCacheURL.appendingPathComponent(cacheFileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        guard let storedData = try? Data(contentsOf: fileURL) else { return nil }
        let payload: Data

        if storedData.starts(with: Self.diskRecordMagic) {
            guard let record = decodeDiskRecord(storedData) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            guard Date() <= record.expirationDate else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            payload = record.data
        } else {
            // 兼容升级前的原始缓存文件，旧文件按最后修改时间判定过期。
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
            let legacyExpirationDate = modificationDate.addingTimeInterval(defaultExpiration)
            if Date() > legacyExpirationDate {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            payload = storedData
            // 首次命中时就地迁移，之后的过期判定不再依赖旧版偏好元数据。
            do {
                try writeDiskRecord(data: storedData, to: fileURL, expirationDate: legacyExpirationDate)
            } catch {
                AppLogger.error("旧版磁盘缓存迁移失败: \(error)")
            }
        }

        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return payload
    }
    
    private func removeFromDiskOnDiskQueue(key: String) {
        let cacheFileName = key.cacheFileName
        let fileURL = diskCacheURL.appendingPathComponent(cacheFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    private func cleanExpiredDiskCache() {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey], options: .skipsHiddenFiles) else { return }

        var files = [(url: URL, date: Date, size: Int)]()
        var totalSize = 0
        var removedCount = 0

        for url in fileURLs {
            if let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey]),
               let date = resourceValues.contentModificationDate,
               let size = resourceValues.totalFileAllocatedSize {
                if let storedData = try? Data(contentsOf: url, options: .mappedIfSafe),
                   storedData.starts(with: Self.diskRecordMagic) {
                    guard let expirationDate = diskRecordExpirationDate(storedData) else {
                        try? FileManager.default.removeItem(at: url)
                        removedCount += 1
                        continue
                    }
                    if Date() > expirationDate {
                        try? FileManager.default.removeItem(at: url)
                        removedCount += 1
                        continue
                    }
                } else if Date().timeIntervalSince(date) > defaultExpiration {
                    try? FileManager.default.removeItem(at: url)
                    removedCount += 1
                    continue
                }

                files.append((url, date, size))
                totalSize += size
            }
        }

        // LRU 淘汰：超出磁盘限制时按最后访问时间排序删除最旧的
        if totalSize > diskLimit {
            files.sort { $0.date < $1.date }

            for file in files {
                if totalSize <= diskLimit / 2 { break } // 清理到 50% 容量，留出余量
                try? FileManager.default.removeItem(at: file.url)
                totalSize -= file.size
                removedCount += 1
            }
        }

        if removedCount > 0 {
            AppLogger.debug("磁盘缓存清理完成：删除 \(removedCount) 个文件")
        }
    }

    private func makeDiskRecord(data: Data, expirationDate: Date) -> Data {
        let milliseconds = UInt64(max(0, expirationDate.timeIntervalSince1970 * 1_000))
        var encodedMilliseconds = milliseconds.bigEndian
        var record = Data(capacity: Self.diskRecordHeaderSize + data.count)
        record.append(Self.diskRecordMagic)
        withUnsafeBytes(of: &encodedMilliseconds) { bytes in
            record.append(contentsOf: bytes)
        }
        record.append(data)
        return record
    }

    private func writeDiskRecord(data: Data, to fileURL: URL, expirationDate: Date) throws {
        let record = makeDiskRecord(data: data, expirationDate: expirationDate)
        try record.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    private func decodeDiskRecord(_ record: Data) -> (data: Data, expirationDate: Date)? {
        guard let expirationDate = diskRecordExpirationDate(record) else { return nil }
        return (Data(record.dropFirst(Self.diskRecordHeaderSize)), expirationDate)
    }

    private func diskRecordExpirationDate(_ record: Data) -> Date? {
        guard record.count >= Self.diskRecordHeaderSize,
              record.starts(with: Self.diskRecordMagic) else {
            return nil
        }

        var milliseconds: UInt64 = 0
        for byte in record[Self.diskRecordMagic.count..<Self.diskRecordHeaderSize] {
            milliseconds = (milliseconds << 8) | UInt64(byte)
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private func performDiskSync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: diskQueueKey) != nil {
            return work()
        }
        return diskQueue.sync(execute: work)
    }
}

// MARK: - 缓存文件名哈希
import CryptoKit

extension String {
    /// 生成安全的缓存文件名（使用 SHA256）
    var cacheFileName: String {
        let digest = SHA256.hash(data: self.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    @available(*, deprecated, message: "Use cacheFileName (SHA256) instead")
    var md5: String {
        let digest = Insecure.MD5.hash(data: self.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
