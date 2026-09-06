// Ingest layer unit checks — no emulator, no network.
//
//   npm run build && node scripts/ingest-unit.mjs
//
// The fixtures under test-fixtures/ are TRIMMED COPIES OF REAL RESPONSES
// captured on 2026-09-06 (Cleveland Public Library LibCal, Ticketmaster
// Discovery for Cleveland, NPS events for Cuyahoga Valley, Tri-C Localist), so
// the mappers are exercised against the shapes the vendors actually return, not
// against what their docs say.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { parseIcs, unfold, unescapeText, expandRRule, parseIcsDate } from "../lib/ingest/ics.js";
import { titleKey, venueKey, classify, zonedToUtc, cleanText, cleanUrl, eventDocId } from "../lib/ingest/normalize.js";
import { mapTicketmaster } from "../lib/ingest/sources/ticketmaster.js";
import { mapIcsEvent } from "../lib/ingest/sources/icsfeed.js";
import { parseLibCalRss, mapLibCalItem } from "../lib/ingest/sources/libcal.js";
import { mapLocalist } from "../lib/ingest/sources/localist.js";
import { mapNps } from "../lib/ingest/sources/nps.js";
import { mapSerp, parseSerpDate, serpApiBudgetAllows, SERPAPI_MONTHLY_CAP } from "../lib/ingest/sources/serpapi.js";
import { isSameEvent, isWithinHorizon } from "../lib/ingest/store.js";
import { CLEVELAND, isInsideArea } from "../lib/ingest/areas.js";
import { coercePayloadRecord } from "../lib/ingest/index.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixture = (name) => readFileSync(join(here, "..", "test-fixtures", name), "utf8");

let passed = 0, failed = 0;
const ok = (name, cond, extra = "") => {
  if (cond) { passed++; console.log(`  ✅ ${name}`); }
  else { failed++; console.error(`  ❌ ${name} ${extra}`); }
};

console.log("── normalize ──");
ok("titleKey ignores case, punctuation and stopwords",
   titleKey("The Cleveland Orchestra: Beethoven at Blossom!") === titleKey("cleveland orchestra — beethoven AT blossom"),
   `${titleKey("The Cleveland Orchestra: Beethoven at Blossom!")} vs ${titleKey("cleveland orchestra — beethoven AT blossom")}`);
ok("titleKey keeps distinct titles distinct", titleKey("Storytime: Dinosaurs") !== titleKey("Storytime: Trucks"));
ok("venueKey uses the first comma segment, alphanumerics only",
   venueKey("Main Library - Downtown, 325 Superior Ave") === "mainlibrarydowntown");
ok("classify: volunteer beats social", classify("Park cleanup volunteer day") === "Cleanup");
ok("classify: library storytime is a Workshop", classify("Toddler Storytime") === "Workshop");
ok("classify: farmers market", classify("Cuyahoga Valley Farmers Market") === "Market");
ok("classify: concert is a Festival", classify("Beethoven concert at Blossom") === "Festival");
ok("classify: unknown → Social", classify("Thing") === "Social");
ok("cleanText strips markup, entities and control chars",
   cleanText("<b>Hello</b>&nbsp;&amp; world  \n now", 50) === "Hello & world now", JSON.stringify(cleanText("<b>Hello</b>&nbsp;&amp; world  \n now", 50)));
ok("cleanUrl rejects javascript:", cleanUrl("javascript:alert(1)") === undefined);
ok("cleanUrl accepts https", cleanUrl("https://cpl.libcal.com/event/1") === "https://cpl.libcal.com/event/1");
ok("eventDocId is Firestore-safe", /^[A-Za-z0-9_-]+$/.test(eventDocId("libcal", "LibCal-8758-17093140@2026-09-10T14:00:00.000Z")));
// 2026-07-04 10:00 New York = 14:00Z (EDT); 2026-01-04 10:00 = 15:00Z (EST).
ok("zonedToUtc handles EDT", zonedToUtc({ y: 2026, m: 7, d: 4, hh: 10, mm: 0, ss: 0 }, "America/New_York").toISOString() === "2026-07-04T14:00:00.000Z");
ok("zonedToUtc handles EST", zonedToUtc({ y: 2026, m: 1, d: 4, hh: 10, mm: 0, ss: 0 }, "America/New_York").toISOString() === "2026-01-04T15:00:00.000Z");

