# Verdure sprint status — 2026-09-27

This is the **Verdure iOS app** in the directory named `Connectify App-iOS`.
The source is the 584-line “Verdure — Next Sprint” brief supplied for this
week. No production deployment, billing upgrade, Apple Developer action or
environment switch has been performed. `CLAUDE.md` deploy status is untouched.

## Built locally

- A1 coverage measurement ran first: the live `/events` collection has zero
  documents. See `COVERAGE-SAN-JOSE.md`. A2 now says Sports & Outdoors.
- B source list was widened and committed before C0 tuning in `462c0a1`:
  SCU LiveWhale, four libraries and City Legistar. Fingerprints and source
  probes are recorded in `FEED-SURVEY-SAN-JOSE.md`.
- C0 classifier and event enrichment run on ingest. Resumable dry-run-first
  backfill, low-confidence CLI and a 200-row stratified reviewer sample exist.
  The human audit is still unreviewed; see `CLASSIFICATION-AUDIT.md`.
- P3's read model is in `READ-BUDGET.md`. The server merges bounded time,
  quality and category candidates into a five-minute shared area cache;
  accepted friends' RSVPs enter separately. Treasury counts candidate query
  returns. The client limits its first feed to 80, and Everything pages 40
  events at a time. Live cost validation remains open with the empty corpus.
- C2 uses a curated interest synonym map. Discover offers For You and
  Everything. Ranking now uses quality, saved events, attended categories and
  organizers, mutual friends, timing, 90-day decaying feedback and a labelled
  exploration slot. Event details offer More like this and Less like this.
  `rank-eval.mjs` is ready for the 20-profile human golden set; no human
  relevance labels have been invented.
- D's typography, radius, depth and accent tokens landed in `c8ef3cb` before
  the new views. E has five tabs, mutual friend requests, invite links/QR,
  adult-only exact username lookup and accepted-only social activity. Friends
  has an honest zero-friend state. The active website has a local invite page.
- F has an options-first, real-event Plan UI with swap/remove, ranked order,
  friend-going hints and RSVP access. It does **not** yet have the server model
  session, model quota/refinement flow or three required acceptance tests.
- G1 stores private age band, optional student status and school, with a
  student ranking boost. G2's Opportunity labels and G3's organizer event
  attributes (age, size, setting, accessibility, venue, deadline) are local.
  App and website privacy copy was updated for birth year/student collection.
- I2/I3 copy audit found the active website selling deferred offline maps and
  AR and showing an obsolete $39.99 yearly price. The local pricing source,
  metadata and structured data now match the iOS paywall's existing $49.99
  yearly plan and four built benefits. App Store listing copy now matches the
  paywall's Advanced Stats benefit. No website deployment was made.

## Verification

- iOS Simulator Debug build: passed after the current iOS changes.
- Functions TypeScript build: passed.
- Ranking units: **48 passed, 0 failed**.
- Backend emulator E2E: **301 passed, 0 failed**.
- Red team: **49 attacks blocked, 0 vulnerable** after the feedback addition.
- All Functions unit suites passed; active website tests and production build
  passed after the invite and pricing changes.
- Computer inspected the Discover For You screen on iPhone 16 Plus. The
  remaining interactive visual sweep was interrupted by Simulator window
  timeouts. Existing screenshots are in `DESIGN-REFRESH.md`.

## Open completion gates

| Scope | Still needed |
| --- | --- |
| A/B | Populate live events; re-run coverage and record the delta; complete County Parks/volunteer supply and required City probes; verify duplicate rate under 5% against live cycles. |
| C0/P2 | Named human reviewer for all 200 sampled classifications, category accuracy and fixes; review a populated-corpus backfill dry run before writing it live. |
| P3/C1 | Measure full Firestore reads against a populated index, including user context, client reads and index entries, before enabling the feed at scale. |
| C3/C9/C10/C11 | Full radius and filter behavior against a dense corpus; household preferences and warnings; named reviewer and 20-profile golden set; impression/outcome instrumentation. |
| D/E | Full screenshot and accessibility matrix, physical-device QA, and real installed-app invite round trip. The website invite page needs deployment before public links work. |
| F | Server assembly from real ranked event IDs, bounded model session/refinements, quota accounting, three acceptance tests and session spend telemetry. |
| G | At least 30 live local volunteer listings before surfacing that subtype; partner/API access and Idealist application; source audit after any post-freeze additions. |
| I/H | Plus interest profiles and saved filters, then group planning. Offline packs and AR stay deferred and must not be advertised. |
| Legal/web alignment | Have the owner review the active website's legacy policy, which still lists phone, billing and shipping data and under-16 language was locally corrected to under-13. Resolve the app/listing `verdure.app` URLs versus the `verdure-app.com` website before publishing either. |

The sprint is **not complete**. The table separates engineering still to do
from the required live corpus, named human review, device QA and external
accounts/partners. No unmeasured ranking or coverage claim is treated as a
release pass.
