/**
 * Personalized event ranking.
 *
 * Nothing read user interests before this file existed. They were collected at
 * onboarding, written to users/{uid}.interests, and then used by no query on
 * either side — the personalization the product promises was a stored field and
 * nothing else.
 *
 * THE ONE RULE: RANK, NEVER FILTER.
 *
 * Every signal below is a weighted term added to a score. Not one of them can
 * remove an event from the result. This is deliberate and it is the difference
 * between a recommender and a cage:
 *
 *   - Interests are a guess made once, at onboarding, before the user had seen
 *     anything. Hard-filtering on them means someone who tapped "Sports" can
 *     never discover the cleanup two blocks away, and nothing in the product
 *     would ever tell them it existed.
 *   - Distance is the strongest term here, but a genuinely special event 20
 *     miles out should still be reachable — it just has to be better to win.
 *   - A cold-start user (no interests, no follows, no history) gets every
 *     signal at its neutral value and falls back to "soon and nearby", which is
 *     a defensible default, not an empty screen.
 *
 * So the worst case for any event is that it ranks last. The worst case for a
 * filter is that a user never learns the event happened.
 *
 * WEIGHTS. Tuned by hand, documented, and summing to 1.0 so a score reads as a
 * percentage and a weight change is obviously a product decision rather than a
 * hidden one. Every component returns 0..1.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { Timestamp } from "firebase-admin/firestore";
import { db, requireUid, enforceRateLimit, safeText } from "./common.js";

export const WEIGHTS = {
  /** Does it match what they said they liked, or what they've actually attended? */
  interest: 0.26,
  /** Can they get there? The single best predictor of whether someone goes. */
  distance: 0.30,
  /** A friend is going. The one signal no search engine can produce. */
  social: 0.18,
  /** Soon enough to act on, far enough away to plan. */
  timing: 0.14,
  /** Haven't seen this organizer/category lately — keeps the feed from ossifying. */
  novelty: 0.12,
} as const;

/** Sanity: the weights must sum to 1. A typo here silently reweights the feed. */
export const WEIGHT_SUM = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);

/** The app's interest labels map onto ingest categories. */
export const INTEREST_TO_CATEGORY: Record<string, string[]> = {
  outdoors: ["Cleanup", "Sports", "Market", "Festival"],
  fitness: ["Sports", "Cleanup"],
  volunteering: ["Volunteer", "Cleanup"],
  arts: ["Workshop", "Festival", "Market"],
  music: ["Festival", "Social"],
  food: ["Market", "Festival", "Social"],
  tech: ["Hackathon", "Workshop", "Meetup"],
  learning: ["Workshop", "Meetup", "Hackathon"],
  community: ["Meetup", "Social", "Volunteer"],
  family: ["Festival", "Market", "Workshop"],
};

export interface RankableEvent {
  id: string;
  category?: string;
  organizer?: string;
  latitude?: number;
  longitude?: number;
  startMs: number;
  tags?: string[];
}

export interface RankingContext {
  interests: string[];
  /** Categories the user has actually attended — behaviour beats stated preference. */
  attendedCategories: Record<string, number>;
  /** eventId -> number of followed accounts going. */
  friendsGoing: Record<string, number>;
  /** Organizers seen recently in this user's feed, for the novelty term. */
  recentOrganizers: Record<string, number>;
  lat?: number;
  lng?: number;
  nowMs: number;
}

const MILE_M = 1609.344;

export function haversineMiles(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return (2 * R * Math.asin(Math.sqrt(h))) / MILE_M;
}

/**
 * Stated interests, plus what they've actually done.
 *
 * Attendance outranks the onboarding tap: someone who selected "tech" but has
 * been to four cleanups is telling us something truer than their first-run
 * answer. Neutral 0.5 when we know nothing — NOT 0, which would push every
 * event below the midpoint for a brand-new user and make the whole feed look
 * like a rejection.
 */
export function interestScore(ev: RankableEvent, ctx: RankingContext): number {
  const cat = ev.category ?? "";
  const hasStated = ctx.interests.length > 0;
  const attendedTotal = Object.values(ctx.attendedCategories).reduce((a, b) => a + b, 0);
  if (!hasStated && attendedTotal === 0) return 0.5;

  let stated = 0;
  if (hasStated) {
    const wanted = new Set(ctx.interests.flatMap((i) => INTEREST_TO_CATEGORY[i.toLowerCase()] ?? []));
    stated = wanted.has(cat) ? 1 : 0;
  }

  let behavioural = 0;
  if (attendedTotal > 0) {
    behavioural = Math.min(1, (ctx.attendedCategories[cat] ?? 0) / Math.max(1, attendedTotal / 2));
  }

  if (!hasStated) return behavioural;
  if (attendedTotal === 0) return stated;
  return 0.4 * stated + 0.6 * behavioural;
}

