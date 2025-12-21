import Foundation
import Combine

/// View model for diagnostics screen
@MainActor
public class DiagnosticsViewModel: ObservableObject {
    @Published public private(set) var snapshot: DiagnosticsSnapshot?

    private var cancellables = Set<AnyCancellable>()

    public init(walletViewModel: WalletViewModel) {
        // Subscribe to wallet diagnostics
        walletViewModel.$diagnostics
            .assign(to: &$snapshot)
    }
}
