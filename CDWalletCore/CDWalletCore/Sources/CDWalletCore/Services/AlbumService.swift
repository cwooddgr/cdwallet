import Foundation
import MusicKit

/// Resolves album IDs to Album objects with concurrency control
public actor AlbumService {
    private let maxConcurrentRequests = 6
    private var cache: [String: Album] = [:]

    /// Cached library albums to avoid repeated fetches
    private var libraryAlbums: [Album]?

    public init() {}

    /// Fetches and caches all library albums (called once)
    private func getLibraryAlbums() async throws -> [Album] {
        if let cached = libraryAlbums {
            return cached
        }

        var request = MusicLibraryRequest<Album>()
        let response = try await request.response()
        let albums = Array(response.items)
        libraryAlbums = albums
        return albums
    }

    /// Search for albums in the library by title and artist
    public func searchAlbums(albumInfo: [(title: String, artist: String)]) async -> [AlbumResolution] {
        // Fetch library once (cached for subsequent calls)
        let libraryAlbums: [Album]
        do {
            libraryAlbums = try await getLibraryAlbums()
        } catch {
            return []
        }

        // Search in memory - no need for TaskGroup since it's fast now
        var results: [AlbumResolution] = []
        for info in albumInfo {
            if let resolution = await searchAlbum(title: info.0, artist: info.1, inLibrary: libraryAlbums) {
                results.append(resolution)
            }
        }

        return results
    }

    /// Search for FULL CATALOG album by title/artist for playback
    /// CRITICAL: Returns complete album with all tracks, not just library tracks
    public func searchCatalogAlbumForPlayback(title: String, artist: String) async -> AlbumResolution {

        do {
            // Use MusicCatalogSearchRequest to find the full album
            var searchRequest = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Album.self])
            let searchResponse = try await searchRequest.response()

            // Find best match
            let normalizedTitle = normalizeAlbumTitle(title)
            let artistLower = artist.lowercased()

            let matchingAlbums = searchResponse.albums.filter { album in
                let albumTitleMatches = normalizeAlbumTitle(album.title) == normalizedTitle
                let artistMatches = album.artistName.lowercased() == artistLower
                return albumTitleMatches && artistMatches
            }

            if let album = matchingAlbums.first {
                cache[album.id.rawValue] = album
                return .resolved(album)
            } else {
                return .unavailable(albumID: "\(artist)-\(title)")
            }

        } catch {
            return .unavailable(albumID: "\(artist)-\(title)")
        }
    }

    /// Resolve FULL CATALOG album by title and artist
    /// This searches the Apple Music catalog and returns the complete album with all tracks
    public func resolveCatalogAlbum(title: String, artist: String) async -> AlbumResolution {

        // Check cache first (keyed by title|artist)
        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache[cacheKey] {
            return .resolved(cached)
        }

        do {
            // Search the catalog
            var searchRequest = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Album.self])
            searchRequest.limit = 10
            let searchResponse = try await searchRequest.response()

            // Find best match using normalized titles
            let normalizedTitle = normalizeAlbumTitle(title)
            let artistLower = artist.lowercased()

            for album in searchResponse.albums {
                let albumNormalized = normalizeAlbumTitle(album.title)
                let albumArtistLower = album.artistName.lowercased()

                if albumNormalized == normalizedTitle && albumArtistLower == artistLower {
                    // Found exact match - load with tracks
                    let fullAlbum = try await album.with([.tracks])
                    cache[cacheKey] = fullAlbum
                    return .resolved(fullAlbum)
                }
            }

            return .unavailable(albumID: cacheKey)

        } catch {
            return .unavailable(albumID: cacheKey)
        }
    }

    /// Resolve multiple album IDs concurrently with limit (CATALOG - requires MusicKit token)
    public func resolveAlbums(ids: [String]) async -> [AlbumResolution] {
        await withTaskGroup(of: (String, AlbumResolution).self) { group -> [AlbumResolution] in
            var semaphore = 0
            var results: [String: AlbumResolution] = [:]
            var pendingIDs = ids

            // Initial batch
            while semaphore < maxConcurrentRequests && !pendingIDs.isEmpty {
                let id = pendingIDs.removeFirst()
                semaphore += 1
                group.addTask {
                    let resolution = await self.resolveAlbum(id: id)
                    return (id, resolution)
                }
            }

            // Process results and spawn more tasks
            for await (id, resolution) in group {
                results[id] = resolution
                semaphore -= 1

                if !pendingIDs.isEmpty {
                    let nextID = pendingIDs.removeFirst()
                    semaphore += 1
                    group.addTask {
                        let resolution = await self.resolveAlbum(id: nextID)
                        return (nextID, resolution)
                    }
                }
            }

            // Return results in original order
            return ids.compactMap { results[$0] }
        }
    }

    // MARK: - Private

    private func searchAlbum(title: String, artist: String, inLibrary albums: [Album]) async -> AlbumResolution? {
        // Filter albums by artist first
        let artistLower = artist.lowercased()
        let albumsByArtist = albums.filter { album in
            album.artistName.lowercased() == artistLower
        }

        // Try to match album title with fuzzy matching
        let normalizedTitle = normalizeAlbumTitle(title)

        let matchingAlbums = albumsByArtist.filter { album in
            let normalizedLibraryTitle = normalizeAlbumTitle(album.title)
            return normalizedLibraryTitle == normalizedTitle
        }

        if let album = matchingAlbums.first {
            cache[album.id.rawValue] = album
            return .resolved(album)
        } else {
            return .unavailable(albumID: "\(artist)-\(title)")
        }
    }

    /// Normalize album title for fuzzy matching
    private func normalizeAlbumTitle(_ title: String) -> String {
        var normalized = title.lowercased()

        // Handle common spelling variations
        normalized = normalized.replacingOccurrences(of: "rumours", with: "rumors")

        // Remove common suffixes that might differ between versions
        let suffixesToRemove = [
            " (deluxe edition)",
            " (deluxe version)",
            " (remastered)",
            " (bonus track version)",
            " (expanded edition)",
            " - ep",
            " - single"
        ]

        for suffix in suffixesToRemove {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count))
            }
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    private func resolveAlbum(id: String) async -> AlbumResolution {
        // Check cache
        if let cached = cache[id] {
            return .resolved(cached)
        }

        // Fetch from MusicKit
        do {
            // In iOS 18, MusicItemID initializer is failable
            let musicItemID = MusicItemID(id)

            var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: musicItemID)

            let response = try await request.response()

            guard let album = response.items.first else {
                return .unavailable(albumID: id)
            }

            // Cache and return
            cache[id] = album
            return .resolved(album)

        } catch {
            return .unavailable(albumID: id)
        }
    }
}
