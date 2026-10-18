/**
 * Annotation — two fields every stored event carries, computed once at write
 * time, right after the frozen classifier (`enrichEvent`) has run:
 *
 *   adultOnly   true when the listing mentions alcohol service or an age limit,
 *               or an alcohol brand presents it; never missing. Structured age
 *               fields from the feed take precedence over free text. The rule
 *               errs toward TRUE: a false positive only hides an event from
 *               teens, a false negative shows a bar crawl to a 15-year-old.
 *   topicTags   John's 19-label keyword inference (CATEGORY_KEYWORDS in
 *               reference/verdure-discovery/verdure/models.py), whole-word
 *               matching exactly as his v3 does. These are NOT the existing
 *               `tags` field (feed tags, which drive the Volunteering category)
 *               and NOT `categories` (frozen classifier output).
 *
 * The six frozen classifier files are not touched; this module is additive.
 * Nothing here is called "enrich": enrichEvent already exists in classify.ts.
 */

import type { NormalizedEvent } from "./types.js";
import type { EnrichedEvent } from "./classify.js";

export interface AnnotatedEvent extends EnrichedEvent {
  adultOnly: boolean;
  adultOnlyReason: AdultOnlyReason | null;
  topicTags: TopicTag[];
}

// ── adultOnly ───────────────────────────────────────────────────────────────

/**
 * Alcohol service or age-limit language. Word-bounded; a few carefully chosen
 * exclusions keep children's programming out ("root beer floats", "ginger
 * beer", "apple cider" and "mocktails" are not alcohol).
 */
export const ALCOHOL_TERMS: readonly string[] = [
  "(?<!root |ginger |birch )beers?", "wines?", "winer(?:y|ies)", "wine tasting", "brewer(?:y|ies)", "brewpubs?", "craft brews?",
  "tasting rooms?", "(?<!mock)cocktails?", "happy hours?", "(?:bar|pub) crawls?", "beer gardens?", "biergartens?",
  "oktoberfest", "distiller(?:y|ies)", "hard seltzers?", "drink specials?", "bottomless mimosas?", "mimosas?", "sangria",
  "tequila", "whisk(?:e)?y", "vodka", "bourbon", "margaritas?", "boozy", "booze", "liquor", "last call",
];
// Each term is tested as a whole word; a lookbehind-heavy alternation cannot
// simply be wrapped in ..., so the guard is applied per term.
const wholeWord = (term: string) => `(?<![a-z])(?:${term})(?![a-z])`;
const ALCOHOL_WORDS = ALCOHOL_TERMS.map((w) => new RegExp(wholeWord(w), "i"));
export const ALCOHOL_PATTERN = new RegExp(ALCOHOL_TERMS.map(wholeWord).join("|"), "i");

/**
 * "21+", "18+", "(19+)", "ages 65+", "ages 21 and over", "must be 21", "18 years and older",
 * "adults only", "no one under 21", "ID required". Any stated minimum of 18 or
 * above is an age limit a minor cannot meet; the library systems' structured
 * audience labels ("Adults, ages 18+", "Seniors, ages 65+") are exactly this.
 */
const ADULT_AGE = "(?:1[89]|[2-9][0-9])";
export const AGE_LIMIT_PATTERN = new RegExp([
  // "18+", "(21+)", "ages 65+" — but not "20+ years of teaching"
  `(?<![0-9])${ADULT_AGE}\\s*\\+(?!\\s*(?:years?|yrs))`,
  // "ages 18 and up", "adults aged 18 and older", "adults, ages 21 or over", "ages 21 years of age and over" — the age cue AND the open-ended bound
  `\\b(?:ages?|aged|adults?,?\\s*ages?|adults? aged)\\s*${ADULT_AGE}\\b(?:\\s*years?(?:\\s*of age)?)?\\s*(?:and|&|or)\\s*(?:up|over|older)\\b`,
  // "must be 21", "must be at least 18", "minimum age 21"
  `\\b(?:must be(?: at least)?|minimum age(?: of| is)?)\\s*${ADULT_AGE}\\b`,
  // "no one under 21", "no minors under 18"
  `\\bno (?:one|minors?|guests?) under\\s*(?:the age of\\s*)?${ADULT_AGE}\\b`,
  // "adults only", "ID required"
  `\\badults?\\s*only\\b`, `\\bvalid (?:photo )?id required\\b`, `\\bid required\\b`,
].join("|"), "i");

/**
 * Brands that present or sponsor drinking events. Matched in the organizer and
 * in "presented by / sponsored by / brought to you by …" phrases, and anywhere
 * in the title (a "Modelo Kickoff" is a beer event). Lower-case, exact words.
 */
