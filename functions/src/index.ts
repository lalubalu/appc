/**
 * Verdure Cloud Functions — server-authoritative game logic.
 *
 * Why this exists: the iOS client computes points locally and the Firestore rules
 * only *clamp* them to a sane range — they can't verify points were actually earned.
 * These callables move the trust boundary to the server: the client asks to check in /
 * redeem, and the SERVER decides the outcome inside a transaction. Pair this with the
 * "production lockdown" rules (see firestore.rules) that deny the client direct writes
 * to points/checkedInEventIDs/redeemedRewardIDs.
 *
 * Deploy:  cd functions && npm i && npm run deploy
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";

initializeApp();
const db = getFirestore();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// ── Attendance-evidence helpers ─────────────────────────────────────────────

/** Great-circle distance in meters (haversine). */
function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/** Parse + range-check a coordinate component; NaN → undefined. */
function parseCoord(v: unknown, max: number): number | undefined {
  const n = Number(v);
  if (!Number.isFinite(n) || Math.abs(n) > max) return undefined;
  return n;
}

// Client gate is 500 ft (~152 m); the server allows generous GPS slop on top —
// anything beyond this is not "at the event".
const MAX_CHECKIN_DISTANCE_M = 1500;

// The proof-photo bucket, stated explicitly.
//
// `getStorage().bucket()` resolves its default from ambient project metadata,
// which differs by environment: it gave `<project>.firebasestorage.app` locally
// but `<project>.appspot.com` in CI. That mismatch meant proofs were uploaded to
// one bucket and looked for in another, so every check-in failed with "proof not
// found". Pinning it here (overridable for tests) keeps dev, CI and production
// pointed at the same place — and it matches STORAGE_BUCKET in
// GoogleService-Info.plist, which is what the iOS app uploads to.
const PROOF_BUCKET =
  process.env.STORAGE_BUCKET || "connectify-19dd8.firebasestorage.app";

// Server-trusted ceilings so a spoofed client can't claim absurd point values.
// Keep in sync with EventCategory.defaultPoints in the app.
const CATEGORY_MAX_POINTS: Record<string, number> = {
  Cleanup: 200, Sports: 150, Social: 100, Workshop: 150, Market: 75,
  Festival: 250, Hackathon: 200, Meetup: 100, Volunteer: 200,
};

// Reward catalog (server-trusted). Mirror RewardsStore / SampleData rewards.
// ── Verdure+ entitlement (server-verified only) ─────────────────────────────
//
// SECURITY: a client's claim that it is subscribed is NEVER trusted for
// server-side value. The only source of truth is `users/{uid}.plusExpiresAt`,
// which Firestore rules deny to clients — it can be written exclusively by the
// Admin SDK. Until the App Store Server API / Server Notifications handler
// lands and starts writing it, this returns false for everyone, so the
// benefits below are correct-but-inert rather than exploitable.
async function hasActivePlus(uid: string): Promise<boolean> {
  const snap = await db.collection("users").doc(uid).get();
  const expiresAt = snap.data()?.plusExpiresAt;
  if (!expiresAt) return false;
  const ms = typeof expiresAt?.toMillis === "function"
    ? expiresAt.toMillis()
    : Number(expiresAt);
  return Number.isFinite(ms) && ms > Date.now();
}

/** Verdure+ earn multiplier. 1.0 for everyone until entitlements are verified. */
const PLUS_POINT_MULTIPLIER = 1.25;

async function earnMultiplier(uid: string): Promise<number> {
  return (await hasActivePlus(uid)) ? PLUS_POINT_MULTIPLIER : 1.0;
}

// ── Reward catalog ──────────────────────────────────────────────────────────
//
// Costs plus optional limited-time windows. `plusEarlyAccessDays` lets verified
// Verdure+ members redeem before the public opening; the window itself is
// enforced here so a patched client cannot redeem a closed drop.

interface RewardRule {
  cost: number;
  /** ISO date the drop opens to everyone. */
  availableFrom?: string;
  /** ISO date the drop closes for everyone. */
  availableUntil?: string;
  /** Days of Verdure+ head start before `availableFrom`. */
  plusEarlyAccessDays?: number;
}

