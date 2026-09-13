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

## Results

| Source | System | Status | Result |
|---|---|---|---|
| San José Public Library | BiblioCommons | ✅ ingesting | **6,477 events**, branch coordinates in-feed |
| Santa Clara County Library District | BiblioCommons | ✅ ingesting | **2,106 events** |
| San José State University | Localist | ✅ ingesting | full page / 30 days, `geo` present |
| Stanford University | Localist | ✅ ingesting | full page / 30 days; ~17 mi, inside the radius |
| Ticketmaster Discovery | API | ✅ ingesting | SAP Center, the California Theatre etc. |
| SerpApi (Google Events) | API | ✅ gap-filler | quota-capped, unchanged |
| Santa Clara University | Localist | ❌ **403** | blocks server-side requests |
| City of San José | — | ❌ **403** | calendar ICS endpoint denies non-browser agents |
| Midpen Open Space / County Parks | — | ❌ none | no iCal or RSS published |
| National Park Service | API | ❌ n/a | **no NPS unit inside the radius** |

### On NPS

`nps.parkCodes` is deliberately **empty**, which is a downgrade from Cleveland.
Cuyahoga Valley NP sat genuinely inside that area's 25 miles; the nearest units
here are Golden Gate NRA (~50 mi) and Pinnacles (~80 mi), both outside it, and
`isInsideArea` would discard their events anyway. Listing them would manufacture
a source that contributes nothing.

### The four ❌ rows are a recruitment list, not a gap to paper over

City of San José, Santa Clara University, Midpen and County Parks all run real
public programming. None of it is machine-readable to us. These are organizer-
account targets, which is the same conclusion Cleveland reached for its Metroparks
and county library.

## Reproducing this survey

```bash
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
