import SwiftUI
import CDWalletCore

/// Shows two CDs side by side like an open CD wallet
struct WalletSpreadView2: View {
    let leftDisc: Disc?
    let rightDisc: Disc?
    let onDiscTapped: (Disc) -> Void

    var body: some View {
        GeometryReader { geometry in
            let discSize = min(geometry.size.width * 0.4, geometry.size.height * 0.8)

            HStack(spacing: geometry.size.width * 0.05) {
                // Left CD
                if let disc = leftDisc {
                    CDDiscView(disc: disc, size: discSize)
                        .onTapGesture { onDiscTapped(disc) }
                } else {
                    Color.clear.frame(width: discSize, height: discSize)
                }

                // Right CD
                if let disc = rightDisc {
                    CDDiscView(disc: disc, size: discSize)
                        .onTapGesture { onDiscTapped(disc) }
                } else {
                    Color.clear.frame(width: discSize, height: discSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
