import Foundation
import MusicKit

/// Result of attempting to resolve an album ID
public enum AlbumResolution: Sendable {
    case resolved(Album)
    case unavailable(albumID: String)
}
