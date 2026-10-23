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
  normalizeInterests,
} from "../lib/ranking.js";
import { reasonsForV1 } from "../lib/ranking-v2.js";

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
ok("a household with a four-year-old ranks a child-suitable event higher",
  interestScore(ev("family", { ageSuitability: "children", minimumAge: 4 }),
    { ...baseCtx, householdYoungestAge: 4 }) >
  interestScore(ev("adult", { ageSuitability: "adults", minimumAge: 18 }),
    { ...baseCtx, householdYoungestAge: 4 }));
ok("confirmed accessibility needs boost a listing without hiding unconfirmed listings",
  interestScore(ev("confirmed", { accessibilityFeatures: ["stepFree", "seating"] }),
    { ...baseCtx, accessibilityNeeds: ["stepFree", "seating"] }) >
  interestScore(ev("unconfirmed", { accessibilityFeatures: ["stepFree"] }),
    { ...baseCtx, accessibilityNeeds: ["stepFree", "seating"] }));
{
  const distant = ev("distant", { latitude: SJ.lat + 0.1 });
  ok("usual walking makes the same trip rank farther away than driving",
    distanceScore(distant, { ...baseCtx, transportMode: "walk" }) <
    distanceScore(distant, { ...baseCtx, transportMode: "drive" }));
  ok("typical distance changes the distance decay without filtering the event",
    distanceScore(distant, { ...baseCtx, radiusMiles: 2 }) <
    distanceScore(distant, { ...baseCtx, radiusMiles: 25 }) &&
    rankEvents([distant], { ...baseCtx, radiusMiles: 2 }).length === 1);
}

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

