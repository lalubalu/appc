# Real-Device QA Script — 2 physical iPhones

**Status: NOT RUN. This is the script, not a result.**

Everything in this file needs two real phones outdoors. It has been on the
checklist for three weeks and cannot be closed from a simulator, because the
three things it covers are exactly the three the simulator fakes:

| What | Why the simulator can't prove it |
|---|---|
| GPS proximity gate | Simulated location is a fixed, perfect, zero-error fix. Real GPS drifts 5–50 m, degrades under tree cover, and takes seconds to settle — which is the whole thing the 500 ft gate has to survive. |
| Photo upload over cellular | The simulator uploads over your Mac's Wi-Fi. It never sees a 200 ms RTT, a captive portal, or a connection dropping mid-PUT. |
| Queue replay | Simulator airplane mode isn't the radio going away; app lifecycle and backgrounding behave differently. |

> **Blocked on backend.** Runs 2 and 3 need Cloud Functions and Storage live.
> As of 2026-08-09 neither is deployed (billing is still Spark). Run 1 works
> today. See the DEPLOY STATUS table in CLAUDE.md.

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

## Reporting

For each failure record: step number, both phones' model + iOS version, the
on-screen text, and the Console log around the timestamp
(`Window → Devices and Simulators → View Device Logs`, filter `Verdure`).

A step that couldn't be attempted is **not a pass** — mark it skipped and say
why. Every previous QA doc in this repo carries that rule; this one is where it
matters most, because these are the checks nothing else can substitute for.
