/** Evaluate the ranking engine against a human-labeled, frozen corpus.
 * Usage: npm run build && node scripts/rank-eval.mjs <corpus.json> <golden.json>
 * No synthetic relevance judgments are generated here: a named reviewer must
 * supply the twenty profile -> relevant event ID pairs.
 */
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { rankEvents } from "../lib/ranking.js";

const [corpusPath, goldenPath] = process.argv.slice(2);
if (!corpusPath || !goldenPath) {
  console.error("Usage: node scripts/rank-eval.mjs <frozen-corpus.json> <human-golden.json>");
  process.exit(2);
}

const corpus = JSON.parse(readFileSync(corpusPath, "utf8"));
const golden = JSON.parse(readFileSync(goldenPath, "utf8"));
if (!Array.isArray(corpus.events) || !Array.isArray(golden.profiles) || golden.profiles.length !== 20) {
  throw new Error("Corpus must have events[] and golden set must have exactly 20 profiles[].");
}
if (!golden.reviewerName?.trim() || !golden.reviewedAt?.trim()) {
  throw new Error("Golden set needs a named human reviewer and review date.");
}
if (corpus.corpusHash && golden.corpusHash !== corpus.corpusHash) {
  throw new Error("Golden labels were made for a different frozen corpus.");
}
if (corpus.corpusHash && corpus.corpusHash !== createHash("sha256").update(JSON.stringify(corpus.events)).digest("hex")) {
  throw new Error("The frozen corpus changed after it was exported.");
}
const eventIds = new Set(corpus.events.map((e) => e.id));
const nowMs = Number(corpus.snapshotAtMs);
if (!Number.isFinite(nowMs)) throw new Error("Corpus needs a fixed snapshotAtMs.");
const results = golden.profiles.map((row) => {
  if (!row.id || !Array.isArray(row.relevantEventIDs) || !row.relevantEventIDs.length) {
    throw new Error(`Profile ${row.id ?? "?"} needs human relevantEventIDs.`);
  }
  for (const id of row.relevantEventIDs) if (!eventIds.has(id)) {
    throw new Error(`Golden relevant ID ${id} is absent from the frozen corpus.`);
  }
  const ctx = {
    interests: [], attendedCategories: {}, friendsGoing: {}, recentOrganizers: {},
    nowMs, ...(row.context ?? {}),
  };
  const ranked = rankEvents(corpus.events, ctx).map((e) => e.id);
  const relevant = new Set(row.relevantEventIDs);
  const first = ranked.findIndex((id) => relevant.has(id));
  const p10 = ranked.slice(0, 10).filter((id) => relevant.has(id)).length / Math.min(10, ranked.length);
  return { id: row.id, precisionAt10: Number(p10.toFixed(3)), firstRelevantPosition: first < 0 ? null : first + 1 };
});
const meanP10 = results.reduce((sum, row) => sum + row.precisionAt10, 0) / results.length;
const firstPositions = results.map((r) => r.firstRelevantPosition).filter((n) => n !== null);
console.log(JSON.stringify({ corpus: corpusPath, golden: goldenPath, profiles: results,
  meanPrecisionAt10: Number(meanP10.toFixed(3)),
  meanFirstRelevantPosition: firstPositions.length
    ? Number((firstPositions.reduce((a, b) => a + b, 0) / firstPositions.length).toFixed(2)) : null,
  profilesWithNoRelevantResult: results.length - firstPositions.length }, null, 2));
