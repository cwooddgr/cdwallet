# CD Wallet

A universal iOS/iPadOS app that recreates the experience of browsing a physical CD wallet for your Apple Music library.

## Overview

CD Wallet lets you curate a collection of albums in a "CDs" playlist, then browse them visually like flipping through a real CD wallet. Tap any album to play it in full—always the complete album, never just the tracks you've added to your library.

## Features

- **Wallet-style browsing**: Swipe through pages of album artwork
- **iPhone layout**: 2 albums per page (vertical)
- **iPad layout**: 6 albums per page (3×2 grid)
- **Full album playback**: Tapping an album plays the complete catalog version with all tracks
- **Smart artwork loading**: Falls back to Apple Music catalog when local artwork isn't cached
- **Diagnostics view**: Debug info for playlist resolution and album matching

## Requirements

- iOS 18.0+ / iPadOS 18.0+
- Apple Music subscription
- Xcode 16+

## Setup

1. Clone the repository
2. Open `CDWallet/CDWallet.xcodeproj` in Xcode
3. Configure signing with your Apple Developer account
4. Ensure the App ID has MusicKit capability enabled in the [Apple Developer Portal](https://developer.apple.com/account)
5. Build and run on a device (MusicKit requires a real device, not simulator)

## Usage

1. In Apple Music, create a playlist named **"CDs"**
2. Add one or more tracks from any albums you want in your wallet
3. Open CD Wallet and grant Apple Music access
4. Browse your albums and tap to play

The app uses your playlist as an album picker—you only need one track per album. When you tap an album, CD Wallet finds the full version in the Apple Music catalog and plays all tracks in order.

## Architecture

The project is organized as:

- **CDWallet/** - Main app target (SwiftUI views)
- **CDWalletCore/** - Swift Package with shared logic
  - Models: `Disc`, `WalletState`, `AlbumResolution`
  - Services: `PlaylistService`, `AlbumService`, `PlayerController`, `ArtworkCache`
  - ViewModels: `WalletViewModel`, `PlayerViewModel`

## Technical Notes

- Uses MusicKit iOS 18 APIs with explicit relationship loading (`.with([.tracks, .entries])`)
- Library album IDs differ from catalog IDs—album matching uses title/artist search
- Fuzzy matching handles spelling variations (e.g., "Rumours" vs "Rumors") and edition suffixes

## License

MIT License - see [LICENSE](LICENSE) for details.
