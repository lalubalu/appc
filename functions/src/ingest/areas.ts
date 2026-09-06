/**
 * Launch areas — the ONLY geography we ingest for.
 *
 * Ingestion is scoped to configured areas, never national: every scheduled job
 * loops over this list, and every fetcher receives one area. Adding a city is a
 * config change here plus a verification pass on its feeds.
 *
 * Every URL and host below was fetched live on 2026-09-06 and returned data.
 * Re-verify before relying on any of them — feeds change without notice.
 *
 * Launch area: CLEVELAND, OH. Chosen because the differentiating civic layer is
 * verifiably real here today: Cleveland Public Library runs LibCal (public
 * iCal, 500 events), Tri-C runs Localist (61 events / 30 days with coordinates),
 * Cuyahoga Valley National Park has 39 NPS events, and Ticketmaster Discovery
 * lists 990 events within 25 miles.
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

export interface LaunchArea {
  id: string;
  name: string;
  center: { lat: number; lng: number };
  radiusMiles: number;
  timeZone: string;
  ticketmaster: { enabled: boolean };
  /** Springshare LibCal calendars (one per library system). */
  libcal: LibCalFeed[];
  /** Localist calendar hosts (city / university / community college). */
  localist: { host: string; name: string }[];
  /** National Park Service park codes with events near the area. */
  nps: { parkCodes: string[] };
  /** Plain .ics / iCal feeds — city, parks, community centres. */
  ics: IcsFeed[];
  /** SerpApi (Google Events) — gap-filler only, quota-capped. */
  serpapi: { enabled: boolean; query: string };
}

export const CLEVELAND: LaunchArea = {
  id: "cleveland-oh",
  name: "Cleveland, OH",
  center: { lat: 41.4993, lng: -81.6944 },
  radiusMiles: 25,
  timeZone: "America/New_York",
  ticketmaster: { enabled: true },
  libcal: [
    {
      // Verified 2026-09-06: rss.php?m=month returns 300 upcoming items with
      // structured libcal:* fields. (The iCal subscription for the same calendar
      // is a rolling 500-event window that ends BEFORE today — unusable for
      // upcoming events; see sources/libcal.ts.)
      name: "Cleveland Public Library",
      calendarId: "8758",
      rssUrl: "https://cpl.libcal.com/rss.php?m=month&cid=8758",
      venues: {
        // Coordinates verified against OpenStreetMap (Overpass, amenity=library,
        // City of Cleveland bbox) on 2026-09-06 — 4-decimal precision (~11 m).
        // Branches NOT present in OSM (Fleet, Mt. Pleasant, Walz) deliberately
        // have no entry: an event there gets no coordinates rather than a guess,
        // so the check-in proximity gate stays off instead of wrong.
        "Main Library - Downtown": { lat: 41.5013, lng: -81.6914 },
        "Glenville": { lat: 41.5410, lng: -81.6025 },
        "Rice": { lat: 41.4848, lng: -81.6033 },
        "Eastman": { lat: 41.4624, lng: -81.7680 },
        "Harvard-Lee": { lat: 41.4496, lng: -81.5616 },
        "Jefferson": { lat: 41.4793, lng: -81.6856 },
        "Rockport": { lat: 41.4338, lng: -81.7903 },
        "South Brooklyn": { lat: 41.4384, lng: -81.7072 },
        "West Park": { lat: 41.4514, lng: -81.8075 },
        "Lorain": { lat: 41.4711, lng: -81.7416 },
        "Fulton": { lat: 41.4579, lng: -81.7127 },
        "Carnegie West": { lat: 41.4824, lng: -81.7113 },
        "Woodland": { lat: 41.4877, lng: -81.6487 },
        "Sterling": { lat: 41.4975, lng: -81.6667 },
        "Hough": { lat: 41.5107, lng: -81.6448 },
        "Addison": { lat: 41.5192, lng: -81.6426 },
        "Langston Hughes": { lat: 41.5213, lng: -81.6172 },
        "Collinwood": { lat: 41.5560, lng: -81.5758 },
        "Memorial-Nottingham": { lat: 41.5829, lng: -81.5619 },
        "Union": { lat: 41.4644, lng: -81.6209 },
        "East 131st": { lat: 41.4546, lng: -81.5916 },
        "Garden Valley": { lat: 41.4798, lng: -81.6379 },
        "Martin Luther King": { lat: 41.5040, lng: -81.6140 },
        "Brooklyn": { lat: 41.4542, lng: -81.7017 },
      },
      tags: ["library"],
    },
  ],
  localist: [
    // Verified 2026-09-06: /api/2/events returns 61 events (30 days), with geo.
    // Cuyahoga Community College — Cleveland's community college; most events
    // are tagged "General Public".
    { host: "events.tri-c.edu", name: "Tri-C" },
  ],
  nps: {
    // Cuyahoga Valley National Park — verified 39 events, recurring farmers market etc.
    parkCodes: ["cuva"],
  },
  ics: [
    // Cleveland Metroparks and the City of Cleveland publish NO iCal/RSS feed
    // (checked clevelandmetroparks.com and clevelandohio.gov on 2026-09-06).
    // Cuyahoga County Public Library's calendar (attend.cuyahogalibrary.org)
    // has ICS export disabled. Recruit these via organizer accounts instead.
  ],
  serpapi: { enabled: true, query: "events in Cleveland, OH" },
};

export const LAUNCH_AREAS: LaunchArea[] = [CLEVELAND];

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
