# CD Wallet (Apple Music) — DESIGN_APPROACH.md

## Design principles
- MVP-first: validate MusicKit access + playback before building nostalgic animations.
- Album-first: the fundamental unit is the album (“disc”).
- Deterministic: playlist → album IDs → resolved albums → stable sort → stable UI.
- Honest UI states: show clear “not authorized / playlist missing / some unavailable” conditions.

## High-level architecture
Universal SwiftUI app with a shared core layer.

- UI: SwiftUI
- Core: CDWalletCore module (models, services, caching, view models)
- Concurrency: async/await (Swift Concurrency)

Suggested pattern: MVVM
- Models: Disc, DiscResolutionResult, WalletState
- ViewModels: WalletViewModel, PlayerViewModel, DiagnosticsViewModel
- Services: AuthorizationService, PlaylistService, AlbumService, ArtworkCache, PlayerController

## Data flow (authoritative)
1. Launch:
   - Determine Music authorization state.
   - If not authorized: show Authorization screen.
2. After authorization:
   - Fetch the “CDs” playlist:
     - if none: show “create playlist” empty state
     - if multiple: apply name-collision rule and record decision for Diagnostics
   - Fetch playlist items.
   - Extract album IDs from each item; ignore items missing album IDs.
   - Dedupe album IDs (Set).
   - Resolve albums for those IDs.
   - Build Disc list with display metadata and sort keys.
   - Sort discs: artistSortKey → albumSortKey → albumID tie-break.
3. UI:
   - Render discs in a simple list for first light.
   - Tap disc → Now Playing (and start playback).

## Completing the album (core experience)
- The playlist may contain partial albums.
- The app must:
  - treat playlist items only as album references
  - resolve each album and queue the full album for playback

Failure modes:
- If an album can’t be resolved: show a disabled disc (post-first-light) or omit it (first light). Prefer disabled disc once basic UI is stable.
- If playback fails: show an error state on Now Playing with retry.

## “First light” UI plan (minimum viable)
### Screen 1: Authorization
- Single explanation + “Allow Access” CTA
- If denied: show instructions to enable in Settings

### Screen 2: Wallet (First light = list)
- A plain list of discs:
  - Artist
  - Album title
  - Small artwork thumbnail
- Pull-to-refresh or a refresh button.

### Screen 3: Now Playing
- Album title, artist
- Play/Pause
- Next/Previous
- Scrubber
- Optional: track title display

### Screen 4: Diagnostics (MVP)
A simple, developer-friendly but user-safe screen showing:
- Authorization status
- Playlist lookup:
  - number of playlists named “CDs”
  - selected playlist identifier/name (and heuristic used if collision)
  - item count
- Resolution stats:
  - playlist items scanned
  - album IDs extracted
  - unique albums
  - resolved albums
  - unresolved / unavailable count
- Last refresh time

## Wallet UI (post-first-light upgrade path)
After MusicKit behavior is verified:
- Replace list with horizontally paged “wallet” browsing.
- iPhone:
  - 2 discs per page/spread
- iPad:
  - denser layout (e.g., 2x2 or 3x2 per page), with the same disc metaphor

Avoid page curl and pull-out animations until the scrolling/selection experience is stable.

## Sorting (presentation semantics)
Compute sort keys:

- artistSortKey:
  - lowercased, trimmed, locale-aware
  - strip leading English articles (“the ”, “a ”, “an ”) for sorting only
- albumSortKey:
  - lowercased, trimmed, locale-aware

Sort:
1) artistSortKey
2) albumSortKey
3) albumID

## Multi-disc album handling
- Represent as one disc (one album).
- Show track list grouped by disc number later; MVP does not need grouping UI.

## Caching strategy (MVP-friendly)
- Artwork:
  - in-memory cache
  - optional disk cache keyed by albumID + size
- Album metadata:
  - in-memory dictionary keyed by albumID
- Rebuild disc list on refresh; reuse caches to accelerate.

## Error and empty states
- Not authorized → Authorization screen
- Playlist missing → explain how to create “CDs” and add one track from each album
- Zero resolved albums → empty state with refresh
- Partial failures → show count in Diagnostics; optionally show disabled discs

## Post-MVP polish backlog (explicitly deferred)
- Page flip animation
- Disc pull-out physics
- CD case textures/shadows and sound effects
- Playlist switching UI when multiple “CDs” playlists exist
- Search/filtering
- Haptics
