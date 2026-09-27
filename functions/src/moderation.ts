/**
 * Content moderation — report flow, auto-hide, 24-hour review SLA, blocks.
 *
 * WHY THIS EXISTS. Verdure carries user-generated content (community posts,
 * organizer events, profiles). App Review guideline 1.2 requires that users can
 * report objectionable content, that reported content is acted on promptly, that
 * users can block abusive accounts, and that a contact for concerns is published.
 * None of that existed: a post could be reported nowhere and removed by nobody.
 *
 * THE MODEL.
 *   /reports/{queueId}_{reporterUid}   one row per (target, reporter) — server-only
 *   /moderationQueue/{targetType}_{id} one row per reported target — server-only
 *   target documents carry two SERVER-OWNED flags:
 *     hidden   — not visible to anyone but the author (auto at threshold, or by staff)
 *     removed  — permanently taken down (staff action or the 24h sweep)
 *   Firestore rules make both flags unwritable by clients and refuse to serve
 *   hidden documents to anyone but their author. Enforcement is in the rules and
 *   here, never in the client.
 *
 * THE TIMELINE. A report enters the queue immediately. At AUTO_HIDE_REPORT_THRESHOLD
 * distinct reporters the content is hidden instantly (visible only to its author).
 * Every open queue item carries an `slaDeadline` 24 hours after the first report;
 * if staff have not reviewed it by then, `moderationSweep` removes it. Reported
 * content therefore never stays up past 24 hours without a human decision — the
 * SLA is enforced by code, not by a promise in the listing.
 *
 * Published contact for concerns: MODERATION_CONTACT (mirrored in the app's
 * Settings and in AppStore/LISTING.md).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  db, requireUid, requireAdmin, enforceRateLimit, safeString, safeText,
  docIdFrom, isBlockedEitherWay,
} from "./common.js";

export const MODERATION_CONTACT = "support@verdure-app.com";

/** Distinct reporters needed before content is hidden automatically. */
export const AUTO_HIDE_REPORT_THRESHOLD = 3;

/** Reported content is removed if nobody has reviewed it within this window. */
export const MODERATION_SLA_MS = 24 * 60 * 60 * 1000;

export const REPORT_REASONS = [
  "spam", "harassment", "hate", "sexual", "violence", "dangerous",
  "misinformation", "impersonation", "other",
] as const;
type ReportReason = typeof REPORT_REASONS[number];

export type TargetType = "post" | "event" | "user" | "organizer";

const TARGET_COLLECTIONS: Record<TargetType, string> = {
  post: "posts",
  event: "events",
  user: "users",
  organizer: "organizers",
};

/** Which field on the target names its author (owner). */
function authorOf(type: TargetType, data: FirebaseFirestore.DocumentData | undefined, id: string): string | null {
  if (!data) return type === "user" ? id : null;
  switch (type) {
    case "post": return safeString(data.authorID) || null;
    case "event": return safeString(data.creatorID) || null;
    case "organizer": return safeString(data.ownerUid) || null;
    case "user": return id;
  }
}

/** A short excerpt of the content so reviewers can triage without opening it. */
function snapshotOf(type: TargetType, data: FirebaseFirestore.DocumentData | undefined): string {
  if (!data) return "";
  const raw = type === "post" ? data.content
    : type === "event" ? `${data.title ?? ""} — ${data.description ?? ""}`
    : type === "organizer" ? `${data.displayName ?? ""} — ${data.description ?? ""}`
    : data.displayName ?? "";
  return safeText(raw, 280);
}

export function queueIdFor(type: TargetType, id: string): string {
  return docIdFrom(type, id);
}

/**
 * reportContent — file a report against a post, event, organizer or user.
 *
 * Idempotent per (target, reporter): reporting the same thing twice is a no-op,
 * so a single account cannot push content over the auto-hide threshold alone.
 * Everything happens in one transaction so two simultaneous third reports can't
 * both observe "2 reporters" and leave the content visible.
 */
