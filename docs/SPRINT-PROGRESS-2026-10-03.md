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
| A2 | Distinct partner map pins; per-user persistent default-on toggle; detail/distance/dismissal | Implemented locally; default-on per-user toggle, distinct pins/detail, dismissal; scoped simulator control/audit checked. Remaining: full discovery beyond 100 perks and immediate invalidation of stationary caches. |
| A3 | One walking-distance/time-appropriate Discover card; When-In-Use only; persistent dismissal; no far fallback | Implemented locally; 800 m, server local-time rules, one session slot, dismissal and hour expiry; focused checks. Same catalog/cache follow-ups as A2; physical venue QA pending. |
| A4 | Nearby default rewards sort with location; existing fallback | Implemented locally; 107 iOS units include distance/fallback/tie behavior; scoped Rewards UI checked. Complete catalog beyond 100 perks remains to fix. |
| A5 | One partner alert per RSVP; event venue proximity; shared weekly cap/quiet hours/preference; emulator proof | Implemented and locally checked: 19 RSVP-job checks, atomic shared budget and once-only notice; device push explicitly untested/excluded. |
| A6 | Opt-in adult-only live promotional alerts; consent/Always toggle; nearest 20 regions; shared cap/privacy | Pending; optional, no cut decision yet |
| B0 | Firebase admin claim CLI only; every endpoint server-gated; immutable admin-only before/after audit; red-team per path | Implemented locally: claim CLI, canonical Auth server checks, immutable audits for reads/mutations and intent/outcome for long jobs. 29 access checks and 12 legacy-job checks; see STAFF-CONSOLE-2026-10-04.md. |
| B1 | Contextual moderation queue/history/filters/age, >20h highlight; reason-required remove/restore/warn/suspend | Implemented locally: 19 server workflow checks, 14 pagination/601-report checks, browser removal/restoration and >100 rows. Detailed reports show a bounded preview plus all reasons/count. |
| B2 | Organizer approval/rejection reasons, 50-cap used/remaining | Implemented locally: 20 server checks including concurrent final-slot approvals; browser approval/cap and >100 application rows. |
| B3 | Geocoded partners; activation requires recorded agreement; perks 500–2,000; CSV duplicate checks/counts; stock <10; immediate deactivation with reason | Implemented locally: 47 management checks and browser geocoded partner/perk/CSV/deactivation/map proof. Agreement and price/stock constraints enforced server-side. Stationary iOS cache invalidation remains; no real business activated. |
| B4 | Support/organizer/merchant submissions; handled status/note | Pending |
| B5 | Per-source ingestion failures/last success/count; duplicate rate; queue age; organizer count; treasury/planner/SerpApi spend | Implemented locally: persistent source failures/history, full current supply/duplicate heuristic, aggregated queues, recorded spend estimates. 14 server checks and actual adapter failure visible in browser; invoice reconciliation is not claimed. |
| C1 | Separate weekly official place pipeline; licenses recorded before ingestion; geometry joins; loud console-visible failures | Pending |
| C2 | Free parks: confirmed amenities/ages/events/trails/story/hours/access/status; filters; required attribution | Pending |
| C3 | Free source-backed trail attributes/overlays/location; official closure link/notice; no navigation | Pending; optional, no cut decision yet |
| C4 | Plus server entitlement; park/set/area packs; events/thumbnails/places/saves/plans/view-only perks; size preview/hard cap; storage/delete/age; Wi-Fi refresh/7-day expiry; offline overlays/location; no offline writes/check-in/base imagery caching | Pending |
| C5 | Working-feature paywall/listing/website copy: offline park and place packs | Pending |
| D2 | Existing supply audit; nine volunteer source fingerprints/terms; deduplicated in-radius count >=30; document exclusions | Pending |
| D3 | Program taxonomy/client; staff curation with required age/cost/location/deadline/official link; >=10 radius threshold; age eligibility and deadline expiry; link-out only | Pending |
| E1 | Neutral signup age gate; under-13 exits without retaining personal data; preserve 13–17 protections | Pending |
| E2 | Local terms/support pages and restored app link; Supabase support → console; accurate privacy | Pending |
| E3 | Organizer/calendar and merchant interest forms; Supabase → console | Pending |
| F1 | Approved place-owner-only <=400-char stories; report/moderation; shown/read engagement | Pending; optional, no cut decision yet |
| F2 | Optional free beta camera/GPS/compass view; permission only on open; no frames saved/transmitted; matching privacy; no pricing claim | Pending; optional, no cut decision yet |
| G1 | Free-team installs on two real iPhones; local populated emulator via DEBUG opt-in | Pending; no hardware evidence collected |
| G2 | Full DEVICE-QA and all sprint additions, outdoor offline trail/GPS test, two-phone flows, a11y/network/power/performance/StoreKit | Pending |
| G3 | Dated device/iOS/item results; defects fixed/regressed; committed; membership/deploy-dependent behavior explicitly untested | Pending |
| H1 | All app/backend/console compound queries inventoried and mapped to matching indexes with locations; missing indexes added; undocumented-query regression check | Pending |
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

Remaining software work includes partner catalog/cache correctness and A6;
B4 with E forms; all C park/offline work; D2/D3 curation/supply; E age/privacy;
F stories/optional explore; H1 inventory and H2 Crashlytics. No optional feature
has been silently cut. Physical two-phone and outdoor offline GPS/crash gates
remain required. The full sprint and final gate are still incomplete.
