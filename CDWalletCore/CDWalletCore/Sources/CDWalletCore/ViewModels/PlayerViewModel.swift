import Foundation
import MusicKit
import Combine

/// View model for Now Playing screen
@MainActor
public class PlayerViewModel: ObservableObject {
    @Published public private(set) var currentAlbum: Album?
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var isPlaying: Bool = false

    private let playerController = PlayerController.shared
    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Observe player state
        playerController.$currentAlbum
            .assign(to: &$currentAlbum)

        playerController.$currentTrack
            .assign(to: &$currentTrack)

        playerController.$isPlaying
            .assign(to: &$isPlaying)
    }

    public func playDisc(_ disc: Disc) async {
        // Search catalog for FULL album (all tracks) using title and artist
        print("📀 DEBUG: PlayerViewModel - Playing disc '\(disc.albumTitle)' by '\(disc.artistName)'")
        let albumService = AlbumService()

        // Resolve catalog album by title/artist - this gets the FULL album with ALL tracks
        let resolution = await albumService.resolveCatalogAlbum(title: disc.albumTitle, artist: disc.artistName)

        if case .resolved(let album) = resolution {
            print("📀 DEBUG: PlayerViewModel - Resolved catalog album with \(album.tracks?.count ?? 0) tracks")
            print("📀 DEBUG: PlayerViewModel - Starting playback...")
            do {
                try await playerController.playAlbum(album)
                print("📀 DEBUG: PlayerViewModel - Playback started successfully")
            } catch {
                print("📀 DEBUG: PlayerViewModel - Playback error: \(error)")
            }
        } else {
            print("📀 DEBUG: PlayerViewModel - Failed to resolve catalog album")
        }
    }

    public func togglePlayPause() {
        playerController.togglePlayPause()
    }

    public func skipNext() {
        playerController.skipToNextTrack()
    }

    public func skipPrevious() {
        playerController.skipToPreviousTrack()
    }

    public func seek(to seconds: TimeInterval) {
        playerController.seek(to: seconds)
    }
}
