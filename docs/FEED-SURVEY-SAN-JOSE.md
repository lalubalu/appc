# Feed survey — San Jose / South Bay launch area

Run date **2026-09-13**. Every row below was fetched live from this machine on
that date. Re-run the probes before trusting any of it; feeds change silently.

This survey is the evidence behind `SAN_JOSE` in `functions/src/ingest/areas.ts`.
It exists because the previous launch area (Cleveland, OH) was a placeholder that
had reached config, and moving it turned out not to be a coordinate swap.

## Headline: neither library system runs LibCal

The single most consequential finding. San José Public Library and Santa Clara
County Library District both run **BiblioCommons**, and **neither publishes
iCal** — `https://sjpl.bibliocommons.com/events/calendar.ics` is a hard 404.
Both the existing `.ics` adapter and the LibCal RSS adapter are unable to read
either system, so a third adapter was written:
`functions/src/ingest/sources/bibliocommons.ts`.

BiblioCommons turns out to be the better source of the two. Each branch carries
`mapLocation.centrePoint {lat,lng}` with an `isGeocoded` flag **in the feed**, so
there is no hand-maintained venue coordinate table (the Cleveland config had one,
and three CPL branches were permanently uncoordinated because OSM did not list
them). The adapter trusts a coordinate only when `isGeocoded === true`; an
ungeocoded centre point is a city centroid and would put the 500 ft check-in gate
around the wrong building.

## The rule this survey works to

**Parse public feeds and open data freely. Do not scrape any source whose terms
prohibit it.**

This corrects an earlier, stricter rule ("APIs and public feeds only"), which
was broader than the facts support and would have cost us real supply for no
benefit. City calendars, library systems and parks departments are fair game and
always were. Where a source publishes a public HTML calendar and no feed,
parsing it is acceptable **provided its terms do not forbid automated access** —
and that is checked, per source, before any adapter is written.

Two named exceptions, off-limits regardless: **Google Maps/Places** and
**Meetup**. Both prohibit it explicitly in their terms. For Google it is also
strategically backwards — the entire premise of this corpus is events Google
does not have, so seeding it from Google would defeat the measurement in
`coverage-check.mjs` as well as the product.

In practice this sprint that rule admitted exactly one source (Midpen, below)
and excluded exactly one (Santa Clara County Parks, also below) — and it
excluded that one on evidence, not on a blanket prohibition.

## Results

| Source | System | Status | Result |
|---|---|---|---|
| San José Public Library | BiblioCommons | ✅ ingesting | **6,477 events**, branch coordinates in-feed |
| Santa Clara County Library District | BiblioCommons | ✅ ingesting | **2,106 events** |
| Midpen Regional Open Space | HTML listing | ✅ ingesting | **57 events, 56 with coordinates**, all free |
| San José State University | Localist | ✅ ingesting | full page / 30 days, `geo` present |
| Stanford University | Localist | ✅ ingesting | full page / 30 days; ~17 mi, inside the radius |
| Ticketmaster Discovery | API | ✅ ingesting | SAP Center, the California Theatre etc. |
| SerpApi (Google Events) | API | ✅ gap-filler | quota-capped, unchanged |
| Santa Clara University | Localist | ❌ **403** | blocks server-side requests |
| City of San José | — | ❌ **403** | calendar ICS endpoint denies non-browser agents |
| Santa Clara County Parks | — | ❌ **403 (WAF)** | blocks everything, incl. `robots.txt` |
| National Park Service | API | ❌ n/a | **no NPS unit inside the radius** |

### On NPS, and what replaced it

`nps.parkCodes` is **empty** for this area. Cuyahoga Valley NP sat genuinely
inside Cleveland's 25 miles; the nearest units here are Golden Gate NRA (~50 mi)
and Pinnacles (~80 mi), both outside it, and `isInsideArea` would discard their
events anyway. Listing them would manufacture a source that contributes nothing.

The **adapter stays in the tree** — it is verified, costs nothing to keep, and
the next launch area may well have a park in range.

The outdoor/nature supply NPS was carrying is **replaced, not absorbed as a
loss**, by Midpen. That is a straight upgrade on every axis that matters:

| | Cuyahoga Valley (Cleveland) | Midpen (San Jose) |
|---|---|---|
| Events | 39 | **57** |
| Sites in radius | 1 park | **19 preserves, all inside** |
| With coordinates | park-level | **56 of 57, preserve-level** |
| Volunteer programming | some | **18 of 57** |

All 19 preserve coordinates were geocoded against OpenStreetMap (Nominatim) on
2026-09-13 and each was checked to fall inside the radius; a unit test asserts
that, so a bad coordinate cannot ship. A preserve missing from the table yields
an event with **no** coordinates rather than a guessed one.

**Known rough edge:** guided hikes classify as `Sports`, because that is the
closest fit in the existing `EventCategory` taxonomy and because Midpen's own
activity column calls them hikes. It is not wrong, but a user filtering "Sports"
expecting a ball game gets a nature walk. The events carry `outdoors` and the
activity name as tags, and the ranker maps the `outdoors` interest onto Sports,
so discovery works. Adding a real `Outdoors` category is a taxonomy change
across the app and is deliberately not bundled into this sprint.

