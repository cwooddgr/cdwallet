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
    /// Returns unavailable if catalog search fails - we never play partial albums
    public func resolveCatalogAlbum(title: String, artist: String) async -> AlbumResolution {
        // Check cache first (keyed by title|artist)
        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache[cacheKey] {
            return .resolved(cached)
        }

        do {
            var searchRequest = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Album.self])
            searchRequest.limit = 10
            let searchResponse = try await searchRequest.response()

            let artistLower = artist.lowercased()

            for album in searchResponse.albums {
                let albumArtistLower = album.artistName.lowercased()

                if titlesMatch(album.title, title) && albumArtistLower == artistLower {
                    let fullAlbum = try await album.with([.tracks])
                    cache[cacheKey] = fullAlbum
                    return .resolved(fullAlbum)
                }
            }
        } catch {
            // Catalog search failed
        }

        return .unavailable(albumID: cacheKey)
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

        // Remove any trailing parenthetical content (remaster info, deluxe edition, etc.)
        while let range = normalized.range(of: " \\([^)]+\\)$", options: .regularExpression) {
            normalized = String(normalized[..<range.lowerBound])
        }

        // Remove any trailing bracketed content
        while let range = normalized.range(of: " \\[[^\\]]+\\]$", options: .regularExpression) {
            normalized = String(normalized[..<range.lowerBound])
        }

        // Remove common dash suffixes
        let dashSuffixes = [" - ep", " - single"]
        for suffix in dashSuffixes {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count))
            }
        }

        // Remove punctuation that varies between library and catalog
        let punctuationToRemove = CharacterSet(charactersIn: ",.!?;:'\"…")
        normalized = normalized.components(separatedBy: punctuationToRemove).joined()

        // Collapse multiple spaces
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Check if two album titles match, allowing for subtitle variations
    private func titlesMatch(_ title1: String, _ title2: String) -> Bool {
        let norm1 = normalizeAlbumTitle(title1)
        let norm2 = normalizeAlbumTitle(title2)

        // Exact match
        if norm1 == norm2 { return true }

        // One is a prefix of the other (handles subtitles like ": The First 10 Years")
        if norm1.hasPrefix(norm2) || norm2.hasPrefix(norm1) { return true }

        // Strip everything after colon and check again
        let base1 = norm1.components(separatedBy: ":").first ?? norm1
        let base2 = norm2.components(separatedBy: ":").first ?? norm2
        if base1.trimmingCharacters(in: .whitespaces) == base2.trimmingCharacters(in: .whitespaces) {
            return true
        }

        return false
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
