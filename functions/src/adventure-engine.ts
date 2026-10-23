/**
 * Deterministic Adventure Planner engine — the planner used when no model key is
 * configured or the model call fails. No vendor, no cost, no invented facts.
 *
 * Same guarantee as the model path: only places from the client's candidate list,
 * with OUR names and coordinates. Every sentence it writes is built from a real
 * field (category, distance, posted hours, Open-Meteo conditions, sunset time).
 *
 * How a plan is made:
 *   1. Usable candidates: real coordinates, within reach for the time available,
 *      open (OSM opening_hours) and in daylight when they are outdoors.
 *   2. Score: the user's picks first, then data quality, distance and conditions.
 *   3. Shape: an anchor (best match), 1–3 complements that differ from it (a contrast,
 *      a place to rest by the water or in a garden, a viewpoint finish near sunset).
 *   4. Route: nearest neighbour from the start, improved by 2-opt over a loop that
 *      returns to the start, so the outing ends near where it began.
 *   5. Times: time per stop by kind, walking under 1.2 km (5 km/h, 1.3 circuity) and
 *      driving otherwise (35 km/h urban + 2 min to park), fitted to the requested
 *      duration within ±10%; nothing is scheduled while closed or after dark.
 *   6. Words: a specific "why" per stop and 1–3 tips, with varied phrasing.
 */

import { normalizeInterests } from "./ranking.js";

export interface EngineCandidate {
  id: string;
  name: string;
  category?: string;
  latitude?: number;
  longitude?: number;
  hours?: string;
  description?: string;
  hasPhoto?: boolean;
}

export interface HourlyConditions { ms: number; precipProb: number; tempF: number; windKmh: number; code: number }

export interface Conditions {
  utcOffsetSeconds: number;
  sunriseMs: number;
  sunsetMs: number;
  current: { tempF: number; code: number; windKmh: number; precipMm: number };
  hourly: HourlyConditions[];
}

export interface EngineInput {
  lat: number;
  lng: number;
  nowMs: number;
  durationMinutes: number;
  /** The app's labels as the user picked them ("Parks", "Trails", …). */
  interests: string[];
  candidates: EngineCandidate[];
  conditions: Conditions | null;
  /** Different seeds give different (equally good) plans: the regenerate path. */
  seed: number;
  /** Stops of the user's previous plan, avoided when an equally good option exists. */
  previousStopIds?: string[];
}

export interface EngineStop {
  placeId: string;
  name: string;
  category: string | null;
  latitude: number;
  longitude: number;
  order: number;
  /** Travel to this stop plus time there, so the stops add up to the whole outing. */
  minutes: number;
  why: string;
  arriveMs: number;
  leaveMs: number;
  travelMinutes: number;
  mode: "walk" | "drive";
  kind: Kind;
}

export interface EnginePlan {
  title: string;
  intro: string;
  tips: string[];
  stops: EngineStop[];
  totalMinutes: number;
}

export class EngineError extends Error {
  constructor(public readonly code: "not-enough-places" | "nothing-open", message: string) { super(message); }
}

// ── Kinds ───────────────────────────────────────────────────────────────────

export type Kind = "trail" | "reserve" | "park" | "garden" | "playground" | "water" | "viewpoint" | "sports" | "community";

/** Minutes at a stop: [shortest sensible, longest useful]. */
export const DWELL: Record<Kind, [number, number]> = {
  trail: [45, 90], reserve: [45, 90], park: [25, 60], garden: [30, 45], playground: [25, 35],
  water: [25, 45], viewpoint: [15, 20], sports: [30, 60], community: [30, 45],
};

const OUTDOOR: Record<Kind, boolean> = {
  trail: true, reserve: true, park: true, garden: true, playground: true, water: true, viewpoint: true,
  sports: false, community: false,
};

/** Shelter when it rains: a community centre is a building; a sports centre often is. */
/** Shelter we can stand behind: a community centre, or a sports centre with posted hours. */
function shelters(u: { kind: Kind; hoursKnown: boolean }): boolean {
  return COVER[u.kind] === 1 || (COVER[u.kind] > 0 && u.hoursKnown);
}

const COVER: Record<Kind, number> = {
  community: 1, sports: 0.6, trail: 0, reserve: 0, park: 0, garden: 0, playground: 0, water: 0, viewpoint: 0,
};

const KIND_INTERESTS: Record<Kind, string[]> = {
  trail: ["hiking", "outdoors"], reserve: ["hiking", "outdoors"], park: ["outdoors", "family"],
  garden: ["outdoors"], playground: ["family"], water: ["outdoors"], viewpoint: ["outdoors"],
  sports: ["fitness"], community: ["community"],
};

/** The app label for each kind, used when the user picked it directly. */
const KIND_LABEL: Record<Kind, string> = {
  trail: "Trails", reserve: "Trails", park: "Parks", garden: "Gardens", playground: "Playgrounds",
  water: "Waterfront", viewpoint: "Scenic", sports: "Sports", community: "Community",
};

const KIND_NOUN: Record<Kind, string> = {
  trail: "trail", reserve: "open-space preserve", park: "park", garden: "garden", playground: "playground",
  water: "waterside spot", viewpoint: "viewpoint", sports: "sports centre", community: "community centre",
};

const MEMBER_ONLY = /\b(club|society|fraternity|sorority|lodge|chapter|alumni association)\b/i;

