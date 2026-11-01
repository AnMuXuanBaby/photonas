import Foundation

/// 磁盘 LRU 缓存：按文件最后访问时间淘汰，容量超限自动清理。
final class DiskCache {
    struct Entry {
        var size: Int64
        var accessed: Date
    }

    let directory: URL
    private let label: String
    private let queue = DispatchQueue(label: "com.photonas.diskcache")
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var currentSize: Int64 = 0
    private var limitBytes: Int64

    init(directory: URL, limitBytes: Int64, label: String) {
        self.directory = directory
        self.limitBytes = limitBytes
        self.label = label
        AppDirs.ensure(directory)
        scan()
    }

    private func scan() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            guard url.pathExtension != "part" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? Date.distantPast
            entries[url.lastPathComponent] = Entry(size: size, accessed: modified)
            currentSize += size
        }
        trim()
    }

    func data(forKey key: String) -> Data? {
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            queue.async { self.removeEntry(key) }
            return nil
        }
        let stamp = Date()
        queue.async {
            if var entry = self.entries[key] {
                entry.accessed = stamp
                self.entries[key] = entry
            } else {
                self.entries[key] = Entry(size: Int64(data.count), accessed: stamp)
                self.currentSize += Int64(data.count)
            }
        }
        return data
    }

    func contains(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(key).path)
    }

    @discardableResult
    func store(_ data: Data, forKey key: String) -> Bool {
        let url = directory.appendingPathComponent(key)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        let size = Int64(data.count)
        queue.async {
            if let old = self.entries[key] {
                self.currentSize -= old.size
            }
            self.entries[key] = Entry(size: size, accessed: Date())
            self.currentSize += size
            self.trim()
        }
        return true
    }

    /// 文件已经由外部写入磁盘时，仅登记元数据，避免把大文件读进内存。
    func registerFile(url: URL, key: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else { return }
        let size = number.int64Value
        queue.async {
            if let old = self.entries[key] {
                self.currentSize -= old.size
            }
            self.entries[key] = Entry(size: size, accessed: Date())
            self.currentSize += size
            self.trim()
        }
    }

    private func removeEntry(_ key: String) {
        if let entry = entries.removeValue(forKey: key) {
            currentSize -= entry.size
        }
    }

    private func trim() {
        guard currentSize > limitBytes else { return }
        let target = Int64(Double(limitBytes) * 0.9)
        let ordered = entries.sorted { $0.value.accessed < $1.value.accessed }
        var removed = 0
        for (key, entry) in ordered {
            if currentSize <= target { break }
            let url = directory.appendingPathComponent(key)
            try? FileManager.default.removeItem(at: url)
            entries.removeValue(forKey: key)
            currentSize -= entry.size
            removed += 1
        }
        if removed > 0 {
            NSLog("[PhotoNAS] \(label) LRU 清理 \(removed) 个文件")
        }
    }

    func setLimit(bytes: Int64) {
        queue.async {
            self.limitBytes = max(bytes, 50 * 1024 * 1024)
            self.trim()
        }
    }

    func stats() -> (count: Int, bytes: Int64, limit: Int64) {
        queue.sync {
            (entries.count, currentSize, limitBytes)
        }
    }

    func clear() {
        queue.sync {
            let manager = FileManager.default
            if let contents = try? manager.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) {
                for url in contents {
                    try? manager.removeItem(at: url)
                }
            }
            self.entries.removeAll()
            self.currentSize = 0
        }
    }
}
