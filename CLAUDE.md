# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Verdure is a community-centered iOS app that revives outdoor spaces and strengthens local connections through gamified exploration, personalized recommendations, and local event boards. It features a Pokémon GO-style collection system where users collect places and attend events to earn points redeemable for gift cards. Tagline: **"Step Outside. Connect Within."**

## Target Audience

- Adults (21–40), Students (13–20), Parents (any age)

## Repository Structure

```
Verdure Website/           — Marketing website (Next.js, claymorphism, Three.js logo)
Verdure Logo.png           — Brand logo (compass + leaf)
PROMPT.md                  — Original website redesign brief

Verdure/                   — Xcode project container (XcodeGen)
  project.yml              — XcodeGen spec (name/target/bundle = Verdure)
  Verdure.xcodeproj        — Generated project
  Secrets.xcconfig         — Firebase project id / SerpApi key (gitignored)
  Verdure/                 — SwiftUI app source
    VerdureApp.swift       — @main App + RootView (owns state, drives light/dark color scheme)
    Theme/
      VerdureTheme.swift   — "Warm Forest" palette (adaptive light + dark), clay tokens, Fredoka/Rubik type ramp, spacing, radii
    Resources/Fonts/       — Fredoka + Rubik static weights (bundled via UIAppFonts)
    Models/
      Models.swift             — Place, Event, Challenge, DailyGem, CommunityPost, etc.
      CollectionModels.swift   — PlaceRarity, CollectiblePlace, Reward, RewardTier
      GameStateManager.swift   — @Observable game state (UserDefaults + Firestore sync)
      AuthService.swift / FirestoreService.swift — Firebase Auth + Firestore
      PlacesAPIService.swift / EventsAPIService.swift — live places/events
      LocationManager.swift    — CLLocationManager wrapper
      SampleData.swift         — placeholder data (also used as fallback when APIs are empty)
    Components/
      ClayKit.swift            — claymorphism primitives: ClayBackground/claySurface, ClayButton, ClayChip, ClayIconTile, ClayProgressBar, KickerLabel, ClaySectionHeader, Haptics
      ClayMotion.swift         — gyro ParallaxTilt, Shimmer, IdleFloat, AmbientGlow, SoftGrain, VerdureBackground, RiseIn
      VerdureMedallion3D.swift — SceneKit 3D compass-leaf medallion (+ faux-3D ClayMedallion)
      SharedComponents.swift   — VerdureButton, CategoryPill, StatCard, AvatarCircle, NeonProgressRing, PlacePlaceholder, etc. (all clay)
      RarityBadge.swift        — RarityBadge/PointsBadge/RarityDot + rarity/category/tier → clay accent mappings
    Views/
      MainTabView.swift        — 6-tab clay floating tab bar (Events, Explore, Map, Collect, Community, Profile)
      Onboarding/OnboardingView.swift — clay onboarding w/ 3D medallion hero
      Explore/ (ExploreView, PlaceDetailView) + DailyGemView.swift
      Collection/ (CollectionView, CollectionCelebrationView)
      Events/EventsView.swift, Map/MapExploreView.swift, Community/CommunityView.swift
      Profile/ProfileView.swift, Rewards/ (RewardsStoreView, RewardConfirmationView)
    Assets.xcassets/         — AppIcon (compass-leaf on clay-cream), VerdureMark imageset
```

## How to Run the App

```bash
open Verdure/Verdure.xcodeproj
```
Select an iPhone simulator and press Cmd+R. Requires Xcode 15+ (iOS 17 target).

If you add new `.swift` files, regenerate the project:
```bash
cd Verdure && xcodegen generate
```

## Build Command

```bash
cd Verdure && xcodebuild -project Verdure.xcodeproj -scheme Verdure -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Dependencies: Firebase (Auth + Firestore) via SwiftPM. Fonts (Fredoka, Rubik) are bundled. Otherwise SwiftUI, SceneKit, MapKit, CoreLocation, CoreMotion, PhotosUI.

## Design Language — "Warm Forest" Claymorphism

The app's visual system mirrors the Verdure website: **claymorphism** with a sage-cream/forest-green palette. Supports **light (default)** and **dark** (deep-evergreen clay) modes; toggle in Profile → Settings.

### Claymorphism rules (non-negotiable)
- **One light source, top-left, everywhere.** Inner gloss highlight offset top-left, inner depth shadow bottom-right, plus a soft outer float. On press, clay sinks IN (inner shadows invert, float collapses). Implemented in `ClayKit.ClayBackground` via SwiftUI `.shadow(.inner(...))` on a gradient fill + stacked outer `.shadow`.
- **Restraint.** Clay is for objects users press or that read as physical (buttons, cards, tiles, chips, wells). Backgrounds and long text stay flat.
- **Depth hierarchy.** Bigger/softer floats for hero cards (`elevation` param), tighter for chips.

### Palette (`VerdureTheme.swift`, all adaptive)
- **Silica/cream** `#E6E8D4` (light canvas) / deep evergreen `#0A140F` (dark canvas) — dominant surface
- **Teal** `#16BFA5` — bright clay accent (dark text)
- **Spruce** `#14532D` — primary CTA / heading accent (light text)
- **Gold** `#B8860B` — warm accent + points (dark text)
- **Evergreen ink** `#0E1B16` — body text; also the dark "wallet/stat" clay tile
- Category & rarity map to these accents (see `RarityBadge.swift` extensions).

### Typography
- **Display: Fredoka** (chunky rounded) — hero + short section headers only. `VType.display(...)`
- **Body/UI: Rubik** — everything else. `VType.body(...)`, `VType.num(...)` for tabular stats.

