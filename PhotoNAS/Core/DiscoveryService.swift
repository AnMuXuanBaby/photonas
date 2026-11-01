import Foundation
import Darwin

/// 局域网 UDP 自动发现：定期广播 beacon，同时监听其他设备的广播与 discover 请求。
final class DiscoveryService {
    struct Peer: Identifiable, Equatable {
        let id: String
        let name: String
        let address: String
        let port: Int
        let lastSeen: Date
    }

    static let discoveryPort: UInt16 = 8899

    var onPeers: (([Peer]) -> Void)?

    private var listenFD: Int32 = -1
    private var beaconFD: Int32 = -1
    private let stateLock = NSLock()
    private var running = false
    private var peers: [String: Peer] = [:]
    private var beaconTimer: DispatchSourceTimer?
    private var serverPort: UInt16 = 8080
    private var displayName = "PhotoNAS"
    private let identity = UUID().uuidString

    // MARK: - 生命周期

    func start(displayName: String, serverPort: UInt16) {
        stop()

        stateLock.lock()
        self.displayName = displayName
        self.serverPort = serverPort
        running = true
        stateLock.unlock()

        let fd = Self.makeSocket()
        guard fd >= 0 else {
            NSLog("[PhotoNAS] 无法创建 UDP 发现套接字")
            return
        }
        listenFD = fd

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(Self.discoveryPort).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))

        let bound = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            NSLog("[PhotoNAS] UDP 端口 \(Self.discoveryPort) 绑定失败")
            close(fd)
            listenFD = -1
            return
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let thread = Thread { [weak self] in
            self?.listenLoop(fd)
        }
        thread.name = "photonas.discovery"
        thread.start()

        beaconFD = Self.makeSocket(broadcast: true)
        startBeaconTimer()
        NSLog("[PhotoNAS] UDP 发现已启动，端口 \(Self.discoveryPort)")
    }

    func stop() {
        stateLock.lock()
        let wasRunning = running
        running = false
        let hadPeers = !peers.isEmpty
        peers.removeAll()
        stateLock.unlock()

        beaconTimer?.cancel()
        beaconTimer = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        if beaconFD >= 0 {
            close(beaconFD)
            beaconFD = -1
        }
        if wasRunning || hadPeers {
            onPeers?([])
        }
    }

    func currentPeers() -> [Peer] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return peers.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    // MARK: - 广播与监听

    private func startBeaconTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.photonas.discovery.timer"))
        timer.schedule(deadline: .now() + 0.8, repeating: 2.5, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.send(payload: self.beaconPayload(command: "beacon"), to: nil)
            self.expirePeers()
        }
        timer.resume()
        beaconTimer = timer
    }

    private func listenLoop(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while isRunning() {
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let received: Int = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return withUnsafeMutablePointer(to: &sender) { pointer -> Int in
                    let sockaddrPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self)
                    return recvfrom(fd, base, raw.count, 0, sockaddrPointer, &senderLength)
                }
            }

            if received <= 0 { continue }

            let data = Data(buffer[0..<received])
            handle(data: data, sender: sender)
        }
    }

    private func handle(data: Data, sender: sockaddr_in) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        guard (object["app"] as? String) == "PhotoNAS" else { return }

        let command = object["cmd"] as? String ?? ""
        let peerID = object["id"] as? String ?? identity

        switch command {
        case "discover":
            send(payload: beaconPayload(command: "beacon"), to: sender)
        case "beacon":
            guard peerID != identity else { return }
            let name = object["name"] as? String ?? "PhotoNAS"
            let port = object["port"] as? Int ?? 8080
            let host = addressString(from: sender)
            guard !host.isEmpty else { return }
            let peer = Peer(id: peerID, name: name, address: host, port: port, lastSeen: Date())
            stateLock.lock()
            peers[peerID] = peer
            stateLock.unlock()
            notifyPeers()
        default:
            break
        }
    }

    private func expirePeers() {
        let now = Date()
        stateLock.lock()
        let expired = peers.filter { now.timeIntervalSince($0.value.lastSeen) > 9 }.map { $0.key }
        for key in expired {
            peers.removeValue(forKey: key)
        }
        stateLock.unlock()
        if !expired.isEmpty {
            notifyPeers()
        }
    }

    private func notifyPeers() {
        let list = currentPeers()
        DispatchQueue.main.async {
            self.onPeers?(list)
        }
    }

    // MARK: - 报文

    private func beaconPayload(command: String) -> Data {
        stateLock.lock()
        let name = displayName
        let port = serverPort
        stateLock.unlock()

        let payload: [String: Any] = [
            "app": "PhotoNAS",
            "cmd": command,
            "ver": 1,
            "id": identity,
            "name": name,
            "port": Int(port)
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func send(payload: Data, to address: sockaddr_in?) {
        let fd = beaconFD
        guard fd >= 0, !payload.isEmpty else { return }

        var destination = address ?? broadcastAddress()
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    _ = sendto(fd, base, raw.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func broadcastAddress() -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(Self.discoveryPort).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("255.255.255.255"))
        return address
    }

    private func addressString(from address: sockaddr_in) -> String {
        var mutable = address
        var host = [CChar](repeating: 0, count: 64)
        let result = withUnsafePointer(to: &mutable) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getnameinfo(socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return result == 0 ? String(cString: host) : ""
    }

    private func isRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private static func makeSocket(broadcast: Bool = false) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return -1 }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        if broadcast {
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        }
        return fd
    }
}
