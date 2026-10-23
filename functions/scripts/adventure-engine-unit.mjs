/**
 * Deterministic Adventure Planner + event-plan sequencer — unit tests, no network.
 * Synthetic edge cases plus the real San José snapshot the app ships.
 */
import { readFileSync } from "node:fs";
import {
  planOuting, openIntervals, kindOf, distanceKm, travel, DWELL, EngineError,
} from "../lib/adventure-engine.js";
import { sequenceEventsFallback, ASSUMED_EVENT_MINUTES, isAllDayListing } from "../lib/eventPlanner.js";

let pass = 0, fail = 0;
const ok = (name, cond, extra = "") => {
  if (cond) { pass++; console.log(`  ✅ ${name}`); } else { fail++; console.log(`  ❌ ${name} ${extra}`); }
};
const throwsEngine = (fn, code) => { try { fn(); return false; } catch (e) { return e instanceof EngineError && e.code === code; } };

const OFF = -7 * 3600;
const DAY = Date.parse("2026-10-23T00:00:00-07:00");   // a Friday
const at = (h, m = 0) => DAY + (h * 60 + m) * 60_000;
const SUNRISE = at(7, 23), SUNSET = at(18, 19);
const START = { lat: 37.3352, lng: -121.8811 };
const cond = ({ tempF = 70, code = 0, rain = 0, wind = 10 } = {}) => ({
  utcOffsetSeconds: OFF, sunriseMs: SUNRISE, sunsetMs: SUNSET,
  current: { tempF, code, windKmh: wind, precipMm: code >= 51 ? 1 : 0 },
  hourly: Array.from({ length: 36 }, (_, h) => ({ ms: at(h), tempF, precipProb: rain, windKmh: wind, code })),
});
const place = (id, name, category, dLat, dLng, extra = {}) =>
  ({ id, name, category, latitude: START.lat + dLat, longitude: START.lng + dLng, ...extra });
const base = (over = {}) => ({ ...START, nowMs: at(14), durationMinutes: 120, interests: ["Parks", "Trails"],
  conditions: cond(), seed: 1, candidates: [], ...over });

// A compact neighbourhood: every kind within ~1.5 km.
const town = [
  place("p1", "Elm Park", "Parks", 0.004, 0.002),
  place("p2", "Oak Park", "Parks", -0.006, 0.004),
  place("t1", "Creek Trail", "Trails", 0.009, -0.006),
  place("g1", "Rose Garden", "Gardens", 0.002, -0.003),
  place("w1", "Lake Edge", "Waterfront", -0.010, -0.004),
  place("v1", "Hill Lookout", "Scenic", 0.012, 0.008),
  place("c1", "Civic Community Center", "Community", -0.003, -0.006, { hours: "Mo-Su 08:00-21:00" }),
  place("s1", "Downtown Rec Center", "Sports", 0.005, 0.009, { hours: "Mo-Fr 06:00-22:00" }),
  place("y1", "Maple Playground", "Playgrounds", -0.004, 0.007),
];

const snapshot = JSON.parse(readFileSync(new URL("../../Verdure/Verdure/Resources/osm-snapshot-san-jose.json", import.meta.url), "utf8"));
const cat = (t) => t.leisure === "garden" ? "Gardens" : t.leisure === "playground" ? "Playgrounds"
  : (t.leisure === "sports_centre" || t.leisure === "pitch") ? "Sports" : t.leisure === "nature_reserve" ? "Scenic"
  : (t.highway === "path" || t.highway === "footway") ? "Trails" : (t.natural === "water" || t.natural === "beach") ? "Waterfront"
  : t.tourism === "viewpoint" ? "Scenic" : t.amenity === "community_centre" ? "Community" : "Parks";
const seen = new Set();
const real = snapshot.elements
  .filter((e) => e.tags?.name)
  .map((e) => ({ id: `osm-${e.id}`, name: e.tags.name, category: cat(e.tags), latitude: e.lat ?? e.center.lat,
    longitude: e.lon ?? e.center.lon, hours: e.tags.opening_hours }))
  .sort((a, b) => distanceKm(START.lat, START.lng, a.latitude, a.longitude) - distanceKm(START.lat, START.lng, b.latitude, b.longitude))
  .filter((c) => { const k = c.name.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; })
  .slice(0, 30);

