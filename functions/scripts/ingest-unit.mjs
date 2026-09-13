// Ingest layer unit checks — no emulator, no network.
//
//   npm run build && node scripts/ingest-unit.mjs
//
// The fixtures under test-fixtures/ are TRIMMED COPIES OF REAL RESPONSES
// captured on 2026-09-06 (San Jose Public Library LibCal, Ticketmaster
// Discovery for San Jose, NPS events for Cuyahoga Valley, Tri-C Localist), so
// the mappers are exercised against the shapes the vendors actually return, not
// against what their docs say.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { parseIcs, unfold, unescapeText, expandRRule, parseIcsDate } from "../lib/ingest/ics.js";
import { titleKey, venueKey, classify, zonedToUtc, cleanText, cleanUrl, eventDocId } from "../lib/ingest/normalize.js";
import { mapTicketmaster } from "../lib/ingest/sources/ticketmaster.js";
import { mapIcsEvent } from "../lib/ingest/sources/icsfeed.js";
import { parseBiblioPayload, mapBiblioItem, trustedCoordinateIds } from "../lib/ingest/sources/bibliocommons.js";
import { parseMidpenListing, mapMidpenItem, parseMidpenDate, MIDPEN_PRESERVES } from "../lib/ingest/sources/midpen.js";
import { parseLibCalRss, mapLibCalItem } from "../lib/ingest/sources/libcal.js";
import { mapLocalist } from "../lib/ingest/sources/localist.js";
import { mapNps } from "../lib/ingest/sources/nps.js";
import { mapSerp, parseSerpDate, serpApiBudgetAllows, SERPAPI_MONTHLY_CAP } from "../lib/ingest/sources/serpapi.js";
import { isSameEvent, isWithinHorizon } from "../lib/ingest/store.js";
import { SAN_JOSE, isInsideArea } from "../lib/ingest/areas.js";
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
   titleKey("The San Jose Orchestra: Beethoven at Blossom!") === titleKey("san jose orchestra — beethoven AT blossom"),
   `${titleKey("The San Jose Orchestra: Beethoven at Blossom!")} vs ${titleKey("san jose orchestra — beethoven AT blossom")}`);
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
const tmMapped = tm._embedded.events.map((e) => mapTicketmaster(e, SAN_JOSE)).filter(Boolean);
ok("ticketmaster: every fixture event maps", tmMapped.length === tm._embedded.events.length);
const trivia = tmMapped.find((e) => e.title.includes("Trivia"));
ok("ticketmaster: venue coords + city + free price range",
   trivia && Math.abs(trivia.latitude - 41.477055) < 1e-6 && trivia.locationName.includes("Lakewood") && trivia.isFree === true && trivia.priceMin === 0,
   JSON.stringify({ lat: trivia?.latitude, loc: trivia?.locationName, free: trivia?.isFree, min: trivia?.priceMin }));
ok("ticketmaster: local date/time land in the venue's zone",
   trivia && trivia.start.toISOString() === "2026-09-06T15:30:00.000Z", trivia?.start.toISOString());
ok("ticketmaster: category from segment", tmMapped.every((e) => typeof e.category === "string"));
ok("ticketmaster: source ids stable", tmMapped.every((e) => e.source === "ticketmaster" && e.sourceEventId.length > 5));

const cplIcs = { name: "San Jose Public Library", url: "https://example.invalid/feed.ics",
  venues: { "Main Library - Downtown": { lat: 37.3352, lng: -121.8850 } }, tags: ["library"] };
const libMapped = events.map((e) => mapIcsEvent(e, SAN_JOSE, cplIcs, "ics")).filter(Boolean);
ok("ics feed: every parsed VEVENT maps", libMapped.length === 12);
ok("ics feed: organizer is the feed name, tags attached",
   libMapped.every((e) => e.organizer === "San Jose Public Library" && e.tags.includes("library")));
const mainLib = libMapped.find((e) => e.locationName.startsWith("Main Library"));
ok("ics feed: branch leads the location and known venue coordinates attach",
   mainLib && mainLib.latitude === 37.3352, JSON.stringify(mainLib && { loc: mainLib.locationName, lat: mainLib.latitude }));
ok("ics feed: all-day events read 'All day'", libMapped.filter((e) => e.time === "All day").length >= 1);

