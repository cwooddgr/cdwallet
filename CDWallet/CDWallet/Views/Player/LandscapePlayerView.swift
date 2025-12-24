import SwiftUI
import MusicKit
import CDWalletCore

/// Landscape-oriented player view with album art, track list, and controls
struct LandscapePlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                // Left side: Album artwork
                albumArtworkSection
                    .frame(maxWidth: .infinity)

                // Right side: Track list and controls
                VStack(spacing: 0) {
                    // Album info header
                    albumInfoHeader
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    // Track listing
                    trackListSection
                        .padding(.top, 10)

                    // Player controls
                    playerControlsSection
                        .padding(.bottom, 20)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }

    // MARK: - Album Artwork Section

    private var albumArtworkSection: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.85

            VStack {
                Spacer()
                if let artwork = playerViewModel.currentAlbum?.artwork,
                   let url = artwork.url(width: Int(size), height: Int(size)) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: size, height: size)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .cornerRadius(8)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Album Info Header

    private var albumInfoHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playerViewModel.currentAlbum?.title ?? "Unknown Album")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)

            Text(playerViewModel.currentAlbum?.artistName ?? "Unknown Artist")
                .font(.title3)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Track List Section

    private var trackListSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let tracks = playerViewModel.currentAlbum?.tracks {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        trackRow(track, number: index + 1)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func trackRow(_ track: Track, number: Int) -> some View {
        let isCurrentTrack = track.id == playerViewModel.currentTrack?.id

        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.body)
                .foregroundColor(isCurrentTrack ? .green : .gray)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 28, alignment: .trailing)

            Text(track.title)
                .font(.body)
                .foregroundColor(isCurrentTrack ? .green : .white)
                .lineLimit(1)

            Spacer()

            if isCurrentTrack && playerViewModel.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - CD Player Display

    private var currentTrackNumber: Int {
        guard let currentTrack = playerViewModel.currentTrack,
              let tracks = playerViewModel.currentAlbum?.tracks else {
            return 0
        }
        if let index = tracks.firstIndex(where: { $0.id == currentTrack.id }) {
            return tracks.distance(from: tracks.startIndex, to: index) + 1
        }
        return 0
    }

    private var cdPlayerDisplay: some View {
        HStack(spacing: 0) {
            // Track number display
            VStack(alignment: .center, spacing: 2) {
                Text("TRACK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7))
                Text(String(format: "%02d", currentTrackNumber))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
            .frame(width: 70)

            Spacer()

            // Time elapsed display
            VStack(alignment: .center, spacing: 2) {
                Text("TIME")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7))
                Text(formatTime(playerViewModel.playbackTime))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
            .frame(width: 100)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Player Controls Section

    private var playerControlsSection: some View {
        VStack(spacing: 16) {
            cdPlayerDisplay

            HStack(spacing: 40) {
                // Previous
                Button {
                    playerViewModel.skipPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                // Play/Pause
                Button {
                    playerViewModel.togglePlayPause()
                } label: {
                    Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }

                // Next
                Button {
                    playerViewModel.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    LandscapePlayerView()
        .environmentObject(PlayerViewModel())
}
