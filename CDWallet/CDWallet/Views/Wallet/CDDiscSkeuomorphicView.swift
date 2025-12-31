import SwiftUI
import MusicKit
import CDWalletCore

/// A CD disc with album artwork that reveals the sleeve texture through the center hole
struct CDDiscSkeuomorphicView: View {
    let disc: Disc
    let size: CGFloat

    @State private var image: UIImage?

    // Center hole is roughly 12% of CD diameter
    private var holeSize: CGFloat { size * 0.12 }

    var body: some View {
        ZStack {
            // Sleeve texture visible through center hole
            WovenSleeveView()
                .frame(width: size, height: size)
                .clipShape(Circle())

            // Album artwork with center hole cut out
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .mask {
                        // Full circle minus center hole
                        Circle()
                            .frame(width: size, height: size)
                            .overlay {
                                Circle()
                                    .frame(width: holeSize, height: holeSize)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
            } else {
                // Placeholder while loading
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .mask {
                        Circle()
                            .frame(width: size, height: size)
                            .overlay {
                                Circle()
                                    .frame(width: holeSize, height: holeSize)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
            }

            // Subtle rim highlight around the hole
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: holeSize, height: holeSize)
        }
        .frame(width: size, height: size)
        .task(id: disc.id) {
            let fetchedImage = await ArtworkCache.shared.artwork(
                for: disc,
                size: CGSize(width: size * 2, height: size * 2)
            )
            await MainActor.run {
                self.image = fetchedImage
            }
        }
    }
}