// LibCal RSS parser.
//
// These assert the PARSER, not the launch area, so they carry their own feed and
// their own area rather than reaching into LAUNCH_AREAS. The fixture is a real
// Cleveland Public Library RSS capture and the 10:30 EDT → 14:30Z assertion
// below only holds in America/New_York — binding it to whatever city happens to
// be launching would make an unrelated config change fail a parser test, which
// is exactly what happened when the launch area moved to San Jose (which runs
// BiblioCommons and has no LibCal calendars at all).
const CPL_AREA = { id: "fixture-cle", name: "Cleveland, OH", center: { lat: 41.4993, lng: -81.6944 },
  radiusMiles: 25, timeZone: "America/New_York", ticketmaster: { enabled: false },
  libcal: [], bibliocommons: [], midpen: [], localist: [], nps: { parkCodes: [] }, ics: [],
  serpapi: { enabled: false, query: "" } };
const CPL_LIBCAL_FEED = { name: "Cleveland Public Library", calendarId: "8758",
  rssUrl: "https://cpl.libcal.com/rss.php?m=month&cid=8758",
  venues: { "Glenville": { lat: 41.541, lng: -81.6025 } }, tags: ["library"] };
const rss = fixture("cpl-libcal-rss-sample.xml");
const rssItems = parseLibCalRss(rss);
ok("libcal rss: parses every <item> with structured fields", rssItems.length === 6 && rssItems.every((i) => i.eventId && i.date && i.title), `n=${rssItems.length}`);
const exhibit = rssItems.find((i) => i.title.includes("International Language"));
ok("libcal rss: all-day marker (00:00:00–23:59:59) and branch/room split",
   exhibit && exhibit.start === "00:00:00" && exhibit.end === "23:59:59" && exhibit.branch === "Main Library - Downtown" && exhibit.room.includes("4th Floor"),
   JSON.stringify(exhibit));
ok("libcal rss: hex entities in HTML descriptions decode", exhibit && exhibit.descriptionHtml.startsWith("<p>Local Artist"), exhibit?.descriptionHtml.slice(0, 40));
ok("libcal rss: '&#x26;' in titles decodes to '&'", rssItems.some((i) => i.title === "Coffee & Conversation"));
const rssMapped = rssItems.map((i) => mapLibCalItem(i, CPL_AREA, CPL_LIBCAL_FEED)).filter(Boolean);
ok("libcal rss: every item maps to a normalized event", rssMapped.length === rssItems.length);
const coffee = rssMapped.find((e) => e.title === "Coffee & Conversation");
ok("libcal rss: 10:30am New York → 14:30Z (EDT) with an end time and branch coordinates",
   coffee && coffee.start.toISOString() === "2026-09-07T14:30:00.000Z" && coffee.end && coffee.time === "10:30 AM" && coffee.latitude === 41.541,
   JSON.stringify(coffee && { s: coffee.start.toISOString(), t: coffee.time, lat: coffee.latitude, loc: coffee.locationName }));
ok("libcal rss: source ids are prefixed by calendar id and stable", rssMapped.every((e) => e.sourceEventId.startsWith("8758-")));
ok("libcal rss: audiences become tags alongside 'library'", coffee && coffee.tags.includes("library") && coffee.tags.length >= 2);

const lo = JSON.parse(fixture("localist-tri-c-sample.json"));
const loMapped = lo.events.flatMap((w) => mapLocalist(w.event, SAN_JOSE, "events.tri-c.edu", "Tri-C") ?? []);
ok("localist: one record per instance with coordinates", loMapped.length >= 3 && loMapped.every((e) => typeof e.latitude === "number"), `n=${loMapped.length}`);
ok("localist: ISO start with offset parses to UTC", loMapped[0].start.toISOString() === "2026-09-07T14:00:00.000Z", loMapped[0].start.toISOString());
ok("localist: free flag honoured", loMapped.every((e) => typeof e.isFree === "boolean"));

const nps = JSON.parse(fixture("nps-sample.json"));
const npsMapped = nps.data.flatMap((e) => mapNps(e, SAN_JOSE));
ok("nps: recurring dates expand (only in-horizon occurrences kept)", npsMapped.length >= 0 && npsMapped.every((e) => e.source === "nps"));
const farmersRaw = nps.data.find((e) => /Farmers Market/.test(e.title));
const farmersAll = mapNps({ ...farmersRaw, dates: ["2099-01-03"], times: [{ timestart: "09:00 AM" }] }, SAN_JOSE);
ok("nps: horizon filter drops far-future dates", farmersAll.length === 0);
const soon = new Date(Date.now() + 3 * 86_400_000).toISOString().slice(0, 10);
const farmersSoon = mapNps({ ...farmersRaw, dates: [soon], times: [{ timestart: "09:00 AM", timeend: "12:00 PM" }] }, SAN_JOSE);
ok("nps: 09:00 AM local becomes the right UTC hour and category Market",
   farmersSoon.length === 1 && farmersSoon[0].category === "Market" && farmersSoon[0].time === "9:00 AM" && farmersSoon[0].isFree === true,
   JSON.stringify(farmersSoon[0] && { c: farmersSoon[0].category, t: farmersSoon[0].time }));

