# Verdure sprint status — 2026-09-27

This is the iOS app named **Verdure** inside the directory named
`Connectify App-iOS`. It is not a second Connectify product. This status is
against the 584-line “Verdure — Next Sprint” engineering scope supplied for
the week.

## Completed and verified locally

- A1 ran before code: live `/events` has 0 documents, so Google absence is not
  measurable. Evidence: `docs/COVERAGE-SAN-JOSE.md`.
- A2 displays “Sports & Outdoors” without changing stored category values.
- B source list was expanded and committed before C0 lexicon tuning in
  `462c0a1`; SCU LiveWhale, four added library calendars, and City Legistar
  are among the new feeds. Public feed probes and source counts are in
  `docs/FEED-SURVEY-SAN-JOSE.md`.
- C0 classifier and enrichment run on ingest; a resumable backfill, low
  confidence CLI, and 200-row review sample are committed. Backend unit tests
  passed. `docs/CLASSIFICATION-AUDIT.md` records the unpassed human gate.
- `docs/READ-BUDGET.md` was written before C1. It explicitly leaves the live
  cost gate open because the index is empty.
- D1–D4 token change landed as one commit `c8ef3cb` before any new view work.
  D5 simplified existing screens; the Events before/after Computer screenshots
  are in `docs/DESIGN-REFRESH.md`. Simulator build passed.
- An unrelated but material audit fix rejects check-ins for missing event
  documents. Account deletion now removes the analytics rows the client
  actually writes. Emulator E2E: **277 passed, 0 failed**. Red team:
  **49 attacks blocked, 0 vulnerable**.

## Open gates and work

| Scope | Status | What closes it |
| --- | --- | --- |
| A1 end comparison | Open | Populate the live index, rerun coverage with source breakdown and a Google search audit. |
| B full supply | Partial | County Parks programming and additional legitimate volunteer sources; national API access where offered. No post-freeze source should ship without rerunning C0.4. |
| C0.4 human audit | Open | Name a reviewer; check all 200 source-linked rows, report accuracy by category, fix any important category below 85%. |
| P2 migration | Open | With a populated live index, review the dry-run movement before the live backfill and commit the report. Empty-emulator dry/write runs processed 0. |
| P3 read budget | Open | Measure against a populated live index before releasing C1; add bounded candidate retrieval, Everything pagination, caching, and treasury read telemetry. |
| C1–C11 | Not shipped | Ranking retrieval, signals, modes, golden set, instrumentation and client wiring. Human golden-set owner needed. |
| D5 | Partial | Computer after screenshots for remaining screens and visual accessibility sweep; Simulator capture timed out after the Events screen. |
| E1 navigation | Local UI built | Five tabs and rehomed surfaces compile; Plan was visually inspected on Simulator. Complete visual matrix and automated accessibility review remain. |
| E2–E4 friends | Open | Mutual requests, accepted-only activity, invite links and QR, minor search safety, rules, account deletion cleanup, then live tab data. The new Friends tab currently shows an honest invite/Community entry without exposing follow-based location activity. |
| F planner | Partial UI | Options-first local event picker and in-place swap/remove are built. Server-ranked candidate assembly, model sequence, session quota, accepted friend signals and acceptance tests remain. |
| G / I / H | Not shipped | Opportunities/student mode, Plus personalization, then group planning. These depend on C's validated data and ranking work. |
| G4 Idealist application | Open | Application contact and organizational details, then submit through the official access process. |

No production deployment, account upgrade, Apple Developer action, or
environment flip was performed. `CLAUDE.md` deploy status was not changed.
