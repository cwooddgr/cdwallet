import Foundation
import MusicKit

/// Result of locating the "CDs" playlist
public struct PlaylistSelection: Sendable {
    public let playlist: Playlist
    public let totalCandidates: Int
    public let selectionReason: SelectionReason

    public enum SelectionReason: Equatable, Sendable {
        case onlyOne
        case mostRecentlyModified
        case largestItemCount
        case firstStable
    }

    public init(playlist: Playlist, totalCandidates: Int, selectionReason: SelectionReason) {
        self.playlist = playlist
        self.totalCandidates = totalCandidates
        self.selectionReason = selectionReason
    }
}
