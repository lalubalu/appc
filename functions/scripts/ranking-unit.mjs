/**
 * Ranking engine unit tests — no emulator, no network.
 *
 * The most important assertions in this file are the NEGATIVE ones: that no
 * input can cause rankEvents to return fewer events than it was given. That is
 * the property the whole design rests on, and it is the one a future weight
 * tweak is most likely to break by "helpfully" dropping a zero-scoring event.
 */
import {
  WEIGHTS, WEIGHT_SUM, rankEvents, scoreEvent, interestScore, distanceScore,
  socialScore, timingScore, noveltyScore, feedbackScore, haversineMiles, INTEREST_TO_CATEGORY,
} from "../lib/ranking.js";

let pass = 0, fail = 0;
const ok = (name, cond, extra = "") => {
  if (cond) { pass++; console.log(`  ✅ ${name}`); }
  else { fail++; console.log(`  ❌ ${name} ${extra}`); }
};

const NOW = Date.UTC(2026, 8, 13, 12, 0, 0);
const days = (n) => NOW + n * 86_400_000;
const SJ = { lat: 37.3382, lng: -121.8863 };

const baseCtx = {
  interests: [], attendedCategories: {}, friendsGoing: {},
  recentOrganizers: {}, lat: SJ.lat, lng: SJ.lng, nowMs: NOW,
};
const ev = (id, o = {}) => ({
  id, category: "Meetup", organizer: "Org", startMs: days(3),
  latitude: SJ.lat, longitude: SJ.lng, ...o,
});

console.log("── weights ──");
ok("weights sum to exactly 1.0", Math.abs(WEIGHT_SUM - 1) < 1e-9, String(WEIGHT_SUM));
ok("distance is the heaviest single term", WEIGHTS.distance === Math.max(...Object.values(WEIGHTS)));

console.log("\n── rank, never filter (the load-bearing property) ──");
{
  const events = [
    ev("a", { category: "Sports", startMs: days(1) }),
    ev("b", { category: "Cleanup", startMs: days(40), latitude: 40.0, longitude: -100.0 }),
    ev("c", { category: "Hackathon", startMs: days(9) }),
    ev("d", { category: "Sports", startMs: days(2) }),
  ];
  const ctx = { ...baseCtx, interests: ["tech"] };
  const out = rankEvents(events, ctx);
  ok("every input event is present in the output", out.length === events.length, `${out.length} vs ${events.length}`);
  ok("no event is dropped even with an interest set that matches only one",
     new Set(out.map((o) => o.id)).size === 4);
  ok("the far, wrong-category, 40-days-out event still has a positive score",
     out.find((o) => o.id === "b").score > 0, JSON.stringify(out.find((o) => o.id === "b")));
}
{
  // Adversarial: a user whose every signal argues against every event.
  const events = [ev("x", { category: "Sports", startMs: days(90), latitude: 10, longitude: 10 })];
  const ctx = { ...baseCtx, interests: ["tech"], recentOrganizers: { Org: 50 } };
  const out = rankEvents(events, ctx);
  ok("worst possible event still returned, still scored above zero",
     out.length === 1 && out[0].score > 0, JSON.stringify(out[0]));
}

console.log("\n── cold start ──");
{
  const ctx = { ...baseCtx };   // no interests, no history, no friends
  const out = rankEvents([ev("a", { startMs: days(3) }), ev("b", { startMs: days(60) })], ctx);
  ok("cold-start user gets a non-empty ranked list", out.length === 2);
  ok("cold start falls back to soon-and-nearby", out[0].id === "a", JSON.stringify(out.map((o) => o.id)));
  ok("unknown interests score neutral 0.5, not 0",
     interestScore(ev("a"), ctx) === 0.5);
  const qualityChoice = rankEvents([
    ev("thin", { qualityScore: 0.15 }),
    ev("complete", { qualityScore: 0.95 }),
  ], ctx);
  ok("cold-start ranks a complete listing above an otherwise equal thin one",
     qualityChoice[0].id === "complete", JSON.stringify(qualityChoice));
  const workshop = ev("workshop", { category: "Workshop", organizer: "San Jose City College" });
  ok("student mode raises a public workshop above a neutral event",
     interestScore(workshop, { ...ctx, studentStatus: true }) > interestScore(ev("neutral"), { ...ctx, studentStatus: true }));
  ok("a workshop at the student's school gets a stronger affinity",
     interestScore(workshop, { ...ctx, studentStatus: true, school: "San Jose City College" }) >
     interestScore(workshop, { ...ctx, studentStatus: true, school: "Other School" }));
}

