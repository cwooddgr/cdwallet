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
            state = .loading

            // Load from cache first for instant display (filtering out unavailable)
            if let cachedDiscs = discCache.load(), !cachedDiscs.isEmpty {
                let availableDiscs = cachedDiscs.filter { disc in
                    !unavailableCache.isUnavailable(title: disc.albumTitle, artist: disc.artistName)
                }
                if !availableDiscs.isEmpty {
                    // Preload artwork for first 2 discs before showing
                    let discsToPreload = Array(availableDiscs.prefix(2))
                    await artworkCache.preload(discs: discsToPreload, size: CGSize(width: 600, height: 600))
                    state = .ready(discs: availableDiscs)
                }
            }
            // Then refresh from Apple Music (will update with latest data)
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

            // 6. Filter out albums known to be unavailable
            let potentialDiscs = discs.filter { disc in
                !unavailableCache.isUnavailable(title: disc.albumTitle, artist: disc.artistName)
            }

            // 7. Verify catalog availability for remaining albums (throttled to avoid rate limiting)
            let maxConcurrent = 5
            var verifiedDiscs: [Disc] = []

            for chunk in potentialDiscs.chunked(into: maxConcurrent) {
                let chunkResults = await withTaskGroup(of: Disc?.self) { group in
                    for disc in chunk {
                        group.addTask {
                            let resolution = await self.albumService.resolveCatalogAlbum(
                                title: disc.albumTitle,
                                artist: disc.artistName
                            )
                            switch resolution {
                            case .resolved:
                                return disc
                            case .unavailable:
                                // Only mark as unavailable when we're SURE it's not in the catalog
                                self.unavailableCache.markUnavailable(title: disc.albumTitle, artist: disc.artistName)
                                return nil
                            case .error:
                                // Temporary error - don't cache, but also don't show in wallet this time
                                return nil
                            }
                        }
                    }
                    var results: [Disc] = []
                    for await disc in group {
                        if let disc = disc {
                            results.append(disc)
                        }
                    }
                    return results
                }
                verifiedDiscs.append(contentsOf: chunkResults)
            }

            let sortedDiscs = verifiedDiscs.sorted()

            // 8. Update state and cache
            if sortedDiscs.isEmpty {
                state = .empty(reason: .noAlbumsResolved)
                discCache.clear()
            } else {
                // Preload artwork for first 2 discs before showing wallet
                let discsToPreload = Array(sortedDiscs.prefix(2))
                await artworkCache.preload(discs: discsToPreload, size: CGSize(width: 600, height: 600))

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

// MARK: - Array Extension

private extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
