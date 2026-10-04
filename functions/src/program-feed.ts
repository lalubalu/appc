/** Keep ranking weights/signals frozen; enforce canonical listing eligibility after scoring. */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, requireUid, enforceRateLimit, safeText } from "./common.js";
import { recommendFor } from "./ranking.js";
import { programEligible, isProgram } from "./programs.js";
import { createFeedSession } from "./feedTelemetry.js";
export async function recommendEligibleFor(uid: string, areaId: string, lat?: number, lng?: number, limit = 50, now = Date.now()) {
  const ranked = await recommendFor(uid, areaId, lat, lng, 100, now);
  if (!ranked.length) return [];
  const [profile, docs] = await Promise.all([db.doc(`users/${uid}`).get(), db.getAll(...ranked.map(r => db.doc(`events/${r.id}`)))]);
  // Re-read canonical state: a five-minute ranking cache cannot retain a deactivated or expired program.
  return ranked.filter((r, i) => { const d = docs[i].data(); return d && (!isProgram(d) || programEligible(d, profile.data() ?? {}, now)); }).slice(0, limit);
}
export const recommendedEvents = onCall(async req => {
  const uid = requireUid(req.auth); await enforceRateLimit(uid, "recommendedEvents");
  const areaId = safeText(req.data?.areaId, 60) || "san-jose-ca";
  if (areaId.includes("/")) throw new HttpsError("invalid-argument", "Invalid area.");
  const lat = Number(req.data?.lat), lng = Number(req.data?.lng);
  const hasLoc = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  const limit = Math.min(100, Math.max(1, Math.floor(Number(req.data?.limit ?? 50)) || 50));
  const ranked = await recommendEligibleFor(uid, areaId, hasLoc ? lat : undefined, hasLoc ? lng : undefined, limit);
  if (!ranked.length) throw new HttpsError("not-found", "No upcoming eligible events in this area yet.");
  const feedSessionId = req.data?.telemetryEnabled === true ? await createFeedSession(uid, areaId, ranked) : null;
  return { areaId, feedSessionId, personalized: true, events: ranked.map(r => ({ id: r.id, score: Number(r.score.toFixed(4)), parts: r.parts })) };
});
