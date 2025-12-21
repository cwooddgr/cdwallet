import Foundation
import MusicKit
import Combine

/// Controls playback using ApplicationMusicPlayer
@MainActor
public class PlayerController: ObservableObject {
    public static let shared = PlayerController()

    private nonisolated(unsafe) let player = ApplicationMusicPlayer.shared

    @Published public private(set) var currentAlbum: Album?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentTrack: Track?

    private var stateObserver: AnyCancellable?
    private var queueObserver: AnyCancellable?

    private init() {
        observePlayerState()
    }

    /// Play a full album (canonical track order) - CRITICAL: Album completion rule
    public func playAlbum(_ album: Album, startTrackID: MusicItemID? = nil) async throws {
        // ⚠️ CRITICAL: Set queue to the resolved album (full album semantics)
        // NEVER queue playlist tracks directly

        // iOS 18 API: Use album directly in queue initialization
        player.queue = [album]

        // Start playback
        try await player.play()

        currentAlbum = album
    }

    public func togglePlayPause() {
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task {
                try? await player.play()
            }
        }
    }

    public func skipToNextTrack() {
        Task {
            try? await player.skipToNextEntry()
        }
    }

    public func skipToPreviousTrack() {
        Task {
            try? await player.skipToPreviousEntry()
        }
    }

    public func seek(to timeInSeconds: TimeInterval) {
        player.playbackTime = timeInSeconds
    }

    // MARK: - Private

    private func observePlayerState() {
        stateObserver = player.state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = self?.player.state.playbackStatus == .playing
            }
        }

        queueObserver = player.queue.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.currentTrack = self?.player.queue.currentEntry?.item as? Track
            }
        }
    }
}
