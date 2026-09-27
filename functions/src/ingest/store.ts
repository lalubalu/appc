/**
 * The normalized /events store: write-time dedupe, provenance, staleness.
 *
 * ONE PASS, AT WRITE TIME. Every record that any fetcher produces goes through
 * `upsertBatch`, which:
 *   1. drops anything outside the launch area or the 120-day horizon;
 *   2. finds the same event by its own source key (`sourceKeys` array) and
 *      refreshes it;
 *   3. otherwise looks for a CROSS-SOURCE duplicate — same normalised title,
 *      start within 120 minutes, same venue key or within 300 m — and merges
 *      into it, recording the extra feed in `sources[]`;
 *   4. otherwise creates a new document with a stable id.
 *
 * STALENESS, NOT DELETION. After a source's records are processed, any FUTURE
 * event from that source not seen this run gets `missedCycles + 1`; at
 * STALE_CYCLES it is marked `active: false`. Cancellations therefore disappear
 * from the app within a few cycles without ever deleting history, and a feed
 * outage (zero records) is treated as "nothing seen" only when the fetch
 * succeeded — a thrown fetch never marks anything stale.
 *
 * The whole area's active corpus is loaded into memory once per run (a few
 * thousand documents) so dedupe costs one query, not one per record.
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../common.js";
import type { LaunchArea } from "./areas.js";
import { isInsideArea } from "./areas.js";
import type { NormalizedEvent, SourceId } from "./types.js";
import { CATEGORY_ICON, CATEGORY_POINTS } from "./types.js";
import { eventDocId, sourceKey, startBucket, titleKey, venueKey } from "./normalize.js";
import { distanceMeters } from "../common.js";

export const STALE_CYCLES = 3;
const HORIZON_DAYS = 120;
const MATCH_WINDOW_MS = 120 * 60 * 1000;
const MATCH_DISTANCE_M = 300;
const BATCH = 400;

interface IndexedEvent {
  id: string;
  data: FirebaseFirestore.DocumentData;
}

interface AreaIndex {
  bySourceKey: Map<string, IndexedEvent>;
  byTitleKey: Map<string, IndexedEvent[]>;
  all: IndexedEvent[];
}

export interface UpsertStats {
  created: number; updated: number; merged: number; skipped: number;
}

/**
 * Load every UPCOMING event in the area once — active or not.
 *
 * Inactive events must be in the index too: a cancelled-then-reinstated event
 * that reappears in its feed has to reattach to its existing document (with the
 * provenance other feeds already merged into it), not be recreated from scratch.
 */
export async function loadAreaIndex(area: LaunchArea, now = new Date()): Promise<AreaIndex> {
  const query = db.collection("events")
    .where("areaId", "==", area.id)
    .where("date", ">=", Timestamp.fromMillis(now.getTime() - 2 * 86_400_000))
    .orderBy("date");
  const index: AreaIndex = { bySourceKey: new Map(), byTitleKey: new Map(), all: [] };
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    const snap = await (cursor ? query.startAfter(cursor) : query).limit(500).get();
    snap.forEach((d) => addToIndex(index, { id: d.id, data: d.data() }));
    if (snap.size < 500) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  return index;
}

function addToIndex(index: AreaIndex, ev: IndexedEvent) {
  index.all.push(ev);
  for (const k of (ev.data.sourceKeys as string[] | undefined) ?? []) index.bySourceKey.set(k, ev);
  const tk = String(ev.data.titleKey ?? "");
  if (tk) {
    const list = index.byTitleKey.get(tk) ?? [];
    list.push(ev);
    index.byTitleKey.set(tk, list);
  }
}

/**
 * Cheap post-write audit of duplicates that survived the exact-key matcher.
 * It is intentionally a heuristic: a warning for review, not a deletion rule.
 * Grouping by hour keeps the scan bounded even for a large launch-area corpus.
 */
