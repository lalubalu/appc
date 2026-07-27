// Verdure backend E2E — runs against the Firebase Local Emulator Suite.
//
//   npx firebase-tools emulators:exec --only auth,functions,firestore,storage \
//       "node functions/scripts/e2e-backend.mjs"
//
// Proves the ENTIRE server loop before any real deploy: auth → proof upload
// (storage.rules) → checkInToEvent (proof + GPS validation, clamps, idempotency)
// → collectPlace → redeemReward (insufficient / success / double) → and the
// Firestore rules lockdown (client cannot write points; CAN write its own fields).
//
// Transport note: the emulator's HTTP/1.1 REST gateway hangs on this machine
// (Netty h2-detection routes h1 connections into limbo), so ALL Firestore
// traffic here goes over gRPC — firebase-admin for seeding (rules-bypassed)
// and the client JS SDK's Node build for rules-checked user writes. Auth,
// Functions (callables), and Storage speak plain HTTP, which works fine.

import http from "node:http";
import { initializeApp as adminInit } from "firebase-admin/app";
import { getFirestore as adminFirestore } from "firebase-admin/firestore";
import { initializeApp as clientInit } from "firebase/app";
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword } from "firebase/auth";
import {
  getFirestore as clientFirestore, connectFirestoreEmulator,
  doc, setDoc, updateDoc, increment, serverTimestamp, collection, query, getDocs,
} from "firebase/firestore";

const PROJECT = "connectify-19dd8";
const REGION = "us-central1";
const AUTH = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1`;
const FN = `http://127.0.0.1:5001/${PROJECT}/${REGION}`;
const BUCKET = `${PROJECT}.firebasestorage.app`;   // matches the functions runtime default
const STORAGE = `http://127.0.0.1:9199/v0/b/${BUCKET}/o`;

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8899";

// ── admin (gRPC, bypasses rules — for seeding + audit reads) ────────────────
adminInit({ projectId: PROJECT });
const db = adminFirestore();

// ── client SDK (gRPC, rules-checked — for lockdown tests) ───────────────────
const capp = clientInit({ projectId: PROJECT, apiKey: "fake-api-key" });
const cauth = getAuth(capp);
connectAuthEmulator(cauth, "http://127.0.0.1:9099", { disableWarnings: true });
const cdb = clientFirestore(capp);
connectFirestoreEmulator(cdb, "127.0.0.1", 8899);

let passed = 0, failed = 0;
function ok(name, cond, extra = "") {
  if (cond) { passed++; console.log(`  ✅ ${name}`); }
  else { failed++; console.error(`  ❌ ${name} ${extra}`); }
}

// ── plain-HTTP helper (auth REST, callables, storage) ───────────────────────

function req(url, { method = "GET", headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const data = body == null ? null : (Buffer.isBuffer(body) ? body : Buffer.from(body));
    const u = new URL(url);
    const r = http.request({
      hostname: u.hostname, port: u.port, path: u.pathname + u.search, method,
      headers: { ...(data ? { "Content-Length": data.length } : {}), ...headers },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let json = null;
        try { json = JSON.parse(text); } catch {}
        resolve({ status: res.statusCode, text, json });
      });
    });
    r.on("error", reject);
    r.setTimeout(30000, () => r.destroy(new Error(`timeout: ${method} ${url}`)));
    if (data) r.write(data);
    r.end();
  });
}

async function signUp(email, password) {
  const r = await req(`${AUTH}/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (!r.json?.idToken) throw new Error(`signUp failed: ${r.text}`);
  return { idToken: r.json.idToken, uid: r.json.localId };
}

async function call(name, data, idToken) {
  const r = await req(`${FN}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return r.json ?? { error: { status: "BAD_RESPONSE", message: r.text } };
}

async function uploadProofDebug(path, idToken) {
  // Multipart upload (what the SDK sends): metadata part carries contentType so
  // storage.rules' `contentType.matches('image/.*')` sees it.
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0, 1, 0xff, 0xd9]);
  const boundary = "e2e-boundary-7f3a";
  const meta = JSON.stringify({ name: path, contentType: "image/jpeg" });
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n${meta}\r\n`),
    Buffer.from(`--${boundary}\r\nContent-Type: image/jpeg\r\n\r\n`),
    jpeg,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  for (const prefix of ["Firebase", "Bearer"]) {
    const r = await req(`${STORAGE}?uploadType=multipart&name=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: {
        "Content-Type": `multipart/related; boundary=${boundary}`,
        "X-Goog-Upload-Protocol": "multipart",
        Authorization: `${prefix} ${idToken}`,
      },
      body,
    });
    if (r.status === 200) return { ...r, prefix };
    if (prefix === "Bearer") return r;
  }
}