export const ALCOHOL_BRANDS: readonly string[] = [
  "modelo", "budweiser", "bud light", "coors", "miller lite", "miller high life", "heineken", "corona", "stella artois",
  "michelob", "pacifico", "dos equis", "lagunitas", "sierra nevada", "anchor steam", "firestone walker", "ballast point",
  "jack daniel's", "jack daniels", "jameson", "tito's", "titos", "smirnoff", "absolut", "grey goose", "bacardi",
  "captain morgan", "jose cuervo", "patrón", "patron tequila", "don julio", "hennessy", "jägermeister", "jagermeister",
  "white claw", "truly hard seltzer", "barefoot wine", "kendall-jackson", "josh cellars", "la crema", "robert mondavi",
  "high noon", "cutwater", "fireball", "guinness", "blue moon", "new belgium", "gordon biersch", "21st amendment",
];
const BRAND_PATTERNS = ALCOHOL_BRANDS.map((b) => new RegExp(`(?<![a-z])${b.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![a-z])`, "i"));
const PRESENTER_PATTERN = /\b(?:presented|sponsored|hosted|brought to you|powered)\s+by\s+([^.;,\n]{2,60})/gi;

/** Structured feed fields that carry an age limit: audiences, event types, tags. */
function structuredAgeLimit(rec: NormalizedEvent & { minimumAge?: number | null }): boolean | null {
  if (typeof rec.minimumAge === "number") return rec.minimumAge >= 18;
  const structured = [...(rec.audiences ?? []), ...(rec.eventTypes ?? []), ...rec.tags].join(" | ");
  if (!structured.trim()) return null;
  if (AGE_LIMIT_PATTERN.test(structured)) return true;
  return null;
}

export function mentionsAlcohol(text: string): boolean {
  const t = String(text ?? "");
  return ALCOHOL_WORDS.some((w) => w.test(t));
}

export function alcoholBrandPresents(rec: NormalizedEvent): boolean {
  const organizer = String(rec.organizer ?? "");
  const title = String(rec.title ?? "");
  if (BRAND_PATTERNS.some((p) => p.test(organizer) || p.test(title))) return true;
  const text = `${rec.title} ${rec.description}`;
  for (const m of text.matchAll(PRESENTER_PATTERN)) {
    if (BRAND_PATTERNS.some((p) => p.test(m[1]))) return true;
  }
  return false;
}

export type AdultOnlyReason = "structured-age-limit" | "age-limit" | "alcohol" | "alcohol-brand";

/**
 * Why a listing is adult-only, or null. Structured age fields win; otherwise
 * age-limit language, alcohol service or an alcohol brand presenting the event.
 * Stored alongside the flag so the share per source can be explained and so a
 * reason line can say "21+ event" rather than "adult only".
 */
export function adultOnlyReason(rec: NormalizedEvent & { minimumAge?: number | null }): AdultOnlyReason | null {
  if (structuredAgeLimit(rec) === true) return "structured-age-limit";
  const text = `${rec.title} ${rec.description}`;
  if (AGE_LIMIT_PATTERN.test(text)) return "age-limit";
  if (mentionsAlcohol(text)) return "alcohol";
  if (alcoholBrandPresents(rec)) return "alcohol-brand";
  return null;
}

/** The adultOnly decision. Always a boolean so the client's `adultOnly == false` filter can match every document. */
export function inferAdultOnly(rec: NormalizedEvent & { minimumAge?: number | null }): boolean {
  return adultOnlyReason(rec) !== null;
}

// ── topicTags — port of models.py: CATEGORY_KEYWORDS / infer_categories() ───

export type TopicTag =
  | "family" | "kids" | "music" | "arts" | "education" | "outdoors" | "volunteer" | "sports" | "fitness"
  | "food" | "community" | "campus" | "tech" | "social" | "film" | "theater" | "workshop" | "civic" | "other";

/** Port of models.py: CATEGORIES */
export const TOPIC_TAGS: readonly TopicTag[] = [
  "family", "kids", "music", "arts", "education", "outdoors", "volunteer", "sports", "fitness",
  "food", "community", "campus", "tech", "social", "film", "theater", "workshop", "civic", "other",
];

