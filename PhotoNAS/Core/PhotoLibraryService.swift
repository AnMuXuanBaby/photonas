import Foundation
import Photos

struct LibraryError: Error {
    let message: String
}

struct PhotoItem {
    let id: String
    let width: Int
    let height: Int
    let date: Date?
    let isVideo: Bool
    let duration: Double
    let isLivePhoto: Bool
    let isFavorite: Bool

    init(asset: PHAsset) {
        id = asset.localIdentifier
        width = asset.pixelWidth
        height = asset.pixelHeight
        date = asset.creationDate
        isVideo = asset.mediaType == .video
        duration = asset.duration
        isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        isFavorite = asset.isFavorite
    }

    var json: [String: Any] {
        [
            "id": id,
            "w": width,
            "h": height,
            "date": date?.timeIntervalSince1970 ?? 0,
            "video": isVideo,
            "duration": duration,
            "live": isLivePhoto,
            "fav": isFavorite
        ]
    }
}

struct PhotoAlbum {
    let id: String
    let name: String
    let count: Int
}

struct PhotoPage {
    let items: [PhotoItem]
    let total: Int
    let offset: Int
    let limit: Int
}

enum MediaKind: String {
    case all
    case photos
    case videos

    var predicate: NSPredicate? {
        switch self {
        case .all:
            return nil
        case .photos:
            return NSPredicate(format: "mediaType == %ld", PHAssetMediaType.image.rawValue)
        case .videos:
            return NSPredicate(format: "mediaType == %ld", PHAssetMediaType.video.rawValue)
        }
    }
}

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private let workQueue = DispatchQueue(label: "com.photonas.photolibrary", qos: .userInitiated, attributes: .concurrent)
    private let cacheLock = NSLock()
    private var collectionCache: [String: PHAssetCollection] = [:]
    private var countCache: [String: (count: Int, date: Date)] = [:]

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private var isAuthorized: Bool {
        let status = authorizationStatus
        return status == .authorized || status == .limited
    }

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func resetCaches() {
        cacheLock.lock()
        collectionCache.removeAll()
        countCache.removeAll()
        cacheLock.unlock()
    }

    func asset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private func collection(for identifier: String) -> PHAssetCollection? {
        cacheLock.lock()
        let cached = collectionCache[identifier]
        cacheLock.unlock()
        if let cached { return cached }
        let fetched = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
        if let fetched {
            cacheLock.lock()
            collectionCache[identifier] = fetched
            cacheLock.unlock()
        }
        return fetched
    }

    // MARK: - 分页查询

    func fetchPage(
        offset: Int,
        limit: Int,
        kind: MediaKind,
        albumID: String?,
        completion: @escaping (Result<PhotoPage, LibraryError>) -> Void
    ) {
        guard isAuthorized else {
            completion(.failure(LibraryError(message: "尚未获得相册访问权限")))
            return
        }

        workQueue.async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = kind.predicate
            options.fetchOffset = max(0, offset)
            options.fetchLimit = max(1, limit)

            let result: PHFetchResult<PHAsset>
            if let albumID, !albumID.isEmpty, let collection = self.collection(for: albumID) {
                result = PHAsset.fetchAssets(in: collection, options: options)
            } else {
                result = PHAsset.fetchAssets(with: options)
            }

            var items: [PhotoItem] = []
            items.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                items.append(PhotoItem(asset: asset))
            }

            let total = self.totalCount(kind: kind, albumID: albumID)
            completion(.success(PhotoPage(items: items, total: total, offset: offset, limit: limit)))
        }
    }

    func totalCount(kind: MediaKind, albumID: String?) -> Int {
        let key = "\(kind.rawValue)|\(albumID ?? "all")"
        cacheLock.lock()
        if let entry = countCache[key], Date().timeIntervalSince(entry.date) < 30 {
            cacheLock.unlock()
            return entry.count
        }
        cacheLock.unlock()

        let options = PHFetchOptions()
        options.predicate = kind.predicate
        let count: Int
        if let albumID, !albumID.isEmpty, let collection = collection(for: albumID) {
            count = PHAsset.fetchAssets(in: collection, options: options).count
        } else {
            count = PHAsset.fetchAssets(with: options).count
        }

        cacheLock.lock()
        countCache[key] = (count, Date())
        cacheLock.unlock()
        return count
    }

    // MARK: - 相册列表

    func fetchAlbums(completion: @escaping ([PhotoAlbum]) -> Void) {
        guard isAuthorized else {
            completion([])
            return
        }

        workQueue.async {
            var albums: [PhotoAlbum] = []
            var seenNames = Set<String>()

            let smart: [(PHAssetCollectionSubtype, String)] = [
                (.smartAlbumUserLibrary, "所有照片"),
                (.smartAlbumFavorites, "个人收藏"),
                (.smartAlbumRecentlyAdded, "最近添加"),
                (.smartAlbumScreenshots, "截屏"),
                (.smartAlbumLivePhotos, "实况照片"),
                (.smartAlbumPanoramas, "全景照片"),
                (.smartAlbumVideos, "视频"),
                (.smartAlbumSlomoVideos, "慢动作"),
                (.smartAlbumSelfPortraits, "自拍")
            ]

            for (subtype, fallbackName) in smart {
                let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                guard let collection = result.firstObject else { continue }
                let name = collection.localizedTitle ?? fallbackName
                guard seenNames.insert(name).inserted else { continue }
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                guard count > 0 else { continue }
                self.cacheLock.lock()
                self.collectionCache[collection.localIdentifier] = collection
                self.cacheLock.unlock()
                albums.append(PhotoAlbum(id: collection.localIdentifier, name: name, count: count))
            }

            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            userAlbums.enumerateObjects { collection, _, _ in
                let name = collection.localizedTitle ?? "未命名相册"
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                self.cacheLock.lock()
                self.collectionCache[collection.localIdentifier] = collection
                self.cacheLock.unlock()
                albums.append(PhotoAlbum(id: collection.localIdentifier, name: name, count: count))
            }

            completion(albums)
        }
    }
}
