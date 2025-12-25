import Foundation
import MusicKit

/// Result of attempting to resolve an album ID
public enum AlbumResolution: Sendable {
    case resolved(Album)
    case unavailable(albumID: String)  // Album definitively not in catalog
    case error(albumID: String)        // Temporary failure, don't cache as unavailable
}
