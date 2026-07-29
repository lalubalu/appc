// Regression assertions for the security primitives.
//
// These exist because every control in lib/security has now been wrong at
// least once in a way that reading it did not reveal and running it did
// immediately: the redirect guard accepted "/..//evil.example", the limiter's
// memory guard reset every counter it was supposed to protect, its first
// replacement evicted the longest-established limits, and the IPv6 collapse
// gave a distinct key to every address in any /64 containing a zero run.
//
// Run with: npm run test:security
//
// No test framework on purpose — the project has none, and one dependency-free
// script that exits non-zero is enough to keep these honest.

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

let out = mkdtempSync(join(tmpdir(), "verdure-sec-"));
let failures = 0;
let checks = 0;

function check(label, condition, detail)
{
  checks = checks + 1;

  if (!condition)
  {
    failures = failures + 1;
  }

  console.log(
    "  " + (condition ? "PASS" : "FAIL") + "  " + label + (detail ? "  " + detail : "")
  );
}

try
{
  execFileSync(
    "npx",
    [
      "tsc",
      "src/lib/security/ip.ts",
      "src/lib/security/rate-limit.ts",
      "src/lib/security/safe-path.ts",
      "--outDir", out,
      "--module", "commonjs",
      "--target", "es2020",
      "--skipLibCheck",
    ],
    { stdio: "inherit", shell: process.platform === "win32" }
  );

  let { normalizeIp } = await import(pathToFileURL(join(out, "ip.js")).href);
  let { rateLimit } = await import(pathToFileURL(join(out, "rate-limit.js")).href);
  let { safeInternalPath } = await import(pathToFileURL(join(out, "safe-path.js")).href);

  // ── IPv6 /64 collapse ───────────────────────────────────────────────────
  // Every case below returned a DISTINCT key under the string-splitting
  // version, which is precisely the free-buckets problem the collapse exists
  // to remove. "::" compression means the first four colon-separated groups
  // are not the first four hextets.
  console.log("\nnormalizeIp — IPv6 /64");

  let ipCases = [
    ["2001:db8:1234:5678::1", "2001:db8:1234:5678::/64"],
    ["2001:db8:1234:5678::2", "2001:db8:1234:5678::/64"],
    ["2001:db8::1", "2001:db8:0:0::/64"],
    ["2001:db8::2", "2001:db8:0:0::/64"],
    ["2001:db8:0:0:aaaa::1", "2001:db8:0:0::/64"],
    ["[2001:db8:1:2::1]:41234", "2001:db8:1:2::/64"],
    ["2001:0db8:0000:0000:0000:0000:0000:0001", "2001:db8:0:0::/64"],
    ["2001:DB8::AAAA", "2001:db8:0:0::/64"],
    ["2001:db8:0:1::1", "2001:db8:0:1::/64"],
    ["fe80::1%eth0", "fe80:0:0:0::/64"],
    // Unwrapped, NOT masked. This line previously asserted "0:0:0:0::/64",
    // which encoded the bug as the expected result: every IPv4-mapped client
    // sharing one bucket with each other and with ::1.
    ["::ffff:192.0.2.1", "192.0.2.1"],
    ["203.0.113.9", "203.0.113.9"],
    ["unknown", "unknown"],
  ];

  for (let [input, expected] of ipCases)
  {
    let actual = normalizeIp(input);
    check(JSON.stringify(input), actual === expected, "-> " + JSON.stringify(actual));
  }

  let oneSlash64 = [
    "2001:db8::1",
    "2001:db8::2",
    "2001:db8:0:0:aaaa::1",
    "[2001:db8::99]:8080",
  ].map(normalizeIp);

  check("four addresses in one /64 share one key", new Set(oneSlash64).size === 1);

  // ── Redirect guard ──────────────────────────────────────────────────────
  console.log("\nsafeInternalPath — open redirect");

  let BS = String.fromCharCode(92);
  let redirectCases = [
    ["/account", "/account"],
    ["/pricing?a=1#x", "/pricing?a=1#x"],
    ["//evil.example", "/account"],
    ["/" + BS + "evil.example", "/account"],
    ["/" + String.fromCharCode(9) + "/evil.example", "/account"],
    ["https://evil.example", "/account"],
    ["javascript:alert(1)", "/account"],
    ["////evil.example", "/account"],
    ["/..//evil.example", "/account"],
    ["/.//evil.example", "/account"],
    ["", "/account"],
    [null, "/account"],
    [undefined, "/account"],
  ];

  for (let [input, expected] of redirectCases)
  {
    let actual = safeInternalPath(input, "/account");
    check(
      typeof input === "string" ? JSON.stringify(input) : String(input),
      actual === expected,
      "-> " + JSON.stringify(actual)
    );
  }

  // ── Rate limiter ────────────────────────────────────────────────────────
  console.log("\nrateLimit — thresholds and eviction");

  let WINDOW = 10 * 60 * 1000;

  for (let i = 0; i < 5; i++)
  {
    rateLimit("wl:threshold", 5, WINDOW);
  }

  check("6th request over a limit of 5 is refused", rateLimit("wl:threshold", 5, WINDOW).ok === false);

  for (let i = 0; i < 5; i++)
  {
    rateLimit("wl:victim", 5, WINDOW);
  }

  for (let i = 0; i < 24000; i++)
  {
    rateLimit("flood:" + i, 5, WINDOW);
  }

  check(
    "a fully-consumed bucket survives a 24k-key flood",
    rateLimit("wl:victim", 5, WINDOW).ok === false
  );

  // Cross-policy ordering: identity (limit 60) must not be shed first purely
  // because its larger limit gives it the most ABSOLUTE headroom.
  for (let i = 0; i < 40; i++)
  {
    rateLimit("identity:1.2.3.4", 60, WINDOW);
  }

  for (let i = 0; i < 24000; i++)
  {
    rateLimit("flood2:" + i, 5, WINDOW);
  }

  let remaining = 0;

  for (let i = 1; i <= 25; i++)
  {
    if (rateLimit("identity:1.2.3.4", 60, WINDOW).ok === false)
    {
      remaining = i;
      break;
    }
  }

  check(
    "a partially-consumed high-limit bucket keeps its count across a flood",
    remaining > 0 && remaining <= 21,
    "blocked after " + remaining + " further calls (expected ~20, not ~60)"
  );
}
finally
{
  rmSync(out, { recursive: true, force: true });
}

console.log(
  "\n" + (failures === 0
    ? checks + " checks passed"
    : failures + " of " + checks + " checks FAILED")
);

process.exit(failures === 0 ? 0 : 1);