export function auditSuspectedDuplicates(index: AreaIndex): { active: number; suspected: number; rate: number } {
  const byHour = new Map<number, IndexedEvent[]>();
  let active = 0;
  let suspected = 0;
  for (const ev of [...index.all].sort((a, b) =>
    (a.data.date?.toMillis?.() ?? 0) - (b.data.date?.toMillis?.() ?? 0))) {
    const data = ev.data;
    if (data.active === false || data.hidden === true) continue;
    const millis = data.date?.toMillis?.();
    if (!Number.isFinite(millis)) continue;
    active++;
    const hour = Math.floor(millis / 3_600_000);
    const key = String(data.titleKey || titleKey(String(data.title || "")));
    const words = new Set(key.split(" ").filter(Boolean));
    let found = false;
    for (let h = hour - 2; h <= hour && !found; h++) {
      for (const prior of byHour.get(h) ?? []) {
        const other = prior.data;
        if (Math.abs(other.date.toMillis() - millis) > MATCH_WINDOW_MS) continue;
        const priorWords = new Set(String(other.titleKey || titleKey(String(other.title || ""))).split(" ").filter(Boolean));
        if (!words.size || !priorWords.size) continue;
        const common = [...words].filter((word) => priorWords.has(word)).length;
        if (common / Math.max(words.size, priorWords.size) < 0.8) continue;
        const lat = Number(data.latitude), lng = Number(data.longitude);
        const otherLat = Number(other.latitude), otherLng = Number(other.longitude);
        const near = data.latitude != null && data.longitude != null && other.latitude != null && other.longitude != null
          && Number.isFinite(lat) && Number.isFinite(lng) && Number.isFinite(otherLat) && Number.isFinite(otherLng)
          && distanceMeters(lat, lng, otherLat, otherLng) <= MATCH_DISTANCE_M;
        const venue = String(data.venueKey || venueKey(String(data.locationName || "")));
        const otherVenue = String(other.venueKey || venueKey(String(other.locationName || "")));
        if (near || (venue && venue === otherVenue)) { found = true; break; }
      }
    }
    if (found) suspected++;
    const bucket = byHour.get(hour) ?? [];
    bucket.push(ev);
    byHour.set(hour, bucket);
  }
  return { active, suspected, rate: active ? suspected / active : 0 };
}

/** Does an existing indexed event describe the same real-world event as `rec`? */
export function isSameEvent(existing: FirebaseFirestore.DocumentData, rec: NormalizedEvent): boolean {
  const start: Timestamp | undefined = existing.date;
  if (!start) return false;
  if (Math.abs(start.toMillis() - rec.start.getTime()) > MATCH_WINDOW_MS) return false;
  const vk1 = String(existing.venueKey ?? "");
  const vk2 = venueKey(rec.locationName);
  const lat1 = Number(existing.latitude), lng1 = Number(existing.longitude);
  if (existing.latitude != null && existing.longitude != null && Number.isFinite(lat1) && Number.isFinite(lng1)
      && rec.latitude !== undefined && rec.longitude !== undefined) {
    if (distanceMeters(lat1, lng1, rec.latitude, rec.longitude) <= MATCH_DISTANCE_M) return true;
    // Coordinates disagree: even identically named venues can be miles apart.
    return false;
  }
  if (vk1 && vk2 && vk1 === vk2) return true;
  // One side has no venue information: distinctive title + time is our last resort.
  return !vk1 || !vk2;
}

/** Score how much a record knows, so a merge keeps the richer description/coords. */
function richness(d: { description?: string; latitude?: unknown; imageURL?: unknown; website?: unknown }): number {
  return (d.description?.length ?? 0) / 100 + (d.latitude !== undefined && d.latitude !== null ? 3 : 0)
    + (d.imageURL ? 1 : 0) + (d.website ? 1 : 0);
}

