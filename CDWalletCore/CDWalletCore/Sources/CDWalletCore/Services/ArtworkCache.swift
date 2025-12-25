import Foundation
import UIKit
import MusicKit

/// Caches artwork images for fast UI rendering (memory + disk)
public actor ArtworkCache {
    public static let shared = ArtworkCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let maxMemoryCacheSize = 50 // albums
    private let diskCacheDirectory: URL

    private init() {
        memoryCache.countLimit = maxMemoryCacheSize

        // Set up disk cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDirectory = caches.appendingPathComponent("ArtworkCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    /// Fetch artwork for an album, using cache when available
    public func artwork(for disc: Disc, size: CGSize) async -> UIImage? {
        let cacheKey = cacheKey(albumID: disc.id, size: size)

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache
        if let diskCached = loadFromDisk(key: cacheKey) {
            memoryCache.setObject(diskCached, forKey: cacheKey as NSString)
            return diskCached
        }

        // Try disc artwork first
        if let discArtwork = disc.artwork {
            if let image = await fetchImage(from: discArtwork, size: size, albumTitle: disc.albumTitle) {
                cacheImage(image, forKey: cacheKey)
                return image
            }
        }

        // Fall back to catalog search
        if let catalogArtwork = await searchCatalogForArtwork(title: disc.albumTitle, artist: disc.artistName) {
            if let image = await fetchImage(from: catalogArtwork, size: size, albumTitle: disc.albumTitle) {
                cacheImage(image, forKey: cacheKey)
                return image
            }
        }

        return nil
    }

    /// Cache image to both memory and disk
    private func cacheImage(_ image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(image: image, key: key)
    }

    /// Save image to disk cache
    private func saveToDisk(image: UIImage, key: String) {
        let fileURL = diskCacheDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".jpg")
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL)
        }
    }

    /// Load image from disk cache
    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = diskCacheDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Fetch image from artwork URL
    private func fetchImage(from artwork: Artwork, size: CGSize, albumTitle: String) async -> UIImage? {
        guard let url = artwork.url(width: Int(size.width), height: Int(size.height)) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// Search the catalog for artwork when library album doesn't have it
    private func searchCatalogForArtwork(title: String, artist: String) async -> Artwork? {
        do {
            var searchRequest = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Album.self])
            searchRequest.limit = 5
            let searchResponse = try await searchRequest.response()

            let titleLower = title.lowercased()
            let artistLower = artist.lowercased()

            // Try exact match first
            for album in searchResponse.albums {
                if album.title.lowercased() == titleLower &&
                   album.artistName.lowercased() == artistLower {
                    return album.artwork
                }
            }

            // Fall back to first result
            return searchResponse.albums.first?.artwork
        } catch {
            return nil
        }
    }

    private func cacheKey(albumID: String, size: CGSize) -> String {
        "\(albumID)_\(Int(size.width))x\(Int(size.height))"
    }

    /// Remove cached artwork for albums no longer in the wallet
    public func cleanup(keepingAlbumIDs: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in files {
            let filename = fileURL.deletingPathExtension().lastPathComponent
            // Extract album ID from filename (format: "albumID_WIDTHxHEIGHT")
            if let albumID = filename.components(separatedBy: "_").first,
               !keepingAlbumIDs.contains(albumID) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
