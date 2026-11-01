import Foundation
import CryptoKit
import Darwin

// MARK: - 沙盒目录

enum AppDirs {
    static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var thumbnailCache: URL {
        caches.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static var originalCache: URL {
        caches.appendingPathComponent("Originals", isDirectory: true)
    }

    static func ensure(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 设置

enum ThumbnailFormat: String, Codable, CaseIterable, Identifiable {
    case webp
    case jpeg

    var id: String { rawValue }
    var title: String { self == .webp ? "WEBP" : "JPEG" }
    var contentType: String { self == .webp ? "image/webp" : "image/jpeg" }
    var fileExtension: String { self == .webp ? "webp" : "jpg" }
}

enum LockPolicy: String, Codable, CaseIterable, Identifiable {
    case keepRunning
    case pauseOnLock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepRunning: return "锁屏后继续运行"
        case .pauseOnLock: return "锁屏后自动暂停"
        }
    }

    var detail: String {
        switch self {
        case .keepRunning: return "后台保持服务在线，可随时从其他设备访问，耗电略高。"
        case .pauseOnLock: return "锁屏即停止监听，回到前台自动恢复，最省电。"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var serverPort: Int = 8080
    var serverNickname: String = ""
    var pageSize: Int = 40
    var thumbnailFormat: ThumbnailFormat = .webp
    var webpQuality: Double = 0.72
    var jpegQuality: Double = 0.78
    var gridThumbnailPixels: Int = 400
    var viewerThumbnailPixels: Int = 1440
    var thumbnailCacheLimitMB: Int = 600
    var originalCacheLimitMB: Int = 2000
    var lockPolicy: LockPolicy = .keepRunning
    var allowICloudDownload: Bool = false
    var autoStartServer: Bool = true

    enum CodingKeys: String, CodingKey {
        case serverPort, serverNickname, pageSize, thumbnailFormat, webpQuality, jpegQuality
        case gridThumbnailPixels, viewerThumbnailPixels, thumbnailCacheLimitMB, originalCacheLimitMB
        case lockPolicy, allowICloudDownload, autoStartServer
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        serverPort = try c.decodeIfPresent(Int.self, forKey: .serverPort) ?? d.serverPort
        serverNickname = try c.decodeIfPresent(String.self, forKey: .serverNickname) ?? d.serverNickname
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? d.pageSize
        thumbnailFormat = try c.decodeIfPresent(ThumbnailFormat.self, forKey: .thumbnailFormat) ?? d.thumbnailFormat
        webpQuality = try c.decodeIfPresent(Double.self, forKey: .webpQuality) ?? d.webpQuality
        jpegQuality = try c.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? d.jpegQuality
        gridThumbnailPixels = try c.decodeIfPresent(Int.self, forKey: .gridThumbnailPixels) ?? d.gridThumbnailPixels
        viewerThumbnailPixels = try c.decodeIfPresent(Int.self, forKey: .viewerThumbnailPixels) ?? d.viewerThumbnailPixels
        thumbnailCacheLimitMB = try c.decodeIfPresent(Int.self, forKey: .thumbnailCacheLimitMB) ?? d.thumbnailCacheLimitMB
        originalCacheLimitMB = try c.decodeIfPresent(Int.self, forKey: .originalCacheLimitMB) ?? d.originalCacheLimitMB
        lockPolicy = try c.decodeIfPresent(LockPolicy.self, forKey: .lockPolicy) ?? d.lockPolicy
        allowICloudDownload = try c.decodeIfPresent(Bool.self, forKey: .allowICloudDownload) ?? d.allowICloudDownload
        autoStartServer = try c.decodeIfPresent(Bool.self, forKey: .autoStartServer) ?? d.autoStartServer
    }

    var sanitized: AppSettings {
        var s = self
        s.serverPort = min(max(s.serverPort, 1024), 65535)
        s.pageSize = min(max(s.pageSize, 8), 200)
        s.gridThumbnailPixels = min(max(s.gridThumbnailPixels, 200), 800)
        s.viewerThumbnailPixels = min(max(s.viewerThumbnailPixels, 800), 3000)
        s.thumbnailCacheLimitMB = min(max(s.thumbnailCacheLimitMB, 100), 5000)
        s.originalCacheLimitMB = min(max(s.originalCacheLimitMB, 200), 20000)
        s.webpQuality = min(max(s.webpQuality, 0.4), 1.0)
        s.jpegQuality = min(max(s.jpegQuality, 0.4), 1.0)
        return s
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    private static let storageKey = "photonas.settings.v1"
    private let lock = NSLock()
    private var current: AppSettings

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            current = decoded.sanitized
        } else {
            current = AppSettings()
        }
    }

    var value: AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func update(_ settings: AppSettings) {
        let clean = settings.sanitized
        lock.lock()
        current = clean
        lock.unlock()
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - 统计

final class ServerStats {
    static let shared = ServerStats()

    struct Snapshot {
        var requests: Int
        var bytes: Int64
        var thumbnailsGenerated: Int
        var thumbnailCacheHits: Int
        var startedAt: Date
    }

    private let lock = NSLock()
    private var _requests = 0
    private var _bytes: Int64 = 0
    private var _thumbnailsGenerated = 0
    private var _thumbnailCacheHits = 0
    private var _startedAt = Date()

    func markStarted() {
        lock.lock()
        _requests = 0
        _bytes = 0
        _thumbnailsGenerated = 0
        _thumbnailCacheHits = 0
        _startedAt = Date()
        lock.unlock()
    }

    func recordRequest(bytes: Int64) {
        lock.lock()
        _requests += 1
        _bytes += bytes
        lock.unlock()
    }

    func recordThumbnailGenerated() {
        lock.lock()
        _thumbnailsGenerated += 1
        lock.unlock()
    }

    func recordThumbnailCacheHit() {
        lock.lock()
        _thumbnailCacheHits += 1
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(requests: _requests, bytes: _bytes, thumbnailsGenerated: _thumbnailsGenerated, thumbnailCacheHits: _thumbnailCacheHits, startedAt: _startedAt)
    }
}

// MARK: - 网络信息

enum NetInfo {
    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var candidates: [(String, String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var host = [CChar](repeating: 0, count: 256)
                let length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let result = getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    let ip = String(cString: host)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                        candidates.append((name, ip))
                    }
                }
            }
            cursor = interface.ifa_next
        }

        if let en0 = candidates.first(where: { $0.0 == "en0" }) { return en0.1 }
        if let wifi = candidates.first(where: { $0.0.hasPrefix("en") || $0.0.hasPrefix("bridge") }) { return wifi.1 }
        return candidates.first?.1
    }
}

// MARK: - 设备识别

enum DeviceParser {
    static func describe(userAgent: String) -> String {
        let ua = userAgent
        if ua.isEmpty { return "未知设备" }
        if ua.contains("curl") || ua.contains("Wget") { return "命令行" }
        if ua.contains("PhotoNAS") { return "PhotoNAS" }

        var device = "其他设备"
        if ua.contains("iPhone") { device = "iPhone" }
        else if ua.contains("iPad") { device = "iPad" }
        else if ua.contains("Macintosh") || ua.contains("Mac OS X") { device = "Mac" }
        else if ua.contains("Android") { device = "Android" }
        else if ua.contains("Windows") { device = "Windows" }
        else if ua.contains("Linux") { device = "Linux" }

        var browser = ""
        if ua.contains("Edg/") { browser = "Edge" }
        else if ua.contains("CriOS") || ua.contains("Chrome/") { browser = "Chrome" }
        else if ua.contains("FxiOS") || ua.contains("Firefox/") { browser = "Firefox" }
        else if ua.contains("Safari/") { browser = "Safari" }

        return browser.isEmpty ? device : "\(device) · \(browser)"
    }
}
