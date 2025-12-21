# CD Wallet (Apple Music) — PROJECT.md

## One-sentence summary
A universal iOS/iPadOS app that recreates browsing a Case Logic CD wallet and defaults to listening to full albums, using the user’s Apple Music library as the source.

## Core product concept
- The user maintains a single Apple Music playlist named **“CDs”**.
- The app treats that playlist as an **album picker**, not a playback source:
  - Any track in “CDs” implies “include that track’s album as a disc in the wallet.”
  - If only some tracks from an album are in the playlist, the app **completes the album** and plays the **entire album** in canonical order.

## Target platforms
- **Universal app**: iPhone + iPad device families in a single target.
- Same features; layouts are device-appropriate so iPad does not feel like a scaled phone UI.
- Deployment target: **latest supported iOS and iPadOS major versions only**.

## Goals
1. Restore full-album listening as the default behavior.
2. Make “browse → pick an album → play” fast and reliable.
3. Reach “first light” MVP as quickly as possible; defer visual polish.

## Non-goals (MVP)
- Realistic page curl/page flip physics
- Disc pull-out gesture animation
- Editing/reordering the “CDs” playlist from inside the app
- Advanced library management (search/tagging/rating)
- Cross-device sync beyond what Apple Music already does

## Primary user stories
1. As a user, I can grant permission and the app loads my **“CDs”** playlist.
2. As a user, I see a browsable collection of discs (albums) derived from “CDs”.
3. As a user, discs are sorted like a physical collection: **band/artist name**, then **album title**.
4. As a user, tapping a disc starts playback of the **full album** and shows a simple CD-player UI.
5. As a user, I can play/pause, skip next/previous, and scrub.

## Key product rules

### Album completion rule (hard requirement)
- Wallet membership comes from playlist items.
- Playback always queues the **resolved album** (full track list), not the playlist subset.

### Playlist selection rule (name collisions)
If multiple playlists named “CDs” exist:
- MVP rule: select the one with the **most recently modified / most recently added-to** timestamp, if available.
- If no reliable timestamp exists, select the one with the **largest item count** as a heuristic.
- Always show which playlist is selected in Diagnostics and allow the user to switch (post-MVP). For MVP, only show the selection decision.

### Disc identity rule (no fuzzy matching)
- The disc corresponds to the **album ID** associated with playlist entries.
- Do not attempt to merge “deluxe” vs “standard” vs “clean/explicit” albums in MVP.

### Multi-disc albums
- MVP rule: treat a multi-disc album as a **single disc** in the wallet.
- Playback queues the full album in canonical order (including disc numbers).

## Sorting requirements
- Primary: artist/band name (ascending)
- Secondary: album title (ascending)
- Comparison: case-insensitive, locale-aware
- Recommended for MVP: ignore leading English articles (“The”, “A”, “An”) in the **artist sort key** only (display unchanged).

## MVP scope

### Included (MVP)
- Music authorization + permission UX
- Find “CDs” playlist + load playlist items
- Extract album IDs, dedupe, resolve albums
- Sort discs by artist then album
- Basic “Wallet” UI (list first; upgrade to paged wallet after first light)
- Now Playing screen (basic controls)
- Diagnostics screen (minimal but real)

### Deferred (post-MVP)
- Wallet page flip animation
- Disc pull-out animation
- Fancy skeuomorphic CD-player chrome
- Playlist switching UI when name collisions occur
- Offline-first behaviors beyond caching

## Acceptance criteria (MVP)
- Fresh install → permission granted → if “CDs” exists, app shows at least one disc.
- Manual refresh updates wallet membership after playlist edits.
- Tapping a disc plays the **entire album**.
- Sorting is stable and matches artist then album title.
- iPad UI is clearly optimized (different layout density, spacing, typography) and not a stretched phone layout.
- Diagnostics screen reports playlist discovery and resolution stats.

## Milestones (implementation order)
1. **First light**: authorization → find “CDs” → list of resolved albums → tap plays full album.
2. Add sorting rules and stable ordering.
3. Add Now Playing polish (scrubber, track title/artist).
4. Add basic caching and faster reloads.
5. Replace list with wallet paging UI (2-per-page style on iPhone; denser grid on iPad).
6. Post-MVP polish backlog.
