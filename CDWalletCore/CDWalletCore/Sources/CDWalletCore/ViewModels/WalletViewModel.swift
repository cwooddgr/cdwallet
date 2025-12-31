import Foundation
import MusicKit
import Combine

/// Main view model coordinating wallet state
@MainActor
public class WalletViewModel: ObservableObject {
    @Published public private(set) var state: WalletState = .loading
    @Published public private(set) var diagnostics: DiagnosticsSnapshot?

    private let authService = AuthorizationService()
    private let playlistService = PlaylistService()
    private let albumService = AlbumService()
    private let discCache = DiscCache.shared
    private let artworkCache = ArtworkCache.shared
    private let unavailableCache = UnavailableAlbumsCache.shared

    private var lastRefreshTime: Date?

    public init() {
        // Check authorization synchronously to avoid flashing auth screen
        if MusicAuthorization.currentStatus != .authorized {
            state = .needsAuthorization
        } else if let cachedDiscs = discCache.load(), !cachedDiscs.isEmpty {
            // If we have cached data, show it immediately (no loading flash)
            let availableDiscs = cachedDiscs.filter { disc in
                !unavailableCache.isUnavailable(title: disc.albumTitle, artist: disc.artistName)
            }
            if !availableDiscs.isEmpty {
                state = .ready(discs: availableDiscs, totalCount: availableDiscs.count)
            }
        }
        // Otherwise stays at .loading (default)
    }

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
                    state = .ready(discs: availableDiscs, totalCount: availableDiscs.count)
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
            print("📀 DEBUG: Built \(discs.count) discs from library")

            // 6. Filter out albums known to be unavailable (from previous playback failures)
            let filteredDiscs = discs.filter { disc in
                !unavailableCache.isUnavailable(title: disc.albumTitle, artist: disc.artistName)
            }
            let totalAvailableCount = filteredDiscs.count
            print("📀 DEBUG: After unavailable filter: \(totalAvailableCount) discs")

            // 7. Limit to maxWalletAlbums (20) - no point processing more than we'll show
            let limitedDiscs = Array(filteredDiscs.prefix(maxWalletAlbums))
            if totalAvailableCount > maxWalletAlbums {
                print("📀 DEBUG: Limiting to \(maxWalletAlbums) discs (hiding \(totalAvailableCount - maxWalletAlbums))")
            }

            // 8. Verify NEW albums only (ones not in our disc cache)
            // Previously verified albums from cache don't need re-verification
            let cachedAlbumIDs = Set((discCache.load() ?? []).map { $0.id })
            print("📀 DEBUG: Cached album IDs: \(cachedAlbumIDs.count)")
            let (cachedDiscs, newDiscs) = limitedDiscs.reduce(into: ([Disc](), [Disc]())) { result, disc in
                if cachedAlbumIDs.contains(disc.id) {
                    result.0.append(disc)
                } else {
                    result.1.append(disc)
                }
            }
            print("📀 DEBUG: Cached discs: \(cachedDiscs.count), New discs to verify: \(newDiscs.count)")

            // Verify only new albums with catalog (throttled)
            var verifiedNewDiscs: [Disc] = []
            for chunk in newDiscs.chunked(into: 5) {
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
                                self.unavailableCache.markUnavailable(title: disc.albumTitle, artist: disc.artistName)
                                return nil
                            case .error:
                                // On error, include anyway - will verify at playback
                                return disc
                            }
                        }
                    }
                    var results: [Disc] = []
                    for await disc in group {
                        if let disc = disc { results.append(disc) }
                    }
                    return results
                }
                verifiedNewDiscs.append(contentsOf: chunkResults)
            }

            print("📀 DEBUG: Verified new discs: \(verifiedNewDiscs.count)")
            let sortedDiscs = (cachedDiscs + verifiedNewDiscs).sorted()
            print("📀 DEBUG: Total discs to show: \(sortedDiscs.count)")

            // 9. Update state and cache
            if sortedDiscs.isEmpty {
                state = .empty(reason: .noAlbumsResolved)
                discCache.clear()
            } else {
                // Preload artwork for first 2 discs before showing wallet
                let discsToPreload = Array(sortedDiscs.prefix(2))
                await artworkCache.preload(discs: discsToPreload, size: CGSize(width: 600, height: 600))

                // Only report higher totalCount if we actually hit the limit
                // (not just because some albums failed verification)
                let reportedTotal = totalAvailableCount > maxWalletAlbums ? totalAvailableCount : sortedDiscs.count
                state = .ready(discs: sortedDiscs, totalCount: reportedTotal)
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