console.log("\n── interest term ──");
{
  const stated = { ...baseCtx, interests: ["tech"] };
  ok("stated interest matches its mapped categories",
     interestScore(ev("a", { category: "Hackathon" }), stated) === 1 &&
     interestScore(ev("a", { category: "Sports" }), stated) === 0);
  ok("interest map covers every app interest with at least one category",
     Object.values(INTEREST_TO_CATEGORY).every((v) => Array.isArray(v) && v.length > 0));
  const hiking = { ...baseCtx, interests: ["hiking"] };
  ok("semantic interest matches a trail day without the word hiking",
     interestScore(ev("trail", { category: "Volunteer", title: "Trail Day at Rancho San Antonio" }), hiking) > 0.8);
  ok("semantic interest matches a nature walk without the word hiking",
     interestScore(ev("walk", { category: "Meetup", title: "Guided Nature Walk" }), hiking) > 0.8);
  ok("semantic match respects word boundaries",
     interestScore(ev("noise", { category: "Meetup", title: "Parkitecture talk" }), hiking) === 0);

  // Behaviour overrides the onboarding tap.
  const contradicted = { ...baseCtx, interests: ["tech"], attendedCategories: { Cleanup: 4 } };
  const cleanup = interestScore(ev("a", { category: "Cleanup" }), contradicted);
  const hack = interestScore(ev("a", { category: "Hackathon" }), contradicted);
  ok("four attended cleanups outweigh a stated 'tech' interest", cleanup > hack, `cleanup=${cleanup} hack=${hack}`);
}

console.log("\n── distance term ──");
{
  ok("haversine: San Jose to Palo Alto is ~14-18 mi",
     (() => { const d = haversineMiles(37.3382, -121.8863, 37.4419, -122.1430); return d > 13 && d < 19; })(),
     String(haversineMiles(37.3382, -121.8863, 37.4419, -122.1430)));
  ok("distance decays monotonically and never reaches 0", (() => {
      const d = (m) => distanceScore(ev("a", { latitude: 37.3382 + m / 69, longitude: -121.8863 }), baseCtx);
      return d(0) > d(5) && d(5) > d(25) && d(200) > 0;
    })());
  ok("~5 miles scores about half", (() => {
      const s = distanceScore(ev("a", { latitude: 37.3382 + 5 / 69, longitude: -121.8863 }), baseCtx);
      return Math.abs(s - 0.5) < 0.05;
    })());
  ok("an event with no coordinates is mildly penalised, not excluded",
     distanceScore(ev("a", { latitude: undefined, longitude: undefined }), baseCtx) === 0.4);
  ok("a user with no location gets neutral distance for everyone",
     distanceScore(ev("a"), { ...baseCtx, lat: undefined, lng: undefined }) === 0.5);
}

console.log("\n── social term ──");
{
  ok("no friends going scores 0", socialScore(ev("a"), baseCtx) === 0);
  const one = socialScore(ev("a"), { ...baseCtx, friendsGoing: { a: 1 } });
  const three = socialScore(ev("a"), { ...baseCtx, friendsGoing: { a: 3 } });
  ok("one friend is most of the effect; it saturates", one >= 0.7 && three <= 1 && three - one < one, `1=${one} 3=${three}`);
  // The social term is worth 0.18, so it flips a moderate distance gap and NOT
  // a large one. Both halves are asserted — a weight change that made "a friend
  // is going" able to drag a 20-mile event to the top would be a bug, not an
  // improvement.
  ok("a friend going flips a moderate distance gap (~4 mi)", (() => {
      const out = rankEvents([
        ev("near", { startMs: days(3) }),
        ev("far", { startMs: days(3), latitude: 37.3382 + 4 / 69, longitude: -121.8863 }),
      ], { ...baseCtx, friendsGoing: { far: 2 } });
      return out[0].id === "far";
    })(), "social should outweigh ~4 miles");
  ok("but a friend going does NOT drag a 20-mile event to the top", (() => {
      const out = rankEvents([
        ev("near", { startMs: days(3) }),
        ev("far", { startMs: days(3), latitude: 37.3382 + 20 / 69, longitude: -121.8863 }),
      ], { ...baseCtx, friendsGoing: { far: 3 } });
      return out[0].id === "near";
    })(), "20 miles should still lose");
}

console.log("\n── timing term ──");
{
  ok("a past event scores 0 on timing", timingScore(ev("a", { startMs: days(-1) }), baseCtx) === 0);
  ok("2-7 days out is the peak",
     timingScore(ev("a", { startMs: days(3) }), baseCtx) === 1 &&
     timingScore(ev("a", { startMs: days(3) }), baseCtx) > timingScore(ev("a", { startMs: days(0.2) }), baseCtx));
  ok("six weeks out is nearly weightless", timingScore(ev("a", { startMs: days(45) }), baseCtx) < 0.2);
  ok("unreachable event starting in 30 minutes is strongly penalized",
     timingScore(ev("far-soon", { startMs: NOW + 30 * 60_000, latitude: 38, longitude: -122 }), baseCtx) < 0.1);
  ok("a weekend attendance pattern prefers weekend plans",
     timingScore(ev("weekend", { startMs: days(6) }), { ...baseCtx, weekendAttendanceRatio: 1 }) >
     timingScore(ev("weekday", { startMs: days(4) }), { ...baseCtx, weekendAttendanceRatio: 1 }));
}

