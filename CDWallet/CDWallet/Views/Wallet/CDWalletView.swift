import SwiftUI
import CDWalletCore

/// CD Wallet view - shows discs like a physical CD binder
struct CDWalletView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var currentPage = 0
    @State private var showingPlayer = false
    @State private var showingLimitAlert = false
    @State private var hasShownLimitAlert = false

    var discs: [Disc] {
        if case .ready(let discs, _) = walletViewModel.state {
            return discs
        }
        return []
    }

    /// Group discs into spreads (2 per spread)
    var spreads: [[(offset: Int, disc: Disc)]] {
        let indexed = discs.enumerated().map { ($0.offset, $0.element) }
        return stride(from: 0, to: indexed.count, by: 2).map { i in
            Array(indexed[i..<min(i + 2, indexed.count)])
        }
    }

    var body: some View {
        ZStack {
            // Dark background (the wallet case)
            Color(white: 0.1)
                .ignoresSafeArea()

            // CD spreads with paging
            TabView(selection: $currentPage) {
                ForEach(spreads.indices, id: \.self) { index in
                    let spread = spreads[index]
                    WalletSpreadView2(
                        leftDisc: spread.first?.disc,
                        rightDisc: spread.count > 1 ? spread[1].disc : nil,
                        onDiscTapped: { disc in
                            Task {
                                let success = await playerViewModel.playDisc(disc)
                                if success {
                                    showingPlayer = true
                                }
                            }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            LandscapePlayerView()
                .environmentObject(playerViewModel)
        }
        .alert("CD Wallet Limit", isPresented: $showingLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your CDs playlist has \(discs.count + walletViewModel.state.hiddenCount) albums. Only the first \(discs.count) are shown.")
        }
        .onAppear {
            checkForLimitAlert()
        }
        .onChange(of: walletViewModel.state) { _, _ in
            checkForLimitAlert()
        }
    }

    private func checkForLimitAlert() {
        if walletViewModel.state.hasMoreAlbums && !hasShownLimitAlert {
            hasShownLimitAlert = true
            showingLimitAlert = true
        }
    }
}

#Preview {
    CDWalletView()
        .environmentObject(WalletViewModel())
        .environmentObject(PlayerViewModel())
}
