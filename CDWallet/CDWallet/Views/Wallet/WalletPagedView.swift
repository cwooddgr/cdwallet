import SwiftUI
import CDWalletCore

struct WalletPagedView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var showingDiagnostics = false
    @State private var showingNowPlaying = false

    var discs: [Disc] {
        if case .ready(let discs) = walletViewModel.state {
            return discs
        }
        return []
    }

    var body: some View {
        NavigationStack {
            TabView {
                ForEach(Array(pagedDiscs.enumerated()), id: \.offset) { index, page in
                    DiscSpreadView(discs: page)
                        .environmentObject(playerViewModel)
                        .onTapGesture {
                            // Tap handling is in DiscSpreadView
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle("My CDs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await walletViewModel.refresh()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("Diagnostics", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView()
            }
            .sheet(isPresented: $showingNowPlaying) {
                NowPlayingView()
            }
            .onChange(of: playerViewModel.currentAlbum) { oldValue, newValue in
                showingNowPlaying = newValue != nil
            }
        }
    }

    /// Group discs into pages based on device
    private var pagedDiscs: [[Disc]] {
        let discsPerPage: Int

        // iPhone: 2 discs per page
        // iPad: 6 discs per page (3x2 grid)
        if UIDevice.current.userInterfaceIdiom == .pad {
            discsPerPage = 6 // 3x2 grid
        } else {
            discsPerPage = 2
        }

        return discs.chunked(into: discsPerPage)
    }
}

#Preview {
    WalletPagedView()
        .environmentObject(WalletViewModel())
        .environmentObject(PlayerViewModel())
}
