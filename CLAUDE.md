# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Connectify is a community-centered iOS app that revives outdoor spaces and strengthens local connections through gamified exploration, personalized recommendations, and local event boards.

## Target Audience

- Adults (21-40), Students (13-20), Parents (any age)

## Repository Structure

```
Website Context/           — Marketing website & business plan
  index.html               — Self-contained about-us website (HTML+CSS+JS)
  Connectify Detailed BP.pdf — Business plan document

Connectify/Connectify/     — SwiftUI iOS app source code
  ConnectifyApp.swift      — App entry point, manages onboarding & dark/light mode
  Theme/
    ConnectifyTheme.swift  — Brand colors (adaptive light/dark), typography, spacing
  Models/
    Models.swift           — Data models: Place, Event, Challenge, DailyGem, CommunityPost, UserProfile
    SampleData.swift       — Placeholder data for all UI screens
  Views/
    MainTabView.swift      — 5-tab navigation: Explore, Events, Map, Community, Profile
    Onboarding/
      OnboardingView.swift — 5-step onboarding: 3 intro pages → interest picker → name entry
    Explore/
      ExploreView.swift    — Home tab: Daily Gem, active challenges, category filters, places list
      PlaceDetailView.swift— Place detail with stats, description, actions
    Events/
      EventsView.swift     — Event board with category filters, event cards, detail sheets
    Map/
      MapExploreView.swift — MapKit view with annotated pins, place selection card
    Community/
      CommunityView.swift  — Social feed with posts, likes, compose sheet
    Profile/
      ProfileView.swift    — User stats, XP bar, badges, challenges, settings (dark mode toggle)
  Components/
    SharedComponents.swift — Reusable UI: buttons, pills, stat cards, avatars, progress rings, badges
```

## How to Run the App

1. Open Xcode (requires Xcode 15+ for iOS 17 APIs)
2. **File → New → Project → iOS → App**
3. Set Product Name to `Connectify`, Interface to `SwiftUI`, Language to `Swift`
4. Save the project into the `Connectify/` directory (replacing the generated template)
5. Delete the auto-generated `ContentView.swift` (our entry point is `ConnectifyApp.swift`)
6. Drag all `.swift` files from `Connectify/Connectify/` into the Xcode project navigator
7. Build and run on simulator (iPhone 15 Pro recommended) or device

No external dependencies — uses only SwiftUI, MapKit, and system frameworks.

## Design Language

Supports **light mode (default)** and **dark mode** (toggle in Profile → Settings).

### Colors (defined programmatically in `ConnectifyTheme.swift`)
- **Primary green:** `hsl(155, 100%, 50%)` — used for buttons, accents, tab tint, XP indicators
- **Light mode:** off-white backgrounds, white cards, dark charcoal text
- **Dark mode:** deep navy `hsl(231, 15%, 9%)` background, `hsl(231, 8%, 16%)` cards, white text (matches website)
- **Category accents:** coral, amber, sky blue, lavender, mint — each `PlaceCategory` has a unique tint
- **Destructive:** `hsl(349, 100%, 62%)` — used for sign-out and error states

### Typography
- Display headings use `.serif` design (SF Pro Serif, matching DM Serif Display intent)
- Body/UI uses `.default` design (SF Pro, matching Outfit intent)
- Custom web fonts (Outfit, DM Serif Display) can be bundled later for exact parity

## Architecture

- **Pattern:** Single-source-of-truth via `@AppStorage` for user preferences (dark mode, onboarding state). No ViewModel layer yet — views read directly from `SampleData`.
- **Navigation:** `NavigationStack` with typed navigation destinations (`Place` is `Hashable` for push navigation). Sheets used for event detail and post compose.
- **Theming:** Adaptive colors via `UIColor { traitCollection in ... }` wrapped in `Color`, so dark/light mode switches automatically. No Asset Catalog color sets required.

## What Needs to Be Done (Backend & Beyond)

- [ ] **Authentication** — Sign up / sign in flow (Firebase Auth, Supabase, or custom)
- [ ] **Backend API** — Replace `SampleData` with real API calls (places, events, posts, user data)
- [ ] **Database** — Persistent storage for user profiles, check-ins, XP, badges
- [ ] **Location services** — `CLLocationManager` integration for real distances and map centering
- [ ] **Image loading** — Replace placeholder icons with real photos (AsyncImage + CDN)
- [ ] **Push notifications** — Event reminders, challenge updates, community activity
- [ ] **Search backend** — Server-side search for places and events
- [ ] **Social features** — Real post creation, comments, follow system
- [ ] **Gamification engine** — Server-side XP calculation, badge unlocking, streak tracking
- [ ] **Deep linking** — Share places and events via URL
- [ ] **Custom fonts** — Bundle Outfit and DM Serif Display .ttf files + register in Info.plist
- [ ] **Asset Catalog** — App icon, launch screen, color sets for named colors
- [ ] **Accessibility** — VoiceOver labels, Dynamic Type support
- [ ] **Unit & UI tests** — XCTest target

## Changelog

- **2026-03-22** — Initial iOS app UI created. All 5 tabs implemented with SwiftUI (Explore, Events, Map, Community, Profile). Includes onboarding flow, dark/light mode, gamification UI (challenges, XP, badges, streaks), Daily Gem feature, community social feed, MapKit integration, and reusable component library. All data is placeholder — no backend connected.

## Website Development

The website is a single self-contained HTML file. Open `Website Context/index.html` in a browser to preview. No build tools required.
