import SwiftUI
import CDWalletCore

/// Main container view for the skeuomorphic CD wallet binder
struct CDWalletBinderView: View {
    let discs: [Disc]
    let onDiscTap: (Disc) -> Void

    @State private var currentSpreadIndex: Int = 0
    @State private var flipState = PageFlipState()
    @State private var isAnimating: Bool = false

    // Group discs into spreads (pairs)
    private var spreads: [[Disc]] {
        stride(from: 0, to: discs.count, by: 2).map { i in
            Array(discs[i..<min(i + 2, discs.count)])
        }
    }

    private var totalSpreads: Int {
        spreads.count
    }

    // Current spread's discs
    private var leftDisc: Disc? {
        guard currentSpreadIndex < spreads.count else { return nil }
        return spreads[currentSpreadIndex].first
    }

    private var rightDisc: Disc? {
        guard currentSpreadIndex < spreads.count,
              spreads[currentSpreadIndex].count > 1 else { return nil }
        return spreads[currentSpreadIndex][1]
    }

    // Next spread's left disc (shown on back of flipping page)
    private var nextLeftDisc: Disc? {
        let nextIndex = currentSpreadIndex + 1
        guard nextIndex < spreads.count else { return nil }
        return spreads[nextIndex].first
    }

    // Previous spread's right disc (for flipping backward)
    private var prevRightDisc: Disc? {
        let prevIndex = currentSpreadIndex - 1
        guard prevIndex >= 0 else { return nil }
        let prevSpread = spreads[prevIndex]
        return prevSpread.count > 1 ? prevSpread[1] : prevSpread.first
    }

    // Previous spread's left disc (shown when flipping backward reveals previous spread)
    private var prevLeftDisc: Disc? {
        let prevIndex = currentSpreadIndex - 1
        guard prevIndex >= 0 else { return nil }
        return spreads[prevIndex].first
    }

    // Can navigate forward/backward
    private var canGoForward: Bool {
        currentSpreadIndex < totalSpreads - 1
    }

    private var canGoBackward: Bool {
        currentSpreadIndex > 0
    }

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width / 2
            let pageHeight = geometry.size.height * 0.9
            let pageSize = CGSize(width: pageWidth, height: pageHeight)