const minutesBetween = (a, b) => Math.round((b - a) / 60_000);
const usesOnly = (plan, list) => plan.stops.every((s) => { const c = list.find((x) => x.id === s.placeId);
  return c && c.name === s.name && c.latitude === s.latitude && c.longitude === s.longitude; });

console.log("\n── opening_hours ──");
{
  const sun = { sunriseMin: 443, sunsetMin: 1099 };
  ok("24/7", JSON.stringify(openIntervals("24/7", 5, sun)) === "[[0,1440]]");
  ok("weekday ranges and later rules override", JSON.stringify(openIntervals("Mo-Fr 08:00-17:00; Sa-Su 10:00-16:00", 5, sun)) === "[[480,1020]]"
    && JSON.stringify(openIntervals("Mo-Fr 08:00-17:00; Sa-Su 10:00-16:00", 6, sun)) === "[[600,960]]");
  ok("sunrise-sunset", JSON.stringify(openIntervals("sunrise-sunset", 2, sun)) === "[[443,1099]]");
  ok("split hours", JSON.stringify(openIntervals("Mo-Su 08:00-12:00,13:00-17:00", 1, sun)) === "[[480,720],[780,1020]]");
  ok("a day that is off is closed", JSON.stringify(openIntervals("Mo-Sa 09:00-17:00; Su off", 0, sun)) === "[]");
  ok("a day no rule names is closed", JSON.stringify(openIntervals("We-Th 17:00-20:00", 5, sun)) === "[]");
  ok("past midnight is open to the end of today", JSON.stringify(openIntervals("Fr 18:00-02:00", 5, sun)) === "[[1080,1440]]");
  ok("holiday rules don't change today", JSON.stringify(openIntervals("Mo-Fr 09:00-17:00; PH off", 5, sun)) === "[[540,1020]]");
  ok("unreadable hours are unknown, not open", openIntervals('We-Th 17:00-20:00; Fr "TBA"', 5, sun) === null
    && openIntervals("Apr-Oct: Mo-Su 08:00-20:00", 5, sun) === null && openIntervals(undefined, 5, sun) === null);
}

console.log("\n── never closed, never dark ──");
{
  const closedNow = place("x1", "Early Bird Garden", "Gardens", 0.001, 0.001, { hours: "Mo-Su 06:00-08:00" });
  const closesSoon = place("x2", "Short Hours Park", "Parks", 0.0015, 0.001, { hours: "Mo-Su 06:00-14:40" });
  for (let seed = 1; seed <= 5; seed++) {
    const plan = planOuting(base({ candidates: [...town, closedNow, closesSoon], seed }));
    ok(`seed ${seed}: a closed place is never scheduled`, !plan.stops.some((s) => s.placeId === "x1"));
    const short = plan.stops.find((s) => s.placeId === "x2");
    ok(`seed ${seed}: a stop ends before closing time`, !short || short.leaveMs <= at(14, 40));
  }
  const unreadable = place("x3", "Mystery Club House", "Community", 0.001, 0.0005, { hours: 'Fr "TBA"' });
  const late = planOuting(base({ candidates: [...town, unreadable], interests: ["Community"] }));
  ok("posted hours that can't be read are never promised", !late.stops.some((s) => s.placeId === "x3"));
  // Late afternoon: trails must end before sunset.
  for (const d of [90, 120, 180]) {
    const plan = planOuting(base({ candidates: town, nowMs: at(16, 30), durationMinutes: d, interests: ["Trails"] }));
    ok(`${d} min from 4:30 pm: no outdoor stop (trail, park, garden, water) after sunset`,
      plan.stops.every((s) => !["trail", "reserve", "park", "garden", "playground", "water"].includes(s.kind) || s.leaveMs <= SUNSET),
      plan.stops.map((s) => `${s.name}@${minutesBetween(DAY, s.leaveMs)}`).join(","));
  }
  ok("after dark with only outdoor places: an honest 'closed or dark' answer",
    throwsEngine(() => planOuting(base({ candidates: town.filter((c) => !["Community", "Sports"].includes(c.category)), nowMs: at(20) })), "nothing-open"));
}

