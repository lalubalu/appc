/**
 * Deterministic classification and enrichment for the frozen San José feeds.
 * Source tags from BiblioCommons and Localist are structured metadata, not
 * just words in a description. Unknowns stay explicit for review.
 */

import type { EventCategory, NormalizedEvent } from "./types.js";

export type CostKind = "free" | "paid" | "unknown";
export type AgeSuitability = "all" | "children" | "teens" | "adults" | "unknown";

export interface EnrichedEvent extends NormalizedEvent {
  categories: string[];
  classificationConfidence: number;
  qualityScore: number;
  inferredCost: CostKind;
  ageSuitability: AgeSuitability;
  endInferred: boolean;
}

type CategoryRule = { category: EventCategory; pattern: RegExp };
const RULES: CategoryRule[] = [
  { category: "Cleanup", pattern: /\b(?:clean[ -]?up|litter|trash pick|creek clean|beach clean)\b/i },
  { category: "Volunteer", pattern: /\b(?:volunteer(?:ing)?|stewardship|restoration|service day|give back|internship|food drive|trail maintenance|habitat restoration|broom removal)\b/i },
  { category: "Hackathon", pattern: /\b(?:hackathon|hack night|code jam|devfest)\b/i },
  { category: "Workshop", pattern: /\b(?:workshop|class|clinic|bootcamp|intro(?:duction)? to|learn to|hands[ -]?on|maker|lab|training|story\s?time|coding|3d printing|seminar)\b/i },
  { category: "Market", pattern: /\b(?:farmers? market|flea market|craft fair|bazaar|swap meet|book sale)\b/i },
  { category: "Festival", pattern: /\b(?:festival|concert|live music|comedy show|theat(?:er|re)|orchestra|symphony|parade|film screening)\b/i },
  { category: "Sports", pattern: /\b(?:sports?|hike|hiking|trail walk|nature walk|birding|marathon|race|yoga|cycling|soccer|basketball|pickleball|kayak(?:ing)?|swim(?:ming)?)\b/i },
  { category: "Meetup", pattern: /\b(?:meetup|meet up|mixer|networking|club meeting|book club|quiz club|advisory group|public meeting|community gathering)\b/i },
];

/** Feed event-type fields are a stronger signal than incidental description words. */
const STRUCTURED_RULES: CategoryRule[] = [
  { category: "Workshop", pattern: /\b(?:storytimes?|learning|classes?|seminars?|lectures?|technology & innovation|arts, crafts, & how-to|life skills)\b/i },
  { category: "Festival", pattern: /\b(?:performance|concerts?|exhibitions?|dance|music)\b/i },
  { category: "Sports", pattern: /\b(?:health & fitness|hikes?|outdoor recreation)\b/i },
  { category: "Meetup", pattern: /\b(?:clubs?|social events and gatherings|community meetings?)\b/i },
  { category: "Volunteer", pattern: /\b(?:volunteer opportunities|community service)\b/i },
];

const FAMILY = /\b(?:family|families|children|kids?|toddler|preschool|baby|babies|story\s?time|all ages)\b/i;
const YOUTH = /\b(?:teens?|youth|students?|high school|middle school)\b/i;
const ADULT = /\b(?:adults? only|ages? 18\+|21\+)\b/i;
const OUTDOORS = /\b(?:outdoors?|hike|trail|nature walk|birding|wildflower|preserve|park walk|creek)\b/i;
const INDOORS = /\b(?:indoors?|library|museum|gallery|classroom|auditorium)\b/i;
const OPPORTUNITY = /\b(?:volunteer|internship|career|job search|resume|service day|stewardship|workshop|class|clinic|training|bootcamp)\b/i;

/** Category priors reflect what a feed can actually guarantee. */
function sourcePrior(rec: NormalizedEvent): { category: EventCategory; confidence: number } {
  switch (rec.source) {
  case "midpen": return { category: "Sports", confidence: 0.78 };
  case "legistar": return { category: "Meetup", confidence: 0.88 };
  case "ticketmaster": return { category: rec.category, confidence: 0.72 };
  case "bibliocommons":
  case "libcal": return { category: rec.category, confidence: 0.56 };
  case "localist":
  case "livewhale": return { category: rec.category, confidence: 0.58 };
  default: return { category: rec.category, confidence: 0.55 };
  }
}

