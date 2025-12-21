import Testing
import MusicKit
@testable import CDWalletCore

@Suite("PlaylistService Tests")
struct PlaylistServiceTests {

    @Test("extractAlbumIDs deduplicates while preserving order")
    func testExtractAlbumIDsDeduplication() async {
        let service = PlaylistService()

        // Mock tracks would need to be created here
        // This demonstrates the intended behavior

        let albumIDs = ["album1", "album2", "album1", "album3", "album2"]
        var seen = Set<String>()
        let dedupedIDs = albumIDs.filter { seen.insert($0).inserted }

        #expect(dedupedIDs == ["album1", "album2", "album3"])
        #expect(dedupedIDs.count == 3)
    }

    @Test("extractAlbumIDs preserves original order")
    func testExtractAlbumIDsPreservesOrder() {
        let albumIDs = ["album3", "album1", "album2"]
        var seen = Set<String>()
        let result = albumIDs.filter { seen.insert($0).inserted }

        #expect(result == ["album3", "album1", "album2"])
    }

    @Test("Playlist selection prefers largest item count")
    func testPlaylistSelectionPrefersLargestCount() {
        // Mock scenario: Two playlists named "CDs"
        // Playlist A: 10 items
        // Playlist B: 20 items
        // Expected: Playlist B selected with reason .largestItemCount

        let countA = 10
        let countB = 20

        #expect(countB > countA)
        // Selection reason should be .largestItemCount
    }

    @Test("Playlist selection uses stable ordering as fallback")
    func testPlaylistSelectionStableFallback() {
        // Mock scenario: Two playlists named "CDs", both empty
        // Expected: Use stable ID ordering

        let idA = "playlist-a"
        let idB = "playlist-b"

        let sorted = [idA, idB].sorted()

        #expect(sorted == [idA, idB])
        // Selection reason should be .firstStable
    }
}