export const reportContent = onCall(async (req) => {
  const uid = requireUid(req.auth, "Sign in to report content.");
  await enforceRateLimit(uid, "reportContent");

  const targetType = safeString(req.data?.targetType) as TargetType;
  const targetId = safeText(req.data?.targetId, 200);
  const reason = safeString(req.data?.reason, "other") as ReportReason;
  const details = safeText(req.data?.details, 1000);

  if (!TARGET_COLLECTIONS[targetType]) throw new HttpsError("invalid-argument", "Unknown content type.");
  if (!targetId || targetId.includes("/")) throw new HttpsError("invalid-argument", "Missing content id.");
  if (!REPORT_REASONS.includes(reason)) throw new HttpsError("invalid-argument", "Unknown report reason.");

  const targetRef = db.collection(TARGET_COLLECTIONS[targetType]).doc(targetId);
  const queueId = queueIdFor(targetType, targetId);
  const queueRef = db.collection("moderationQueue").doc(queueId);
  const reportRef = db.collection("reports").doc(docIdFrom(queueId, uid));

  return db.runTransaction(async (tx) => {
    const [targetSnap, queueSnap, reportSnap] = await Promise.all([
      tx.get(targetRef), tx.get(queueRef), tx.get(reportRef),
    ]);
    // Users may not have a profile document yet; every other type must exist.
    if (!targetSnap.exists && targetType !== "user") {
      throw new HttpsError("not-found", "That content no longer exists.");
    }
    const target = targetSnap.data();
    const author = authorOf(targetType, target, targetId);
    if (author === uid) {
      throw new HttpsError("failed-precondition", "You can't report your own content.");
    }
    if (reportSnap.exists) {
      return { reported: true, alreadyReported: true, hidden: queueSnap.data()?.hidden === true, queueId };
    }

    const now = Timestamp.now();
    const q = queueSnap.data() ?? {};
    const alreadyResolved = q.status === "removed";
    // A dismissed item that gets reported again reopens with a fresh SLA clock
    // AND a fresh reporter count: staff already judged the earlier reports, so
    // they must not be able to re-trip the auto-hide on their own.
    const reopening = q.status === "dismissed";
    const reporters: string[] = (!reopening && Array.isArray(q.reporters)) ? q.reporters : [];
    const distinct = new Set(reporters); distinct.add(uid);
    const firstReportedAt: Timestamp = (!queueSnap.exists || reopening) ? now : (q.firstReportedAt ?? now);
    const slaDeadline = Timestamp.fromMillis(firstReportedAt.toMillis() + MODERATION_SLA_MS);

    const canHide = targetType !== "user";
    const shouldHide = canHide && !alreadyResolved && distinct.size >= AUTO_HIDE_REPORT_THRESHOLD;

    tx.set(reportRef, {
      queueId, targetType, targetId, reporterUid: uid, reason, details,
      status: "open", createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(queueRef, {
      targetType, targetId,
      authorUid: author,
      snapshot: snapshotOf(targetType, target),
      reporters: Array.from(distinct),
      reportCount: distinct.size,
      reasons: FieldValue.arrayUnion(reason),
      firstReportedAt,
      lastReportedAt: now,
      slaDeadline,
      status: alreadyResolved ? "removed" : "open",
      hidden: alreadyResolved ? true : (shouldHide || q.hidden === true),
      ...(shouldHide && q.hidden !== true ? { hiddenAt: now, hiddenBy: "auto-threshold" } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    if (shouldHide && targetSnap.exists && target?.hidden !== true) {
      tx.set(targetRef, { hidden: true, hiddenAt: now }, { merge: true });
    }
    return { reported: true, alreadyReported: false, hidden: shouldHide || q.hidden === true, queueId };
  });
});

type ModerationAction = "remove" | "dismiss" | "restore" | "suspend";

/** Apply a moderation decision to a queue item and its target. Shared by staff + sweep. */
async function applyDecision(queueId: string, action: ModerationAction, by: string, resolution: string) {
  const queueRef = db.collection("moderationQueue").doc(queueId);
  const queueSnap = await queueRef.get();
  if (!queueSnap.exists) throw new HttpsError("not-found", "No such moderation item.");
  const q = queueSnap.data()!;
  const targetType = q.targetType as TargetType;
  const targetRef = db.collection(TARGET_COLLECTIONS[targetType]).doc(String(q.targetId));
  const now = Timestamp.now();

  const batch = db.batch();
  let targetUpdate: Record<string, unknown> | null = null;
  let status: string;

  switch (action) {
    case "remove":
      status = "removed";
      if (targetType === "user") {
        targetUpdate = { suspended: true, suspendedAt: now };
      } else {
        targetUpdate = { hidden: true, removed: true, removedAt: now };
        // Redact user-authored prose so it cannot be recovered through any other path.
        if (targetType === "post") targetUpdate.content = "[removed by moderation]";
        if (targetType === "event") targetUpdate.description = "[removed by moderation]";
      }
      break;
    case "suspend":
      status = "removed";
      if (q.authorUid) {
        batch.set(db.collection("users").doc(String(q.authorUid)),
          { suspended: true, suspendedAt: now }, { merge: true });
      }
      if (targetType !== "user") targetUpdate = { hidden: true, removed: true, removedAt: now };
      break;
    case "dismiss":
      status = "dismissed";
      if (targetType !== "user") targetUpdate = { hidden: false };
      break;
    case "restore":
      status = "dismissed";
      targetUpdate = targetType === "user"
        ? { suspended: false }
        : { hidden: false, removed: false };
      break;
  }

  // Content that has since been deleted needs no update; a USER must be updated
  // even when they have no profile document yet, or the suspension would
  // silently fail to stick for exactly the accounts that never finished setup.
  if (targetUpdate && (targetType === "user" || (await targetRef.get()).exists)) {
    batch.set(targetRef, targetUpdate, { merge: true });
  }
  batch.set(queueRef, {
    status, hidden: status === "removed" ? true : false,
    resolution, reviewedAt: now, reviewedBy: by, updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const reports = await db.collection("reports").where("queueId", "==", queueId).get();
  reports.forEach((r) => batch.set(r.ref, {
    status: status === "removed" ? "actioned" : "dismissed", reviewedAt: now,
  }, { merge: true }));
  await batch.commit();
  return { queueId, status, resolution };
}

/**
 * moderateContent — staff decision on a queue item.
 *   remove  → content hidden + marked removed (prose redacted); user → suspended
 *   dismiss → content visible again, item closed
 *   restore → undo a removal
 *   suspend → remove the content AND suspend its author
 */
export const moderateContent = onCall(async (req) => {
  const staff = await requireAdmin(req.auth);
  const queueId = safeText(req.data?.queueId, 900);
  const action = safeString(req.data?.action) as ModerationAction;
  if (!queueId) throw new HttpsError("invalid-argument", "Missing queueId.");
  if (!["remove", "dismiss", "restore", "suspend"].includes(action)) {
    throw new HttpsError("invalid-argument", "Unknown moderation action.");
  }
  return applyDecision(queueId, action, staff, `staff:${action}`);
});

/**
 * The 24-hour guarantee. Any open item whose deadline has passed is removed.
 * Idempotent: an already-decided item is skipped, so re-running is harmless.
 */
export async function sweepModerationQueue(now = Date.now()): Promise<{ removed: number }> {
  const due = await db.collection("moderationQueue")
    .where("status", "==", "open")
    .where("slaDeadline", "<=", Timestamp.fromMillis(now))
    .limit(200)
    .get();
  let removed = 0;
  for (const d of due.docs) {
    const type = d.data().targetType as TargetType;
    // Reports against a *person* are never auto-actioned — suspending an account
    // on a timer with no human in the loop is the abuse vector, not the fix.
    if (type === "user") continue;
    await applyDecision(d.id, "remove", "system", "auto:24h-sla");
    removed++;
  }
  return { removed };
}

export const moderationSweep = onSchedule("every 60 minutes", async () => {
  const { removed } = await sweepModerationQueue();
  if (removed) console.log(`[moderation] SLA sweep removed ${removed} item(s)`);
});

/** Manual trigger for the sweep (staff / E2E — schedules don't fire in the emulator). */
export const runModerationSweep = onCall(async (req) => {
  await requireAdmin(req.auth);
  return sweepModerationQueue();
});

/**
 * Staff view of the queue. Clients cannot read /moderationQueue directly (rules),
 * so this is the only window into it — and it is admin-gated.
 */
export const listModerationQueue = onCall(async (req) => {
  await requireAdmin(req.auth);
  const status = safeString(req.data?.status, "open");
  const snap = await db.collection("moderationQueue")
    .where("status", "==", status)
    .orderBy("slaDeadline", "asc")
    .limit(100)
    .get();
  return {
    items: snap.docs.map((d) => {
      const q = d.data();
      return {
        queueId: d.id, targetType: q.targetType, targetId: q.targetId,
        reportCount: q.reportCount, reasons: q.reasons ?? [], snapshot: q.snapshot ?? "",
        hidden: q.hidden === true,
        slaDeadlineMs: q.slaDeadline?.toMillis?.() ?? null,
      };
    }),
  };
});

/** Exposed for other modules (social feed, RSVP visibility). */
export { isBlockedEitherWay };

/**
 * One-time backfill for documents created before moderation flags existed.
 * The read rules now REQUIRE `hidden == false`, so a legacy post or event with
 * no flag would silently vanish from every feed. Idempotent; admin-only.
 */
export const backfillModerationFlags = onCall(async (req) => {
  await requireAdmin(req.auth);
  let updated = 0;
  for (const coll of ["posts", "events", "organizers"]) {
    const snap = await db.collection(coll).limit(2000).get();
    const batch = db.batch();
    let n = 0;
    snap.forEach((d) => {
      if (typeof d.data().hidden !== "boolean") {
        batch.set(d.ref, { hidden: false }, { merge: true });
        n++;
      }
    });
    if (n) await batch.commit();
    updated += n;
  }
  return { updated };
});
