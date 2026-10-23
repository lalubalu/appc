/**
 * Adventure Planner scenario review: real San José candidates (the bundled
 * OpenStreetMap snapshot, mapped and trimmed exactly as the app sends them), ten
 * scenarios plus today's live Open-Meteo conditions, written to ../planner-review.md
 * with the checks a picky local would make.
 *
 *   npm run build && node scripts/adventure-review.mjs [--out ../../planner-review.md]
 */
import { readFileSync, writeFileSync } from "node:fs";
import { planOuting, openIntervals, kindOf, distanceKm, clockText, EngineError } from "../lib/adventure-engine.js";

const SNAPSHOT = new URL("../../Verdure/Verdure/Resources/osm-snapshot-san-jose.json", import.meta.url);
const OUT = process.argv.includes("--out") ? process.argv[process.argv.indexOf("--out") + 1] : new URL("../../../planner-review.md", import.meta.url);
const SJSU = { lat: 37.3352, lng: -121.8811 };
const OFFSET = -7 * 3600;                         // PDT on 2026-10-23
const DAY = Date.parse("2026-10-23T00:00:00-07:00");
const at = (h, m = 0) => DAY + (h * 60 + m) * 60_000;
const SUNRISE = at(7, 23), SUNSET = at(18, 19);   // Open-Meteo, San José, 2026-10-23

/** PlacesAPIService.categorize, verbatim in JS. */
function categorize(t) {
  const leisure = t.leisure ?? "", highway = t.highway ?? "", natural = t.natural ?? "", tourism = t.tourism ?? "", amenity = t.amenity ?? "";
  if (leisure === "garden") return "Gardens";
  if (leisure === "playground") return "Playgrounds";
  if (leisure === "sports_centre" || leisure === "pitch") return "Sports";
  if (leisure === "nature_reserve") return "Scenic";
  if (highway === "path" || highway === "footway") return "Trails";
  if (natural === "water" || natural === "beach") return "Waterfront";
  if (tourism === "viewpoint") return "Scenic";
  if (amenity === "community_centre") return "Community";
  return "Parks";
}

/** What the app sends: named OSM places within 5 km, nearest 30 (PlacesAPIService.maxPlaces). */
function candidatesAround(origin, limit = 30) {
  const snap = JSON.parse(readFileSync(SNAPSHOT, "utf8"));
  const seen = new Set();
  return snap.elements
    .map((e) => ({ e, lat: e.lat ?? e.center?.lat, lon: e.lon ?? e.center?.lon }))
    .filter(({ e, lat, lon }) => e.tags?.name && lat && lon)
    .map(({ e, lat, lon }) => ({ e, lat, lon, km: distanceKm(origin.lat, origin.lng, lat, lon) }))
    .filter((x) => x.km <= 5)
    .sort((a, b) => a.km - b.km)
    .filter(({ e }) => { const k = e.tags.name.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; })
    .slice(0, limit)
    .map(({ e, lat, lon }) => ({
      id: `osm-${e.id}`, name: e.tags.name, category: categorize(e.tags), latitude: lat, longitude: lon,
      hours: e.tags.opening_hours, hasPhoto: Boolean(e.tags.image), description: e.tags.description,
    }));
}

function conditions({ tempF = 70, code = 0, rain = 0, wind = 10, hot } = {}) {
  const hourly = Array.from({ length: 36 }, (_, h) => ({
    ms: at(h), tempF: hot && h >= 11 && h <= 17 ? hot : tempF, precipProb: rain, windKmh: wind, code,
  }));
  return { utcOffsetSeconds: OFFSET, sunriseMs: SUNRISE, sunsetMs: SUNSET,
    current: { tempF: hot ?? tempF, code, windKmh: wind, precipMm: code >= 51 ? 1.2 : 0 }, hourly };
}

async function liveConditions() {
  const q = new URLSearchParams({ latitude: SJSU.lat, longitude: SJSU.lng,
    current: "temperature_2m,precipitation,weather_code,wind_speed_10m",
    hourly: "precipitation_probability,temperature_2m,wind_speed_10m,weather_code",
    daily: "sunrise,sunset", timezone: "auto", forecast_days: 2, temperature_unit: "fahrenheit", wind_speed_unit: "kmh" });
  const body = await (await fetch(`https://api.open-meteo.com/v1/forecast?${q}`, { signal: AbortSignal.timeout(10_000) })).json();
  const off = body.utc_offset_seconds;
  const local = (s) => Date.parse(`${s}:00Z`) - off * 1000;
  return {
    utcOffsetSeconds: off, sunriseMs: local(body.daily.sunrise[0]), sunsetMs: local(body.daily.sunset[0]),
    current: { tempF: body.current.temperature_2m, code: body.current.weather_code, windKmh: body.current.wind_speed_10m, precipMm: body.current.precipitation },
    hourly: body.hourly.time.map((t, i) => ({ ms: local(t), precipProb: body.hourly.precipitation_probability[i] ?? 0,
      tempF: body.hourly.temperature_2m[i], windKmh: body.hourly.wind_speed_10m[i], code: body.hourly.weather_code[i] })),
  };
}