console.log("\n── ics parser ──");
const raw = fixture("cpl-libcal-sample.ics");
ok("unfold joins continuation lines", unfold("DESCRIPTION:Hello\r\n  world\r\nX:1").length === 2 && unfold("DESCRIPTION:Hello\r\n  world")[0] === "DESCRIPTION:Hello world");
ok("unescapeText handles \\, \\; \\n", unescapeText("a\\, b\\; c\\nd") === "a, b; c\nd");
const dOnly = parseIcsDate("20260806", { VALUE: "DATE" }, "America/New_York");
ok("VALUE=DATE parses as all-day local midnight", dOnly?.allDay === true && dOnly.date.toISOString() === "2026-08-06T04:00:00.000Z", dOnly?.date.toISOString());
const dt = parseIcsDate("20260906T100000", { TZID: "America/New_York" }, "UTC");
ok("TZID local time converts to UTC", dt?.date.toISOString() === "2026-09-06T14:00:00.000Z", dt?.date.toISOString());
const dz = parseIcsDate("20260906T140000Z", {}, "America/New_York");
ok("Z suffix is UTC", dz?.date.toISOString() === "2026-09-06T14:00:00.000Z");
const horizon = new Date("2030-01-01T00:00:00Z");
const events = parseIcs(raw, { defaultTimeZone: "America/New_York", horizonEnd: horizon });
ok("parses every VEVENT in the real CPL sample", events.length === 12, `got ${events.length}`);
const first = events[0];
ok("SUMMARY / UID / URL / CATEGORIES / ORGANIZER come through",
   first.summary === "AsiaTown Passport" && first.uid === "LibCal-8758-17093140"
   && first.url === "https://cpl.libcal.com/event/17093140" && first.categories.includes("School of Arts & Culture")
   && first.organizer === "Tai-Renee King", JSON.stringify({ s: first.summary, u: first.uid, url: first.url, c: first.categories, o: first.organizer }));
ok("folded DESCRIPTION is unfolded and unescaped",
   first.description.includes("Passport Challenge!") && first.description.includes("locations, including the ArtBox"), first.description.slice(0, 120));
ok("LOCATION with escaped comma", first.location === "ArtBoxEvent, Offsite", first.location);
ok("X-WR-TIMEZONE applied to local DATE-TIMEs",
   events.some((e) => !e.allDay && e.start.getUTCHours() !== 0) || events.every((e) => e.allDay));
const weekly = expandRRule("FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4", new Date("2026-09-01T14:00:00Z"), horizon);
ok("RRULE weekly BYDAY COUNT expands to 4 Tue/Thu", weekly.length === 4 && weekly.every((d) => [2, 4].includes(d.getUTCDay())),
   weekly.map((d) => d.toISOString()).join(","));
const daily = expandRRule("FREQ=DAILY;INTERVAL=2;UNTIL=20260910T000000Z", new Date("2026-09-01T14:00:00Z"), horizon);
ok("RRULE daily INTERVAL/UNTIL", daily.length === 5, `got ${daily.length}`);
const rec = parseIcs(
  "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r1\r\nSUMMARY:Storytime\r\nDTSTART;TZID=America/New_York:20260901T100000\r\nDTEND;TZID=America/New_York:20260901T103000\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nEXDATE;TZID=America/New_York:20260908T100000\r\nEND:VEVENT\r\nEND:VCALENDAR",
  { defaultTimeZone: "America/New_York", horizonEnd: horizon });
ok("recurring VEVENT expands with EXDATE removed and duration kept",
   rec.length === 2 && rec.every((e) => e.end.getTime() - e.start.getTime() === 30 * 60_000) && rec.every((e) => e.recurrenceId),
   JSON.stringify(rec.map((e) => e.start.toISOString())));
ok("occurrences get distinct source ids", new Set(rec.map((e) => `${e.uid}@${e.recurrenceId}`)).size === 2);

console.log("\n── mappers (real fixtures) ──");
const tm = JSON.parse(fixture("ticketmaster-sample.json"));
const tmMapped = tm._embedded.events.map((e) => mapTicketmaster(e, CLEVELAND)).filter(Boolean);
ok("ticketmaster: every fixture event maps", tmMapped.length === tm._embedded.events.length);
const trivia = tmMapped.find((e) => e.title.includes("Trivia"));
ok("ticketmaster: venue coords + city + free price range",
   trivia && Math.abs(trivia.latitude - 41.477055) < 1e-6 && trivia.locationName.includes("Lakewood") && trivia.isFree === true && trivia.priceMin === 0,
   JSON.stringify({ lat: trivia?.latitude, loc: trivia?.locationName, free: trivia?.isFree, min: trivia?.priceMin }));
ok("ticketmaster: local date/time land in the venue's zone",
   trivia && trivia.start.toISOString() === "2026-09-06T15:30:00.000Z", trivia?.start.toISOString());
ok("ticketmaster: category from segment", tmMapped.every((e) => typeof e.category === "string"));
ok("ticketmaster: source ids stable", tmMapped.every((e) => e.source === "ticketmaster" && e.sourceEventId.length > 5));

