/**
 * Organizer accounts — our own event supply (Part 2 §5).
 *
 * The clubs, libraries, rec leagues and community orgs post their own events.
 * That data exists in no external index and cannot be replicated by anyone
 * renting the same feeds — it is the one source that improves as we grow.
 *
 * THE GUARD. Interviewees named the failure directly: low-quality self-promoted
 * events crowding the feed. So an organizer may CREATE the moment they sign
 * up, but may not BROADCAST until a human approves them. Unverified organizers'
 * events are visible only to the organizer and to people who chose to follow
 * them; approval flips `broadcast: true` on everything they have published.
 * The first MAX_MANUALLY_APPROVED organizers are reviewed by hand — less code
 * than automated verification, and at this stage we want to look at each one.
 * Approval state lives on the server and is enforced by the rules; nothing a
 * client sends can change it.
 *
 * Verification exempts nothing: organizer events and profiles go through the
 * same report / block / moderateContent paths as any other content.
 *
 * SHAPE. The organizer record is designed so a future merchant account is the
 * same type with `billing` filled in — do not build merchant billing yet.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  db, requireUid, requireAdmin, enforceRateLimit, assertNotSuspended,
  safeString, safeText, parseCoord,
} from "./common.js";
import { LAUNCH_AREAS, isInsideArea } from "./ingest/areas.js";
import { CATEGORY_ICON, CATEGORY_POINTS, type EventCategory } from "./ingest/types.js";
import { titleKey, venueKey, startBucket, cleanUrl } from "./ingest/normalize.js";

/** The manual-review window. Approval beyond this needs a deliberate policy change. */
export const MAX_MANUALLY_APPROVED = 50;

export const ORGANIZER_CATEGORIES = [
  "nonprofit", "library", "parks", "rec-league", "community-org", "school", "faith", "arts", "business", "other",
] as const;

type OrganizerStatus = "pending" | "approved" | "rejected" | "suspended";

async function organizerOwnedBy(uid: string) {
  const snap = await db.collection("organizers").where("ownerUid", "==", uid).limit(1).get();
  return snap.empty ? null : snap.docs[0];
}

/**
 * createOrganizer — apply for an organizer profile. One per account. Starts
 * `pending`; the applicant can create events immediately but they stay
 * follower-only until approval.
 */
