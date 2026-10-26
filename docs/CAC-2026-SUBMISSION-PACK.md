# Verdure — CAC 2026 submission pack (video script + written answers)

Companion to `docs/CAC-2026-SUBMISSION-REVIEW.md`. Everything factual below is taken from the
repository as it stands on 2026-10-25; every `[TEAM: …]` is something only you can say truthfully.
Replace them all before you submit. Do not read the bracketed text aloud.

Required video elements (Rules §4) and where the script covers them:
names of each participant (0:00), app name (0:00), purpose in one sentence (0:08),
target audience (0:16), tools and coding languages (0:22 and 1:50), functionality (0:35–2:25).
Length 1–3 minutes; target **2:40**, hard stop **3:00**. Upload **Public** on YouTube or Vimeo.

---

## 1. Demonstration video script (2:40)

Record the simulator at iPhone size with the emulator stack running (`./run-all.command`, sign in
as the demo judge account). One narrator per section is fine; every teammate must appear or be
named on screen. Keep the app full-frame; put the speaker in a small corner window or a name card.

| Time | On screen | Narration |
|---|---|---|
| 0:00–0:08 | Title card: **Verdure — Step Outside. Connect Within.** Four name cards: Lalith, Rishit, John, Vishvak. | "Hi, we're Lalith, Rishit, John and Vishvak, and this is Verdure." |
| 0:08–0:16 | App icon → onboarding (`demo-screens/01`). | "Verdure gets people out of the house and into their own neighbourhood by rewarding them for actually showing up at real parks and real community events." *(the one-sentence purpose)* |
| 0:16–0:22 | Interest picker (`02-onboarding-interests`). | "It's built for students and young adults who want to go outside more but never know what's on nearby — and for parents looking for things to do with their kids." |
| 0:22–0:35 | Quick architecture card: iPhone app · Cloud Functions · Firestore · civic feeds. | "It's a native iOS app written in **Swift** with SwiftUI, SceneKit and MapKit. The server is **TypeScript** on Firebase Cloud Functions with Firestore. Our event-discovery research engine is in **Python**, and the marketing site is **JavaScript** with Next.js. We'll show you the code in a moment." |
| 0:35–0:55 | Events feed (`04`, `05`): scroll the For You slate; tap a card; show "Why you're seeing this" (`07`). | "Every event you see is real. Verdure ingests public calendars from libraries, universities, the city and open-space districts — nineteen sources, about eight and a half thousand events for the South Bay — and never scrapes a site whose terms forbid it. The feed is ranked to your interests, and every card can tell you why it's there." |
| 0:55–1:15 | Event detail → **Check in**: location gate, proof photo, points awarded. | "To earn points you have to be there. Check-in needs your GPS within 500 feet **and** a photo, and the server verifies both before a single point is credited. The phone can't mint points — Firestore rules deny it, and we red-teamed that with ninety-six attacks." |
| 1:15–1:30 | Places tab → place detail with the OpenStreetMap credit (`09`, `10`, `11`) → Map (`12`). | "Places come from OpenStreetMap, the National Park Service and Recreation.gov. Collect one by walking up to it — rarity from a common city park to a legendary overlook. We show nothing we can't source: no made-up ratings, no fake attendee counts." |
| 1:30–1:50 | Plan tab → Adventure Planner → plan with weather line (`planner`, `planner-plan`, `credit-weather`). | "Tell it how long you have and it builds an itinerary from real nearby places and today's weather — stops close before closing time, nothing outdoors after sunset. This runs on our own deterministic engine; it needs no AI key." |
| 1:50–2:10 | Xcode: `GameStateManager.swift` pending-op queue; VS Code: `functions/src/ranking.ts` or `ingest/store.ts`; terminal: test summary (E2E 363/363, 161 iOS unit tests). | "[TEAM member who owns it]: The hardest part was making earning safe offline. Check-ins apply instantly on the phone, queue as idempotent operations, and replay when the server is reachable — so a dead network never loses a point and a replay never doubles one. We used an AI coding assistant for parts of the code and tests; that's disclosed in the repo, and every design decision you just saw is ours." |
| 2:10–2:25 | Dark mode toggle; large Dynamic Type; VoiceOver cursor on the check-in button; Rewards (`15`). | "It's built to be used by everyone: full dark mode, Dynamic Type, and fifteen of fifteen Apple accessibility audits pass. Points redeem for real gift cards." |
| 2:25–2:40 | End card: app name, four names, repo URL, "CA-10 · Congressional App Challenge 2026". | "Verdure. Step outside, connect within. Thanks for watching." |

Recording checklist: status bar clean (the UI tests set 9:41), motion off if the simulator stutters
(`-QADisableMotion`), no browser open on the 8 GB Mac (see the verification doc), export 1080p,
confirm the uploaded video plays while signed out of YouTube.

---

## 2. Written answers (draft)

### Q1. What is the title of your app?
Verdure