console.log("\n── duration fits within ±10% ──");
for (const list of [["synthetic", town], ["real San José", real]]) {
  for (const d of [45, 60, 90, 120, 150, 180, 240]) {
    const plan = planOuting(base({ candidates: list[1], durationMinutes: d, nowMs: at(10) }));
    const sum = plan.stops.reduce((s, x) => s + x.minutes, 0);
    ok(`${list[0]} ${d} min → ${sum} min (stops add up to the shown total)`, sum >= d * 0.9 && sum <= d * 1.1 && sum === plan.totalMinutes);
  }
}

console.log("\n── weather and light ──");
{
  const wet = planOuting(base({ candidates: town, conditions: cond({ code: 63, rain: 85, tempF: 55 }), durationMinutes: 90 }));
  ok("rain: a covered stop is chosen", wet.stops.some((s) => s.kind === "community" || s.kind === "sports"));
  ok("rain: the plan says so", /Rain is likely \(85% chance\)/.test(wet.intro));
  ok("rain: exposed stops at their shortest", wet.stops.every((s) => !["park", "garden", "water", "viewpoint", "playground"].includes(s.kind)
    || Math.round((s.leaveMs - s.arriveMs) / 60_000) <= DWELL[s.kind][0]));

  const hot = planOuting(base({ candidates: town, conditions: cond({ tempF: 97 }), durationMinutes: 120, nowMs: at(12) }));
  ok("heat: bring water", /Bring water/.test(hot.intro));
  ok("heat: outdoor stops at their shortest", hot.stops.every((s) => ["community", "sports"].includes(s.kind)
    || Math.round((s.leaveMs - s.arriveMs) / 60_000) <= DWELL[s.kind][0] || s.kind === "trail"));
  ok("heat: an indoor stop takes the midday", hot.stops.some((s) => s.kind === "sports" || s.kind === "community"));

  const windy = planOuting(base({ candidates: town, conditions: cond({ wind: 55 }), interests: ["Scenic", "Parks"] }));
  ok("strong wind: no exposed viewpoint", !windy.stops.some((s) => s.kind === "viewpoint") && /Strong wind/.test(windy.intro));

  const evening = planOuting(base({ candidates: town, nowMs: at(16, 50), durationMinutes: 90, interests: ["Scenic", "Parks"] }));
  const last = evening.stops[evening.stops.length - 1];
  const before = minutesBetween(last.arriveMs, SUNSET);
  ok("sunset: finishes at the viewpoint, arriving within 30 min of sunset", last.kind === "viewpoint" && before >= 0 && before <= 30, `${last.kind} ${before}`);
  ok("sunset: the why names the sunset time", /sunset \(6:19 pm\)/.test(last.why), last.why);
}

console.log("\n── route ──");
{
  const permutations = (xs) => xs.length <= 1 ? [xs] : xs.flatMap((x, i) => permutations([...xs.slice(0, i), ...xs.slice(i + 1)]).map((p) => [x, ...p]));
  const loop = (seq) => { let p = START, t = 0; for (const s of seq) { t += distanceKm(p.lat, p.lng, s.latitude, s.longitude); p = { lat: s.latitude, lng: s.longitude }; }
    return t + distanceKm(p.lat, p.lng, START.lat, START.lng); };
  for (const [label, list, now, d] of [["synthetic 3 h", town, at(10), 180], ["real 4 h", real, at(9, 30), 240], ["real 2 h", real, at(14, 30), 120]]) {
    const plan = planOuting(base({ candidates: list, nowMs: now, durationMinutes: d, interests: ["Parks", "Gardens"] }));
    const best = Math.min(...permutations(plan.stops).map(loop));
    ok(`${label}: the loop is the shortest order of its stops (no backtracking)`, loop(plan.stops) <= best + 1e-6,
      `${loop(plan.stops).toFixed(3)} vs ${best.toFixed(3)}`);
    ok(`${label}: legs under 1.2 km are walks, longer ones drives`, plan.stops.every((s, i) => {
      const p = i === 0 ? START : { lat: plan.stops[i - 1].latitude, lng: plan.stops[i - 1].longitude };
      const t = travel(distanceKm(p.lat, p.lng, s.latitude, s.longitude));
      return t.mode === s.mode && t.minutes === s.travelMinutes;
    }));
  }
}

