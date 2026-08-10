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

## ⚠️ DEPLOY STATUS — re-verified against the live project 2026-08-09

Do not infer deploy state from changelog prose. E2E "37/37 green" is the **local
emulator**, not production. Live facts, re-checkable any time with the command below:

| Component | Live status (2026-08-09) |
|---|---|
| Firestore rules | ✅ **DEPLOYED** — ruleset `43d80b64…`, sha256 of live source matches `firestore.rules` byte-for-byte, updated 2026-07-29T01:32Z |
| Cloud Functions | ❌ **NOT DEPLOYED** — 0 functions exist (v1 and v2 APIs both empty) |
| Cloud Storage | ❌ **NO BUCKET** — Storage never initialised in console |
| Billing plan | ❌ **Spark** (`billingEnabled: false`) — Functions *cannot* deploy until Blaze |

**The backend stack is Firebase, not Supabase.** Supabase is the *marketing
website* only (`Verdure-website--main/`). The iOS app has zero Supabase code:
its SwiftPM deps are FirebaseAuth/Firestore/Functions/Storage and it ships a
`GoogleService-Info.plist`. There is no migration branch, stash, or plan. Do not
act on a belief that the app moved to Supabase — it did not.

**Consequence while Functions are down:** check-ins/collects apply optimistically on
device and queue in `pendingOps` forever; nothing is server-credited, no proof photo
uploads (no bucket), and `/attendance` audit rows are never written. The queue is
durable and replays automatically once the backend is live — no data is lost.
`GameStateManager.serverConfirmed` guards against the cloud's empty balance
overwriting those local earnings (see `CloudMergeTests`).

Re-verify live state at any time:
```bash
# prints billing plan, deployed function count, storage buckets, and diffs the
# live Firestore ruleset against firestore.rules
npx firebase-tools projects:list        # confirms auth
npx firebase-tools deploy --only functions --non-interactive   # errors if still Spark
```

## GO-LIVE RUNBOOK — run in this order

Everything below is written and tested against the emulators; step 1 is the only
one a human must do in a browser, and nothing after it can run until it's done.

```bash
# 1. HUMAN, IN THE CONSOLE (billing decision — cannot be scripted):
#    a) console.firebase.google.com → connectify-19dd8 → Upgrade → Blaze
#    b) Build → Storage → "Get Started" (creates the bucket)
#       Set a budget alert while you're there; Blaze is pay-as-you-go.

# 2. Secrets. Deploys succeed without these, but the features stay inert:
#    each one is read via defineSecret and simply reports "not configured".
cd functions
npx firebase-tools functions:secrets:set TREMENDOUS_API_KEY            # gift cards
npx firebase-tools functions:secrets:set TREMENDOUS_FUNDING_SOURCE_ID
npx firebase-tools functions:secrets:set TREMENDOUS_CATALOG            # {"starbucks-5":"<product id>", ...}
npx firebase-tools functions:secrets:set APPLE_IAP_PRIVATE_KEY         # .p8 CONTENTS
npx firebase-tools functions:secrets:set APPLE_IAP_KEY_ID
npx firebase-tools functions:secrets:set APPLE_IAP_ISSUER_ID
npx firebase-tools functions:secrets:set ANTHROPIC_API_KEY             # adventure planner
npx firebase-tools functions:secrets:set RECREATION_GOV_KEY            # places proxy
npx firebase-tools functions:secrets:set NPS_API_KEY

# 3. Deploy. Rules first — they're the lockdown the callables assume.
cd ..
npx firebase-tools deploy --only firestore:rules
npx firebase-tools deploy --only storage
npx firebase-tools deploy --only functions

# 4. VERIFY IT ACTUALLY LANDED (do not trust step 3's output alone):
#    functions should be non-empty, buckets non-empty, billingEnabled true.
#    The same read-only REST checks that produced the table above.
npx firebase-tools functions:list
```

Then: point App Store Server Notifications V2 at the deployed
`appStoreNotifications` URL, set `APPLE_APP_APPLE_ID` in `functions/.env`, flip
`APPLE_IAP_ENVIRONMENT` to `production` at launch, and work through
`DEVICE-QA.md` on two real phones.

## What Needs to Be Done (Backend & Beyond)

