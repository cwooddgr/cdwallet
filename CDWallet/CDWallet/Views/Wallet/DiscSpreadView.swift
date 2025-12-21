import SwiftUI
import CDWalletCore

/// A single page/spread showing 2+ discs
struct DiscSpreadView: View {
    let discs: [Disc]
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad: 3x2 Grid layout that fits within screen
                let availableHeight = geometry.size.height - 64 // padding
                let availableWidth = geometry.size.width - 64 // padding
                let spacing: CGFloat = 24
                let rows = 2
                let columns = 3
                let itemHeight = (availableHeight - spacing) / CGFloat(rows)
                let itemWidth = (availableWidth - (spacing * CGFloat(columns - 1))) / CGFloat(columns)

                LazyVGrid(columns: [
                    GridItem(.fixed(itemWidth), spacing: spacing),
                    GridItem(.fixed(itemWidth), spacing: spacing),
                    GridItem(.fixed(itemWidth), spacing: spacing)
                ], spacing: spacing) {
                    ForEach(discs) { disc in
                        DiscCardView(disc: disc)
                            .frame(height: itemHeight)
                            .onTapGesture {
                                Task {
                                    await playerViewModel.playDisc(disc)
                                }
                            }
                    }
                }
                .padding(32)
            } else {
                // iPhone: 2-up vertical layout
                VStack(spacing: 32) {
                    ForEach(discs) { disc in
                        DiscCardView(disc: disc)
                            .frame(maxHeight: geometry.size.height / CGFloat(discs.count) - 32)
                            .onTapGesture {
                                Task {
                                    await playerViewModel.playDisc(disc)
                                }
                            }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
    }
}

#Preview("iPhone - 2 Discs") {
    DiscSpreadView(discs: [])
        .environmentObject(PlayerViewModel())
}