console.log("\n── only candidates; friendly errors ──");
{
  for (const list of [town, real]) {
    const plan = planOuting(base({ candidates: list }));
    ok("every stop is a candidate, with our name and coordinates", usesOnly(plan, list));
  }
  ok("fewer than 2 places: the existing friendly error", throwsEngine(() => planOuting(base({ candidates: [town[0]] })), "not-enough-places"));
  ok("no places with coordinates: the existing friendly error",
    throwsEngine(() => planOuting(base({ candidates: [{ id: "a", name: "A" }, { id: "b", name: "B" }] })), "not-enough-places"));
}

console.log("\n── regenerate ──");
{
  const plans = [1, 2, 3].map((seed, i, all) => planOuting(base({ candidates: real, seed, nowMs: at(14, 30) })));
  const keys = plans.map((p) => p.stops.map((s) => s.placeId).join(","));
  ok("three seeds give three different plans", new Set(keys).size === 3, keys.join(" | "));
  const onTopic = (p) => p.stops.filter((s) => ["park", "garden", "water", "viewpoint", "trail", "reserve"].includes(s.kind)).length;
  ok("never a worse copy: as many on-topic stops as the first plan", plans.every((p) => onTopic(p) >= onTopic(plans[0])));
  const avoid = planOuting(base({ candidates: real, seed: 2, nowMs: at(14, 30), previousStopIds: plans[0].stops.map((s) => s.placeId) }));
  ok("the previous plan's stops are avoided when equally good options exist",
    avoid.stops.filter((s) => plans[0].stops.some((x) => x.placeId === s.placeId)).length < plans[0].stops.length);
}

