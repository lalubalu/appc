# Volunteer supply follow-up — 2026-09-27

Four organizations in G4 were fingerprinted read-only with
`node functions/scripts/fingerprint.mjs <hostname>`. These probes do **not**
add post-freeze sources or imply any live Verdure listings. The C0 human audit
has not passed, so the source list remains frozen.

| Organization | Official calendar evidence | Fingerprint result |
| --- | --- | --- |
| [Our City Forest](https://www.ourcityforest.org/newsletters) | Volunteer calendar and Eventbrite signup mentioned | Home/robots 200; LiveWhale, Localist and CivicPlus probes 404; platform unconfirmed |
| [Guadalupe River Park Conservancy](https://grpg.org/calendar/events/) | Recurring orchard, rose garden and trail workdays | WordPress home/robots 200; apparent 200s at LiveWhale/Localist paths returned **HTML**, not feed data; platform unconfirmed |
| [Grassroots Ecology](https://www.grassrootsecology.org/calendar) | Official volunteer events calendar | Home/robots 200; standard feed probes 404; platform unconfirmed |
| [Keep Coyote Creek Beautiful](https://www.keepcoyotecreekbeautiful.org/creek-cleanups) | Monthly creek cleanups link to Eventbrite registration | Wix home/robots 200; LiveWhale/Localist probes 404, CivicPlus probe 400; platform unconfirmed |

The official Guadalupe page says community workdays require preregistration
and gives chaperone rules for younger volunteers. Those facts must be preserved
if its listings are eventually indexed. A 200 HTML response on a feed-shaped
URL is **not** a feed; the fingerprinter correctly leaves the platform unknown.

Next source work needs a terms/usage review and an actual structured event
endpoint or organizer permission. A silent HTML parser would violate the
existing source-failure rule. Once the human classifier audit passes, any
source added here requires rerunning the C0.4 audit before shipping.

The official [Idealist Open Network API page](https://www.idealist.org/en/open-network-api)
routes applicants to an inquiry form. The application is prepared in
`IDEALIST-INQUIRY.md`; it has not been submitted because the project has no
verified business contact name/email in the repository.

## Existing-feed supply preview

A read-only `node functions/scripts/ingest-smoke.mjs` run after the classifier
corrections fetched **12,267 raw records** from all 11 configured public feeds.
Of those, **3,213** were dated in the following 30 days, carried coordinates,
and lay strictly within 25 miles of the San José center. **55** of those were
classified Volunteer before deduplication or human review: San José Public
Library 42, Midpen 10, SJSU 2, Stanford 1. The log is
`/tmp/verdure-radius-preview-20260927.log`.

This is promising source supply, **not** a pass of the 30-live-listing gate.
The production `/events` collection remains empty, repeated occurrences and
false-positive volunteer labels have not been removed, and some source entries
may not ask attendees to volunteer. Review each candidate's activity and age
eligibility before deciding whether the subtype can appear.
