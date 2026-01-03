import SwiftUI
import MusicKit
import CDWalletCore

/// A realistic CD disc with proper concentric regions:
/// - Center hole (0-0.125R): Fully transparent
/// - Album artwork (0.125R-0.9667R): Album art with clamp ring masked out
/// - Clamp/stack ring (0.2167R-0.2750R): Clear plastic with gradient highlight
/// - Outer rim (0.9667R-1.0R): Clear plastic
struct CDDiscSkeuomorphicView: View {
    let disc: Disc
    let size: CGFloat

    @State private var image: UIImage?

    // CD region constants (as fraction of radius)
    private let centerHoleRadius: CGFloat = 0.125
    private let artworkOuterRadius: CGFloat = 0.98
    private let clampInnerRadius: CGFloat = 0.2650
    private let clampOuterRadius: CGFloat = 0.2750

    private var R: CGFloat { size / 2 }

    var body: some View {
        ZStack {
            // 1. Base: Sleeve texture (shows through center hole, clamp ring, outer rim)
            WovenSleeveView()
                .frame(width: size, height: size)
                .clipShape(Circle())

            // 2. Album artwork (0.125R to 0.9667R) with clamp ring masked out
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .mask {
                        artworkMask()
                    }
            } else {
                // Placeholder while loading
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .mask {
                        artworkMask()
                    }
            }

            // 3. Outer clear rim (0.9667R to 1.0R) - clear plastic with subtle tint
            outerRimOverlay()

            // 4. Clamp ring (0.2167R to 0.2750R) - clear plastic with gradient highlight
            clampRingOverlay()
        }
        .frame(width: size, height: size)
        .mask {
            // Final mask: full circle with center hole cut out
            Circle()
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .frame(width: R * 2 * centerHoleRadius, height: R * 2 * centerHoleRadius)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
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

    // MARK: - Helper Views

    /// Creates an annulus from 0.125R to 0.9667R with the clamp ring (0.2167R-0.2750R) cut out
    private func artworkMask() -> some View {
        Circle()
            .frame(width: R * 2 * artworkOuterRadius, height: R * 2 * artworkOuterRadius)
            .overlay {
                // Cut out center hole region
                Circle()
                    .frame(width: R * 2 * centerHoleRadius, height: R * 2 * centerHoleRadius)
                    .blendMode(.destinationOut)
            }
            .overlay {
                // Cut out clamp ring
                clampRingShape()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    /// Annulus shape from 0.2167R to 0.2750R (for masking)
    private func clampRingShape() -> some View {
        Circle()
            .frame(width: R * 2 * clampOuterRadius, height: R * 2 * clampOuterRadius)
            .overlay {
                Circle()
                    .frame(width: R * 2 * clampInnerRadius, height: R * 2 * clampInnerRadius)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    /// Clear plastic clamp ring with gradient highlight
    private func clampRingOverlay() -> some View {
        ZStack {
            // Clear plastic tint (mostly transparent)
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.15),
                    lineWidth: R * (clampOuterRadius - clampInnerRadius)
                )
                .frame(width: R * 2 * clampOuterRadius, height: R * 2 * clampOuterRadius)

            // Gradient highlight suggesting depth/bevel
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .clear, .black.opacity(0.1)],
                        center: .center,
                        startRadius: R * clampInnerRadius,
                        endRadius: R * clampOuterRadius
                    ),
                    lineWidth: R * (clampOuterRadius - clampInnerRadius)
                )
                .frame(width: R * 2 * clampOuterRadius, height: R * 2 * clampOuterRadius)
        }
    }

    /// Clear plastic outer rim from 0.9667R to 1.0R
    private func outerRimOverlay() -> some View {
        Circle()
            .strokeBorder(
                Color.white.opacity(0.1),
                lineWidth: R * (1.0 - artworkOuterRadius)
            )
            .frame(width: size, height: size)
    }
}
