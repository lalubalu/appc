import { headers } from "next/headers";
import { normalizeIp } from "./ip";

// Resolves the caller's address for rate-limiting purposes.
//
// x-forwarded-for is only trustworthy because Vercel's proxy overwrites it on
// the way in — the client cannot inject a value that survives. If this site
// ever runs behind a different proxy, or directly, this needs revisiting
// before anything security-relevant leans on it.
// A single cheap host is routinely handed an IPv6 /64 — 18 quintillion
// addresses — so keying a limit on the full address is the same as having no
// limit at all against anyone who bothers. Collapsing to the /64 means the
// whole allocation shares one bucket, which is the unit an ISP actually hands
// to one customer.
//
// The parsing lives in lib/security/ip.ts and is deliberately not a string
// split: see the note there for why the obvious version silently fails on
// every address containing "::".

export async function clientIp(): Promise<string>
{
  let requestHeaders = await headers();
  let forwarded = requestHeaders.get("x-forwarded-for");

  if (forwarded)
  {
    // Real client first, proxy chain after.
    let first = forwarded.split(",").at(0);

    if (first && first.trim())
    {
      return normalizeIp(first.trim());
    }
  }

  let realIp = requestHeaders.get("x-real-ip");

  if (realIp && realIp.trim())
  {
    return normalizeIp(realIp.trim());
  }

  // Local dev, or a proxy that strips both. Everyone shares one bucket, which
  // is the safe direction to fail.
  return "unknown";
}
