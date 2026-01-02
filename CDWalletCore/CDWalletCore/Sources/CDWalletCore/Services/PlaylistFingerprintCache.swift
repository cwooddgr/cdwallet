import Foundation

/// Caches a fingerprint of the playlist (track IDs) to detect changes
public final class PlaylistFingerprintCache: Sendable {
    public static let shared = PlaylistFingerprintCache()

    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("playlist_fingerprint.json")
    }

    /// Save the current playlist fingerprint
    public func save(trackIDs: Set<String>) {
        do {
            let data = try JSONEncoder().encode(Array(trackIDs))
            try data.write(to: cacheURL)
        } catch {
            // Silently fail - cache is best-effort
        }
    }

    /// Load the cached fingerprint
    public func load() -> Set<String>? {
        guard let data = try? Data(contentsOf: cacheURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return Set(ids)
    }

    /// Check if the playlist has changed
    public func hasChanged(currentTrackIDs: Set<String>) -> Bool {
        guard let cached = load() else {
            // No cache = assume changed
            return true
        }
        return cached != currentTrackIDs
    }
}
