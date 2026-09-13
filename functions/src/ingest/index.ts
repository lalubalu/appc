/**
 * Ingest-and-own orchestration.
 *
 * Users never trigger an upstream call. Cloud Scheduler runs the fetchers —
 * hourly for ticketed feeds, daily for civic and library calendars — and writes
 * a normalized event store the app reads from Firestore alone. That is what
 * makes push notifications, personalisation over the full corpus and a flat
 * cost curve possible; the previous fetch-on-demand model could do none of them.
 *
 * Admin-only `runIngest` exists for two reasons: operations (re-run a source
 * now) and tests (a `payload` mode pushes already-normalized records through
 * the exact same store code, so dedupe and staleness are proven on the
 * emulator without touching a vendor).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, requireAdmin, safeString, safeText, utcMonthKey } from "../common.js";
import { NPS_API_KEY, SERPAPI_KEY, TICKETMASTER_KEY } from "../secrets.js";
import { LAUNCH_AREAS, areaById, type LaunchArea } from "./areas.js";
import type { IngestResult, NormalizedEvent, SourceId, EventCategory } from "./types.js";
import { CATEGORY_POINTS } from "./types.js";
import { loadAreaIndex, upsertBatch, markStale } from "./store.js";
import { fetchTicketmaster } from "./sources/ticketmaster.js";
import { fetchIcsFeed } from "./sources/icsfeed.js";
import { fetchLibCal } from "./sources/libcal.js";
import { fetchBiblioCommons } from "./sources/bibliocommons.js";
import { fetchLocalist } from "./sources/localist.js";
import { fetchNps } from "./sources/nps.js";
import { fetchSerpApi, serpApiBudgetAllows, SERPAPI_MONTHLY_CAP } from "./sources/serpapi.js";
import { cleanText, cleanUrl, cleanCoord, classify, formatLocalTime } from "./normalize.js";

const SOURCES: SourceId[] = ["ticketmaster", "libcal", "bibliocommons", "localist", "nps", "ics", "serpapi"];
const TICKETED: SourceId[] = ["ticketmaster"];
const CIVIC: SourceId[] = ["libcal", "bibliocommons", "localist", "nps", "ics", "serpapi"];

interface Keys { ticketmaster?: string; nps?: string; serpapi?: string; }

/** Fetch one source for one area. Throws on a failed fetch (nothing is marked stale then). */
async function fetchSource(source: SourceId, area: LaunchArea, keys: Keys): Promise<NormalizedEvent[]> {
  switch (source) {
    case "ticketmaster":
      if (!area.ticketmaster.enabled) return [];
      return fetchTicketmaster(area, keys.ticketmaster ?? "");
    case "libcal": {
      const all: NormalizedEvent[] = [];
      for (const feed of area.libcal) all.push(...await fetchLibCal(area, feed));
      return all;
    }
    case "bibliocommons": {
      const all: NormalizedEvent[] = [];
      for (const feed of area.bibliocommons ?? []) all.push(...await fetchBiblioCommons(area, feed));
      return all;
    }
    case "ics": {
      const all: NormalizedEvent[] = [];
      for (const feed of area.ics) all.push(...await fetchIcsFeed(area, feed, "ics"));
      return all;
    }
    case "localist": {
      const all: NormalizedEvent[] = [];
      for (const cal of area.localist) all.push(...await fetchLocalist(area, cal.host, cal.name));
      return all;
    }
    case "nps":
      if (!area.nps.parkCodes.length) return [];
      return fetchNps(area, keys.nps ?? "");
    case "serpapi": {
      if (!area.serpapi.enabled) return [];
      // Quota gate — counted BEFORE the call so a crash mid-fetch still counts.
      const allowed = await reserveSerpApiCall();
      if (!allowed) {
        console.warn(`[ingest] SerpApi monthly cap (${SERPAPI_MONTHLY_CAP}) reached — skipping; stale cache stands`);
        throw new SkipSource("SerpApi monthly quota exhausted");
      }
      return fetchSerpApi(area, keys.serpapi ?? "");
    }
    default:
      return [];
  }
}

class SkipSource extends Error {}