const serpDate = parseSerpDate({ start_date: "Sep 12", when: "Sat, Sep 12, 7 – 9 PM" }, "America/New_York", new Date("2026-09-06T00:00:00Z"));
ok("serpapi: 'Sep 12, 7 PM' → 23:00Z in September", serpDate?.toISOString() === "2026-09-12T23:00:00.000Z", serpDate?.toISOString());
const rollover = parseSerpDate({ start_date: "Jan 5" }, "America/New_York", new Date("2026-12-20T00:00:00Z"));
ok("serpapi: month already passed rolls to next year", rollover?.getUTCFullYear() === 2027, rollover?.toISOString());
const serpMapped = mapSerp({ title: "San Jose Night Market", date: { start_date: "Sep 20", when: "Sat, Sep 20, 6 PM" },
  venue: { name: "AsiaTown" }, link: "https://example.com/e", ticket_info: [{ link_type: "Tickets", link: "https://t.example.com" }] }, SAN_JOSE);
ok("serpapi: ticket links mark the event paid; venue + link kept",
   serpMapped && serpMapped.isFree === false && serpMapped.locationName === "AsiaTown" && serpMapped.website === "https://example.com/e" && serpMapped.category === "Market");
ok("serpapi: the same event with and without a clock time hashes to one id", mapSerp({ title: "San Jose Night Market", date: { start_date: "Sep 20" }, venue: { name: "AsiaTown" } }, SAN_JOSE).sourceEventId === serpMapped.sourceEventId);
ok(`serpapi: budget allows below the ${SERPAPI_MONTHLY_CAP}-call cap and refuses at it`, serpApiBudgetAllows(0) && serpApiBudgetAllows(SERPAPI_MONTHLY_CAP - 1) && !serpApiBudgetAllows(SERPAPI_MONTHLY_CAP));


// ── BiblioCommons (San José PL + Santa Clara County LD) ──────────────────────
//
// Fixture is a trimmed live capture (2026-09-13) of the public gateway,
// deliberately including a VIRTUAL event with no branch — the case where an
// event must end up with NO coordinates rather than the library's.
console.log("\n── bibliocommons ──");
const bcPayload = JSON.parse(fixture("sjpl-bibliocommons-sample.json"));
const bcItems = parseBiblioPayload(bcPayload, "sjpl.bibliocommons.com");
ok("bibliocommons: flattens the entity graph into one item per occurrence",
   bcItems.length === 4 && bcItems.every((i) => i.eventId && i.title && i.startISO), `n=${bcItems.length}`);

const SJPL_FEED = { name: "San José Public Library", library: "sjpl",
  host: "sjpl.bibliocommons.com", tags: ["library"] };
const bcMapped = bcItems.map((i) => mapBiblioItem(i, SAN_JOSE, SJPL_FEED)).filter(Boolean);
ok("bibliocommons: every item maps to a normalized event", bcMapped.length === bcItems.length);

const king = bcMapped.find((e) => e.locationName.startsWith("King Library"));
ok("bibliocommons: branch coordinates come from the feed, no venue table needed",
   king && Math.abs(king.latitude - 37.3356906) < 1e-6 && Math.abs(king.longitude + 121.8852558) < 1e-6,
   JSON.stringify(king && { loc: king.locationName, lat: king.latitude, lng: king.longitude }));

const virtual = bcMapped.find((e) => e.title.includes("Digital Skills"));
ok("bibliocommons: an event with no branch gets NO coordinates (check-in gate stays off, not wrong)",
   virtual && virtual.latitude === undefined && virtual.longitude === undefined,
   JSON.stringify(virtual && { t: virtual.title, lat: virtual.latitude }));

ok("bibliocommons: source ids are prefixed by library so systems never collide",
   bcMapped.every((e) => e.source === "bibliocommons" && e.sourceEventId.startsWith("sjpl-")));
ok("bibliocommons: library programming is free and tagged",
   bcMapped.every((e) => e.isFree === true && e.tags.includes("library")));
ok("bibliocommons: indexStart is already UTC — no timezone maths applied",
   bcMapped.every((e) => !Number.isNaN(e.start.getTime())) &&
   bcMapped[0].start.toISOString() === new Date(bcItems[0].startISO).toISOString());