const all = candidatesAround(SJSU);
const scenarios = [
  { name: "1. Sunny afternoon, 2 h, Parks + Trails", now: at(14, 30), duration: 120, interests: ["Parks", "Trails"], cond: conditions({ tempF: 72 }) },
  { name: "2. Rainy morning, 1 h, Parks + Gardens", now: at(9), duration: 60, interests: ["Parks", "Gardens"], cond: conditions({ tempF: 56, code: 63, rain: 85 }) },
  { name: "3. Hot day, 3 h, Parks + Trails + Waterfront", now: at(12), duration: 180, interests: ["Parks", "Trails", "Waterfront"], cond: conditions({ tempF: 88, hot: 96 }) },
  { name: "4. Evening, 90 min, Scenic", now: at(16, 50), duration: 90, interests: ["Scenic"], cond: conditions({ tempF: 66 }) },
  { name: "5. Family, 2 h, Playgrounds + Gardens", now: at(10), duration: 120, interests: ["Playgrounds", "Gardens"], cond: conditions({ tempF: 68 }) },
  { name: "6. Community, 2 h", now: at(13), duration: 120, interests: ["Community"], cond: conditions({ tempF: 70 }) },
  { name: "7. Very short, 45 min, Parks", now: at(11), duration: 45, interests: ["Parks"], cond: conditions({ tempF: 70 }) },
  { name: "8. Long, 4 h, Parks + Trails + Gardens + Waterfront", now: at(9, 30), duration: 240, interests: ["Parks", "Trails", "Gardens", "Waterfront"], cond: conditions({ tempF: 70 }) },
  { name: "9. Few candidates (3), 2 h, Parks", now: at(14), duration: 120, interests: ["Parks"], cond: conditions({ tempF: 70 }), candidates: all.filter((c) => !/\b(club|society)\b/i.test(c.name)).slice(0, 3) },
  { name: "10a. Regenerate — scenario 1, seed 2", now: at(14, 30), duration: 120, interests: ["Parks", "Trails"], cond: conditions({ tempF: 72 }), seed: 2, previousFrom: 0 },
  { name: "10b. Regenerate — scenario 1, seed 3", now: at(14, 30), duration: 120, interests: ["Parks", "Trails"], cond: conditions({ tempF: 72 }), seed: 3, previousFrom: "10a" },
];

function checks(plan, s) {
  const out = [];
  const total = plan.totalMinutes;
  const fit = total / s.duration;
  out.push(`${fit >= 0.9 && fit <= 1.1 ? "✅" : "❌"} duration ${total} of ${s.duration} min (${Math.round(fit * 100)}%)`);
  const ids = new Set((s.candidates ?? all).map((c) => c.id));
  out.push(`${plan.stops.every((x) => ids.has(x.placeId)) ? "✅" : "❌"} every stop is a candidate`);
  const byId = new Map((s.candidates ?? all).map((c) => [c.id, c]));
  const sun = { sunriseMin: 7 * 60 + 23, sunsetMin: 18 * 60 + 19 };
  const closed = plan.stops.filter((x) => {
    const open = openIntervals(byId.get(x.placeId).hours, 5, sun);   // 2026-10-23 is a Friday
    if (!open) return false;
    const a = (x.arriveMs - DAY) / 60_000, b = (x.leaveMs - DAY) / 60_000;
    return !open.some(([o, c]) => a >= o && b <= c);
  });
  out.push(`${closed.length ? "❌" : "✅"} no stop while closed${closed.length ? `: ${closed.map((c) => c.name).join(", ")}` : ""}`);
  const dark = plan.stops.filter((x) => ["trail", "reserve", "park", "garden", "playground", "water"].includes(x.kind) && (x.leaveMs > SUNSET || x.arriveMs < SUNRISE));
  out.push(`${dark.length ? "❌" : "✅"} outdoor stops in daylight${dark.length ? `: ${dark.map((d) => d.name).join(", ")}` : ""}`);
  // Variety rule (documented): no repeated kind while an unused kind that matches the
  // user's picks was available among the candidates.
  const kinds = plan.stops.map((x) => x.kind);
  const onTopic = new Set((s.candidates ?? all).map((c) => kindOf(c)).filter((k) => s.interests.some((i) =>
    ({ Parks: ["park", "garden", "water", "viewpoint", "trail", "reserve"], Trails: ["trail", "reserve", "park", "garden", "water", "viewpoint"],
       Gardens: ["garden", "park", "water", "viewpoint", "trail", "reserve"], Waterfront: ["water", "park", "garden", "viewpoint", "trail", "reserve"],
       Scenic: ["viewpoint", "park", "garden", "water", "trail", "reserve"], Playgrounds: ["playground", "park"], Sports: ["sports"], Community: ["community"] })[i]?.includes(k))));
  const repeated = kinds.length !== new Set(kinds).size;
  const unusedOnTopic = [...onTopic].filter((k) => !kinds.includes(k));
  out.push(`${!repeated || s.interests.length === 1 || unusedOnTopic.length === 0 ? "✅" : "❌"} variety: ${kinds.join(", ")}${repeated && unusedOnTopic.length ? ` (unused: ${unusedOnTopic.join(", ")})` : ""}`);
  return out;
}

