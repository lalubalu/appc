// Review queue for events the deterministic classifier could not label well.
// Read-only; use FIRESTORE_EMULATOR_HOST to inspect local fixtures.
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
initializeApp(emulator
  ? { projectId: process.env.GCLOUD_PROJECT || "connectify-19dd8" }
  : { credential: applicationDefault(), projectId: process.env.GCLOUD_PROJECT || "connectify-19dd8" });
const db = getFirestore();
const threshold = 0.65;
const snap = await db.collection("events")
  .where("classificationConfidence", "<", threshold)
  .orderBy("classificationConfidence")
  .limit(200).get();
console.log("id\tsource\tconfidence\tcategory\ttitle");
for (const doc of snap.docs) {
  const d = doc.data();
  const safe = (value) => String(value ?? "").replace(/[\t\r\n]/g, " ");
  console.log([doc.id, safe(d.source), Number(d.classificationConfidence).toFixed(2),
    safe(d.category), safe(d.title)].join("\t"));
}
console.error(`${snap.size} events below ${threshold} (first 200)`);
