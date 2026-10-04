# Completing the product — execution and evidence

Scope: [the complete attached sprint](SPRINT-SCOPE-2026-10-03.txt). This tracker
does not replace or narrow its requirements. Work remains on
`codex/rishit-handoff-2026-09-27`. No deployments, production writes, billing
changes, environment flips or key rotations. `ranking.ts` weights, signals and
synonym map remain untouched; `CLAUDE.md` deploy status remains untouched.

## Requirement ledger

| Item | Required outcome | Current evidence |
| --- | --- | --- |
| D1 | Internship → Program; source-metadata mappings; fixed-input before/after confidence overall/per source/reason; regenerated 200-row sample; finishing commit and classifier freeze | Complete at `d4b7150`: 12,165 fixed inputs; 32.77% → 11.68%; 200 rows with blank human labels. 274 Functions units and 103 iOS units passed. Hash guard records frozen classifier/source mappings. See CLASSIFICATION-AUDIT.md. |
| A1 | No partners in organic For You/Everything; allowed map/near_you surfaces; regression | Implemented locally; allowed surfaces and organic-feed regression: 16 focused checks. See PARTNER-SURFACES-2026-10-04.md. |
| A2 | Distinct partner map pins; per-user persistent default-on toggle; detail/distance/dismissal | Implemented locally; default-on per-user toggle, distinct pins/detail, dismissal; scoped simulator control/audit checked. Full active catalog now paged beyond 500 and stationary pins invalidated by safe public metadata. 25 connected catalog/listener checks and an actual iOS SDK invalidation/expiry test passed. |
| A3 | One walking-distance/time-appropriate Discover card; When-In-Use only; persistent dismissal; no far fallback | Implemented locally; 800 m, server local-time rules, one session slot, dismissal and hour expiry; focused checks. Stationary card invalidation, real timed expiry and account clearing tested with SDK listeners. Physical venue QA pending. |
| A4 | Nearby default rewards sort with location; existing fallback | Implemented locally; 107 iOS units include distance/fallback/tie behavior; scoped Rewards UI checked. 502-fixture Rewards catalog returned in full. Rewards cache invalidation remains to audit; server redemption rechecks availability. |
| A5 | One partner alert per RSVP; event venue proximity; shared weekly cap/quiet hours/preference; emulator proof | Implemented and locally checked: 19 RSVP-job checks, atomic shared budget and once-only notice; device push explicitly untested/excluded. |
| A6 | Opt-in adult-only live promotional alerts; consent/Always toggle; nearest 20 regions; shared cap/privacy | Pending; optional, no cut decision yet |
| B0 | Firebase admin claim CLI only; every endpoint server-gated; immutable admin-only before/after audit; red-team per path | Implemented locally: claim CLI, canonical Auth server checks, immutable audits for reads/mutations and intent/outcome for long jobs. 29 access checks and 12 legacy-job checks; see STAFF-CONSOLE-2026-10-04.md. |
| B1 | Contextual moderation queue/history/filters/age, >20h highlight; reason-required remove/restore/warn/suspend | Implemented locally: 19 server workflow checks, 14 pagination/601-report checks, browser removal/restoration and >100 rows. Detailed reports show a bounded preview plus all reasons/count. |
| B2 | Organizer approval/rejection reasons, 50-cap used/remaining | Implemented locally: 20 server checks including concurrent final-slot approvals; browser approval/cap and >100 application rows. |
| B3 | Geocoded partners; activation requires recorded agreement; perks 500–2,000; CSV duplicate checks/counts; stock <10; immediate deactivation with reason | Implemented locally: 47 management checks and browser geocoded partner/perk/CSV/deactivation/map proof. Agreement and price/stock constraints enforced server-side. Stationary map/card invalidation verified; Rewards and other sponsored caches remain to audit. No real business activated. |
| B4 | Support/organizer/merchant submissions; handled status/note | Implemented locally: 43 browser/server/database checks, canonical Firebase authorization for all 3 actions, Supabase immutable read/mutation audits and rollback proof. See WEBSITE-SUBMISSIONS-2026-10-04.md. |
| B5 | Per-source ingestion failures/last success/count; duplicate rate; queue age; organizer count; treasury/planner/SerpApi spend | Implemented locally: persistent source failures/history, full current supply/duplicate heuristic, aggregated queues, recorded spend estimates. 14 server checks and actual adapter failure visible in browser; invoice reconciliation is not claimed. |
| C1 | Separate weekly official place pipeline; licenses recorded before ingestion; geometry joins; loud console-visible failures | Backend implemented locally: five permission-checked sources, Tuesday schedule, complete atomic catalog, exact geometry/hole joins, source health and actual browser outage/recovery. 59 new units + 33 pipeline/browser checks; 5,507 real usable features read back with every geometry checksum. Native coordinate joins and public park-week events are now integrated with C2; see PARK-GUIDE-2026-10-04.md as well as PARK-PIPELINE-2026-10-04.md. |
| C2 | Free parks: confirmed amenities/ages/events/trails/story/hours/access/status; filters; required attribution | Online guide implemented and locally checked: signed-out/free access, geometry joins, status-labelled amenities, published ages/access/entrances, park-week events, attribution and shared filters. 80 park units, 29 actual callable checks, 7 focused native checks plus earlier 12 filter regressions. F1 story integration and full device gates remain pending. See PARK-GUIDE-2026-10-04.md. |
| C3 | Free source-backed trail attributes/overlays/location; official closure link/notice; no navigation | Online overview implemented locally: source attributes and lossless MapKit overlays, user annotation/recenter control, parent/trail status, notice and official closure link. Real County source flow passed in Simulator and screenshot inspected. Physical/outdoor GPS and offline-pack behavior remain pending with G/C4. No cut. |
| C4 | Plus server entitlement; park/set/area packs; events/thumbnails/places/saves/plans/view-only perks; size preview/hard cap; storage/delete/age; Wi-Fi refresh/7-day expiry; offline overlays/location; no offline writes/check-in/base imagery caching | Implemented locally: server-gated private chunks, exact size preview and 50 MB cap, full snapshots and compressed thumbnails, native account-isolated storage/delete/expiry, Wi-Fi replacement, stored guides/trails/events, online-action refusal and legacy attendance-queue removal. 24 offline units, 32 callable/rules/content/cleanup checks and actual native SDK/UI flows passed. Physical airplane-mode/moving GPS gates remain required with G. See OFFLINE-PACKS-2026-10-04.md. |
| C5 | Working-feature paywall/listing/website copy: offline park and place packs | Included in the same working feature change, with seven-day/no-base-imagery explanation and matching privacy/App Privacy notes. Fresh website build/lint and 18 production-page/copy-parity checks passed. No publication. |
| D2 | Existing supply audit; nine volunteer source fingerprints/terms; deduplicated in-radius count >=30; document exclusions | Minimum local supply and full native threshold verified: 137 classified current public listings in 25 miles, conservative 80 direct-service invitations; 53 classified within 30 days. All nine hosts fingerprinted and dispositions recorded. Native full-supply/29-vs-30 SDK checks passed. New-source permission/venue evaluation remains explicitly pending (including Save The Bay); no silent cut. See VOLUNTEER-SUPPLY-2026-09-27.md. |
| D3 | Program taxonomy/client; staff curation with required age/cost/location/deadline/official link; >=10 radius threshold; age eligibility and deadline expiry; link-out only | Implemented locally: 34 policy units, 42 actual callable/rules/security checks, 8 actual staff browser checks, canonical age/deadline filtering without ranking tuning, full native supply/account/deep-link checks and a passing Program UI/accessibility journey. Saved eligible Programs work in private offline packs and open details recheck age/expiry. See PROGRAM-CURATION-2026-10-04.md; physical/final gates remain pending. |
| E1 | Neutral signup age gate; under-13 exits without retaining personal data; preserve 13–17 protections | Implemented locally: neutral blank birth year before account fields, under-13 ends/clears volatile draft, signup age guard precedes credential processing, existing registerAgeBand unchanged. Two actual signup UI flows plus age boundary/persistence units passed. |
| E2 | Local terms/support pages and restored app link; Supabase support → console; accurate privacy | Implemented locally: build plus 15 production-page/parity checks, 43 submission checks, Swift Terms URL resolves HTTP 200 against explicit local website. Public publication remains outside this sprint. |
| E3 | Organizer/calendar and merchant interest forms; Supabase → console | Implemented locally: both native browser forms save exact fields in real local Supabase and appear in staff inbox; no partner activation from interest. 43 checks passed. |
| F1 | Approved place-owner-only <=400-char stories; report/moderation; shown/read engagement | Pending; optional, no cut decision yet |
| F2 | Optional free beta camera/GPS/compass view; permission only on open; no frames saved/transmitted; matching privacy; no pricing claim | Pending; optional, no cut decision yet |
| G1 | Free-team installs on two real iPhones; local populated emulator via DEBUG opt-in | Pending; no hardware evidence collected |
| G2 | Full DEVICE-QA and all sprint additions, outdoor offline trail/GPS test, two-phone flows, a11y/network/power/performance/StoreKit | Pending |
| G3 | Dated device/iOS/item results; defects fixed/regressed; committed; membership/deploy-dependent behavior explicitly untested | Pending |
| H1 | All app/backend/console compound queries inventoried and mapped to matching indexes with locations; missing indexes added; undocumented-query regression check | Complete locally: 109 source variants (37 compound mappings, 72 simpler queries), 92 distinct shapes; nine composite definitions and four group overrides added. Source-aware guard runs in backend CI and test:units; 49 positive/negative checks plus 424 existing backend checks passed with a fresh build and D1 freeze check. See FIRESTORE-INDEXES.md and docs/evidence/firestore-index-audit-2026-10-04.json. No indexes deployed or live readiness inferred. |
| H2 | Crashlytics integration/symbol upload; physical readable test crash; accurate privacy/App Privacy in same change | Pending |
| Final gate | Fresh iOS/backend unit/E2E/red-team checks green; every scope item audited; no deploy/status change | Pending |

