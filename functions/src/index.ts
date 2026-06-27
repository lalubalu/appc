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

initializeApp();
const db = getFirestore();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Server-trusted ceilings so a spoofed client can't claim absurd point values.
// Keep in sync with EventCategory.defaultPoints in the app.
const CATEGORY_MAX_POINTS: Record<string, number> = {
  Cleanup: 200, Sports: 150, Social: 100, Workshop: 150, Market: 75,
  Festival: 250, Hackathon: 200, Meetup: 100, Volunteer: 200,
};

// Reward catalog (server-trusted). Mirror RewardsStore / SampleData rewards.
const REWARD_COSTS: Record<string, number> = {
  // "<rewardId>": <pointCost>  — fill from your real rewards list
};

/**
 * checkInToEvent — record an attendance and award points, server-side & idempotent.
 * Community events (in /events) are validated against their stored pointValue;
 * external events are clamped to the category ceiling. Double check-ins are no-ops.
 */
export const checkInToEvent = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to check in.");

  const eventId = String(req.data?.eventId ?? "").slice(0, 200);
  const category = String(req.data?.category ?? "Social");
  const claimed = Math.max(0, Math.floor(Number(req.data?.claimedPoints ?? 0)));
  if (!eventId) throw new HttpsError("invalid-argument", "Missing eventId.");

  // Determine the authoritative point value.
  let award = Math.min(claimed, CATEGORY_MAX_POINTS[category] ?? 100);
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (eventSnap.exists) {
    const pv = Number(eventSnap.data()?.pointValue ?? award);
    award = Math.min(pv, 1000); // community events: trust the stored value (rule-validated ≤1000)
  }

  const userRef = db.collection("users").doc(uid);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};
    const checkedIn: string[] = data.checkedInEventIDs ?? [];
    if (checkedIn.includes(eventId)) return { alreadyCheckedIn: true, awarded: 0 };

    tx.set(userRef, {
      checkedInEventIDs: FieldValue.arrayUnion(eventId),
      pointsBalance: (Number(data.pointsBalance) || 0) + award,
      lifetimePoints: (Number(data.lifetimePoints) || 0) + award,
      lastUpdated: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { alreadyCheckedIn: false, awarded: award };
  });

  return result;
});

/**
 * redeemReward — deduct points and mark a reward redeemed, server-side & idempotent.
 */
export const redeemReward = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to redeem.");

  const rewardId = String(req.data?.rewardId ?? "").slice(0, 100);
  const cost = REWARD_COSTS[rewardId];
  if (!rewardId || cost === undefined) {
    throw new HttpsError("invalid-argument", "Unknown reward.");
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

    // TODO: trigger real gift-card fulfilment here (Tango/Tremendous API call).
    return { redeemed: true, remaining: balance - cost };
  });
});

/**
 * onPostCreated — fan-out a push notification when a community post is created.
 * Requires FCM tokens stored at users/{uid}.fcmTokens (set from the iOS client).
 */
export const onPostCreated = onDocumentCreated("posts/{postId}", async (event) => {
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
