import SwiftUI
import CDWalletCore

/// CD Wallet view - shows discs like a physical CD binder
struct CDWalletView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var currentPage = 0
    @State private var showingDiagnostics = false
    @State private var showingPlayer = false

    var discs: [Disc] {
        if case .ready(let discs) = walletViewModel.state {
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
            Color.black
                .ignoresSafeArea()

            VStack {
                // Title bar
                HStack {
                    Text("My CDs")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()

                    Menu {
                        Button {
                            Task { await walletViewModel.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("Diagnostics", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding()

                // CD spreads with paging
                TabView(selection: $currentPage) {
                    ForEach(spreads.indices, id: \.self) { index in
                        let spread = spreads[index]
                        WalletSpreadView2(
                            leftDisc: spread.first?.disc,
                            rightDisc: spread.count > 1 ? spread[1].disc : nil,
                            onDiscTapped: { disc in
                                Task {
                                    await playerViewModel.playDisc(disc)
                                    showingPlayer = true
                                }
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            LandscapePlayerView()
                .environmentObject(playerViewModel)
        }
    }
}

#Preview {
    CDWalletView()
        .environmentObject(WalletViewModel())
        .environmentObject(PlayerViewModel())
}