## Evidence discipline

Current baseline is inspected source and a fresh TypeScript build, not the
older sprint's reported test counts. Classification capture/replay reads only
public feeds; the immutable response snapshot makes confidence deltas
re-runnable without moving input data. Confidence is not human accuracy.

Device gates remain required. No simulator result will be recorded as physical
GPS, two-phone, crash delivery or outdoors/airplane-mode proof.

The first fresh iOS unit run passed 103 tests, but its host attempted analytics
writes against the configured Firebase project (refused permission-denied).
Test-host emulator isolation was then fixed: 107 fresh iOS units passed with local Firestore/Auth/Functions/Storage startup and remote push skipped. This is
an observed local test defect, not a successful production write/deploy claim.

## October 4 local checkpoint

Staff console browser/server workflow: 23 passed. Backend gates on a fresh,
separate emulator: 286 units, 337 end-to-end, 49 attacks blocked. Website build,
typecheck/lint and existing IP/security checks passed. Evidence and exact reruns
are in STAFF-CONSOLE-2026-10-04.md. A reused working-emulator broad run failed
16 fixture-collision checks; the isolated runner resolves that test setup issue.

Remaining software work includes Rewards/other sponsored cache correctness and A6;
C2 story integration and C4/C5 offline work; D2/D3 curation/supply; F stories/optional explore;
H1 inventory and H2 Crashlytics. No optional feature has been silently cut.
Physical two-phone and outdoor offline GPS/crash gates remain required.
The full sprint and final gate are still incomplete.

