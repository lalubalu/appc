# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Connectify is a community-centered iOS app that revives outdoor spaces and strengthens local connections through gamified exploration, personalized recommendations, and local event boards. Features a Pokemon GO-style collection system where users collect places and earn points redeemable for gift cards.

## Target Audience

- Adults (21-40), Students (13-20), Parents (any age)

## Repository Structure

```
Website Context/           — Marketing website & business plan
  index.html               — Self-contained about-us website (HTML+CSS+JS)
  Connectify Detailed BP.pdf — Business plan document

Connectify/Connectify/     — SwiftUI iOS app source code
  ConnectifyApp.swift      — App entry point, manages onboarding, dark/light mode, GameStateManager
  Theme/
    ConnectifyTheme.swift  — Brand colors (adaptive light/dark), typography, spacing
  Models/
    Models.swift           — Core models: Place (with distanceValue), Event, Challenge, DailyGem, etc.
    CollectionModels.swift — Gamification: PlaceRarity, CollectiblePlace, Reward, RewardTier
    GameStateManager.swift — @Observable game state: collected places, points, rewards (UserDefaults persistence)
    SampleData.swift       — Placeholder data: places, collectibles, events, rewards, challenges
  Views/
    MainTabView.swift      — 6-tab navigation: Explore, Collect, Map, Events, Community, Profile
    Onboarding/
      OnboardingView.swift — 5-step onboarding: 3 intro pages → interest picker → name entry
    Explore/
      ExploreView.swift    — Home: Daily Gem, challenges, category filters, places with rarity indicators
      PlaceDetailView.swift— Place detail with collect button, rarity stats, celebration overlay
    Collection/
      CollectionView.swift — "Collectidex": points wallet, progress ring, category breakdown, collection grid
      CollectionCelebrationView.swift — Full-screen collect animation with particles and point counter
    Events/
      EventsView.swift     — Event board with category filters, event cards, detail sheets
    Map/
      MapExploreView.swift — MapKit with collection-state pins, radar pulse, nearby uncollected panel
    Community/
      CommunityView.swift  — Social feed with posts, likes, compose sheet
    Rewards/
      RewardsStoreView.swift       — Gift card store grouped by tier, redeem flow
      RewardConfirmationView.swift — Redemption success with animated checkmark
    Profile/
      ProfileView.swift    — Points balance, collection stats, XP, badges, challenges, rewards link, settings
  Components/
    SharedComponents.swift — Buttons, pills, stat cards, avatars, progress rings, XP badges
    RarityBadge.swift      — Rarity tier badge, PointsBadge, RarityDot indicators
  Models/
    LocationManager.swift  — @Observable CLLocationManager wrapper with GPS distance/proximity methods
```

## How to Run the App

The Xcode project is pre-generated via XcodeGen:

```bash
open Connectify/Connectify.xcodeproj
```

Select an iPhone simulator and press Cmd+R. Requires Xcode 15+ (iOS 17 target).

If you add new `.swift` files, regenerate the project:
```bash
cd Connectify && xcodegen generate
```

No external dependencies — uses only SwiftUI, MapKit, CoreLocation, and PhotosUI.

## Build Command

