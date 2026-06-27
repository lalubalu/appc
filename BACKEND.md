# Verdure — Backend

Firebase (Auth + Firestore) is **real and working** in the app. This doc covers what's
implemented, and the steps only you can do (deploy + account-level setup).

## What's implemented (in this repo)

| Piece | Where | Status |
|---|---|---|
| Email/password auth | `Models/AuthService.swift` | ✅ working |
| Game-state + profile sync | `Models/FirestoreService.swift` | ✅ working |
| **Community posts → Firestore** | `FirestoreService.createPost/fetchRecentPosts`, `CommunityView` | ✅ wired (needs sign-in to round-trip) |
| **Firestore security rules** | `firestore.rules` | ✅ written — **must be deployed** |
| **Storage rules** (profile pics, proof photos) | `storage.rules` | ✅ written — deploy + enable Storage |
| **Cloud Functions** (server-authoritative points) | `functions/src/index.ts` | ✅ written — **must be deployed** |
| Deploy config | `firebase.json` | ✅ |

## Steps only you can do

### 1. Deploy rules + functions  (highest priority)
```bash
npm i -g firebase-tools
firebase login                       # your Google account
firebase use connectify-19dd8        # or your project id
cd functions && npm install && cd ..
firebase deploy --only firestore:rules,storage,functions
```
Until you deploy `firestore.rules`, your database may still be in open **test mode**.

### 2. Fix the bundle-ID mismatch
`GoogleService-Info.plist` is registered for `com.vaiybhav.connectify`, but the app is
`com.vaiybhav.verdure`. Auth/Firestore work anyway, but to be clean:
Firebase console → Project settings → **Add app** → iOS → bundle id `com.vaiybhav.verdure`
→ download the new `GoogleService-Info.plist` → replace `Verdure/Verdure/GoogleService-Info.plist`.

### 3. Go server-authoritative on points (anti-cheat)
After the functions are deployed:
- Tighten `firestore.rules` per the **PRODUCTION LOCKDOWN** comment (deny client writes to
  `pointsBalance` / `lifetimePoints` / `checkedInEventIDs` / `redeemedRewardIDs`).
- Call the callables from the client (add `FirebaseFunctions` to `project.yml` SPM products):
  ```swift
  let res = try await Functions.functions().httpsCallable("checkInToEvent")
      .call(["eventId": event.id, "category": event.category.rawValue,
             "claimedPoints": event.pointValue])
  ```
- Fill `REWARD_COSTS` in `functions/src/index.ts` with your real reward IDs + costs.

### 4. Images (optional)
Enable **Storage** in the console, deploy `storage.rules`, add `FirebaseStorage` to SPM, then
upload profile pics to `profilePics/{uid}` and proof photos to `proofs/{uid}/{eventId}`.

### 5. Push notifications (optional)
Add `FirebaseMessaging` to SPM + upload an **APNs auth key** (Apple Developer → Keys) in the
Firebase console. The client should register its FCM token to `users/{uid}.fcmTokens`; the
`onPostCreated` / `sendEventReminders` functions already fan out from there.

### 6. Real gift-card fulfilment (optional)
In `redeemReward` (functions), replace the `TODO` with a Tango Card / Tremendous API call.
Those require a vendor account + funded balance.

## Not yet done (needs the above)
- Server-verified check-ins/points (code ready, needs deploy + client swap)
- Real proof-of-attendance verification (proximity + photo review)
- Image storage, push delivery, gift-card fulfilment