/** Start of the current month, matching the client's SampleData anchor. */
function monthAnchor(days: number): string {
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

const LIMITED_TIME_REWARDS: Record<string, RewardRule> = {
  "rei-15-trail-season": {
    cost: 4000,
    availableFrom: monthAnchor(0),
    availableUntil: monthAnchor(28),
  },
  "patagonia-30-earth": {
    cost: 9000,
    availableFrom: monthAnchor(18),
    availableUntil: monthAnchor(40),
    plusEarlyAccessDays: 7,
  },
};

const REWARD_COSTS: Record<string, number> = {
  // Bronze (1000 pts)
  "starbucks-5": 1000,
  "dunkin-5": 1000,
  // Silver (2500 pts)
  "amazon-10": 2500,
  "target-10": 2500,
  "chipotle-10": 2500,
  // Gold (7500 pts)
  "amazon-25": 7500,
  "nike-25": 7500,
  // Platinum (20000 pts)
  "apple-50": 20000,
  "rei-50": 20000,
};

/**
 * checkInToEvent — record an attendance and award points, server-side & idempotent.
 * Community events (in /events) are validated against their stored pointValue;
 * external events are clamped to the category ceiling. Double check-ins are no-ops.
 *
 * ATTENDANCE EVIDENCE (required):
 *  - proofPath: a Storage object under proofs/{uid}/ (the caller's own folder —
 *    storage.rules make it owner-writable). Existence is verified best-effort.
 *  - lat/lng: the user's GPS fix. If the event doc stores venue coordinates, the
 *    fix must be within MAX_CHECKIN_DISTANCE_M; otherwise the fix is recorded in
 *    /attendance for manual spot-checking.
 */
export const checkInToEvent = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to check in.");

  const eventId = String(req.data?.eventId ?? "").slice(0, 200);
  const category = String(req.data?.category ?? "Social");
  const claimed = Math.max(0, Math.floor(Number(req.data?.claimedPoints ?? 0)));
  if (!eventId) throw new HttpsError("invalid-argument", "Missing eventId.");

  // ── Evidence: proof photo reference ──
  const proofPath = String(req.data?.proofPath ?? "");
  if (!proofPath.startsWith(`proofs/${uid}/`) || proofPath.includes("..")) {
    throw new HttpsError("invalid-argument", "A proof-of-attendance photo is required to check in.");
  }
  // Best-effort existence check: hard-fail only on a definitive "not there".
  // (Storage being unreachable/misconfigured shouldn't block honest check-ins.)
  try {
    const bucket = getStorage().bucket(PROOF_BUCKET);
    const [exists] = await bucket.file(proofPath).exists();
    if (!exists) {
      console.warn(`[checkIn] proof missing: bucket=${bucket.name} path=${proofPath}`);
      throw new HttpsError("invalid-argument", "Proof photo was not found — upload it first.");
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.warn(`[checkIn] proof existence check unavailable for ${proofPath}:`, e);
  }

  // ── Evidence: GPS fix ──
  const lat = parseCoord(req.data?.lat, 90);
  const lng = parseCoord(req.data?.lng, 180);
  if (lat === undefined || lng === undefined) {
    throw new HttpsError("invalid-argument", "Your location is required to check in.");
  }

  // Determine the authoritative point value + venue coordinate (if stored).
  // The claim is clamped to the category ceiling BEFORE any multiplier, so a
  // Verdure+ bonus can never be used to smuggle an inflated base award through.
  let award = Math.min(claimed, CATEGORY_MAX_POINTS[category] ?? 100);
  let distanceM: number | null = null;
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (eventSnap.exists) {
    const ev = eventSnap.data() ?? {};
    const pv = Number(ev.pointValue ?? award);
    award = Math.min(pv, 1000); // community events: trust the stored value (rule-validated ≤1000)

    const evLat = parseCoord(ev.latitude, 90);
    const evLng = parseCoord(ev.longitude, 180);
    if (evLat !== undefined && evLng !== undefined) {
      distanceM = distanceMeters(lat, lng, evLat, evLng);
      if (distanceM > MAX_CHECKIN_DISTANCE_M) {
        throw new HttpsError(
          "failed-precondition",
          `Too far from the event to check in (${Math.round(distanceM)} m away).`
        );
      }
    }
  }

  // Verdure+ earn bonus, applied AFTER the ceiling clamp above.
  const multiplier = await earnMultiplier(uid);
  const baseAward = award;
  award = Math.floor(award * multiplier);

  // Audit trail for manual spot-checks (server-only collection — no client rules).
  const attendanceId = `${uid}_${eventId}`.replace(/[\/#?%]/g, "-").slice(0, 900);
  await db.collection("attendance").doc(attendanceId).set({
    uid, eventId, proofPath, lat, lng,
    distanceM: distanceM === null ? null : Math.round(distanceM),
    category, claimedPoints: claimed,
    baseAward, multiplier, award,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const userRef = db.collection("users").doc(uid);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};
    const checkedIn: string[] = data.checkedInEventIDs ?? [];
    const balance = Number(data.pointsBalance) || 0;
    const lifetime = Number(data.lifetimePoints) || 0;
    if (checkedIn.includes(eventId)) {
      return { alreadyCheckedIn: true, awarded: 0, newBalance: balance, newLifetime: lifetime };
    }

    tx.set(userRef, {
      checkedInEventIDs: FieldValue.arrayUnion(eventId),
      pointsBalance: balance + award,
      lifetimePoints: lifetime + award,
      lastUpdated: FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
      alreadyCheckedIn: false, awarded: award,
      newBalance: balance + award, newLifetime: lifetime + award,
    };
  });

  return result;
});

/**
 * collectPlace — record a place collection and award its (small) points, server-side
 * & idempotent. Place points are capped at the Legendary ceiling (50 — see
 * PlaceRarity.pointValue in the app), so a spoofed client can't inflate them.
 */
const PLACE_MAX_POINTS = 50;

export const collectPlace = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to collect.");

  const placeId = String(req.data?.placeId ?? "").slice(0, 200);
  const claimed = Math.max(0, Math.floor(Number(req.data?.claimedPoints ?? 0)));
  if (!placeId) throw new HttpsError("invalid-argument", "Missing placeId.");
  const award = Math.min(claimed, PLACE_MAX_POINTS);

  // Record the GPS fix (when provided) for spot-checking — places have no
  // server-side registry to hard-validate against, so this is evidence, not a gate.
  const lat = parseCoord(req.data?.lat, 90);
  const lng = parseCoord(req.data?.lng, 180);
  if (lat !== undefined && lng !== undefined) {
    const collectionId = `${uid}_${placeId}`.replace(/[\/#?%]/g, "-").slice(0, 900);
    await db.collection("attendance").doc(collectionId).set({
      uid, placeId, lat, lng, kind: "collect",
      claimedPoints: claimed,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  const userRef = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};
    const collected: string[] = data.collectedPlaceIDs ?? [];
    const balance = Number(data.pointsBalance) || 0;
    const lifetime = Number(data.lifetimePoints) || 0;
    if (collected.includes(placeId)) {
      return { alreadyCollected: true, awarded: 0, newBalance: balance, newLifetime: lifetime };
    }

    tx.set(userRef, {
      collectedPlaceIDs: FieldValue.arrayUnion(placeId),
      pointsBalance: balance + award,
      lifetimePoints: lifetime + award,
      lastUpdated: FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
      alreadyCollected: false, awarded: award,
      newBalance: balance + award, newLifetime: lifetime + award,
    };
  });
});

/**
 * redeemReward — deduct points and mark a reward redeemed, server-side & idempotent.
 */
export const redeemReward = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to redeem.");

  const rewardId = String(req.data?.rewardId ?? "").slice(0, 100);
  const limited = LIMITED_TIME_REWARDS[rewardId];
  const cost = limited?.cost ?? REWARD_COSTS[rewardId];
  if (!rewardId || cost === undefined) {
    throw new HttpsError("invalid-argument", "Unknown reward.");
  }

  // Limited-time drops: enforce the window server-side so a patched client
  // can't redeem before it opens or after it closes.
  if (limited) {
    const now = Date.now();
    if (limited.availableUntil && now >= Date.parse(limited.availableUntil)) {
      throw new HttpsError("failed-precondition", "This reward is no longer available.");
    }
    if (limited.availableFrom) {
      const publicFrom = Date.parse(limited.availableFrom);
      const earlyMs = (limited.plusEarlyAccessDays ?? 0) * 86_400_000;
      const plusFrom = publicFrom - earlyMs;
      if (now < plusFrom) {
        throw new HttpsError("failed-precondition", "This reward isn't available yet.");
      }
      // Inside the early window → Verdure+ members only (server-verified).
      if (now < publicFrom && !(await hasActivePlus(uid))) {
        throw new HttpsError("permission-denied", "Verdure+ early access — opens to everyone soon.");
      }
    }
  }

  const userRef = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};
    const redeemed: string[] = data.redeemedRewardIDs ?? [];
    const balance = Number(data.pointsBalance) || 0;

    if (redeemed.includes(rewardId)) throw new HttpsError("already-exists", "Already redeemed.");
    if (balance < cost) throw new HttpsError("failed-precondition", "Not enough points.");

    tx.set(userRef, {
      redeemedRewardIDs: FieldValue.arrayUnion(rewardId),
      pointsBalance: balance - cost,
      lastUpdated: FieldValue.serverTimestamp(),
    }, { merge: true });

    // FULFILMENT QUEUE.
    //
    // The gift-card vendor (Tango/Tremendous) isn't wired up yet, and a
    // redemption that only debits points would take value and give nothing
    // back. So the debit and a durable fulfilment request are written in the
    // SAME transaction: every redemption is recoverable and nothing can be
    // silently lost, whether it's fulfilled by an API call later or by hand.
    //
    // Deterministic id => the queue is idempotent even if this ever re-runs.
    const fulfilmentRef = db.collection("fulfillments")
      .doc(`${uid}_${rewardId}`.replace(/[\/#?%]/g, "-").slice(0, 900));
    tx.set(fulfilmentRef, {
      uid,
      rewardId,
      pointsSpent: cost,
      status: "pending",          // pending → sent | failed (set by the fulfiller)
      requestedAt: FieldValue.serverTimestamp(),
      deliverToEmail: req.auth?.token?.email ?? null,
      vendor: null,               // filled in when a provider is integrated
      vendorOrderId: null,
    }, { merge: true });

    return { redeemed: true, remaining: balance - cost };
  });
});

/**
 * onPostCreated — fan-out a push notification when a community post is created.
 * Requires FCM tokens stored at users/{uid}.fcmTokens (set from the iOS client).
 *
 * Skipped under the Local Emulator Suite: the Firestore emulator rejects v2
 * eventarc trigger registration (tools/jar version skew) and this trigger isn't
 * part of the E2E surface — only the callables are.
 */
const inEmulator = process.env.FUNCTIONS_EMULATOR === "true";

export const onPostCreated: unknown = inEmulator ? undefined
  : onDocumentCreated("posts/{postId}", async (event) => {
  const post = event.data?.data();
  if (!post) return;
  // Collect a handful of recent tokens (a real app would target by proximity/follows).
  const usersSnap = await db.collection("users").limit(200).get();
  const tokens: string[] = [];
  usersSnap.forEach((d) => {
    const t = d.data().fcmTokens;
    if (Array.isArray(t)) tokens.push(...t);
  });
  if (tokens.length === 0) return;

  await getMessaging().sendEachForMulticast({
    tokens: tokens.slice(0, 500),
    notification: {
      title: `${post.authorName ?? "Someone"} posted in the community`,
      body: String(post.content ?? "").slice(0, 120),
    },
  });
});

/**
 * sendEventReminders — daily scheduled reminder fan-out (placeholder).
 * Hook up to saved events + FCM tokens to remind attendees the day before.
 */
export const sendEventReminders = onSchedule("every day 09:00", async () => {
  // Query events happening tomorrow, find users who saved them, send FCM. (Stub.)
  return;
});
