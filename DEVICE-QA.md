# Real-Device QA Script — 2 physical iPhones

**Status: NOT RUN. This is the script, not a result.**

## Free Apple Account first pass

Rishit chose to start with owned iPhones and free Apple Account signing. In
Xcode, add the Apple Account under Settings → Accounts, connect and unlock an
iPhone, trust this Mac, enable Developer Mode if prompted, select the personal
team for the `Verdure` target, and attempt a Debug build to that device.
Record the signing/build result and device model before claiming any run.
Personal-team provisioning expires and some app capabilities may require paid
membership or different entitlements; capture the actual Xcode error rather
than changing the paid account status or weakening production signing.

As of 2026-09-27, `xcrun devicectl list devices` sees Vaiybhav's iPhone 16
Pro Max as **unavailable**, so no physical-device build or QA result exists.
Once the phone is connected, the first free pass can cover launch, visual
layout, Dynamic Type, VoiceOver, permissions, foreground/background behavior,
Map battery use and local location UI. The backend-dependent parts below
remain blocked by the empty/guest-denied live event index and undeployed
Functions/Storage. A signed build alone does not pass any checklist item.

The complete field script needs two real phones outdoors. It cannot be closed
from a simulator, because the three core paths are affected by real hardware:

| What | Why the simulator can't prove it |
|---|---|
| GPS proximity gate | Simulated location is a fixed, perfect, zero-error fix. Real GPS drifts 5–50 m, degrades under tree cover, and takes seconds to settle — which is the whole thing the 500 ft gate has to survive. |
| Photo upload over cellular | The simulator uploads over your Mac's Wi-Fi. It never sees a 200 ms RTT, a captive portal, or a connection dropping mid-PUT. |
| Queue replay | Simulator airplane mode isn't the radio going away; app lifecycle and backgrounding behave differently. |

> **Blocked on backend.** Runs 2 and 3 need Cloud Functions and Storage live.
> Run 1 also needs a reachable event with real coordinates and the relevant
> server path before its server-enforcement check can pass. The live guest feed
> currently fails, so do not mark Run 1 complete from an offline/demo event.
> See the DEPLOY STATUS table in CLAUDE.md.

## Before you leave

- [ ] Both phones on the same build (`Verdure` scheme, Release if possible)
- [ ] Phone A: signed in as account A. Phone B: account B. **Different accounts** — several checks below are about one user not affecting another.
- [ ] Location permission granted, "While Using the App", **Precise Location ON**
- [ ] Note the build's commit SHA here: `________________`
- [ ] Pick a target event with **known real coordinates**. Create one in Community if needed — but note check-in on your *own* event is refused by design (self-dealing guard), so create it on phone A and check in from phone B.

## Run 1 — GPS proximity gate, outdoors

The gate: client refuses at >500 ft from a known venue; server independently
refuses at >1500 m. Two layers, tested separately, because a client-only pass
proves nothing about someone using a patched app.

| # | Where | Action | Expected | Pass? |
|---|---|---|---|---|
| 1.1 | ~1 km away | Open event, tap Check In | Refused, distance shown, no points | ☐ |
| 1.2 | ~250 m away | Same | Still refused (500 ft ≈ 152 m) | ☐ |
| 1.3 | Standing at the venue | Same | Proof-photo camera opens | ☐ |
| 1.4 | At venue, under heavy tree cover | Same | Still passes, or fails with an honest "couldn't get a fix" — **never** silently awards | ☐ |
| 1.5 | At venue, Precise Location OFF | Same | Refused or prompts for precise — must not award on a coarse fix | ☐ |

**1.6 — the one that actually matters.** Phone B at the venue, phone A at home.
Phone A tries to check into the same event.
Expected: phone A refused. If phone A succeeds, the gate is client-side only and
the server check isn't running — stop and report.

Record the accuracy radius shown in Console for each attempt; a gate that only
passes at ±5 m accuracy will fail for real users on older phones.

## Run 2 — Proof photo over cellular *(needs Storage live)*

