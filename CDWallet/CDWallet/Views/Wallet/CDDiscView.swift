import SwiftUI
import MusicKit
import CDWalletCore

/// A single CD disc showing album artwork clipped to a circle with center hole
struct CDDiscView: View {
    let disc: Disc
    let size: CGFloat

    @State private var image: UIImage?

    // Center hole is roughly 12% of CD diameter
    private var holeSize: CGFloat { size * 0.12 }

    var body: some View {
        ZStack {
            // Album artwork clipped to circle
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Placeholder
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
            }

            // Center hole
            Circle()
                .fill(Color.black)
                .frame(width: holeSize, height: holeSize)
        }
        .frame(width: size, height: size)
        .task(id: disc.id) {
            // Load from cache (which handles memory, disk, and network)
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

// Preview requires a mock Disc which isn't easily available
// Use in context of CDWalletView for testing