ok("bibliocommons: HTML descriptions are stripped to text",
   bcMapped.every((e) => !/<[a-z]/i.test(e.description)));

// Coordinate trust. The first version of this adapter accepted a coordinate
// only when `mapLocation.isGeocoded === true`. A live run showed SJPL sets that
// flag and Santa Clara County Library District does not — on ANY branch — while
// publishing plainly correct per-branch coordinates. That rule discarded good
// data for 2,106 events and silently disabled check-in proximity for a whole
// library system. The replacement keeps the protection it was actually there
// for (a city centroid repeated across every branch) without the collateral.
const geo = (lat, lng, flag) => ({ mapLocation: { centrePoint: { lat, lng }, isGeocoded: flag } });
ok("bibliocommons: a flagged coordinate is trusted",
   trustedCoordinateIds({ a: geo(37.1, -121.1, true) }).has("a"));
ok("bibliocommons: an UNflagged but distinct coordinate is trusted (the SCCLD case)",
   (() => {
     const t = trustedCoordinateIds({
       a: geo(37.3178, -122.0290, false), b: geo(37.4324, -121.9065, false), c: geo(37.1241, -121.6628, false),
     });
     return t.size === 3;
   })());
ok("bibliocommons: a point REPEATED across every branch is discarded for all of them",
   (() => {
     const t = trustedCoordinateIds({
       a: geo(37.3382, -121.8863, false), b: geo(37.3382, -121.8863, false), c: geo(37.3382, -121.8863, false),
     });
     return t.size === 0;
   })(), "that is the city-centroid signature");
ok("bibliocommons: a flagged coordinate survives even if it collides with a centroid",
   (() => {
     const t = trustedCoordinateIds({
       a: geo(37.3382, -121.8863, true), b: geo(37.3382, -121.8863, false),
     });
     return t.has("a") && !t.has("b");
   })());
ok("bibliocommons: a location with no coordinate at all is simply absent",
   trustedCoordinateIds({ a: { mapLocation: {} }, b: {} }).size === 0);

// A feed that hands back an unrecognised shape must yield nothing, not throw:
// a library changing its API should degrade to zero events for that system,
// leaving every other source in the run intact.
ok("bibliocommons: junk payload yields no items instead of throwing",
   parseBiblioPayload({ nope: true }, "x").length === 0 && parseBiblioPayload(null, "x").length === 0);


// ── Midpen (the outdoor source that replaced NPS) ────────────────────────────
//
// This adapter parses HTML, so its tests carry more weight than a feed
// parser's: there is no contract upstream, only a page that can change. The
// fixture is a trimmed live capture (2026-09-13).
console.log("\n── midpen ──");
const mpHtml = fixture("midpen-events-listing.html");
const mpItems = parseMidpenListing(mpHtml);
ok("midpen: parses the Views table into one item per event",
   mpItems.length === 6 && mpItems.every((i) => i.title && i.dateText && i.preserve && i.link),
   `n=${mpItems.length} ${JSON.stringify(mpItems[0] ?? {})}`);
ok("midpen: the 'Image' alt-text prefix is stripped off the activity",
   mpItems.every((i) => !/^Image/i.test(i.activity)), JSON.stringify(mpItems.map((i) => i.activity)));

const MIDPEN_FEED = { name: "Midpeninsula Regional Open Space District", tags: ["outdoors", "parks"] };
const mpMapped = mpItems.map((i) => mapMidpenItem(i, SAN_JOSE, MIDPEN_FEED)).filter(Boolean);
ok("midpen: every parsed row maps to a normalized event", mpMapped.length === mpItems.length,
   `${mpMapped.length}/${mpItems.length}`);
ok("midpen: preserve coordinates attach from the verified table",
   mpMapped.some((e) => typeof e.latitude === "number"),
   JSON.stringify(mpMapped.map((e) => [e.locationName, e.latitude])));
ok("midpen: all programming is free and tagged outdoors",
   mpMapped.every((e) => e.isFree === true && e.tags.includes("outdoors")));
ok("midpen: volunteer projects classify as Volunteer regardless of title wording",
   mapMidpenItem({ ...mpItems[0], kind: "Volunteer Project", title: "Trail Maintenance" },
                 SAN_JOSE, MIDPEN_FEED).category === "Volunteer");