### Q2. Explain the app's purpose. *(if a short field: 140 characters)*
Short: **Verdure rewards people for going outside and showing up at real local parks and community events, verified by location and photo.** (134)

Long: Verdure is an iOS app that turns a neighbourhood into something worth exploring. It
ingests real community events from public civic calendars (libraries, universities, the city,
open-space districts) and real places from OpenStreetMap and the National Park Service, ranks
them to each user's interests, and rewards attendance with points that become gift cards. Earning
requires being there: a check-in needs GPS within 500 feet and a proof photo, both verified on the
server. A built-in planner turns an afternoon into an itinerary from real nearby places and the
day's weather. Nothing in the app is fabricated — if a source does not provide a rating, a count
or opening hours, Verdure shows nothing rather than a plausible number.

### Q3. What inspired you to create this app?
[TEAM: two or three sentences in your own words. The honest version is the best version. Prompts:
what made you notice the problem — a park you'd never been to five minutes from home, friends
who only meet online, a parent asking "what's on this weekend"? Why existing apps didn't fix it:
Meetup/Eventbrite list things but don't get you there; AllTrails is solo; nothing ties showing up
to a reward.] Then, factual: "We wanted a feed that only contains real local things and never
scrapes a site that asks not to be — so we wrote the sourcing rule into the code, and an automatic
discovery job that finds and inspects new civic calendars against six evidenced rules."

### Q4. What technical/coding difficulty did you face, and how did you address it?
Pick **one** and tell it as a story; both below are true and in the repo.

**Option A — personalization that was silently doing nothing.** Users pick interests like
"Parks" and "Trails", but the ranker only knew a lower-case server vocabulary ("outdoors",
"fitness"), so the interest weight was zero for every event for every real user — the For You
feed was ordered by distance and timing alone, and a Parks user got career workshops. The fix was
not one line: we wrote `interests.ts` to normalise labels, match on title phrases and the
classifier's specific categories (never bare words like "park", which matched "Mitchell Park
Library"), strip venue names first, add an interest-keyed retrieval step with a new composite
index, and sort direct matches above every non-match while never filtering anything out. We
proved it with a per-interest acceptance script (50/50) and a manual review of every top-10 that
found zero false matches.

**Option B — earning points safely offline.** Points must be server-authoritative (a client
that writes its own balance is a cheat), but a check-in happens at a park with bad reception.
We apply the earn optimistically on the phone, spool the proof photo to disk, queue a durable
pending operation, and replay it when connectivity returns. Every server callable is idempotent
on the operation id so a replay can never double-credit, and the client only trusts the server's
balance after a real round trip so an empty cloud can never wipe local progress. Firestore rules
deny every client write to the balance fields; a 96-attack red-team suite checks that on every
build.

[TEAM: whoever presents this must be able to explain it without notes.]

### Q5. What did you learn while participating in the CAC? What was your biggest takeaway?
[TEAM: your own words. Candidate takeaways that are true for this project — keep only the ones
that are true for *you*: that honest empty states beat fabricated content; that "parse public
feeds freely, never scrape where terms forbid" is a rule you can put in code; that tests against
a recorded corpus let four people work on two machines without the live internet; that an AI
assistant speeds up typing but you still own every design decision and have to understand every
line a judge might ask about; that secrets end up in git history unless a gate stops them.]

### Q6. What would you change about your app if you were to create a 2.0 version?
Based on what is written down as open in the repo:
- Deploy the backend (Firebase Blaze) and ship through TestFlight so judges and users can install
  it instead of running the local stack.
- Recruit the three South Bay organisers that block automated access (City of San José, Santa
  Clara University, Santa Clara County Parks) so their events appear — a human conversation, not
  a better parser.
- A real "Outdoors" event category (guided hikes currently classify as Sports).
- Real photos for places and real social features (follows, per-user feeds).
- Venue geocoding for WordPress-calendar sources so volunteer plantings show on the map.
- Turn the ranker's v2 (feedback affinity, novelty) on after a blind evaluation.
[TEAM: add the one you personally want most.]

---

## 3. Form fields you will also be asked for

| Field | Value |
|---|---|
| App name | Verdure |
| Platform | iOS (iPhone), iOS 17+ |
| Languages | Swift, TypeScript, Python, JavaScript |
| Tools | Xcode, XcodeGen, SwiftUI, SceneKit, MapKit, Firebase (Auth, Firestore, Functions, Storage, Messaging), Firebase Local Emulator Suite, Node.js, Next.js |
| Video URL | [TEAM: public YouTube/Vimeo link] |
| Source code URL | `https://github.com/lalubalu/appc` branch `cac-submission` (clean history) — or `CAC-handoff` once public |
| AI disclosure | `AI-AND-THIRD-PARTY-DISCLOSURE.md` in the repo root; one sentence in the video at 1:50 |
| Open-source / third-party | same file, §3 |
| Team | Lalith, Rishit, John, Vishvak |
