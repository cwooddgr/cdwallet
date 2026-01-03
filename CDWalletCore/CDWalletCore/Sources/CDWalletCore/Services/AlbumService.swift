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

        // Enrich albums missing releaseDate with catalog data
        return await enrichWithReleaseDates(resolutions: results)
    }

    /// Fetch release dates from catalog for albums missing them
    private func enrichWithReleaseDates(resolutions: [AlbumResolution]) async -> [AlbumResolution] {
        // Find albums missing release dates
        let needsEnrichment = resolutions.enumerated().filter { (_, resolution) in
            if case .resolved(let album) = resolution {
                return album.releaseDate == nil
            }
            return false
        }

        guard !needsEnrichment.isEmpty else { return resolutions }

        print("📀 Enriching \(needsEnrichment.count) albums with missing release dates")

        // Fetch release dates with controlled concurrency (10 at a time to avoid rate limiting)
        var enrichedDates: [Int: Date] = [:]
        for chunk in needsEnrichment.chunked(into: 10) {
            let chunkResults = await withTaskGroup(of: (Int, Date?).self) { group in
                for (index, resolution) in chunk {
                    guard case .resolved(let album) = resolution else { continue }
                    group.addTask {
                        let date = await self.fetchReleaseDateFromCatalog(title: album.title, artist: album.artistName)
                        return (index, date)
                    }
                }

                var results: [Int: Date] = [:]
                for await (index, date) in group {
                    if let date = date {
                        results[index] = date
                    }
                }
                return results
            }
            enrichedDates.merge(chunkResults) { _, new in new }
        }

        // Build enriched results
        var enrichedResults = resolutions
        for (index, date) in enrichedDates {
            if case .resolved(let album) = resolutions[index] {
                enrichedResults[index] = .resolvedWithDate(album, releaseDate: date)
            }
        }

        return enrichedResults
    }

    /// Search catalog to get release date for an album
    private func fetchReleaseDateFromCatalog(title: String, artist: String) async -> Date? {
        // Try search strategies in order - first success wins
        let searchTerms = [
            "\(artist) \(title)",
            "\(title) \(artist)",
            title  // Just the title as fallback
        ]

        for searchTerm in searchTerms {
            if let date = await searchCatalogForReleaseDate(term: searchTerm, title: title, artist: artist) {
                return date
            }
        }

        print("📀 Could not find release date for '\(title)' by '\(artist)'")
        return nil
    }

    private func searchCatalogForReleaseDate(term: String, title: String, artist: String) async -> Date? {
        do {
            var searchRequest = MusicCatalogSearchRequest(term: term, types: [Album.self])
            searchRequest.limit = 15
            let response = try await searchRequest.response()

            let normalizedTitle = normalizeAlbumTitle(title)

            for album in response.albums {
                let titleMatch = normalizeAlbumTitle(album.title) == normalizedTitle || titlesMatch(album.title, title)
                let artistMatch = artistsMatch(album.artistName, artist)

                if titleMatch && artistMatch {
                    // Try releaseDate first, then parse copyright year as fallback
                    if let date = album.releaseDate {
                        print("📀 Found release date for '\(title)': \(date)")
                        return date
                    } else if let copyrightDate = parseCopyrightYear(album.copyright) {
                        print("📀 Found copyright date for '\(title)': \(copyrightDate) (from '\(album.copyright ?? "")')")
                        return copyrightDate
                    }
                }
            }

            // Second pass: more lenient matching (check if base titles match)
            for album in response.albums {
                let baseTitle = normalizeAlbumTitle(title)
                let catalogBase = normalizeAlbumTitle(album.title)
                // Check if either contains the other (handles "Whammy" vs "Whammy!")
                let titleMatch = baseTitle.contains(catalogBase) || catalogBase.contains(baseTitle)
                let artistMatch = artistsMatch(album.artistName, artist)

                if titleMatch && artistMatch {
                    if let date = album.releaseDate {
                        print("📀 Found release date for '\(title)' (lenient match to '\(album.title)'): \(date)")
                        return date
                    } else if let copyrightDate = parseCopyrightYear(album.copyright) {
                        print("📀 Found copyright date for '\(title)' (lenient match): \(copyrightDate)")
                        return copyrightDate
                    }
                }
            }
        } catch {
            // Continue to next search term
        }
        return nil
    }

    /// Parse a year from copyright string like "℗ 1983 Warner Records" -> Date for Jan 1, 1983
    private func parseCopyrightYear(_ copyright: String?) -> Date? {
        guard let copyright = copyright else { return nil }

        // Look for a 4-digit year (19xx or 20xx)
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: copyright, range: NSRange(copyright.startIndex..., in: copyright)),
              let yearRange = Range(match.range(at: 1), in: copyright),
              let year = Int(copyright[yearRange]) else {
            return nil
        }

        // Create a date for January 1 of that year
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components)
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
        print("🔍 Searching: '\(title)' by '\(artist)'")

        // Check cache first (keyed by title|artist)
        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache[cacheKey] {
            print("🔍 Found in cache")
            return .resolved(cached)
        }

        // Extract primary artist (before &, and, feat., etc.) for fallback search
        let primaryArtist = extractPrimaryArtist(artist)

        // Try multiple search strategies
        let searchTerms: [String]
        if primaryArtist != artist.lowercased() {
            searchTerms = [
                "\(artist) \(title)",           // Full artist + title
                "\(primaryArtist) \(title)",    // Primary artist + title
                title                            // Just title as last resort
            ]
        } else {
            searchTerms = [
                "\(artist) \(title)",
                title
            ]
        }

        for searchTerm in searchTerms {
            print("🔍 Trying search: '\(searchTerm)'")
            if let result = await searchCatalogWithTerm(searchTerm, title: title, artist: artist, cacheKey: cacheKey) {
                return result
            }
        }

        print("🔍 ✗ No match after all search strategies")
        return .unavailable(albumID: cacheKey)
    }

    /// Extract primary artist name before collaboration markers
    private func extractPrimaryArtist(_ artist: String) -> String {
        var primary = artist.lowercased()
        let separators = [" & ", " and ", " feat. ", " feat ", " featuring ", " with ", ", "]
        for sep in separators {
            if let range = primary.range(of: sep) {
                primary = String(primary[..<range.lowerBound])
            }
        }
        return primary.trimmingCharacters(in: .whitespaces)
    }

    /// Search catalog with a specific term and match against title/artist
    private func searchCatalogWithTerm(_ term: String, title: String, artist: String, cacheKey: String) async -> AlbumResolution? {
        do {
            var searchRequest = MusicCatalogSearchRequest(term: term, types: [Album.self])
            searchRequest.limit = 15
            let searchResponse = try await searchRequest.response()
            print("🔍 Catalog returned \(searchResponse.albums.count) results")

            for album in searchResponse.albums {
                let titleMatch = titlesMatch(album.title, title)
                let artistMatch = artistsMatch(album.artistName, artist)
                print("🔍   '\(album.title)' by '\(album.artistName)' → title:\(titleMatch) artist:\(artistMatch)")

                if titleMatch && artistMatch {
                    let fullAlbum = try await album.with([.tracks])
                    cache[cacheKey] = fullAlbum
                    print("🔍 ✓ Match found")
                    return .resolved(fullAlbum)
                }
            }
            return nil
        } catch {
            print("🔍 ✗ Search error: \(error)")
            return nil
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
        let normalizedTitle = normalizeAlbumTitle(title)

        // Search by title first, then verify artist matches
        let matchingAlbums = albums.filter { album in
            let normalizedLibraryTitle = normalizeAlbumTitle(album.title)
            guard normalizedLibraryTitle == normalizedTitle || titlesMatch(album.title, title) else {
                return false
            }
            // Flexible artist matching
            return artistsMatch(album.artistName, artist)
        }

        if let album = matchingAlbums.first {
            cache[album.id.rawValue] = album
            return .resolved(album)
        } else {
            // Library search failed - try catalog as fallback
            // This handles albums that exist in Apple Music but not in user's library
            let catalogResult = await resolveCatalogAlbum(title: title, artist: artist)
            switch catalogResult {
            case .resolved(let album):
                return .resolved(album)
            case .resolvedWithDate(let album, let date):
                return .resolvedWithDate(album, releaseDate: date)
            case .unavailable, .error:
                return .unavailable(albumID: "\(artist)-\(title)")
            }
        }
    }

    /// Flexible artist matching - handles "Artist & Featured" vs "Artist"
    private func artistsMatch(_ artist1: String, _ artist2: String) -> Bool {
        let a1 = artist1.lowercased()
        let a2 = artist2.lowercased()

        // Exact match
        if a1 == a2 { return true }

        // One contains the other
        if a1.contains(a2) || a2.contains(a1) { return true }

        // Extract primary artist (before &, and, feat., featuring, with)
        let separators = [" & ", " and ", " feat. ", " feat ", " featuring ", " with "]
        var primary1 = a1
        var primary2 = a2
        for sep in separators {
            if let range = primary1.range(of: sep) {
                primary1 = String(primary1[..<range.lowerBound])
            }
            if let range = primary2.range(of: sep) {
                primary2 = String(primary2[..<range.lowerBound])
            }
        }

        return primary1 == primary2
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
        // Extract base titles BEFORE normalization (to preserve : and - separators)
        let base1 = extractBaseTitle(title1.lowercased())
        let base2 = extractBaseTitle(title2.lowercased())

        // Compare base titles (with punctuation stripped)
        let normBase1 = stripPunctuation(base1)
        let normBase2 = stripPunctuation(base2)
        if normBase1 == normBase2 { return true }

        // Also try full normalized titles
        let norm1 = normalizeAlbumTitle(title1)
        let norm2 = normalizeAlbumTitle(title2)

        // Exact match
        if norm1 == norm2 { return true }

        // One is a prefix of the other
        if norm1.hasPrefix(norm2) || norm2.hasPrefix(norm1) { return true }

        return false
    }

    /// Extract base title before any subtitle separator (: or -)
    private func extractBaseTitle(_ title: String) -> String {
        var base = title

        // Split on colon first
        if let colonRange = base.range(of: ":") {
            base = String(base[..<colonRange.lowerBound])
        }

        // Split on " - " (space-dash-space to avoid splitting hyphenated words)
        if let dashRange = base.range(of: " - ") {
            base = String(base[..<dashRange.lowerBound])
        }

        return base.trimmingCharacters(in: .whitespaces)
    }

    /// Strip just punctuation (used for base title comparison)
    private func stripPunctuation(_ text: String) -> String {
        let punctuation = CharacterSet(charactersIn: ",.!?;:'\"…")
        return text.components(separatedBy: punctuation).joined()
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

// MARK: - Array Extension

private extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
