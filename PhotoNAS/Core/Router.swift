import Foundation
import UIKit

final class Router {
    private let library = PhotoLibraryService.shared
    private let thumbnails = ThumbnailService.shared
    private let originals = OriginalStore.shared

    func handle(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        if request.method == "OPTIONS" {
            completion(HTTPResponse(status: 204, headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                "Access-Control-Max-Age": "86400"
            ], body: .empty))
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            completion(Responses.text("Method Not Allowed", status: 405))
            return
        }

        switch request.path {
        case "/":
            completion(Responses.html(WebAssets.indexHTML))
        case "/health":
            completion(Responses.text("ok"))
        case "/api/info":
            handleInfo(completion)
        case "/api/photos":
            handlePhotos(request, completion)
        case "/api/albums":
            handleAlbums(completion)
        case "/api/logs":
            handleLogs(request, completion)
        case "/thumb":
            handleThumbnail(request, completion)
        case "/original":
            handleOriginal(request, completion)
        case "/media":
            handleOriginal(request, completion)
        default:
            completion(Responses.text("Not Found", status: 404))
        }
    }

    // MARK: - 接口

    private func handleInfo(_ completion: @escaping (HTTPResponse) -> Void) {
        let settings = SettingsStore.shared.value
        let authorized = library.authorizationStatus == .authorized || library.authorizationStatus == .limited

        DispatchQueue.global(qos: .userInitiated).async {
            let total = authorized ? self.library.totalCount(kind: .all, albumID: nil) : 0
            let stats = ServerStats.shared.snapshot()
            let thumbStats = self.thumbnails.cacheStats()
            let originalStats = self.originals.cacheStats()

            let payload: [String: Any] = [
                "name": self.displayName(settings),
                "version": "1.0.0",
                "authorized": authorized,
                "total": total,
                "pageSize": settings.pageSize,
                "format": self.effectiveFormat(settings).rawValue,
                "webpAvailable": ImageEncoding.isWebPAvailable,
                "ip": NetInfo.localIPv4() ?? "",
                "port": settings.serverPort,
                "stats": [
                    "requests": stats.requests,
                    "bytes": stats.bytes,
                    "thumbnails": stats.thumbnailsGenerated,
                    "cacheHits": stats.thumbnailCacheHits,
                    "thumbCacheCount": thumbStats.count,
                    "thumbCacheBytes": thumbStats.bytes,
                    "thumbCacheLimit": thumbStats.limit,
                    "originalCacheCount": originalStats.count,
                    "originalCacheBytes": originalStats.bytes,
                    "originalCacheLimit": originalStats.limit
                ]
            ]
            completion(Responses.json(payload))
        }
    }

    private func handlePhotos(_ request: HTTPRequest, _ completion: @escaping (HTTPResponse) -> Void) {
        let settings = SettingsStore.shared.value
        let page = max(0, request.queryInt("page") ?? 0)
        let size = min(max(request.queryInt("size") ?? settings.pageSize, 1), 200)
        let kind = MediaKind(rawValue: request.queryValue("kind") ?? "all") ?? .all
        let albumID = request.queryValue("album")
        let format = effectiveFormat(settings)

        library.fetchPage(offset: page * size, limit: size, kind: kind, albumID: albumID) { result in
            switch result {
            case .success(let slice):
                let loaded = page * size + slice.items.count
                let payload: [String: Any] = [
                    "page": page,
                    "size": size,
                    "total": slice.total,
                    "hasMore": loaded < slice.total,
                    "format": format.rawValue,
                    "items": slice.items.map { $0.json }
                ]
                completion(Responses.json(payload))
            case .failure(let error):
                completion(Responses.text(error.message, status: 403))
            }
        }
    }

    private func handleAlbums(_ completion: @escaping (HTTPResponse) -> Void) {
        library.fetchAlbums { albums in
            let payload: [String: Any] = [
                "albums": albums.map { album -> [String: Any] in
                    ["id": album.id, "name": album.name, "count": album.count]
                }
            ]
            completion(Responses.json(payload))
        }
    }

    private func handleLogs(_ request: HTTPRequest, _ completion: @escaping (HTTPResponse) -> Void) {
        let limit = min(max(request.queryInt("limit") ?? 100, 1), 1000)
        let entries = LogStore.shared.snapshot(limit: limit).map { $0.json }
        completion(Responses.json(["entries": entries]))
    }

    private func handleThumbnail(_ request: HTTPRequest, _ completion: @escaping (HTTPResponse) -> Void) {
        guard let identifier = request.queryValue("id"), !identifier.isEmpty else {
            completion(Responses.text("missing id", status: 400))
            return
        }
        let settings = SettingsStore.shared.value
        let size = ThumbSize(rawValue: request.queryValue("s") ?? "g") ?? .grid

        thumbnails.thumbnail(assetID: identifier, size: size, settings: settings) { result in
            switch result {
            case .success(let thumb):
                if request.header("if-none-match") == thumb.etag {
                    completion(Responses.notModified(etag: thumb.etag))
                    return
                }
                let headers: [String: String] = [
                    "Content-Type": thumb.contentType,
                    "ETag": thumb.etag,
                    "Cache-Control": "public, max-age=604800, immutable",
                    "X-Thumb-Cache": thumb.fromCache ? "HIT" : "MISS"
                ]
                completion(HTTPResponse(status: 200, headers: headers, body: .data(thumb.data)))
            case .failure(let error):
                completion(Responses.text(error.localizedDescription, status: 503))
            }
        }
    }

    private func handleOriginal(_ request: HTTPRequest, _ completion: @escaping (HTTPResponse) -> Void) {
        guard let identifier = request.queryValue("id"), !identifier.isEmpty else {
            completion(Responses.text("missing id", status: 400))
            return
        }
        let settings = SettingsStore.shared.value
        let forceDownload = request.queryValue("dl") == "1"

        originals.file(assetID: identifier, allowiCloud: settings.allowICloudDownload) { result in
            switch result {
            case .success(let file):
                completion(Responses.file(
                    url: file.url,
                    mime: file.mime,
                    request: request,
                    filename: forceDownload ? file.filename : nil,
                    forceDownload: forceDownload
                ))
            case .failure(let error):
                completion(Responses.text(error.localizedDescription, status: 503))
            }
        }
    }

    // MARK: - 辅助

    private func effectiveFormat(_ settings: AppSettings) -> ThumbnailFormat {
        if settings.thumbnailFormat == .webp && !ImageEncoding.isWebPAvailable {
            return .jpeg
        }
        return settings.thumbnailFormat
    }

    private func displayName(_ settings: AppSettings) -> String {
        let nickname = settings.serverNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        let device = UIDevice.current.name
        return device.isEmpty ? "PhotoNAS" : device
    }
}