| # | Action | Expected | Pass? |
|---|---|---|---|
| 2.1 | Wi-Fi OFF, LTE/5G only. Check in with photo | Uploads, check-in completes, points land | ☐ |
| 2.2 | Repeat on 1 bar / edge of coverage | Slow but completes, or queues — no crash, no double award | ☐ |
| 2.3 | Kill the app mid-upload, reopen | Photo still spooled, upload resumes, exactly one check-in | ☐ |
| 2.4 | Airplane mode on immediately after shutter | Queues; no error blaming the user | ☐ |
| 2.5 | Check `proofs/{uid}/` in Storage console | One object per check-in, no orphans, no other user's uid | ☐ |

**2.6 — ownership.** With phone A signed in, try to make it upload to phone B's
`proofs/{B-uid}/` path (needs a debug build or a proxy). Expected: denied by
storage.rules. This is the check that stops one user fabricating another's
evidence.

## Run 3 — Queue replay, the real test *(needs Functions live)*

This is the first time weeks of locally-queued check-ins will ever reach a
server. **Do 3.0 first — it's the only step that can't be redone.**

**3.0 — Capture the "before" state.** On a phone that has been used while the
backend was down:
- [ ] Screenshot: Profile → points balance and lifetime points
- [ ] Screenshot: the unsynced-earnings indicator (`hasUnsyncedEarnings`)
- [ ] Note the exact numbers: balance `______` lifetime `______` queued `______`

If these disappear during replay you need the "before" numbers to prove it.
Points from event check-ins are **never backfilled** by design (there's no honest
proof to resubmit), so a loss here is unrecoverable.

| # | Action | Expected | Pass? |
|---|---|---|---|
| 3.1 | Airplane mode, check into 3 events + collect 3 places | All apply optimistically, queue count = 6 | ☐ |
| 3.2 | Force-quit, reopen, still offline | Queue survives at 6 — persisted, not in memory | ☐ |
| 3.3 | Restore network | Queue drains to 0, balance unchanged from 3.1 | ☐ |
| 3.4 | Compare against Firestore console | Server balance matches device exactly | ☐ |
| 3.5 | Replay the same ops (toggle airplane mode mid-flush) | No double credit — callables are idempotent | ☐ |
| 3.6 | Sign out and back in | Balance still correct — **this is the points-wipe regression** (fixed 07-24, see `CloudMergeTests`) | ☐ |

**3.7 — the queue's worst case.** Put phone A in airplane mode, earn until the
daily cap (2000 pts) is exceeded, then reconnect. Expected: the server clamps to
the cap and the device *reconciles downward* without losing the check-in records
themselves. The user keeps attendance/streak credit; only points stop. If the app
shows a number the server disagrees with after flush, that's a bug — report the
two numbers.

## Run 4 — Things that only break on real hardware

