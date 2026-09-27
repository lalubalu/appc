// Live smoke test for the ingestion fetchers — READ-ONLY, no Firestore writes.
//
//   TICKETMASTER_KEY=... NPS_API_KEY=... node scripts/ingest-smoke.mjs
//
// Proves each source that remains in the tree actually returns real data for
// the launch area today (Part 2 §1 "done when": every provider remaining can be
// demonstrated returning real data). SerpApi is deliberately NOT called here —
// every call spends monthly quota — its mapper is covered by unit tests.
//
// Prints one line per source: count, a sample title, and how many records
// carry coordinates. Exit code 1 if any configured source returns zero.

import { SAN_JOSE, isInsideArea } from "../lib/ingest/areas.js";
import { enrichEvent } from "../lib/ingest/classify.js";
import { fetchTicketmaster } from "../lib/ingest/sources/ticketmaster.js";
import { fetchIcsFeed } from "../lib/ingest/sources/icsfeed.js";
import { fetchLibCal } from "../lib/ingest/sources/libcal.js";
import { fetchBiblioCommons } from "../lib/ingest/sources/bibliocommons.js";
import { fetchMidpen } from "../lib/ingest/sources/midpen.js";
import { fetchLocalist } from "../lib/ingest/sources/localist.js";
import { fetchLiveWhale } from "../lib/ingest/sources/livewhale.js";
import { fetchLegistar } from "../lib/ingest/sources/legistar.js";
import { fetchNps } from "../lib/ingest/sources/nps.js";

const area = SAN_JOSE;
let failures = 0;

function report(name, records) {
  const withCoords = records.filter((r) => typeof r.latitude === "number").length;
  const free = records.filter((r) => r.isFree).length;
  const sample = records[0] ? `"${records[0].title}" @ ${records[0].locationName} (${records[0].start.toISOString().slice(0, 16)})` : "—";
  const cats = {};
  for (const r of records) cats[r.category] = (cats[r.category] ?? 0) + 1;
  console.log(`${records.length ? "✅" : "❌"} ${name}: ${records.length} events, ${withCoords} with coords, ${free} free · ${sample}`);
  console.log(`     categories: ${JSON.stringify(cats)}`);
  const now = Date.now();
  const next30Days = now + 30 * 86_400_000;
  const inRadius = records.filter((r) => r.latitude != null && r.longitude != null &&
    isInsideArea(area, r.latitude, r.longitude, 0) &&
    r.start.getTime() >= now && r.start.getTime() < next30Days);
  const volunteerCandidates = inRadius.filter((r) => enrichEvent(r).category === "Volunteer");
  console.log(`     preview only: ${inRadius.length} dated, geocoded records within ${area.radiusMiles} mi in 30 days; ` +
    `${volunteerCandidates.length} classified Volunteer before dedupe/human review`);
  if (!records.length) failures++;
}

async function run(name, fn) {
  try { report(name, await fn()); }
  catch (e) { failures++; console.log(`❌ ${name}: ${e.message}`); }
}

console.log(`── Live ingest smoke — ${area.name} (${area.radiusMiles} mi) ──`);
if (process.env.TICKETMASTER_KEY) {
  await run("ticketmaster", () => fetchTicketmaster(area, process.env.TICKETMASTER_KEY));
} else console.log("⏭  ticketmaster: TICKETMASTER_KEY not set");
for (const feed of area.libcal) await run(`libcal · ${feed.name}`, () => fetchLibCal(area, feed));
for (const feed of area.bibliocommons ?? []) await run(`bibliocommons · ${feed.name}`, () => fetchBiblioCommons(area, feed));
for (const cal of area.localist) await run(`localist · ${cal.name}`, () => fetchLocalist(area, cal.host, cal.name));
for (const cal of area.livewhale) await run(`livewhale · ${cal.name}`, () => fetchLiveWhale(area, cal.host, cal.name));
for (const cal of area.legistar) await run(`legistar · ${cal.name}`, () => fetchLegistar(area, cal.client, cal.name));
if (process.env.NPS_API_KEY) {
  await run("nps", () => fetchNps(area, process.env.NPS_API_KEY));
} else console.log("⏭  nps: NPS_API_KEY not set");
for (const feed of area.midpen ?? []) await run(`midpen · ${feed.name}`, () => fetchMidpen(area, feed));
for (const feed of area.ics) await run(`ics · ${feed.name}`, () => fetchIcsFeed(area, feed, "ics"));

console.log(failures ? `\n${failures} source(s) returned nothing or failed` : "\nall configured sources returned real data");
process.exit(failures ? 1 : 0);
