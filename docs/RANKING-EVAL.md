# Ranking evaluation handoff

`functions/scripts/rank-eval.mjs` computes precision at 10 and the position of
the first relevant result for exactly 20 reviewer-written profiles. It refuses
to run without a frozen corpus and human relevance judgments. No result is
claimed yet: the live `/events` collection is empty, and no reviewer has been
named for the golden set.

The reviewer needs a fixed, source-linked export containing `snapshotAtMs` and
`events[]` (each item shaped like `RankableEvent` in `functions/src/ranking.ts`).

## Prepared public-source preview

`functions/scripts/make-rank-review-corpus.mjs` fetched the existing 11 public
feeds read-only and froze [233 source-linked candidate events](audits/rank-corpus-preview-2026-09-27.json)
from the following 30 days, all with coordinates inside 25 miles of downtown
San José. Its source-ID and occurrence checks reduced 3,223 in-radius records
to 3,211 provisional unique occurrences before category sampling. The export
has an event-array SHA-256 and is paired with a [20-profile context template](audits/rank-golden-template-2026-09-27.json).
The template's reviewer name, review date and relevance IDs are intentionally
blank. `rank-eval.mjs` rejects that template until a named human fills them,
and rejects a golden file whose corpus hash no longer matches. No ranking
precision is claimed from this preview, and the live-index golden set must be
refreshed once actual production events exist.

Reproduce the preview from `functions/`:

```sh
npm run build
node scripts/make-rank-review-corpus.mjs
node scripts/make-rank-golden-template.mjs ../docs/audits/rank-corpus-preview-2026-09-27.json
```

The source feeds change over time, so a reproduction is a **new snapshot**;
use that day's filename for the second command and do not silently relabel the
committed snapshot when the hash changes.
For each profile, record a stable ID, a `context` of interests, location,
household constraints or history, and `relevantEventIDs` chosen by a person
from that export. Include users with no declared interests, outdoors interests,
students, families, accessibility needs, and accepted friends going to events.
For every relevant choice, verify time, eligibility and location from the
source URL. The reviewer should record their name and date in the golden file.

Run after `npm run build`:

```sh
node scripts/rank-eval.mjs ../docs/audits/rank-corpus.json ../docs/audits/rank-golden.json
```

Re-run this command on every ranking change. Comparing precision at 10 per
profile is as important as the mean; a gain for one profile can hide a severe
regression for another. A known-interest false negative rate above 20% is the
trigger to evaluate embeddings against the curated synonym map.