/** Increment this month's SerpApi counter in /treasury and say whether the call may proceed. */
export async function reserveSerpApiCall(): Promise<boolean> {
  const ref = db.collection("treasury").doc(utcMonthKey());
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = Number(snap.data()?.serpApiCalls) || 0;
    if (!serpApiBudgetAllows(used)) return false;
    tx.set(ref, { serpApiCalls: used + 1, serpApiCap: SERPAPI_MONTHLY_CAP, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

/** Run one source for one area end to end and log the result. */
export async function runSource(source: SourceId, area: LaunchArea, keys: Keys, payload?: NormalizedEvent[]): Promise<IngestResult> {
  const started = Date.now();
  const runStart = new Date(started);
  const result: IngestResult = {
    source, areaId: area.id, fetched: 0, created: 0, updated: 0, merged: 0,
    markedStale: 0, deactivated: 0, skipped: 0, errors: [], durationMs: 0,
  };
  try {
    const records = payload ?? await fetchSource(source, area, keys);
    result.fetched = records.length;
    const index = await loadAreaIndex(area);
    const stats = await upsertBatch(records, area, index, runStart);
    Object.assign(result, stats);
    // A source that returned nothing at all is far more likely a feed outage
    // than 100% cancellations. Only age the corpus when we actually saw records.
    if (records.length > 0) {
      const stale = await markStale(source, area, index, runStart);
      result.markedStale = stale.markedStale;
      result.deactivated = stale.deactivated;
    }
  } catch (e) {
    result.errors.push(e instanceof Error ? e.message : String(e));
    if (!(e instanceof SkipSource)) console.error(`[ingest] ${source}/${area.id} failed:`, e);
  }
  result.durationMs = Date.now() - started;
  await db.collection("ingestRuns").doc(`${runStart.toISOString()}_${source}_${area.id}`).set({
    ...result, runAt: Timestamp.fromDate(runStart),
  });
  // Supply telemetry per month: records seen per source.
  await db.collection("treasury").doc(utcMonthKey()).set({
    supply: { [`${source}.fetched`]: FieldValue.increment(result.fetched), [`${source}.runs`]: FieldValue.increment(1) },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return result;
}

function keysFromSecrets(): Keys {
  const read = (p: { value(): string }) => { try { return p.value(); } catch { return ""; } };
  return { ticketmaster: read(TICKETMASTER_KEY), nps: read(NPS_API_KEY), serpapi: read(SERPAPI_KEY) };
}

// ── Schedules ───────────────────────────────────────────────────────────────

export const ingestTicketed = onSchedule(
  { schedule: "every 60 minutes", secrets: [TICKETMASTER_KEY], timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const keys = keysFromSecrets();
    for (const area of LAUNCH_AREAS) for (const s of TICKETED) await runSource(s, area, keys);
  },
);

export const ingestCivic = onSchedule(
  { schedule: "every 24 hours", secrets: [NPS_API_KEY, SERPAPI_KEY], timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const keys = keysFromSecrets();
    for (const area of LAUNCH_AREAS) for (const s of CIVIC) await runSource(s, area, keys);
  },
);

// ── Admin: run now / feed a payload ─────────────────────────────────────────

/** Coerce an untrusted payload record into a NormalizedEvent, or null. */
export function coercePayloadRecord(raw: unknown, area: LaunchArea): NormalizedEvent | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const source = safeString(r.source) as SourceId;
  if (!SOURCES.includes(source) && source !== "organizer") return null;
  const start = new Date(safeString(r.start));
  if (Number.isNaN(start.getTime())) return null;
  const title = cleanText(r.title, 120);
  if (!title) return null;
  const categoryRaw = safeString(r.category);
  const category = (categoryRaw in CATEGORY_POINTS ? categoryRaw : classify(title)) as EventCategory;
  const end = r.end ? new Date(safeString(r.end)) : undefined;
  return {
    source,
    sourceEventId: safeText(r.sourceEventId, 120) || `${Date.now()}`,
    areaId: area.id,
    title,
    description: cleanText(r.description, 600),
    organizer: cleanText(r.organizer, 80) || "Community",
    start,
    end: end && !Number.isNaN(end.getTime()) ? end : undefined,
    time: cleanText(r.time, 60) || formatLocalTime(start, area.timeZone),
    locationName: cleanText(r.locationName, 100) || "Location TBA",
    latitude: cleanCoord(r.latitude, 90),
    longitude: cleanCoord(r.longitude, 180),
    category,
    isFree: r.isFree !== false,
    priceMin: typeof r.priceMin === "number" && Number.isFinite(r.priceMin) ? r.priceMin : undefined,
    website: cleanUrl(r.website),
    imageURL: cleanUrl(r.imageURL),
    tags: Array.isArray(r.tags) ? r.tags.filter((t): t is string => typeof t === "string").map((t) => cleanText(t, 40)).slice(0, 8) : [],
  };
}

export const runIngest = onCall(
  { secrets: [TICKETMASTER_KEY, NPS_API_KEY, SERPAPI_KEY], timeoutSeconds: 540, memory: "512MiB" },
  async (req) => {
    await requireAdmin(req.auth);
    const area = areaById(safeString(req.data?.areaId, LAUNCH_AREAS[0].id));
    if (!area) throw new HttpsError("invalid-argument", "Unknown launch area.");

    // Payload mode: normalized records, straight into the store.
    if (Array.isArray(req.data?.payload)) {
      const source = safeString(req.data?.source) as SourceId;
      if (!SOURCES.includes(source) && source !== "organizer") throw new HttpsError("invalid-argument", "Unknown source.");
      const records = (req.data.payload as unknown[]).slice(0, 2000)
        .map((r) => coercePayloadRecord(r, area))
        .filter((r): r is NormalizedEvent => r !== null && r.source === source);
      return { results: [await runSource(source, area, {}, records)] };
    }

    const requested = Array.isArray(req.data?.sources)
      ? (req.data.sources as unknown[]).map((s) => safeString(s)).filter((s): s is SourceId => SOURCES.includes(s as SourceId))
      : SOURCES;
    const keys = keysFromSecrets();
    const results: IngestResult[] = [];
    for (const s of requested) results.push(await runSource(s, area, keys));
    return { results };
  },
);

// ── Coverage report (Part 2 §1e) ────────────────────────────────────────────

export interface SupplyReport {
  areaId: string;
  computedAt: string;
  totalActiveUpcoming: number;
  bySource: Record<string, number>;
  byAnySource: Record<string, number>;
  sourcesOver10Percent: string[];
  organizerEvents: number;
  notInGoogleShare: number;
  duplicateRate: number;
  multiSourceEvents: number;
  targets: { total: number; notInGoogleShare: number; sourcesOver10: number; organizerEvents: number; duplicateRate: number };
  meets: Record<string, boolean>;
}

export async function computeSupplyReport(area: LaunchArea, now = new Date()): Promise<SupplyReport> {
  const snap = await db.collection("events")
    .where("areaId", "==", area.id)
    .where("active", "==", true)
    .limit(8000)
    .get();
  const upcoming = snap.docs.map((d) => d.data()).filter((d) => (d.date as Timestamp)?.toMillis?.() >= now.getTime());
  const total = upcoming.length;
  const bySource: Record<string, number> = {};
  const byAnySource: Record<string, number> = {};
  let organizerEvents = 0, multi = 0, notInGoogle = 0;
  const buckets = new Map<string, number>();
  for (const d of upcoming) {
    const primary = String(d.source ?? "community");
    bySource[primary] = (bySource[primary] ?? 0) + 1;
    const sources = Array.isArray(d.sources) ? d.sources.map((s: { source?: string }) => String(s.source)) : [primary];
    for (const s of new Set(sources)) byAnySource[s] = (byAnySource[s] ?? 0) + 1;
    if (primary === "organizer") organizerEvents++;
    if (sources.length > 1) multi++;
    if (!sources.includes("serpapi")) notInGoogle++;
    const key = `${d.titleKey}|${Math.floor(Number(d.startBucket) / 2)}`;
    buckets.set(key, (buckets.get(key) ?? 0) + 1);
  }
  let residualDupes = 0;
  for (const n of buckets.values()) if (n > 1) residualDupes += n - 1;
  const sourcesOver10 = Object.entries(bySource).filter(([, n]) => total > 0 && n / total > 0.10).map(([s]) => s);
  const targets = { total: 300, notInGoogleShare: 0.40, sourcesOver10: 3, organizerEvents: 50, duplicateRate: 0.05 };
  const report: SupplyReport = {
    areaId: area.id,
    computedAt: now.toISOString(),
    totalActiveUpcoming: total,
    bySource, byAnySource,
    sourcesOver10Percent: sourcesOver10,
    organizerEvents,
    notInGoogleShare: total ? notInGoogle / total : 0,
    duplicateRate: total ? residualDupes / total : 0,
    multiSourceEvents: multi,
    targets,
    meets: {
      total: total >= targets.total,
      notInGoogleShare: total > 0 && notInGoogle / total >= targets.notInGoogleShare,
      sourcesOver10: sourcesOver10.length >= targets.sourcesOver10,
      organizerEvents: organizerEvents >= targets.organizerEvents,
      duplicateRate: total > 0 && residualDupes / total < targets.duplicateRate,
    },
  };
  await db.collection("supplyReports").doc(`${now.toISOString().slice(0, 10)}_${area.id}`).set(report);
  await db.collection("treasury").doc(utcMonthKey(now)).set({ supplyReport: report, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return report;
}

export const supplyReportWeekly = onSchedule("every monday 09:00", async () => {
  for (const area of LAUNCH_AREAS) await computeSupplyReport(area);
});

export const getSupplyReport = onCall(async (req) => {
  await requireAdmin(req.auth);
  const area = areaById(safeString(req.data?.areaId, LAUNCH_AREAS[0].id));
  if (!area) throw new HttpsError("invalid-argument", "Unknown launch area.");
  return computeSupplyReport(area);
});

/** Public, read-only: which launch areas exist (the app uses this to explain coverage honestly). */
export const listLaunchAreas = onCall(async () => ({
  areas: LAUNCH_AREAS.map((a) => ({ id: a.id, name: a.name, center: a.center, radiusMiles: a.radiusMiles })),
}));
