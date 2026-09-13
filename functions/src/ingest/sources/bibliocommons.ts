/**
 * BiblioCommons — public library event calendars via the public gateway API.
 *
 * WHY THIS EXISTS. The South Bay's two library systems (San José Public Library
 * and Santa Clara County Library District) both run BiblioCommons, not LibCal.
 * Surveyed live 2026-09-13:
 *
 *   https://sjpl.bibliocommons.com/events/calendar.ics   → 404 (no iCal at all)
 *   https://gateway.bibliocommons.com/v2/libraries/sjpl/events  → 200, 6,485 events
 *   https://gateway.bibliocommons.com/v2/libraries/sccl/events  → 200, paginated
 *
 * So neither the .ics adapter nor the LibCal RSS adapter can read them, which is
 * why this is a third source rather than a config entry.
 *
 * ONE REAL ADVANTAGE OVER LIBCAL: branch coordinates come from the feed. Each
 * location carries `mapLocation.centrePoint {lat,lng}` with `isGeocoded: true`,
 * so there is no hand-maintained venue table here and no branch silently
 * missing coordinates — the failure mode that forced the Cleveland config to
 * leave three branches uncoordinated. Check-in proximity therefore works for
 * every branch the feed geocodes, and only for those.
 *
 * SHAPE. The response is normalized-by-id: `entities.events` holds the event
 * records, `entities.locations` the branches, `entities.images` the artwork, and
 * `events.items` is the ordered id list. Each event's real payload sits under
 * `definition`, with `indexStart`/`indexEnd` carrying the resolved UTC instants
 * of that occurrence (recurring series are already expanded, one record per
 * occurrence) — so no timezone maths is needed, unlike the LibCal path.
 */

import type { LaunchArea, BiblioFeed } from "../areas.js";
import type { NormalizedEvent } from "../types.js";
import { cleanText, cleanUrl, cleanCoord, classify, formatLocalTime } from "../normalize.js";

export interface BiblioItem {
  eventId: string;
  title: string;
  descriptionHtml: string;
  startISO: string;
  endISO?: string;
  branch: string;
  room: string;
  lat?: number;
  lng?: number;
  types: string[];
  audiences: string[];
  image?: string;
  link?: string;
  isFull: boolean;
}

interface GatewayPayload {
  events?: { items?: unknown[]; pagination?: { count?: number; pages?: number; page?: number } };
  entities?: Record<string, Record<string, any>>;
}

/**
 * Flatten the gateway's entity graph into plain items.
 *
 * Exported so the unit tests can run it against a captured fixture with no
 * network — the same pattern parseLibCalRss follows.
 */
export function parseBiblioPayload(payload: unknown, host: string): BiblioItem[] {
  const p = (payload ?? {}) as GatewayPayload;
  const events = p.entities?.events ?? {};
  const locations = p.entities?.locations ?? {};
  const images = p.entities?.images ?? {};
  const types = p.entities?.eventTypes ?? {};
  const audiences = p.entities?.eventAudiences ?? {};

  // Preserve the server's ordering when it gives one; fall back to the map.
  const ids = Array.isArray(p.events?.items) && p.events!.items!.length
    ? p.events!.items!.map(String)
    : Object.keys(events);

  const out: BiblioItem[] = [];
  for (const id of ids) {
    const ev = events[id];
    const def = ev?.definition;
    if (!ev || !def || typeof def !== "object") continue;

    const loc = locations[String(def.branchLocationId ?? "")] ?? {};
    const centre = loc?.mapLocation?.centrePoint;
    const geocoded = loc?.mapLocation?.isGeocoded === true;

    const img = images[String(def.featuredImageId ?? "")];

    out.push({
      eventId: String(ev.id ?? id),
      title: String(def.title ?? ""),
      descriptionHtml: String(def.description ?? ""),
      // indexStart/indexEnd are the resolved UTC instants for this occurrence.
      startISO: String(ev.indexStart ?? ""),
      endISO: ev.indexEnd ? String(ev.indexEnd) : undefined,
      branch: String(loc?.name ?? ""),
      room: String(def.locationDetails ?? ""),
      // Only trust a coordinate the feed says it actually geocoded. An
      // ungeocoded centrePoint is a city centroid, which would put the
      // check-in gate around the wrong building.
      lat: geocoded ? cleanCoord(centre?.lat, 90) : undefined,
      lng: geocoded ? cleanCoord(centre?.lng, 180) : undefined,
      types: (Array.isArray(def.typeIds) ? def.typeIds : [])
        .map((t: unknown) => String(types[String(t)]?.name ?? "")).filter(Boolean),
      audiences: (Array.isArray(def.audienceIds) ? def.audienceIds : [])
        .map((a: unknown) => String(audiences[String(a)]?.name ?? "")).filter(Boolean),
      image: img?.url ? String(img.url) : undefined,
      link: `https://${host}/events/${ev.id ?? id}`,
      isFull: ev.isFull === true,
    });
  }
  return out;
}

