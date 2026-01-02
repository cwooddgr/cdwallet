import Foundation
import MusicKit

public enum PlaylistServiceError: Error, LocalizedError {
    case noPlaylistFound
    case fetchFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .noPlaylistFound:
            return "No playlist named 'CDs' found in your library."
        case .fetchFailed(let error):
            return "Failed to fetch playlist: \(error.localizedDescription)"
        }
    }
}

/// Manages "CDs" playlist discovery and item extraction
public actor PlaylistService {
    public init() {}

    /// Locate the "CDs" playlist using deterministic selection rules
    public func locateCDsPlaylist() async throws -> PlaylistSelection {
        // Fetch all library playlists
        var request = MusicLibraryRequest<Playlist>()
        let response = try await request.response()

        // Filter to playlists named "CDs" (case-insensitive)
        let candidates = response.items.filter { playlist in
            playlist.name.lowercased() == "cds"
        }

        guard !candidates.isEmpty else {
            throw PlaylistServiceError.noPlaylistFound
        }

        if candidates.count == 1 {
            return PlaylistSelection(
                playlist: candidates[0],
                totalCandidates: 1,
                selectionReason: .onlyOne
            )
        }

        // Multiple candidates: apply selection heuristic
        return selectPlaylist(from: candidates)
    }

    /// Fetch all items from a playlist
    public func fetchPlaylistItems(playlistID: MusicItemID) async throws -> [Track] {
        // iOS 18: Use MusicLibraryRequest with explicit relationship loading
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: playlistID)

        let response = try await request.response()
        guard let playlist = response.items.first else {
            throw PlaylistServiceError.noPlaylistFound
        }

        print("📀 DEBUG: Found playlist '\(playlist.name)'")

        // iOS 18: Try to load tracks with explicit relationship
        do {
            let detailedPlaylist = try await playlist.with([.tracks, .entries])

            print("📀 DEBUG: After with() - tracks: \(detailedPlaylist.tracks != nil), entries: \(detailedPlaylist.entries != nil)")

            // Try tracks first
            if let playlistTracks = detailedPlaylist.tracks {
                print("📀 DEBUG: playlist.tracks exists with \(playlistTracks.count) items")

                // Debug: Check first track's properties
                if let firstTrack = playlistTracks.first {
                    print("📀 DEBUG: First track - title: '\(firstTrack.title)', id: \(firstTrack.id.rawValue)")
                    print("📀 DEBUG: First track - albumTitle: \(firstTrack.albumTitle ?? "nil"), artistName: \(firstTrack.artistName)")
                }

                // iOS 18: Playlist tracks have albumTitle and artistName, but not album relationships
                // We can use them directly without re-fetching
                print("📀 DEBUG: Using playlist tracks directly (they have albumTitle/artistName)")
                return Array(playlistTracks)
            }

            // Try entries as fallback
            if let entries = detailedPlaylist.entries {
                print("📀 DEBUG: entries exists with \(entries.count) items")

                // Extract track IDs from entries
                let trackIDs = entries.compactMap { entry -> MusicItemID? in
                    // Entry.item is an enum that can contain different types
                    if case .song(let song) = entry.item {
                        return song.id
                    }
                    return nil
                }

                print("📀 DEBUG: Extracted \(trackIDs.count) track IDs from entries")

                // Re-fetch tracks from library
                var tracksRequest = MusicLibraryRequest<Track>()
                tracksRequest.filter(matching: \.id, memberOf: trackIDs)

                let tracksResponse = try await tracksRequest.response()
                let fullTracks = Array(tracksResponse.items)

                print("📀 DEBUG: Re-fetched \(fullTracks.count) tracks with full details")

                // Preserve playlist order
                let trackDict = Dictionary(uniqueKeysWithValues: fullTracks.map { ($0.id, $0) })
                let orderedTracks = trackIDs.compactMap { trackDict[$0] }

                return orderedTracks
            }
        } catch {
            print("📀 DEBUG: Error loading relationships: \(error)")
            // Fall through to try direct access
        }

        // Final fallback: try direct property access
        if let playlistTracks = playlist.tracks {
            print("📀 DEBUG: Direct playlist.tracks exists with \(playlistTracks.count) items")
            return Array(playlistTracks)
        }

        if let entries = playlist.entries {
            print("📀 DEBUG: Direct entries exists with \(entries.count) items")
            // Can't cast Entry.Item to Track directly, need different approach
            return []
        }

        print("📀 DEBUG: No tracks found via any method")
        return []
    }

    /// Extract album title/artist pairs from tracks for searching
    public func extractAlbumInfo(from tracks: [Track]) -> [(title: String, artist: String)] {
        print("📀 DEBUG: Extracting album info from \(tracks.count) tracks")

        let albumInfo = tracks.compactMap { track -> (String, String)? in
            guard let albumTitle = track.albumTitle else {
                print("📀 DEBUG: Track '\(track.title)' has no album title")
                return nil
            }

            let artistName = track.artistName
            print("📀 DEBUG: Track '\(track.title)' -> Album: '\(albumTitle)', Artist: '\(artistName)'")
            return (albumTitle, artistName)
        }

        print("📀 DEBUG: Extracted \(albumInfo.count) album info pairs")

        // Dedupe while preserving order - use normalized titles to merge editions
        var seen = Set<String>()
        let uniqueInfo = albumInfo.filter { info in
            // Normalize title for dedup (strips "(Deluxe Edition)", "(Remastered)", etc.)
            let normalizedTitle = normalizeAlbumTitleForDedup(info.0)
            let key = "\(normalizedTitle)|\(info.1.lowercased())"
            return seen.insert(key).inserted
        }

        print("📀 DEBUG: After deduplication: \(uniqueInfo.count) unique albums")

        return uniqueInfo
    }

    // MARK: - Album Title Normalization

    /// Normalize album title for deduplication - strips edition suffixes like "(Deluxe Edition)"
    private func normalizeAlbumTitleForDedup(_ title: String) -> String {
        var normalized = title.lowercased()

        // Remove any trailing parenthetical content (remaster info, deluxe edition, etc.)
        while let range = normalized.range(of: " \\([^)]+\\)$", options: .regularExpression) {
            normalized = String(normalized[..<range.lowerBound])
        }

        // Remove any trailing bracketed content
        while let range = normalized.range(of: " \\[[^\\]]+\\]$", options: .regularExpression) {
            normalized = String(normalized[..<range.lowerBound])
        }

        // Remove common dash suffixes
        let dashSuffixes = [" - ep", " - single", " - deluxe", " - remastered", " - expanded"]
        for suffix in dashSuffixes {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count))
            }
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Fetch a lightweight fingerprint of the playlist (just track IDs)
    /// This is a minimal API call to detect if the playlist has changed
    public func fetchPlaylistFingerprint(playlistID: MusicItemID) async throws -> Set<String> {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: playlistID)

        let response = try await request.response()
        guard let playlist = response.items.first else {
            throw PlaylistServiceError.noPlaylistFound
        }

        // Load just entries (lighter than full tracks)
        let detailedPlaylist = try await playlist.with([.entries])

        var trackIDs = Set<String>()

        if let entries = detailedPlaylist.entries {
            for entry in entries {
                if case .song(let song) = entry.item {
                    trackIDs.insert(song.id.rawValue)
                }
            }
        }

        return trackIDs
    }

    /// Extract unique album IDs from tracks (legacy method for library tracks)
    public func extractAlbumIDs(from tracks: [Track]) -> [String] {
        print("📀 DEBUG: Extracting album IDs from \(tracks.count) tracks")

        let albumIDs = tracks.compactMap { track -> String? in
            track.albums?.first?.id.rawValue
        }

        print("📀 DEBUG: Extracted \(albumIDs.count) album IDs (before deduplication)")

        // Dedupe while preserving order
        var seen = Set<String>()
        let uniqueIDs = albumIDs.filter { seen.insert($0).inserted }
        print("📀 DEBUG: After deduplication: \(uniqueIDs.count) unique album IDs")

        return uniqueIDs
    }

    // MARK: - Private

    private func selectPlaylist(from candidates: [Playlist]) -> PlaylistSelection {
        // Rule 1: Prefer most recently modified (if available)
        // Note: MusicKit Playlist may not expose lastModifiedDate directly
        // For MVP, we'll fall back to item count heuristic

        // Rule 2: Prefer largest item count
        // iOS 18: Use entries?.count instead of tracks?.count
        let sorted = candidates.sorted { ($0.entries?.count ?? 0) > ($1.entries?.count ?? 0) }

        if let largest = sorted.first, (largest.entries?.count ?? 0) > 0 {
            return PlaylistSelection(
                playlist: largest,
                totalCandidates: candidates.count,
                selectionReason: .largestItemCount
            )
        }

        // Rule 3: First stable ordering (by ID)
        let stableSorted = candidates.sorted { $0.id.rawValue < $1.id.rawValue }
        return PlaylistSelection(
            playlist: stableSorted[0],
            totalCandidates: candidates.count,
            selectionReason: .firstStable
        )
    }
}
