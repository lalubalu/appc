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
import { loadAreaIndex, upsertBatch, markStale, auditSuspectedDuplicates } from "./store.js";
import { fetchTicketmaster } from "./sources/ticketmaster.js";
import { fetchIcsFeed } from "./sources/icsfeed.js";
import { fetchLibCal } from "./sources/libcal.js";
import { fetchBiblioCommons } from "./sources/bibliocommons.js";
import { fetchMidpen } from "./sources/midpen.js";
import { fetchLocalist } from "./sources/localist.js";
import { fetchLiveWhale } from "./sources/livewhale.js";
import { fetchLegistar } from "./sources/legistar.js";
import { fetchNps } from "./sources/nps.js";
import { fetchSerpApi, serpApiBudgetAllows, SERPAPI_MONTHLY_CAP } from "./sources/serpapi.js";
import { cleanText, cleanUrl, cleanCoord, classify, formatLocalTime } from "./normalize.js";
import { recordSourceHealth } from "./health.js";
import { auditedStaffJob, staffReason } from "../staff-audit.js";
import { loadActiveSources, isDeniedHost, type SourceDoc } from "./sources-registry.js";
import type { IcsFeed, LibCalFeed, BiblioFeed, MidpenFeed } from "./areas.js";

export const SOURCES: SourceId[] = ["ticketmaster", "libcal", "bibliocommons", "localist", "livewhale", "legistar", "nps", "midpen", "ics", "serpapi"];
const TICKETED: SourceId[] = ["ticketmaster"];
const CIVIC: SourceId[] = ["libcal", "bibliocommons", "localist", "livewhale", "legistar", "nps", "midpen", "ics", "serpapi"];

interface Keys { ticketmaster?: string; nps?: string; serpapi?: string; }

/**
 * Fetch every ACTIVE /sources document of one adapter type for one area (W4.1).
 * `sources` may be supplied directly (tests, the migration check); otherwise
 * they are read from Firestore. A denied host is refused here too, so the
 * deny-list holds even if a bad document reached the collection. Throws on a
 * failed fetch (nothing is marked stale then).
 */
