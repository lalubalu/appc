import { selectPlanCandidates, avoidRecentPlanEvents, validateModelStops, refineSelection } from "../lib/eventPlanner.js";

let pass = 0;
let fail = 0;
function ok(name, condition) {
  if (condition) { pass++; console.log(`  ✅ ${name}`); }
  else { fail++; console.error(`  ❌ ${name}`); }
}

const nowMs = Date.UTC(2026, 8, 28, 15);
const rows = [
  { id: "a", title: "Park cleanup", category: "Cleanup", locationName: "Park", startMs: nowMs + 86_400_000, isFree: true, latitude: 37.3, longitude: -121.9 },
  { id: "b", title: "Maker workshop", category: "Workshop", locationName: "Library", startMs: nowMs + 2 * 86_400_000, isFree: false, priceMin: 10, latitude: 37.31, longitude: -121.9 },
  { id: "c", title: "Jazz concert", category: "Music", locationName: "Stage", startMs: nowMs + 3 * 86_400_000, isFree: false, priceMin: 25, latitude: 37.5, longitude: -121.9 },
  { id: "d", title: "Garden workshop", category: "Workshop", locationName: "Garden", startMs: nowMs + 4 * 86_400_000, isFree: true, latitude: 37.32, longitude: -121.9 },
];
const req = { when: "Any day", who: "Just me", distance: "Anywhere nearby", budget: "Doesn't matter", note: "", nowMs };
ok("free only excludes paid stops", selectPlanCandidates(rows, { ...req, budget: "Free" }).map((r) => r.id).join() === "a,d");
ok("search note narrows to real matching stops", selectPlanCandidates(rows, { ...req, note: "workshop" }).map((r) => r.id).join() === "b,d");
ok("model IDs are verified and de-duplicated", validateModelStops([
  { eventId: "invented", why: "x" }, { eventId: "a", why: "real" }, { eventId: "a", why: "again" }, { eventId: "b", why: "real" },
], rows).map((r) => r.eventId).join() === "a,b");
ok("refinement swaps without another model call", refineSelection(["a", "b"], rows, "cheaper", "b").join() === "a,d");
ok("longer adds a new verified stop", refineSelection(["a", "b"], rows, "longer", "").join() === "a,b,c");
ok("shorter keeps one verified stop", refineSelection(["a", "b"], rows, "shorter", "").join() === "a");
const futureRows = rows.map((row, index) => ({ ...row, startMs: nowMs + (16 + index) * 86_400_000 }));
const twoWeeksLater = selectPlanCandidates(futureRows, { ...req, nowMs: nowMs + 14 * 86_400_000 });
ok("same user two weeks later receives different still-upcoming stops",
  avoidRecentPlanEvents(twoWeeksLater, ["a", "b"]).map((row) => row.id).join() === "c,d");
console.log(`══ ${pass} passed, ${fail} failed ══`);
if (fail) process.exitCode = 1;
