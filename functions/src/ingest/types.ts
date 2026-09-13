/**
 * One schema for every event source.
 *
 * Every fetcher (Ticketmaster, LibCal/.ics, Localist, NPS, SerpApi, organizer
 * accounts) produces `NormalizedEvent`s and nothing else. The store never sees
 * a vendor payload, so dedupe, staleness and the client all reason about one
 * shape. Field names match what the iOS `Event` model and the Firestore rules
 * already expect for community events, plus the provenance fields.
 */

export type SourceId =
  | "ticketmaster"
  | "libcal"
  | "bibliocommons"
  | "midpen"
  | "localist"
  | "nps"
  | "ics"
  | "serpapi"
  | "organizer"
  | "community";

/** Mirrors EventCategory in the iOS app and CATEGORY_MAX_POINTS on the server. */
export type EventCategory =
  | "Cleanup" | "Sports" | "Social" | "Workshop" | "Market"
  | "Festival" | "Hackathon" | "Meetup" | "Volunteer";

export interface NormalizedEvent {
  /** Which feed produced this record. */
  source: SourceId;
  /** The feed's own id for the event (stable across cycles). */
  sourceEventId: string;
  /** Launch area the record was ingested for. */
  areaId: string;

  title: string;
  description: string;
  organizer: string;
  /** Start, UTC. */
  start: Date;
  /** End, UTC, when the feed says. */
  end?: Date;
  /** Human time string for the card, e.g. "7:00 PM" or "All day". */
  time: string;
  locationName: string;
  latitude?: number;
  longitude?: number;
  category: EventCategory;
  /** True when the feed marks the event free, or has no price at all. */
  isFree: boolean;
  /** Lowest listed price in USD, when known. */
  priceMin?: number;
  website?: string;
  imageURL?: string;
  /** Feed-provided tags, kept for search + the Volunteering category. */
  tags: string[];
}

/** What one ingest run did, per source. */
export interface IngestResult {
  source: SourceId;
  areaId: string;
  fetched: number;
  created: number;
  updated: number;
  merged: number;
  markedStale: number;
  deactivated: number;
  skipped: number;
  errors: string[];
  durationMs: number;
}

/** Points ceiling per category — mirrors CATEGORY_MAX_POINTS in index.ts. */
export const CATEGORY_POINTS: Record<EventCategory, number> = {
  Cleanup: 200, Sports: 150, Social: 100, Workshop: 150, Market: 75,
  Festival: 250, Hackathon: 200, Meetup: 100, Volunteer: 200,
};

/** SF Symbol per category — mirrors EventCategory.icon in the app. */
export const CATEGORY_ICON: Record<EventCategory, string> = {
  Cleanup: "sparkles", Sports: "figure.run", Social: "cup.and.saucer.fill",
  Workshop: "hammer.fill", Market: "bag.fill", Festival: "party.popper.fill",
  Hackathon: "laptopcomputer", Meetup: "person.3.fill", Volunteer: "heart.fill",
};
