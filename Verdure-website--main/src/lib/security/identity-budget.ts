import { rateLimit } from "./rate-limit";

// Ceiling on how many Supabase identity lookups one source may force.
//
// getUser() is an outbound call to Supabase Auth on every invocation — that is
// the point of it, since it revalidates the token rather than trusting the
// cookie's own claims. It is also therefore an amplifier: a junk sb-* cookie
// plus repeated GETs buys one outbound call per request, which burns function
// budget and, worse, the project's shared auth rate limit — the same limit
// real users need in order to log in.
//
// This module exists because the budget lived inside the middleware and one
// route escaped it. /auth/session is a Route Handler that calls getUser()
// itself; the middleware's `needsUser` test does not name it, so it took the
// early return and the handler then called out with nothing counting the
// calls. Measured, same junk cookie, same minute, before this file existed:
//
//   100x /account       ->  60 outbound getUser calls   (capped)
//   100x /auth/session  -> 100 outbound getUser calls   (uncapped)
//
// THE CALLER MUST BE THE MIDDLEWARE, and that constraint is the reason this is
// a module rather than two calls to rateLimit(). The first attempt at the fix
// put a second check inside the route handler with the same key and the same
// number, which reads as one budget and measured as two: 50 requests to
// /auth/session plus 50 to /account cost 100 lookups, not 60. Middleware runs
// in a different runtime from Route Handlers, so the Map below is not the same
// Map. Charging in one place is what makes the number mean anything.
//
// It is still per-instance within that runtime — see the note at the top of
// rate-limit.ts, which is honest about cold starts. This bounds the cheap,
// single-source flood that actually happens; it is not a distributed quota.
let IDENTITY_LOOKUP_LIMIT = 60;
let IDENTITY_LOOKUP_WINDOW_MS = 60 * 1000;

// True when the caller may spend one identity lookup; false when the budget for
// this source is exhausted. Callers MUST fail closed — answer from the cookie's
// own untrusted state, or refuse — rather than calling Supabase anyway. Every
// such fallback can only err towards treating somebody as signed out, which is
// the direction that costs a person one login rather than costing everyone the
// project's auth quota.
export function canSpendIdentityLookup(ip: string): boolean
{
  return rateLimit("identity:" + ip, IDENTITY_LOOKUP_LIMIT, IDENTITY_LOOKUP_WINDOW_MS).ok;
}
