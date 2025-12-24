//
//  ContentView.swift
//  CDWallet
//
//  Created by Charlie Wood on 12/21/25.
//

import SwiftUI
import CDWalletCore

struct ContentView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel

    var body: some View {
        switch walletViewModel.state {
        case .needsAuthorization:
            AuthorizationView()
        case .loading:
            ProgressView("Loading your CDs...")
        case .ready:
            CDWalletView()
        case .empty(let reason):
            EmptyStateView(reason: reason)
        case .error(let message):
            ErrorView(message: message)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletViewModel())
        .environmentObject(PlayerViewModel())
}
