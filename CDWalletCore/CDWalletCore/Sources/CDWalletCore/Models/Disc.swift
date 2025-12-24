import Foundation
import MusicKit

/// Represents one "CD" in the wallet, backed by a resolved Apple Music album
public struct Disc: Identifiable, Hashable {
    public let id: String // albumID
    public let albumID: MusicItemID
    public let artistName: String
    public let albumTitle: String
    public let artwork: Artwork?
    public let releaseDate: Date?

    // Sort keys (computed at creation)
    public let artistSortKey: String
    public let albumSortKey: String

    // Diagnostics
    public let trackCount: Int
    public let isAvailable: Bool

    public init(album: Album) {
        self.id = album.id.rawValue
        self.albumID = album.id
        self.artistName = album.artistName
        self.albumTitle = album.title
        self.artwork = album.artwork
        self.releaseDate = album.releaseDate
        self.trackCount = album.tracks?.count ?? 0
        self.isAvailable = true // MusicKit returns only available albums

        // Compute sort keys
        self.artistSortKey = Self.computeArtistSortKey(from: album.artistName)
        self.albumSortKey = Self.computeAlbumSortKey(from: album.title)
    }

    /// Initialize from cached data (artwork loaded separately via ArtworkCache)
    internal init(cached: CachedDisc) {
        self.id = cached.id
        self.albumID = MusicItemID(cached.id)
        self.artistName = cached.artistName
        self.albumTitle = cached.albumTitle
        self.artwork = nil // Loaded via ArtworkCache
        self.releaseDate = cached.releaseDate
        self.trackCount = cached.trackCount
        self.isAvailable = true
        self.artistSortKey = cached.artistSortKey
        self.albumSortKey = cached.albumSortKey
    }

    /// For playback, we need title and artist to search for the full catalog album
    public var searchInfo: (title: String, artist: String) {
        (albumTitle, artistName)
    }

    /// Strip leading articles ("the", "a", "an") for artist sorting only
    private static func computeArtistSortKey(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()

        // Check for leading articles (case-insensitive)
        if trimmed.hasPrefix("the ") {
            return String(trimmed.dropFirst(4))
        } else if trimmed.hasPrefix("a ") {
            return String(trimmed.dropFirst(2))
        } else if trimmed.hasPrefix("an ") {
            return String(trimmed.dropFirst(3))
        }

        return trimmed
    }

    private static func computeAlbumSortKey(from title: String) -> String {
        return title.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

extension Disc: Comparable {
    public static func < (lhs: Disc, rhs: Disc) -> Bool {
        if lhs.artistSortKey != rhs.artistSortKey {
            return lhs.artistSortKey < rhs.artistSortKey
        }
        if lhs.albumSortKey != rhs.albumSortKey {
            return lhs.albumSortKey < rhs.albumSortKey
        }
        return lhs.id < rhs.id // tie-break by albumID
    }
}