### Motion (no generic fade-up)
- Physical springs with overshoot (`back.out`-like), weighted `riseIn`/`idleFloat`, gyro `parallaxTilt`, shimmer, particle bursts, the map radar sweep, and the SceneKit medallion idle-spin/drag.

## Architecture

- **Color scheme:** `RootView` (in `VerdureApp.swift`) owns `@AppStorage("prefersDarkMode")` and applies `.preferredColorScheme` — kept in a View (not the App struct) so toggling updates reliably.
- **State:** `GameStateManager` (`@Observable`, `.environment()`-injected) persists to UserDefaults + syncs to Firestore.
- **Dual currency:** XP = progression (levels); Points = spendable (gift cards).
- **Rarity:** 4 tiers (Common 5 / Uncommon 10 / Rare 25 / Legendary 50 pts). Events are the primary earner (75–250 pts).
- **Proximity:** real GPS via `LocationManager`; collection requires <500 ft. Event check-in requires proximity + proof-of-attendance photo (verification is placeholder).
- **Empty-API fallback:** screens fall back to `SampleData` when live APIs return nothing, so the UI is always populated.

## Backend / External

- **Firebase** project is `connectify-19dd8` (Auth + Firestore). The app bundle id is `com.vaiybhav.verdure`; `GoogleService-Info.plist` is still registered for the old bundle id, so Firebase logs a non-fatal bundle-id mismatch warning. To fully decouple, re-register a `com.vaiybhav.verdure` app in the Firebase console and swap in a new `GoogleService-Info.plist`.

## What Needs to Be Done (Backend & Beyond)

- [ ] **Upgrade Firebase project to Blaze**, then `npx firebase-tools deploy --only functions` (rules ARE deployed; functions blocked on billing — queued check-ins hold until then)
- [ ] **Enable Storage in console** (Get Started), then `npx firebase-tools deploy --only storage` (proof photos spool locally until then)
- [ ] Create the two Verdure+ subscriptions in App Store Connect (`com.vaiybhav.verdure.plus.monthly` / `.yearly` — local testing uses `Verdure/Verdure.storekit` via the Verdure scheme)
- [ ] Server-side subscription check (App Store Server API) so redeemReward enforces Plus-only tiers
- [ ] Real-device QA (2 phones): GPS gate outdoors, photo upload over cellular, airplane-mode queue replay
- [ ] Real gift-card fulfillment (Tango/Tremendous)
- [ ] Real photos (AsyncImage + CDN) to replace clay icon placeholders
- [ ] Push notifications, real social features
- [ ] Dynamic Type app-wide (scaled variants exist in VType; check-in + paywall adopted)

## Changelog

- **2026-07-20** — **Attendance evidence + honest paywall + tests.** Check-in now demands real proof: GPS proximity gate in EventDetailSheet (CoreLocation vs. event coords — source-provided or geocoded; hard 500 ft gate when the venue is known), proof photo spooled to Application Support and uploaded to Storage (`proofs/{uid}/{digest}.jpg`) during queue flush, and `checkInToEvent` now REQUIRES proofPath + lat/lng server-side (path-ownership check, best-effort existence check, ≤1.5 km haversine vs. stored event coords, `/attendance` audit log). Events carry optional `latitude/longitude` (rules-validated; community events geocode at creation; Eventbrite/Localist/Commons parse source coords; sample events seeded). Legacy event backfill dropped (nothing honest to submit). Fixed the Firebase bundle-ID mismatch via CLI re-registration (`apps:create` + new GoogleService-Info.plist — warning verified gone in launch logs). Paywall now sells ONLY live benefits (Premium Rewards + new profile member badge); roadmap features removed from sale copy. `VType.scaled*` Dynamic Type variants added (check-in + paywall adopted). New VerdureTests target: 10 passing transaction-logic tests (double check-in/collect no-ops, fast double-redeem, proof spooling, queue persistence + v1 decode, reset). Firestore rules redeployed. Functions/Storage deploys still blocked on Blaze + console Storage setup.

- **2026-07-19** — **Server-authoritative points + personalization + Verdure+.** Points/check-ins/redemptions now go through Cloud Functions callables (`checkInToEvent`, new `collectPlace`, `redeemReward` w/ real REWARD_COSTS); GameStateManager applies earns optimistically and reconciles via a persisted pending-op queue (offline-safe, idempotent replays, legacy backfill on first connect). Firestore rules deployed with production lockdown (client writes to points/checked-in/redeemed denied; zero-on-create). FirebaseFunctions added to SwiftPM. Daily Gem reworked into a once-per-day fun-fact splash (generic nature/community/environment facts, no repeats until pool exhausts — `DailyGemStore`). New "For You" personalized events section (interest→event-category mapping + in-app interest picker). Paid events removed (Ticketmaster/SeatGeek providers off; Eventbrite/Localist filtered to free). Verdure+ subscription via StoreKit 2 (`StoreService`, clay `PaywallView`, `Verdure.storekit` scheme config; Gold/Platinum reward tiers gated). VoiceOver pass on check-in, redeem, and onboarding flows.

- **2026-06-17** — **Verdure rebrand + full visual overhaul.** Complete rename Connectify → Verdure (project, target, scheme, bundle id `com.vaiybhav.verdure`, source folder, all symbols/strings). New "Warm Forest" claymorphism design system (`VerdureTheme` + `ClayKit` + `ClayMotion`), Fredoka/Rubik bundled fonts, real SceneKit 3D compass-leaf medallion, clay floating tab bar, and every screen rebuilt in clay (light + dark). New app icon from the compass-leaf logo. Old neon/"Bio" component library removed.
