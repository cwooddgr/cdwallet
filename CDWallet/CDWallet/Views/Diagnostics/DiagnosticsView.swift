import SwiftUI
import CDWalletCore
import MusicKit

struct DiagnosticsView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @Environment(\.dismiss) var dismiss

    var snapshot: DiagnosticsSnapshot? {
        walletViewModel.diagnostics
    }

    var body: some View {
        NavigationStack {
            List {
                // Authorization
                Section("Authorization") {
                    InfoRow(label: "Status", value: authStatusString)
                }

                // Playlist Selection
                if let playlistInfo = snapshot?.playlistSelectionInfo {
                    Section("Playlist Selection") {
                        InfoRow(label: "Total 'CDs' playlists found", value: "\(playlistInfo.totalCandidates)")
                        InfoRow(label: "Selected playlist", value: playlistInfo.selectedPlaylistName)
                        InfoRow(label: "Selection reason", value: selectionReasonString(playlistInfo.selectionReason))
                        InfoRow(label: "Item count", value: "\(playlistInfo.itemCount)")
                    }
                }

                // Resolution Stats
                if let stats = snapshot?.resolutionStats {
                    Section("Resolution") {
                        InfoRow(label: "Playlist items scanned", value: "\(stats.playlistItemsScanned)")
                        InfoRow(label: "Album IDs extracted", value: "\(stats.albumIDsExtracted)")
                        InfoRow(label: "Unique albums", value: "\(stats.uniqueAlbumIDs)")
                        InfoRow(label: "Resolved albums", value: "\(stats.resolvedAlbums)")
                        InfoRow(label: "Unavailable albums", value: "\(stats.unavailableAlbums)")
                    }
                }

                // Last Refresh
                Section("Refresh") {
                    if let lastRefresh = snapshot?.lastRefreshTime {
                        InfoRow(label: "Last refresh", value: formatDate(lastRefresh))
                    } else {
                        InfoRow(label: "Last refresh", value: "Never")
                    }
                }

                // Errors
                if let error = snapshot?.lastError {
                    Section("Last Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var authStatusString: String {
        guard let status = snapshot?.authorizationStatus else { return "Unknown" }
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func selectionReasonString(_ reason: PlaylistSelection.SelectionReason) -> String {
        switch reason {
        case .onlyOne: return "Only one playlist found"
        case .mostRecentlyModified: return "Most recently modified"
        case .largestItemCount: return "Largest item count"
        case .firstStable: return "First in stable ordering"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(WalletViewModel())
}
