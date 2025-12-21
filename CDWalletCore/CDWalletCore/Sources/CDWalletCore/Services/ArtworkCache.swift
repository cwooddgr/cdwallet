import Foundation
import UIKit
import MusicKit

/// Caches artwork images for fast UI rendering
public actor ArtworkCache {
    public static let shared = ArtworkCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let maxMemoryCacheSize = 50 // albums

    private init() {
        memoryCache.countLimit = maxMemoryCacheSize
    }

    /// Fetch artwork for an album, using cache when available
    public func artwork(for disc: Disc, size: CGSize) async -> UIImage? {
        let cacheKey = cacheKey(albumID: disc.id, size: size)

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Try disc artwork first
        if let discArtwork = disc.artwork {
            if let image = await fetchImage(from: discArtwork, size: size, albumTitle: disc.albumTitle) {
                memoryCache.setObject(image, forKey: cacheKey as NSString)
                return image
            }
            // Local artwork failed (not cached on device) - fall through to catalog search
            print("📀 DEBUG: ArtworkCache - Local artwork failed for '\(disc.albumTitle)', trying catalog...")
        }

        // Fall back to catalog search
        if let catalogArtwork = await searchCatalogForArtwork(title: disc.albumTitle, artist: disc.artistName) {
            if let image = await fetchImage(from: catalogArtwork, size: size, albumTitle: disc.albumTitle) {
                memoryCache.setObject(image, forKey: cacheKey as NSString)
                return image
            }
        }

        print("📀 DEBUG: ArtworkCache - No artwork found for '\(disc.albumTitle)'")
        return nil
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
            print("📀 DEBUG: ArtworkCache - Fetch error for '\(albumTitle)': \(error.localizedDescription)")
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

            for album in searchResponse.albums {
                if album.title.lowercased() == titleLower &&
                   album.artistName.lowercased() == artistLower {
                    print("📀 DEBUG: ArtworkCache - Found catalog artwork for '\(title)'")
                    return album.artwork
                }
            }

            // If no exact match, use first result as fallback
            if let firstAlbum = searchResponse.albums.first {
                print("📀 DEBUG: ArtworkCache - Using first catalog result artwork for '\(title)'")
                return firstAlbum.artwork
            }

            print("📀 DEBUG: ArtworkCache - No catalog results for '\(title)'")
            return nil
        } catch {
            print("📀 DEBUG: ArtworkCache - Error searching catalog for artwork: \(error)")
            return nil
        }
    }

    private func cacheKey(albumID: String, size: CGSize) -> String {
        "\(albumID)_\(Int(size.width))x\(Int(size.height))"
    }
}
