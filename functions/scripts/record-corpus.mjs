// Record the configured public feeds ONCE into a gzipped fixture.
//
//   npm run build && node scripts/record-corpus.mjs            # live network, read-only
//
// This is the sprint's single "live run per milestone". It calls the real
// adapters for every source family configured in ingest/areas.ts (plus
// Ticketmaster when TICKETMASTER_KEY is set; SerpApi is never called because
// every call spends monthly quota) and writes the normalized records to
// functions/test-fixtures/corpus/<areaId>-<date>.json.gz together with a
// manifest. Nothing is written to Firestore. Every later measurement replays
// this file through the actual ingest code, so before/after numbers come from
// identical input.

import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { SAN_JOSE } from "../lib/ingest/areas.js";
import { fetchTicketmaster } from "../lib/ingest/sources/ticketmaster.js";
import { fetchIcsFeed } from "../lib/ingest/sources/icsfeed.js";
import { fetchLibCal } from "../lib/ingest/sources/libcal.js";
import { fetchBiblioCommons } from "../lib/ingest/sources/bibliocommons.js";
import { fetchMidpen } from "../lib/ingest/sources/midpen.js";
import { fetchLocalist } from "../lib/ingest/sources/localist.js";
import { fetchLiveWhale } from "../lib/ingest/sources/livewhale.js";
import { fetchLegistar } from "../lib/ingest/sources/legistar.js";
import { CORPUS_DIR, saveRecordedCorpus } from "./corpus-fixture.mjs";

const area = SAN_JOSE;
const recordedAt = new Date();
const date = recordedAt.toISOString().slice(0, 10);
const corpus = { kind: "recorded-normalized-corpus", areaId: area.id, recordedAt: recordedAt.toISOString(),
  radiusMiles: area.radiusMiles, sources: {}, feeds: [], skipped: [] };

async function feed(sourceId, name, fetcher) {
  const started = Date.now();
  try {
    const records = await fetcher();
    const bucket = corpus.sources[sourceId] ??= { records: [] };
    bucket.records.push(...records);
    corpus.feeds.push({ source: sourceId, name, records: records.length,
      withCoordinates: records.filter((r) => typeof r.latitude === "number").length, seconds: (Date.now() - started) / 1000 });
    console.log(`${sourceId.padEnd(14)} ${name}: ${records.length} records`);
  } catch (e) {
    corpus.feeds.push({ source: sourceId, name, records: 0, error: String(e?.message ?? e) });
    console.error(`${sourceId.padEnd(14)} ${name}: FAILED ${e?.message ?? e}`);
  }
}

if (process.env.TICKETMASTER_KEY) await feed("ticketmaster", "Ticketmaster Discovery", () => fetchTicketmaster(area, process.env.TICKETMASTER_KEY));
else corpus.skipped.push({ source: "ticketmaster", reason: "TICKETMASTER_KEY not set ($0 sprint; no key on this machine)" });
corpus.skipped.push({ source: "serpapi", reason: "never recorded: every call spends monthly quota" });
corpus.skipped.push({ source: "nps", reason: "no NPS unit inside the launch radius (areas.ts)" });
for (const f of area.libcal) await feed("libcal", f.name, () => fetchLibCal(area, f));
for (const f of area.bibliocommons ?? []) await feed("bibliocommons", f.name, () => fetchBiblioCommons(area, f));
for (const c of area.localist) await feed("localist", c.name, () => fetchLocalist(area, c.host, c.name));
for (const c of area.livewhale) await feed("livewhale", c.name, () => fetchLiveWhale(area, c.host, c.name));
for (const c of area.legistar) await feed("legistar", c.name, () => fetchLegistar(area, c.client, c.name));
for (const f of area.midpen ?? []) await feed("midpen", f.name, () => fetchMidpen(area, f));
for (const f of area.ics) await feed("ics", f.name, () => fetchIcsFeed(area, f, "ics"));

const failed = corpus.feeds.filter((f) => f.error);
const path = join(CORPUS_DIR, `${area.id}-${date}.json.gz`);
const { bytes, sha256 } = saveRecordedCorpus(path, corpus);
const manifest = { recordedAt: corpus.recordedAt, areaId: area.id, file: `${area.id}-${date}.json.gz`, uncompressedBytes: bytes, sha256,
  totalRecords: Object.values(corpus.sources).reduce((n, s) => n + s.records.length, 0),
  perSource: Object.fromEntries(Object.entries(corpus.sources).map(([s, v]) => [s, v.records.length])),
  feeds: corpus.feeds, skipped: corpus.skipped };
writeFileSync(join(CORPUS_DIR, `MANIFEST-${area.id}-${date}.json`), JSON.stringify(manifest, null, 2) + "\n");
console.log(JSON.stringify({ path, ...manifest }, null, 2));
if (failed.length) { console.error(`${failed.length} feed(s) failed; the recording is partial.`); process.exit(1); }
