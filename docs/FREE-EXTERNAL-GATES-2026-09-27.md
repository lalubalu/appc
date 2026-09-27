# Free external gates — 2026-09-27

Scope: read-only checks and no-cost access requests for the Verdure sprint. No
production deployment, billing change, API purchase, account creation or
environment switch was made. The owner explicitly said **no deployment yet**.

## Public source availability

`node functions/scripts/ingest-smoke.mjs` fetched records from all 11
configured public sources on September 27. The log is
`/tmp/verdure-free-source-smoke-20260927.log`. The adapters returned 12,268
raw records in total, including 6,018 from San José Public Library, 1,916
from Santa Clara County Library District and 54 from Midpen. These are source
responses, not deduplicated, radius-filtered live Firestore events. Ticketmaster
and NPS were skipped because their keys are unset. This run made no Firestore
writes. C0 human classification review and the live-corpus read/cost gates still
precede production ingestion.

## Website and hosting

- The owner confirmed `https://verdure-app.com/` is the production website.
  It responds `200` with a Vercel server header.
- `https://verdure-app.com/invite` responds `404`. The invitation route exists
  in local website source only.
- `https://verdure-app.com/privacy` responds `200` and displays a policy dated
  July 26, 2026, including payment and shipping language. The newer local
  policy is unpublished.
- `npx --yes vercel whoami` reports Logged out; no `.vercel` project link is
  present in the local website directory. GitHub CLI is signed in, but the
  repository has no GitHub deployment records. No push or deploy was attempted.

## Free access requests

| Service | Official path | Current gate |
| --- | --- | --- |
| Idealist Listings API | [Open Network API inquiry](https://www.idealist.org/en/open-network-api), which leads to a five-question Typeform | First name, last name, email and organization are required on the first screen. The owner's contact identity is needed. The page describes API pricing but does not promise free access. Draft: `docs/IDEALIST-INQUIRY.md`. |
| SeatGeek Public Catalog API | [Developer portal](https://portal.seatgeek.com/) and its [approval form](https://docs.google.com/forms/d/13gfeUdfbZQpnT3XNd12pyi7P2A4W7vDoB4bSwIdlG9k/viewform) | The form requires the email address of a pending SeatGeek developer account and an intended-use explanation. It states the Public Catalog API provides catalog data, not prices or ticket listings. No developer account or key is available in the workspace. |
| Bandsintown and Songkick | See `docs/NATIONAL-API-EVALUATION.md` | Existing first-party terms require a partnership or fee; neither is a ready free regional feed. |

## Next actions when inputs arrive

1. With the Verdure contact name, business email and organization name, complete
   the Idealist inquiry for listings access and pricing information. Do not agree
   to paid or contractual terms on behalf of the owner.
2. With a registered SeatGeek developer account email, submit the catalog API
   access request, then assess coverage and overlap before adding an adapter.
3. After the owner authorizes a website deployment and the correct Vercel
   project/account is connected, publish the locally prepared invite, privacy
   and pricing changes and verify the public routes.