async function uploadProof(path, idToken) {
  return (await uploadProofDebug(path, idToken)).status;
}

/** Rules-checked user write via the client SDK; returns the error code or "ok". */
async function userWrite(path, fields) {
  try {
    await updateDoc(doc(cdb, path), fields);
    return "ok";
  } catch (e) {
    return e.code ?? String(e);
  }
}

// Venue at (44.98, -93.26); NEAR is a few hundred meters away, FAR ~10 km.
const NEAR = { lat: 44.9812, lng: -93.2612 };
const FAR = { lat: 45.07, lng: -93.26 };

// ── the suite ───────────────────────────────────────────────────────────────

async function main() {
  console.log("── Verdure backend E2E (emulators) ──");
  const email = `e2e-${Date.now()}@verdure.test`;
  const password = "test-password-1";
  const { idToken, uid } = await signUp(email, password);
  await signInWithEmailAndPassword(cauth, email, password);   // client SDK user context
  console.log(`  user: ${uid}`);

  // Seed two community events (admin gRPC) with venue coordinates.
  const event = (title) => ({
    title, organizer: "E2E", date: new Date("2026-08-01T17:00:00Z"),
    time: "12:00 PM", locationName: "E2E Venue", attendeeCount: 1,
    category: "Volunteer", imagePlaceholder: "heart.fill", pointValue: 200,
    creatorID: "seed-admin", createdAt: new Date(),
    latitude: 44.98, longitude: -93.26,
  });
  await db.doc("events/e2e-event-1").set(event("E2E Cleanup One"));
  await db.doc("events/e2e-event-2").set(event("E2E Cleanup Two"));

  // Storage rules: owner path accepted, foreign path rejected.
  const own = await uploadProofDebug(`proofs/${uid}/p1.jpg`, idToken);
  ok("storage: owner can upload proof", own.status === 200, `got ${own.status}: ${own.text?.slice(0, 200)}`);
  ok("storage: foreign-path upload rejected", (await uploadProof("proofs/someone-else/p.jpg", idToken)) === 403);

  const proofPath = `proofs/${uid}/p1.jpg`;

  // T1 — no proof → rejected
  let r = await call("checkInToEvent", { eventId: "e2e-event-1", category: "Volunteer", claimedPoints: 200, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("checkIn without proof rejected", r.error?.status === "INVALID_ARGUMENT", JSON.stringify(r));

  // T2 — no coords → rejected
  r = await call("checkInToEvent", { eventId: "e2e-event-1", category: "Volunteer", claimedPoints: 200, proofPath }, idToken);
  ok("checkIn without coords rejected", r.error?.status === "INVALID_ARGUMENT", JSON.stringify(r));

  // T3 — foreign proof path → rejected
  r = await call("checkInToEvent", { eventId: "e2e-event-1", category: "Volunteer", claimedPoints: 200, proofPath: "proofs/not-you/x.jpg", lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("checkIn with foreign proofPath rejected", r.error?.status === "INVALID_ARGUMENT", JSON.stringify(r));

  // T4 — valid check-in near the venue → stored pointValue
  r = await call("checkInToEvent", { eventId: "e2e-event-1", category: "Volunteer", claimedPoints: 200, proofPath, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("checkIn near venue awards stored pointValue", r.result?.awarded === 200 && r.result?.newBalance === 200, JSON.stringify(r));

  // T5 — duplicate check-in → idempotent no-op
  r = await call("checkInToEvent", { eventId: "e2e-event-1", category: "Volunteer", claimedPoints: 200, proofPath, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("duplicate checkIn is a no-op", r.result?.alreadyCheckedIn === true && r.result?.awarded === 0, JSON.stringify(r));

  // T6 — too far from a coordinated event → rejected
  r = await call("checkInToEvent", { eventId: "e2e-event-2", category: "Volunteer", claimedPoints: 200, proofPath, lat: FAR.lat, lng: FAR.lng }, idToken);
  ok("checkIn too far rejected (haversine)", r.error?.status === "FAILED_PRECONDITION", JSON.stringify(r));

  // T7 — external event (no doc): claims clamp to the category ceiling
  r = await call("checkInToEvent", { eventId: "serp-e2e-external-1", category: "Festival", claimedPoints: 99999, proofPath, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("external checkIn clamped to category ceiling (250)", r.result?.awarded === 250 && r.result?.newBalance === 450, JSON.stringify(r));

  // T8 — attendance audit doc written with evidence
  const audit = (await db.doc(`attendance/${uid}_e2e-event-1`).get()).data();
  ok("attendance audit doc has proof + GPS", !!audit?.proofPath && typeof audit?.lat === "number", JSON.stringify(audit ?? {}));

  // T9 — RULES LOCKDOWN (client SDK over gRPC, rules-checked)
  let code = await userWrite(`users/${uid}`, { pointsBalance: 999999 });
  ok("rules: client write to pointsBalance DENIED", code === "permission-denied", `got ${code}`);
  code = await userWrite(`users/${uid}`, { checkedInEventIDs: ["cheat"] });
  ok("rules: client write to checkedInEventIDs DENIED", code === "permission-denied", `got ${code}`);
  code = await userWrite(`users/${uid}`, { redeemedRewardIDs: ["free-stuff"] });
  ok("rules: client write to redeemedRewardIDs DENIED", code === "permission-denied", `got ${code}`);
  code = await userWrite(`users/${uid}`, { collectedPlaceIDs: ["osm-123"] });
  ok("rules: client write to collectedPlaceIDs allowed", code === "ok", `got ${code}`);

  // T10 — collectPlace clamps to rarity ceiling + idempotent
  r = await call("collectPlace", { placeId: "osm-999", claimedPoints: 5000, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  ok("collectPlace clamped to 50", r.result?.awarded === 50 && r.result?.newBalance === 500, JSON.stringify(r));
  r = await call("collectPlace", { placeId: "osm-999", claimedPoints: 50 }, idToken);
  ok("duplicate collect is a no-op", r.result?.alreadyCollected === true, JSON.stringify(r));

  // T11 — redeem with insufficient points → rejected (balance 500 < 1000)
  r = await call("redeemReward", { rewardId: "starbucks-5" }, idToken);
  ok("redeem with insufficient points rejected", r.error?.status === "FAILED_PRECONDITION", JSON.stringify(r));

  // Earn to 1000 via two more external check-ins (Festival ceiling 250 × 2).
  await call("checkInToEvent", { eventId: "serp-e2e-external-2", category: "Festival", claimedPoints: 250, proofPath, lat: NEAR.lat, lng: NEAR.lng }, idToken);
  await call("checkInToEvent", { eventId: "serp-e2e-external-3", category: "Festival", claimedPoints: 250, proofPath, lat: NEAR.lat, lng: NEAR.lng }, idToken);

  // T12 — redeem success
  r = await call("redeemReward", { rewardId: "starbucks-5" }, idToken);
  ok("redeem succeeds and returns remaining", r.result?.redeemed === true && r.result?.remaining === 0, JSON.stringify(r));

  // T13 — double redeem → rejected
  r = await call("redeemReward", { rewardId: "starbucks-5" }, idToken);
  ok("double redeem rejected", r.error?.status === "ALREADY_EXISTS", JSON.stringify(r));

  // T14 — unknown reward → rejected
  r = await call("redeemReward", { rewardId: "free-yacht" }, idToken);
  ok("unknown reward rejected", r.error?.status === "INVALID_ARGUMENT", JSON.stringify(r));

  // T15 — unauthenticated call → rejected
  r = await call("checkInToEvent", { eventId: "x", category: "Social", claimedPoints: 1 }, null);
  ok("unauthenticated checkIn rejected", r.error?.status === "UNAUTHENTICATED", JSON.stringify(r));

  // T16 — community-post likes: exactly +1 on likeCount is the only allowed edit
  let code2;
  try {
    await setDoc(doc(cdb, "posts/e2e-post-1"), {
      authorID: uid, authorName: "E2E User", authorInitials: "EU",
      placeName: "E2E Venue", content: "hello neighborhood",
      likeCount: 0, createdAt: serverTimestamp(),
    });
    code2 = "ok";
  } catch (e) { code2 = e.code ?? String(e); }
  ok("rules: author can create a post", code2 === "ok", `got ${code2}`);

  code2 = await userWrite("posts/e2e-post-1", { likeCount: increment(1) });
  ok("rules: like (+1) allowed", code2 === "ok", `got ${code2}`);
  code2 = await userWrite("posts/e2e-post-1", { likeCount: increment(5) });
  ok("rules: like (+5) denied", code2 === "permission-denied", `got ${code2}`);
  code2 = await userWrite("posts/e2e-post-1", { content: "vandalized" });
  ok("rules: editing post content denied", code2 === "permission-denied", `got ${code2}`);

  // ── Verdure+ entitlement & limited-time drops ────────────────────────────
  //
  // The entitlement (`users/{uid}.plusExpiresAt`) must be UNWRITABLE by clients:
  // it gates the earn multiplier and early reward access.
  code2 = await userWrite(`users/${uid}`, { plusExpiresAt: Date.now() + 86_400_000 });
  ok("rules: client CANNOT grant itself Verdure+ (plusExpiresAt denied)",
     code2 === "permission-denied", `got ${code2}`);

  // "patagonia-30-earth" opens publicly on day 18 of the month with 7 days of
  // Plus early access (day 11). Behaviour depends on today's date, so assert the
  // branch that actually applies rather than pretending the clock is fixed.
  const dayOfMonth = new Date().getUTCDate();
  r = await call("redeemReward", { rewardId: "patagonia-30-earth" }, idToken);
  const err = r.error?.status;
  if (dayOfMonth < 11) {
    ok("limited drop before early window rejected", err === "FAILED_PRECONDITION", JSON.stringify(r));
  } else if (dayOfMonth < 18) {
    // Inside the Plus-only window and this user has no verified entitlement.
    ok("limited drop in early window denied to non-Plus", err === "PERMISSION_DENIED", JSON.stringify(r));
  } else {
    // Publicly open — so it should fail on points, not availability.
    ok("limited drop publicly open (fails on points, not window)",
       err === "FAILED_PRECONDITION" && /enough points/i.test(r.error?.message ?? ""), JSON.stringify(r));
  }

  // Grant a verified entitlement the only legitimate way (Admin SDK = what the
  // App Store notification handler will do) and confirm early access opens up.
  await db.doc(`users/${uid}`).set(
    { plusExpiresAt: new Date(Date.now() + 86_400_000) }, { merge: true });
  await db.doc(`users/${uid}`).set({ pointsBalance: 12000 }, { merge: true });
  r = await call("redeemReward", { rewardId: "patagonia-30-earth" }, idToken);
  if (dayOfMonth < 11) {
    ok("verified Plus still cannot redeem before the early window",
       r.error?.status === "FAILED_PRECONDITION", JSON.stringify(r));
  } else {
    ok("verified Plus redeems limited drop (early access honoured)",
       r.result?.redeemed === true, JSON.stringify(r));
  }

  // The Verdure+ earn multiplier: base award is clamped to the category ceiling
  // FIRST (Festival = 250), then multiplied — so 250 → floor(250 × 1.25) = 312.
  // This user now has a verified entitlement from the step above.
  r = await call("checkInToEvent", {
    eventId: "serp-e2e-plus-multiplier", category: "Festival",
    claimedPoints: 99999, proofPath, lat: NEAR.lat, lng: NEAR.lng,
  }, idToken);
  ok("verified Plus earns the 1.25× multiplier (ceiling clamped first)",
     r.result?.awarded === 312, JSON.stringify(r));

  // And a fresh user WITHOUT the entitlement still earns the base rate — proving
  // the multiplier is gated on the server-verified field, not on any client claim.
  const plain = await signUp(`e2e-plain-${Date.now()}@verdure.test`, password);
  await uploadProof(`proofs/${plain.uid}/p1.jpg`, plain.idToken);
  r = await call("checkInToEvent", {
    eventId: "serp-e2e-plain", category: "Festival", claimedPoints: 99999,
    proofPath: `proofs/${plain.uid}/p1.jpg`, lat: NEAR.lat, lng: NEAR.lng,
  }, plain.idToken);
  ok("non-Plus user earns the base rate (no multiplier)",
     r.result?.awarded === 250, JSON.stringify(r));

  // ── Redemption fulfilment + server-only collection privacy ───────────────
  //
  // A redemption must never just debit points: it has to leave a durable,
  // recoverable order behind (the vendor integration isn't live yet).
  const ff = (await db.doc(`fulfillments/${uid}_starbucks-5`).get()).data();
  ok("redemption writes a durable fulfilment record",
     ff?.status === "pending" && ff?.rewardId === "starbucks-5" && ff?.pointsSpent === 1000,
     JSON.stringify(ff ?? {}));

  // Those records hold a delivery email + spend, and /attendance holds GPS —
  // clients must not be able to read either.
  try {
    await getDocs(query(collection(cdb, "fulfillments")));
    ok("rules: client CANNOT read /fulfillments (PII)", false, "read succeeded!");
  } catch (e) {
    ok("rules: client CANNOT read /fulfillments (PII)", e.code === "permission-denied", `got ${e.code}`);
  }
  try {
    await getDocs(query(collection(cdb, "attendance")));
    ok("rules: client CANNOT read /attendance (GPS)", false, "read succeeded!");
  } catch (e) {
    ok("rules: client CANNOT read /attendance (GPS)", e.code === "permission-denied", `got ${e.code}`);
  }

  console.log(`\n══ ${passed} passed, ${failed} failed ══`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => { console.error("E2E crashed:", e); process.exit(1); });