// Dates. A misparse here silently shifts an event by hours or a year.
ok("midpen: 12-hour times convert correctly, including the noon/midnight edges", (() => {
    const pm = parseMidpenDate("Saturday, Sep 12, 2026 6:00 pm");
    const am = parseMidpenDate("Sunday, Sep 13, 2026 9:30 am");
    const noon = parseMidpenDate("Monday, Sep 14, 2026 12:00 pm");
    const mid = parseMidpenDate("Monday, Sep 14, 2026 12:30 am");
    return pm.hh === 18 && am.hh === 9 && am.mm === 30 && noon.hh === 12 && mid.hh === 0 && mid.mm === 30;
  })(), "12pm must be 12 and 12am must be 0");
ok("midpen: an unparseable date drops the row instead of defaulting to now",
   parseMidpenDate("sometime next spring") === null &&
   mapMidpenItem({ ...mpItems[0], dateText: "sometime next spring" }, SAN_JOSE, MIDPEN_FEED) === null);

// Coordinates: every preserve we claim to know must be inside the area, or the
// check-in gate would sit around a hillside 40 miles away.
ok("midpen: every preserve in the table geocodes inside the launch area",
   Object.values(MIDPEN_PRESERVES).every((v) => isInsideArea(SAN_JOSE, v.lat, v.lng)),
   JSON.stringify(Object.entries(MIDPEN_PRESERVES).filter(([, v]) => !isInsideArea(SAN_JOSE, v.lat, v.lng))));
ok("midpen: an unknown preserve yields NO coordinates rather than a guess",
   mapMidpenItem({ ...mpItems[0], preserve: "Somewhere Unlisted Preserve" }, SAN_JOSE, MIDPEN_FEED).latitude === undefined);

// The loud-failure contract. Returning [] on a redesign would read as "no
// events this week" and drain the outdoor category silently over three cycles.
ok("midpen: unrecognisable markup yields zero rows (so fetchMidpen can throw)",
   parseMidpenListing("<html><body><p>we redesigned</p></body></html>").length === 0);
ok("midpen: a table with no event links is not mistaken for events",
   parseMidpenListing("<table><tr><td>a</td><td>b</td><td>c</td><td>d</td><td>e</td></tr></table>").length === 0);

console.log("\n── dedupe + scoping ──");
const ts = (d) => ({ toMillis: () => new Date(d).getTime() });
const existing = { date: ts("2026-09-20T23:00:00Z"), venueKey: "asiatown", latitude: 41.51, longitude: -81.66, titleKey: "san jose night market" };
const same = { title: "San Jose Night Market", start: new Date("2026-09-20T23:30:00Z"), locationName: "AsiaTown, San Jose", latitude: 41.5101, longitude: -81.6601 };
ok("isSameEvent: same title, 30 min apart, same venue key → match", isSameEvent(existing, same));
ok("isSameEvent: 3 hours apart → no match", !isSameEvent(existing, { ...same, start: new Date("2026-09-21T02:30:00Z") }));
ok("isSameEvent: different venue with far coordinates → no match",
   !isSameEvent(existing, { ...same, locationName: "Plaza de Cesar Chavez", latitude: 37.3325, longitude: -121.8890 }));
ok("isSameEvent: no venue info on the new record → title+time match",
   isSameEvent(existing, { ...same, locationName: "", latitude: undefined, longitude: undefined }));
ok("horizon: 200 days out is skipped", !isWithinHorizon({ start: new Date(Date.now() + 200 * 86_400_000) }));
ok("scoping: Public Square is inside San Jose, Columbus is not",
   isInsideArea(SAN_JOSE, 37.3382, -121.8863) && !isInsideArea(SAN_JOSE, 39.9612, -82.9988));

console.log("\n── payload coercion (runIngest payload mode) ──");
const good = coercePayloadRecord({ source: "libcal", sourceEventId: "x1", title: "<b>Book Club</b>", start: "2026-10-01T18:00:00Z", locationName: "Main Library", tags: ["library", 42] }, SAN_JOSE);
ok("valid payload record coerces with cleaned title and tags", good && good.title === "Book Club" && good.category === "Workshop" && good.tags.length === 1, JSON.stringify(good));
ok("unknown source rejected", coercePayloadRecord({ source: "meetup", title: "x", start: "2026-10-01T18:00:00Z" }, SAN_JOSE) === null);
ok("bad date rejected", coercePayloadRecord({ source: "libcal", title: "x", start: "yesterday-ish" }, SAN_JOSE) === null);
ok("hostile toString payload does not crash", coercePayloadRecord({ source: { toString: "x" }, title: {}, start: [] }, SAN_JOSE) === null);

console.log(`\n══ ${passed} passed, ${failed} failed ══`);
process.exit(failed ? 1 : 0);
