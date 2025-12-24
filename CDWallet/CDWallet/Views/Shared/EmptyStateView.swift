import SwiftUI
import CDWalletCore

struct EmptyStateView: View {
    let reason: WalletState.EmptyReason
    @EnvironmentObject var walletViewModel: WalletViewModel

    var body: some View {
        ZStack {
            Color(white: 0.1).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundColor(.gray)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                Button {
                    Task {
                        await walletViewModel.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }

    private var iconName: String {
        switch reason {
        case .noPlaylist: return "music.note.list"
        case .playlistEmpty: return "tray"
        case .noAlbumsResolved: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch reason {
        case .noPlaylist: return "No CDs Playlist Found"
        case .playlistEmpty: return "CDs Playlist is Empty"
        case .noAlbumsResolved: return "No Albums Available"
        }
    }

    private var message: String {
        switch reason {
        case .noPlaylist:
            return "Create a playlist named 'CDs' in Apple Music and add one track from each album you want in your wallet."
        case .playlistEmpty:
            return "Add tracks to your 'CDs' playlist in Apple Music. Each track adds its full album to your wallet."
        case .noAlbumsResolved:
            return "None of the albums from your 'CDs' playlist could be loaded. Check your connection and try again."
        }
    }
}

struct ErrorView: View {
    let message: String
    @EnvironmentObject var walletViewModel: WalletViewModel

    var body: some View {
        ZStack {
            Color(white: 0.1).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("Something Went Wrong")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                Button {
                    Task {
                        await walletViewModel.refresh()
                    }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

#Preview("No Playlist") {
    EmptyStateView(reason: .noPlaylist)
        .environmentObject(WalletViewModel())
}

#Preview("Error") {
    ErrorView(message: "Failed to load playlists")
        .environmentObject(WalletViewModel())
}