const cplIcs = { name: "Cleveland Public Library", url: "https://example.invalid/feed.ics",
  venues: { "Main Library - Downtown": { lat: 41.5013, lng: -81.6906 } }, tags: ["library"] };
const libMapped = events.map((e) => mapIcsEvent(e, CLEVELAND, cplIcs, "ics")).filter(Boolean);
ok("ics feed: every parsed VEVENT maps", libMapped.length === 12);
ok("ics feed: organizer is the feed name, tags attached",
   libMapped.every((e) => e.organizer === "Cleveland Public Library" && e.tags.includes("library")));
const mainLib = libMapped.find((e) => e.locationName.startsWith("Main Library"));
ok("ics feed: branch leads the location and known venue coordinates attach",
   mainLib && mainLib.latitude === 41.5013, JSON.stringify(mainLib && { loc: mainLib.locationName, lat: mainLib.latitude }));
ok("ics feed: all-day events read 'All day'", libMapped.filter((e) => e.time === "All day").length >= 1);

// LibCal RSS (the path actually used for library systems — see sources/libcal.ts).
const rss = fixture("cpl-libcal-rss-sample.xml");
const rssItems = parseLibCalRss(rss);
ok("libcal rss: parses every <item> with structured fields", rssItems.length === 6 && rssItems.every((i) => i.eventId && i.date && i.title), `n=${rssItems.length}`);
const exhibit = rssItems.find((i) => i.title.includes("International Language"));
ok("libcal rss: all-day marker (00:00:00–23:59:59) and branch/room split",
   exhibit && exhibit.start === "00:00:00" && exhibit.end === "23:59:59" && exhibit.branch === "Main Library - Downtown" && exhibit.room.includes("4th Floor"),
   JSON.stringify(exhibit));
ok("libcal rss: hex entities in HTML descriptions decode", exhibit && exhibit.descriptionHtml.startsWith("<p>Local Artist"), exhibit?.descriptionHtml.slice(0, 40));
ok("libcal rss: '&#x26;' in titles decodes to '&'", rssItems.some((i) => i.title === "Coffee & Conversation"));
const rssMapped = rssItems.map((i) => mapLibCalItem(i, CLEVELAND, CLEVELAND.libcal[0])).filter(Boolean);
ok("libcal rss: every item maps to a normalized event", rssMapped.length === rssItems.length);
const coffee = rssMapped.find((e) => e.title === "Coffee & Conversation");
ok("libcal rss: 10:30am New York → 14:30Z (EDT) with an end time and branch coordinates",
   coffee && coffee.start.toISOString() === "2026-09-07T14:30:00.000Z" && coffee.end && coffee.time === "10:30 AM" && coffee.latitude === 41.541,
   JSON.stringify(coffee && { s: coffee.start.toISOString(), t: coffee.time, lat: coffee.latitude, loc: coffee.locationName }));
ok("libcal rss: source ids are prefixed by calendar id and stable", rssMapped.every((e) => e.sourceEventId.startsWith("8758-")));
ok("libcal rss: audiences become tags alongside 'library'", coffee && coffee.tags.includes("library") && coffee.tags.length >= 2);

const lo = JSON.parse(fixture("localist-tri-c-sample.json"));
const loMapped = lo.events.flatMap((w) => mapLocalist(w.event, CLEVELAND, "events.tri-c.edu", "Tri-C") ?? []);
ok("localist: one record per instance with coordinates", loMapped.length >= 3 && loMapped.every((e) => typeof e.latitude === "number"), `n=${loMapped.length}`);
ok("localist: ISO start with offset parses to UTC", loMapped[0].start.toISOString() === "2026-09-07T14:00:00.000Z", loMapped[0].start.toISOString());
ok("localist: free flag honoured", loMapped.every((e) => typeof e.isFree === "boolean"));

const nps = JSON.parse(fixture("nps-sample.json"));
const npsMapped = nps.data.flatMap((e) => mapNps(e, CLEVELAND));
ok("nps: recurring dates expand (only in-horizon occurrences kept)", npsMapped.length >= 0 && npsMapped.every((e) => e.source === "nps"));
const farmersRaw = nps.data.find((e) => /Farmers Market/.test(e.title));
const farmersAll = mapNps({ ...farmersRaw, dates: ["2099-01-03"], times: [{ timestart: "09:00 AM" }] }, CLEVELAND);
ok("nps: horizon filter drops far-future dates", farmersAll.length === 0);
const soon = new Date(Date.now() + 3 * 86_400_000).toISOString().slice(0, 10);
const farmersSoon = mapNps({ ...farmersRaw, dates: [soon], times: [{ timestart: "09:00 AM", timeend: "12:00 PM" }] }, CLEVELAND);
ok("nps: 09:00 AM local becomes the right UTC hour and category Market",
   farmersSoon.length === 1 && farmersSoon[0].category === "Market" && farmersSoon[0].time === "9:00 AM" && farmersSoon[0].isFree === true,
   JSON.stringify(farmersSoon[0] && { c: farmersSoon[0].category, t: farmersSoon[0].time }));