- [ ] **Upgrade Firebase project to Blaze + enable Storage** — the ONLY human-gated step; everything below is written and waiting. Re-verified 2026-08-09: still Spark, still 0 functions, still no bucket.
- [ ] Deploy functions + storage (see runbook above), then re-verify live state
- [ ] Create the two Verdure+ subscriptions in App Store Connect (`com.vaiybhav.verdure.plus.monthly` / `.yearly` — local testing uses `Verdure/Verdure.storekit` via the Verdure scheme)
- [ ] **Real-device QA (2 phones)** — script written at `DEVICE-QA.md`; needs hardware. Runs 2 and 3 also need the backend live.
- [ ] Fund a Tremendous account + map reward ids → product ids (`TREMENDOUS_CATALOG`); flip `TREMENDOUS_ENV=production` in `functions/.env`
- [ ] APNs Auth Key (.p8) → Firebase Cloud Messaging, and Push Notifications capability on the App ID (code is done; nothing delivers without these)
- [ ] Once Functions are live: add the Verdure+ 1.25x multiplier to `PaywallView.features` AND the store description in the same commit (both files carry the instruction)
- [x] ~~Server-side subscription check~~ — done (`functions/src/subscriptions.ts`)
- [x] ~~Real gift-card fulfillment~~ — done (`functions/src/fulfillment.ts`, Tremendous)
- [ ] Real photos (AsyncImage + CDN) to replace clay icon placeholders
- [ ] Real social features (follows, per-user feeds)
- [ ] Dynamic Type app-wide (scaled variants exist in VType; check-in + paywall adopted)

## Changelog

- **2026-08-09** — **The backend's two dead ends closed; planner + push added.** Re-verified live state: **still Spark, 0 functions, no bucket** — the checklist was right and the changelog prose was wrong, so check-ins have been queuing on-device for three weeks and nothing has ever been server-credited (no data lost; `pendingOps` is durable). Also settled a live misconception: **the iOS app has never used Supabase** — that's the marketing website; the app is 100% Firebase. Two features that shipped as no-ops are now real: **gift-card fulfilment** (`fulfillment.ts`, Tremendous — trigger + 30-min sweeper drain `/fulfillments`, idempotent on `external_id`, permanent failures refund points and un-redeem the reward, $25+ holds for manual approval) and **Verdure+ entitlement** (`subscriptions.ts`, App Store Server API + Server Notifications V2 write `plusExpiresAt`, which `hasActivePlus` reads and nothing previously wrote — so the 1.25x multiplier and Plus early access were inert for paying members). Ownership binding uses a **uid-derived `appAccountToken`** (RFC 4122 v5), so there's no stored field to overwrite and a replayed transaction id computes the wrong token. New **AI Adventure Planner** (`adventure.ts` + `AdventurePlannerView`): Claude picks from a candidate allowlist of real nearby places, weather from Open-Meteo (no API key), and **any stop it invents is dropped server-side** — grounding is mechanical, not a prompt instruction. **Push notifications** wired (FirebaseMessaging, APNs bridge, token stored per-user and removed on sign-out). Three real bugs fixed: `externalFetch` read `process.env` secrets it never declared, so both place providers would have returned "not configured" **in production only**; the new server-written `plus*` fields would have tripped the user-doc `hasOnly()` allowlist and permanently locked users out of their own document (the exact failure the rules comment already warned about); and `defineString` params made `npm run e2e` hang on an interactive prompt (fixed with `functions/.env`). `fcmTokens` now bounded at 10 — it's client-writable and fanned out to by `onPostCreated`. Push token lifecycle wired end to end (the settings toggle now actually registers with APNs; token attaches on sign-in and detaches on sign-out — otherwise a shared phone keeps receiving push for the previous account), and Restore Purchases falls back to the server's verified entitlement when StoreKit returns nothing. Tests: **backend E2E 48/48** (was 37), **23 new backend unit checks** incl. a golden vector pinning the `appAccountToken` derivation, **iOS 55/55** incl. a new a11y audit for the planner. `DEVICE-QA.md` written — the 2-phone field script, still unrun, and honestly marked as such.

