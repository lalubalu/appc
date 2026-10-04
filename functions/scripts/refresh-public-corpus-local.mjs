// Refresh configured, previously permission-reviewed public feeds using the
// actual deduplicating ingestion pipeline. Never accepts production hosts/keys.
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { SAN_JOSE } from "../lib/ingest/areas.js";
import { runSource } from "../lib/ingest/index.js";
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8899");
assert.equal(process.env.GCLOUD_PROJECT, "connectify-19dd8");
const output = process.argv[2];
assert.ok(output, "Supply a local JSON report path");
const report = { startedAt: new Date().toISOString(), emulator: process.env.FIRESTORE_EMULATOR_HOST, areaId: SAN_JOSE.id, results: [] };
for (const source of ["bibliocommons", "libcal", "localist", "livewhale", "legistar", "midpen"]) {
  const result = await runSource(source, SAN_JOSE, {});
  report.results.push(result);
  writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(result));
}
report.finishedAt = new Date().toISOString();
writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
if (report.results.some(r => r.errors.length || !r.fetched)) throw new Error("A configured public source failed; inspect the report and staff source health.");
