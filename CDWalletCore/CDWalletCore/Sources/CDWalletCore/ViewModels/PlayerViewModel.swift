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
    @Published public private(set) var currentDiscID: String?

    /// Tracks if pause was user-initiated (vs app-initiated when closing player)
    @Published public private(set) var wasUserPaused: Bool = false

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
        case .resolved(let album), .resolvedWithDate(let album, _):
            do {
                try await playerController.playAlbum(album)
                currentDiscID = disc.id
                wasUserPaused = false
                print("🎵 Playback started: \(album.tracks?.count ?? 0) tracks")
                return true
            } catch {
                print("🎵 Playback error: \(error)")
                return false
            }
        case .unavailable(let id):
            print("🎵 FAILED - unavailable: \(id)")
            // Mark as unavailable so it gets hidden from wallet
            UnavailableAlbumsCache.shared.markUnavailable(title: disc.albumTitle, artist: disc.artistName)
            return false
        case .error(let id):
            print("🎵 FAILED - temporary error: \(id)")
            // Don't mark as unavailable - might work next time
            return false
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            userPause()
        } else {
            Task {
                await resume()
            }
        }
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

    public func stop() {
        playerController.stop()
        currentDiscID = nil
    }

    /// Pause initiated by user (tap pause button)
    public func userPause() {
        wasUserPaused = true
        playerController.pause()
    }

    /// Pause initiated by app (closing player view)
    public func appPause() {
        // Don't change wasUserPaused - preserve previous state
        playerController.pause()
    }

    public func resume() async {
        wasUserPaused = false
        await playerController.resume()
    }

    /// Check if the given disc is already loaded (paused or playing)
    public func isDiscLoaded(_ disc: Disc) -> Bool {
        return currentDiscID == disc.id
    }
}