export async function fetchSource(source: SourceId, area: LaunchArea, keys: Keys, sources?: SourceDoc[]): Promise<NormalizedEvent[]> {
  const docs = (sources ?? await loadActiveSources(area.id, source)).filter((s) => s.type === source && s.areaId === area.id && !isDeniedHost(s.host));
  const all: NormalizedEvent[] = [];
  for (const s of docs) {
    const p = s.params as Record<string, unknown>;
    switch (source) {
      case "ticketmaster":
        if (p.enabled === true) all.push(...await fetchTicketmaster(area, keys.ticketmaster ?? ""));
        break;
      case "libcal": all.push(...await fetchLibCal(area, p as unknown as LibCalFeed)); break;
      case "bibliocommons": all.push(...await fetchBiblioCommons(area, p as unknown as BiblioFeed)); break;
      case "midpen": all.push(...await fetchMidpen(area, p as unknown as MidpenFeed)); break;
      case "ics": all.push(...await fetchIcsFeed(area, p as unknown as IcsFeed, "ics")); break;
      case "localist": all.push(...await fetchLocalist(area, String(p.host), String(p.name))); break;
      case "livewhale": all.push(...await fetchLiveWhale(area, String(p.host), String(p.name))); break;
      case "legistar": all.push(...await fetchLegistar(area, String(p.client), String(p.name))); break;
      case "nps": {
        const codes = Array.isArray(p.parkCodes) ? p.parkCodes.filter((c): c is string => typeof c === "string") : [];
        if (codes.length) all.push(...await fetchNps({ ...area, nps: { parkCodes: codes } } as LaunchArea & { nps: { parkCodes: string[] } }, keys.nps ?? ""));
        break;
      }
      case "serpapi": {
        if (p.enabled !== true) break;
        // Quota gate — counted BEFORE the call so a crash mid-fetch still counts.
        const allowed = await reserveSerpApiCall();
        if (!allowed) {
          console.warn(`[ingest] SerpApi monthly cap (${SERPAPI_MONTHLY_CAP}) reached — skipping; stale cache stands`);
          throw new SkipSource("SerpApi monthly quota exhausted");
        }
        all.push(...await fetchSerpApi({ ...area, serpapi: { enabled: true, query: String(p.query ?? `events in ${area.name}`) } } as LaunchArea & { serpapi: { enabled: boolean; query: string } }, keys.serpapi ?? ""));
        break;
      }
      default: break;
    }
  }
  return all;
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
export async function runSource(source: SourceId, area: LaunchArea, keys: Keys, payload?: NormalizedEvent[], sources?: SourceDoc[]): Promise<IngestResult> {
  const started = Date.now();
  const runStart = new Date(started);
  const result: IngestResult = {
    source, areaId: area.id, fetched: 0, created: 0, updated: 0, merged: 0,
    mergeRate: 0, suspectedDuplicates: 0, suspectedDuplicateRate: 0,
    markedStale: 0, deactivated: 0, skipped: 0, unchanged: 0, fuzzyMerged: 0, rejected: 0, rejectedByReason: {}, writes: 0,
    errors: [], durationMs: 0,
  };
  try {
    const records = payload ?? await fetchSource(source, area, keys, sources);
    result.fetched = records.length;
    const index = await loadAreaIndex(area);
    const stats = await upsertBatch(records, area, index, runStart);
    Object.assign(result, stats);
    const candidates = result.created + result.merged;
    result.mergeRate = candidates ? result.merged / candidates : 0;
    // A source that returned nothing at all is far more likely a feed outage
    // than 100% cancellations. Only age the corpus when we actually saw records.
    if (records.length > 0) {
      const stale = await markStale(source, area, index, runStart);
      result.markedStale = stale.markedStale;
      result.deactivated = stale.deactivated;
      result.writes += stale.writes;
    }
    const audit = auditSuspectedDuplicates(index);
    result.suspectedDuplicates = audit.suspected;
    result.suspectedDuplicateRate = audit.rate;
    if (audit.active > 0 && audit.rate > 0.05) {
      console.warn(`[ingest] ${source}/${area.id} suspected duplicate rate ${(audit.rate * 100).toFixed(1)}% exceeds 5% target`);
    }
  } catch (e) {
    result.errors.push(e instanceof Error ? e.message : String(e));
    if (!(e instanceof SkipSource)) console.error(`[ingest] ${source}/${area.id} failed:`, e);
  }
  result.durationMs = Date.now() - started;
  await db.collection("ingestRuns").doc(`${runStart.toISOString()}_${source}_${area.id}`).set({
    ...result, runAt: Timestamp.fromDate(runStart),
  });
  await recordSourceHealth(result, Timestamp.fromDate(runStart));
  // Supply telemetry per month: records seen per source.
  await db.collection("treasury").doc(utcMonthKey()).set({
    supply: { [`${source}.fetched`]: FieldValue.increment(result.fetched), [`${source}.runs`]: FieldValue.increment(1) },
    dedupe: {
      [`${source}.merged`]: FieldValue.increment(result.merged),
      [`${source}.fuzzyMerged`]: FieldValue.increment(result.fuzzyMerged),
      [`${source}.candidates`]: FieldValue.increment(result.created + result.merged),
      [`${source}.suspectedRate`]: result.suspectedDuplicateRate,
    },
    // Free-tier budget telemetry: writes issued and writes avoided, per source.
    writes: {
      [`${source}.writes`]: FieldValue.increment(result.writes),
      [`${source}.unchanged`]: FieldValue.increment(result.unchanged),
      [`${source}.rejected`]: FieldValue.increment(result.rejected),
    },
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
    isFree: typeof r.isFree === "boolean" ? r.isFree : undefined,
    priceMin: typeof r.priceMin === "number" && Number.isFinite(r.priceMin) ? r.priceMin : undefined,
    website: cleanUrl(r.website),
    imageURL: cleanUrl(r.imageURL),
    tags: Array.isArray(r.tags) ? r.tags.filter((t): t is string => typeof t === "string").map((t) => cleanText(t, 40)).slice(0, 8) : [],
  };
}

export const runIngest = onCall(
  { secrets: [TICKETMASTER_KEY, NPS_API_KEY, SERPAPI_KEY], timeoutSeconds: 540, memory: "512MiB" },
  async (req) => {
    const staff = await requireAdmin(req.auth);
    const area = areaById(safeString(req.data?.areaId, LAUNCH_AREAS[0].id));
    if (!area) throw new HttpsError("invalid-argument", "Unknown launch area.");
    const reason = req.data?.reason ? staffReason(req.data.reason) : "Manual source ingestion requested by staff";

    // Payload mode: normalized records, straight into the store.
    if (Array.isArray(req.data?.payload)) {
      const source = safeString(req.data?.source) as SourceId;
      if (!SOURCES.includes(source) && source !== "organizer") throw new HttpsError("invalid-argument", "Unknown source.");
      const records = (req.data.payload as unknown[]).slice(0, 2000)
        .map((r) => coercePayloadRecord(r, area))
        .filter((r): r is NormalizedEvent => r !== null && r.source === source);
      const before = (await db.doc(`sourceHealth/${area.id}_${source}`).get()).data() ?? null;
      return auditedStaffJob(staff, "ingest:run", `${area.id}/${source}`, before, reason,
        async () => ({ results: [await runSource(source, area, {}, records)] }));
    }

    const requested = Array.isArray(req.data?.sources)
      ? (req.data.sources as unknown[]).map((s) => safeString(s)).filter((s): s is SourceId => SOURCES.includes(s as SourceId))
      : SOURCES;
    const keys = keysFromSecrets();
    const before = await Promise.all(requested.map(async (s) => ({ source: s,
      health: (await db.doc(`sourceHealth/${area.id}_${s}`).get()).data() ?? null })));
    return auditedStaffJob(staff, "ingest:run", area.id, before, reason, async () => {
      const results: IngestResult[] = [];
      for (const s of requested) results.push(await runSource(s, area, keys));
      return { results };
    });
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
  const query = db.collection("events")
    .where("areaId", "==", area.id)
    .where("active", "==", true);
  const upcoming: FirebaseFirestore.DocumentData[] = [];
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    const snap = await (cursor ? query.startAfter(cursor) : query).limit(500).get();
    for (const d of snap.docs) {
      const data = d.data();
      if ((data.date as Timestamp)?.toMillis?.() >= now.getTime()) upcoming.push(data);
    }
    if (snap.size < 500) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
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
  const staff = await requireAdmin(req.auth);
  const area = areaById(safeString(req.data?.areaId, LAUNCH_AREAS[0].id));
  if (!area) throw new HttpsError("invalid-argument", "Unknown launch area.");
  const before = (await db.doc(`treasury/${utcMonthKey()}`).get()).data()?.supplyReport ?? null;
  return auditedStaffJob(staff, "supply:report", area.id, before,
    req.data?.reason ? staffReason(req.data.reason) : "Recompute event supply report", () => computeSupplyReport(area));
});

/** Public, read-only: which launch areas exist (the app uses this to explain coverage honestly). */
export const listLaunchAreas = onCall(async () => ({
  areas: LAUNCH_AREAS.map((a) => ({ id: a.id, name: a.name, center: a.center, radiusMiles: a.radiusMiles })),
}));
