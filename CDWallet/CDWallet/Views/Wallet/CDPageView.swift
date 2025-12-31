import SwiftUI
import CDWalletCore

/// Direction of page flip
enum FlipDirection {
    case forward   // Right page flips left (next spread)
    case backward  // Left page flips right (previous spread)
    case none
}

/// A single flippable page in the CD binder with 3D rotation
struct CDPageView: View {
    let frontDisc: Disc?
    let backDisc: Disc?
    let pageSize: CGSize
    let rotationAngle: Double
    let flipDirection: FlipDirection
    let onDiscTap: (Disc) -> Void

    // Determine which side is visible based on rotation
    private var showingFront: Bool {
        rotationAngle < 90
    }

    // CD size relative to page
    private var discSize: CGFloat {
        min(pageSize.width, pageSize.height) * 0.85
    }

    // Anchor point depends on flip direction
    private var anchor: UnitPoint {
        flipDirection == .backward ? .trailing : .leading
    }

    // Shadow direction depends on flip direction
    private var shadowX: CGFloat {
        flipDirection == .backward ? 4 : -4
    }

    var body: some View {
        ZStack {
            // Page background (sleeve texture)
            WovenSleeveView()

            // Content: either front or back disc
            if showingFront {
                // Front side
                if let disc = frontDisc {
                    CDDiscSkeuomorphicView(disc: disc, size: discSize)
                        .onTapGesture {
                            onDiscTap(disc)
                        }
                }
            } else {
                // Back side - Scale X by -1 to counter the mirror effect from rotation > 90°
                if let disc = backDisc {
                    CDDiscSkeuomorphicView(disc: disc, size: discSize)
                        .scaleEffect(x: -1, y: 1)
                        .onTapGesture {
                            onDiscTap(disc)
                        }
                }
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // Shadow for depth during flip
        .shadow(
            color: .black.opacity(0.3 * min(1, rotationAngle / 45)),
            radius: 8,
            x: shadowX,
            y: 2
        )
        // 3D rotation around Y-axis
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: anchor,
            anchorZ: 0,
            perspective: 1/500
        )
    }
}

/// Manages the interactive page flip gesture state
struct PageFlipState {
    var isDragging: Bool = false
    var dragOffset: CGFloat = 0
    var currentAngle: Double = 0
    var direction: FlipDirection = .none

    /// Convert drag offset to rotation angle (0-180 range) and detect direction
    mutating func updateAngle(for translation: CGFloat, pageWidth: CGFloat, canGoForward: Bool, canGoBackward: Bool) {
        // Detect direction from drag if not yet set
        if direction == .none {
            if translation < 0 && canGoForward {
                direction = .forward
            } else if translation > 0 && canGoBackward {
                direction = .backward
            }
        }

        // Calculate angle based on direction
        switch direction {
        case .forward:
            let normalizedDrag = -translation / pageWidth
            currentAngle = min(180, max(0, normalizedDrag * 180))
        case .backward:
            let normalizedDrag = translation / pageWidth
            currentAngle = min(180, max(0, normalizedDrag * 180))
        case .none:
            currentAngle = 0
        }
    }

    /// Determine if flip should complete or cancel based on position
    func shouldCompleteFlip(velocity: CGFloat) -> Bool {
        // Complete flip if past 90 degrees
        currentAngle >= 90
    }
}
