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
    @State private var wasInBackground = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(walletViewModel)
                .environmentObject(playerViewModel)
                .task {
                    await walletViewModel.initialize()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Track when we enter background
                    if newPhase == .background {
                        wasInBackground = true
                    }
                    // Check for playlist changes when becoming active after being in background
                    if newPhase == .active && wasInBackground {
                        wasInBackground = false
                        Task {
                            await walletViewModel.refreshIfNeeded()
                        }
                    }
                }
        }
    }
}
