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
    @Published public private(set) var playbackTime: TimeInterval = 0

    private var stateObserver: AnyCancellable?
    private var timeObserver: Timer?

    private init() {
        observePlayerState()
        startTimeObserver()
    }

    private func startTimeObserver() {
        timeObserver = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playbackTime = self?.player.playbackTime ?? 0
                self?.updateCurrentTrackFromQueue()
            }
        }
    }

    private func updateCurrentTrackFromQueue() {
        guard let entry = player.queue.currentEntry else { return }

        // Match current playing item to a track in the album by title
        let title = entry.title
        if let tracks = currentAlbum?.tracks,
           let matchingTrack = tracks.first(where: { $0.title == title }) {
            currentTrack = matchingTrack
        }
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
        // Set initial track to first track
        currentTrack = album.tracks?.first
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

    public func stop() {
        player.stop()
        currentAlbum = nil
        currentTrack = nil
        playbackTime = 0
    }

    public func pause() {
        player.pause()
    }

    public func resume() async {
        try? await player.play()
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

    }
}