```bash
cd Connectify && xcodebuild -project Connectify.xcodeproj -scheme Connectify -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Design Language

Supports **light mode (default)** and **dark mode** (toggle in Profile → Settings).

### Colors (defined programmatically in `ConnectifyTheme.swift`)
- **Primary green:** `hsl(155, 100%, 50%)` — buttons, accents, tab tint, collection indicators
- **Light mode:** off-white backgrounds, white cards, dark charcoal text
- **Dark mode:** deep navy `hsl(231, 15%, 9%)` background, `hsl(231, 8%, 16%)` cards, white text
- **Category accents:** coral, amber, sky blue, lavender, mint — each `PlaceCategory` has a unique tint
- **Rarity colors:** green (Common), amber (Uncommon), lavender (Rare), coral (Legendary)
- **Destructive:** `hsl(349, 100%, 62%)`

### Corner Radii & Shape Language
- Sharp, editorial corners — `Radius.sm=2, md=4, lg=6, xl=8`
- Badges and pills use `RoundedRectangle(cornerRadius: 3-4)` instead of `Capsule()`
- Only XP progress bar tracks use `Capsule()` (thin functional bars)

### Typography
- Display headings use `.serif` design (SF Pro Serif)
- Body/UI uses `.default` design (SF Pro)
- Custom web fonts (Outfit, DM Serif Display) can be bundled later

## Architecture

- **State management:** `GameStateManager` is an `@Observable` class injected via `.environment()` from `ConnectifyApp`. Persists to `UserDefaults` (collected place IDs, points balance, redeemed rewards stored as JSON-encoded sets).
- **Dual currency:** XP = permanent progression (levels). Points = spendable currency (gift cards). They are independent.
- **Rarity system:** Places have 4 rarity tiers mapped from category: Common (5pts), Uncommon (10pts), Rare (25pts), Legendary (50pts). Events are the primary point source (75–250 pts).
- **Proximity:** Real GPS via `LocationManager` (`CLLocationManager`). Collection requires being within 500 feet. `CollectiblePlace.isNearby(from:)` checks live distance. `isNearbyStatic` is a fallback using static `distanceValue`.
- **Event check-in:** Requires proximity (500 ft) + proof of attendance photo upload (via `PhotosPicker`). Verification logic is placeholder — to be implemented server-side.
- **Economy:** Events = primary earner (75–250 pts). Places = secondary (5–50 pts). Rewards: $5 = 1000 pts, $10 = 2500 pts, $25 = 7500 pts, $50 = 20000 pts.
- **Navigation:** `NavigationStack` per tab with typed destinations. Sheets for detail views, rewards store.
- **Theming:** Adaptive colors via `UIColor { traitCollection in ... }` — dark/light mode switches automatically.

## What Needs to Be Done (Backend & Beyond)

- [ ] **Authentication** — Sign up / sign in flow (Firebase Auth, Supabase, or custom)
- [ ] **Backend API** — Replace `SampleData` and `GameStateManager` UserDefaults with real API calls
- [ ] **Database** — Persistent storage for user profiles, collection state, points, rewards
- [x] **Location services** — `CLLocationManager` integrated via `LocationManager` class. Real GPS proximity for collection and map.
- [ ] **Proof of attendance verification** — Server-side image verification for event check-in photos
- [ ] **Rewards fulfillment** — Real gift card API integration (e.g., Tango Card, Tremendous)
- [ ] **Image loading** — Replace placeholder icons with real photos (AsyncImage + CDN)
- [ ] **Push notifications** — Event reminders, challenge updates, nearby place alerts
- [ ] **Social features** — Real post creation, comments, follow system
- [ ] **Gamification engine** — Server-side XP, badge unlocking, streak tracking, challenge completion
- [ ] **Deep linking** — Share places, events, and collection progress via URL
- [ ] **Custom fonts** — Bundle Outfit and DM Serif Display .ttf files
- [ ] **Asset Catalog** — App icon (placeholder structure exists at `Assets.xcassets/AppIcon.appiconset/` — drop a 1024x1024 PNG named `AppIcon.png` there), launch screen
- [ ] **Accessibility** — VoiceOver labels, Dynamic Type support
- [ ] **Unit & UI tests** — XCTest target

## Changelog

- **2026-03-22** — UI polish: sharp corners throughout (Radius values reduced to 2/4/6/8), all Capsule() badges replaced with tight RoundedRectangles. Less generic, more editorial aesthetic.
- **2026-03-22** — Event-centric economy rebalance. Events are now primary tab and primary point source (75–250 pts). Places reduced to 5–50 pts. Rewards rebalanced (1000–20000 pts). Event check-in requires 500ft proximity + proof of attendance photo. Real GPS via LocationManager (CLLocationManager). App icon placeholder structure added. Bundle ID changed to com.vaiybhav.connectify.
- **2026-03-22** — Pokemon GO-style gamification system added. New "Collect" tab with Collectidex grid, 4-rarity-tier system, points wallet, collection celebration animations, rewards store with gift cards, and radar-style map with pulsing pins for nearby uncollected places. `GameStateManager` persists collection/points/rewards state locally. Profile updated with points balance and rewards access. 7 new files, 7 modified files.
- **2026-03-22** — Initial iOS app UI created. 5 tabs (Explore, Events, Map, Community, Profile), onboarding flow, dark/light mode, gamification UI (challenges, XP, badges, streaks), Daily Gem, community feed, MapKit integration.

## Website Development

The website is a single self-contained HTML file. Open `Website Context/index.html` in a browser to preview. No build tools required.