function inferCost(rec: NormalizedEvent): CostKind {
  if (rec.priceMin !== undefined) return rec.priceMin <= 0 ? "free" : "paid";
  if (rec.isFree === true) return "free";
  if (rec.isFree === false) return "paid";
  if (/\bfree\b|no cost|no admission fee/i.test(`${rec.title} ${rec.description}`)) return "free";
  if (/\$\s?\d|ticket(?:s)? required|admission fee|registration fee/i.test(`${rec.title} ${rec.description}`)) return "paid";
  if (["bibliocommons", "libcal", "midpen", "legistar"].includes(rec.source)) return "free";
  return "unknown";
}

function inferAge(text: string): AgeSuitability {
  if (ADULT.test(text)) return "adults";
  if (/\ball ages\b|everyone welcome|open to all/i.test(text)) return "all";
  if (YOUTH.test(text)) return "teens";
  if (FAMILY.test(text)) return "children";
  return "unknown";
}

/** One pure operation used identically by fresh ingest and corpus backfill. */
export function enrichEvent(rec: NormalizedEvent): EnrichedEvent {
  const title = rec.title;
  const structured = rec.tags.join(" ");
  const text = `${title} ${rec.description}`;
  const allText = `${title} ${structured} ${rec.description}`;
  const prior = sourcePrior(rec);
  const scores = new Map<EventCategory, number>([[prior.category, prior.confidence]]);
  for (const rule of STRUCTURED_RULES) {
    if (rule.pattern.test(structured)) {
      const structuredConfidence = rule.category === "Workshop" ? 0.9 : 0.86;
      scores.set(rule.category, Math.max(structuredConfidence, scores.get(rule.category) ?? 0));
    }
  }
  for (const rule of RULES) {
    let confidence = 0;
    if (rule.pattern.test(title)) confidence = 0.94;
    else if (rule.pattern.test(structured)) confidence = 0.88;
    else if (rule.pattern.test(rec.description)) {
      // A volunteer leading a class does not make the class a volunteer
      // opportunity. Description-only volunteering needs an invitation to act.
      confidence = rule.category === "Volunteer" &&
        !/\b(?:volunteer(?:ing)? opportunities?|join (?:us|our) (?:volunteer|stewardship)|sign up to volunteer|volunteers? needed)\b/i.test(rec.description)
        ? 0 : 0.68;
    }
    if (confidence) scores.set(rule.category, Math.max(confidence, scores.get(rule.category) ?? 0));
  }
  // Midpen's volunteer projects often mention an interpretive hike too. The
  // work to be done defines the primary purpose; retain Outdoors as a label.
  if (rec.source === "midpen" && rec.category === "Volunteer") {
    scores.set("Volunteer", Math.max(0.97, scores.get("Volunteer") ?? 0));
  }
  if (/\bstory\s?time\b/i.test(`${title} ${structured}`)) {
    scores.set("Workshop", Math.max(0.97, scores.get("Workshop") ?? 0));
  }
  const ranked = [...scores].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const primary = ranked[0]?.[0] ?? rec.category;
  const confidence = ranked[0]?.[1] ?? 0.4;
  const labels = new Set<string>(ranked.filter(([, score]) => score >= 0.67).map(([category]) => category));
  labels.add(primary);
  if (rec.source === "midpen" || OUTDOORS.test(allText)) labels.add("Outdoors");
  if (FAMILY.test(allText)) labels.add("Family");
  if (YOUTH.test(allText)) labels.add("Youth");
  if (INDOORS.test(allText)) labels.add("Indoor");
  if (OPPORTUNITY.test(allText) || labels.has("Volunteer")) labels.add("Opportunity");
  const cost = inferCost(rec);
  if (cost === "free") labels.add("Free");
  const age = inferAge(`${structured} ${text}`);
  const endInferred = !rec.end;
  const end = rec.end ?? new Date(rec.start.getTime() + (rec.time === "All day" ? 24 : 2) * 3_600_000);
  const quality = Math.min(1,
    (rec.imageURL ? 0.2 : 0) +
    (rec.description.length >= 80 ? 0.2 : rec.description.length > 0 ? 0.1 : 0) +
    (rec.latitude != null && rec.longitude != null ? 0.25 : 0) +
    (!endInferred ? 0.1 : 0.05) +
    (confidence >= 0.65 ? 0.15 : 0) +
    (rec.website ? 0.1 : 0));
  return { ...rec, end, endInferred, category: primary,
    categories: [...labels], classificationConfidence: confidence,
    qualityScore: Math.round(quality * 100) / 100,
    inferredCost: cost, ageSuitability: age };
}
