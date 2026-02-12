//
//  PhotoManager.swift
//  LITA
//

import Photos
import UIKit

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let collection: PHAssetCollection
    let title: String
    let count: Int

    static func == (lhs: AlbumInfo, rhs: AlbumInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class PhotoManager: ObservableObject {
    @Published var albums: [AlbumInfo] = []
    @Published var thumbnails: [UIImage] = []
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0   // 0…1 for thumbnail batch
    @Published var isFetchingMemory = false
    @Published var memoryDownloadProgress: Double = 0  // 0…1 for single hi-res photo
    @Published var permissionGranted = false
    @Published var permissionDenied = false

    private(set) var allAssets: PHFetchResult<PHAsset>?

    // MARK: - Permission

    func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    self?.permissionGranted = true
                    self?.fetchAlbums()
                default:
                    self?.permissionDenied = true
                }
            }
        }
    }

    // MARK: - Fetch Albums

    private func fetchAlbums() {
        var results: [AlbumInfo] = []

        let imageOnly = PHFetchOptions()
        imageOnly.predicate = NSPredicate(
            format: "mediaType = %d", PHAssetMediaType.image.rawValue
        )

        // Regular user albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: imageOnly).count
            if count > 0 {
                results.append(AlbumInfo(
                    id: collection.localIdentifier,
                    collection: collection,
                    title: collection.localizedTitle ?? "Untitled",
                    count: count
                ))
            }
        }

        // Shared iCloud albums
        let sharedAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumCloudShared, options: nil
        )
        sharedAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: imageOnly).count
            if count > 0 {
                results.append(AlbumInfo(
                    id: collection.localIdentifier,
                    collection: collection,
                    title: collection.localizedTitle ?? "Shared Album",
                    count: count
                ))
            }
        }

        // Smart albums (Recents, Favorites, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .any, options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: imageOnly).count
            if count > 0 {
                results.append(AlbumInfo(
                    id: collection.localIdentifier,
                    collection: collection,
                    title: collection.localizedTitle ?? "Album",
                    count: count
                ))
            }
        }

        self.albums = results.sorted { $0.count > $1.count }
    }

    // MARK: - Load Thumbnails (random sample of ~200)

    func loadThumbnails(from album: AlbumInfo, maxCount: Int = 200) {
        isLoading = true
        loadingProgress = 0
        thumbnails = []

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d", PHAssetMediaType.image.rawValue
        )
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        let assets = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)
        self.allAssets = assets

        guard assets.count > 0 else {
            isLoading = false
            return
        }

        let totalCount = assets.count
        let sampleCount = min(maxCount, totalCount)
        var indices = Array(0..<totalCount)
        indices.shuffle()
        let selectedIndices = Array(indices.prefix(sampleCount))

        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let total = Double(sampleCount)
        for index in selectedIndices {
            let asset = assets.object(at: index)
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 128, height: 128),
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                DispatchQueue.main.async {
                    self.thumbnails.append(image)
                    self.loadingProgress = Double(self.thumbnails.count) / total
                    if self.thumbnails.count >= sampleCount {
                        self.isLoading = false
                    }
                }
            }
        }

        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.isLoading = false
        }
    }

    // MARK: - Fetch Random Full Photo (from entire album)

    func fetchRandomPhoto(completion: @escaping (UIImage?, PHAsset?) -> Void) {
        guard let assets = allAssets, assets.count > 0 else {
            completion(nil, nil)
            return
        }

        let randomIndex = Int.random(in: 0..<assets.count)
        let asset = assets.object(at: randomIndex)

        isFetchingMemory = true
        memoryDownloadProgress = 0

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        options.progressHandler = { [weak self] progress, _, _, _ in
            DispatchQueue.main.async {
                self?.memoryDownloadProgress = progress
            }
        }

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !isDegraded else { return }
            DispatchQueue.main.async {
                self?.isFetchingMemory = false
                self?.memoryDownloadProgress = 1
                completion(image, asset)
            }
        }
    }
}
