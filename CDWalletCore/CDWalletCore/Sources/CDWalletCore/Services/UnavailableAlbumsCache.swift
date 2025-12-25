import Foundation

/// Tracks albums that failed catalog resolution so they can be hidden from the wallet
public final class UnavailableAlbumsCache: Sendable {
    public static let shared = UnavailableAlbumsCache()

    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("unavailable_albums.json")
    }

    /// Mark an album as unavailable (by title|artist key)
    public func markUnavailable(title: String, artist: String) {
        var unavailable = load()
        let key = "\(artist.lowercased())|\(title.lowercased())"
        unavailable.insert(key)
        save(unavailable)
    }

    /// Check if an album is known to be unavailable
    public func isUnavailable(title: String, artist: String) -> Bool {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        return load().contains(key)
    }

    /// Clear the unavailable list (e.g., to retry all albums)
    public func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func load() -> Set<String> {
        guard let data = try? Data(contentsOf: cacheURL),
              let list = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return list
    }

    private func save(_ unavailable: Set<String>) {
        if let data = try? JSONEncoder().encode(unavailable) {
            try? data.write(to: cacheURL)
        }
    }
}