function fullDocument(rec: NormalizedEvent, now: Timestamp): FirebaseFirestore.DocumentData {
  const doc: FirebaseFirestore.DocumentData = {
    title: rec.title,
    description: rec.description,
    organizer: rec.organizer,
    date: Timestamp.fromDate(rec.start),
    time: rec.time,
    locationName: rec.locationName,
    attendeeCount: 0,
    maxAttendees: null,
    category: rec.category,
    imagePlaceholder: CATEGORY_ICON[rec.category],
    pointValue: CATEGORY_POINTS[rec.category],
    creatorID: "system:ingest",
    createdAt: now,
    // Visibility flags the client queries on.
    hidden: false,
    broadcast: true,
    active: true,
    // Provenance.
    source: rec.source,
    sourceEventId: rec.sourceEventId,
    sourceKeys: [sourceKey(rec.source, rec.sourceEventId)],
    sources: [{ source: rec.source, sourceEventId: rec.sourceEventId, url: rec.website ?? null, lastSeenAt: now }],
    areaId: rec.areaId,
    titleKey: titleKey(rec.title),
    venueKey: venueKey(rec.locationName),
    startBucket: startBucket(rec.start),
    isFree: rec.isFree,
    tags: rec.tags.slice(0, 8),
    ingestedAt: now,
    lastSeenAt: now,
    missedCycles: 0,
  };
  if (rec.end) doc.endDate = Timestamp.fromDate(rec.end);
  if (rec.latitude !== undefined) doc.latitude = rec.latitude;
  if (rec.longitude !== undefined) doc.longitude = rec.longitude;
  if (rec.priceMin !== undefined) doc.priceMin = rec.priceMin;
  if (rec.website) doc.website = rec.website;
  if (rec.imageURL) doc.imageURL = rec.imageURL;
  return doc;
}

/** Fields refreshed on every sighting from the PRIMARY source. */
function refreshFromPrimary(rec: NormalizedEvent): FirebaseFirestore.DocumentData {
  const upd: FirebaseFirestore.DocumentData = {
    title: rec.title, description: rec.description, organizer: rec.organizer,
    date: Timestamp.fromDate(rec.start), time: rec.time, locationName: rec.locationName,
    category: rec.category, imagePlaceholder: CATEGORY_ICON[rec.category], pointValue: CATEGORY_POINTS[rec.category],
    titleKey: titleKey(rec.title), venueKey: venueKey(rec.locationName), startBucket: startBucket(rec.start),
    isFree: rec.isFree, tags: rec.tags.slice(0, 8),
  };
  if (rec.end) upd.endDate = Timestamp.fromDate(rec.end);
  if (rec.latitude !== undefined) upd.latitude = rec.latitude;
  if (rec.longitude !== undefined) upd.longitude = rec.longitude;
  if (rec.priceMin !== undefined) upd.priceMin = rec.priceMin;
  if (rec.website) upd.website = rec.website;
  if (rec.imageURL) upd.imageURL = rec.imageURL;
  return upd;
}

/** Fill blanks from a secondary source without overwriting the primary's facts. */
function fillFromSecondary(existing: FirebaseFirestore.DocumentData, rec: NormalizedEvent): FirebaseFirestore.DocumentData {
  const upd: FirebaseFirestore.DocumentData = {};
  if ((existing.latitude === undefined || existing.latitude === null) && rec.latitude !== undefined) {
    upd.latitude = rec.latitude; upd.longitude = rec.longitude;
  }
  if (!existing.website && rec.website) upd.website = rec.website;
  if (!existing.imageURL && rec.imageURL) upd.imageURL = rec.imageURL;
  if ((existing.description?.length ?? 0) < rec.description.length) upd.description = rec.description;
  if (existing.isFree === true && rec.isFree === false && rec.priceMin !== undefined) {
    upd.isFree = false; upd.priceMin = rec.priceMin;
  }
  return upd;
}

export function isWithinHorizon(rec: NormalizedEvent, now = Date.now()): boolean {
  const t = rec.start.getTime();
  return Number.isFinite(t) && t >= now - 86_400_000 && t <= now + HORIZON_DAYS * 86_400_000;
}

/**
 * Write a batch of normalized records for one source into the area's store.
 * `index` is mutated so later records in the same run see earlier writes.
 */
