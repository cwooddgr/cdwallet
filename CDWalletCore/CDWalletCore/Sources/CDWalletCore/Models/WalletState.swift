import Foundation

/// Maximum number of albums to display in the wallet
public let maxWalletAlbums = 20

/// Represents the current state of the wallet
public enum WalletState: Equatable {
    case needsAuthorization
    case loading
    case ready(discs: [Disc], totalCount: Int)  // totalCount includes albums beyond the limit
    case empty(reason: EmptyReason)
    case error(message: String)

    public enum EmptyReason: Equatable {
        case noPlaylist
        case playlistEmpty
        case noAlbumsResolved
    }

    /// Convenience to check if there are more albums than shown
    public var hasMoreAlbums: Bool {
        if case .ready(let discs, let total) = self {
            return total > discs.count
        }
        return false
    }

    /// Number of albums not shown
    public var hiddenCount: Int {
        if case .ready(let discs, let total) = self {
            return max(0, total - discs.count)
        }
        return 0
    }
}
