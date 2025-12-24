import SwiftUI
import MusicKit

/// A single CD disc showing album artwork clipped to a circle with center hole
struct CDDiscView: View {
    let artwork: Artwork?
    let size: CGFloat

    // Center hole is roughly 12% of CD diameter
    private var holeSize: CGFloat { size * 0.12 }

    var body: some View {
        ZStack {
            // Album artwork clipped to circle
            if let artwork = artwork,
               let url = artwork.url(width: Int(size * 2), height: Int(size * 2)) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
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
    }
}

#Preview {
    CDDiscView(artwork: nil, size: 200)
        .background(Color.black)
}