export function kindOf(c: Pick<EngineCandidate, "name" | "category">): Kind {
  const name = c.name.toLowerCase();
  const category = (c.category ?? "").toLowerCase();
  if (/\b(preserve|open space|nature reserve|wildlife refuge)\b/.test(name) &&
      ["parks", "scenic", "trails", ""].includes(category)) return "reserve";
  switch (category) {
    case "trails": return "trail";
    case "parks": return "park";
    case "gardens": return "garden";
    case "playgrounds": return "playground";
    case "waterfront": return "water";
    case "scenic": return "viewpoint";
    case "sports": return "sports";
    case "community": return "community";
    default: return "park";
  }
}

// ── Geometry, travel and time ───────────────────────────────────────────────

export function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const h = Math.sin(toRad(bLat - aLat) / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(toRad(bLng - aLng) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export const WALK_LIMIT_KM = 1.2;

/** Walk under 1.2 km at 5 km/h with a 1.3 circuity factor; otherwise drive at 35 km/h plus parking. */
export function travel(km: number): { minutes: number; mode: "walk" | "drive" } {
  if (km < WALK_LIMIT_KM) return { minutes: Math.max(1, Math.round((km * 1.3) / 5 * 60)), mode: "walk" };
  return { minutes: Math.round((km * 1.3) / 35 * 60) + 2, mode: "drive" };
}

const MIN = 60_000;

/** Minutes since local midnight for a UTC instant. */
function localMinutes(ms: number, offsetSec: number): number {
  const d = new Date(ms + offsetSec * 1000);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
}

function localWeekday(ms: number, offsetSec: number): number {
  return new Date(ms + offsetSec * 1000).getUTCDay();   // 0 = Sunday
}

export function clockText(ms: number, offsetSec: number): string {
  const m = localMinutes(ms, offsetSec);
  const h24 = Math.floor(m / 60), mm = m % 60;
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${String(mm).padStart(2, "0")} ${h24 < 12 ? "am" : "pm"}`;
}

function hourText(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440;
  const h24 = Math.floor(m / 60), mm = m % 60;
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}${mm ? `:${String(mm).padStart(2, "0")}` : ""} ${h24 < 12 ? "am" : "pm"}`;
}

// ── OSM opening_hours ───────────────────────────────────────────────────────

const DAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

/**
 * Open intervals (local minutes) for one weekday, or null when the hours are missing
 * or use syntax this parser doesn't understand (months, dates, week numbers,
 * holidays-only rules). Later rules override earlier ones for the days they name,
 * as in the OSM specification. sunrise/sunset/dawn/dusk use the given times.
 */
export function openIntervals(hours: string | undefined, weekday: number,
  sun: { sunriseMin: number; sunsetMin: number }): Array<[number, number]> | null {
  if (!hours) return null;
  const text = hours.trim();
  if (!text) return null;
  if (/^24\/7$/.test(text)) return [[0, 1440]];
  let result: Array<[number, number]> | null = null;
  let understood = false;
  for (const raw of text.split(";")) {
    const rule = raw.trim();
    if (!rule) continue;
    if (/^PH\b/.test(rule) || /^SH\b/.test(rule)) continue;   // holiday rules: not today's schedule
    const m = /^((?:(?:Mo|Tu|We|Th|Fr|Sa|Su)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?)(?:,(?:Mo|Tu|We|Th|Fr|Sa|Su)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?)*)?\s*(.*)$/.exec(rule);
    if (!m) return null;
    const daySpec = m[1];
    const timeSpec = (m[2] ?? "").replace(/,\s*PH\b.*$/, "").trim();
    let applies = true;
    if (daySpec) {
      applies = daySpec.split(",").some((part) => {
        const [a, b] = part.split("-");
        const start = DAYS.indexOf(a), end = DAYS.indexOf(b ?? a);
        if (start < 0 || end < 0) return false;
        return start <= end ? weekday >= start && weekday <= end : weekday >= start || weekday <= end;
      });
    }
    if (/^(off|closed)$/i.test(timeSpec)) {
      understood = true;
      if (applies) result = [];
      continue;
    }
    if (/^24\/7$/.test(timeSpec) || timeSpec === "00:00-24:00") {
      understood = true;
      if (applies) result = [[0, 1440]];
      continue;
    }
    const point = (t: string): number | null => {
      if (t === "sunrise") return sun.sunriseMin;
      if (t === "sunset") return sun.sunsetMin;
      if (t === "dawn") return sun.sunriseMin - 30;
      if (t === "dusk") return sun.sunsetMin + 30;
      const hm = /^(\d{1,2}):(\d{2})$/.exec(t);
      return hm ? Number(hm[1]) * 60 + Number(hm[2]) : null;
    };
    const ranges: Array<[number, number]> = [];
    for (const span of timeSpec.split(",")) {
      const parts = span.trim().split("-");
      if (parts.length !== 2) return null;
      const a = point(parts[0].trim()), b = point(parts[1].trim().replace(/\+$/, ""));
      if (a === null || b === null) return null;
      ranges.push([a, b <= a ? 1440 : Math.min(1440, b)]);   // past midnight: open to the end of today
    }
    if (!ranges.length) return null;
    understood = true;
    if (applies) result = ranges;
  }
  if (!understood) return null;
  return result ?? [];   // rules exist but none names today: closed today
}

// ── Seeded choice ───────────────────────────────────────────────────────────

function rng(seed: number): () => number {
  let a = (seed >>> 0) + 0x9e3779b9;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Pick among options within `band` of the best score; the seed decides which. */
function pickNearBest<T>(scored: Array<{ item: T; score: number }>, band: number, random: () => number): T | undefined {
  if (!scored.length) return undefined;
  const sorted = [...scored].sort((a, b) => b.score - a.score);
  const best = sorted[0].score;
  const pool = sorted.filter((s) => s.score >= best - band).slice(0, 4);
  return pool[Math.floor(random() * pool.length)].item;
}

// ── Engine ──────────────────────────────────────────────────────────────────

interface Usable {
  c: EngineCandidate & { latitude: number; longitude: number };
  kind: Kind;
  km: number;                         // from the start
  open: Array<[number, number]> | null;   // local minutes today; null = no posted hours
  hoursKnown: boolean;
  interest: number;
  directPick: boolean;
  base: number;
}

interface Weather {
  rainProb: number;
  maxTempF: number;
  windKmh: number;
  hot: boolean;
  wet: boolean;
  windy: boolean;
}

function weatherFor(cond: Conditions | null, startMs: number, endMs: number): Weather {
  if (!cond) return { rainProb: 0, maxTempF: 70, windKmh: 0, hot: false, wet: false, windy: false };
  const hours = cond.hourly.filter((h) => h.ms >= startMs - 60 * MIN && h.ms <= endMs);
  const rainProb = Math.max(0, ...hours.map((h) => h.precipProb));
  const maxTempF = Math.max(cond.current.tempF, ...hours.map((h) => h.tempF));
  const windKmh = Math.max(cond.current.windKmh, ...hours.map((h) => h.windKmh));
  const raining = cond.current.code >= 51 && cond.current.code <= 82;
  return { rainProb, maxTempF, windKmh, hot: maxTempF > 89.6, wet: rainProb > 50 || raining, windy: windKmh >= 40 };
}

/** Window (absolute ms) in which a stop of this kind may be visited today. */
function allowedWindow(u: Usable, cond: Conditions | null, dayStartMs: number): Array<[number, number]> {
  const off = cond?.utcOffsetSeconds ?? 0;
  const sunrise = cond ? localMinutes(cond.sunriseMs, off) : 7 * 60;
  const sunset = cond ? localMinutes(cond.sunsetMs, off) : 18 * 60;
  let windows: Array<[number, number]>;
  if (u.open) windows = u.open;
  else if (OUTDOOR[u.kind]) windows = [[0, 1440]];
  else windows = [[9 * 60, 18 * 60]];   // indoor place with no posted hours: ordinary daytime only
  // Outdoors only in daylight; a viewpoint may stay until 20 min after sunset for the view.
  const daylight: [number, number] = u.kind === "viewpoint" ? [sunrise, sunset + 20] : [sunrise, sunset];
  const clipped = OUTDOOR[u.kind]
    ? windows.map(([a, b]) => [Math.max(a, daylight[0]), Math.min(b, daylight[1])] as [number, number])
    : windows;
  return clipped.filter(([a, b]) => b > a).map(([a, b]) => [dayStartMs + a * MIN, dayStartMs + b * MIN]);
}

function fits(windows: Array<[number, number]>, arrive: number, leave: number): boolean {
  return windows.some(([a, b]) => arrive >= a && leave <= b);
}

function closesAt(windows: Array<[number, number]>, at: number): number | null {
  const w = windows.find(([a, b]) => at >= a && at <= b);
  return w ? w[1] : null;
}

export function planOuting(input: EngineInput): EnginePlan {
  const random = rng(input.seed * 2654435761 + Math.round(input.lat * 1000) + Math.round(input.lng * 1000));
  const cond = input.conditions;
  const off = cond?.utcOffsetSeconds ?? 0;
  const duration = Math.min(600, Math.max(30, input.durationMinutes));
  const startMs = input.nowMs;
  const dayStartMs = startMs - localMinutes(startMs, off) * MIN - (new Date(startMs).getUTCSeconds() * 1000) - (startMs % 1000);
  const weekday = localWeekday(startMs, off);
  const sun = {
    sunriseMin: cond ? localMinutes(cond.sunriseMs, off) : 7 * 60,
    sunsetMin: cond ? localMinutes(cond.sunsetMs, off) : 18 * 60,
  };
  const weather = weatherFor(cond, startMs, startMs + duration * MIN);
  const { interests, labels } = normalizeInterests(input.interests);
  const picked = new Set(input.interests.map((l) => l.trim().toLowerCase()));
  const previous = new Set(input.previousStopIds ?? []);
  const reachKm = Math.min(14, Math.max(2.5, duration / 60 * 3.5));

  // 1. Usable candidates.
  const seenNames = new Set<string>();
  const usable: Usable[] = [];
  for (const c of input.candidates) {
    if (typeof c.latitude !== "number" || typeof c.longitude !== "number") continue;
    const key = c.name.trim().toLowerCase();
    if (!key || seenNames.has(key)) continue;
    seenNames.add(key);
    const kind = kindOf(c);
    // A club or society tagged as a community or sports centre is a member organisation's
    // room, not a public place to visit (e.g. "Computer Science Club SJSU").
    if ((kind === "community" || kind === "sports") && MEMBER_ONLY.test(c.name)) continue;
    if (weather.windy && kind === "viewpoint") continue;   // exposed in strong wind
    const km = distanceKm(input.lat, input.lng, c.latitude, c.longitude);
    if (km > reachKm) continue;
    const open = openIntervals(c.hours, weekday, sun);
    if (c.hours && c.hours.trim() && open === null) continue;   // posted hours we can't read: can't promise it's open
    const directPick = picked.has(KIND_LABEL[kind].toLowerCase());
    const mapped = KIND_INTERESTS[kind].some((i) => interests.includes(i));
    const interest = interests.length === 0 ? 0.5 : directPick ? 1 : mapped ? 0.7 : 0.15;
    const quality = Math.min(1, 0.3 + (open !== null ? 0.35 : 0) + (c.hasPhoto ? 0.2 : 0) + (c.description ? 0.15 : 0));
    const near = 1 / (1 + km / 2);
    let conditionsFit = 0.5;
    if (weather.wet) conditionsFit = 0.2 + 0.8 * COVER[kind];
    if (weather.hot) conditionsFit = OUTDOOR[kind] ? (kind === "water" || kind === "garden" ? 0.55 : 0.3) : 0.9;
    const unpostedIndoor = !OUTDOOR[kind] && open === null;   // can't promise it's open
    const base = interest * 0.45 + quality * 0.15 + near * 0.25 + conditionsFit * 0.15 - (previous.has(c.id) ? 0.06 : 0)
      - (unpostedIndoor ? 0.15 : 0);
    usable.push({ c: c as Usable["c"], kind, km, open, hoursKnown: open !== null, interest, directPick, base });
  }

  const windows = new Map(usable.map((u) => [u.c.id, allowedWindow(u, cond, dayStartMs)]));
  // Anything that can't be visited at all in the outing's span is out.
  const endCap = startMs + duration * 1.1 * MIN;
  // Visitable = open (and in daylight, outdoors) for at least a short visit within the outing itself.
  const visitable = usable.filter((u) =>
    windows.get(u.c.id)!.some(([a, b]) => Math.min(b, endCap) - Math.max(a, startMs) >= Math.min(DWELL[u.kind][0], 15) * MIN));
  if (usable.length < 2) {
    throw new EngineError("not-enough-places", "Not enough nearby places to plan an outing yet.");
  }
  if (visitable.length < 2) {
    throw new EngineError("nothing-open",
      localMinutes(startMs, off) >= sun.sunsetMin
        ? "Most places nearby are closed or dark now. Try planning for the morning."
        : "Not enough nearby places are open for that long right now. Try a shorter outing.");
  }

  // Target stop count by time available.
  const targetStops = duration <= 50 ? 2 : duration <= 100 ? 3 : duration <= 170 ? 3 : 4;

  // Sunset finish: the outing ends within 30 min of sunset and a viewpoint is reachable.
  const sunsetMs = cond ? cond.sunsetMs : dayStartMs + sun.sunsetMin * MIN;
  const outingEnd = startMs + duration * MIN;
  const sunsetFinish = Math.abs(outingEnd - sunsetMs) <= 45 * MIN || (sunsetMs > startMs && sunsetMs < outingEnd);

  type Attempt = EnginePlan | { reject: string } | null;
  const attempt = (stopCount: number, excluded: Set<string>): Attempt => {
    // 2. Anchor: the best match for what the user picked.
    const pool = visitable.filter((u) => !excluded.has(u.c.id));
    const matching = pool.filter((u) => u.interest >= 0.7);
    const anchorPool = (matching.length ? matching : pool)
      .filter((u) => !(u.kind === "viewpoint" && stopCount > 2 && pool.some((p) => p.kind !== "viewpoint")));
    const anchor = pickNearBest(anchorPool.map((u) => ({
      // A short outing can't spend its time getting to the anchor.
      item: u, score: u.base + (u.kind === "trail" || u.kind === "reserve" ? 0.05 : 0) + (duration < 75 ? 0.8 / (1 + u.km) : 0),
    })), 0.06, random);
    if (!anchor) return null;
    const chosen: Usable[] = [anchor];
    const onlyOneKind = new Set(interests.flatMap((i) => Object.entries(KIND_INTERESTS)
      .filter(([, list]) => list.includes(i)).map(([k]) => k))).size === 1;

    // 3. Complements, by role.
    const roles: Array<"contrast" | "rest" | "finish"> = ["contrast", "rest", "finish"];
    while (chosen.length < stopCount) {
      const role = roles[(chosen.length - 1) % roles.length];
      const last = chosen[chosen.length - 1];
      const hasUnposted = chosen.some((x) => !OUTDOOR[x.kind] && !x.hoursKnown);
      const open = pool.filter((u) => !chosen.includes(u) && !(hasUnposted && !OUTDOOR[u.kind] && !u.hoursKnown));
      // Variety is a rule, not a preference: no repeated kind while another kind is available,
      // unless the user picked only that kind.
      // Off-topic places only for shelter in rain or heat, or when nothing on-topic is left.
      const needShelter = (weather.wet || weather.hot) && !chosen.some(shelters);
      // An outing that runs past sunset needs somewhere open indoors for the dark part.
      const runsIntoDark = startMs + duration * MIN > sunsetMs + 20 * MIN;
      const relevant = interests.length
        ? open.filter((u) => u.interest >= 0.7 || (needShelter && shelters(u)) || (runsIntoDark && !OUTDOOR[u.kind])) : open;
      const candidates = relevant.length ? relevant : open;
      const fresh = candidates.filter((u) => !chosen.some((x) => x.kind === u.kind));
      // Rain or heat over the threshold: the next stop is a shelter whenever one is open in reach.
      const shelterOptions = needShelter ? candidates.filter(shelters) : [];
      const options = (shelterOptions.length ? shelterOptions : onlyOneKind || !fresh.length ? candidates : fresh).map((u) => {
        const fromCluster = Math.min(...chosen.map((x) => distanceKm(x.c.latitude, x.c.longitude, u.c.latitude, u.c.longitude)));
        const sameKind = chosen.some((x) => x.kind === u.kind);
        // Short outings can't afford long hops: closeness to the stops already chosen counts more.
        const closeness = duration < 75 ? 0.6 : 0.25;
        let score = u.base + closeness / (1 + fromCluster / 1.2) - (sameKind ? (onlyOneKind ? 0.25 : 0.6) : 0);
        // Rain or heat makes shelter the point of a stop; otherwise off-topic only when nothing better is left.
        const shelterNeeded = (weather.wet || weather.hot) && shelters(u) && !chosen.some(shelters);
        if (interests.length && u.interest < 0.7 && !shelterNeeded) score -= 0.35;
        if (role === "contrast" && u.kind !== last.kind) score += 0.08;
        if (role === "rest" && (u.kind === "water" || u.kind === "garden" || u.kind === "park")) score += 0.12;
        if (role === "finish" && u.kind === "viewpoint") score += sunsetFinish ? 0.35 : 0.1;
        // In rain or heat the plan needs shelter: one covered stop when any is open nearby.
        if (shelterNeeded) score += 0.5;
        return { item: u, score };
      });
      const next = pickNearBest(options, 0.04, random);
      if (!next) break;
      chosen.push(next);
    }
    if (chosen.length < 2) return null;

    // Sunset: if a viewpoint is in the plan and the outing ends near sunset, it goes last.
    const finishLast = sunsetFinish ? chosen.find((u) => u.kind === "viewpoint") : undefined;

    // 4. Route: nearest neighbour from the start, then 2-opt over the loop back home.
    const legKm = (a: { lat: number; lng: number }, b: { lat: number; lng: number }) => distanceKm(a.lat, a.lng, b.lat, b.lng);
    const pt = (u: Usable) => ({ lat: u.c.latitude, lng: u.c.longitude });
    const home = { lat: input.lat, lng: input.lng };
    const free = chosen.filter((u) => u !== finishLast);
    const order: Usable[] = [];
    let at = home;
    while (free.length) {
      free.sort((a, b) => legKm(at, pt(a)) - legKm(at, pt(b)));
      const n = free.shift()!;
      order.push(n);
      at = pt(n);
    }
    const loopKm = (seq: Usable[]) => {
      const all = finishLast ? [...seq, finishLast] : seq;
      let total = 0, p = home;
      for (const u of all) { total += legKm(p, pt(u)); p = pt(u); }
      return total + legKm(p, home);
    };
    let improved = true;
    while (improved) {
      improved = false;
      for (let i = 0; i < order.length - 1; i++) {
        for (let j = i + 1; j < order.length; j++) {
          const candidate = [...order.slice(0, i), ...order.slice(i, j + 1).reverse(), ...order.slice(j + 1)];
          if (loopKm(candidate) + 1e-9 < loopKm(order)) { order.splice(0, order.length, ...candidate); improved = true; }
        }
      }
    }
    let route = finishLast ? [...order, finishLast] : order;

    // Feasibility pass: if the shortest order puts a stop outside its open or daylight
    // window (at its shortest visit), take the shortest order that fits. ≤4 stops, so all
    // orders are checked; a viewpoint timed for sunset stays last.
    const scheduleFits = (seq: Usable[]) => {
      let clock = startMs, p = home;
      for (const u of seq) {
        const arrive = clock + travel(legKm(p, pt(u))).minutes * MIN;
        const leave = arrive + DWELL[u.kind][0] * MIN * (duration < 60 ? 0.6 : duration < 75 ? 0.7 : 1);
        if (!fits(windows.get(u.c.id)!, arrive, leave)) return false;
        clock = leave; p = pt(u);
      }
      return true;
    };
    if (!scheduleFits(route)) {
      const permute = (xs: Usable[]): Usable[][] => xs.length <= 1 ? [xs]
        : xs.flatMap((x, i) => permute([...xs.slice(0, i), ...xs.slice(i + 1)]).map((rest) => [x, ...rest]));
      const feasible = permute(finishLast ? order : route)
        .map((seq) => (finishLast ? [...seq, finishLast] : seq))
        .filter(scheduleFits)
        .sort((a, b) => loopKm(finishLast ? a.slice(0, -1) : a) - loopKm(finishLast ? b.slice(0, -1) : b));
      if (feasible.length) route = feasible[0];
    }

    // 5. Times: fit the dwell times to the requested duration, inside open windows.
    const legs = route.map((u, i) => travel(legKm(i === 0 ? home : pt(route[i - 1]), pt(u))));
    const travelTotal = legs.reduce((s, l) => s + l.minutes, 0);
    const range = route.map((u) => {
      const [lo, hi] = DWELL[u.kind];
      // A short outing scales the shortest sensible visit down (never under 10 min).
      const shortScale = duration < 60 ? 0.6 : duration < 75 ? 0.7 : 1;
      let min = Math.max(10, Math.round(lo * shortScale)), max = hi;
      // A long outing earns longer time in a park, garden or by the water.
      if (duration >= 180 && (u.kind === "park" || u.kind === "water")) max = 75;
      if (duration >= 180 && u.kind === "garden") max = 55;
      if (weather.wet && OUTDOOR[u.kind]) max = lo;       // keep exposed stops short in rain
      if (weather.hot && OUTDOOR[u.kind]) max = min;       // heat: outdoor stops at their shortest
      if (weather.hot && !OUTDOOR[u.kind]) max = u.kind === "sports" ? 75 : 60;   // indoors can stretch
      if (u.kind === "trail" || u.kind === "reserve") {   // longer outings earn a longer walk
        min = duration <= 75 ? 30 : duration <= 150 ? 45 : 60;
        max = Math.max(min, duration <= 75 ? 45 : duration <= 150 ? 75 : 90);
        if (weather.wet || weather.hot) max = min;
      }
      return [min, max] as [number, number];
    });
    const minTotal = travelTotal + range.reduce((s, r) => s + r[0], 0);
    const maxTotal = travelTotal + range.reduce((s, r) => s + r[1], 0);
    if (minTotal > duration * 1.1) {
      // Too much for the time: swap out the costliest complement (travel + shortest visit).
      // The anchor stays, and so does the one covered stop when rain or heat needs shelter.
      const shelter = (weather.wet || weather.hot) ? route.find(shelters) : undefined;
      const costs = route.map((u, i) => (u === anchor || u === shelter ? -1 : legs[i].minutes + range[i][0]));
      const worst = costs.indexOf(Math.max(...costs));
      return worst >= 0 && costs[worst] >= 0 ? { reject: route[worst].c.id } : null;
    }
    // With a viewpoint finish, aim to end at sunset so the view comes just before it.
    const wanted = finishLast
      ? Math.min(duration * 1.1, Math.max(duration * 0.9, (sunsetMs - startMs) / MIN))
      : duration;
    const target = Math.min(Math.max(wanted, minTotal), maxTotal);
    const spare = maxTotal === minTotal ? 0 : (target - minTotal) / (maxTotal - minTotal);
    const dwell = range.map(([lo, hi]) => Math.round(lo + (hi - lo) * spare));
    let total = travelTotal + dwell.reduce((s, d) => s + d, 0);
    // Rounding drift goes to the anchor so the total lands on target.
    const anchorIndex = route.indexOf(anchor);
    const drift = Math.round(target - total);
    if (drift && anchorIndex >= 0) {
      const [lo, hi] = range[anchorIndex];
      dwell[anchorIndex] = Math.min(hi, Math.max(lo, dwell[anchorIndex] + drift));
      total = travelTotal + dwell.reduce((s, d) => s + d, 0);
    }
    if (total < duration * 0.9) return null;               // too little: caller adds a stop

    // A viewpoint finish lands within 30 min before sunset when the outing reaches it.
    let clock = startMs;
    const stops: EngineStop[] = [];
    for (let i = 0; i < route.length; i++) {
      const u = route[i];
      const arrive = clock + legs[i].minutes * MIN;
      const leave = arrive + dwell[i] * MIN;
      if (!fits(windows.get(u.c.id)!, arrive, leave)) return { reject: u.c.id };
      stops.push({
        placeId: u.c.id, name: u.c.name, category: u.c.category ?? null,
        latitude: u.c.latitude, longitude: u.c.longitude, order: i + 1,
        minutes: legs[i].minutes + dwell[i], why: "", arriveMs: arrive, leaveMs: leave,
        travelMinutes: legs[i].minutes, mode: legs[i].mode, kind: u.kind,
      });
      clock = leave;
    }

    // 6. Words.
    const prevName = (i: number) => (i === 0 ? null : route[i - 1].c.name);
    stops.forEach((s, i) => { s.why = whyLine(s, route[i], i, prevName(i), windows.get(s.placeId)!, off, sunsetMs, weather, labels, random); });
    const tips = tipsFor({ weather, stops, route, usable, visitable, pickedLabels: input.interests.filter((l) => l.trim()),
      sunsetMs, off, cond });
    const last = stops[stops.length - 1];
    const backKm = legKm(pt(route[route.length - 1]), home);
    return {
      title: titleFor(route, anchor, random),
      intro: introFor(stops, route, backKm, weather, cond, off, sunsetMs, random) + (tips.length ? " " + tips.join(" ") : ""),
      tips,
      stops,
      totalMinutes: Math.round((last.leaveMs - startMs) / MIN),
    };
  };

  // Try the target stop count, then fewer (too long) or more (too short). A stop that
  // can't be visited at its scheduled time is excluded and the plan is chosen again.
  const counts = [targetStops, targetStops - 1, targetStops + 1, targetStops - 2].filter((n) => n >= 2 && n <= 4);
  for (const n of counts) {
    const excluded = new Set<string>();
    for (let tries = 0; tries < 8; tries++) {
      const result = attempt(n, excluded);
      if (result && "stops" in result) return result;
      if (result && "reject" in result) { excluded.add(result.reject); continue; }
      break;
    }
  }
  // Last resort: the two nearest visitable places, at their shortest sensible times.
  const two = [...visitable].sort((a, b) => a.km - b.km).slice(0, 2);
  const fallbackInput = { ...input, candidates: two.map((u) => u.c), durationMinutes: duration, seed: input.seed + 1 };
  if (input.candidates.length > 2) return planOuting(fallbackInput);
  throw new EngineError("nothing-open", "Not enough nearby places are open for that long right now. Try a shorter outing.");
}

// ── Wording ─────────────────────────────────────────────────────────────────

function minutesText(n: number): string {
  return n >= 60 ? `${Math.floor(n / 60)} h${n % 60 ? ` ${n % 60} min` : ""}` : `${n} min`;
}

function whyLine(s: EngineStop, u: Usable, i: number, prev: string | null, windows: Array<[number, number]>,
  off: number, sunsetMs: number, w: Weather, labels: Record<string, string[]>, random: () => number): string {
  const facts: string[] = [];
  // What the user picked.
  if (u.directPick) facts.push(pick(random, [`Matches ${KIND_LABEL[u.kind]}`, `For your ${KIND_LABEL[u.kind]} pick`, `Right in line with your ${KIND_LABEL[u.kind]} pick`]));
  else {
    const via = KIND_INTERESTS[u.kind].map((i) => labels[i]?.[0]).find(Boolean);
    if (via && u.interest >= 0.7) facts.push(pick(random, [`A ${KIND_NOUN[u.kind]}, in keeping with your ${via} pick`,
      `A ${KIND_NOUN[u.kind]} to suit your ${via} pick`, `This ${KIND_NOUN[u.kind]} fits your ${via} pick`, `${articleNoun(u.kind)} for the ${via} lover`]));
  }
  // Getting there.
  const leg = `${s.travelMinutes}-min ${s.mode === "walk" ? "walk" : "drive"}`;
  facts.push(i === 0
    ? pick(random, [`${leg} from where you start`, `${leg} to begin`])
    : pick(random, [`${leg} from ${prev}`, `${leg} on from your last stop`]));
  // Hours, only when posted.
  const close = closesAt(windows, s.arriveMs);
  if (u.hoursKnown && close !== null && close - s.leaveMs < 6 * 60 * MIN) facts.push(`open until ${hourText(localMinutes(close, off))}`);
  else if (u.hoursKnown && u.open?.length === 1 && u.open[0][0] === 0 && u.open[0][1] === 1440) facts.push("open 24 hours");
  // Time and light.
  const toSunset = Math.round((sunsetMs - s.arriveMs) / MIN);
  if (u.kind === "viewpoint" && toSunset >= 0 && toSunset <= 30) {
    facts.push(`arrive ${toSunset} min before sunset (${clockText(sunsetMs, off)}) to catch the last light`);
  } else {
    facts.push(pick(random, [`arrive about ${clockText(s.arriveMs, off)}`, `there by ${clockText(s.arriveMs, off)}`, `${clockText(s.arriveMs, off)} arrival`]));
  }
  if (OUTDOOR[u.kind] && !(u.kind === "viewpoint") && sunsetMs > s.leaveMs && sunsetMs - s.leaveMs < 45 * MIN) {
    facts.push(`done before sunset at ${clockText(sunsetMs, off)}`);
  }
  if (w.wet && COVER[u.kind] === 1) facts.push("indoors if the rain arrives");
  if (w.wet && COVER[u.kind] > 0 && COVER[u.kind] < 1) facts.push("a sports centre to duck into if it rains");
  if (w.hot && COVER[u.kind] > 0) facts.push(`a ${KIND_NOUN[u.kind]} for the hottest part of the day`);
  // Phrase: sometimes a "·" list, sometimes a sentence.
  const dwell = Math.round((s.leaveMs - s.arriveMs) / MIN);
  if (random() < 0.5) return `${capitalize(facts.join(" · "))}. About ${minutesText(dwell)} here.`;
  const [first, ...rest] = facts;
  return `${capitalize(first)}; ${rest.join(", ")}. Plan on ${minutesText(dwell)}.`;
}

interface TipContext {
  weather: Weather; stops: EngineStop[]; route: Usable[]; usable: Usable[]; visitable: Usable[];
  pickedLabels: string[]; sunsetMs: number; off: number; cond: Conditions | null;
}

function tipsFor(t: TipContext): string[] {
  const { weather: w, stops, route } = t;
  const tips: string[] = [];
  if (w.wet) {
    const covered = route.find((u) => COVER[u.kind] === 1) ?? route.find(shelters);
    const coveredNearby = t.usable.some(shelters);
    tips.push(covered
      ? `Rain is likely (${Math.round(w.rainProb)}% chance): ${covered.c.name} is ${COVER[covered.kind] === 1 ? "indoors" : "a sports centre"} and the outdoor stops are kept short. Bring a jacket.`
      : coveredNearby
        ? `Rain is likely (${Math.round(w.rainProb)}% chance) and the covered places nearby are closed or too far for this outing, so the outdoor stops are kept short. Bring a jacket.`
        : `Rain is likely (${Math.round(w.rainProb)}% chance) and nothing covered is nearby, so the outdoor stops are kept short. Bring a jacket.`);
  }
  if (w.hot) tips.push(`It's hot (up to ${Math.round(w.maxTempF)}°F): outdoor stops are kept short. Bring water and rest in the shade between stops.`);
  if (w.windy) tips.push(`Strong wind (${Math.round(w.windKmh)} km/h), so exposed viewpoints are left out today.`);
  // A pick with nothing to match among the places loaded nearby, said plainly.
  const missing = t.pickedLabels.filter((label) =>
    !t.usable.some((u) => KIND_LABEL[u.kind].toLowerCase() === label.toLowerCase()));
  if (missing.length) {
    const used = Array.from(new Set(route.map((u) => `${KIND_NOUN[u.kind]}s`)));
    tips.push(`No ${listText(missing.map((m) => LABEL_PLURAL[m.toLowerCase()] ?? m.toLowerCase()), "or")} are among the places loaded nearby, so this plan uses ${listText(used, "and")}.`);
  }
  for (const label of t.pickedLabels) {
    const matching = t.usable.filter((u) => KIND_LABEL[u.kind].toLowerCase() === label.toLowerCase());
    if (matching.length === 1 && route.includes(matching[0]) && route.length > 1 && t.pickedLabels.length === 1) {
      tips.push(`${matching[0].c.name} is the only ${KIND_NOUN[matching[0].kind]} nearby, so the rest of the plan is ${listText(
        Array.from(new Set(route.filter((u) => u !== matching[0]).map((u) => `${KIND_NOUN[u.kind]}s`))), "and")}.`);
    }
  }
  const unposted = route.find((u) => !OUTDOOR[u.kind] && !u.hoursKnown);
  if (unposted) tips.push(`Hours aren't posted for ${unposted.c.name}; check before you go.`);
  const last = stops[stops.length - 1];
  const toSunset = Math.round((t.sunsetMs - last.arriveMs) / MIN);
  if (t.cond && last.kind === "viewpoint" && toSunset >= 0 && toSunset <= 30) {
    tips.push(`Linger at ${last.name} if you can: sunset is ${clockText(t.sunsetMs, t.off)}.`);
  }
  if (t.visitable.length <= 3) tips.push(`Only ${t.visitable.length} places nearby fit right now, so the plan uses what's there.`);
  const driveLegs = stops.filter((s) => s.mode === "drive").length;
  if (driveLegs === 0) tips.push("Every leg is walkable, so you can leave the car.");
  else if (driveLegs === stops.length) tips.push("The stops are spread out, so each leg is a short drive.");
  else tips.push(`${driveLegs === 1 ? "One leg is" : `${driveLegs} legs are`} a short drive; the rest you can walk.`);
  return tips.slice(0, 3);
}

function listText(items: string[], conj: "and" | "or"): string {
  if (items.length <= 1) return items[0] ?? "";
  return `${items.slice(0, -1).join(", ")} ${conj} ${items[items.length - 1]}`;
}

const LABEL_PLURAL: Record<string, string> = {
  parks: "parks", trails: "trails", gardens: "gardens", playgrounds: "playgrounds", waterfront: "waterfront spots",
  sports: "sports centres", scenic: "viewpoints", community: "community centres",
};

function articleNoun(kind: Kind): string {
  const noun = KIND_NOUN[kind];
  return `${/^[aeiou]/.test(noun) ? "An" : "A"} ${noun}`;
}

function titleFor(route: Usable[], anchor: Usable, random: () => number): string {
  const kinds = Array.from(new Set(route.map((u) => KIND_NOUN[u.kind])));
  const first = route[0], last = route[route.length - 1];
  const options = [
    `${shortName(anchor.c.name)} and around`,
    `${shortName(first.c.name)} to ${shortName(last.c.name)}`,
    kinds.length >= 2 ? `A ${kinds[0]} and ${kinds[1]} loop` : `A ${kinds[0]} outing`,
  ];
  return pick(random, options).slice(0, 60);
}

function introFor(stops: EngineStop[], route: Usable[], backKm: number, w: Weather, cond: Conditions | null,
  off: number, sunsetMs: number, random: () => number): string {
  const first = stops[0], last = stops[stops.length - 1];
  const back = backKm < 0.95 ? `about ${Math.max(100, Math.round(backKm * 10) * 100)} m from where you started`
    : `${backKm < 1.05 ? "about 1" : backKm.toFixed(1)} km from where you started`;
  const span = pick(random, [
    `Start at ${first.name} around ${clockText(first.arriveMs, off)} and wrap up at ${last.name} by ${clockText(last.leaveMs, off)}, ${back}.`,
    `${stops.length} stops from ${clockText(first.arriveMs, off)} to ${clockText(last.leaveMs, off)}, ending at ${last.name}, ${back}.`,
    `From ${first.name} to ${last.name}, ${clockText(first.arriveMs, off)}–${clockText(last.leaveMs, off)}, finishing ${back}.`,
  ]);
  const conditions = cond
    ? `It's ${Math.round(cond.current.tempF)}°F and ${describeCode(cond.current.code)} now${w.rainProb > 0 ? `, rain chance up to ${Math.round(w.rainProb)}%` : ""}; sunset is ${clockText(sunsetMs, off)}.`
    : "Weather is unavailable right now, so check the sky before you head out.";
  return `${span} ${conditions}`;
}

export function describeCode(code: number): string {
  if (code === 0) return "clear";
  if (code <= 3) return "partly cloudy";
  if (code <= 48) return "foggy";
  if (code <= 57) return "drizzling";
  if (code <= 67) return "rainy";
  if (code <= 77) return "snowy";
  if (code <= 82) return "showery";
  if (code <= 86) return "snowy";
  return "stormy";
}

function shortName(name: string): string {
  return name.length <= 28 ? name : name.slice(0, 27).replace(/\s+\S*$/, "") + "…";
}

function capitalize(s: string): string {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

function pick<T>(random: () => number, options: T[]): T {
  return options[Math.floor(random() * options.length)];
}
