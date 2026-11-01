import Foundation
import Network

final class HTTPServer {
    struct Configuration {
        var port: UInt16 = 8080
        var serviceName: String = "PhotoNAS"
        var maxConnections: Int = 40
    }

    var onStateChange: ((Bool, String?) -> Void)?

    private let queue = DispatchQueue(label: "com.photonas.http.server")
    private let router = Router()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private var configuration = Configuration()

    func start(configuration: Configuration) throws {
        var thrown: Error?
        queue.sync {
            self.stopInternal()
            self.configuration = configuration
            do {
                try self.startInternal(configuration)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    func stop() {
        queue.async {
            self.stopInternal()
        }
    }

    private func startInternal(_ configuration: Configuration) throws {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw LibraryError(message: "端口号无效")
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        let listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(name: configuration.serviceName, type: "_photonas._tcp")

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.notify(state: true, message: nil)
            case .failed(let error):
                self.listener?.cancel()
                self.listener = nil
                self.notify(state: false, message: Self.describe(error))
            case .waiting(let error):
                self.notify(state: false, message: Self.describe(error))
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.queue.async {
                self.accept(connection)
            }
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    private func stopInternal() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        if connections.count >= configuration.maxConnections {
            Self.reject(connection)
            return
        }

        let remote = Self.remoteAddress(from: connection.endpoint)
        let handler = HTTPConnection(connection: connection, router: router, remoteAddress: remote)
        handler.onLog = { entry in
            LogStore.shared.append(entry)
        }
        handler.onClose = { [weak self, weak handler] in
            guard let self, let handler else { return }
            self.queue.async {
                self.connections.removeValue(forKey: ObjectIdentifier(handler))
            }
        }
        connections[ObjectIdentifier(handler)] = handler
        handler.start()
    }

    private func notify(state: Bool, message: String?) {
        DispatchQueue.main.async {
            self.onStateChange?(state, message)
        }
    }

    private static func remoteAddress(from endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, _) = endpoint {
            switch host {
            case .ipv4(let address):
                return "\(address)"
            case .ipv6(let address):
                return "\(address)"
            case .name(let name, _):
                return name
            default:
                return "\(host)"
            }
        }
        return "unknown"
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix:
            return "监听失败：端口可能已被占用，请在设置里换个端口。(\(error))"
        case .dns:
            return "网络名称解析失败。(\(error))"
        default:
            return "网络错误：(\(error))"
        }
    }

    private static func reject(_ connection: NWConnection) {
        let body = Data("Too many connections".utf8)
        let head = "HTTP/1.1 503 Service Unavailable\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let rejectQueue = DispatchQueue(label: "com.photonas.http.reject")
        connection.start(queue: rejectQueue)
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            connection.send(content: body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        })
    }
}

// MARK: - 单个连接

extension HTTPRequest {
    var queryString: String {
        guard let mark = rawTarget.firstIndex(of: "?") else { return "" }
        return String(rawTarget[rawTarget.index(after: mark)...])
    }
}

final class HTTPConnection {
    var onClose: (() -> Void)?
    var onLog: ((AccessLogEntry) -> Void)?

    private let connection: NWConnection
    private let router: Router
    private let remoteAddress: String
    private let workQueue: DispatchQueue

    private var buffer = Data()
    private var closed = false
    private var isBusy = false
    private var isReceiving = false
    private var clientEOF = false
    private var idleWorkItem: DispatchWorkItem?

    private static let headerLimit = 64 * 1024
    private static let bodyChunk = 512 * 1024
    private static let idleTimeout: TimeInterval = 75

