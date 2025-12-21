import Foundation
import MusicKit

/// Diagnostic information for debugging and user support
public struct DiagnosticsSnapshot {
    public let authorizationStatus: MusicAuthorization.Status
    public let playlistSelectionInfo: PlaylistSelectionInfo?
    public let resolutionStats: ResolutionStats
    public let lastRefreshTime: Date?
    public let lastError: String?

    public struct PlaylistSelectionInfo {
        public let totalCandidates: Int
        public let selectedPlaylistID: String
        public let selectedPlaylistName: String
        public let selectionReason: PlaylistSelection.SelectionReason
        public let itemCount: Int
    }

    public struct ResolutionStats {
        public let playlistItemsScanned: Int
        public let albumIDsExtracted: Int
        public let uniqueAlbumIDs: Int
        public let resolvedAlbums: Int
        public let unavailableAlbums: Int
    }

    public init(
        authorizationStatus: MusicAuthorization.Status,
        playlistSelectionInfo: PlaylistSelectionInfo?,
        resolutionStats: ResolutionStats,
        lastRefreshTime: Date?,
        lastError: String?
    ) {
        self.authorizationStatus = authorizationStatus
        self.playlistSelectionInfo = playlistSelectionInfo
        self.resolutionStats = resolutionStats
        self.lastRefreshTime = lastRefreshTime
        self.lastError = lastError
    }
}