### Why Midpen is parsed from HTML, and Santa Clara County Parks is not

**Midpen — parsed, with permission established first.** They publish no events
feed: `/events/feed`, `/events/rss.xml`, `/events.ics`, `/api/events` and
`/jsonapi` all 404, and `/rss.xml` is a site-wide "recent content" feed of ten
mixed items with no start times or locations. So it was HTML or nothing. Before
writing the adapter:

* `robots.txt` **allows** `/events` — it disallows only `/core`, `/profiles`,
  `/node/add`, `/comment/reply`, `/filter/tips`, `/media/oembed` and some READMEs.
* Their terms page (`/terms-use-privacy`, ~13k characters, read in full)
  contains **no** prohibition on automated access — no mention of scraping,
  crawling, spiders, robots, harvesting or data mining. Its one "commercial"
  clause governs user-submitted comments, not access.

A public agency, public programming, a page robots explicitly permits. It
qualifies under the rule above.

**Santa Clara County Parks — NOT parsed.** `sccgov.org` and `parks.sccgov.org`
return **403 to every request, including `robots.txt` itself**, with a browser
User-Agent as well as ours. That is an active WAF block, and because it also
blocks their rules file, their permissions **cannot be read at all**. Evading a
WAF is not "parsing a public page", and proceeding without being able to check
permission is not a judgement call we get to make on their behalf. They become a
recruitment target — which is a better outcome anyway, since an organizer
account gives us their programming with their consent and a contact behind it.

### Midpen will break, and it will say so

A feed has a contract; a page does not. When Midpen redesigns, the selectors
stop matching. The failure that must never happen is returning **zero** events
quietly — that reads as "no events this week" and nobody investigates, while the
staleness sweeper deactivates the whole outdoor category over three cycles.

So `fetchMidpen` **throws** when the page loads but yields no parseable rows.
The ingest runner records a source error, existing events are left alone, and
the failure is visible. A thrown error is a bug report; an empty array is a
silent outage. Two unit tests pin this by feeding it a redesigned page and a
table with no event links.

### The ❌ rows are a recruitment list, not a gap to paper over

City of San José, Santa Clara University and Santa Clara County Parks all run
real public programming that we cannot reach. All three return 403 to
server-side requests, so this is not a "no feed" problem that parsing solves —
it is a refusal, and the answer is to ask them. Same conclusion Cleveland
reached for its Metroparks and county library.

## Reproducing this survey

```bash
# Midpen: no feed anywhere, and the listing that replaces it
for p in /events/feed /events/rss.xml /events.ics /api/events /jsonapi; do
  curl -s -o /dev/null -w "$p: %{http_code}\n" "https://www.openspace.org$p"
done
curl -s "https://www.openspace.org/robots.txt" | grep -i event   # no Disallow
curl -s "https://www.openspace.org/events" | grep -c "<tr"

# Santa Clara County Parks: 403 on everything, robots.txt included
curl -s -o /dev/null -w "sccgov:        %{http_code}\n" "https://parks.sccgov.org/"
curl -s -o /dev/null -w "sccgov robots: %{http_code}\n" "https://parks.sccgov.org/robots.txt"

# Library systems — the two that needed the new adapter
curl -s "https://gateway.bibliocommons.com/v2/libraries/sjpl/events?limit=1" \
  | python3 -c "import sys,json;print('sjpl',json.load(sys.stdin)['events']['pagination']['count'])"
curl -s "https://gateway.bibliocommons.com/v2/libraries/sccl/events?limit=1" \
  | python3 -c "import sys,json;print('sccl',json.load(sys.stdin)['events']['pagination']['count'])"

# Proof there is no iCal path (expect 404)
curl -s -o /dev/null -w "sjpl ics: %{http_code}\n" "https://sjpl.bibliocommons.com/events/calendar.ics"

# Localist
curl -s "https://events.sjsu.edu/api/2/events?days=30&pp=100"     | head -c 80
curl -s "https://events.stanford.edu/api/2/events?days=30&pp=100" | head -c 80

# The two that refuse us (expect 403)
curl -s -o /dev/null -w "scu:  %{http_code}\n" "https://events.scu.edu/api/2/events?days=30&pp=3"
curl -s -o /dev/null -w "sjca: %{http_code}\n" "https://www.sanjoseca.gov/Home/Components/Calendar/Event/ICS"
```

Adapter behaviour is pinned without network by
`functions/test-fixtures/sjpl-bibliocommons-sample.json` (a trimmed live capture,
including a virtual event with no branch) — `npm run test:units` in `functions/`.

## One bug this move surfaced

SerpApi event ids hashed on the **UTC** calendar date. SerpApi's `when` field is
optional, so the same event arrives sometimes as `"Sat, Sep 20, 6 PM"` and
sometimes as bare `"Sep 20"`. In `America/New_York` a 6 PM start is still 22:00Z
the same day, so both hashed identically and dedupe worked. In
`America/Los_Angeles` 6 PM PDT is 01:00Z the **next** day — the two records hash
differently and the event would have ingested twice. Fixed in
`sources/serpapi.ts` by hashing the local calendar date; regression test in
`ingest-unit.mjs`.
