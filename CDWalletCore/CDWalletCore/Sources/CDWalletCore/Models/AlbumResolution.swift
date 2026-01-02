import Foundation
import MusicKit

/// Result of attempting to resolve an album ID
public enum AlbumResolution: Sendable {
    case resolved(Album)
    case resolvedWithDate(Album, releaseDate: Date)  // Album with enriched release date from catalog
    case unavailable(albumID: String)  // Album definitively not in catalog
    case error(albumID: String)        // Temporary failure, don't cache as unavailable
}