    init(connection: NWConnection, router: Router, remoteAddress: String) {
        self.connection = connection
        self.router = router
        self.remoteAddress = remoteAddress
        self.workQueue = DispatchQueue(label: "com.photonas.http.conn", qos: .userInitiated)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: workQueue)
        resetIdleTimer()
        receiveNext()
    }

    func cancel() {
        workQueue.async {
            self.close()
        }
    }

    private func receiveNext() {
        guard !closed, !isReceiving else { return }
        isReceiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.isReceiving = false
            if error != nil {
                self.close()
                return
            }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.resetIdleTimer()
            }
            if isComplete {
                self.clientEOF = true
            }
            self.pump()
        }
    }

    private func pump() {
        guard !closed, !isBusy else { return }

        guard let terminator = buffer.range(of: HTTPParser.headerTerminator) else {
            if buffer.count > Self.headerLimit {
                sendSimple(status: 400, message: "Request header too large")
            } else if clientEOF {
                close()
            } else {
                receiveNext()
            }
            return
        }

        let result = HTTPParser.parse(buffer.subdata(in: 0..<terminator.upperBound))
        switch result {
        case .incomplete:
            if buffer.count > Self.headerLimit {
                sendSimple(status: 400, message: "Request header too large")
            }
        case .badRequest:
            buffer.removeAll()
            sendSimple(status: 400, message: "Bad Request")
        case .ok(let request):
            buffer.removeSubrange(0..<terminator.upperBound)
            isBusy = true
            let startedAt = Date()
            router.handle(request) { [weak self] response in
                guard let self else { return }
                self.workQueue.async {
                    self.write(response, for: request, startedAt: startedAt)
                }
            }
        }
    }

    private func sendSimple(status: Int, message: String) {
        isBusy = true
        let data = Data(message.utf8)
        let response = HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain; charset=utf-8", "Content-Length": String(data.count)],
            body: .data(data)
        )
        write(response, for: nil, startedAt: Date())
    }

    private func write(_ response: HTTPResponse, for request: HTTPRequest?, startedAt: Date) {
        guard !closed else { return }

        var resp = response
        let keepAlive = request?.keepAlive == true && !clientEOF && request?.method != "POST"
        resp.headers["Date"] = Self.httpDate()
        resp.headers["Server"] = "PhotoNAS/1.0"
        resp.headers["Access-Control-Allow-Origin"] = "*"
        resp.headers["Access-Control-Allow-Headers"] = "*"
        resp.headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
        if resp.headers["Content-Length"] == nil {
            resp.headers["Content-Length"] = String(resp.byteCount)
        }
        if resp.headers["Content-Type"] == nil, resp.byteCount > 0 {
            resp.headers["Content-Type"] = "application/octet-stream"
        }
        if keepAlive {
            resp.headers["Connection"] = "keep-alive"
        } else {
            resp.headers["Connection"] = "close"
        }

        var head = "HTTP/1.1 \(resp.status) \(HTTPResponse.reason(resp.status))\r\n"
        for key in resp.headers.keys.sorted() {
            head += "\(key): \(resp.headers[key] ?? "")\r\n"
        }
        head += "\r\n"

        let allowBody = request?.isHead != true

        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.close()
                return
            }
            self.sendBody(resp.body, allowBody: allowBody) {
                self.finishRequest(response: resp, request: request, allowBody: allowBody, startedAt: startedAt, keepAlive: keepAlive)
            }
        })
    }

    private func finishRequest(response: HTTPResponse, request: HTTPRequest?, allowBody: Bool, startedAt: Date, keepAlive: Bool) {
        if let request {
            let userAgent = request.header("user-agent") ?? ""
            let entry = AccessLogEntry(
                id: UUID(),
                date: Date(),
                ip: remoteAddress,
                method: request.method,
                path: request.path,
                query: request.queryString,
                status: response.status,
                bytes: allowBody ? response.byteCount : 0,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                userAgent: userAgent,
                device: DeviceParser.describe(userAgent: userAgent)
            )
            onLog?(entry)
            ServerStats.shared.recordRequest(bytes: allowBody ? response.byteCount : 0)
        }

        isBusy = false
        if closed { return }
        if keepAlive {
            resetIdleTimer()
            pump()
        } else {
            close()
        }
    }

    private func sendBody(_ body: HTTPResponse.Body, allowBody: Bool, completed: @escaping () -> Void) {
        guard allowBody else {
            completed()
            return
        }
        switch body {
        case .empty:
            completed()
        case .data(let data):
            sendData(data, completed: completed)
        case .file(let url, let offset, let length):
            sendFile(url: url, offset: offset, length: length, completed: completed)
        }
    }

    private func sendData(_ data: Data, completed: @escaping () -> Void) {
        if data.count <= Self.bodyChunk {
            connection.send(content: data, completion: .contentProcessed { error in
                _ = error
                completed()
            })
            return
        }

        var remaining = data
        func sendNext() {
            guard !remaining.isEmpty else {
                completed()
                return
            }
            let size = min(Self.bodyChunk, remaining.count)
            let chunk = Data(remaining.prefix(size))
            remaining.removeFirst(size)
            connection.send(content: chunk, completion: .contentProcessed { error in
                if error != nil {
                    completed()
                    return
                }
                sendNext()
            })
        }
        sendNext()
    }

    private func sendFile(url: URL, offset: Int64, length: Int64, completed: @escaping () -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            completed()
            return
        }
        do {
            try handle.seek(toOffset: UInt64(max(0, offset)))
        } catch {
            try? handle.close()
            completed()
            return
        }

        var remaining = max(0, length)
        func sendNextChunk() {
            if remaining <= 0 {
                try? handle.close()
                completed()
                return
            }
            let readSize = Int(min(remaining, Int64(Self.bodyChunk)))
            let chunk = (try? handle.read(upToCount: readSize)) ?? nil
            guard let data = chunk, !data.isEmpty else {
                try? handle.close()
                completed()
                return
            }
            remaining -= Int64(data.count)
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil {
                    try? handle.close()
                    completed()
                    return
                }
                sendNextChunk()
            })
        }
        sendNextChunk()
    }

    private func resetIdleTimer() {
        idleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.close()
        }
        idleWorkItem = item
        workQueue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: item)
    }

    private func close() {
        guard !closed else { return }
        closed = true
        idleWorkItem?.cancel()
        idleWorkItem = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
    }

    private static func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