## October 4 continuation checkpoint

- Partner catalogue and invalidation: Functions fresh build and 286 units;
  25 catalogue/live-listener checks; 47 partner-management regressions;
  108 iOS units including real SDK invalidation/expiry before the age changes.
- Submissions: 43 actual browser/server/Supabase checks; fresh pending migration
  replay in a rollback transaction, NULL accountability rejection and zero local
  security-advisor findings. Data and secrets stay local/server-side.
- Website: fresh production build, lint, 39 IP and 47 existing security checks;
  15 legal/production-page checks, including cold production hydration and
  exact app/website document parity. Development cold hydration stalls observed
  earlier remain unexplained; a clean warmed development run passed.
- iOS: fresh 112 passed / 0 failed / 0 skipped (110 units plus two signup UI
  paths) at `Test-Verdure-2026.10.04_02-52-52--0700.xcresult`; subsequent
  13 focused core/UI checks included the connected local Terms link, followed
  by a fresh focused rerun of that link. See the website evidence document.

No physical-device, outdoor GPS, production index, push delivery, purchase or
crash-report proof is implied by these local results.

## October 4 park-pipeline checkpoint

- Permission was recorded before capture. Five official sources returned
  5,510 public features; 5,507 have usable geometry. Three null trail geometries
  are surfaced in source health. One City zero-area component is explicitly
  normalized, with its valid polygon retained and the change recorded.
