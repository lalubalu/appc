# Verdure — CAC 2026 handoff: FINAL REPORT

Branch `cac-2026`. Work done 2026-10-24/25 on a **Windows machine with no Xcode**, against the
local Firebase emulators only. Every Swift change in this report is therefore **written and
reviewed but not compiled**, every iOS suite says **not run**, and there are **no screenshots**
— those three things need a Mac and are listed under "What is not perfect" with exactly what
to run. Nothing was deployed, pushed, purchased or flipped. No paid API was used.

The Mac's unpushed work the handoff describes (the first `adventure-engine.ts`, the interest
normaliser, `osm-snapshot-san-jose.json`, `planner-review.md`, the history purge and the
`cac-final*` tags) was **not available** here: the team remote `appc/cac-2026` ends at
`8fa3143` ("Mac verification: Overpass never answered overnight"). This clone was
fast-forwarded to that commit and every item below was built from there. When the Mac and
this branch meet, take this branch's versions of the files named below; they are complete and
tested, and the Mac's drafts of the same files were never pushed.

## Commits on this branch (in order)

| Commit | Item | Summary |
|---|---|---|
| `12d42fb` | 1.1 | For You personalized: labels understood, precise matching, interest retrieval, match-first order |
| `ca74814` | 1.2 | Adventure Planner works with no AI key: deterministic engine, hours, sunset, heat, rain |
| `2ab1dd6` | 1.3 | False "AI" claims removed from privacy policy, listing, StoreKit copy, comments |
| `3b95b85` | 1.4 | OpenStreetMap: mirror fallback, per-area cache, bundled snapshot, parallel start-up loads |
| `c238ad6` `cc0de18` `769c2dd` | 1.5 | Secrets out of the tree, scan gate, keyed providers tested, new-repo procedure |
| `a7ca6e1` | 1.7 / 1.2 | `run-all.command` and the planner UI test |
| (this report's commit) | 1.6 / 1.1 cause 5 | E2E planner checks, Google-Maps intake fix, acceptance reasons check, discovery recording, final numbers |

---

## 1.0 Recover and reload

- `git status` was clean apart from an unrelated zip; the local branch was five commits behind
  `appc/cac-2026` and was fast-forwarded (no conflicts). There were no half-finished edits to
  `ranking.ts`, `adventure-engine.ts` or `firestore.indexes.json` in this clone — the Mac's
  drafts never reached the remote.
- Backend built clean (`npm --prefix functions run build`). `xcodegen generate` and the
  simulator build need a Mac: **not run**. The new Swift files (`StartupFetches.swift`,
  `StartupFetchesTests.swift`, `PlacesMirrorTests.swift`, `PlannerUITests.swift`) are not in
  `project.pbxproj` until `xcodegen generate` runs.
- Emulators: Firestore on 8899 with Java 21 (`C:\Program Files\Microsoft\jdk-21…`), via
  `node functions/scripts/sprint-emulators.mjs --config-only`.
- Data reloaded through the real pipeline and the counts recorded:

| Data | Count (2026-10-25) | Command |
|---|---|---|
| events (public feeds, live) | **8,035** created: bibliocommons 7,385 · livewhale 342 · localist 181 · libcal 61 · midpen 57 · legistar 9 | `node functions/scripts/refresh-public-corpus-local.mjs <report.json>` |
| of which in the next 14 days | 2,048 | (from `personalization-e2e.mjs`) |
| park catalog (live) | **5,507** features: city-parks 614 · city-amenities 2,260 · county-trails 1,744 · county-poi 852 · county-boundaries 37 | `node functions/scripts/parks-local.mjs --live` |
| outdoor / volunteer sources | see 1.1 cause 5 below | `npm run e2e:discovery:record` |

- Exported to `../emulator-data` (35 MB, `firestore_export/`). `run-all.command` now starts the
  emulators with `--import ../emulator-data --export-on-exit`, so a restart never wipes the
  data again, and keeps the Mac awake with `caffeinate -dims` for the whole run.

## 1.1 Personalization (For You) — P0

**Root cause, confirmed in code:** the app stores interests as PlaceCategory labels
(`Parks`, `Trails`, `Gardens`, `Playgrounds`, `Waterfront`, `Sports`, `Scenic`, `Community`)
while both rankers only knew a lower-case vocabulary (`outdoors`, `fitness`, `volunteering`…).
`INTEREST_TO_CATEGORY["parks"]` was `undefined`, so the interest term was **0 for every event
for every real user** and For You was ordered by distance, timing and quality alone — hence
random sports events for Community and career workshops for Parks + Trails (the student floor
then lifted workshops to 0.75 against everybody else's 0). The build has no "Volunteering"
option; `Community` maps to community + volunteering.

Fixes (all in `functions/src/interests.ts`, `ranking.ts`, `ranking-v2.ts`):

1. **Labels understood** — `normalizeInterests` maps every PlaceCategory label (and a future
   "Volunteering") to server terms; both rankers and the reasons builder go through it. Server
   terms stored by older accounts still pass through.
2. **Candidate pool** — `interestCandidates`: per distinct interest set, the next 14 days of
   events whose `topicTags` or specific categories speak to the picks (≤ 150 + ≤ 100 docs,
   cached 5 min per interest set, shared by every user with the same picks). New composite index
   `events: areaId, active, topicTags (CONTAINS), date` in `firestore.indexes.json`;
   `npm run check:indexes` passes; `docs/READ-BUDGET.md` updated.
3. **Interest vs distance** — weights interest **0.16 → 0.20**, distance **0.24 → 0.20** (others
   unchanged), AND a direct match **orders above every non-match** (`rankEvents` sorts on
   `parts.interestMatch`, then score). Still "rank, never filter": nothing is dropped, distance
   orders within each group, a user with no picks gets the pure score. The student floor still
   lifts opportunities (0.75 / 0.9) but can no longer beat a direct match. A pick's *primary*
   meaning (hiking for Trails, waterfront for Waterfront) leads its shared outdoors matches.
4. **False matches** — matching is phrase-based on the title, the frozen classifier's
   *specific* categories (Cleanup, Volunteer, Sports, Market, Hackathon), and an allow-list of
   whole feed tags; description phrases, umbrella feed labels ("Health & Fitness") and
   lift-only categories (Festival for Community) raise the score (0.8) but never count as a
   match or earn a reason. Venue, branch and organizer names are stripped first (Mitchell Park
   Library, Greenhouse Community Room, Educational Park). Bare words that produced the false
   matches are gone: park, garden, walk, social, community, civic, nature, bay, reservoir, roses,
   game, summit, ridge. A lecture about a topic is not the activity. Catch-all categories
   (Workshop, Social, Meetup) never match.
5. **Supply** — see the before → after table and the discovery section below.
6. **Exploration slot** — the 10th card is the only off-interest card, is labelled in `parts`
   (`exploration: 1`) **and carries its own reason** the card shows: "Something different —
   outside your picks". It prefers quality, then score (so a nearer pick).

Also fixed in passing: **v1 series collapse** (a recurring listing was three identical cards —
"Open Lab Hours" ×3 in the Community top 10; now one card with `moreDates`, the later dates
move to the end of the list, nothing dropped), the reasons line **names the user's own pick**
("Because you like Parks") and is emitted only on a direct match (never for a floor or
behaviour; a stored server term reads as "family activities"), and the client's offline
fallback map (`PlaceCategory.relatedEventCategories`) drops the catch-all categories
(`Trails → Sports + Meetup` was how career events reached a Parks + Trails user with the backend
down). Changing interests re-ranks at once: the user document is read fresh on every request
and the new pool cache is keyed by the interest set (proved in the acceptance script).

**Before → after** (fresh account at the San José launch-area centre, 2,048 events in the next
14 days, `docs/PERSONALIZATION-REVIEW-2026-10-25.md`, evidence
`docs/evidence/personalization-2026-10-25.json`):

| Pick | matching events in 14 d | pool before → after | matches in pool before → after | top-10 matches |
|---|---|---|---|---|
| Parks | 28 | 272 → 367 | 11 → 24 | 9 (+ exploration) |
| Trails | 28 | 272 → 367 | 11 → 24 | 9 |
| Gardens | 52 | 270 → 365 | 12 → 25 | 9 |
| Playgrounds | 957 | 272 → 340 | 94 → 154 | 9 |
| Waterfront | 30 | 272 → 367 | 11 → 24 | 9 |
| Sports | 71 | 272 → 420 | 18 → 58 | 9 |
| Scenic | 31 | 272 → 367 | 12 → 27 | 9 |
| Community | 306 | 272 → 417 | 94 → 140 | 9 |
| Parks + Trails (student) | 28 | 272 → 367 | 11 → 24 | 9, **0 career/hackathon** |

Before the fix the interest term was 0 for every label, so "top-10 matches" was whatever
distance produced (the symptom in the brief). Pairwise overlap of the top 10: Parks + Trails
vs Community **1**, Sports vs Community **1**, Playgrounds vs anything 1; the outdoor picks
overlap each other heavily (Parks vs Waterfront 10) because the corpus holds few
waterfront-specific listings — the waterfront-specific ones (Lake Elizabeth Bird Walk) lead.
Manual review of every top 10: **zero false matches** after three rounds (the rounds removed:
South Bay Needlepointers → Waterfront via "bay"; a geothermal "Reservoir" seminar; "The Songs
of Nature" art exhibit; "Open Lab Hours at AI Center for Civic…" via "civic"; "Cinema Sunday:
Yellow Rose" → Gardens via "roses"; "Monday Meditation" → Sports via the "Health & Fitness"
umbrella tag; a drag-story-time *lecture* → Playgrounds).

Tests: `ranking-unit` **52 → 99** (labels, false matches, match-first order, exploration slot,
primary order, series collapse, reasons), `ranking-v2-unit` 69, `personalization-e2e.mjs`
**50/50** on the populated emulator (one fresh account per pick, the acceptance criteria as
assertions, writes the review doc), Swift `CoreLogicTests.testFallbackMappingAvoidsCatchAllCategories`
(not run). `ranking.version` stays **v1** (`seed/ranking-config.json` untouched).

Screenshots `demo-screens/foryou-<interest>.png`: **not taken** (no simulator here).

## 1.2 Adventure Planner (free, no AI key)

`functions/src/adventure-engine.ts` (new, pure, 66 unit checks) builds the itinerary from the
same candidate allowlist the model would get; `planAdventure` uses it whenever no
`ANTHROPIC_API_KEY` exists and falls back to it if a model call fails. The model path is
intact and runs only with a key. Rules, each tested:

- member-only organisations (clubs, lodges, societies, congregations tagged as community
  centres) are never stops;
- posted OSM hours honoured **at arrival time**; a stop never runs past its closing (an earlier
  stop is cut short to reach a later one in time; a two-stop plan keeps a "quick look" that ends
  at closing and says so); at most one stop with unposted hours; after dark an outdoor place with
  unposted hours is not assumed open and a trail is never a stop;
- a pick's own category beats distance (off-topic costs more than distance can buy back); each
  pick gets a stop when a candidate exists; when nothing is listed under the pick the intro
  says so instead of claiming the stops were chosen for it;
- 85 °F caps outdoor stops at 45 min, 95 °F at 30 and lets an indoor stop in as "a break from the
  heat"; rain prefers shelter, avoids trails and sitting down, ends indoors;
- plain outdoor stops finish before sunset (Open-Meteo now supplies sunrise/sunset), a sunset
  spot or indoor stop goes last, the plan names the sunset time;
- nearest-neighbour order from the user, travel deducted, **never over the minutes asked**;
- phrase pools with no phrase repeated in a plan and **no invented facts** — no benches, lawns,
  loop paths, views or swings the engine cannot see (`INVENTED_FEATURE_WORDS` test);
- a sparse area (two candidates) plans; "everything nearby is closed at this hour" is said
  instead of inventing a plan, and the callable's error carries that sentence.

`docs/PLANNER-REVIEW-2026-10-25.md`: the eleven scenarios regenerated by
`functions/scripts/planner-review.mjs` on **real City of San José parks** (from the ingested
catalog, CC BY; hours fixture-supplied and labelled), each reviewed by hand as a picky local;
**11/11** pass every check after three fix rounds (the review lines record what the first
draft got wrong — a stop after sunset at a dawn-to-dusk site, school playgrounds at night,
feature-asserting verbs, no trail for a Trails pick, 4 minutes over budget).

`planEvents` (the event planner) no longer answers "A plan nearby / Real events that fit your
choices." with no key: the deterministic plan follows the user's ranking, puts the picked
events in start order without overlaps, and gives concrete reasons (time, place, price,
friends, distance). The client decodes and shows the planner's notes and shows the server's
own sentence on a precondition failure. "Weather data by Open-Meteo.com" is unchanged in the
view and the response now carries the attribution too.

**Not done here:** the planner UI test is written (`PlannerUITests`) but **not run**; it needs
places on screen, i.e. the bundled OSM snapshot or a live Overpass answer (see 1.4). No
screenshot.

## 1.3 Remove false "AI" claims

Privacy policy (`Legal.swift` and the website's `legal.ts`, identical): itineraries are built
on our servers from public candidates and the user's preferences; **AI is used only when a
language-model key is configured**, and only then is anything sent to Anthropic.
`AppStore/LISTING.md` says the planner works with no key (key optional). `Verdure.storekit`
product description no longer says "AI planner, AR adventures" (prices, tiers, features
unchanged). Code comments in `PaywallView`, `ExploreView`, `functions/src/index.ts`,
`functions/.env` and the planner client/view stop calling it "AI". `git grep` for
`AI planner|AI Adventure|optional AI|AI-powered` over user-facing files: **0 hits**.

## 1.4 Nearby places (OpenStreetMap)

- User agent `Verdure/1.0 (+https://verdure-app.com)` on every request (no personal address),
  **four mirrors** in order (overpass-api.de, overpass.private.coffee, overpass.kumi.systems,
  maps.mail.ru) with **25 s** each, the Overpass `[timeout:25]`, then **this area's cache**
  (keyed by a ~5.5 km cell so one neighbourhood's cache is never served in another), then the
  **bundled snapshot** when the user is within its radius + 10 km. `PlacesSource` records which
  answered; the credit shows "© OpenStreetMap contributors · snapshot <date>" when the snapshot
  is on screen (Explore and the map pass the date; all four credit sites unchanged otherwise).
- **Events no longer wait behind places**: `VerdureApp.connectServicesIfNeeded` awaited places
  then events, so the Events tab sat empty for the Overpass timeout (~22 s). `StartupFetches.run`
  starts both together; `StartupFetchesTests` proves it with a continuation gate (no sleeps).
- `PlacesMirrorTests` (not run): user agent + timeout, mirror order, snapshot fallback with
  date, snapshot distance guard, per-area cache, keyed providers, and **that the snapshot file
  ships — this test fails until the snapshot is captured**.
- `functions/scripts/osm-snapshot.mjs` captures the snapshot with the app's own query, read out
  of the Swift source so the two cannot drift.

**Not done: the snapshot itself.** Every Overpass instance refused or timed out all day from
this network (overpass-api.de and its lz4/z backends: 502 "all query workers are busy";
private.coffee, kumi.systems, openstreetmap.ru, mail.ru: connection timeouts; osm.ch and
osm.jp: regional, 0 elements), while openstreetmap.org and Open-Meteo answered in under a
second. A retry loop ran every four minutes for two hours without success. **To finish:**
`node functions/scripts/osm-snapshot.mjs` once any mirror answers (it writes
`Verdure/Verdure/Resources/osm-snapshot-san-jose.json`), then `xcodegen generate`, then the
`PlacesMirrorTests` and `PlannerUITests` runs and the places screenshot.

## 1.5 Secrets and config

- `Verdure/Secrets.xcconfig` and `Verdure/Verdure/GoogleService-Info.plist` **untracked**
  (`git rm --cached`) and ignored with `functions/.secret.local`, `functions/.env.local`, `*.p8`;
  the `.template` files stay tracked. The `.gitignore` note that said the xcconfig *is*
  committed is gone.
- **Deviation, deliberate:** `functions/.env` stays tracked. It holds only non-secret defaults
  that keep the emulators non-interactive (`defineString` prompts on stdin otherwise and
  `npm run e2e` hangs on a fresh clone). The secret scan runs over it on every build.
- The new NPS and Recreation.gov keys live **only** in the two ignored files; both answer 200
  live (NPS parks, NPS events, RIDB facilities). Without a key NPS answers 403 and RIDB 401 —
  the app never sees either because a missing key means **no request at all**
  (`PlacesMirrorTests.testKeyedProvidersAreSkippedSilentlyWithoutTheirKeys`, and
  `ingest-unit`: an NPS source with no key resolves to an empty list without fetching).
- `functions/scripts/check-no-secrets.mjs` (`npm run check:secrets`, first in `test:units`):
  shape-based scan of every tracked file (NPS/Recreation.gov/SerpApi/Ticketmaster/Tremendous
  key assignments, `AIza` browser keys, `sk-ant-`, PEM, service-account JSON) and refuses any
  tracked secret file. `--history` scans every commit on every branch.
- History: the two burned keys appear **3 times each** in this clone's history (plus the old
  Firebase browser key and a SerpApi-style key in earlier commits); the new NPS key **0** times
  and in **0** tracked files. The purge was done on the Mac, not here: this clone's history
  is still the unpurged one. `docs/NEW-REPO-PUSH.md` gives the exact clean-history procedure
  (an orphan first commit of the current tree, scan, push only when Rishit says so).
- `GoogleService-Info.plist` `GOOGLE_APP_ID` and `Secrets.xcconfig` `FIREBASE_GOOGLE_APP_ID`
  both read `1:350584206981:ios:d008b84adbc0f34bd29bec`.
- The handoff document still holds the two key values; replace them with "sent to developer".

## 1.6 Tests

| Suite | Result | Command |
|---|---|---|
| Backend units (`npm run test:units`) | FILLED IN BELOW | classifier freeze ✓ · secret scan ✓ · indexes ✓ · 16 suites |
| Backend E2E (`npm run e2e`) | FILLED IN BELOW | |
| Red team (`npm run redteam`) | FILLED IN BELOW | |
| Acceptance (`npm run acceptance`) | FILLED IN BELOW | |
| Discovery unit | FILLED IN BELOW | after the live recording |
| Personalization E2E | **50/50** | `node functions/scripts/personalization-e2e.mjs` on the loaded emulator |
| Planner review | **11/11** | `node functions/scripts/planner-review.mjs` |
| iOS unit (`VerdureTests`) | **not run** (no Xcode) | `cd Verdure && xcodebuild … -only-testing:VerdureTests` |
| iOS UI, each class alone | **not run** | `… -only-testing:VerdureUITests/<Class> -parallel-testing-enabled NO` |
| Fresh-install walkthrough + screenshots | **not done** | needs the simulator |

The three intermittent UI tests and the two intermittent unit tests: **not touched**. Making a
test deterministic requires running it; nothing here could, and editing them blind risks
making them worse. They are the first thing to do on the Mac (three runs each).

## 1.7 Ready to record

`run-all.command` (repo root) does the whole stack in one double-click on the Mac — see its
header. **Not run here.** The data export it imports from is in `../emulator-data`.

---

## What is not perfect, and exactly why

1. **No Swift was compiled and no iOS test ran** — Windows, no Xcode. Files to compile first:
   `interests` has no Swift side; `Models.swift` (fallback map), `CoreLogicTests.swift`,
   `PlacesAPIService.swift`, `StartupFetches.swift`, `SharedComponents.swift`,
   `ExploreView.swift`, `MapExploreView.swift`, `VerdureApp.swift`,
   `AdventurePlannerService.swift`, `AdventurePlannerView.swift`, `Legal.swift`,
   `PaywallView.swift`, and the three new test files. Run `xcodegen generate` first.
2. **No OSM snapshot** — Overpass was down from this network all day. One command finishes it
   (1.4). Until then `PlacesMirrorTests.testBundledSnapshotCoversTheLaunchAreaWhenPresent`
   fails by design and the planner UI test cannot find places unless Overpass answers live.
3. **No screenshots** — `demo-screens/` was not produced.
4. **Flaky iOS tests not addressed** — see 1.6.
5. **History not purged in this clone** — the clean push procedure is written; the Mac's purged
   history or an orphan commit is what goes to the new repository.
6. **Outdoor supply** — see the discovery section below for what the live run activated; the
   Santa Clara County Parks, City of San José and SCU hosts still refuse automated access
   (403) and need a human to ask.

## Discovery recording run and outdoor/volunteer sources (1.1 cause 5, 1.6)

FILLED IN BELOW