export const createOrganizer = onCall(async (req) => {
  const uid = requireUid(req.auth, "Sign in to become an organizer.");
  await enforceRateLimit(uid, "createOrganizer");
  await assertNotSuspended(uid);

  const displayName = safeText(req.data?.displayName, 80);
  const category = safeString(req.data?.category, "other");
  const description = safeText(req.data?.description, 600);
  const website = cleanUrl(req.data?.website) ?? null;
  if (displayName.length < 2) throw new HttpsError("invalid-argument", "Give your organization a name.");
  if (!(ORGANIZER_CATEGORIES as readonly string[]).includes(category)) throw new HttpsError("invalid-argument", "Unknown category.");

  const existing = await organizerOwnedBy(uid);
  if (existing) {
    return { organizerId: existing.id, status: existing.data().status, alreadyExists: true };
  }
  const ref = db.collection("organizers").doc();
  await ref.set({
    ownerUid: uid,
    displayName, category, description, website,
    status: "pending" as OrganizerStatus,
    kind: "organizer",           // a future merchant is the same record with `billing` set
    billing: null,
    followerCount: 0,
    eventCount: 0,
    hidden: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("users").doc(uid).set({ organizerId: ref.id }, { merge: true });
  return { organizerId: ref.id, status: "pending", alreadyExists: false };
});

/**
 * approveOrganizer — staff decision. `approve` flips broadcast on for every
 * event the organizer has published; `reject`/`suspend` flips it off.
 * The manual window is capped: the 51st approval is refused with an explicit
 * message rather than silently continuing a policy that was meant to end.
 */
export const approveOrganizer = onCall(async (req) => {
  const staff = await requireAdmin(req.auth);
  const organizerId = safeText(req.data?.organizerId, 128);
  const action = safeString(req.data?.action, "approve");
  if (!organizerId || organizerId.includes("/")) throw new HttpsError("invalid-argument", "Missing organizerId.");
  if (!["approve", "reject", "suspend", "reinstate"].includes(action)) throw new HttpsError("invalid-argument", "Unknown action.");

  const ref = db.collection("organizers").doc(organizerId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No such organizer.");

  const status: OrganizerStatus = action === "approve" || action === "reinstate" ? "approved"
    : action === "reject" ? "rejected" : "suspended";

  if (status === "approved" && snap.data()?.status !== "approved") {
    const approved = await db.collection("organizers").where("status", "==", "approved").count().get();
    if (approved.data().count >= MAX_MANUALLY_APPROVED) {
      throw new HttpsError("resource-exhausted",
        `The manual approval window (${MAX_MANUALLY_APPROVED} organizers) is full. Decide the next policy before approving more.`);
    }
  }

  const now = Timestamp.now();
  await ref.set({
    status, reviewedAt: now, reviewedBy: staff, updatedAt: now,
    ...(status === "approved" ? { approvedAt: now } : {}),
  }, { merge: true });

  // Approval state is enforced on every event the organizer owns.
  const events = await db.collection("events").where("organizerId", "==", organizerId).get();
  let flipped = 0;
  let batch = db.batch();
  for (const ev of events.docs) {
    batch.set(ev.ref, { broadcast: status === "approved" }, { merge: true });
    if (++flipped % 400 === 0) { await batch.commit(); batch = db.batch(); }
  }
  if (flipped % 400) await batch.commit();
  return { organizerId, status, eventsUpdated: events.size };
});

/** Staff view of pending applications. */
export const listOrganizerApplications = onCall(async (req) => {
  await requireAdmin(req.auth);
  const status = safeString(req.data?.status, "pending");
  const snap = await db.collection("organizers").where("status", "==", status).orderBy("createdAt", "asc").limit(100).get();
  return {
    organizers: snap.docs.map((d) => ({ id: d.id, ...pick(d.data(), ["ownerUid", "displayName", "category", "description", "website", "status", "eventCount", "followerCount"]) })),
  };
});

function pick(d: FirebaseFirestore.DocumentData, keys: string[]) {
  const out: Record<string, unknown> = {};
  for (const k of keys) if (k in d) out[k] = d[k];
  return out;
}

/**
 * createEvent — an organizer publishes an event. Broadcast follows the
 * organizer's approval state at the moment of publishing; approval later flips
 * it. Everything else about the document is set here, so a client can never
 * mint a broadcast event or forge provenance.
 */
export const createEvent = onCall(async (req) => {
  const uid = requireUid(req.auth, "Sign in to publish an event.");
  await enforceRateLimit(uid, "createEvent");
  await assertNotSuspended(uid);

  const org = await organizerOwnedBy(uid);
  if (!org) throw new HttpsError("failed-precondition", "Create an organizer profile first — it takes a minute.");
  const orgData = org.data();
  if (orgData.hidden === true || orgData.removed === true || orgData.status === "suspended" || orgData.status === "rejected") {
    throw new HttpsError("permission-denied", "This organizer account can't publish events right now.");
  }

  const title = safeText(req.data?.title, 120);
  const description = safeText(req.data?.description, 2000);
  const locationName = safeText(req.data?.locationName, 200);
  const time = safeText(req.data?.time, 50);
  const categoryRaw = safeString(req.data?.category, "Social");
  const category = (categoryRaw in CATEGORY_POINTS ? categoryRaw : "Social") as EventCategory;
  const startMs = Number(req.data?.startMs);
  const maxAttendeesRaw = Number(req.data?.maxAttendees);
  const maxAttendees = Number.isFinite(maxAttendeesRaw) && maxAttendeesRaw >= 1 ? Math.min(100000, Math.floor(maxAttendeesRaw)) : null;
  const lat = parseCoord(req.data?.latitude, 90);
  const lng = parseCoord(req.data?.longitude, 180);
  const website = cleanUrl(req.data?.website) ?? null;
  const isFree = req.data?.isFree !== false;
  const expectedSize = Number.isInteger(req.data?.expectedSize) && req.data.expectedSize >= 1 && req.data.expectedSize <= 100000
    ? req.data.expectedSize as number : null;
  const indoorOutdoor = ["indoor", "outdoor", "mixed", "unknown"].includes(req.data?.indoorOutdoor)
    ? req.data.indoorOutdoor as string : "unknown";
  const minimumAge = Number.isInteger(req.data?.minimumAge) && req.data.minimumAge >= 0 && req.data.minimumAge <= 100
    ? req.data.minimumAge as number : null;
  const maximumAge = Number.isInteger(req.data?.maximumAge) && req.data.maximumAge >= 0 && req.data.maximumAge <= 100
    ? req.data.maximumAge as number : null;
  if (minimumAge !== null && maximumAge !== null && minimumAge > maximumAge) {
    throw new HttpsError("invalid-argument", "Minimum age must not exceed maximum age.");
  }
  const ageSuitability = ["all", "children", "teens", "adults", "unknown"].includes(req.data?.ageSuitability)
    ? req.data.ageSuitability as string : "unknown";
  const allowedAccess = new Set(["stepFree", "accessibleRestroom", "seating", "quietSpace", "asl", "captions", "other"]);
  const accessibilityFeatures = Array.isArray(req.data?.accessibilityFeatures)
    ? Array.from(new Set((req.data.accessibilityFeatures as unknown[]).filter((x): x is string => typeof x === "string" && allowedAccess.has(x)))).slice(0, 8)
    : [];
  const publicVenue = req.data?.publicVenue === true;
  const recurring = req.data?.recurring === true;
  const virtual = req.data?.virtual === true;
  const opportunitySubtype = ["volunteer", "workshop", "program"].includes(req.data?.opportunitySubtype)
    ? req.data.opportunitySubtype as string : null;
  const deadlineMs = Number(req.data?.applicationDeadlineMs);
  const applicationDeadline = Number.isFinite(deadlineMs) && deadlineMs > Date.now() && deadlineMs <= startMs
    ? Timestamp.fromMillis(deadlineMs) : null;

  if (title.length < 3) throw new HttpsError("invalid-argument", "Give the event a title.");
  if (!locationName) throw new HttpsError("invalid-argument", "Where is it?");
  if (!Number.isFinite(startMs) || startMs < Date.now() - 3_600_000) throw new HttpsError("invalid-argument", "Pick a start time in the future.");
  if (startMs > Date.now() + 365 * 86_400_000) throw new HttpsError("invalid-argument", "Events can be published up to a year ahead.");

  const start = new Date(startMs);
  const area = (lat !== undefined && lng !== undefined)
    ? LAUNCH_AREAS.find((a) => isInsideArea(a, lat, lng)) ?? null
    : LAUNCH_AREAS[0] ?? null;
  const broadcast = orgData.status === "approved";
  const ref = db.collection("events").doc();
  const now = Timestamp.now();
  const doc: FirebaseFirestore.DocumentData = {
    title, description, organizer: safeText(orgData.displayName, 80) || "Organizer",
    date: Timestamp.fromDate(start), time: time || "See details", locationName,
    attendeeCount: 0, maxAttendees, category, imagePlaceholder: CATEGORY_ICON[category], pointValue: CATEGORY_POINTS[category],
    creatorID: uid, createdAt: now,
    hidden: false, active: true, broadcast,
    source: "organizer", sourceEventId: ref.id, sourceKeys: [`organizer:${ref.id}`],
    sources: [{ source: "organizer", sourceEventId: ref.id, url: website, lastSeenAt: now }],
    organizerId: org.id, organizerOwnerUid: uid,
    areaId: area?.id ?? null,
    titleKey: titleKey(title), venueKey: venueKey(locationName), startBucket: startBucket(start),
    isFree, website, tags: [safeText(orgData.category, 40)].filter(Boolean),
    categories: [category, ...(category === "Workshop" || category === "Volunteer" ? ["Opportunity"] : []),
      ...(indoorOutdoor === "outdoor" ? ["Outdoors"] : []), ...(isFree ? ["Free"] : [])],
    classificationConfidence: 1,
    qualityScore: Math.min(1, (description.length >= 80 ? 0.25 : description.length > 0 ? 0.1 : 0) +
      (lat !== undefined && lng !== undefined ? 0.25 : 0) + (website ? 0.1 : 0) +
      (ageSuitability !== "unknown" ? 0.15 : 0) + (indoorOutdoor !== "unknown" ? 0.15 : 0) + 0.1),
    inferredCost: isFree ? "free" : "paid", ageSuitability, endInferred: true,
    indoorOutdoor, accessibilityFeatures, publicVenue, recurring, virtual,
    ...(expectedSize !== null ? { expectedSize } : {}),
    ...(minimumAge !== null ? { minimumAge } : {}),
    ...(maximumAge !== null ? { maximumAge } : {}),
    ...(applicationDeadline !== null ? { applicationDeadline } : {}),
    ...(opportunitySubtype !== null ? { opportunitySubtype } : {}),
    ingestedAt: now, lastSeenAt: now, missedCycles: 0,
  };
  if (lat !== undefined) doc.latitude = lat;
  if (lng !== undefined) doc.longitude = lng;
  await ref.set(doc);
  await org.ref.set({ eventCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  // Followers' activity feed: a new event from an organizer they follow.
  await db.collection("activity").add({
    kind: "organizer-event", actorUid: uid, actorName: safeText(orgData.displayName, 80),
    actorInitials: safeText(orgData.displayName, 80).slice(0, 2).toUpperCase(),
    organizerId: org.id, visibility: "public",
    eventId: ref.id, eventTitle: title, eventDate: doc.date, broadcast,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { eventId: ref.id, broadcast, organizerStatus: orgData.status };
});

/** The caller's own organizer profile (or null). */
export const myOrganizer = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const org = await organizerOwnedBy(uid);
  if (!org) return { organizer: null };
  return { organizer: { id: org.id, ...pick(org.data(), ["displayName", "category", "description", "website", "status", "eventCount", "followerCount", "hidden"]) } };
});
