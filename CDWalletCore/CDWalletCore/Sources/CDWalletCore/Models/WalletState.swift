import Foundation

/// Represents the current state of the wallet
public enum WalletState: Equatable {
    case needsAuthorization
    case loading
    case ready(discs: [Disc])
    case empty(reason: EmptyReason)
    case error(message: String)

    public enum EmptyReason: Equatable {
        case noPlaylist
        case playlistEmpty
        case noAlbumsResolved
    }
}