console.log("\n── the app's own interest labels (onboarding saves PlaceCategory raw values) ──");
{
  // The app writes "Parks", "Trails", … to users/{uid}.interests. Before normalization only
  // "Community" matched anything, so a hiker's For You filled with career and dev listings.
  const n = normalizeInterests(["Parks", "Trails", "Playgrounds", "Sports", "Community", "outdoors", "Mystery"]);
  ok("app labels map onto ranking interests; unknown labels pass through",
     ["outdoors", "hiking", "family", "fitness", "community", "mystery"].every((i) => n.interests.includes(i)), JSON.stringify(n));
  ok("each mapped interest remembers the label the user picked",
     n.labels.hiking?.[0] === "Trails" && n.labels.outdoors?.includes("Parks") && n.labels.fitness?.[0] === "Sports");

  // A mixed slate at comparable distance (~2.5 mi): outdoor programs (Midpen-style hikes are
  // classified Sports), community meetups, and deliberately well-structured opportunity listings
  // (higher quality, free, sooner). Distance stays the heaviest weight by design, so the slate
  // holds it level to isolate what the user picked.
  const outdoor = [
    ["hike-1", "Guided Hike: Rancho San Antonio Ridge", "Sports"], ["hike-2", "Sunset Hike at Sierra Azul", "Sports"],
    ["walk-1", "Nature Walk for Beginners", "Social"], ["park-1", "Park Cleanup at Guadalupe River Park", "Cleanup"],
    ["trail-1", "Trail Restoration Day", "Volunteer"], ["bird-1", "Birding Ramble at Alviso Marsh", "Meetup"],
    ["garden-1", "Community Garden Workday in the park", "Volunteer"], ["hike-3", "Wildflower Hike, Coyote Valley", "Sports"],
    ["hike-4", "Family Trail Hike at Almaden Quicksilver", "Sports"], ["walk-2", "Docent-led Nature Walk at Alum Rock Park", "Festival"],
    ["hike-5", "Full Moon Hike at Fremont Older", "Sports"], ["park-2", "Park Ranger Talk at Vasona Lake", "Meetup"],
  ].map(([id, title, category], i) => ev(id, { title, category, organizer: `Midpen ${i % 4}`, startMs: days(2 + (i % 5)),
      latitude: SJ.lat + 0.03, longitude: SJ.lng - 0.02, qualityScore: 0.6, topicTags: ["outdoors"] }));
  const community = Array.from({ length: 10 }, (_, i) => ev(`comm-${i}`, { title: `Neighborhood Association Meetup ${i}`,
      category: "Meetup", organizer: `Neighbors ${i % 3}`, startMs: days(2 + (i % 5)), latitude: SJ.lat - 0.03, longitude: SJ.lng + 0.02, qualityScore: 0.6, topicTags: ["community"] }));
  const careerish = [
    ["career-1", "Career Fair: Tech Employers", "Workshop"], ["career-2", "Resume Workshop for Engineers", "Workshop"],
    ["hack-1", "Student Hackathon 2026", "Hackathon"], ["dev-1", "iOS Developers Meetup", "Meetup"],
    ["career-3", "Interview Skills Workshop", "Workshop"], ["career-4", "Networking Night: Startups", "Workshop"],
    ["hack-2", "AI Build Weekend", "Hackathon"], ["dev-2", "Intro to Python Workshop", "Workshop"],
    ["career-5", "Internship Info Session", "Workshop"], ["vol-1", "Tutoring Volunteers Needed", "Volunteer"],
  ].map(([id, title, category], i) => ev(id, { title, category, organizer: "San José State University", startMs: days(1 + (i % 4)),
      latitude: SJ.lat - 0.03, longitude: SJ.lng - 0.02, qualityScore: 0.95, isFree: true, tags: ["Opportunity"], topicTags: ["tech"] }));
  const slate = [...outdoor, ...community, ...careerish];
  const outdoorIds = new Set(outdoor.map((e) => e.id));
  const careerIds = new Set(careerish.filter((e) => e.category !== "Volunteer").map((e) => e.id));
  const ctxFor = (labels, extra = {}) => { const n = normalizeInterests(labels);
    return { ...baseCtx, interests: n.interests, interestLabels: n.labels, ...extra }; };
  const top = (ctx) => rankEvents(slate, ctx).slice(0, 10).map((s) => s.id);

  const trails = top(ctxFor(["Trails", "Parks"]));
  const comm = top(ctxFor(["Community"]));
  const outdoorIn = (ids) => ids.filter((id) => outdoorIds.has(id)).length;
  ok("['Trails','Parks'] fills the top 10 with outdoor/hike events", outdoorIn(trails) >= 8, trails.join(","));
  ok("…well above ['Community']", outdoorIn(trails) - outdoorIn(comm) >= 4, `${outdoorIn(trails)} vs ${outdoorIn(comm)}: ${comm.join(",")}`);
  ok("the two top-10s differ", JSON.stringify(trails) !== JSON.stringify(comm));

  const student = top(ctxFor(["Parks", "Trails"], { studentStatus: true, school: "San José State University" }));
  ok("a student who picked Parks + Trails gets a mostly outdoor top 10", outdoorIn(student) >= 7, student.join(","));
  ok("…with at most 2 workshop/hackathon/career events", student.filter((id) => careerIds.has(id)).length <= 2, student.join(","));
  ok("a direct interest match outranks the student opportunity floor",
     interestScore(outdoor[0], ctxFor(["Parks", "Trails"], { studentStatus: true })) >
     interestScore(careerish[0], ctxFor(["Parks", "Trails"], { studentStatus: true })));
  ok("a student with no stated interests keeps the opportunity floor",
     interestScore(careerish[0], { ...baseCtx, studentStatus: true }) >= 0.75);

  const hike = outdoor[0];
  const scored = scoreEvent(hike, ctxFor(["Parks", "Trails"]));
  const why = reasonsForV1(hike, ctxFor(["Parks", "Trails"]), scored.parts);
  ok("the reasons line names what the user picked", why.includes("Because you like Trails"), JSON.stringify(why));
  ok("…never an internal word", !why.some((r) => /the outdoors|hiking/.test(r)), JSON.stringify(why));

  // Real San José listings that were labelled "Because you like Parks" (emulator corpus, 2026-10-23).
  const picks = ctxFor(["Parks", "Trails"]);
  const yoga = ev("yoga", { title: "Community Yoga and Heartfulness Meditation", category: "Sports",
    description: "Experience the soothing calm of yoga and meditation.", locationName: "Cambrian · Community Room" });
  const ell = ev("ell", { title: "English Language Learner (ELL) for Beginners", category: "Workshop",
    description: "English learners are invited to beginner friendly lessons at the Rose Garden Branch Library. " +
      "Invitamos a participar en nuestras clases en la biblioteca Rose Garden." });
  const parkBranch = ev("branch", { title: "Tabletop Gamers", category: "Social", description: "Meet at the Educational Park Branch." });
  ok("indoor yoga (Sports) is not a Parks/Trails match", interestScore(yoga, picks) === 0, String(interestScore(yoga, picks)));
  ok("a library branch named 'Rose Garden' / 'Educational Park' is not a Parks match",
     interestScore(ell, picks) === 0 && interestScore(parkBranch, picks) === 0);
  const ellWhy = reasonsForV1(ell, picks, scoreEvent(ell, picks).parts);
  ok("…and its reasons never claim the user's pick", !ellWhy.some((r) => r.startsWith("Because you like")), JSON.stringify(ellWhy));
  ok("a real garden or park listing still matches",
     interestScore(ev("g", { title: "Community Garden Workday in the park", category: "Volunteer" }), picks) >= 0.9);
}

console.log(`\n══ ${pass} passed, ${fail} failed ══`);
process.exit(fail ? 1 : 0);
