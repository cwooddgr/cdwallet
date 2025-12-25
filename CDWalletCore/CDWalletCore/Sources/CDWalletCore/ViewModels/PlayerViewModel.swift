import Foundation
import MusicKit
import Combine

/// View model for Now Playing screen
@MainActor
public class PlayerViewModel: ObservableObject {
    @Published public private(set) var currentAlbum: Album?
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var playbackTime: TimeInterval = 0

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

        playerController.$playbackTime
            .assign(to: &$playbackTime)
    }

    /// Play a disc. Returns true if playback started successfully.
    @discardableResult
    public func playDisc(_ disc: Disc) async -> Bool {
        print("🎵 playDisc: '\(disc.albumTitle)' by '\(disc.artistName)'")

        let albumService = AlbumService()
        let resolution = await albumService.resolveCatalogAlbum(title: disc.albumTitle, artist: disc.artistName)

        switch resolution {
        case .resolved(let album):
            do {
                try await playerController.playAlbum(album)
                print("🎵 Playback started: \(album.tracks?.count ?? 0) tracks")
                return true
            } catch {
                print("🎵 Playback error: \(error)")
                return false
            }
        case .unavailable(let id):
            print("🎵 FAILED - unavailable: \(id)")
            return false
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
