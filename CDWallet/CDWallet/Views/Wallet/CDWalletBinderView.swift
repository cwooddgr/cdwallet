import SwiftUI
import CDWalletCore

/// A physical page in the binder with a CD on each side
struct PhysicalPage: Identifiable {
    let id: Int
    let frontDisc: Disc?  // Visible when page is in right stack (unflipped)
    let backDisc: Disc?   // Visible when page is in left stack (flipped)
}

/// Main container view for the skeuomorphic CD wallet binder
/// Uses a pre-rendered page stack - all pages exist at all times, only rotation changes
struct CDWalletBinderView: View {
    let discs: [Disc]
    let onDiscTap: (Disc) -> Void

    // All physical pages, created once from discs
    private var pages: [PhysicalPage] {
        stride(from: 0, to: discs.count, by: 2).enumerated().map { index, discIndex in
            PhysicalPage(
                id: index,
                frontDisc: discs[discIndex],
                backDisc: discIndex + 1 < discs.count ? discs[discIndex + 1] : nil
            )
        }
    }

    // How many pages have been flipped to the left stack
    @State private var flippedPageCount: Int = 0

    // Current rotation angle of the page being dragged (0-180)
    @State private var dragAngle: Double = 0

    // Which direction we're currently dragging (nil = not dragging)
    @State private var dragDirection: FlipDirection? = nil

    // Whether we're in a completion/cancel animation
    @State private var isAnimating: Bool = false

    // The page currently being interacted with
    private var activePageIndex: Int? {
        guard let direction = dragDirection else { return nil }
        switch direction {
        case .forward:
            // Flipping the top page of right stack (next unflipped page)
            return flippedPageCount < pages.count ? flippedPageCount : nil
        case .backward:
            // Flipping the top page of left stack (most recently flipped page)
            return flippedPageCount > 0 ? flippedPageCount - 1 : nil
        case .none:
            return nil
        }
    }

    private var canGoForward: Bool {
        flippedPageCount < pages.count
    }

    private var canGoBackward: Bool {
        flippedPageCount > 0
    }

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width / 2
            let pageHeight = geometry.size.height * 0.9
            let pageSize = CGSize(width: pageWidth, height: pageHeight)

            ZStack {
                // Dark wallet background
                walletBackground

                // Render all pages
                ForEach(pages) { page in
                    pageView(for: page, size: pageSize)
                }

                // Binder spine (center divider) - on top of pages
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 4)
                    .zIndex(100)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleDragChanged(value, pageWidth: pageWidth)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
    }

    // MARK: - Page Rendering

    @ViewBuilder
    private func pageView(for page: PhysicalPage, size: CGSize) -> some View {
        let isFlipped = page.id < flippedPageCount
        let isActive = page.id == activePageIndex

        // Calculate rotation angle for this page
        let angle: Double = {
            if isActive {
                // This page is being dragged
                if dragDirection == .forward {
                    return dragAngle
                } else {
                    // Backward: angle goes from 180 (flipped) back toward 0
                    return 180 - dragAngle
                }
            } else if isFlipped {
                // Already flipped, sitting at 180°
                return 180
            } else {
                // Not flipped, sitting at 0°
                return 0
            }
        }()

        // Z-index: active page on top, then by stack position
        let zIndex: Double = {
            if isActive {
                return 50
            } else if isFlipped {
                // Left stack: most recently flipped on top
                return Double(page.id)
            } else {
                // Right stack: lowest index on top (reversed)
                return Double(pages.count - page.id)
            }
        }()

        BinderPageView(
            page: page,
            pageSize: size,
            rotationAngle: angle,
            onDiscTap: onDiscTap
        )
        .zIndex(zIndex)
    }

    // MARK: - Background

    private var walletBackground: some View {
        Canvas { context, size in
            // Dark fabric texture
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(white: 0.08))
            )

            // Subtle noise texture
            let noiseSpacing: CGFloat = 3
            for x in stride(from: 0, to: size.width, by: noiseSpacing) {
                for y in stride(from: 0, to: size.height, by: noiseSpacing) {
                    let opacity = Double.random(in: 0.02...0.06)
                    let rect = CGRect(x: x, y: y, width: 1, height: 1)
                    context.fill(Path(rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Gesture Handling

    private func handleDragChanged(_ value: DragGesture.Value, pageWidth: CGFloat) {
        guard !isAnimating else { return }

        let translation = value.translation.width

        // Detect direction if not yet set
        if dragDirection == nil {
            if translation < -10 && canGoForward {
                dragDirection = .forward
            } else if translation > 10 && canGoBackward {
                dragDirection = .backward
            }
        }

        // Update angle based on drag
        guard let direction = dragDirection else { return }

        let normalizedDrag: Double
        switch direction {
        case .forward:
            normalizedDrag = -translation / pageWidth
        case .backward:
            normalizedDrag = translation / pageWidth
        case .none:
            return
        }

        dragAngle = min(180, max(0, normalizedDrag * 180))
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard !isAnimating, dragDirection != nil else {
            resetDragState()
            return
        }

        if dragAngle >= 90 {
            completeFlip()
        } else {
            cancelFlip()
        }
    }

    private func completeFlip() {
        guard let direction = dragDirection else { return }

        isAnimating = true

        withAnimation(.easeOut(duration: 0.3)) {
            dragAngle = 180
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Update which pages are flipped
            switch direction {
            case .forward:
                flippedPageCount += 1
            case .backward:
                flippedPageCount -= 1
            case .none:
                break
            }

            resetDragState()
            isAnimating = false
        }
    }

    private func cancelFlip() {
        isAnimating = true

        withAnimation(.easeOut(duration: 0.25)) {
            dragAngle = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            resetDragState()
            isAnimating = false
        }
    }

    private func resetDragState() {
        dragAngle = 0
        dragDirection = nil
    }
}

/// A single page view with front and back content
struct BinderPageView: View {
    let page: PhysicalPage
    let pageSize: CGSize
    let rotationAngle: Double
    let onDiscTap: (Disc) -> Void

    // Which side is visible based on rotation
    private var showingFront: Bool {
        rotationAngle < 90
    }

    // CD size relative to page
    private var discSize: CGFloat {
        min(pageSize.width, pageSize.height) * 0.85
    }

    var body: some View {
        ZStack {
            // Page background (sleeve texture)
            WovenSleeveView()

            // Show front or back disc based on rotation
            if showingFront {
                if let disc = page.frontDisc {
                    CDDiscSkeuomorphicView(disc: disc, size: discSize)
                        .onTapGesture {
                            onDiscTap(disc)
                        }
                }
            } else {
                if let disc = page.backDisc {
                    CDDiscSkeuomorphicView(disc: disc, size: discSize)
                        .scaleEffect(x: -1, y: 1)  // Counter mirror effect
                        .onTapGesture {
                            onDiscTap(disc)
                        }
                }
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // Shadow for depth
        .shadow(
            color: .black.opacity(0.3 * min(1, abs(rotationAngle - 90) / 45)),
            radius: 8,
            x: rotationAngle < 90 ? -4 : 4,
            y: 2
        )
        // 3D rotation - always rotate around leading edge
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: .leading,
            anchorZ: 0,
            perspective: 0
        )
        // Position: offset so leading edge is at center spine
        .offset(x: pageSize.width / 2)
    }
}

#Preview {
    CDWalletBinderView(discs: []) { _ in }
}
