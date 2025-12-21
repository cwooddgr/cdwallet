# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CD Wallet is a universal iOS/iPadOS app that recreates the experience of browsing a Case Logic CD wallet for Apple Music. The app uses a user's "CDs" playlist as an album picker and defaults to full-album listening.

**Tech Stack**: Swift, SwiftUI, MusicKit, Swift Concurrency (async/await), MVVM architecture

**Deployment Target**: Latest supported iOS and iPadOS major versions only

## Development Commands

This project has not yet been initialized. When the Xcode project is created, typical commands will be:
- Build: Cmd+B in Xcode or `xcodebuild -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Run tests: Cmd+U in Xcode or `xcodebuild test -scheme CDWallet -destination 'platform=iOS Simulator,name=iPhone 15'`
- Run single test: Right-click test method in Xcode or use `-only-testing:CDWalletCoreTests/TestClassName/testMethodName`

## Project Structure

**Single universal app target** (iPhone + iPad in one target)

**CDWalletCore module** (internal framework or Swift package):
- Models: `Disc`, `DiscResolutionResult`, `WalletState`
- ViewModels: `WalletViewModel`, `PlayerViewModel`, `DiagnosticsViewModel`
- Services: `AuthorizationService`, `PlaylistService`, `AlbumService`, `ArtworkCache`, `PlayerController`

**UI Layout Strategy**: Use SwiftUI size classes and idiom checks for device-appropriate layouts. iPad layouts must be optimized (different density, spacing, typography), not stretched phone layouts.

## Core Architecture & Data Flow

### The Album Completion Rule (Critical)
- The "CDs" playlist is an **album picker**, not a playback source
- Any track in the playlist implies "include that track's entire album"
- Playback always queues the **full resolved album** in canonical order, even if only one track from that album is in the playlist
- Never play playlist tracks directly; always resolve to the full album first

### Data Flow (Authoritative)
1. **Authorization**: Check MusicKit authorization → show auth screen if needed
2. **Playlist Discovery**:
   - Find playlist(s) named "CDs"
   - If multiple exist: select based on most-recent modification timestamp, or largest item count as fallback
   - Record selection decision for Diagnostics
3. **Album Resolution**:
   - Fetch playlist items → extract album IDs → dedupe (Set)
   - Resolve albums for those IDs via AlbumService
   - Handle unavailable albums gracefully (show disabled disc or omit)
4. **Sorting**: Build `Disc` list with sort keys:
   - Primary: `artistSortKey` (lowercase, trimmed, strip leading "the"/"a"/"an" for sorting only)
   - Secondary: `albumSortKey` (lowercase, trimmed)
   - Tie-break: `albumID`
5. **UI**: Render sorted discs → tap plays full album via `ApplicationMusicPlayer.shared`

### Multi-disc Albums
Treat as a **single disc** in the wallet. Playback queues the full album in canonical order (including disc numbers).

### Playlist Name Collision Rule
If multiple "CDs" playlists exist:
1. Prefer most recently modified/added-to timestamp
2. Else prefer largest item count
3. Else first stable ordering
Always record selection reason in Diagnostics.

## Core Services

### AuthorizationService
- `func ensureAuthorized() async -> Bool`
- Manages MusicKit authorization state

### PlaylistService
- `func locateCDsPlaylist() async throws -> PlaylistSelection`
- `func fetchPlaylistItems(playlistID:) async throws -> [TrackLike]`
- `func extractAlbumIDs(from:) -> [String]`
- Implements name collision resolution

### AlbumService
- `func resolveAlbums(ids: [String]) async -> [AlbumResolution]`
- Use TaskGroup with concurrency limit (max ~6 concurrent requests)
- Cache resolved album metadata in-memory

### ArtworkCache
- In-memory NSCache keyed by `albumID+size`
- Optional disk cache in Caches directory

### PlayerController
- Uses `ApplicationMusicPlayer.shared` (app-controlled queue)
- `func playAlbum(albumID: String, startTrackID: String?) async throws`
- Always queues the resolved Album object (full tracks in canonical order), never playlist tracks

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

### First Light (MVP)
1. Authorization screen + `NSAppleMusicUsageDescription` in Info.plist
2. Locate "CDs" playlist (handle missing/duplicate cases)
3. Extract album IDs → resolve albums → simple **list** view (not paged wallet yet)
4. Tap disc → Now Playing → play full album
5. Diagnostics screen showing: auth status, playlist selection decision, resolution stats

### Post-First Light
1. Add sorting and stable ordering
2. Add manual refresh + caching (artwork + metadata)
3. Replace list with horizontally **paged wallet** UI:
   - iPhone: 2 discs per page
   - iPad: denser grid (e.g., 2×2 or 3×2)

### Deferred (Post-MVP)
- Page flip animation, disc pull-out gestures
- Playlist switching UI for name collisions
- Search/filtering, haptics, CD case textures

## Required Xcode Configuration

- **Capability**: Enable MusicKit in Signing & Capabilities
- **Info.plist**: Add `NSAppleMusicUsageDescription` with explanation for library access
- **Device Families**: iPhone + iPad (universal target)

## Testing Strategy

### Unit Tests (CDWalletCore)
- Sort key generation (including article stripping: "The Beatles" → "beatles, the")
- Stable sorting by artist → album → albumID
- Album ID deduplication
- Playlist selection heuristic when multiple "CDs" playlists exist
- Missing album ID handling

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
