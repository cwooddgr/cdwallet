import SwiftUI
import CDWalletCore
import MusicKit

struct DiscCardView: View {
    let disc: Disc
    @State private var artworkImage: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            // Album artwork
            Group {
                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            // Metadata
            VStack(spacing: 4) {
                Text(disc.albumTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(disc.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .task {
            artworkImage = await ArtworkCache.shared.artwork(for: disc, size: CGSize(width: 400, height: 400))
        }
    }
}