/**
 * Distance decay. 0 mi -> 1, ~5 mi -> 0.5, 25 mi -> ~0.17, and never 0: a
 * distant event keeps a small positive score so it can still be surfaced by
 * being outstanding on every other axis.
 */
export function distanceScore(ev: RankableEvent, ctx: RankingContext): number {
  if (ctx.lat === undefined || ctx.lng === undefined) return 0.5;
  if (ev.latitude === undefined || ev.longitude === undefined) return 0.4;   // unknown, mildly penalised
  const miles = haversineMiles(ctx.lat, ctx.lng, ev.latitude, ev.longitude);
  return 1 / (1 + miles / 5);
}

/**
 * Friends going. Saturating, not linear: the jump from nobody to one friend is
 * the whole effect, and three friends is not three times as persuasive.
 */
export function socialScore(ev: RankableEvent, ctx: RankingContext): number {
  const n = ctx.friendsGoing[ev.id] ?? 0;
  if (n <= 0) return 0;
  return Math.min(1, 0.7 + 0.15 * Math.min(2, n - 1));
}

/**
 * Timing. Peaks 2–7 days out: far enough to plan, near enough to feel real.
 * Tonight scores well but not best; six weeks out is nearly weightless.
 */
export function timingScore(ev: RankableEvent, ctx: RankingContext): number {
  const days = (ev.startMs - ctx.nowMs) / 86_400_000;
  if (days < 0) return 0;              // past; ranking cannot resurrect it
  if (days < 0.5) return 0.55;         // today — good, but hard to act on
  if (days <= 1) return 0.8;
  if (days <= 7) return 1;
  if (days <= 14) return 0.7;
  if (days <= 30) return 0.4;
  return 0.15;
}

/**
 * Novelty / diversity. An organizer the user has already seen a lot of this
 * session is damped, so one prolific library does not own the whole feed. This
 * is a demotion, never a removal — the fourth library event still ranks, just
 * below the first cleanup.
 */
export function noveltyScore(ev: RankableEvent, ctx: RankingContext): number {
  const seen = ctx.recentOrganizers[ev.organizer ?? ""] ?? 0;
  return 1 / (1 + seen * 0.6);
}

export interface ScoredEvent { id: string; score: number; parts: Record<string, number> }

/** Score one event. Exported so tests can assert a single term in isolation. */
export function scoreEvent(ev: RankableEvent, ctx: RankingContext): ScoredEvent {
  const parts = {
    interest: interestScore(ev, ctx),
    distance: distanceScore(ev, ctx),
    social: socialScore(ev, ctx),
    timing: timingScore(ev, ctx),
    novelty: noveltyScore(ev, ctx),
  };
  const score =
    parts.interest * WEIGHTS.interest +
    parts.distance * WEIGHTS.distance +
    parts.social * WEIGHTS.social +
    parts.timing * WEIGHTS.timing +
    parts.novelty * WEIGHTS.novelty;
  return { id: ev.id, score, parts };
}

/**
 * Rank a whole list.
 *
 * Category diversity is applied HERE rather than as a per-event term, because
 * it is a property of the result set, not of any event: walk the sorted list
 * and damp each repeat of a category already used higher up. The top result is
 * never touched, so the best event always leads.
 *
 * Output length always equals input length. This function cannot drop an event.
 */
export function rankEvents(events: RankableEvent[], ctx: RankingContext): ScoredEvent[] {
  const scored = events.map((e) => scoreEvent(e, ctx));
  scored.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));

  const byId = new Map(events.map((e) => [e.id, e]));
  const usedCategory: Record<string, number> = {};
  const diversified = scored.map((s) => {
    const cat = byId.get(s.id)?.category ?? "";
    const seen = usedCategory[cat] ?? 0;
    usedCategory[cat] = seen + 1;
    // 1st of a category untouched, 2nd x0.93, 3rd x0.87, floor 0.7.
    const damp = Math.max(0.7, 1 - seen * 0.07);
    return { ...s, score: s.score * damp, parts: { ...s.parts, diversity: damp } };
  });
  diversified.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
  return diversified;
}

// ---------------------------------------------------------------------------
// Server plumbing
// ---------------------------------------------------------------------------

const MAX_CANDIDATES = 400;

