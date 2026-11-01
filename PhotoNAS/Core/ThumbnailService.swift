import Foundation
import Photos
import UIKit

enum ThumbSize: String {
    case grid = "g"
    case viewer = "v"
    case tiny = "t"

    func pixels(settings: AppSettings) -> CGFloat {
        switch self {
        case .grid: return CGFloat(settings.gridThumbnailPixels)
        case .viewer: return CGFloat(settings.viewerThumbnailPixels)
        case .tiny: return 160
        }
    }
}

struct ThumbnailResult {
    let data: Data
    let contentType: String
    let etag: String
    let cacheKey: String
    let fromCache: Bool
}

final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: DiskCache
    private let memory = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var inflight: [String: [(Result<ThumbnailResult, Error>) -> Void]] = [:]
    private let semaphore = DispatchSemaphore(value: 4)
    private let encodeQueue = DispatchQueue(label: "com.photonas.thumbnail.encode", qos: .userInitiated, attributes: .concurrent)
    private let library = PhotoLibraryService.shared

    private init() {
        let settings = SettingsStore.shared.value
        cache = DiskCache(
            directory: AppDirs.thumbnailCache,
            limitBytes: Int64(settings.thumbnailCacheLimitMB) * 1024 * 1024,
            label: "缩略图"
        )
        memory.countLimit = 260
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    func applySettings(_ settings: AppSettings) {
        cache.setLimit(bytes: Int64(settings.thumbnailCacheLimitMB) * 1024 * 1024)
    }

    func cacheStats() -> (count: Int, bytes: Int64, limit: Int64) {
        cache.stats()
    }

    func clearCache() {
        memory.removeAllObjects()
        cache.clear()
    }

    func thumbnail(
        assetID: String,
        size: ThumbSize,
        settings: AppSettings,
        completion: @escaping (Result<ThumbnailResult, Error>) -> Void
    ) {
        var format = settings.thumbnailFormat
        if format == .webp && !ImageEncoding.isWebPAvailable {
            format = .jpeg
        }

        let pixels = Int(size.pixels(settings: settings))
        let quality = format == .webp ? settings.webpQuality : settings.jpegQuality
        let qualityTag = Int(quality * 100)
        let key = "\(AppDirs.hash(assetID))-\(size.rawValue)-\(pixels)-\(format.rawValue)-\(qualityTag).\(format.fileExtension)"
        let memoryKey = key as NSString

        if let data = memory.object(forKey: memoryKey) {
            ServerStats.shared.recordThumbnailCacheHit()
            completion(.success(ThumbnailResult(
                data: data as Data,
                contentType: format.contentType,
                etag: "\"\(key)\"",
                cacheKey: key,
                fromCache: true
            )))
            return
        }

        if let data = cache.data(forKey: key) {
            memory.setObject(data as NSData, forKey: memoryKey, cost: data.count)
            ServerStats.shared.recordThumbnailCacheHit()
            completion(.success(ThumbnailResult(
                data: data,
                contentType: format.contentType,
                etag: "\"\(key)\"",
                cacheKey: key,
                fromCache: true
            )))
            return
        }

        lock.lock()
        if inflight[key] != nil {
            inflight[key]?.append(completion)
            lock.unlock()
            return
        }
        inflight[key] = [completion]
        lock.unlock()

        generate(assetID: assetID, pixels: pixels, format: format, quality: quality, key: key, allowiCloud: settings.allowICloudDownload)
    }

    private func generate(assetID: String, pixels: Int, format: ThumbnailFormat, quality: Double, key: String, allowiCloud: Bool) {
        guard let asset = library.asset(for: assetID) else {
            finish(key, .failure(LibraryError(message: "找不到该照片")))
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.version = .current
        options.isNetworkAccessAllowed = allowiCloud

        let target = CGSize(width: pixels, height: pixels)
        let guardFlag = RequestGuard()

        semaphore.wait()
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard guardFlag.claim() else { return }
            self.semaphore.signal()

            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                self.finish(key, .failure(LibraryError(message: "缩略图请求被取消")))
                return
            }
            if let error = info?[PHImageErrorKey] as? Error {
                self.finish(key, .failure(error))
                return
            }
            guard let cgImage = image?.cgImage else {
                self.finish(key, .failure(LibraryError(message: "照片仍在 iCloud 中，无法在本机生成缩略图")))
                return
            }

            self.encodeQueue.async {
                guard let data = ImageEncoding.encode(image: cgImage, format: format, quality: quality) else {
                    self.finish(key, .failure(LibraryError(message: "缩略图编码失败")))
                    return
                }
                self.memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
                self.cache.store(data, forKey: key)
                ServerStats.shared.recordThumbnailGenerated()
                self.finish(key, .success(ThumbnailResult(
                    data: data,
                    contentType: ImageEncoding.contentType(of: data, fallback: format),
                    etag: "\"\(key)\"",
                    cacheKey: key,
                    fromCache: false
                )))
            }
        }
    }

    private func finish(_ key: String, _ result: Result<ThumbnailResult, Error>) {
        lock.lock()
        let waiters = inflight.removeValue(forKey: key) ?? []
        lock.unlock()
        for waiter in waiters {
            waiter(result)
        }
    }

    private final class RequestGuard {
        private let lock = NSLock()
        private var finished = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }
}
