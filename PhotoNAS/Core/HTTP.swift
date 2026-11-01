import Foundation

// MARK: - 请求

struct HTTPRequest {
    let method: String
    let rawTarget: String
    let path: String
    let query: [String: String]
    let version: String
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func queryValue(_ name: String) -> String? {
        query[name]
    }

    func queryInt(_ name: String) -> Int? {
        guard let raw = query[name] else { return nil }
        return Int(raw)
    }

    var isHead: Bool { method == "HEAD" }

    var keepAlive: Bool {
        let connection = header("connection")?.lowercased()
        if version.uppercased() == "HTTP/1.0" {
            return connection == "keep-alive"
        }
        return connection != "close"
    }
}

enum HTTPParseResult {
    case incomplete
    case badRequest
    case ok(HTTPRequest)
}

enum HTTPParser {
    static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> HTTPParseResult {
        guard let terminator = buffer.range(of: headerTerminator) else {
            return buffer.count > 48 * 1024 ? .badRequest : .incomplete
        }

        let headData = buffer.subdata(in: 0..<terminator.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return .badRequest }

        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else { return .badRequest }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .badRequest }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let version = parts.count >= 3 ? String(parts[2]) : "HTTP/1.1"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            if let existing = headers[key] {
                headers[key] = existing + ", " + value
            } else {
                headers[key] = value
            }
        }

        var path = target
        var query: [String: String] = [:]
        if let questionMark = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<questionMark])
            let queryString = String(target[target.index(after: questionMark)...])
            for pair in queryString.split(separator: "&") {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let first = pieces.first else { continue }
                let rawKey = String(first)
                let key = rawKey.removingPercentEncoding ?? rawKey
                var rawValue = pieces.count > 1 ? String(pieces[1]) : ""
                rawValue = rawValue.replacingOccurrences(of: "+", with: " ")
                let value = rawValue.removingPercentEncoding ?? rawValue
                query[key] = value
            }
        }

        let decodedPath = path.removingPercentEncoding ?? path
        return .ok(HTTPRequest(method: method, rawTarget: target, path: decodedPath, query: query, version: version, headers: headers))
    }
}

// MARK: - 响应

struct HTTPResponse {
    enum Body {
        case empty
        case data(Data)
        case file(url: URL, offset: Int64, length: Int64)
    }

    var status: Int
    var headers: [String: String]
    var body: Body

    init(status: Int = 200, headers: [String: String] = [:], body: Body = .empty) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    var byteCount: Int64 {
        switch body {
        case .empty: return 0
        case .data(let data): return Int64(data.count)
        case .file(_, _, let length): return length
        }
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

// MARK: - 响应构造

enum Responses {
    static func text(_ message: String, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        var headers = ["Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store"]
        headers.merge(extraHeaders) { _, new in new }
        return HTTPResponse(status: status, headers: headers, body: .data(Data(message.utf8)))
    }

    static func html(_ markup: String, status: Int = 200) -> HTTPResponse {
        let headers: [String: String] = [
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-cache"
        ]
        return HTTPResponse(status: status, headers: headers, body: .data(Data(markup.utf8)))
    }

    static func json(_ object: Any, status: Int = 200, cacheControl: String = "no-store") -> HTTPResponse {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return text("JSON encode failed", status: 500)
        }
        let headers: [String: String] = [
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": cacheControl
        ]
        return HTTPResponse(status: status, headers: headers, body: .data(data))
    }

    static func notModified(etag: String) -> HTTPResponse {
        var headers: [String: String] = ["ETag": etag, "Cache-Control": "public, max-age=604800"]
        headers["Content-Length"] = "0"
        return HTTPResponse(status: 304, headers: headers, body: .empty)
    }

    /// 支持 Range 的文件响应。视频/原图下载都走这里。
    static func file(
        url: URL,
        mime: String,
        request: HTTPRequest,
        filename: String? = nil,
        forceDownload: Bool = false,
        extraHeaders: [String: String] = [:]
    ) -> HTTPResponse {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return text("File not found", status: 404)
        }
        let size = sizeNumber.int64Value

        var headers: [String: String] = [
            "Content-Type": mime,
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=86400"
        ]
        if let filename {
            headers["Content-Disposition"] = contentDisposition(filename: filename, inline: !forceDownload)
        }
        headers.merge(extraHeaders) { _, new in new }

        let rangeResult = RangeParser.parse(request.header("range"), size: size, ifRange: request.header("if-range"))
        switch rangeResult {
        case .unsatisfiable:
            headers["Content-Range"] = "bytes */\(size)"
            return HTTPResponse(status: 416, headers: headers, body: .empty)
        case .satisfied(let start, let end):
            headers["Content-Range"] = "bytes \(start)-\(end)/\(size)"
            headers["Content-Length"] = String(end - start + 1)
            return HTTPResponse(status: 206, headers: headers, body: .file(url: url, offset: start, length: end - start + 1))
        case .none:
            headers["Content-Length"] = String(size)
            return HTTPResponse(status: 200, headers: headers, body: .file(url: url, offset: 0, length: size))
        }
    }

    static func contentDisposition(filename: String, inline: Bool) -> String {
        let type = inline ? "inline" : "attachment"
        let asciiFallback = String(filename.map { character -> Character in
            guard let scalar = character.unicodeScalars.first, scalar.isASCII, scalar.value >= 32, scalar.value != 34 else {
                return "_"
            }
            return character
        })
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
        return "\(type); filename=\"\(asciiFallback)\"; filename*=UTF-8''\(encoded)"
    }
}

// MARK: - Range 解析

enum RangeParseResult {
    case none
    case satisfied(Int64, Int64)
    case unsatisfiable
}

enum RangeParser {
    static func parse(_ header: String?, size: Int64, ifRange: String?) -> RangeParseResult {
        guard let header, !header.isEmpty else { return .none }
        if let ifRange, !ifRange.isEmpty, ifRange != "\"photonas\"" { return .none }

        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return .none }
        let spec = String(trimmed.dropFirst("bytes=".count))
        guard !spec.contains(",") else { return .none }

        let pieces = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return .unsatisfiable }

        let startText = String(pieces[0]).trimmingCharacters(in: .whitespaces)
        let endText = String(pieces[1]).trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            guard let suffix = Int64(endText.trimmingCharacters(in: .whitespaces)), suffix > 0 else { return .unsatisfiable }
            let length = min(suffix, size)
            let start = size - length
            guard length > 0 else { return .unsatisfiable }
            return .satisfied(start, size - 1)
        }

        guard let start = Int64(startText), start >= 0 else { return .unsatisfiable }
        guard start < size else { return .unsatisfiable }

        if endText.isEmpty {
            return .satisfied(start, size - 1)
        }
        guard let rawEnd = Int64(endText), rawEnd >= start else { return .unsatisfiable }
        let end = min(rawEnd, size - 1)
        return .satisfied(start, end)
    }
}
