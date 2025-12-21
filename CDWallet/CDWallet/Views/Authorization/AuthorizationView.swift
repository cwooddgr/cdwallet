import SwiftUI
import CDWalletCore

struct AuthorizationView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Welcome to CD Wallet")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("CD Wallet needs access to your Apple Music library to find your CDs playlist and play your albums.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button {
                Task {
                    await walletViewModel.requestAuthorization()
                }
            } label: {
                Text("Allow Access to Apple Music")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    AuthorizationView()
        .environmentObject(WalletViewModel())
}
