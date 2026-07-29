import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { safeInternalPath } from "@/lib/security/safe-path";

// Supabase redirects here after the user clicks the email confirmation (or
// magic) link. We exchange the one-time ?code for a session cookie, then
// forward the user on.
export async function GET(request: NextRequest)
{
  let { searchParams, origin } = new URL(request.url);
  let code = searchParams.get("code");

  // Guard against open-redirects via the ?next param — parse-based, because
  // prefix checks miss the "/\evil.com" spellings browsers accept.
  let next = safeInternalPath(searchParams.get("next"), "/account");

  if (code)
  {
    let supabase = await createClient();

    if (supabase)
    {
      let { error } = await supabase.auth.exchangeCodeForSession(code);

      if (!error)
      {
        return NextResponse.redirect(`${origin}${next}`);
      }
    }
  }

  return NextResponse.redirect(`${origin}/login?error=auth_callback_failed`);
}
