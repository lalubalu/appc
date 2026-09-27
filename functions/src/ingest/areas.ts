/**
 * Launch areas — the ONLY geography we ingest for.
 *
 * Ingestion is scoped to configured areas, never national: every scheduled job
 * loops over this list, and every fetcher receives one area. Adding a city is a
 * config change here plus a verification pass on its feeds.
 *
 * Every URL and host below was fetched live and returned data on the date noted
 * against it. Re-verify before relying on any of them — feeds change silently.
 *
 * ── WHAT WE MAY INGEST FROM ──────────────────────────────────────────────────
 *
 * Parse public feeds and open data freely. Do NOT scrape any source whose terms
 * prohibit it.
 *
 * This supersedes an earlier, stricter rule ("APIs and public feeds only"),
 * which was broader than the facts support and would have cost real supply for
 * no benefit. City calendars, library systems and parks departments are fair
 * game and always were. Where a source publishes a public HTML calendar and no
 * feed, parsing it is acceptable PROVIDED its terms do not forbid automated
 * access — checked per source, before the adapter is written, with the evidence
 * recorded in the adapter's header and in docs/FEED-SURVEY-<area>.md.
 *
 * Two standing exceptions, off-limits regardless of how useful they look:
 *   • Google Maps / Places — prohibited by their terms, AND strategically
 *     self-defeating: the premise of this corpus is events Google does not
 *     have, so seeding it from Google would invalidate coverage-check.mjs
 *     along with the product claim.
 *   • Meetup — prohibited by their terms.
 *
 * A 403 is not a licence to try harder. If a source blocks automated requests
 * outright — especially if it blocks robots.txt itself, so its rules cannot
 * even be read — it is a RECRUITMENT target, not a parsing target. Santa Clara
 * County Parks is the worked example; see the survey doc.
 *
 * Launch area: SAN JOSE / SOUTH BAY, CA.
 *
 * This replaced Cleveland, OH on 2026-09-13. Cleveland was never a decision —
 * it was a placeholder that survived into config. Verdure launches where its
 * operators and first users are, and that is the South Bay.
 *
 * The civic layer is denser here than it was in Cleveland, but it is reached
 * DIFFERENTLY, and that difference cost a new adapter. Surveyed live 2026-09-13
 * (full write-up and every probe in docs/FEED-SURVEY-SAN-JOSE.md):
 *
 *   San José Public Library      BiblioCommons   6,477 events   ✅ sources/bibliocommons.ts
 *   Santa Clara County Library   BiblioCommons   2,106 events   ✅ same adapter
 *   San José State University    Localist          100+/30d     ✅ with coordinates
 *   Stanford University          Localist          100+/30d     ✅ (~17 mi, inside radius)
 *   Ticketmaster Discovery       API                  —         ✅ SAP Center et al.
 *   Santa Clara University       LiveWhale        JSON v2 200   ✅ sources/livewhale.ts
 *   City of San José             Legistar API       14 public meetings (2026-09-26 read)
 *   Mountain View Library        LibCal RSS         64 events (2026-09-26 read)
 *
 * NEITHER library system runs LibCal, and neither publishes iCal — SJPL's
 * /events/calendar.ics is a hard 404. The existing .ics and LibCal adapters
 * could not read either one, which is why sources/bibliocommons.ts exists.
 * Unlike LibCal, BiblioCommons ships branch coordinates in the feed
 * (mapLocation.centrePoint, isGeocoded), so there is no hand-kept venue table
 * below and no branch silently missing coordinates.
 */

export interface IcsFeed {
  /** Shown as the organizer when the feed has no ORGANIZER line. */
  name: string;
  url: string;
  /** Known venue coordinates keyed by an exact LOCATION substring. */
  venues?: Record<string, { lat: number; lng: number }>;
  /** Default tags to attach (e.g. "library"). */
  tags?: string[];
}

/** A Springshare LibCal calendar, read through its public RSS feed (see sources/libcal.ts). */
export interface LibCalFeed {
  name: string;
  /** LibCal calendar id (`cid`); prefixes source event ids so systems never collide. */
  calendarId: string;
  /** `https://<inst>.libcal.com/rss.php?m=month&cid=<calendarId>` */
  rssUrl: string;
  /** Known branch coordinates keyed by an exact `libcal:campus` substring. */
  venues?: Record<string, { lat: number; lng: number }>;
  tags?: string[];
}

/**
 * A BiblioCommons library system, read through the public gateway API
 * (see sources/bibliocommons.ts). No venue table: the feed geocodes branches.
 */
export interface BiblioFeed {
  name: string;
  /** Gateway library slug, e.g. "sjpl" — prefixes source ids so systems never collide. */
  library: string;
  /** Public site host, used to build event links. Defaults to `<library>.bibliocommons.com`. */
  host?: string;
  /** For systems extending beyond the launch radius, only keep geolocated in-area events. */
  requireInAreaCoordinates?: boolean;
  /** Lower when a system's gateway fails on large late pages. */
  pageSize?: number;
  tags?: string[];
}

/**
 * Midpeninsula Regional Open Space District. Parsed from their events listing —
 * they publish no feed. See sources/midpen.ts for the permission check that
 * precedes that decision, and docs/FEED-SURVEY-SAN-JOSE.md for the evidence.
 */
export interface MidpenFeed {
  name: string;
  tags?: string[];
}

