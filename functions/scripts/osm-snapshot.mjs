// CAC 2026 (1.4) — capture the bundled OpenStreetMap snapshot for the launch area.
//
//   node functions/scripts/osm-snapshot.mjs            # tries each Overpass mirror, 25 s each
//   node functions/scripts/osm-snapshot.mjs --from file.json   # wrap an Overpass answer already saved to disk
//
// Runs the app's OWN Overpass query (read out of PlacesAPIService.swift so the two
// cannot drift) around the San José launch-area centre and writes
// Verdure/Verdure/Resources/osm-snapshot-san-jose.json with the capture time,
// the mirror that answered and the ODbL attribution. The app uses it as the
// starting place cache when every mirror is down (as all four were on
// 2026-10-22 and 2026-10-25). Public data under the ODbL; the credit stays on
// every screen that shows these places.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const CENTER = { lat: 37.3382, lng: -121.8863 };   // LAUNCH_AREAS[0].center (functions/src/ingest/areas.ts)
const RADIUS_M = 5000, LIMIT = 60;                 // PlacesAPIService: radiusMeters, maxPlaces * 2
const MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];
const USER_AGENT = "Verdure/1.0 (+https://verdure-app.com)";
const OUT = join(root, "Verdure", "Verdure", "Resources", "osm-snapshot-san-jose.json");

/** The query template as the app builds it, taken from the Swift source. */
export function queryFromSwift(swiftSource, center, radius, limit) {
  const m = /static func overpassQuery[\s\S]*?return """\n([\s\S]*?)\n\s*"""/.exec(swiftSource);
  if (!m) throw new Error("Could not find overpassQuery in PlacesAPIService.swift");
  return m[1].split("\n").map((l) => l.replace(/^ {8}/, "")).join("\n")
    .replace(/\\\(r\)/g, String(radius)).replace(/\\\(lat\)/g, String(center.lat)).replace(/\\\(lon\)/g, String(center.lng)).replace(/\\\(limit\)/g, String(limit));
}

export function wrapSnapshot(overpassBody, endpoint, now = new Date()) {
  if (!Array.isArray(overpassBody?.elements) || overpassBody.elements.length < 10) throw new Error("Overpass answer has too few elements to be a useful snapshot");
  const named = overpassBody.elements.filter((e) => e.tags?.name && ((e.lat && e.lon) || e.center));
  return {
    _comment: "Bundled OpenStreetMap snapshot for the San José launch area — the app's own Overpass query, captured once. Used only when every Overpass mirror fails. Data © OpenStreetMap contributors, ODbL (openstreetmap.org/copyright).",
    center: { lat: CENTER.lat, lon: CENTER.lng },
    radiusMeters: RADIUS_M,
    fetchedAt: now.toISOString(),
    endpoint,
    osm3s: overpassBody.osm3s ?? null,
    attribution: "© OpenStreetMap contributors (ODbL)",
    elements: named,
  };
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const fromIdx = process.argv.indexOf("--from");
  let body, endpoint;
  if (fromIdx >= 0) {
    body = JSON.parse(readFileSync(process.argv[fromIdx + 1], "utf8"));
    endpoint = process.argv[fromIdx + 2] && !process.argv[fromIdx + 2].startsWith("--") ? process.argv[fromIdx + 2] : "saved answer";
  } else {
    const swift = readFileSync(join(root, "Verdure", "Verdure", "Models", "PlacesAPIService.swift"), "utf8");
    const query = queryFromSwift(swift, CENTER, RADIUS_M, LIMIT);
    for (const mirror of MIRRORS) {
      try {
        const res = await fetch(mirror, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": USER_AGENT },
          body: "data=" + encodeURIComponent(query), signal: AbortSignal.timeout(25_000) });
        if (!res.ok) { console.error(`${mirror}: HTTP ${res.status}`); continue; }
        body = await res.json(); endpoint = mirror; break;
      } catch (e) { console.error(`${mirror}: ${e.message}`); }
    }
    if (!body) { console.error("No Overpass mirror answered; nothing written."); process.exit(2); }
  }
  const snapshot = wrapSnapshot(body, endpoint);
  writeFileSync(OUT, JSON.stringify(snapshot, null, 1) + "\n");
  console.log(`wrote ${OUT}: ${snapshot.elements.length} named elements from ${endpoint} at ${snapshot.fetchedAt}`);
}