export function mapBiblioItem(i: BiblioItem, area: LaunchArea, feed: BiblioFeed): NormalizedEvent | null {
  const title = cleanText(i.title, 120);
  if (!title) return null;

  const start = new Date(i.startISO);
  if (Number.isNaN(start.getTime())) return null;
  const end = i.endISO ? new Date(i.endISO) : undefined;

  const description = cleanText(i.descriptionHtml, 600);
  const location = [cleanText(i.branch, 60), cleanText(i.room, 60)].filter(Boolean).join(" · ") || feed.name;
  const text = `${title} ${i.types.join(" ")} ${i.audiences.join(" ")} ${description.slice(0, 300)}`;

  return {
    source: "bibliocommons",
    sourceEventId: `${feed.library}-${i.eventId}`,
    areaId: area.id,
    title,
    description,
    organizer: cleanText(feed.name, 80),
    start,
    end: end && !Number.isNaN(end.getTime()) ? end : undefined,
    time: formatLocalTime(start, area.timeZone),
    locationName: cleanText(location, 100),
    latitude: i.lat,
    longitude: i.lng,
    category: classify(text),
    // Library programming is free unless the copy says otherwise. Same rule as
    // the LibCal path, same regex, deliberately — these are the same kind of
    // institution and should not disagree about what "free" means.
    isFree: !/\$\s?\d|ticket(s)? required|admission fee/i.test(description),
    website: cleanUrl(i.link),
    imageURL: cleanUrl(i.image),
    tags: [...(feed.tags ?? []), ...i.types.map((t) => cleanText(t, 40)),
           ...i.audiences.map((a) => cleanText(a, 40))].filter(Boolean).slice(0, 8),
  };
}

/** Max pages to walk. SJPL alone reports 6,485 events; we want the near future. */
const MAX_PAGES = 4;
const PAGE_SIZE = 100;

export async function fetchBiblioCommons(
  area: LaunchArea,
  feed: BiblioFeed,
  fetchImpl: typeof fetch = fetch,
): Promise<NormalizedEvent[]> {
  const host = feed.host ?? `${feed.library}.bibliocommons.com`;
  const out: NormalizedEvent[] = [];

  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = `https://gateway.bibliocommons.com/v2/libraries/${encodeURIComponent(feed.library)}` +
                `/events?limit=${PAGE_SIZE}&page=${page}`;
    const res = await fetchImpl(url, {
      headers: { accept: "application/json", "user-agent": "Verdure/1.0 (events ingest)" },
    });
    if (!res.ok) {
      if (page === 1) throw new Error(`${feed.name} returned ${res.status}`);
      break;   // a partial read still beats dropping the system entirely
    }
    const payload = await res.json();
    const items = parseBiblioPayload(payload, host);
    if (items.length === 0) break;

    for (const i of items) {
      const mapped = mapBiblioItem(i, area, feed);
      if (mapped) out.push(mapped);
    }

    const pages = Number((payload as GatewayPayload)?.events?.pagination?.pages ?? 1);
    if (page >= pages) break;
  }
  return out;
}
