//
//  CDWalletApp.swift
//  CDWallet
//
//  Created by Charlie Wood on 12/21/25.
//

import SwiftUI
import CDWalletCore

@main
struct CDWalletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var walletViewModel = WalletViewModel()
    @StateObject private var playerViewModel = PlayerViewModel()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletViewModel)
                .environmentObject(playerViewModel)
                .task {
                    await walletViewModel.initialize()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Check for playlist changes when returning from background
                    if oldPhase == .background && newPhase == .active {
                        Task {
                            await walletViewModel.refreshIfNeeded()
                        }
                    }
                }
        }
    }
}
