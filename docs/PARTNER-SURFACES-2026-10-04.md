# Location-based partner surfaces: local evidence

D1 remains frozen at `d4b7150`; `ranking.ts` is unchanged. A1–A5 are implemented.
The full sprint is still incomplete; the requirement ledger retains B–H and
the optional features. No deploy, billing, environment or key changes occurred.

## Behavior

- Organic For You and Everything query only events; partner cards use a separate
  payload. `events_feed`, `for_you`, `everything` and social surfaces are refused.
- Map partners use ink storefront pins with a gold border, a default-on per-account local toggle,
  offer details, estimated walking time and remembered server dismissal.
- Near you claims at most one card per app session, within 800 metres. Server
  time controls coffee/morning, food/mealtimes and activities/weekend rules.
  Both location endpoints enforce proximity; there is no distant fallback.
  Cached cards expire at the server's hour boundary and disappear if refreshed
  data no longer includes the offer. Only existing When-In-Use GPS is used.
- Rewards defaults to Nearby when actual GPS exists, preserves the original
  order without GPS, sorts unknown coordinates last, and preserves ties.
- Offer visibility requires an active partner, recorded agreement, valid price,
  future expiry and stock (sold-out offers remain visible in Rewards).
  Emulator fixtures name entirely fictional businesses and record fixture-only
  agreement references. Staff creation/CSV/deactivation tooling is implemented locally; see STAFF-CONSOLE-2026-10-04.md.
- RSVP alerts are queued atomically with Going, using the venue location.
  They become due one hour before start, or immediately for a late RSVP.
  A 15-minute worker rechecks attendance, availability, opt-in and quiet hours.
  Cancelled/past events cannot notify. The notification, sent ledger and shared
  weekly slot commit together, so concurrent workers/retries cannot duplicate
  the in-app alert. Push is attempted once through the existing notifier after
  commit; a crash at that boundary can miss delivery, rather than resend it.
- RSVP offers default off with a separate server-backed preference. No new
  background-location permission or collection was introduced. A6 is pending.

## Re-run

From the repository root, build Functions, then start a separate terminal:

```sh
cd functions && npm run build
# From the repository root, in the service terminal:
node functions/scripts/sprint-emulators.mjs
```

The helper derives a gitignored local configuration from `firebase.json`.
It uses port 5002 for Functions and does not stop an unrelated port-5001 service.
`--lan` is for later physical-device QA only. Set the DEBUG user default
`QAUseFirestoreEmulator=YES` and `QAEmulatorHost` to the Mac's LAN address for
that phase; all four Firebase services use the same host.

From `functions/`, while those services run:

```sh
npm run test:units
FIRESTORE_EMULATOR_HOST=127.0.0.1:8899 node scripts/sprint-partners-e2e.mjs
FIRESTORE_EMULATOR_HOST=127.0.0.1:8899 node scripts/rsvp-partners-e2e.mjs
```

Observed: seven backend unit suites, 286 passed / 0 failed; focused partner
endpoint/feed checks, 16 passed; RSVP job checks, 19 passed. The Everything
check uses the app's area/date/visibility filters, ordering and page limit.
The RSVP checks include concurrent workers, retry, cancel/re-RSVP, cap sharing,
quiet hours, separate opt-out, distant venues and event expiry.

Fresh iOS unit results: 107 passed / 0 failed on iPhone 16 Plus, iOS 18.4
Simulator. Includes an assertion that the unit host's Firestore is local,
plaintext and memory-cached; Auth/Functions/Storage are routed locally in the
same startup branch, with remote-push startup skipped. This corrects the first
D1 unit host's denied production analytics attempts.

```sh
cd Verdure
xcodegen generate
xcodebuild -quiet -project Verdure.xcodeproj -scheme Verdure \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus' \
  -only-testing:VerdureTests \
  -only-testing:VerdureUITests/PartnerSurfaceTests \
  -only-testing:VerdureUITests/AccessibilityAuditTests/testAuditNotificationSettings test
```

Scoped simulator UI checks covered Rewards' Nearby fallback, notification settings and the map-layer toggle. The map audit passed with one narrowly recorded exception: MapKit's native Legal attribution link has a text-sized hit region. Full physical VoiceOver and the complete G script remain required. Live partner pin/card interaction on physical phones remains unverified. Push delivery, real purchases, universal links and cellular use against a local emulator remain explicitly untested.

Discovery currently queries only the first 100 active perks. A stationary cached pin/card also remains until its next fetch after server deactivation. Removing that limit and invalidating those caches remain follow-up work; server redemption and fresh surfaces already refuse inactive offers immediately.

The new RSVP compound-query index is present in `firestore.indexes.json`.
The complete query inventory/check required by H1 is still pending; emulator
success does not prove a live index exists.
