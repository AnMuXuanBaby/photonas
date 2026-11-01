import Foundation
import Combine

struct AccessLogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let ip: String
    let method: String
    let path: String
    let query: String
    let status: Int
    let bytes: Int64
    let durationMs: Double
    let userAgent: String
    let device: String

    var fullPath: String {
        query.isEmpty ? path : "\(path)?\(query)"
    }

    var json: [String: Any] {
        [
            "id": id.uuidString,
            "timestamp": date.timeIntervalSince1970,
            "ip": ip,
            "method": method,
            "path": path,
            "query": query,
            "status": status,
            "bytes": bytes,
            "durationMs": (durationMs * 10).rounded() / 10,
            "device": device
        ]
    }
}

final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [AccessLogEntry] = []

    private let lock = NSLock()
    private var storage: [AccessLogEntry] = []
    private let maxEntries = 3000
    private let fileURL: URL = AppDirs.documents.appendingPathComponent("access-log.json")
    private let saveQueue = DispatchQueue(label: "com.photonas.logstore.save")
    private var saveWorkItem: DispatchWorkItem?
    private var publishScheduled = false
    private var lastPublish = Date.distantPast

    private init() {
        load()
        entries = storage
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AccessLogEntry].self, from: data) else { return }
        storage = decoded
        if storage.count > maxEntries {
            storage.removeLast(storage.count - maxEntries)
        }
    }

    func append(_ entry: AccessLogEntry) {
        lock.lock()
        storage.insert(entry, at: 0)
        if storage.count > maxEntries {
            storage.removeLast(storage.count - maxEntries)
        }
        lock.unlock()
        schedulePublish()
        scheduleSave()
    }

    private func schedulePublish() {
        let now = Date()
        lock.lock()
        let shouldPublishImmediately = now.timeIntervalSince(lastPublish) > 0.3
        if shouldPublishImmediately {
            lastPublish = now
            publishScheduled = false
        } else if !publishScheduled {
            publishScheduled = true
        } else {
            lock.unlock()
            return
        }
        lock.unlock()

        let delay = shouldPublishImmediately ? 0 : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.publish()
        }
    }

    private func publish() {
        lock.lock()
        let snapshot = storage
        publishScheduled = false
        lastPublish = Date()
        lock.unlock()
        if entries.count != snapshot.count || entries.first?.id != snapshot.first?.id {
            entries = snapshot
        }
    }

    private func scheduleSave() {
        saveQueue.async {
            self.saveWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.persist()
            }
            self.saveWorkItem = item
            self.saveQueue.asyncAfter(deadline: .now() + 2.0, execute: item)
        }
    }

    private func persist() {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func snapshot(limit: Int = 200) -> [AccessLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        if limit <= 0 || limit >= storage.count { return storage }
        return Array(storage.prefix(limit))
    }

    func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.entries = [] }
        saveQueue.async {
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }
}