/** Port of models.py: CATEGORY_KEYWORDS (verbatim). */
export const CATEGORY_KEYWORDS: Record<Exclude<TopicTag, "community" | "campus" | "other">, string[]> = {
  kids: ["storytime", "story time", "toddler", "preschool", "children", "kids", "baby"],
  family: ["family", "all ages", "parents"],
  music: ["concert", "music", "band", "live music", "jazz", "orchestra", "dj", "choir"],
  arts: ["art", "gallery", "exhibit", "painting", "craft"],
  outdoors: ["hike", "walk", "preserve", "trail", "nature", "naturalist", "birding", "park"],
  volunteer: ["volunteer", "cleanup", "clean-up", "restoration"],
  education: ["lecture", "talk", "class", "seminar", "tutoring", "lesson"],
  workshop: ["workshop", "hands-on"],
  sports: ["game", "match", "tournament", "basketball", "soccer", "baseball"],
  fitness: ["yoga", "run", "running", "5k", "fitness", "workout", "climbing"],
  food: ["farmers market", "food", "tasting", "cooking"],
  tech: ["hackathon", "coding", "tech", "technology", "robotics", "ai", "programming"],
  film: ["film", "movie", "screening"],
  theater: ["theater", "theatre", "play", "musical"],
  civic: ["city council", "town hall", "public meeting", "civic"],
  social: ["meetup", "mixer", "social", "networking"],
};

const escapeRegExp = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** Port of models.py: _CATEGORY_PATTERNS — whole-word, optional plural "s", so "art" never matches "start" or "party" and "ai" never matches "Thai". */
export const CATEGORY_PATTERNS: Record<string, RegExp> = Object.fromEntries(
  Object.entries(CATEGORY_KEYWORDS).map(([cat, words]) => [cat, new RegExp(`\\b(?:${words.map(escapeRegExp).join("|")})s?\\b`, "i")]),
);
/** Port of models.py: _DESCRIPTION_IGNORED — a "Coding Club" that mentions building small games is not a sports event. */
export const DESCRIPTION_IGNORED: ReadonlySet<string> = new Set(["sports", "theater"]);

/** Port of models.py: infer_categories(title, description, default). A source's own category labels go in with the TITLE (strong signal), not the description. */
export function inferTopicTags(title: string, description: string, fallback?: TopicTag): TopicTag[] {
  const titleL = String(title ?? "").toLowerCase();
  const descL = String(description ?? "").toLowerCase();
  const found: TopicTag[] = [];
  for (const [cat, pattern] of Object.entries(CATEGORY_PATTERNS)) if (pattern.test(titleL)) found.push(cat as TopicTag);
  for (const [cat, pattern] of Object.entries(CATEGORY_PATTERNS)) {
    if (!found.includes(cat as TopicTag) && !DESCRIPTION_IGNORED.has(cat) && pattern.test(descL)) found.push(cat as TopicTag);
  }
  if (!found.length && fallback) found.push(fallback);
  return found.length ? found : ["other"];
}

/** Port of config.yaml `default_category` per source: John uses campus for the universities and community for library iCal feeds. */
export const SOURCE_DEFAULT_TOPIC: Partial<Record<string, TopicTag>> = {
  localist: "campus", livewhale: "campus", bibliocommons: "community", libcal: "community", ics: "community",
  midpen: "outdoors", legistar: "civic",
};

/**
 * John's 19 labels mapped onto the app's interest vocabulary (the keys of
 * INTEREST_TO_CATEGORY in ranking.ts). Kept in code, never stored: it is a
 * product decision, not data. Several labels fold into one interest.
 */
export const TOPIC_TO_INTEREST: Record<TopicTag, string[]> = {
  kids: ["family"], family: ["family"], music: ["music"], arts: ["arts"], theater: ["arts"], film: ["arts"],
  education: ["learning"], workshop: ["learning"], campus: ["learning"], tech: ["tech"],
  outdoors: ["outdoors"], volunteer: ["volunteering"], sports: ["fitness"], fitness: ["fitness"],
  food: ["food"], community: ["community"], civic: ["community"], social: ["community"], other: [],
};

/** App interests a tag list speaks to, deduplicated and ordered by first appearance. */
export function interestsForTopics(tags: readonly string[]): string[] {
  const out: string[] = [];
  for (const tag of tags) for (const interest of TOPIC_TO_INTEREST[tag as TopicTag] ?? []) if (!out.includes(interest)) out.push(interest);
  return out;
}

/** The structured labels that join the title as John's "source's own category labels". */
function structuredLabels(rec: NormalizedEvent): string {
  return [...(rec.eventTypes ?? []), ...rec.tags.filter((t) => !/^(library|google-events)$/i.test(t))].join(" ");
}

// ── The one call upsertBatch makes ──────────────────────────────────────────

/** Add adultOnly and topicTags to an enriched event. Pure; identical for fresh ingest and backfill. */
export function annotateEvent(rec: EnrichedEvent & { minimumAge?: number | null }): AnnotatedEvent {
  const fallback = SOURCE_DEFAULT_TOPIC[rec.source];
  const topicTags = inferTopicTags(`${rec.title} ${structuredLabels(rec)}`, rec.description, fallback);
  const reason = adultOnlyReason(rec);
  return { ...rec, adultOnly: reason !== null, adultOnlyReason: reason, topicTags };
}
