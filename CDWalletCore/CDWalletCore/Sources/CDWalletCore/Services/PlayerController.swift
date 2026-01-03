import Foundation
import MusicKit
import Combine

/// Controls playback using ApplicationMusicPlayer
@MainActor
public class PlayerController: ObservableObject {
    public static let shared = PlayerController()

    // Access player directly - avoid storing to prevent early initialization
    private nonisolated(unsafe) var player: ApplicationMusicPlayer {
        ApplicationMusicPlayer.shared
    }

    // Track if we've set up observers (only do this once, after first play)
    private var isObserving = false

    @Published public private(set) var currentAlbum: Album?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var playbackTime: TimeInterval = 0

    private var stateObserver: AnyCancellable?
    private var timeObserver: Timer?

    private init() {
        // Don't access player here - wait until first use after authorization
    }

    /// Start observing player state (called on first play)
    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        observePlayerState()
        startTimeObserver()
    }

    private func startTimeObserver() {
        timeObserver = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isObserving else { return }
                self.playbackTime = self.player.playbackTime
                self.updateCurrentTrackFromQueue()
            }
        }
    }

    private func updateCurrentTrackFromQueue() {
        guard isObserving, let entry = player.queue.currentEntry else { return }

        // Match current playing item to a track in the album by title
        let title = entry.title
        if let tracks = currentAlbum?.tracks,
           let matchingTrack = tracks.first(where: { $0.title == title }) {
            currentTrack = matchingTrack
        }
    }

    /// Play a full album (canonical track order) - CRITICAL: Album completion rule
    public func playAlbum(_ album: Album, startTrackID: MusicItemID? = nil) async throws {
        startObservingIfNeeded()

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
        startObservingIfNeeded()
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task {
                try? await player.play()
            }
        }
    }

    public func stop() {
        guard isObserving else { return }
        player.stop()
        currentAlbum = nil
        currentTrack = nil
        playbackTime = 0
    }

    public func pause() {
        guard isObserving else { return }
        player.pause()
    }

    public func resume() async {
        startObservingIfNeeded()
        try? await player.play()
    }

    public func skipToNextTrack() {
        guard isObserving else { return }
        Task {
            try? await player.skipToNextEntry()
        }
    }

    public func skipToPreviousTrack() {
        guard isObserving else { return }
        Task {
            try? await player.skipToPreviousEntry()
        }
    }

    public func seek(to timeInSeconds: TimeInterval) {
        guard isObserving else { return }
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
