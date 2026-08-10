# App Store Connect submission pack — Verdure

Everything here is written to match what the app **actually does today**. If a
feature ships or is pulled, update this file in the same commit.

---

## Basics

| Field | Value |
|---|---|
| App name | `Verdure` |
| Subtitle (30 char max) | `Step Outside. Connect Within.` (29) |
| Bundle ID | `com.vaiybhav.verdure` |
| Primary category | Health & Fitness |
| Secondary category | Travel |
| Age rating | 4+ |
| Price | Free (with auto-renewable subscription) |

## Promotional text (170 char max — editable without review)

> Discover parks, trails and community events near you. Check in, earn points,
> and turn time outside into real gift cards. New seasonal rewards every month.

*(159 characters)*

> **Pending copy change — do not submit early.** A Verdure+ **1.25x earn
> multiplier** is implemented and server-enforced (`earnMultiplier` in
> `functions/src/index.ts`), and it is proven by the E2E suite. It is
> deliberately absent from both the description above and `PaywallView.features`
> because it cannot pay out until Cloud Functions are deployed *and* the Apple
> IAP secrets are set — and this repo's rule is that we do not sell a benefit
> that doesn't yet pay. Once both are true, add the line
> `• Bonus points — earn 1.25x on every check-in and collection`
> to the description **and** to `PaywallView.features` in the same commit, so
> the store listing and the in-app paywall can never disagree.

## Description

> **Step Outside. Connect Within.**
>
> Verdure turns your neighborhood into something worth exploring. Find the parks,
> trails, gardens and gathering places around you — then get outside and collect
> them.
>
> **Discover what's nearby**
> Real places from open map data and national park services, sorted by how close
> they are. Real community events with real dates and locations — never filler.
>
> **Collect the outdoors**
> Every place you visit becomes part of your collection, from Common city parks
> to Legendary scenic overlooks. Get close enough and it's yours.
>
> **Earn by showing up**
> Check in at community events to earn points. Attendance is verified with your
> location and a photo, so points mean something. Points become real gift cards.
>
> **Build a streak**
> Daily streaks, monthly challenges and badges that unlock from what you've
> genuinely done — no busywork.
>
> **A Daily Gem**
> One fun fact a day about nature, community and the environment. Small, but it
> gets you looking around.
>
> **Plan my adventure**
> Tell Verdure how long you've got and it builds you an itinerary — real places
> near you, ordered sensibly, shaped by the actual weather and the time of day.
> Every stop is a place that genuinely exists nearby; nothing is invented.
>
> **Verdure+ (optional)**
> $4.99/month or $49.99/year:
> • Premium Rewards — unlock the Gold and Platinum tiers ($25 and $50 gift cards)
> • Early Access — redeem limited-time seasonal drops up to a week early
> • Member badge on your player card
>
> Verdure is free to use. A subscription is entirely optional and never required
> to earn points or redeem the standard rewards.
>
> ---
> Location is used to find nearby places, to verify you're actually at an event
> when you check in, and for nothing else. We don't track you, and we don't sell
> your data.

## Keywords (100 char max, comma-separated, no spaces)

```
outdoors,parks,trails,hiking,walk,nature,community,events,local,explore,rewards,steps,adventure
```

*(94 characters)*

## Support / marketing URLs

| Field | Value |
|---|---|
| Support URL | `https://<domain>/support` — page built (`/support`) |
| Marketing URL | *(the Verdure Website in this repo, once deployed)* |
| Privacy Policy URL | `https://<domain>/privacy` — page built (`/privacy`) |

---

## Privacy nutrition label answers

These must match `Verdure/Verdure/PrivacyInfo.xcprivacy` exactly.

**Does your app collect data?** → **Yes**
**Do you use data for tracking?** → **No** (no ad SDKs, no analytics, no brokers)

| Data type | Collected | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| Precise Location | Yes | Yes | No | App Functionality |
| Email Address | Yes | Yes | No | App Functionality |
| Name | Yes | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality |
| Photos or Videos | Yes | Yes | No | App Functionality |
| Other User Content | Yes | Yes | No | App Functionality |
| Purchase History | Yes | Yes | No | App Functionality |
| Device ID | Yes | Yes | No | App Functionality |

