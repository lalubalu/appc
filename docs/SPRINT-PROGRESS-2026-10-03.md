# Completing the product — execution and evidence

Scope: [the complete attached sprint](SPRINT-SCOPE-2026-10-03.txt). This tracker
does not replace or narrow its requirements. Work remains on
`codex/rishit-handoff-2026-09-27`. No deployments, production writes, billing
changes, environment flips or key rotations. `ranking.ts` weights, signals and
synonym map remain untouched; `CLAUDE.md` deploy status remains untouched.

## Requirement ledger

| Item | Required outcome | Current evidence |
| --- | --- | --- |
| D1 | Internship → Program; source-metadata mappings; fixed-input before/after confidence overall/per source/reason; regenerated 200-row sample; finishing commit and classifier freeze | Code/measurement/sample verified: 12,165 fixed inputs; 32.77% → 11.68%; 200 rows with blank human labels. 274 Functions units and 103 iOS units passed. Freeze commit pending. See CLASSIFICATION-AUDIT.md. |
| A1 | No partners in organic For You/Everything; allowed map/near_you surfaces; regression | Pending |
| A2 | Distinct partner map pins; per-user persistent default-on toggle; detail/distance/dismissal | Pending |
| A3 | One walking-distance/time-appropriate Discover card; When-In-Use only; persistent dismissal; no far fallback | Pending |
| A4 | Nearby default rewards sort with location; existing fallback | Pending |
| A5 | One partner alert per RSVP; event venue proximity; shared weekly cap/quiet hours/preference; emulator proof | Pending; physical push excluded by scope |
| A6 | Opt-in adult-only live promotional alerts; consent/Always toggle; nearest 20 regions; shared cap/privacy | Pending; optional, no cut decision yet |
| B0 | Firebase admin claim CLI only; every endpoint server-gated; immutable admin-only before/after audit; red-team per path | Pending |
| B1 | Contextual moderation queue/history/filters/age, >20h highlight; reason-required remove/restore/warn/suspend | Pending |
| B2 | Organizer approval/rejection reasons, 50-cap used/remaining | Pending |
| B3 | Geocoded partners; activation requires recorded agreement; perks 500–2,000; CSV duplicate checks/counts; stock <10; immediate deactivation with reason | Pending |
| B4 | Support/organizer/merchant submissions; handled status/note | Pending |
| B5 | Per-source ingestion failures/last success/count; duplicate rate; queue age; organizer count; treasury/planner/SerpApi spend | Pending |
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
Test-host emulator isolation must be fixed before further iOS testing. This is
an observed local test defect, not a successful production write/deploy claim.
