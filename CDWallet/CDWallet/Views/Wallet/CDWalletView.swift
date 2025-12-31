import SwiftUI
import CDWalletCore

/// CD Wallet view - shows discs like a physical CD binder
struct CDWalletView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var showingPlayer = false
    @State private var showingLimitAlert = false
    @State private var hasShownLimitAlert = false

    var discs: [Disc] {
        if case .ready(let discs, _) = walletViewModel.state {
            return discs
        }
        return []
    }

    var body: some View {
        CDWalletBinderView(discs: discs) { disc in
            Task {
                let success = await playerViewModel.playDisc(disc)
                if success {
                    showingPlayer = true
                }
            }
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