console.log("\n── feedback term ──");
{
  const candidate = ev("feedback", { category: "Workshop", organizer: "Library" });
  const neutral = feedbackScore(candidate, baseCtx);
  ok("saved intent raises a score", feedbackScore(candidate, { ...baseCtx, savedEventIDs: ["feedback"] }) > neutral);
  ok("two attended organizer events raise affinity",
     feedbackScore(candidate, { ...baseCtx, attendedOrganizers: { Library: 2 } }) > neutral);
  const less = { ...baseCtx, eventFeedback: { seenWorkshop: { category: "Workshop", kind: "less", atMs: NOW } } };
  ok("less like this lowers matching category", feedbackScore(candidate, less) < neutral);
  ok("dismissal fades to neutral after 90 days",
     feedbackScore(candidate, { ...less, nowMs: NOW + 91 * 86_400_000 }) === neutral);
  const more = { ...baseCtx, eventFeedback: { seenWorkshop: { category: "Workshop", kind: "more", atMs: NOW } } };
  ok("more like this raises matching category", feedbackScore(candidate, more) > neutral);
  ok("feedback changes the subsequent rank order", (() => {
    const rows = [candidate, ev("other", { category: "Sports", organizer: "Parks" })];
    return rankEvents(rows, less)[0].id === "other" && rankEvents(rows, more)[0].id === "feedback";
  })());
}

console.log("\n── novelty + diversity ──");
{
  ok("an unseen organizer scores 1", noveltyScore(ev("a", { organizer: "New" }), baseCtx) === 1);
  ok("a heavily-seen organizer is damped but never zeroed",
     noveltyScore(ev("a", { organizer: "Org" }), { ...baseCtx, recentOrganizers: { Org: 10 } }) > 0);

  // One prolific library must not own the whole feed.
  //
  // The six workshops are deliberately made BETTER than the cleanup on every
  // per-event term (nearer and sooner), so without diversity damping they would
  // occupy all six leading positions and the cleanup would land dead last. The
  // assertion is that it does not.
  const many = Array.from({ length: 6 }, (_, i) =>
    ev(`lib${i}`, { category: "Workshop", organizer: "Library", startMs: days(3) }));
  const other = ev("cleanup", { category: "Cleanup", organizer: "Parks", startMs: days(6),
                                latitude: 37.3382 + 2 / 69, longitude: -121.8863 });

  // Establish the counterfactual rather than asserting it from memory.
  const undamped = [...many, other]
    .map((e) => scoreEvent(e, baseCtx))
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
  ok("counterfactual: without diversity the cleanup ranks last",
     undamped[undamped.length - 1].id === "cleanup", undamped.map((o) => o.id).join(","));

  const out = rankEvents([...many, other], baseCtx);
  const firstCleanupIdx = out.findIndex((o) => o.id === "cleanup");
  ok("diversity lifts the lone cleanup out of last place",
     firstCleanupIdx < 6, `idx=${firstCleanupIdx} order=${out.map((o) => o.id)}`);
  ok("the best workshop still leads — diversity reorders, it does not invert",
     out[0].id.startsWith("lib"), out.map((o) => o.id).join(","));
  ok("diversity damping never removes anything", out.length === 7);
  ok("the top result is never damped", out[0].parts.diversity === 1);
}

console.log("\n── determinism ──");
{
  const events = [ev("b"), ev("a"), ev("c")];
  const a = rankEvents(events, baseCtx).map((o) => o.id);
  const b = rankEvents([...events].reverse(), baseCtx).map((o) => o.id);
  ok("ties break stably by id regardless of input order", JSON.stringify(a) === JSON.stringify(b), `${a} vs ${b}`);
}

console.log("\n── scoring shape ──");
{
  const s = scoreEvent(ev("a"), baseCtx);
  ok("score is 0..1 and parts are all 0..1",
     s.score >= 0 && s.score <= 1 && Object.values(s.parts).every((p) => p >= 0 && p <= 1), JSON.stringify(s));
  ok("parts are returned so a placement can be explained on-device",
     ["interest", "distance", "social", "timing", "novelty"].every((k) => k in s.parts));
}

console.log(`\n══ ${pass} passed, ${fail} failed ══`);
process.exit(fail ? 1 : 0);
