import Foundation
import MusicKit
import Combine

/// Main view model coordinating wallet state
@MainActor
public class WalletViewModel: ObservableObject {
    @Published public private(set) var state: WalletState = .needsAuthorization
    @Published public private(set) var diagnostics: DiagnosticsSnapshot?

    private let authService = AuthorizationService()
    private let playlistService = PlaylistService()
    private let albumService = AlbumService()
    private let discCache = DiscCache.shared
    private let artworkCache = ArtworkCache.shared
    private let unavailableCache = UnavailableAlbumsCache.shared

    private var lastRefreshTime: Date?

    public init() {}

    /// Initial load: check authorization and load wallet
    public func initialize() async {
        let isAuthorized = await authService.ensureAuthorized()

        if isAuthorized {
            // Load from cache first for instant display
            if let cachedDiscs = discCache.load(), !cachedDiscs.isEmpty {
                state = .ready(discs: cachedDiscs)
            }
            // Then refresh from Apple Music
            await refresh()
        } else {
            state = .needsAuthorization
            updateDiagnostics()
        }
    }

    /// Request authorization
    public func requestAuthorization() async {
        let isAuthorized = await authService.ensureAuthorized()

        if isAuthorized {
            await refresh()
        } else {
            state = .needsAuthorization
            updateDiagnostics()
        }
    }

    /// Refresh wallet from "CDs" playlist
    public func refresh() async {
        // Only show loading if we don't have cached data
        if case .ready = state {
            // Already showing cached data, refresh silently
        } else {
            state = .loading
        }

        do {
            // 1. Locate "CDs" playlist
            let selection = try await playlistService.locateCDsPlaylist()

            // 2. Fetch playlist items
            let tracks = try await playlistService.fetchPlaylistItems(playlistID: selection.playlist.id)

            guard !tracks.isEmpty else {
                state = .empty(reason: .playlistEmpty)
                updateDiagnostics(
                    playlistSelection: selection,
                    stats: .init(
                        playlistItemsScanned: 0,
                        albumIDsExtracted: 0,
                        uniqueAlbumIDs: 0,
                        resolvedAlbums: 0,
                        unavailableAlbums: 0
                    )
                )
                return
            }

            // 3. Extract album info (title/artist pairs)
            let albumInfo = await playlistService.extractAlbumInfo(from: tracks)

            guard !albumInfo.isEmpty else {
                state = .empty(reason: .noAlbumsResolved)
                updateDiagnostics(
                    playlistSelection: selection,
                    stats: .init(
                        playlistItemsScanned: tracks.count,
                        albumIDsExtracted: 0,
                        uniqueAlbumIDs: 0,
                        resolvedAlbums: 0,
                        unavailableAlbums: 0
                    )
                )
                return
            }

            // 4. Search for albums in library by title/artist
            let resolutions = await albumService.searchAlbums(albumInfo: albumInfo)

            // 5. Build discs from resolved albums
            let discs = resolutions.compactMap { resolution -> Disc? in
                if case .resolved(let album) = resolution {
                    return Disc(album: album)
                }
                return nil
            }

            // 6. Filter out albums known to be unavailable, then sort
            let availableDiscs = discs.filter { disc in
                !unavailableCache.isUnavailable(title: disc.albumTitle, artist: disc.artistName)
            }
            let sortedDiscs = availableDiscs.sorted()

            // 7. Update state and cache
            if sortedDiscs.isEmpty {
                state = .empty(reason: .noAlbumsResolved)
                discCache.clear()
            } else {
                state = .ready(discs: sortedDiscs)
                discCache.save(discs: sortedDiscs)

                // Clean up artwork cache for albums no longer in wallet
                let currentAlbumIDs = Set(sortedDiscs.map { $0.id })
                await artworkCache.cleanup(keepingAlbumIDs: currentAlbumIDs)
            }

            lastRefreshTime = Date()

            // Update diagnostics
            let unavailableCount = resolutions.filter {
                if case .unavailable = $0 { return true }
                return false
            }.count

            updateDiagnostics(
                playlistSelection: selection,
                stats: .init(
                    playlistItemsScanned: tracks.count,
                    albumIDsExtracted: albumInfo.count,
                    uniqueAlbumIDs: albumInfo.count,
                    resolvedAlbums: discs.count,
                    unavailableAlbums: unavailableCount
                )
            )

        } catch PlaylistServiceError.noPlaylistFound {
            state = .empty(reason: .noPlaylist)
            updateDiagnostics()
        } catch {
            state = .error(message: error.localizedDescription)
            updateDiagnostics(lastError: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func updateDiagnostics(
        playlistSelection: PlaylistSelection? = nil,
        stats: DiagnosticsSnapshot.ResolutionStats? = nil,
        lastError: String? = nil
    ) {
        Task {
            let authStatus = await authService.status

            let playlistInfo: DiagnosticsSnapshot.PlaylistSelectionInfo? = playlistSelection.map {
                DiagnosticsSnapshot.PlaylistSelectionInfo(
                    totalCandidates: $0.totalCandidates,
                    selectedPlaylistID: $0.playlist.id.rawValue,
                    selectedPlaylistName: $0.playlist.name,
                    selectionReason: $0.selectionReason,
                    itemCount: $0.playlist.entries?.count ?? 0
                )
            }

            let defaultStats = DiagnosticsSnapshot.ResolutionStats(
                playlistItemsScanned: 0,
                albumIDsExtracted: 0,
                uniqueAlbumIDs: 0,
                resolvedAlbums: 0,
                unavailableAlbums: 0
            )

            diagnostics = DiagnosticsSnapshot(
                authorizationStatus: authStatus,
                playlistSelectionInfo: playlistInfo,
                resolutionStats: stats ?? defaultStats,
                lastRefreshTime: lastRefreshTime,
                lastError: lastError
            )
        }
    }
}
