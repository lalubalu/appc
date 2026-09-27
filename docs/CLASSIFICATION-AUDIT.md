# Classification audit — San José, 2026-09-27

## Status

**Review pending.** The 200-event stratified sample exists at
[`audits/classification-sample-2026-09-27.csv`](audits/classification-sample-2026-09-27.csv).
The `reviewerCategory`, `reviewerLabels`, `labelCorrect`, and `reviewerNotes`
columns are intentionally blank. No accuracy percentage or 85% pass is claimed
until a named reviewer checks every row. The sample was generated from public
source feeds after the source-list freeze commit `462c0a1`; it is not a sample
from a populated production `/events` collection, which currently has zero
documents.

## Reproduce

From `functions/` run `npm run build && node scripts/make-classification-sample.mjs`.
The script fetches read-only public feeds, removes duplicate source IDs, sorts
each feed by a date-seeded SHA-256 of the source ID, and takes round-robin rows
until 200 are selected. This prevents the largest library from monopolizing
the sample. The date in the file name is the sampling seed; a rerun on another
day produces a different sample. Ticketmaster and SerpApi were unavailable
without keys and are not represented; their absence must be stated in any
accuracy report.

| Feed | Rows |
| --- | ---: |
| San José Public Library | 19 |
| Santa Clara County Library District | 19 |
| Palo Alto City Library | 19 |
| Alameda County Library | 19 |
| San Mateo County Libraries | 19 |
| Mountain View Public Library | 19 |
| San José State University | 18 |
| Stanford University | 18 |
| Santa Clara University | 18 |
| Midpeninsula Regional Open Space District | 18 |
| City of San José | 14 |

The current sample has **60/200 predictions below 0.65 confidence**. That is a
review queue, not an error rate. Regenerate the sample with the final build
before hand review if the classifier changes; do not edit predicted columns
manually. The CSV includes each official source URL, date, venue, full
normalized description, and structured tags so the reviewer can resolve
ambiguous cases at the source.

## Reviewer rubric

Choose the primary category by the activity the attendee would do. Use
`Workshop` for teaching, storytime and hands-on practice; `Volunteer` for work
performed for a community cause; `Sports` for physical recreation including
hikes; `Festival` for performances, exhibitions and festivals; `Meetup` for
clubs and gatherings; `Cleanup` for trash removal. Use source programme type
and audience fields before incidental words in the description. A volunteer
*teaching* a class does not turn that class into a volunteer opportunity.
Check secondary labels for Family, Youth, Outdoors, Indoor, Opportunity and
Free only when supported by the source details. Mark `labelCorrect` false if
either the primary category or a material secondary label is wrong. Explain
ambiguous cases in `reviewerNotes`.

After review, compute overall and per-primary-category accuracy with a
denominator for each. Categories with small sample counts need an additional
targeted sample before claiming the 85% gate. Fix categories below 85%,
regenerate predictions, and have the owner review affected rows again.

## Corpus migration gate

`functions/scripts/backfill-classify.mjs` is idempotent, cursor-based, and
defaults to dry-run. Dry-run and `--write` were exercised only against an empty
Firestore emulator and reported 0 processed / 0 changed. The live index is
empty, so there was no corpus to migrate. Once it is populated, run the live
dry-run, review category movement and low-confidence distribution, then run
`--write` and commit the actual before/after report. This gate remains open.
