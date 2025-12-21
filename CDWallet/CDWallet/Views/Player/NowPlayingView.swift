import SwiftUI
import CDWalletCore
import MusicKit

struct NowPlayingView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Album artwork
                if let artwork = playerViewModel.currentAlbum?.artwork {
                    ArtworkImage(artwork: artwork, size: CGSize(width: 300, height: 300))
                        .frame(width: 300, height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }

                // Album info
                VStack(spacing: 8) {
                    Text(playerViewModel.currentAlbum?.title ?? "")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(playerViewModel.currentAlbum?.artistName ?? "")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Track info
                if let track = playerViewModel.currentTrack {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Playback controls
                HStack(spacing: 48) {
                    Button {
                        playerViewModel.skipPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 32))
                    }

                    Button {
                        playerViewModel.togglePlayPause()
                    } label: {
                        Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }

                    Button {
                        playerViewModel.skipNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 32))
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ArtworkImage: View {
    let artwork: Artwork
    let size: CGSize
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task {
            do {
                // iOS 18 API: url(width:height:)
                guard let url = artwork.url(width: Int(size.width), height: Int(size.height)) else {
                    return
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                image = UIImage(data: data)
            } catch {
                // Handle error silently for MVP
            }
        }
    }
}

#Preview {
    NowPlayingView()
        .environmentObject(PlayerViewModel())
}
