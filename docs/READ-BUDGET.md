# Discovery read budget — 2026-09-26

## Live measurement and gate

The read-only A1 query found **zero documents** in the live `events`
collection. The measured candidate reads per feed load are therefore **zero
against an empty corpus**. This is not a usable load benchmark; C1 cannot be
declared cost-validated until a real area corpus exists. No live ingest or
production feed rollout was performed here.

For a populated index, a candidate set of 300 documents would cost about 300
document reads per uncached load, plus any index-entry reads. At three loads per
user per day, that is 900 reads per user per day. The table is a scenario, **not
a measured production result**.

| Users | Reads/day at 300 × 3 | Reads/30 days | Gross document-read charge |
| ---: | ---: | ---: | ---: |
| 100 | 90,000 | 2.7 million | $0.81 |
| 1,000 | 900,000 | 27 million | $8.10 |
| 10,000 | 9 million | 270 million | $81.00 |

The [current Firestore Standard price in us-central1](https://cloud.google.com/firestore/pricing)
is $0.03 per 100,000 document reads beyond the daily 50,000-read free quota.
Gross figures deliberately ignore free quota, index-entry reads, writes,
storage, network, other app reads and functions. They show order of magnitude,
not a project invoice. The region and edition must be checked before use.

## Architecture decision before C1

Avoid re-reading several hundred Firestore event documents for every pull to
refresh. Build a bounded shared candidate snapshot per area and short time
window; rank against it server-side and cache the per-user result for a short
window. Expose a read counter in `/treasury`. A per-user feed document can make
client reads one per load, but generating it still reads candidates; schedule
refreshes and measure total backend reads before claiming a cost reduction.

Everything mode must use a cursor and a small page size. It must never return
the full radius set in one query. Before enabling the feed on a populated live
index, rerun this report with actual document and index-entry reads and a
measured cache hit rate. Keep the C1 launch gate closed until then.