            ZStack {
                // Dark wallet background
                walletBackground

                // Left side pages
                // When flipping backward: show prevSpreadPreview, hide leftPage
                // Otherwise: show leftPage
                HStack(spacing: 0) {
                    ZStack {
                        // Preview of previous spread (revealed when flipping backward)
                        prevSpreadPreview(size: pageSize)
                            .opacity(flipState.direction == .backward ? 1 : 0)

                        // Static left page (hidden when flipping backward)
                        leftPage(size: pageSize)
                            .opacity(flipState.direction == .backward ? 0 : 1)
                    }
                    Spacer()
                }
                .zIndex(1)

                // Right side pages
                // When flipping forward: show nextSpreadPreview, hide rightPage
                // Otherwise: show rightPage
                HStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        // Preview of next spread (revealed when flipping forward)
                        nextSpreadPreview(size: pageSize)
                            .opacity(flipState.direction == .forward ? 1 : 0)

                        // Static right page (hidden when flipping forward)
                        rightPage(size: pageSize)
                            .opacity(flipState.direction == .forward ? 0 : 1)
                    }
                }
                .zIndex(1)

                // Layer 2: Flipping pages (always rendered to avoid insertion flash)

                // Backward flipping page (covers left static page)
                HStack(spacing: 0) {
                    backwardFlippingPage(size: pageSize)
                    Spacer()
                }
                .zIndex(flipState.direction == .backward ? 2 : -1)
                .opacity(flipState.direction == .backward ? 1 : 0)
                .allowsHitTesting(flipState.direction == .backward)

                // Forward flipping page (covers right static page)
                HStack(spacing: 0) {
                    Spacer()
                    forwardFlippingPage(size: pageSize)
                }
                .zIndex(flipState.direction == .forward ? 2 : -1)
                .opacity(flipState.direction == .forward ? 1 : 0)
                .allowsHitTesting(flipState.direction == .forward)

                // Binder spine (center divider) - on top of pages
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 4)
                    .zIndex(3)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isAnimating else { return }
                        flipState.isDragging = true
                        flipState.dragOffset = value.translation.width
                        flipState.updateAngle(
                            for: value.translation.width,
                            pageWidth: pageSize.width,
                            canGoForward: canGoForward,
                            canGoBackward: canGoBackward
                        )
                    }
                    .onEnded { value in
                        guard !isAnimating else { return }
                        flipState.isDragging = false
                        let velocity = value.velocity.width

                        if flipState.shouldCompleteFlip(velocity: velocity) {
                            completeFlip()
                        } else {
                            cancelFlip()
                        }
                    }
            )
        }
    }

    // MARK: - Subviews

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

    private func leftPage(size: CGSize) -> some View {
        ZStack {
            WovenSleeveView()

            if let disc = leftDisc {
                CDDiscSkeuomorphicView(disc: disc, size: min(size.width, size.height) * 0.85)
                    .onTapGesture {
                        onDiscTap(disc)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .rotation3DEffect(
            .degrees(0),
            axis: (x: 0, y: 1, z: 0),
            anchor: .trailing,
            anchorZ: 0,
            perspective: 0
        )
    }

    private func rightPage(size: CGSize) -> some View {
        ZStack {
            WovenSleeveView()

            if let disc = rightDisc {
                CDDiscSkeuomorphicView(disc: disc, size: min(size.width, size.height) * 0.85)
                    .onTapGesture {
                        onDiscTap(disc)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .rotation3DEffect(
            .degrees(0),
            axis: (x: 0, y: 1, z: 0),
            anchor: .leading,
            anchorZ: 0,
            perspective: 0
        )
    }

    private func nextSpreadPreview(size: CGSize) -> some View {
        ZStack {
            WovenSleeveView()

            // Show the right disc of the next spread
            if let nextIndex = currentSpreadIndex + 1 < spreads.count ? currentSpreadIndex + 1 : nil,
               spreads[nextIndex].count > 1,
               let disc = spreads[nextIndex].last {
                CDDiscSkeuomorphicView(disc: disc, size: min(size.width, size.height) * 0.85)
                    .onTapGesture {
                        onDiscTap(disc)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .rotation3DEffect(
            .degrees(0),
            axis: (x: 0, y: 1, z: 0),
            anchor: .leading,
            anchorZ: 0,
            perspective: 0
        )
    }

    private func prevSpreadPreview(size: CGSize) -> some View {
        ZStack {
            WovenSleeveView()

            // Show the left disc of the previous spread
            if let disc = prevLeftDisc {
                CDDiscSkeuomorphicView(disc: disc, size: min(size.width, size.height) * 0.85)
                    .onTapGesture {
                        onDiscTap(disc)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .rotation3DEffect(
            .degrees(0),
            axis: (x: 0, y: 1, z: 0),
            anchor: .trailing,
            anchorZ: 0,
            perspective: 0
        )
    }

    private func forwardFlippingPage(size: CGSize) -> some View {
        CDPageView(
            frontDisc: rightDisc,
            backDisc: nextLeftDisc,
            pageSize: size,
            rotationAngle: flipState.currentAngle,
            flipDirection: .forward,
            onDiscTap: onDiscTap
        )
    }

    private func backwardFlippingPage(size: CGSize) -> some View {
        // When flipping backward, the page pivots from the right edge
        // Front shows left disc of current spread, back shows right disc of previous spread
        CDPageView(
            frontDisc: leftDisc,
            backDisc: prevRightDisc,
            pageSize: size,
            rotationAngle: flipState.currentAngle,
            flipDirection: .backward,
            onDiscTap: onDiscTap
        )
    }

    // MARK: - Flip Actions

    private func completeFlip() {
        switch flipState.direction {
        case .forward:
            guard currentSpreadIndex < totalSpreads - 1 else {
                cancelFlip()
                return
            }
            isAnimating = true
            withAnimation(.easeOut(duration: 0.3)) {
                flipState.currentAngle = 180
            }
            // After animation: update index first, then reset flip state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                currentSpreadIndex += 1
                // Small delay before resetting direction to ensure smooth handoff
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    flipState = PageFlipState()
                    isAnimating = false
                }
            }

        case .backward:
            guard currentSpreadIndex > 0 else {
                cancelFlip()
                return
            }
            isAnimating = true
            withAnimation(.easeOut(duration: 0.3)) {
                flipState.currentAngle = 180
            }
            // After animation: update index first, then reset flip state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                currentSpreadIndex -= 1
                // Small delay before resetting direction to ensure smooth handoff
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    flipState = PageFlipState()
                    isAnimating = false
                }
            }

        case .none:
            cancelFlip()
        }
    }

    private func cancelFlip() {
        isAnimating = true
        withAnimation(.easeOut(duration: 0.25)) {
            flipState.currentAngle = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            flipState = PageFlipState()
            isAnimating = false
        }
    }
}

#Preview {
    CDWalletBinderView(discs: []) { _ in }
}