export async function upsertBatch(
  records: NormalizedEvent[], area: LaunchArea, index: AreaIndex, runStart: Date,
): Promise<UpsertStats> {
  const stats: UpsertStats = { created: 0, updated: 0, merged: 0, skipped: 0 };
  const now = Timestamp.fromDate(runStart);
  let batch = db.batch();
  let pending = 0;
  const flush = async () => { if (pending) { await batch.commit(); batch = db.batch(); pending = 0; } };
  const queue = async (fn: (b: FirebaseFirestore.WriteBatch) => void) => {
    fn(batch); pending++;
    if (pending >= BATCH) await flush();
  };

  for (const rec of records) {
    if (!rec.title || !isWithinHorizon(rec, runStart.getTime())) { stats.skipped++; continue; }
    if (rec.latitude !== undefined && rec.longitude !== undefined && !isInsideArea(area, rec.latitude, rec.longitude)) {
      stats.skipped++; continue;   // geographic scoping: never ingest outside the launch area
    }
    const key = sourceKey(rec.source, rec.sourceEventId);
    const seen = index.bySourceKey.get(key);

    if (seen) {
      const isPrimary = seen.data.source === rec.source;
      const upd: FirebaseFirestore.DocumentData = {
        ...(isPrimary ? refreshFromPrimary(rec) : fillFromSecondary(seen.data, rec)),
        lastSeenAt: now, missedCycles: 0, active: true,
        sources: ((seen.data.sources as Array<Record<string, unknown>>) ?? []).map((s) =>
          s.source === rec.source && s.sourceEventId === rec.sourceEventId ? { ...s, lastSeenAt: now, url: rec.website ?? s.url ?? null } : s),
      };
      Object.assign(seen.data, upd);
      await queue((b) => b.set(db.collection("events").doc(seen.id), upd, { merge: true }));
      stats.updated++;
      continue;
    }

    const candidates = index.byTitleKey.get(titleKey(rec.title)) ?? [];
    const match = candidates.find((c) => isSameEvent(c.data, rec));
    if (match) {
      const richer = richness(rec) > richness(match.data as { description?: string; latitude?: unknown; imageURL?: unknown; website?: unknown });
      const upd: FirebaseFirestore.DocumentData = {
        ...fillFromSecondary(match.data, rec),
        ...(richer && rec.description.length > (match.data.description?.length ?? 0) ? { description: rec.description } : {}),
        sourceKeys: FieldValue.arrayUnion(key),
        sources: FieldValue.arrayUnion({ source: rec.source, sourceEventId: rec.sourceEventId, url: rec.website ?? null, lastSeenAt: now }),
        lastSeenAt: now, missedCycles: 0, active: true,
      };
      // Keep the in-memory index truthful for the rest of the run.
      (match.data.sourceKeys as string[]) = [...((match.data.sourceKeys as string[]) ?? []), key];
      (match.data.sources as unknown[]) = [...((match.data.sources as unknown[]) ?? []), { source: rec.source, sourceEventId: rec.sourceEventId }];
      match.data.lastSeenAt = now;
      index.bySourceKey.set(key, match);
      await queue((b) => b.set(db.collection("events").doc(match.id), upd, { merge: true }));
      stats.merged++;
      continue;
    }

    const id = eventDocId(rec.source, rec.sourceEventId);
    const doc = fullDocument(rec, now);
    addToIndex(index, { id, data: doc });
    await queue((b) => b.set(db.collection("events").doc(id), doc, { merge: true }));
    stats.created++;
  }
  await flush();
  return stats;
}

/**
 * Mark future events from `source` that this run did not see. Uses the in-memory
 * index (already refreshed by upsertBatch), so no extra query is needed.
 */
export async function markStale(
  source: SourceId, area: LaunchArea, index: AreaIndex, runStart: Date,
): Promise<{ markedStale: number; deactivated: number }> {
  let markedStale = 0, deactivated = 0;
  let batch = db.batch();
  let pending = 0;
  const runMs = runStart.getTime();
  for (const ev of index.all) {
    if (ev.data.source !== source || ev.data.active !== true) continue;
    const lastSeen: Timestamp | undefined = ev.data.lastSeenAt;
    if (lastSeen && lastSeen.toMillis() >= runMs) continue;          // seen this run
    const start: Timestamp | undefined = ev.data.date;
    if (!start || start.toMillis() < runMs) continue;                 // already past — leave history alone
    const missed = (Number(ev.data.missedCycles) || 0) + 1;
    const upd: FirebaseFirestore.DocumentData = { missedCycles: missed };
    if (missed >= STALE_CYCLES) { upd.active = false; upd.inactiveAt = Timestamp.fromDate(runStart); deactivated++; }
    markedStale++;
    Object.assign(ev.data, upd);
    batch.set(db.collection("events").doc(ev.id), upd, { merge: true });
    if (++pending >= BATCH) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (pending) await batch.commit();
  return { markedStale, deactivated };
}
