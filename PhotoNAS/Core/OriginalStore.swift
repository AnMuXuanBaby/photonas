import Foundation
import Photos
import UniformTypeIdentifiers

final class OriginalStore {
    struct OriginalFile {
        let url: URL
        let mime: String
        let filename: String
        let size: Int64
    }

    static let shared = OriginalStore()

    private let cache: DiskCache
    private let writeQueue = DispatchQueue(label: "com.photonas.original", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var inflight: [String: [(Result<OriginalFile, Error>) -> Void]] = [:]

    private init() {
        let settings = SettingsStore.shared.value
        cache = DiskCache(
            directory: AppDirs.originalCache,
            limitBytes: Int64(settings.originalCacheLimitMB) * 1024 * 1024,
            label: "原图"
        )
    }

    func applySettings(_ settings: AppSettings) {
        cache.setLimit(bytes: Int64(settings.originalCacheLimitMB) * 1024 * 1024)
    }

    func cacheStats() -> (count: Int, bytes: Int64, limit: Int64) {
        cache.stats()
    }

    func clearCache() {
        cache.clear()
    }

    func file(
        assetID: String,
        allowiCloud: Bool,
        completion: @escaping (Result<OriginalFile, Error>) -> Void
    ) {
        guard let asset = PhotoLibraryService.shared.asset(for: assetID) else {
            completion(.failure(LibraryError(message: "找不到该资源")))
            return
        }
        guard let resource = Self.preferredResource(for: asset) else {
            completion(.failure(LibraryError(message: "该照片没有可下载的原始文件")))
            return
        }

        let rawExtension = (resource.originalFilename as NSString).pathExtension.lowercased()
        let fileExtension = rawExtension.isEmpty ? "bin" : rawExtension
        let key = "\(AppDirs.hash(assetID)).\(fileExtension)"
        let targetURL = cache.directory.appendingPathComponent(key)
        let mime = Self.mimeType(for: resource, fallbackExtension: fileExtension)
        let filename = resource.originalFilename

        if let resolved = Self.existingFile(at: targetURL, mime: mime, filename: filename, key: key, cache: cache) {
            completion(.success(resolved))
            return
        }

        lock.lock()
        if inflight[assetID] != nil {
            inflight[assetID]?.append(completion)
            lock.unlock()
            return
        }
        inflight[assetID] = [completion]
        lock.unlock()

        let temporaryURL = cache.directory.appendingPathComponent(key + ".part")
        try? FileManager.default.removeItem(at: temporaryURL)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowiCloud

        writeQueue.async {
            PHAssetResourceManager.default().writeData(for: resource, toFile: temporaryURL, options: options) { error in
                if let error {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    self.finish(assetID, .failure(error))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: targetURL)
                    try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
                } catch {
                    self.finish(assetID, .failure(error))
                    return
                }
                self.cache.registerFile(url: targetURL, key: key)
                guard let resolved = Self.existingFile(at: targetURL, mime: mime, filename: filename, key: key, cache: self.cache) else {
                    self.finish(assetID, .failure(LibraryError(message: "原始文件写入失败")))
                    return
                }
                self.finish(assetID, .success(resolved))
            }
        }
    }

    private static func existingFile(at url: URL, mime: String, filename: String, key: String, cache: DiskCache) -> OriginalFile? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber,
              number.int64Value > 0 else {
            return nil
        }
        return OriginalFile(url: url, mime: mime, filename: filename, size: number.int64Value)
    }

    private func finish(_ assetID: String, _ result: Result<OriginalFile, Error>) {
        lock.lock()
        let waiters = inflight.removeValue(forKey: assetID) ?? []
        lock.unlock()
        for waiter in waiters {
            waiter(result)
        }
    }

    private static func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return nil }

        let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo, .pairedVideo]
            : [.fullSizePhoto, .photo, .alternatePhoto]

        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }
        return resources.first
    }

    private static func mimeType(for resource: PHAssetResource, fallbackExtension: String) -> String {
        let identifier = resource.uniformTypeIdentifier
        if let type = UTType(identifier), let mime = type.preferredMIMEType {
            return mime
        }
        if let type = UTType(filenameExtension: fallbackExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
