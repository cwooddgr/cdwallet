import Foundation
import MusicKit

/// Resolves album IDs to Album objects with concurrency control
public actor AlbumService {
    private let maxConcurrentRequests = 6
    private var cache: [String: Album] = [:]

    public init() {}

    /// Search for albums in the library by title and artist
    public func searchAlbums(albumInfo: [(title: String, artist: String)]) async -> [AlbumResolution] {
        print("📀 DEBUG: AlbumService searching for \(albumInfo.count) albums")

        return await withTaskGroup(of: (Int, AlbumResolution?).self) { group -> [AlbumResolution] in
            for (index, info) in albumInfo.enumerated() {
                group.addTask {
                    let resolution = await self.searchAlbum(title: info.0, artist: info.1)
                    return (index, resolution)
                }
            }

            var results: [Int: AlbumResolution?] = [:]
            for await (index, resolution) in group {
                results[index] = resolution
            }

            // Return results in original order, filtering out nil
            return albumInfo.indices.compactMap { results[$0] ?? nil }
        }
    }

    /// Search for FULL CATALOG album by title/artist for playback
    /// CRITICAL: Returns complete album with all tracks, not just library tracks
    public func searchCatalogAlbumForPlayback(title: String, artist: String) async -> AlbumResolution {
        print("📀 DEBUG: Searching catalog for FULL album '\(title)' by '\(artist)'")

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
                print("📀 DEBUG: Found FULL catalog album '\(album.title)' with \(album.tracks?.count ?? 0) tracks")
                cache[album.id.rawValue] = album
                return .resolved(album)
            } else {
                print("📀 DEBUG: No catalog album match found")
                print("📀 DEBUG: Search returned \(searchResponse.albums.count) albums")
                return .unavailable(albumID: "\(artist)-\(title)")
            }

        } catch {
            print("📀 DEBUG: Error searching catalog: \(error)")
            return .unavailable(albumID: "\(artist)-\(title)")
        }
    }

    /// Resolve FULL CATALOG album by title and artist
    /// This searches the Apple Music catalog and returns the complete album with all tracks
    public func resolveCatalogAlbum(title: String, artist: String) async -> AlbumResolution {
        print("📀 DEBUG: Searching catalog for '\(title)' by '\(artist)'")

        // Check cache first (keyed by title|artist)
        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache[cacheKey] {
            print("📀 DEBUG: Found cached catalog album")
            return .resolved(cached)
        }

        do {
            // Search the catalog
            var searchRequest = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Album.self])
            searchRequest.limit = 10
            let searchResponse = try await searchRequest.response()

            print("📀 DEBUG: Catalog search returned \(searchResponse.albums.count) albums")

            // Find best match using normalized titles
            let normalizedTitle = normalizeAlbumTitle(title)
            let artistLower = artist.lowercased()

            for album in searchResponse.albums {
                let albumNormalized = normalizeAlbumTitle(album.title)
                let albumArtistLower = album.artistName.lowercased()

                if albumNormalized == normalizedTitle && albumArtistLower == artistLower {
                    // Found exact match - load with tracks
                    let fullAlbum = try await album.with([.tracks])
                    print("📀 DEBUG: Found catalog album '\(fullAlbum.title)' with \(fullAlbum.tracks?.count ?? 0) tracks")
                    cache[cacheKey] = fullAlbum
                    return .resolved(fullAlbum)
                }
            }

            // No exact match found
            print("📀 DEBUG: No exact match found in catalog")
            return .unavailable(albumID: cacheKey)

        } catch {
            print("📀 DEBUG: Error searching catalog: \(error)")
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

    private func searchAlbum(title: String, artist: String) async -> AlbumResolution? {
        print("📀 DEBUG: Searching for album '\(title)' by '\(artist)'")

        do {
            // Search in library for albums matching title
            var request = MusicLibraryRequest<Album>()
            let response = try await request.response()

            print("📀 DEBUG:   Total albums in library: \(response.items.count)")

            // Filter albums by artist first
            let artistLower = artist.lowercased()
            let albumsByArtist = response.items.filter { album in
                album.artistName.lowercased() == artistLower
            }
            print("📀 DEBUG:   Albums by '\(artist)': \(albumsByArtist.count)")

            if albumsByArtist.count > 0 {
                print("📀 DEBUG:   Album titles by this artist: \(albumsByArtist.map { $0.title }.prefix(5))")
            }

            // Try to match album title with fuzzy matching
            let normalizedTitle = normalizeAlbumTitle(title)

            let matchingAlbums = albumsByArtist.filter { album in
                let normalizedLibraryTitle = normalizeAlbumTitle(album.title)
                return normalizedLibraryTitle == normalizedTitle
            }

            if let album = matchingAlbums.first {
                print("📀 DEBUG: Found album '\(album.title)' by '\(album.artistName)' in library")
                cache[album.id.rawValue] = album
                return .resolved(album)
            } else {
                print("📀 DEBUG: No matching album found for '\(title)' by '\(artist)'")
                print("📀 DEBUG:   Normalized search title: '\(normalizedTitle)'")
                if let firstByArtist = albumsByArtist.first {
                    print("📀 DEBUG:   Example normalized library title: '\(normalizeAlbumTitle(firstByArtist.title))'")
                }
                return .unavailable(albumID: "\(artist)-\(title)")
            }

        } catch {
            print("📀 DEBUG: Error searching for album: \(error)")
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
