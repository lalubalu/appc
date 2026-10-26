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

## 2. Written answers (final)

Written in the team's voice from the repository's own record. Two sentences in Q3 and one in Q5
describe the team's experience rather than code; they are marked with ⟨confirm⟩ and should be
read once by all four of you before submitting. Everything else is checkable in the repo.

### Q1. What is the title of your app?
Verdure

### Q2. Explain the app's purpose.
Short (140 characters): **Verdure rewards people for going outside and showing up at real local parks and community events, verified by location and photo.**

Full: Verdure is an iOS app that turns your own neighbourhood into something worth exploring.
It gathers real community events from public civic calendars (libraries, universities, the
city, open-space districts) and real places from OpenStreetMap and the National Park Service,
ranks them to your interests, and rewards you for showing up. Earning requires being there: a
check-in needs your GPS within 500 feet and a proof photo, and the server verifies both before a
single point is credited. Points become gift cards. A built-in planner turns a free afternoon
into an itinerary of real nearby places shaped by today's weather. Nothing in Verdure is
fabricated: if a source does not publish a rating, an attendance count or opening hours, the app
shows nothing rather than a made-up number.

### Q3. What inspired you to create this app?
We live in the South Bay, surrounded by parks, trails and free community events, and most people
we know, including us, never go to any of them. ⟨confirm⟩ The information exists, but it is
scattered across a dozen library, city, university and open-space calendars that nobody checks,
and the apps that do list events stop at listing: nothing gets you out the door, and nothing
notices whether you went. Pokémon GO proved that a game can move millions of people through real
streets; we wanted that pull aimed at real places and real neighbours instead of virtual
creatures. ⟨confirm⟩ So Verdure makes going outside the game: collect the parks you actually
walk to, earn for the events you actually attend, and plan the afternoon from what is genuinely
nearby. We also set ourselves a rule early that shaped everything after it: never show the user
something that is not real, and never take data from a site whose terms say not to. That rule
is written into the code, including an automatic discovery job that finds new civic calendars
and inspects each one against six evidenced checks before it is ever used.

### Q4. What technical/coding difficulty did you face in programming your app, and how did you address this technical challenge?
The hardest problem was points. Verdure points turn into real gift cards, so if the phone is allowed to set its own balance, somebody will eventually set it to a million. But the whole point of the app is being outdoors, and parks are exactly where reception is worst. Our first version did what every tutorial does: tap check in, call the server, show a spinner. It didn't take long to see that this was wrong on both ends. Nothing stopped a modified client from skipping the call and writing to Firestore directly, and anyone in a park with no signal just stared at the spinner until it gave up.

So we rebuilt how points move. The server became the only thing allowed to touch a balance. Every earn goes through a Cloud Function written in TypeScript, and the Firestore security rules flat out deny a client write to any points field, even on the user's own document. To make sure we didn't quietly break that later, we wrote a red-team suite that throws 96 attacks at the rules, things like forging a check-in for another user or editing your own balance, and it runs on every build. Right now it's 96 blocked, 0 through.

The offline side took longer to get right. A check-in now shows up on the phone instantly, the proof photo is saved to disk, and the whole thing goes into a queue as a pending operation with its own ID. When the network comes back the queue replays on its own. Every server call is idempotent on that ID, so if the same check-in gets sent three times because the connection dropped, it still only credits once. We also learned the hard way that the phone can't trust whatever balance the cloud sends back. During testing a fresh backend returned an empty balance and the app overwrote everything the user had earned offline. Now it only accepts the server's number after a confirmed round trip, and there is a test for exactly that.

The server checks the proof too. It runs a haversine distance check against the event's stored coordinates and confirms the photo path belongs to the user's own account.

We tested the full path with 363 end-to-end checks on the Firebase emulators, including double check-ins, replayed operations and spoofed coordinates. The lesson that stuck: the phone can propose, but only the server gets to decide.

### Q5. What did you learn while participating in the CAC? What was your biggest takeaway?
Our biggest takeaway is that real data is the hard part. Making a beautiful feed of fake events
takes an afternoon; making a feed of only real ones took most of the project: thirteen feed
adapters, a classifier we froze once it was right, fuzzy de-duplication, a rule that every event
carries an age flag so minors never see a bar crawl, and the discipline to show an honest empty
state instead of a plausible placeholder. We learned that a product rule, like "parse public
feeds freely, never scrape where terms forbid", is only real once it is code that fails a test
when broken. We learned to record every external feed as a fixture so four people on two
machines could run the same tests without the live internet. We used an AI coding assistant for
parts of the code and tests, and learned that it changes the job rather than removing it: every
design decision, and the understanding of every line a judge might ask about, still has to be
ours. ⟨confirm⟩ And we learned, by finding old API keys in our own git history, that secrets leak
unless a check blocks them, so we wrote that check into the build.

### Q6. What would you change about your app if you were to create a 2.0 version?
Deploy the backend to the cloud and ship through TestFlight, so anyone can install Verdure
instead of running our local stack. Recruit the three South Bay organisers whose sites block
automated access (City of San José, Santa Clara University, Santa Clara County Parks) by asking
them for a calendar feed, since no parser can fix a 403. Add a real "Outdoors" event category;
guided hikes currently classify as Sports. Geocode venues for WordPress-calendar sources so
volunteer plantings appear on the map. Replace placeholder place icons with real photos, and add
real social features: follows and per-user feeds. Turn on the second-generation ranker, which
learns from what each user actually attends, after a blind evaluation against the current one.
And add more launch areas beyond San Jose, which the ingestion pipeline is already built to take.

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