function render(s, plan, live = false) {
  const lines = [`## ${s.name}${live ? " (live Open-Meteo)" : ""}`, ""];
  lines.push(`Start ${clockText(s.now, s.cond.utcOffsetSeconds)} from SJSU · ${s.duration} min · interests: ${s.interests.join(", ") || "none"} · ` +
    `${Math.round(s.cond.current.tempF)}°F, code ${s.cond.current.code}, rain ${Math.max(...s.cond.hourly.map((h) => h.precipProb))}% · sunset ${clockText(s.cond.sunsetMs, s.cond.utcOffsetSeconds)}`, "");
  lines.push(`**${plan.title}**`, "", plan.intro, "");
  for (const x of plan.stops) {
    lines.push(`${x.order}. **${x.name}** (${x.category}, ${x.kind}) — ${x.minutes} min (${x.travelMinutes}-min ${x.mode} + ${Math.round((x.leaveMs - x.arriveMs) / 60000)} there), ` +
      `${clockText(x.arriveMs, s.cond.utcOffsetSeconds)}–${clockText(x.leaveMs, s.cond.utcOffsetSeconds)}`);
    lines.push(`   > ${x.why}`);
  }
  lines.push("", ...checks(plan, s).map((c) => `- ${c}`), "");
  return lines.join("\n");
}

const md = [`# Adventure Planner review — deterministic engine, real San José candidates`, "",
  `Candidates: the ${all.length} nearest named OpenStreetMap places within 5 km of SJSU, from the bundled snapshot ` +
  `(© OpenStreetMap contributors, ODbL), categorised exactly as PlacesAPIService does. Scenario weather is set per ` +
  `scenario; sunrise 7:23 am and sunset 6:19 pm are Open-Meteo's for 2026-10-23. Generated ${new Date().toISOString()}.`, ""];
const plans = new Map();
for (const s of scenarios) {
  const previousStopIds = s.previousFrom === 0 ? plans.get(scenarios[0].name)?.stops.map((x) => x.placeId)
    : s.previousFrom ? plans.get(scenarios.find((x) => x.name.startsWith(s.previousFrom)).name)?.stops.map((x) => x.placeId) : undefined;
  if (process.env.REVIEW_PROGRESS) console.error(`planning ${s.name}`);
  try {
    const plan = planOuting({ lat: SJSU.lat, lng: SJSU.lng, nowMs: s.now, durationMinutes: s.duration, interests: s.interests,
      candidates: s.candidates ?? all, conditions: s.cond, seed: s.seed ?? 1, previousStopIds });
    plans.set(s.name, plan);
    md.push(render(s, plan));
  } catch (e) {
    md.push(`## ${s.name}`, "", `Engine answered: ${e instanceof EngineError ? `${e.code} — ${e.message}` : e}`, "");
  }
}
try {
  const cond = await liveConditions();
  const s = { name: "11. Right now", now: Date.now(), duration: 120, interests: ["Parks", "Trails"], cond };
  md.push(render(s, planOuting({ lat: SJSU.lat, lng: SJSU.lng, nowMs: s.now, durationMinutes: 120, interests: s.interests, candidates: all, conditions: cond, seed: 1 }), true));
} catch (e) { md.push("## 11. Right now", "", `Live conditions unavailable or no plan: ${e.message}`, ""); }
writeFileSync(OUT, md.join("\n"));
console.log(`wrote ${OUT instanceof URL ? OUT.pathname : OUT} (${scenarios.length + 1} plans)`);