export interface LaunchArea {
  id: string;
  name: string;
  center: { lat: number; lng: number };
  radiusMiles: number;
  timeZone: string;
  ticketmaster: { enabled: boolean };
  /** Springshare LibCal calendars (one per library system). */
  libcal: LibCalFeed[];
  /** BiblioCommons library systems (one per library system). */
  bibliocommons: BiblioFeed[];
  /** Midpeninsula Regional Open Space District (HTML listing; no feed exists). */
  midpen: MidpenFeed[];
  /** Localist calendar hosts (city / university / community college). */
  localist: { host: string; name: string }[];
  /** LiveWhale Calendar hosts (public JSON v2 feeds). */
  livewhale: { host: string; name: string }[];
  /** Public legislative meeting calendars through the Legistar Web API. */
  legistar: { client: string; name: string }[];
  /** National Park Service park codes with events near the area. */
  nps: { parkCodes: string[] };
  /** Plain .ics / iCal feeds — city, parks, community centres. */
  ics: IcsFeed[];
  /** SerpApi (Google Events) — gap-filler only, quota-capped. */
  serpapi: { enabled: boolean; query: string };
}

export const SAN_JOSE: LaunchArea = {
  id: "san-jose-ca",
  name: "San Jose, CA",
  // Downtown San José (City Hall). 25 miles reaches Palo Alto and Stanford to
  // the north-west, Gilroy to the south, and Fremont across the bay.
  center: { lat: 37.3382, lng: -121.8863 },
  radiusMiles: 25,
  timeZone: "America/Los_Angeles",
  ticketmaster: { enabled: true },
  // Mountain View Library's public RSS calendar, distinct from its bookmobile.
  libcal: [{
    name: "Mountain View Public Library",
    calendarId: "8800",
    rssUrl: "https://mountainview.libcal.com/rss.php?m=month&cid=8800",
    tags: ["library"],
  }],
  bibliocommons: [
    {
      // Verified 2026-09-13: gateway reports 6,477 events. calendar.ics → 404.
      name: "San José Public Library",
      library: "sjpl",
      host: "sjpl.bibliocommons.com",
      tags: ["library"],
    },
    {
      // Verified 2026-09-13: gateway reports 2,106 events.
      name: "Santa Clara County Library District",
      library: "sccl",
      host: "sccl.bibliocommons.com",
      // Page 13 at 150 returns HTTP 500; pages of 100 work through the same range.
      pageSize: 100,
      tags: ["library"],
    },
    {
      // Verified 2026-09-26: public gateway reports 457 upcoming records.
      name: "Palo Alto City Library",
      library: "paloalto",
      host: "paloalto.bibliocommons.com",
      tags: ["library"],
    },
    {
      // Fremont, Newark, Centerville and Union City are inside the radius;
      // other Alameda County branches are not. Missing coordinates are excluded.
      name: "Alameda County Library",
      library: "aclibrary",
      host: "aclibrary.bibliocommons.com",
      requireInAreaCoordinates: true,
      tags: ["library"],
    },
    {
      // Eastern San Mateo County branches reach the area, western ones do not.
      name: "San Mateo County Libraries",
      library: "smcl",
      host: "smcl.bibliocommons.com",
      requireInAreaCoordinates: true,
      tags: ["library"],
    },
  ],
  localist: [
    // Verified 2026-09-13: /api/2/events returns a full page with geo.
    { host: "events.sjsu.edu", name: "San José State University" },
    // Verified 2026-09-13. Palo Alto is ~17 mi from centre, inside the radius.
    { host: "events.stanford.edu", name: "Stanford University" },
  ],
  livewhale: [
    // Verified 2026-09-26: public JSON v2 returns ~520 events/60 days.
    // The old Localist probe was a platform mismatch, not proof of no feed.
    { host: "events.scu.edu", name: "Santa Clara University" },
  ],
  legistar: [{ client: "sanjose", name: "City of San José" }],
  midpen: [
    // Verified 2026-09-13: 64 events across 22 preserves, 19 of which geocode
    // INSIDE the radius. This is what replaces NPS for this area — see below.
    { name: "Midpeninsula Regional Open Space District", tags: ["outdoors", "parks"] },
  ],
  nps: {
    // No NPS unit sits inside the radius. Pinnacles is ~80 mi and Golden Gate
    // ~50 mi, both outside it, and isInsideArea would discard their events
    // anyway. Empty is the honest value; the previous area had Cuyahoga Valley
    // genuinely inside its radius, and this one has nothing.
    //
    // The ADAPTER stays in the tree deliberately. It is verified, it costs
    // nothing to keep, and the next launch area may well have a park in range.
    // Outdoor/nature supply for THIS area comes from `midpen` above, which is
    // nearer, larger and carries more family programming than Cuyahoga Valley
    // did — so the category is replaced, not absorbed as a loss.
    parkCodes: [],
  },
  ics: [
    // City of San José returns 403 to its calendar ICS endpoint from servers.
    // Midpeninsula Regional Open Space and County Parks publish no iCal.
    // Recruit these via organizer accounts instead.
  ],
  serpapi: { enabled: true, query: "events in San Jose, CA" },
};

export const LAUNCH_AREAS: LaunchArea[] = [SAN_JOSE];

export function areaById(id: string | undefined): LaunchArea | undefined {
  return LAUNCH_AREAS.find((a) => a.id === id);
}

const MILE_M = 1609.344;

/** Is a coordinate inside the area's radius (plus a small tolerance)? */
export function isInsideArea(area: LaunchArea, lat: number, lng: number, toleranceMiles = 5): boolean {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat - area.center.lat);
  const dLng = toRad(lng - area.center.lng);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(area.center.lat)) * Math.cos(toRad(lat)) * Math.sin(dLng / 2) ** 2;
  const d = 2 * R * Math.asin(Math.sqrt(a));
  return d <= (area.radiusMiles + toleranceMiles) * MILE_M;
}
