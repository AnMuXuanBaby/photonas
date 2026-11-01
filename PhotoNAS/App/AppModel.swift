import Foundation
import UIKit
import Photos
import Combine

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AppSettings {
        didSet {
            let previous = oldValue
            let sanitized = settings.sanitized
            if sanitized != settings {
                settings = sanitized
                return
            }
            SettingsStore.shared.update(sanitized)
            ThumbnailService.shared.applySettings(sanitized)
            OriginalStore.shared.applySettings(sanitized)

            if running, sanitized.serverPort != previous.serverPort {
                restartServer()
            }
        }
    }

    @Published var running = false
    @Published var statusMessage = ""
    @Published var localURL = ""
    @Published var peers: [DiscoveryService.Peer] = []
    @Published var authorization: PHAuthorizationStatus = .notDetermined
    @Published var stats = ServerStats.shared.snapshot()
    @Published var totalPhotos = 0
    @Published var thumbnailCacheText = "—"
    @Published var originalCacheText = "—"

    private let server = HTTPServer()
    private let discovery = DiscoveryService()
    private let keeper = BackgroundKeeper()
    private var pausedByBackground = false
    private var didBootstrap = false
    private var statsTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        settings = SettingsStore.shared.value
        authorization = PhotoLibraryService.shared.authorizationStatus

        server.onStateChange = { [weak self] ready, message in
            guard let self else { return }
            self.running = ready
            if let message, !ready {
                self.statusMessage = message
                self.discovery.stop()
            }
            self.refreshAddress()
        }

        discovery.onPeers = { [weak self] peers in
            self?.peers = peers
        }

        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        observers = [backgroundObserver, foregroundObserver]

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
        refreshAddress()
    }

    // MARK: - 生命周期

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        authorization = PhotoLibraryService.shared.authorizationStatus
        refreshStats()

        if settings.autoStartServer, authorization == .authorized || authorization == .limited {
            startServer()
        }
    }

    private func handleDidEnterBackground() {
        if settings.lockPolicy == .pauseOnLock {
            guard running else { return }
            pausedByBackground = true
            stopInternal()
            statusMessage = "已按设置暂停服务（锁屏 / 后台）"
        } else if running {
            keeper.start()
        }
    }

    private func handleWillEnterForeground() {
        keeper.stop()
        if pausedByBackground {
            pausedByBackground = false
            statusMessage = ""
            startServer()
        }
        refreshStats()
    }

    // MARK: - 服务控制

    var displayName: String {
        let nickname = settings.serverNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        let name = UIDevice.current.name
        return name.isEmpty ? "PhotoNAS" : name
    }

    func startServer() {
        guard !running else { return }
        let status = PhotoLibraryService.shared.authorizationStatus
        authorization = status

        if status == .notDetermined {
            requestAuthorization()
            return
        }
        guard status == .authorized || status == .limited else {
            statusMessage = "需要相册权限才能启动服务"
            return
        }

        let port = UInt16(clamping: settings.serverPort)
        let configuration = HTTPServer.Configuration(port: port, serviceName: displayName, maxConnections: 40)
        do {
            try server.start(configuration: configuration)
            ServerStats.shared.markStarted()
            discovery.start(displayName: displayName, serverPort: port)
            statusMessage = ""
            running = true
            refreshAddress()
            refreshStats()
        } catch {
            statusMessage = error.localizedDescription
            running = false
        }
    }

    func stopServer() {
        pausedByBackground = false
        stopInternal()
        statusMessage = ""
        refreshStats()
    }

    private func stopInternal() {
        discovery.stop()
        server.stop()
        running = false
    }

    private func restartServer() {
        stopInternal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startServer()
        }
    }

    func requestAuthorization() {
        PhotoLibraryService.shared.requestAuthorization { [weak self] status in
            guard let self else { return }
            self.authorization = status
            if status == .authorized || status == .limited {
                self.startServer()
            } else {
                self.statusMessage = "未授权相册访问，请在系统设置中开启"
            }
        }
    }

    func rescanLibrary() {
        PhotoLibraryService.shared.resetCaches()
        refreshStats()
    }

    func clearThumbnailCache() {
        ThumbnailService.shared.clearCache()
        refreshStats()
    }

    func clearOriginalCache() {
        OriginalStore.shared.clearCache()
        refreshStats()
    }

    // MARK: - 统计

    func refreshStats() {
        stats = ServerStats.shared.snapshot()
        let thumbs = ThumbnailService.shared.cacheStats()
        thumbnailCacheText = "\(thumbs.count) 张 · \(Self.bytes(thumbs.bytes)) / \(Self.bytes(thumbs.limit))"
        let originals = OriginalStore.shared.cacheStats()
        originalCacheText = "\(originals.count) 个 · \(Self.bytes(originals.bytes)) / \(Self.bytes(originals.limit))"

        guard authorization == .authorized || authorization == .limited else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let total = PhotoLibraryService.shared.totalCount(kind: .all, albumID: nil)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.totalPhotos != total {
                    self.totalPhotos = total
                }
            }
        }
    }

    private func refreshAddress() {
        let ip = NetInfo.localIPv4() ?? "127.0.0.1"
        localURL = "http://\(ip):\(settings.serverPort)"
    }

    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(value)
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(size)) \(units[index])" }
        return String(format: "%.1f %@", size, units[index])
    }
}