- **2026-07-21** — **Backend E2E-proven + everything hardcoded made real.** New Local-Emulator E2E suite (`npm run e2e` in functions/; firebase-tools@13, firestore emulator on port 8899 — 8080 wedges on this machine; Firestore over gRPC only): **25/25 green** covering storage ownership/image rules, checkIn proof+GPS validation & haversine rejection & clamps & idempotency, attendance audit, rules lockdown, redeem lifecycle, and the new post-like rule (+1-only, deployed). Fabrications removed app-wide: real daily **streak** (foreground-day tracking), real **challenges** (monthly progress from a persisted earn-history) and **badges** (unlock dates persisted, real notifications) via `GamificationEngine`; Community rebuilt fake-free (real authors→stories, real trending from post places, real counts, Firestore-backed likes with per-device dedupe, honest member sheets, samples never mixed into real feed); notifications inbox no longer seeded — persisted real entries only; places carry **real coordinates** (collectibles/map no longer hash-scattered), **real photos** (NPS/RecGov/OSM via AsyncImage), real OSM hours when present ("typical" clearly labeled otherwise), and **no synthetic ratings/review counts/attendee counts anywhere**; PlaceDetail Share/Directions/Save all work (save persisted), events-at-place matched from live events; reward confirmation copy honest (email delivery, no fake code). **Dynamic Type enabled globally** at the VType ramp. Tests: 16/16 XCTest (incl. new streak/challenge/badge suite). Firestore rules redeployed.

- **2026-07-20** — **Attendance evidence + honest paywall + tests.** Check-in now demands real proof: GPS proximity gate in EventDetailSheet (CoreLocation vs. event coords — source-provided or geocoded; hard 500 ft gate when the venue is known), proof photo spooled to Application Support and uploaded to Storage (`proofs/{uid}/{digest}.jpg`) during queue flush, and `checkInToEvent` now REQUIRES proofPath + lat/lng server-side (path-ownership check, best-effort existence check, ≤1.5 km haversine vs. stored event coords, `/attendance` audit log). Events carry optional `latitude/longitude` (rules-validated; community events geocode at creation; Eventbrite/Localist/Commons parse source coords; sample events seeded). Legacy event backfill dropped (nothing honest to submit). Fixed the Firebase bundle-ID mismatch via CLI re-registration (`apps:create` + new GoogleService-Info.plist — warning verified gone in launch logs). Paywall now sells ONLY live benefits (Premium Rewards + new profile member badge); roadmap features removed from sale copy. `VType.scaled*` Dynamic Type variants added (check-in + paywall adopted). New VerdureTests target: 10 passing transaction-logic tests (double check-in/collect no-ops, fast double-redeem, proof spooling, queue persistence + v1 decode, reset). Firestore rules redeployed. Functions/Storage deploys still blocked on Blaze + console Storage setup.

- **2026-07-19** — **Server-authoritative points + personalization + Verdure+.** Points/check-ins/redemptions now go through Cloud Functions callables (`checkInToEvent`, new `collectPlace`, `redeemReward` w/ real REWARD_COSTS); GameStateManager applies earns optimistically and reconciles via a persisted pending-op queue (offline-safe, idempotent replays, legacy backfill on first connect). Firestore rules deployed with production lockdown (client writes to points/checked-in/redeemed denied; zero-on-create). FirebaseFunctions added to SwiftPM. Daily Gem reworked into a once-per-day fun-fact splash (generic nature/community/environment facts, no repeats until pool exhausts — `DailyGemStore`). New "For You" personalized events section (interest→event-category mapping + in-app interest picker). Paid events removed (Ticketmaster/SeatGeek providers off; Eventbrite/Localist filtered to free). Verdure+ subscription via StoreKit 2 (`StoreService`, clay `PaywallView`, `Verdure.storekit` scheme config; Gold/Platinum reward tiers gated). VoiceOver pass on check-in, redeem, and onboarding flows.

- **2026-06-17** — **Verdure rebrand + full visual overhaul.** Complete rename Connectify → Verdure (project, target, scheme, bundle id `com.vaiybhav.verdure`, source folder, all symbols/strings). New "Warm Forest" claymorphism design system (`VerdureTheme` + `ClayKit` + `ClayMotion`), Fredoka/Rubik bundled fonts, real SceneKit 3D compass-leaf medallion, clay floating tab bar, and every screen rebuilt in clay (light + dark). New app icon from the compass-leaf logo. Old neon/"Bio" component library removed.
