# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CD Wallet is a universal iOS/iPadOS app that recreates the experience of browsing a Case Logic CD wallet for Apple Music. The app uses a user's "CDs" playlist as an album picker and defaults to full-album listening.

**Tech Stack**: Swift, SwiftUI, MusicKit, Swift Concurrency (async/await), MVVM architecture

**Deployment Target**: iOS 18.0+ / iPadOS 18.0+

## Development Status

**Current State**: Fully implemented through Post-First Light milestone. The app is functional and ready to use with iOS 18+, Apple Music subscription, and a "CDs" playlist.

**Implementation Complete**:
- ✅ MusicKit authorization and library access
- ✅ Playlist discovery with deterministic collision handling
- ✅ Album resolution via title/artist search with fuzzy matching
- ✅ Landscape-only wallet UI with circular CD discs (2 per page spread)
- ✅ Full album playback from Apple Music catalog
- ✅ Player view with album art, track listing, and playback controls
- ✅ CD player-style display (track number + elapsed time with green LCD styling)
- ✅ Manual refresh and comprehensive diagnostics
- ✅ Sorting by artist → album → albumID with article stripping
- ✅ Unit tests for sorting and playlist selection logic

**Known Limitations**:
- iOS 18.0+ required (uses iOS 18 MusicKit APIs)
- Playlist modification timestamps not exposed by MusicKit (uses item count heuristic)
- In-memory artwork cache only (cleared on app restart)
- Physical device required for testing (MusicKit not available in simulator)

## Development Commands

**Project location**: `CDWallet/CDWallet.xcodeproj`
**Core package**: `CDWalletCore/CDWalletCore/Package.swift`

- Build: Cmd+B in Xcode or `xcodebuild -project CDWallet/CDWallet.xcodeproj -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Run tests: Cmd+U in Xcode or `xcodebuild test -project CDWallet/CDWallet.xcodeproj -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 16'`
- Run single test: Right-click test method in Xcode or use `-only-testing:CDWalletCoreTests/TestClassName/testMethodName`

**Note**: MusicKit requires a physical device with Apple Music subscription. Simulator testing limited to UI/logic tests only.

## Project Structure

**Single universal app target** (iPhone + iPad in one target)

**CDWalletCore module** (Swift package):
- Models: `Disc`, `AlbumResolution`, `WalletState`, `PlaylistSelection`, `DiagnosticsSnapshot`
- ViewModels: `WalletViewModel`, `PlayerViewModel`, `DiagnosticsViewModel`
- Services: `AuthorizationService`, `PlaylistService`, `AlbumService`, `ArtworkCache`, `PlayerController`

**UI Views** (CDWallet app target):
- Wallet: `CDWalletView`, `WalletSpreadView2`, `CDDiscView`
- Player: `LandscapePlayerView`
- Support: `AppDelegate` (forces landscape orientation)

**UI Layout Strategy**: Landscape-only orientation. Uses SwiftUI with circular CD disc visuals and paged spread navigation.

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
   - Secondary: `albumSortKey` (lowercase, trimmed)
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
- `func extractAlbumInfo(from: [Track]) -> [(title: String, artist: String)]` — primary method
- `func extractAlbumIDs(from: [Track]) -> [String]` — legacy, unused
- Implements name collision resolution

### AlbumService
- `func searchAlbums(albumInfo: [(title: String, artist: String)]) async -> [AlbumResolution]` — searches library
- `func searchCatalogAlbumForPlayback(title: String, artist: String) async -> AlbumResolution` — searches catalog for complete album
- `func resolveCatalogAlbum(title: String, artist: String) async -> AlbumResolution` — alternative catalog search
- Uses TaskGroup for concurrent searches (max ~6 concurrent requests)
- Fuzzy matching via `normalizeAlbumTitle()` and `titlesMatch()`:
  - Strips trailing parenthetical content: `(Deluxe Edition)`, `(20th Anniversary Remaster)`, etc.
  - Strips trailing bracketed content: `[Bonus Tracks]`, etc.
  - Removes punctuation variations: commas, ellipses, quotes
  - Handles subtitles: matches if one title is prefix of another or base titles match before `:`
  - Spelling variations: `Rumours` ↔ `Rumors`
- Cache resolved album metadata in-memory (keyed by title|artist)

### ArtworkCache
- In-memory NSCache keyed by `albumID+size` (50 item limit)
- Falls back to catalog search when library artwork unavailable
- No disk cache

### PlayerController
- Uses `ApplicationMusicPlayer.shared` (app-controlled queue)
- `func playAlbum(_ album: Album, startTrackID: MusicItemID?) async throws`
- Always queues the resolved Album object (full tracks in canonical order), never playlist tracks
- Tracks current playback state: `currentAlbum`, `currentTrack`, `isPlaying`, `playbackTime`
- Uses timer-based polling (0.5s) to update playback time and match current track by title

## States & Error Handling

### WalletState enum
- `needsAuthorization`
- `loading`
- `ready(discs)`
- `empty(reason)` — playlist missing or zero resolved albums
- `error(userFacingError)`

### Error Handling Philosophy
- Never crash on missing metadata
- Surface partial failures in Diagnostics screen
- Show clear states: not authorized / playlist missing / some unavailable

## Implementation Milestones

### First Light (MVP) ✅ COMPLETE
1. ✅ Authorization screen + `NSAppleMusicUsageDescription` in Info.plist
2. ✅ Locate "CDs" playlist (handles missing/duplicate cases with deterministic selection)
3. ✅ Extract album info → search library → resolve albums → build disc list
4. ✅ Tap disc → Now Playing → play full catalog album
5. ✅ Diagnostics screen showing: auth status, playlist selection decision, resolution stats

### Post-First Light ✅ COMPLETE
1. ✅ Sorting and stable ordering (artist → album → albumID with article stripping)
2. ✅ Manual refresh + caching (in-memory artwork + metadata)
3. ✅ Landscape-only wallet UI with circular CD discs (2 per spread)
4. ✅ Player view with:
   - Album artwork display (left side)
   - Track listing with numbers and current track highlighting (right side)
   - CD player-style display (track number + elapsed time, green LCD styling)
   - Playback controls (previous/play-pause/next)

### Deferred (Post-MVP)
- Page flip animation, disc pull-out gestures
- Playlist switching UI for name collisions
- Search/filtering, haptics, CD case textures
- Disk-based artwork cache

## Required Xcode Configuration

- **Capability**: Enable MusicKit in Signing & Capabilities
- **Info.plist**: Add `NSAppleMusicUsageDescription` with explanation for library access
- **Device Families**: iPhone + iPad (universal target)

## Testing Strategy

### Unit Tests (CDWalletCore)
- Sort key generation (including article stripping: "The Beatles" → "beatles, the")
- Stable sorting by artist → album → albumID
- Album info deduplication (title/artist pairs with order preservation)
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
2. **Disc identity**: Use album ID; do not merge deluxe/standard/clean/explicit variants
3. **Sorting**: Ignore leading articles ("The", "A", "An") in artist sort key only; display unchanged
4. **MVP-first approach**: Validate MusicKit access + full-album playback before building nostalgic animations
5. **Deterministic behavior**: Same playlist state → same disc order → same selection
