// Fixed-window rate limiter, held in process memory.
//
// Honest about what this is: on Vercel each serverless instance keeps its own
// map, so a determined attacker spread across enough cold starts gets more
// than `limit` attempts. It stops the thing that actually happens to a public
// form — one script hammering one endpoint from one address — and it costs no
// infrastructure. When the waitlist starts taking real abuse, swap the two
// functions here for Upstash Redis or Vercel KV and every call site keeps
// working unchanged.

type Bucket = {
  count: number;
  resetAt: number;
  // Kept so eviction can tell a bucket that is actively blocking somebody
  // from one that is merely occupying space. See evict().
  limit: number;
};

let BUCKETS = new Map<string, Bucket>();

// A ceiling so a flood of distinct keys cannot grow the map without bound.
let MAX_BUCKETS = 10_000;

export type RateLimitResult = {
  ok: boolean;
  retryAfterSeconds: number;
};

// Reclaim space when the map hits its ceiling.
//
// The ONLY buckets worth keeping are the ones currently refusing somebody:
// a bucket below its limit permits the next request anyway, so losing it
// changes nothing, while losing a bucket at its limit hands an attacker the
// reset they were trying to buy.
//
// Two earlier versions of this got it wrong in instructive ways. BUCKETS.clear()
// dropped every counter, making "reach the ceiling" a complete bypass. Evicting
// the oldest entries was worse than it sounds: with a shared window length,
// oldest means longest-established, so a flood of fresh keys evicted exactly
// the limits that had been earned — measured, and it failed the test.
//
// Sorting by CONSUMED FRACTION fixes both: a flood arrives as count=1 buckets
// and evicts itself first.
//
// Fraction rather than absolute headroom, which is what this compared at
// first. Namespaces have different limits — waitlist 5, login 10, signout 20,
// identity 60 — so absolute headroom is dominated by whichever policy has the
// largest limit, regardless of how heavily it is being used. The identity
// limiter therefore sat at the top of the eviction order by construction and
// was the first thing discarded under any memory pressure, attacker-driven or
// organic: the newest control shed first. count/limit compares like with like.
function evict(now: number): void
{
  let expired: string[] = [];

  BUCKETS.forEach(function (bucket, key)
  {
    if (bucket.resetAt <= now)
    {
      // Index assignment rather than concat: concat rebuilt the whole array on
      // every hit, so a sweep that found all 10,000 entries expired copied ~50
      // million elements to collect 10,000 keys.
      expired[expired.length] = key;
    }
  });

  expired.forEach(function (key)
  {
    BUCKETS.delete(key);
  });

  if (BUCKETS.size < MAX_BUCKETS)
  {
    return;
  }

  // Everything is live. Evict least-consumed first, so a bucket at 1/5 goes
  // before one at 40/60 and a blocking bucket (1.0) goes last of all.
  let consumed = function (bucket: Bucket): number
  {
    return bucket.limit > 0 ? bucket.count / bucket.limit : 1;
  };

  let byConsumed = Array.from(BUCKETS.entries())
    .slice()
    .sort(function (a, b)
    {
      return consumed(a[1]) - consumed(b[1]);
    });

  byConsumed.slice(0, Math.ceil(MAX_BUCKETS / 10)).forEach(function (entry)
  {
    BUCKETS.delete(entry[0]);
  });
}

export function rateLimit(
  key: string,
  limit: number,
  windowMs: number
): RateLimitResult
{
  let now = Date.now();
  let bucket = BUCKETS.get(key);

  if (!bucket || bucket.resetAt <= now)
  {
    // This used to be BUCKETS.clear() at the cap, which turned the memory
    // guard into a weapon: anyone able to mint distinct keys — trivial from a
    // single machine holding an IPv6 /64 — could push the map to the ceiling
    // and wipe EVERY counter on the instance, including the ones that were
    // actively throttling them. Reaching the cap was the attacker's goal, not
    // an accident to absorb.
    //
    // Now expired entries go first, and only if that frees nothing do we drop
    // by consumed fraction — see evict(). A flood of fresh keys therefore
    // evicts other fresh keys rather than resetting established limits.
    if (BUCKETS.size >= MAX_BUCKETS)
    {
      evict(now);
    }

    BUCKETS.set(key, { count: 1, resetAt: now + windowMs, limit });
    return { ok: true, retryAfterSeconds: 0 };
  }

  if (bucket.count >= limit)
  {
    return {
      ok: false,
      retryAfterSeconds: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    };
  }

  BUCKETS.set(key, { count: bucket.count + 1, resetAt: bucket.resetAt, limit });
  return { ok: true, retryAfterSeconds: 0 };
}
