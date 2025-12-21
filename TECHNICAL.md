# CD Wallet (Apple Music) — TECHNICAL.md

## Tech stack
- Swift + Swift Concurrency (async/await)
- SwiftUI
- MusicKit
- MVVM with a shared core module (internal framework or Swift package)

## Project structure (universal app)
Single app target:
- Device families: iPhone + iPad
- Separate UI layouts via size class / idiom checks (e.g., `horizontalSizeClass`, `UIDevice.userInterfaceIdiom`)

Shared module:
- `CDWalletCore`
  - Models
  - Services
  - ViewModels
  - Caching

Rationale:
- Fastest path to shipping an iPhone and iPad experience without doubling App Store overhead.

## Capabilities, permissions, and config
### Capabilities
- Enable the MusicKit capability in Signing & Capabilities.

### Info.plist
- `NSAppleMusicUsageDescription`: required to request library access.

### Operational assumptions (MVP)
- User is signed into Apple Music / Music app.
- Streaming availability may vary; handle unavailable items gracefully.

## Domain model

### Disc
Represents one “CD” in the wallet; backed by an Album.

Minimum fields:
- `albumID: String` (or MusicItemID wrapper)
- `artistName: String`
- `albumTitle: String`
- `artworkURL` or `Artwork` reference
- `artistSortKey: String`
- `albumSortKey: String`

### Diagnostics snapshot
A struct capturing:
- auth status
- playlist match counts and selection decision
- resolution stats
- last refresh time
- last error (optional)

## Core services

### AuthorizationService
Responsibilities:
- expose current authorization status
- request authorization

API sketch:
- `func ensureAuthorized() async -> Bool`
- `var status: MusicAuthorization.Status`

### PlaylistService
Responsibilities:
- fetch library playlists and find “CDs”
- handle duplicate names deterministically
- fetch playlist items
- extract album IDs

MVP name-collision selection:
1) Prefer playlist with most-recent modification timestamp if available.
2) Else prefer playlist with largest item count.
3) Else fall back to first stable ordering and record reason for Diagnostics.

API sketch:
- `func locateCDsPlaylist() async throws -> PlaylistSelection`
- `func fetchPlaylistItems(playlistID: ...) async throws -> [TrackLike]`
- `func extractAlbumIDs(from items: [TrackLike]) -> [String]`

### AlbumService
Responsibilities:
- resolve album IDs to album metadata (and optionally tracks)
- concurrency-limited resolution
- caching

API sketch:
- `func resolveAlbums(ids: [String]) async -> [AlbumResolution]`

Concurrency:
- Use a TaskGroup plus a simple semaphore/concurrency limiter (e.g., max 6).

### ArtworkCache
Responsibilities:
- deliver artwork quickly for scrolling UI
- bound memory usage

MVP:
- in-memory NSCache keyed by albumID+size
- optional disk cache in Caches directory

### PlayerController
Use `ApplicationMusicPlayer.shared` (app-controlled queue).

Responsibilities:
- set queue to an album (full album semantics)
- play/pause/next/previous/seek
- expose observable playback state

API sketch:
- `func playAlbum(albumID: String, startTrackID: String? = nil) async throws`
- `func togglePlayPause()`
- `func next()`
- `func previous()`
- `func seek(to seconds: Double)`

Queue semantics:
- Always queue the resolved Album object (canonical track ordering), not playlist tracks.

## Sorting implementation
Generate sort keys when building Disc:

- `artistSortKey`:
  - lowercased + trimmed
  - optionally strip leading “the ” / “a ” / “an ”
- `albumSortKey`:
  - lowercased + trimmed

Sort:
- `(artistSortKey, albumSortKey, albumID)` ascending

Keep the display strings unchanged.

## UI implementation plan (build order)

### Step 1: Authorization + first light list
- Authorization screen
- Wallet list:
  - artist, album title, thumbnail
- Tap → Now Playing → start playback
- Diagnostics screen

### Step 2: Stabilize resolution
- Add manual refresh
- Add partial failure handling
- Add sorting and stable ordering
- Add caching (artwork + metadata)

### Step 3: Wallet paging UI
- Replace list with horizontally paged wallet view
- iPhone: 2 discs per page/spread
- iPad: denser grid per page

## States and errors
WalletState:
- `needsAuthorization`
- `loading`
- `ready(discs)`
- `empty(reason)`
- `error(userFacingError)`

Design requirement:
- Never crash on missing metadata; surface counts in Diagnostics.

## Testing (pragmatic)
Unit tests in CDWalletCore:
- sort key generation (including article stripping)
- stable sorting
- dedupe album IDs
- playlist selection heuristic when multiple “CDs” playlists exist
- missing album IDs handling

Manual test checklist:
- playlist missing
- multiple playlists named “CDs”
- playlist with partial albums
- album unavailable
- iPad layout sanity (not stretched)

## “First light” checklist (explicit)
- [ ] MusicKit capability enabled
- [ ] `NSAppleMusicUsageDescription` added
- [ ] Authorization request works
- [ ] Locate “CDs” playlist (or show missing state)
- [ ] Extract album IDs and resolve at least one album
- [ ] Show list of resolved albums
- [ ] Tap album plays full album via app-controlled player
- [ ] Diagnostics displays counts and selection decision
