import Foundation
import MusicKit

/// Codable representation of Disc for disk caching
struct CachedDisc: Codable, Sendable {
    let id: String
    let artistName: String
    let albumTitle: String
    let releaseDate: Date?
    let trackCount: Int
    let artistSortKey: String
    let albumSortKey: String

    init(disc: Disc) {
        self.id = disc.id
        self.artistName = disc.artistName
        self.albumTitle = disc.albumTitle
        self.releaseDate = disc.releaseDate
        self.trackCount = disc.trackCount
        self.artistSortKey = disc.artistSortKey
        self.albumSortKey = disc.albumSortKey
    }
}

/// Caches the disc list to disk for instant startup
public final class DiscCache: Sendable {
    public static let shared = DiscCache()

    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("disc_cache.json")
    }

    /// Save discs to disk
    public func save(discs: [Disc]) {
        let cached = discs.map { CachedDisc(disc: $0) }
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: cacheURL)
        } catch {
            // Silently fail - cache is best-effort
        }
    }

    /// Load discs from disk cache
    public func load() -> [Disc]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([CachedDisc].self, from: data) else {
            return nil
        }
        return cached.map { Disc(cached: $0) }
    }

    /// Clear the cache
    public func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
