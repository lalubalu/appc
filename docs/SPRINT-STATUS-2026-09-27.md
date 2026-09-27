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
  Onboarding and the interest picker now sync declared interests to Firestore,
  which closes a prior gap where the server ranker could not see those choices.
- D's typography, radius, depth and accent tokens landed in `c8ef3cb` before
  the new views. E has five tabs, mutual friend requests, invite links/QR,
  adult-only exact username lookup and accepted-only social activity. Friends
  has an honest zero-friend state. The active website has a local invite page.
- F now has an options-first Plan UI backed by a server session. The ranker
  selects real candidate documents; the model can only sequence verified IDs,
  and a deterministic fallback serves the same verified IDs when the model key
  is unavailable. Refinements stay in the same session without a model call.
  The date option now opens a calendar picker and filters verified candidates
  to that local day, as the brief specifies.
  Monthly free-plan quota is transactional; model cost is counted in treasury.
  Emulator acceptance checks cover profile difference, no invention and
  repeat avoidance. The actual model path still needs a configured key and
  review on a populated index.
- G1 stores private age band, optional student status and school, with a
  student ranking boost. G2's Opportunity labels and G3's organizer event
  attributes (age, size, setting, accessibility, venue, deadline) are local.
  C9 adds an optional youngest-child household setting, a family ranking lift
  and age/late-ending warnings where event metadata supports them. App and
  website privacy copy was updated for these fields. Volunteer filters stay
  hidden until 30 upcoming listings with coordinates fall within the chosen
  radius. Four G4 organizations were fingerprinted read-only; findings and
  the prepared Idealist inquiry are in `VOLUNTEER-SUPPLY-2026-09-27.md`.
- I2/I3 copy audit found the active website selling deferred offline maps and
  AR and showing an obsolete $39.99 yearly price. The local pricing source,
  metadata and structured data now match the iOS paywall's existing $49.99
  yearly plan and four built benefits. App Store listing copy now matches the
  paywall's Advanced Stats benefit. No website deployment was made.
- I1 now has server-verified Verdure+ interest profiles, active-profile ranking,
  distance presets, permanent category exclusions and saved filter sets.
  Discover and Plan can open the profile switcher. Free accounts keep the one
  implicit profile and their ranked feed. The fifth Plus benefit was added
  only after the profile-switch ranking test passed.
- C11 now records server-scored For You slates and visible-card impressions,
  including rank position, contributing terms and ignored/tap/save/RSVP/dismiss
  outcomes. Clients cannot forge a slate entry or read/write the telemetry
  collection directly. Group plans (H) use verified Plan-session events,
  private invitations to accepted friends, shortlists and independent RSVPs.

## Verification

- iOS Simulator Debug build: passed after the current iOS changes. The iOS
  unit suite passed after updating its paywall-benefit count from four to five.
  The separate simulator UI suite stalled before any UI test result appeared;
  it was interrupted after roughly three minutes, so UI automation is unverified.
- Functions TypeScript build: passed.
- Ranking units: **49 passed, 0 failed**; planner units: **8 passed, 0 failed**.
- Backend emulator E2E: **328 passed, 0 failed**, including group invitations,
  shortlist votes, telemetry opt-out and access revocation.
- Red team: **49 attacks blocked, 0 vulnerable** after the feedback addition.
- All Functions unit suites passed; active website tests and production build
  passed after the invite and pricing changes.
- Computer inspected Discover For You and reopened Verdure to its Daily Gem
  screen on iPhone 16 Plus. Further taps returned `noWindowsAvailable`, so
  the full interactive visual sweep remains unverified. The saved Plan capture
  in `DESIGN-REFRESH.md` predates the new date picker and server results.

## Open completion gates

| Scope | Still needed |
| --- | --- |
| A/B | Populate live events; re-run coverage and record the delta; assess County Parks/volunteer structured access; verify duplicate rate under 5% against live cycles. The required City and County path probes are recorded, and six new sources are configured. |
| C0/P2 | Named human reviewer for all 200 sampled classifications, category accuracy and fixes; review a populated-corpus backfill dry run before writing it live. |
| P3/C1 | Measure full Firestore reads against a populated index, including user context, client reads and index entries, before enabling the feed at scale. |
| C3/C10/C11 | Full radius and filter behavior against a dense corpus; named reviewer and 20-profile golden set; live measurement of impression/outcome coverage and cost. |
| D/E | Full screenshot and accessibility matrix, physical-device QA, and real installed-app invite round trip. The website invite page needs deployment before public links work. |
| F | Configure and exercise the actual model secret; review sequencing, sponsor trust and session spend against a populated index. Emulator tests prove the verified-ID fallback and session mechanics. |
| G | At least 30 live local volunteer listings before surfacing that subtype; the Volunteer chip is hidden below this threshold. Partner/API access and Idealist application remain; any post-freeze source addition requires a renewed classification audit. |
| I/H | Profile and group-plan controls need device QA and a real two-phone invite test. Offline packs and AR stay deferred and are no longer advertised. |
| Legal/web alignment | Have the owner review the active website's legacy policy, which still lists phone, billing and shipping data and under-16 language was locally corrected to under-13. Resolve the app/listing `verdure.app` URLs versus the `verdure-app.com` website before publishing either. |

The sprint is **not complete**. The table separates engineering still to do
from the required live corpus, named human review, device QA and external
accounts/partners. No unmeasured ranking or coverage claim is treated as a
release pass.