- The complete catalog was published only to the local Firestore emulator and
  fully read back with all geometry checksums verified. Atomic publication
  prevents incomplete downloads from replacing the catalog. Old concurrent
  runs cannot erase newer failures or results.
- New park checks: 59 units and 33 pipeline/browser checks passed, including
  actual staff-screen outage/prior-success/recovery, direct SDK rules and
  multi-chunk lossless geometry. The browser's mobile layout was inspected.
- Fresh isolated backend gates: 345 units, 337 end-to-end checks, 49 attacks
  blocked. Website production build and lint passed.
- C1 backend scheduling, normalization, source-health and geometry helpers are
  implemented. Native geometry connection, C2–C5 and all other pending rows
  above remain part of the full sprint. No scope has been cut or redefined.

See PARK-PIPELINE-2026-10-04.md for exact reruns, source/permission limits,
counts and evidence. Neither native/device park behavior nor deployment has
been claimed.

## October 4 park-guide checkpoint

- The real local catalog now includes a checksummed compact 651-park index.
  Public/free guide callables preserve holes/islands, source status and all
  pages; park-week events are joined by coordinates, with privacy/age/block
  filtering. No extra collectible IDs or point awards were added.
- Native Discover/Map/Collection use confirmed amenity filters. Existing place
  detail connects to guides by geometry and no longer invents hours, amenities
  or accessibility. The trail view draws original source lines and boundaries,
  includes attribution/notice/official link, and has no route guidance.
- Fresh backend: 366 units, including 80 park checks and the unchanged D1 freeze;
  29 new callable checks; 28 pipeline regressions. Fresh focused native: 7/7
  with no skips, including real-source SDK and actual UI flows. Screenshots were
  inspected and are saved under docs/evidence. These are local results only.
- A device inventory found one registered iPhone 16 Pro Max marked unavailable;
  no two-phone install or outdoor run was performed. Hardware availability was
  requested while software work continued.
- C4/C5, D2/D3, F1/F2, A6, remaining partner-cache audit, H1/H2 and G/final gates
  remain in the full scope. C2's F1 story field is not yet implemented. Nothing
  was cut, deployed or represented as complete without evidence.

## October 4 offline-pack checkpoint

- Paid/free/other-account actual callable paths, direct client SDK staging rules,
  exact download size/hash, selection geometry, authorized saves/plans, compressed
  image bytes, view-only perks, subscription/staging expiry and bounded cleanup
  are checked locally. The final focused pack run passed 32 checks. Public
  guide regression passed 29.
- Native actual Firebase SDK tests verify full download, private file storage,
  backup exclusion, reopening, corruption/owner/expiry rejection, deletion,
  account cleanup, offline-action refusal and successful Wi-Fi replacement.
  The latest full native snapshot passed 122 tests with no failures or skips.
  The expanded journey separately covers stored-event refusal, source trail
  overlay, accessibility audits and storage deletion.
- Broad backend snapshot: 390 units, 337 end-to-end, 49 attacks blocked. The
  later bounded staging-cleanup adjustment has separate fresh 32-check evidence.
  Final whole-sprint gates remain pending after the other sections.
- Paywall, listing, website pricing and identical app/website privacy changed
  with the feature. Website production build/lint and 18 page/parity checks
  passed. Simulator screenshots were inspected; they include system imagery,
  and the DEBUG offline preflight is not physical airplane-mode proof.