Nothing else is collected — no contacts, health, browsing, search history,
diagnostics, or advertising data.

---

## App Review notes

> **Signing in**
> Create an account with any email on the sign-up screen, or tap "Continue as
> guest" to browse without one.
>
> **About check-ins (important for review)**
> Checking in to an event requires two things by design: being physically within
> 500 ft of the venue, and attaching a photo as proof of attendance. On a
> simulator or from a desk, check-in will correctly stay locked and show
> "Too far to check in" — this is intended anti-fraud behaviour, not a bug.
> To exercise the flow, use Xcode's location simulation to set a location at one
> of the listed event venues, then attach any photo.
>
> **About the subscription**
> Verdure+ unlocks the Gold/Platinum reward tiers, early access to limited-time
> drops, and a profile badge. Everything else in the app is free. The paywall
> lists only features that are live in this build.
>
> **About "Plan my adventure"**
> This builds an itinerary using a language model, but the model is only ever
> allowed to choose from a list of real nearby places the app has already
> fetched from public map/park data. Any place it returns that isn't on that
> list is discarded server-side, so the itinerary cannot contain invented
> locations. No user content is sent — only place names, categories and the
> current weather.
>
> **Location usage**
> Used for finding nearby places, the collection proximity check, and verifying
> event attendance. There is no background location and no tracking.

---

## Screenshot set

Captured at Apple's required 6.9" size (1320 × 2868) in `screenshots/6.9-inch/`:

| Order | File | Suggested caption |
|---|---|---|
| 1 | `events.png` | Real community events near you |
| 2 | `explore.png` | Discover the outdoors around you |
| 3 | `collect.png` | Collect every place you visit |
| 4 | `profile.png` | Streaks, badges and real rewards |
| 5 | `community.png` | See what your neighbors are finding |

*Regenerate:* boot the iPhone 16 Pro Max simulator and launch with
`-QATab <tab> -QADisableMotion YES -QAOfflineData YES` (see `QA.md`).

---

## Pre-submission blockers

- [x] **Privacy Policy page** — built at `/privacy` on the marketing site
- [x] **Support page** — built at `/support` (both linked from the footer)
- [ ] **Deploy the marketing site** so those two URLs actually resolve, then
      paste the live URLs into App Store Connect
- [ ] Create the two subscriptions in App Store Connect
      (`com.vaiybhav.verdure.plus.monthly`, `com.vaiybhav.verdure.plus.yearly`)
      with localized display names, and attach them to the app
- [ ] Upgrade Firebase to Blaze and deploy Functions + Storage — **without this
      no check-in ever credits points and no proof photo uploads** (see the
      DEPLOY STATUS table in `CLAUDE.md`)
- [x] Real gift-card fulfilment — **Tremendous integrated**
      (`functions/src/fulfillment.ts`): a trigger + 30-minute sweeper drain the
      `/fulfillments` queue, orders are idempotent on `external_id`, permanent
      failures refund the user's points, and anything $25+ waits for manual
      approval. **Still needs**: a funded Tremendous account and the three
      secrets (`TREMENDOUS_API_KEY`, `TREMENDOUS_FUNDING_SOURCE_ID`, and
      `TREMENDOUS_CATALOG` mapping reward ids to that account's product ids).
      Nothing sends until those exist — the queue simply holds.
- [x] Server-side Verdure+ verification — **done**
      (`functions/src/subscriptions.ts`): the App Store Server API writes
      `users/{uid}.plusExpiresAt`, App Store Server Notifications V2 keep it
      fresh, and ownership is bound via a uid-derived `appAccountToken`.
      **Still needs**: an In-App Purchase key (.p8) from App Store Connect and
      the ASSN V2 URL pointed at the deployed `appStoreNotifications` endpoint.
- [ ] **AI Adventure Planner**: set `ANTHROPIC_API_KEY` as a function secret.
      Until then the planner tile is visible but returns "isn't switched on yet".
- [ ] **Push notifications**: upload an APNs Auth Key (.p8) to Firebase → Cloud
      Messaging and add the Push Notifications capability to the App ID.
      Without both, permission is granted but nothing is ever delivered.
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) — done, ships in the bundle
- [x] Screenshots at a required size — done (6.9")