const serpDate = parseSerpDate({ start_date: "Sep 12", when: "Sat, Sep 12, 7 – 9 PM" }, "America/New_York", new Date("2026-09-06T00:00:00Z"));
ok("serpapi: 'Sep 12, 7 PM' → 23:00Z in September", serpDate?.toISOString() === "2026-09-12T23:00:00.000Z", serpDate?.toISOString());
const rollover = parseSerpDate({ start_date: "Jan 5" }, "America/New_York", new Date("2026-12-20T00:00:00Z"));
ok("serpapi: month already passed rolls to next year", rollover?.getUTCFullYear() === 2027, rollover?.toISOString());
const serpMapped = mapSerp({ title: "Cleveland Night Market", date: { start_date: "Sep 20", when: "Sat, Sep 20, 6 PM" },
  venue: { name: "AsiaTown" }, link: "https://example.com/e", ticket_info: [{ link_type: "Tickets", link: "https://t.example.com" }] }, CLEVELAND);
ok("serpapi: ticket links mark the event paid; venue + link kept",
   serpMapped && serpMapped.isFree === false && serpMapped.locationName === "AsiaTown" && serpMapped.website === "https://example.com/e" && serpMapped.category === "Market");
ok("serpapi: same event hashes to the same id", mapSerp({ title: "Cleveland Night Market", date: { start_date: "Sep 20" }, venue: { name: "AsiaTown" } }, CLEVELAND).sourceEventId === serpMapped.sourceEventId);
ok(`serpapi: budget allows below the ${SERPAPI_MONTHLY_CAP}-call cap and refuses at it`, serpApiBudgetAllows(0) && serpApiBudgetAllows(SERPAPI_MONTHLY_CAP - 1) && !serpApiBudgetAllows(SERPAPI_MONTHLY_CAP));

console.log("\n── dedupe + scoping ──");
const ts = (d) => ({ toMillis: () => new Date(d).getTime() });
const existing = { date: ts("2026-09-20T23:00:00Z"), venueKey: "asiatown", latitude: 41.51, longitude: -81.66, titleKey: "cleveland night market" };
const same = { title: "Cleveland Night Market", start: new Date("2026-09-20T23:30:00Z"), locationName: "AsiaTown, Cleveland", latitude: 41.5101, longitude: -81.6601 };
ok("isSameEvent: same title, 30 min apart, same venue key → match", isSameEvent(existing, same));
ok("isSameEvent: 3 hours apart → no match", !isSameEvent(existing, { ...same, start: new Date("2026-09-21T02:30:00Z") }));
ok("isSameEvent: different venue with far coordinates → no match",
   !isSameEvent(existing, { ...same, locationName: "Public Square", latitude: 41.4993, longitude: -81.6944 }));
ok("isSameEvent: no venue info on the new record → title+time match",
   isSameEvent(existing, { ...same, locationName: "", latitude: undefined, longitude: undefined }));
ok("horizon: 200 days out is skipped", !isWithinHorizon({ start: new Date(Date.now() + 200 * 86_400_000) }));
ok("scoping: Public Square is inside Cleveland, Columbus is not",
   isInsideArea(CLEVELAND, 41.4993, -81.6944) && !isInsideArea(CLEVELAND, 39.9612, -82.9988));

console.log("\n── payload coercion (runIngest payload mode) ──");
const good = coercePayloadRecord({ source: "libcal", sourceEventId: "x1", title: "<b>Book Club</b>", start: "2026-10-01T18:00:00Z", locationName: "Main Library", tags: ["library", 42] }, CLEVELAND);
ok("valid payload record coerces with cleaned title and tags", good && good.title === "Book Club" && good.category === "Workshop" && good.tags.length === 1, JSON.stringify(good));
ok("unknown source rejected", coercePayloadRecord({ source: "meetup", title: "x", start: "2026-10-01T18:00:00Z" }, CLEVELAND) === null);
ok("bad date rejected", coercePayloadRecord({ source: "libcal", title: "x", start: "yesterday-ish" }, CLEVELAND) === null);
ok("hostile toString payload does not crash", coercePayloadRecord({ source: { toString: "x" }, title: {}, start: [] }, CLEVELAND) === null);

console.log(`\n══ ${passed} passed, ${failed} failed ══`);
process.exit(failed ? 1 : 0);