/** Build a user's ranking context from Firestore. Shared by the callable and C/E. */
export async function loadContext(uid: string, lat?: number, lng?: number, nowMs = Date.now()): Promise<RankingContext> {
  const [userSnap, followingSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection(`users/${uid}/following`).where("kind", "==", "user").get(),
  ]);
  const u = userSnap.data() ?? {};

  const interests: string[] = Array.isArray(u.interests)
    ? u.interests.map((i: unknown) => safeText(i, 40)).filter(Boolean).slice(0, 20) : [];

  // Behaviour: categories of events already attended.
  const attendedCategories: Record<string, number> = {};
  const attended: string[] = Array.isArray(u.checkedInEventIDs) ? u.checkedInEventIDs.slice(-40) : [];
  if (attended.length) {
    const docs = await Promise.all(attended.slice(0, 30).map((id: string) => db.collection("events").doc(String(id)).get()));
    for (const d of docs) {
      const c = String(d.data()?.category ?? "");
      if (c) attendedCategories[c] = (attendedCategories[c] ?? 0) + 1;
    }
  }

  // Friends going, for the events we are about to rank. Read from the
  // attendee subcollections of followed users' RSVPs is expensive; instead we
  // read each followed user's rsvpEventIDs, which is one doc each.
  const friendsGoing: Record<string, number> = {};
  const friendIds = followingSnap.docs.map((d) => d.id).slice(0, 100);
  if (friendIds.length) {
    const friendDocs = await Promise.all(friendIds.map((id) => db.collection("users").doc(id).get()));
    for (const f of friendDocs) {
      const fd = f.data();
      if (!fd) continue;
      // Respect the privacy model: a "friends"-visibility user's RSVPs are only
      // visible to accounts they follow back. Default is friends.
      const visibility = fd.activityPrivacy === "public" ? "public" : "friends";
      if (visibility === "friends" && !(await db.doc(`users/${f.id}/following/${uid}`).get()).exists) continue;
      for (const eid of (Array.isArray(fd.rsvpEventIDs) ? fd.rsvpEventIDs : [])) {
        const k = String(eid);
        friendsGoing[k] = (friendsGoing[k] ?? 0) + 1;
      }
    }
  }

  return { interests, attendedCategories, friendsGoing, recentOrganizers: {}, lat, lng, nowMs };
}

/**
 * Rank the area's upcoming events for one user.
 *
 * Internal, so C (notifications) and E (partner surfacing) call the same code
 * path the user sees. A second ranking implementation for notifications would
 * drift from this one within a sprint.
 */
export async function recommendFor(
  uid: string, areaId: string, lat?: number, lng?: number, limit = 50, nowMs = Date.now(),
): Promise<ScoredEvent[]> {
  const snap = await db.collection("events")
    .where("areaId", "==", areaId)
    .where("active", "==", true)
    .limit(MAX_CANDIDATES)
    .get();

  const ctx = await loadContext(uid, lat, lng, nowMs);
  const candidates: RankableEvent[] = snap.docs
    .filter((d) => d.data()?.hidden !== true)
    .map((d) => {
      const x = d.data();
      const ms = (x.date as Timestamp)?.toMillis?.() ?? 0;
      return {
        id: d.id, category: x.category, organizer: x.organizer,
        latitude: typeof x.latitude === "number" ? x.latitude : undefined,
        longitude: typeof x.longitude === "number" ? x.longitude : undefined,
        startMs: ms,
        tags: Array.isArray(x.tags) ? x.tags : [],
      };
    })
    // The ONLY exclusion in this file, and it is not personalization: an event
    // that already happened cannot be attended. Everything else is ranked.
    .filter((e) => e.startMs >= nowMs);

  return rankEvents(candidates, ctx).slice(0, limit);
}

export const recommendedEvents = onCall(async (req) => {
  const uid = requireUid(req.auth);
  await enforceRateLimit(uid, "recommendedEvents");

  const areaId = safeText(req.data?.areaId, 60) || "san-jose-ca";
  const lat = Number(req.data?.lat);
  const lng = Number(req.data?.lng);
  const hasLoc = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  const limit = Math.min(100, Math.max(1, Math.floor(Number(req.data?.limit ?? 50)) || 50));

  const ranked = await recommendFor(uid, areaId, hasLoc ? lat : undefined, hasLoc ? lng : undefined, limit);
  if (!ranked.length) throw new HttpsError("not-found", "No upcoming events in this area yet.");

  return {
    areaId,
    personalized: true,
    // `parts` ships so the client can explain a placement ("a friend is going")
    // and so a bad ranking is debuggable from a device instead of by guesswork.
    events: ranked.map((r) => ({ id: r.id, score: Number(r.score.toFixed(4)), parts: r.parts })),
  };
});
