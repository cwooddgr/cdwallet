# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CD Wally is a universal iOS/iPadOS app that recreates the experience of browsing a Case Logic CD wallet for Apple Music. The app uses a user's "CDs" playlist as an album picker and defaults to full-album listening.

**Tech Stack**: Swift, SwiftUI, MusicKit, Swift Concurrency (async/await), MVVM architecture

**Deployment Target**: iOS 18.0+ / iPadOS 18.0+

## Development Status

**Current State**: Fully implemented through Post-First Light milestone. The app is functional and ready to use with iOS 18+, Apple Music subscription, and a "CDs" playlist.

**Implementation Complete**:
- ✅ MusicKit authorization and library access (deferred player initialization for proper auth flow)
- ✅ Playlist discovery with deterministic collision handling
- ✅ Album resolution via title/artist search with fuzzy matching
- ✅ Library-to-catalog fallback (albums not in user's library still appear via catalog search)
- ✅ Compound artist search with fallback strategies ("Dr. Dre & Snoop Dogg" → tries primary artist)
- ✅ Edition deduplication (merges "Deluxe Edition", "Remastered", etc. with base album)
- ✅ Album limit (20 max) with one-time notification dialog
- ✅ Landscape-only wallet UI with circular CD discs (2 per page spread)
- ✅ Full album playback from Apple Music catalog
- ✅ Player view with album art, track listing, and playback controls
- ✅ CD player-style display (track number + elapsed time with green LCD styling)
- ✅ Refresh on app launch with catalog availability verification
- ✅ Disk caching for artwork and disc list (fast startup)
- ✅ Unavailable album filtering (albums not on Apple Music hidden)
- ✅ Sorting by artist → release date → albumID with article stripping
- ✅ Release date enrichment from Apple Music catalog (with copyright year fallback)
- ✅ 3D page flip animation with drag gesture support
- ✅ Player pause/resume (closing player pauses; tapping same CD resumes)
- ✅ Auto-refresh on return from background with smart fingerprinting
- ✅ Unit tests for sorting and playlist selection logic
- ✅ Skeuomorphic UI redesign:
  - Background image with wallet scaled to 90%
  - Realistic CD disc rendering with concentric regions (center hole, artwork, clamp ring, outer rim)
  - Woven sleeve texture simulating 90s CD wallet plastic
  - Artwork preloading for smoother disc display
  - Drag dead zone (15% from binding) to prevent accidental page flips

**Known Limitations**:
- iOS 18.0+ required (uses iOS 18 MusicKit APIs)
- Playlist modification timestamps not exposed by MusicKit (uses item count heuristic)
- Physical device required for testing (MusicKit not available in simulator)

## Development Commands

**Project location**: `CDWallet/CDWallet.xcodeproj`
**Core package**: `CDWalletCore/CDWalletCore/Package.swift`

- Build: Cmd+B in Xcode or `xcodebuild -project CDWallet/CDWallet.xcodeproj -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Run tests: Cmd+U in Xcode or `xcodebuild test -project CDWallet/CDWallet.xcodeproj -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 17'`
- Run single test: Right-click test method in Xcode or use `-only-testing:CDWalletCoreTests/TestClassName/testMethodName`

**Note**: MusicKit requires a physical device with Apple Music subscription. Simulator testing limited to UI/logic tests only.

## Project Structure

**Single universal app target** (iPhone + iPad in one target)

**CDWalletCore module** (Swift package):
- Models: `Disc`, `AlbumResolution`, `WalletState`, `PlaylistSelection`, `DiagnosticsSnapshot`
- ViewModels: `WalletViewModel`, `PlayerViewModel`, `DiagnosticsViewModel`
- Services: `AuthorizationService`, `PlaylistService`, `AlbumService`, `ArtworkCache`, `PlayerController`

**UI Views** (CDWallet app target):
- Wallet: `CDWalletView`, `CDWalletBinderView`, `BinderPageView`, `CDDiscSkeuomorphicView`, `WovenSleeveView`
- Player: `LandscapePlayerView`
- Support: `AppDelegate` (forces landscape orientation)

**UI Layout Strategy**: Landscape-only orientation. Uses SwiftUI with skeuomorphic CD disc visuals (realistic concentric regions with center hole, clamp ring, outer rim) and 3D page flip navigation.

## Core Architecture & Data Flow

### The Album Completion Rule (Critical)
- The "CDs" playlist is an **album picker**, not a playback source
- Any track in the playlist implies "include that track's entire album"
- Playback always queues the **full resolved album** in canonical order, even if only one track from that album is in the playlist
- Never play playlist tracks directly; always resolve to the full album first

### Data Flow (Authoritative)
1. **Authorization**: Check MusicKit authorization → show auth screen if needed
2. **Playlist Discovery**:
   - Find playlist(s) named "CDs" (case-insensitive)
   - If multiple exist: select based on largest item count, or stable ID ordering as fallback
   - Record selection decision for Diagnostics
3. **Album Resolution** (iOS 18 Title/Artist Search):
   - Fetch playlist items → extract (title, artist) pairs → dedupe
   - Search library for albums via `AlbumService.searchAlbums(albumInfo:)`
   - Apply fuzzy matching: normalize titles (e.g., "Rumours"↔"Rumors"), strip edition suffixes
   - Build `Disc` list from matched library albums
   - For playback: search catalog via `searchCatalogAlbumForPlayback(title:artist:)` to ensure complete album
   - Handle unavailable albums gracefully (show in diagnostics, omit from wallet)
4. **Sorting**: Build `Disc` list with sort keys:
   - Primary: `artistSortKey` (lowercase, trimmed, strip leading "the"/"a"/"an" for sorting only)
   - Secondary: `releaseDate` (ascending; albums without dates sort last)
   - Tie-break: `albumID`
5. **UI**: Render sorted discs → tap plays full album via `ApplicationMusicPlayer.shared`

### Multi-disc Albums
Treat as a **single disc** in the wallet. Playback queues the full album in canonical order (including disc numbers).

### Playlist Name Collision Rule
If multiple "CDs" playlists exist:
1. Prefer largest item count (primary heuristic)
2. Else stable ordering by playlist ID

*(Note: MusicKit iOS 18 Playlist doesn't expose modification timestamps)*

Always record selection reason in Diagnostics.

### Album Resolution Strategy (iOS 18 Two-Phase Approach)

The app uses a two-phase resolution strategy to handle iOS 18 MusicKit library/catalog separation:

**Phase 1: Library Search (for wallet display)**
1. Extract `(title, artist)` pairs from playlist tracks
2. Search user's library via `MusicLibraryRequest<Album>`
3. Apply fuzzy matching with `normalizeAlbumTitle()`:
   - Spelling variations: "Rumours" ↔ "Rumors"
   - Strip edition suffixes: "(Deluxe Edition)", "(Remastered)", "(Bonus Track Version)", etc.
4. Build `Disc` objects from matched library albums

**Phase 2: Catalog Search (for playback)**
1. When user taps a disc, search full Apple Music catalog via `MusicCatalogSearchRequest`
2. Find exact match using normalized title/artist
3. Load complete album with `.with([.tracks])`
4. Queue full album in `ApplicationMusicPlayer.shared` (ensures all tracks, not just library tracks)

**Why Two Phases?**
- Library album IDs differ from catalog album IDs in iOS 18
- Library albums may have incomplete track listings
- Catalog albums guarantee complete, authoritative track lists
- Display uses library (faster, user's collection metadata)
- Playback uses catalog (complete albums in canonical order)

## Core Services

### AuthorizationService
- `func ensureAuthorized() async -> Bool`
- Manages MusicKit authorization state

### PlaylistService
- `func locateCDsPlaylist() async throws -> PlaylistSelection`
- `func fetchPlaylistItems(playlistID:) async throws -> [Track]`
- `func fetchPlaylistFingerprint(playlistID:) async throws -> Set<String>` — lightweight check for change detection
- `func extractAlbumInfo(from: [Track]) -> [(title: String, artist: String)]` — primary method
- `func extractAlbumIDs(from: [Track]) -> [String]` — legacy, unused
- Implements name collision resolution
- **Edition deduplication**: Normalizes album titles when deduplicating to merge editions (e.g., "21st Century Breakdown" and "21st Century Breakdown (Deluxe Edition)" are treated as the same album). First occurrence in playlist order is kept.

### AlbumService
- `func searchAlbums(albumInfo: [(title: String, artist: String)]) async -> [AlbumResolution]` — searches library, falls back to catalog if not found
- `func searchCatalogAlbumForPlayback(title: String, artist: String) async -> AlbumResolution` — searches catalog for complete album
- `func resolveCatalogAlbum(title: String, artist: String) async -> AlbumResolution` — alternative catalog search
- `func enrichWithReleaseDates(_ resolutions: [AlbumResolution]) async -> [AlbumResolution]` — fetches missing release dates from catalog
- Uses TaskGroup for concurrent searches (max 10 concurrent requests for rate limiting)
- **Library-to-catalog fallback**: When library search fails to find an album, automatically tries catalog search. This allows albums that exist in Apple Music but not in the user's library to appear in the wallet.
- **Compound artist fallback**: When catalog search fails, tries progressively simpler search terms:
  1. Full artist + title (e.g., "Dr. Dre & Snoop Dogg Still D.R.E.")
  2. Primary artist + title (e.g., "Dr. Dre Still D.R.E." — strips " & ", " and ", " feat. ", " featuring ", " with ", ", ")
  3. Just title as last resort
- Fuzzy matching via `normalizeAlbumTitle()`, `titlesMatch()`, and `artistsMatch()`:
  - Strips trailing parenthetical content: `(Deluxe Edition)`, `(20th Anniversary Remaster)`, etc.
  - Strips trailing bracketed content: `[Bonus Tracks]`, etc.
  - Removes punctuation variations: commas, ellipses, quotes
  - Handles subtitles: matches if one title is prefix of another or base titles match before `:`
  - Spelling variations: `Rumours` ↔ `Rumors`
  - Artist matching: flexible match instead of exact (handles variations in artist naming)
- Cache resolved album metadata in-memory (keyed by title|artist)
- **Release date enrichment**: For albums missing library release dates, searches catalog and parses copyright year (e.g., "℗ 1983 Warner Records" → 1983) as fallback

### ArtworkCache
- Two-tier cache: in-memory NSCache (50 item limit) + disk cache (`Caches/ArtworkCache/*.jpg`)
- Keyed by `albumID+size` (uses fixed 600x600 size for consistency between preload and display)
- Falls back to catalog search when library artwork unavailable
- Cleanup removes cached artwork for albums no longer in wallet

### DiscCache
- Disk cache for disc list (`Caches/disc_cache.json`)
- Enables instant wallet display on app launch
- Refresh updates cache after verifying catalog availability

### UnavailableAlbumsCache
- Tracks albums not found in Apple Music catalog (`Caches/unavailable_albums.json`)
- Keyed by `artist|title` (lowercase)
- Prevents showing unavailable albums in wallet

### PlaylistFingerprintCache
- Stores fingerprint of playlist (set of track IDs) for change detection
- On return from background, compares current playlist to cached fingerprint
- Only triggers full refresh if playlist actually changed
- Avoids unnecessary API calls when user switches apps without modifying playlist

### PlayerController
- Uses `ApplicationMusicPlayer.shared` (app-controlled queue)
- **Deferred initialization**: Player and observers are initialized lazily on first play to avoid accessing `ApplicationMusicPlayer.shared` before MusicKit authorization completes
- `func playAlbum(_ album: Album, startTrackID: MusicItemID?) async throws`
- `func pause()` / `func resume() async` — pause/resume current playback
- Always queues the resolved Album object (full tracks in canonical order), never playlist tracks
- Tracks current playback state: `currentAlbum`, `currentTrack`, `isPlaying`, `playbackTime`
- Uses timer-based polling (0.5s) to update playback time and match current track by title

### PlayerViewModel
- Wraps `PlayerController` for SwiftUI views
- Tracks `currentDiscID: String?` to identify which disc is loaded
- `isDiscLoaded(_ disc: Disc) -> Bool` — check if a disc is already loaded (for resume behavior)
- Closing player pauses playback; tapping the same disc resumes from where it left off

### WalletViewModel
- Orchestrates wallet state and refresh logic
- `initialize()` — initial load with cached data, then background refresh
- `refresh()` — full refresh from Apple Music
- `refreshIfNeeded()` — smart refresh using fingerprint comparison
- `isRefreshing: Bool` — published state for showing "Updating..." indicator
- On return from background: checks fingerprint first, only full refresh if changed

## States & Error Handling

### WalletState enum
- `needsAuthorization`
- `loading`
- `ready(discs: [Disc], totalCount: Int)` — totalCount includes albums beyond the limit
- `empty(reason)` — playlist missing or zero resolved albums
- `error(userFacingError)`

**Album limit**: `maxWalletAlbums = 20` limits the wallet to 20 albums. Computed properties:
- `hasMoreAlbums: Bool` — true if totalCount > discs.count
- `hiddenCount: Int` — number of albums not shown

A one-time modal dialog notifies the user when their playlist exceeds the limit.

### Error Handling Philosophy
- Never crash on missing metadata
- Surface partial failures in Diagnostics screen
- Show clear states: not authorized / playlist missing / some unavailable

## Swift Concurrency Patterns

### Sendable Conformance
When using `TaskGroup` or passing objects across actor/task boundaries, Swift requires `Sendable` conformance.

**Pattern for value types with MusicKit types:**
MusicKit types like `Artwork` and `MusicItemID` may not formally conform to `Sendable`, but are safe in practice. Mark structs containing these as `@unchecked Sendable`:

```swift
public struct Disc: Identifiable, Hashable, @unchecked Sendable {
    public let artwork: Artwork?  // MusicKit type, safe but not formally Sendable
    public let albumID: MusicItemID
    // ...
}
```

**Pattern for cache classes:**
Use `final class` with `Sendable` conformance and thread-safe storage:

```swift
public final class DiscCache: Sendable {
    private let cacheURL: URL  // Immutable after init
    // File I/O is thread-safe
}
```

**When to use `@unchecked Sendable`:**
- Immutable structs containing MusicKit types
- Classes with immutable state or thread-safe operations (FileManager, UserDefaults)
- Never for classes with mutable shared state

## Implementation Milestones

### First Light (MVP) ✅ COMPLETE
1. ✅ Authorization screen + `NSAppleMusicUsageDescription` in Info.plist
2. ✅ Locate "CDs" playlist (handles missing/duplicate cases with deterministic selection)
3. ✅ Extract album info → search library → resolve albums → build disc list
4. ✅ Tap disc → Now Playing → play full catalog album
5. ✅ Diagnostics screen showing: auth status, playlist selection decision, resolution stats

### Post-First Light ✅ COMPLETE
1. ✅ Sorting and stable ordering (artist → release date → albumID with article stripping)
2. ✅ Manual refresh + caching (in-memory artwork + metadata)
3. ✅ Landscape-only wallet UI with CD discs (2 per spread)
4. ✅ 3D page flip animation with drag gesture (flip threshold at 45°, perspective -1/10)
5. ✅ Player view with:
   - Album artwork display (left side)
   - Track listing with numbers and current track highlighting (right side)
   - CD player-style display (track number + elapsed time, green LCD styling)
   - Playback controls (previous/play-pause/next)
   - Pause on close, resume when tapping same disc
6. ✅ Auto-refresh on return from background with smart fingerprinting

### Skeuomorphic UI ✅ COMPLETE
1. ✅ Background image with scaled wallet (90% scale for visual breathing room)
2. ✅ Realistic CD disc rendering (`CDDiscSkeuomorphicView`):
   - Center hole (0-0.125R): Transparent, shows sleeve through
   - Album artwork (0.125R-0.98R): Album art with clamp ring masked out
   - Clamp ring (0.265R-0.275R): Clear plastic with gradient highlight
   - Outer rim (0.98R-1.0R): Clear plastic edge
3. ✅ Woven sleeve texture (`WovenSleeveView`): Cross-hatch pattern simulating 90s CD wallet plastic
4. ✅ Artwork preloading: Async loading with placeholder during fetch
5. ✅ Drag dead zone: 15% of page width from binding prevents accidental flips

### Deferred (Post-MVP)
- Disc pull-out gestures
- Playlist switching UI for name collisions
- Search/filtering, haptics

## Required Xcode Configuration

- **Capability**: Enable MusicKit in Signing & Capabilities
- **Info.plist**: Add `NSAppleMusicUsageDescription` with explanation for library access
- **Device Families**: iPhone + iPad (universal target)

## Testing Strategy

### Unit Tests (CDWalletCore)
- Sort key generation (including article stripping: "The Beatles" → "beatles, the")
- Stable sorting by artist → release date → albumID
- Album info deduplication (title/artist pairs with order preservation)
- Edition deduplication (merges "Album (Deluxe Edition)" with "Album")
- Album title fuzzy matching (spelling variations, edition suffix stripping)
- Playlist selection heuristic when multiple "CDs" playlists exist
- Missing album metadata handling

### Manual Test Cases
- Playlist missing → shows empty state with instructions
- Multiple playlists named "CDs" → deterministic selection
- Playlist with partial albums → plays full albums
- Album unavailable → handles gracefully
- iPad layout → not stretched phone UI

## Key Product Rules

1. **Album completion is mandatory**: Always play the full album, even if only one track is in the playlist
2. **Disc identity**: Use album ID for display; editions are merged during deduplication (e.g., "Deluxe Edition" and standard are treated as one album, first occurrence kept)
3. **Sorting**: Primary by artist (ignore leading articles), secondary by release date ascending, tie-break by album ID
4. **MVP-first approach**: Validate MusicKit access + full-album playback before building nostalgic animations
5. **Deterministic behavior**: Same playlist state → same disc order → same selection
6. **Album limit**: Wallet displays max 20 albums; one-time dialog notifies user if playlist exceeds limit
