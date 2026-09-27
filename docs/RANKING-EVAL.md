# Ranking evaluation handoff

`functions/scripts/rank-eval.mjs` computes precision at 10 and the position of
the first relevant result for exactly 20 reviewer-written profiles. It refuses
to run without a frozen corpus and human relevance judgments. No result is
claimed yet: the live `/events` collection is empty, and no reviewer has been
named for the golden set.

The reviewer needs a fixed, source-linked export containing `snapshotAtMs` and
`events[]` (each item shaped like `RankableEvent` in `functions/src/ranking.ts`).
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