console.log("\n── data quality and sparse areas ──");
{
  const clubs = [place("k1", "Chess Club House", "Community", 0.0005, 0.0005), place("k2", "Engineering Society Room", "Community", 0.0006, 0.0004)];
  const plan = planOuting(base({ candidates: [...town, ...clubs], interests: ["Community"] }));
  ok("member-only clubs and societies are not outing stops", !plan.stops.some((s) => s.placeId.startsWith("k")));
  const unposted = [place("u1", "Hall One", "Community", 0.001, 0.001), place("u2", "Hall Two", "Community", -0.001, 0.001),
    place("u3", "Hall Three", "Community", 0.001, -0.001)];
  const halls = planOuting(base({ candidates: [...unposted, town[0], town[3]], interests: ["Community"] }));
  ok("at most one indoor stop without posted hours", halls.stops.filter((s) => s.placeId.startsWith("u")).length <= 1);
  ok("…and the plan says to check its hours", /Hours aren't posted for Hall/.test(halls.intro));
  const sparse = planOuting(base({ candidates: real.filter((c) => !/club|society/i.test(c.name)).slice(0, 3), interests: ["Parks"] }));
  ok("sparse area: a plan from the 3 real places there", sparse.stops.length >= 2 && sparse.stops.length <= 3);
  ok("sparse area: the plan says so", /Only 3 places nearby fit right now/.test(sparse.intro));
  const family = planOuting(base({ candidates: real, interests: ["Playgrounds", "Gardens"], nowMs: at(10) }));
  ok("a pick with nothing nearby is named plainly", /No playgrounds are among the places loaded nearby/.test(family.intro));
}

console.log("\n── wording ──");
{
  const plans = [];
  for (const [d, now, i] of [[45, at(11), ["Parks"]], [120, at(14, 30), ["Parks", "Trails"]], [240, at(9, 30), ["Gardens"]], [90, at(16, 50), ["Scenic"]]]) {
    for (const list of [town, real]) plans.push(planOuting(base({ candidates: list, durationMinutes: d, nowMs: now, interests: i })));
  }
  const text = plans.flatMap((p) => [p.title, p.intro, ...p.stops.map((s) => s.why)]).join("\n");
  ok("never claims AI", !/\bAI\b|artificial intelligence|language model|Claude/i.test(text));
  ok("no placeholder or broken values", !/undefined|NaN|null|\[object|\$\{/.test(text));
  ok("no two stops in a plan share the same why", plans.every((p) => new Set(p.stops.map((s) => s.why)).size === p.stops.length));
  ok("every why gives an arrival time or the sunset", plans.every((p) => p.stops.every((s) => /\d{1,2}:\d{2} (am|pm)/.test(s.why))));
  ok("phrasing varies across plans", new Set(plans.flatMap((p) => p.stops.map((s) => s.why.split(/[·;,]/)[0].replace(/\b(park|garden|viewpoint|Parks|Trails|Gardens|Scenic)\b/g, "")))).size >= 4);
  ok("1–3 tips per plan", plans.every((p) => p.tips.length >= 1 && p.tips.length <= 3));
  ok("kind mapping follows the app's categories", kindOf({ name: "Alum Rock Open Space", category: "Parks" }) === "reserve" && kindOf({ name: "Overlook", category: "Scenic" }) === "viewpoint");
}

console.log("\n── event plan without a model ──");
{
  const ev = (id, title, h, m, dLat, extra = {}) => ({ id, title, category: "Social", organizer: "Org", startMs: at(h, m),
    locationName: `Venue ${id}`, isFree: true, latitude: START.lat + dLat, longitude: START.lng, social: 0, ...extra });
  const rows = [ev("a", "Poe Fest", 18, 0, 0.002), ev("b", "Book Swap", 18, 30, 0.003), ev("c", "Garden Talk", 15, 0, 0.004),
    ev("d", "Night Market", 20, 30, 0.02), ev("e", "Tomorrow Thing", 34, 0, 0.001)];
  const plan = sequenceEventsFallback(rows);
  const ids = plan.stops.map((s) => s.eventId);
  ok("overlapping events are not both chosen", !(ids.includes("a") && ids.includes("b")));
  ok("only the first pick's day", !ids.includes("e"));
  ok("in time order", ids.join(",") === ["c", "a", "d"].filter((x) => ids.includes(x)).join(","), ids.join(","));
  const chosen = ids.map((id) => rows.find((r) => r.id === id));
  ok("each event reachable after the one before", chosen.every((e, i) => i === 0 || e.startMs >= chosen[i - 1].startMs + ASSUMED_EVENT_MINUTES * 60_000));
  const whyOf = (id) => plan.stops.find((s) => s.eventId === id)?.why ?? "";
  ok("the best-ranked event (not just the earliest) says why it leads, with its host",
    /^Your best-ranked match for these choices · .*hosted by Org\./.test(whyOf("a")) && !/best-ranked/.test(whyOf("c")), `${whyOf("a")} | ${whyOf("c")}`);
  ok("every later stop gives the walk/drive from the one before and the gap", plan.stops.slice(1).every((s) =>
    /(\d+-min (walk|drive) from |Same venue as ).+ · starts \d/.test(s.why)), plan.stops.map((s) => s.why).join(" | "));
  ok("no why repeats the card's time or venue", plan.stops.every((s) => !/\d{1,2}:\d{2} (am|pm)|Venue /.test(s.why)));
  ok("a friend going is mentioned only when true", !plan.stops.some((s) => /friend/.test(s.why))
    && /a friend is going/.test(sequenceEventsFallback([ev("f", "With Friends", 12, 0, 0, { social: 0.85 })]).stops[0].why));
  ok("title and intro carry no AI claim", !/\bAI\b/.test(plan.title + plan.intro) && /timed events in order/.test(plan.intro));
  // A day-long listing (midnight start, 23:59:59 end) is "any time that day", never "12:00 am".
  const allDay = ev("z", "Spooky Season Scavenger Hunt", 0, 0, 0.001, { allDay: true });
  const withAllDay = sequenceEventsFallback([allDay, rows[2], rows[0], rows[3]]);
  ok("a day-long listing never gives the plan a midnight start", !/12:00 am/.test(withAllDay.title + withAllDay.intro),
    `${withAllDay.title} | ${withAllDay.intro}`);
  ok("…its why says it runs all day", /runs all day/.test(withAllDay.stops.find((s) => s.eventId === "z")?.why ?? ""));
  ok("…and the timed events still chain in order", withAllDay.stops.filter((s) => s.eventId !== "z").map((s) => s.eventId).join(",") === "c,a");
  ok("isAllDayListing: midnight start + 23:59:59 end, or 'All day'", isAllDayListing(at(0), at(23, 59) + 59_000, "12:00 AM")
    && isAllDayListing(at(10), undefined, "All day") && !isAllDayListing(at(0), at(2), "12:00 AM") && !isAllDayListing(at(15), at(23, 59), "3:00 PM"));
}

console.log(`\n══ ${pass} passed, ${fail} failed ══`);
process.exit(fail ? 1 : 0);