| # | Check | Expected | Pass? |
|---|---|---|---|
| 4.1 | Battery: 30 min of Map + Explore | No runaway drain from the gyro parallax / SceneKit medallion | ☐ |
| 4.2 | Low Power Mode on | App still usable; ambient animation degrades, doesn't freeze | ☐ |
| 4.3 | Incoming call mid-check-in | Returns cleanly, queue intact | ☐ |
| 4.4 | Dynamic Type at accessibility XL, outdoors in sun | Check-in CTA still reachable and readable | ☐ |
| 4.5 | VoiceOver through check-in start → finish | Every control labeled; proof step announced | ☐ |
| 4.6 | Rotate / return from background repeatedly | No layout break, no duplicate fetches | ☐ |
| 4.7 | Browse Explore after the expanded civic/library corpus is loaded | Scroll and search remain responsive; no blank cards, repeated event cards, or memory termination | ☐ |
| 4.8 | Open an SCU or library event whose feed has no coordinates | Check-in never presents a false venue pin or awards proximity points from a guessed location | ☐ |
| 4.9 | Open a Mountain View Library programme and a San José public meeting | Both display the right local time and official source link; a closed session never appears | ☐ |
| 4.10 | Browse after two feeds publish the same event | One card appears, rich image/description survive, and source attribution includes both feeds | ☐ |
| 4.11 | Open a library teen workshop, a volunteer trail day, and a concert | Category, age, cost and indoor/outdoor labels agree with the source details | ☐ |
| 4.12 | Browse Discover with zero events, then a populated feed | The empty state is readable above the tab bar; events appear ahead of personal stats | ☐ |
| 4.13 | Increase Dynamic Type through accessibility sizes on every tab | Headings, chips, card actions and tab labels remain readable without clipping | ☐ |
| 4.14 | Turn on Reduce Motion, then browse every tab | Essential transitions remain clear; decorative movement does not obscure controls | ☐ |
| 4.15 | Discover → For You, then Everything, with a populated corpus | Ranked order differs from chronological order; Everything pages through every matching event without repeats | ☐ |
| 4.16 | Open an event and tap More like this / Less like this | The next For You order changes; a mere view does not erase an explicit choice | ☐ |
| 4.17 | Two accounts: request, decline, request again, accept, then block | Only an accepted friend sees RSVP activity; the block ends access immediately | ☐ |
| 4.18 | Sign up as a 16-year-old, then search from an adult account | Minor absent from exact-username search; private invite works and requires acceptance | ☐ |
| 4.19 | Open a friend invitation URL in Safari with the app installed | The token stays out of the HTTP URL; the app opens Friends with the request ready | ☐ |
| 4.20 | Discover and Plan with large Dynamic Type and VoiceOver | Both mode controls, plan options, feedback buttons and event actions remain reachable | ☐ |
| 4.21 | Organizer posts an accessible outdoor event with age/size details | Details persist and display under Before you go; invalid minimum/maximum ages are refused | ☐ |
| 4.22 | Create a student account and browse Opportunities | Student/school affect ordering without hiding events; private fields are absent from public profiles | ☐ |
| 4.23 | Create and switch two Verdure+ interest profiles in Discover and Plan | Each name, distance preset, exclusion and saved filter persists; switching changes order; free account sees no Plus controls | ☐ |
| 4.24 | Save two child ages, accessibility needs, usual transport and typical distance in Profile; relaunch; open a late, adult-only or accessibility-unconfirmed event | All preferences persist; suitable/confirmed events rise in For You; age, late-ending and unconfirmed-accessibility warnings appear where supported; clearing preferences removes them | ☐ |
| 4.25 | Build a Plan from real events, swap, make it shorter/longer, then reopen | Cards and RSVP work; refinement stays in the same session and never invents a stop | ☐ |
| 4.26 | Two accepted friends share a group plan | Invitee opts in, both shortlist, each independently RSVPs; an unaccepted user cannot find the plan | ☐ |
| 4.27 | Scroll For You, tap, save, RSVP and dismiss a card | Server impression records position, score, signals and the strongest outcome only for displayed cards | ☐ |
| 4.28 | Filter by setting, age audience, group size, accessibility and public venue, then relaunch | Only listings with matching confirmed details remain; selections persist; Reset clears them; an empty result never restores unrelated cards | ☐ |
| 4.29 | Build a Plan with one event image and one missing image while an accepted friend is going | Real image loads without stretching, fallback icon remains legible, friend avatars appear, and RSVP/Refine controls fit at large Dynamic Type | ☐ |
| 4.30 | With two adult accounts that RSVP'd before an event ended, open Add Friends after it ends; repeat while it is upcoming and with a minor account | Adult shared-event suggestion appears only after the end; upcoming attendees and minors never appear; request/accept works | ☐ |
| 4.30 | Deny location, then open Places and Map | Browse from the named launch area, radius count matches displayed cards, no GPS-based check-in is enabled, and a later GPS fix refreshes the list | ☐ |

## Reporting

For each failure record: step number, both phones' model + iOS version, the
on-screen text, and the Console log around the timestamp
(`Window → Devices and Simulators → View Device Logs`, filter `Verdure`).

A step that couldn't be attempted is **not a pass** — mark it skipped and say
why. Every previous QA doc in this repo carries that rule; this one is where it
matters most, because these are the checks nothing else can substitute for.