- C4's physical/outdoor gate, D2/D3, F1/F2, A6, remaining partner-cache audit,
  H1/H2, G and final acceptance remain in scope. No optional cut or deployment
  has been made. See OFFLINE-PACKS-2026-10-04.md and docs/evidence.

## October 4 Program checkpoint

- Staff creates, edits and deactivates official Program listings with required
  facts, canonical admin authorization and immutable audits. Programs have no
  attendance points, RSVP, invitations, group outings or park-week event slots.
- Eligibility is checked against canonical account age, visibility and deadline
  after existing ranking, before telemetry, and in the independent complete
  Program supply query. Ten unique current eligible listings in radius are
  required for the chip; account changes fail closed.
- Fresh isolated backend: 424 units, 337 end-to-end checks, 49 attacks blocked.
  Additional actual Program 42 and offline 35 checks passed. Staff browser: 8.
  Website build/lint/typecheck and 18 legal/production-page checks passed.
- Native: 123 full units passed; the combined attempt's UI failure is retained
  honestly. The corrected Program UI separately passed, followed by the new
  offline deadline/age unit and the actual offline download/trail/storage UI.
  Both fixture scripts were cleaned after verification. Screenshots inspected.
- D3 software is locally implemented; D2 supply, F1/F2, A6, remaining partner
  caches, H1/H2, physical G and final acceptance remain required. The current
  working emulator has been found to contain test remnants rather than the
  complete public corpus; a configured-public-source refresh and deduplicated
  volunteer audit are now in progress. No silent cut, production write or
  deployment occurred. See PROGRAM-CURATION-2026-10-04.md.

## October 4 volunteer-supply checkpoint

- The configured public source refresh completed all six adapters, using the
  frozen classifier and actual deduplicating store. Source outcomes and actual
  persisted Volunteer IDs are committed as re-runnable evidence. The earlier
  test-only working corpus is no longer mistaken for the real public supply.
- Current 25-mile supply: 137 classified public listings, 53 within 30 days.
  A conservative invitation-evidence subset verifies 80 direct-service listings,
  including 36 within 30 days. Four apparent classification false positives and
  53 service-group/orientation records are excluded from that lower bound.
  Description digests prevent changed facts from inheriting a prior review.
- Native discovery now pages the whole public Volunteer supply independently
  of the first 80 chronological cards. A fresh four-test connected run passed
  full public IDs, 29/30 threshold edges and Program account/eligibility regressions.
  The new query's index definition is local; H1 and production deployment are
  not inferred from the emulator pass. Fictional Program fixtures were cleaned.
- All nine requested organization fingerprints and permission dispositions are
  recorded. Save The Bay's real feed requires reuse/precise-venue follow-up;
  several other permissions or supported feeds remain unverified. These source
  tasks remain pending, rather than being quietly cut after meeting the minimum.
- F1/F2, A6, remaining partner caches, H1/H2, physical G and final acceptance
  still remain. No ranking/classifier drift, deployment or optional cut occurred.

## October 4 Firestore-index checkpoint

- H1 inventories current native Swift, Functions, website-console server paths
  and four operational scripts. Alias builders, status/filter branches, finite
  collection selectors and the offline paging helper are included. Conservative
  builder prefixes are documented explicitly; these counts do not claim 109
  separate executed queries.
- Added nine composite definitions and four collection-group overrides. The
  previously missing follower-event, invite cleanup and account-deletion group
  mappings are covered alongside the ranking, ingestion and console queries.
- The guard verifies source locations/shapes against the documentation and
  actual index fields/scope/direction/array modes. Unknown syntax fails closed.
  Temporary-fixture tests prove new backend/Swift files, Web SDK queries and
  operational scripts cannot silently bypass inventory; missing definitions and
  undocumented changes are rejected. Output is deterministic across locales.
- Fresh TypeScript build and all 424 existing backend checks passed; the 49
  index-guard cases passed both in the full command and the final focused run.
  D1's six-file freeze passed. CI is configured to run the guard; no remote CI
  run or live index deployment was performed. Logs and source digests are saved.
- Remaining partner caches, F1/F2, A6, D2 permission/venue follow-up, H2,
  physical G and final whole-sprint acceptance remain in scope. Nothing was cut
  or deployed. The full sprint remains incomplete.
