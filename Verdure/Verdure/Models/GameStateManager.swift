import Foundation
import SwiftUI
import CoreLocation
import Observation

@MainActor @Observable
final class GameStateManager {

    // MARK: - Persisted State

    var collectedPlaceIDs: Set<String> {
        didSet {
            save(collectedPlaceIDs, forKey: "collectedPlaceIDs")
            scheduleSyncIfNeeded()
        }
    }

    var checkedInEventIDs: Set<String> {
        didSet {
            save(checkedInEventIDs, forKey: "checkedInEventIDs")
            scheduleSyncIfNeeded()
        }
    }

    var pointsBalance: Int {
        didSet {
            UserDefaults.standard.set(pointsBalance, forKey: "pointsBalance")
            scheduleSyncIfNeeded()
        }
    }

    var lifetimePoints: Int {
        didSet {
            UserDefaults.standard.set(lifetimePoints, forKey: "lifetimePoints")
            scheduleSyncIfNeeded()
        }
    }

    var redeemedRewardIDs: Set<String> {
        didSet {
            save(redeemedRewardIDs, forKey: "redeemedRewardIDs")
            scheduleSyncIfNeeded()
        }
    }

    /// Bookmarked events (local only — not cloud-synced).
    var savedEventIDs: Set<String> {
        didSet { save(savedEventIDs, forKey: "savedEventIDs"); scheduleSyncIfNeeded() }
    }

    /// Bookmarked places (local only).
    var savedPlaceIDs: Set<String> {
        didSet { save(savedPlaceIDs, forKey: "savedPlaceIDs") }
    }

    // MARK: - Earn History (fuels real challenges, badges & streaks)

    /// One record per earn action, with the context (category/rarity) needed to
    /// compute challenge progress and badge unlocks honestly.
    struct EarnRecord: Codable, Equatable {
        enum Kind: String, Codable { case event, place }
        let kind: Kind
        let id: String
        let category: String   // EventCategory/PlaceCategory rawValue
        let rarity: String?    // PlaceRarity rawValue (places only)
        let points: Int
        let date: Date
    }

    private(set) var earnHistory: [EarnRecord] {
        didSet {
            if let data = try? JSONEncoder().encode(earnHistory.suffix(500)) {
                UserDefaults.standard.set(data, forKey: "earnHistory")
            }
        }
    }

    private func record(_ record: EarnRecord) {
        earnHistory.append(record)
        refreshGamification()
    }

    // MARK: - Daily Streak (consecutive days the app was opened)

    private(set) var currentStreak: Int {
        didSet { UserDefaults.standard.set(currentStreak, forKey: "streakCount") }
    }
    private var lastActiveDay: String {
        didSet { UserDefaults.standard.set(lastActiveDay, forKey: "streakLastDay") }
    }

    // MARK: Streak freeze
    //
    // One missed day used to reset a 40-day streak to 1. That is a punishment
    // for having a life, and it hits hardest the people who had most invested —
    // the exact users you least want to lose.
    //
    // ONE forgiven day per rolling 30, automatic, for EVERY user. Not a
    // purchase, not a tier, not a Verdure+ benefit.
    //
    // That is a product decision, not an oversight, and the reasoning is worth
    // keeping because the cost-side argument for selling it is genuinely
    // tempting (zero marginal cost, protects retention). Selling relief from a
    // punishment we invented is a dark pattern. The usual comparison —
    // Duolingo sells streak freezes — does not transfer: their streak tracks
    // daily practice, a thing people independently want to keep up. Ours tracks
    // check-ins, a mechanic we invented and that no interviewee raised
    // unprompted. Charging for anxiety relief about that, to an audience that
    // includes students and minors, is not a business we want.
    //
    // The retention benefit is kept in full. Only the lever is removed.
    //
    // ROLLING 30 DAYS, not a calendar month. A calendar reset would forgive a
    // miss on Jan 31 and another on Feb 1 — two misses in two days — which is
    // the gaming a per-month allowance invites.

    /// How many days may be missed without breaking the streak, per window.
    /// Identical for every account — there is no tier that changes either value.
    static let streakInsuranceDays = 1
    static let streakInsuranceWindowDays = 30

    private(set) var streakInsuranceUsedOn: String {
        didSet { UserDefaults.standard.set(streakInsuranceUsedOn, forKey: "streakInsuranceUsedOn") }
    }

    /// True when a gap was forgiven recently — the UI says so rather than
    /// letting the number look like it survived by magic.
    func streakInsuranceAvailable(now: Date = Date()) -> Bool {
        guard let used = Self.dayFormatter.date(from: streakInsuranceUsedOn) else { return true }
        let days = Calendar.current.dateComponents([.day], from: used, to: now).day ?? 999
        return days >= Self.streakInsuranceWindowDays
    }

    /// Call on every foreground. Same day → no-op; consecutive day → streak+1;
    /// exactly one missed day with insurance available → streak survives;
    /// anything longer → resets to 1.
    @discardableResult
    func recordActiveDay(now: Date = Date()) -> Bool {
        let today = Self.dayString(now)
        guard lastActiveDay != today else { return false }

        var insuranceUsed = false
        if let last = Self.dayFormatter.date(from: lastActiveDay) {
            let gap = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: last),
                to: Calendar.current.startOfDay(for: now)
            ).day ?? 999

            if gap == 1 {
                currentStreak += 1
            } else if gap == 2 && currentStreak > 0 && streakInsuranceAvailable(now: now) {
                // Exactly one day missed. Forgive it, and count today.
                currentStreak += 1
                streakInsuranceUsedOn = today
                insuranceUsed = true
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        lastActiveDay = today
        return insuranceUsed
    }

    nonisolated static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    nonisolated static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: - XP, Badges & Challenge bonuses (computed by GamificationEngine)

    /// XP bonus from completed challenges (progression-only; points stay server-owned).
    private(set) var challengeBonusXP: Int {
        didSet { UserDefaults.standard.set(challengeBonusXP, forKey: "challengeBonusXP") }
    }
    /// Challenges already rewarded, keyed "challengeID|yyyy-MM" so monthly ones re-arm.
    private var completedChallengeKeys: Set<String> {
        didSet { save(completedChallengeKeys, forKey: "completedChallengeKeys") }
    }
    /// Unlocked badges with their unlock dates (stable across launches).
    private(set) var earnedBadges: [String: Date] {
        didSet {
            if let data = try? JSONEncoder().encode(earnedBadges) {
                UserDefaults.standard.set(data, forKey: "earnedBadges")
            }
        }
    }

    /// Total progression XP: lifetime points ×2 plus challenge bonuses.
    var totalXP: Int { lifetimePoints * 2 + challengeBonusXP }
    var level: Int { max(1, totalXP / 500 + 1) }
    var xpInLevel: Int { totalXP % 500 }
    var levelProgress: Double { Double(xpInLevel) / 500.0 }

    /// Re-evaluate challenges + badges after an earn; awards bonuses, unlocks
    /// badges, and drops real entries into the notification inbox.
    func refreshGamification(now: Date = Date()) {
        // Challenge completions → one-time XP bonus per month-window.
        for challenge in GamificationEngine.challenges(for: self, now: now) where challenge.progress >= 1.0 {
            let key = "\(challenge.title)|\(Self.monthKey(now))"
            guard !completedChallengeKeys.contains(key) else { continue }
            completedChallengeKeys.insert(key)
            challengeBonusXP += challenge.xpReward
            NotificationManager.shared.push(AppNotification(
                kind: .points, title: "Challenge complete: \(challenge.title)",
                message: "+\(challenge.xpReward) XP — \(challenge.description)", timeAgo: "now"))
        }
        // Badge unlocks → persist the unlock date once.
        for badge in GamificationEngine.badges(for: self) where badge.earned {
            guard earnedBadges[badge.name] == nil else { continue }
            earnedBadges[badge.name] = now
            NotificationManager.shared.push(AppNotification(
                kind: .badge, title: "Badge unlocked: \(badge.name)",
                message: badge.detail, timeAgo: "now"))
        }
    }

    nonisolated static func monthKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    // MARK: - Saved places

    func isPlaceSaved(_ placeID: String) -> Bool { savedPlaceIDs.contains(placeID) }

    func togglePlaceSaved(_ placeID: String) {
        if savedPlaceIDs.contains(placeID) { savedPlaceIDs.remove(placeID) }
        else { savedPlaceIDs.insert(placeID); Haptics.success() }
    }

    // MARK: - Server Ops Queue
    //
    // Points are SERVER-authoritative: check-ins, collections, and redemptions go
    // through Cloud Functions callables (see FunctionsService). Earn actions apply
    // optimistically for instant UI + offline support, and are queued here until
    // the server confirms them. The callables are idempotent, so replays are safe.

    struct PendingOp: Codable, Equatable {
        enum Kind: String, Codable { case checkIn, collect }
        let kind: Kind
        let id: String        // event ID or place ID
        let category: String  // event category rawValue ("" for places)
        let points: Int       // points claimed at earn time (server clamps)
        // Attendance evidence (check-ins) — all optional so v1 queued ops still decode.
        var lat: Double? = nil        // user GPS at earn time
        var lon: Double? = nil
        var proofFile: String? = nil  // local JPEG filename awaiting upload
        var proofPath: String? = nil  // storage path once uploaded (upload is resumable)
    }

    private(set) var pendingOps: [PendingOp] {
        didSet {
            if let data = try? JSONEncoder().encode(pendingOps) {
                UserDefaults.standard.set(data, forKey: "pendingServerOps")
            }
        }
    }
    private var isFlushing = false

    /// True once a callable has actually round-tripped successfully — i.e. the
    /// Cloud Functions are really deployed and reachable. Until then the server's
    /// balance is NOT treated as authoritative (see mergeCloudState).
    private(set) var serverConfirmed = false

    /// Server-owned points earned locally but not yet credited by the server.
    /// Surfaced in the UI so a stalled backend is visible instead of silent.
    var unsyncedPointsCount: Int { pendingOps.reduce(0) { $0 + $1.points } }
    var hasUnsyncedEarnings: Bool { !pendingOps.isEmpty }

    // MARK: - Cloud Sync

    private var firestoreService: FirestoreService?
    private var functionsService: FunctionsService?
    private var currentUserID: String?
    private var syncTask: Task<Void, Never>?

    /// Connect to Firestore + Cloud Functions for cloud sync. Call after authentication.
    func connectCloud(firestore: FirestoreService, functions: FunctionsService, userID: String) {
        self.firestoreService = firestore
        self.functionsService = functions
        self.currentUserID = userID

        Task { @MainActor in
            let cloudState = await firestore.fetchGameState(userID: userID)
            if let cloudState {
                self.mergeCloudState(cloudState)
            } else {
                self.syncToCloud()
            }
            // Anything earned before this account connected (offline sessions,
            // pre-server-authority installs) gets re-submitted so the SERVER
            // credits it — the client can no longer write points itself.
            self.enqueueBackfill(cloud: cloudState)
            await self.flushPendingOps()
        }
    }

    /// Disconnect cloud sync (e.g., on sign out).
    func disconnectCloud() {
        syncTask?.cancel()
        firestoreService = nil
        functionsService = nil
        currentUserID = nil
    }

    /// Push queued earn-ops to the server, oldest first. Stops on network trouble
    /// (the queue persists and retries on next foreground/connect). Adopts the
    /// server's balance as truth once the queue fully drains.
    func flushPendingOps() async {
        guard let fx = functionsService, !isFlushing, !pendingOps.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        var lastBalance: Int?
        var lastLifetime: Int?

        while var op = pendingOps.first {
            // Stage 1 for check-ins: get the proof photo into Cloud Storage first.
            // The upload is resumable — proofPath persists on the op, so a retry
            // after upload success skips straight to the callable.
            if op.kind == .checkIn, let file = op.proofFile, op.proofPath == nil {
                let fileURL = Self.proofsDirectory.appendingPathComponent(file)
                guard let jpeg = try? Data(contentsOf: fileURL) else {
                    // Proof photo vanished from disk — the server will never accept
                    // this op, so drop it rather than wedge the queue.
                    print("[GameState] dropping check-in \(op.id) — proof photo missing")
                    pendingOps.removeFirst()
                    continue
                }
                do {
                    op.proofPath = try await StorageService.uploadProof(eventId: op.id, jpeg: jpeg)
                    pendingOps[0] = op   // persist upload progress
                } catch {
                    break   // Storage unreachable (offline / not yet enabled) — retry later
                }
            }

            do {
                let result: ServerAwardResult
                switch op.kind {
                case .checkIn:
                    result = try await fx.checkInToEvent(
                        eventId: op.id, category: op.category, claimedPoints: op.points,
                        proofPath: op.proofPath, lat: op.lat, lon: op.lon)
                case .collect:
                    result = try await fx.collectPlace(
                        placeId: op.id, claimedPoints: op.points, lat: op.lat, lon: op.lon)
                }
                serverConfirmed = true   // a callable really answered → server is live
                if op.kind == .checkIn, let file = op.proofFile {
                    try? FileManager.default.removeItem(at: Self.proofsDirectory.appendingPathComponent(file))
                }
                pendingOps.removeFirst()
                if let b = result.newBalance { lastBalance = b }
                if let l = result.newLifetime { lastLifetime = l }
            } catch ServerCallError.offline {
                break   // transient — keep queued, retry later
            } catch ServerCallError.notSignedIn {
                break   // auth hiccup — keep queued, retry after re-auth
            } catch {
                // Permanently rejected op (bad ID, failed proximity, etc.) — drop it
                // so the queue can't wedge. The optimistic local points for it get
                // corrected the next time a server balance is adopted.
                print("[GameState] dropping rejected op \(op.kind.rawValue):\(op.id) — \(error.localizedDescription)")
                pendingOps.removeFirst()
            }
        }

        // Only adopt the server balance when everything queued has landed —
        // otherwise the UI would briefly lose the optimistic points of later ops.
        if pendingOps.isEmpty {
            if let b = lastBalance { pointsBalance = b }
            if let l = lastLifetime { lifetimePoints = l }
        }
    }

    /// Queue server credit for locally-collected PLACES the cloud doesn't know about.
    /// Claims are conservative (server clamps to the rarity ceiling anyway).
    ///
    /// Event check-ins are deliberately NOT backfilled: the server now requires a
    /// proof photo + GPS coords, which legacy local check-ins never captured — so
    /// there is nothing honest to submit for them. Their IDs stay in the local
    /// collection (badges/history), they just never mint server points.
    private func enqueueBackfill(cloud: CloudGameState?) {
        let cloudPlaces = cloud?.collectedPlaceIDs ?? []
        let queuedIDs = Set(pendingOps.map(\.id))

        for id in collectedPlaceIDs where !cloudPlaces.contains(id) && !queuedIDs.contains(id) {
            pendingOps.append(PendingOp(kind: .collect, id: id, category: "", points: 5))
        }
    }

    /// Local spool for proof photos awaiting upload (Application Support/proofs).
    static var proofsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("proofs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func enqueue(_ op: PendingOp) {
        pendingOps.append(op)
        Task { await flushPendingOps() }
    }

    // MARK: - Computed

    var totalCollected: Int { collectedPlaceIDs.count }
    var totalEventsAttended: Int { checkedInEventIDs.count }

    func collectionProgress(total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(collectedPlaceIDs.count) / Double(total)
    }

    // MARK: - Init

    init() {
        self.collectedPlaceIDs = Self.loadSet(forKey: "collectedPlaceIDs")
        self.checkedInEventIDs = Self.loadSet(forKey: "checkedInEventIDs")
        self.pointsBalance = UserDefaults.standard.integer(forKey: "pointsBalance")
        self.lifetimePoints = UserDefaults.standard.integer(forKey: "lifetimePoints")
        self.redeemedRewardIDs = Self.loadSet(forKey: "redeemedRewardIDs")
        self.savedEventIDs = Self.loadSet(forKey: "savedEventIDs")
        self.savedPlaceIDs = Self.loadSet(forKey: "savedPlaceIDs")
        if let data = UserDefaults.standard.data(forKey: "pendingServerOps"),
           let ops = try? JSONDecoder().decode([PendingOp].self, from: data) {
            self.pendingOps = ops
        } else {
            self.pendingOps = []
        }
        if let data = UserDefaults.standard.data(forKey: "earnHistory"),
           let records = try? JSONDecoder().decode([EarnRecord].self, from: data) {
            self.earnHistory = records
        } else {
            self.earnHistory = []
        }
        self.currentStreak = UserDefaults.standard.integer(forKey: "streakCount")
        self.streakInsuranceUsedOn = UserDefaults.standard.string(forKey: "streakInsuranceUsedOn") ?? ""
        self.lastActiveDay = UserDefaults.standard.string(forKey: "streakLastDay") ?? ""
        self.challengeBonusXP = UserDefaults.standard.integer(forKey: "challengeBonusXP")
        self.completedChallengeKeys = Self.loadSet(forKey: "completedChallengeKeys")
        if let data = UserDefaults.standard.data(forKey: "earnedBadges"),
           let badges = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.earnedBadges = badges
        } else {
            self.earnedBadges = [:]
        }

        // Seed demo data on first launch
        if !UserDefaults.standard.bool(forKey: "gameStateSeeded_v2") {
            seedDemoData()
            UserDefaults.standard.set(true, forKey: "gameStateSeeded_v2")
        }
    }

    // MARK: - Event Check-in (primary points source)

    /// Check in to an event. Applies instantly (optimistic + offline-friendly) and
    /// queues the server call — the server is the final authority on points and
    /// silently no-ops double check-ins.
    ///
    /// `proofPhoto` (JPEG) is spooled to disk and uploaded to Cloud Storage during
    /// flush; `userCoordinate` is the GPS fix at the moment of check-in. The server
    /// REJECTS check-ins without both, so callers must gate on them (see
    /// EventDetailSheet's proximity + photo requirements).
    @discardableResult
    func checkInEvent(_ event: Event, proofPhoto: Data? = nil,
                      userCoordinate: CLLocationCoordinate2D? = nil) -> Int {
        guard !isCheckedIn(event.id) else { return 0 }
        // Fixture content can never earn — not even under the QA harness.
        guard !SampleData.isSample(id: event.id) else { return 0 }
        checkedInEventIDs.insert(event.id)
        let pts = event.pointValue
        pointsBalance += pts
        lifetimePoints += pts

        // Spool the proof photo locally so offline check-ins survive relaunches.
        var proofFile: String? = nil
        if let proofPhoto {
            let name = StorageService.proofFileName(for: event.id)
            if (try? proofPhoto.write(to: Self.proofsDirectory.appendingPathComponent(name))) != nil {
                proofFile = name
            }
        }

        enqueue(PendingOp(kind: .checkIn, id: event.id,
                          category: event.category.rawValue, points: pts,
                          lat: userCoordinate?.latitude, lon: userCoordinate?.longitude,
                          proofFile: proofFile))
        record(EarnRecord(kind: .event, id: event.id, category: event.category.rawValue,
                          rarity: nil, points: pts, date: Date()))
        // Q1 outcome. Logged here rather than at the server confirmation
        // because the question is about the USER's action; whether the pending
        // op later drains is a different question with a different answer.
        Analytics.log(event: .checkinSucceeded, params: [
            "category": event.category.rawValue,
            "points": pts,
            "hadProof": proofPhoto != nil,
        ])
        NotificationManager.shared.push(AppNotification(
            kind: .points, title: "+\(pts) points earned",
            message: "Thanks for checking in to \(event.title).", timeAgo: "now"))
        return pts
    }

    func isCheckedIn(_ eventID: String) -> Bool {
        checkedInEventIDs.contains(eventID)
    }

    // MARK: - Saved / bookmarked events

    func isSaved(_ eventID: String) -> Bool { savedEventIDs.contains(eventID) }

    func toggleSaved(_ event: Event) {
        if savedEventIDs.contains(event.id) {
            savedEventIDs.remove(event.id)
            NotificationManager.shared.cancelEventReminder(for: event)
        } else {
            savedEventIDs.insert(event.id); Haptics.success()
            NotificationManager.shared.scheduleEventReminder(for: event)
            // Q1 cohort entry point — see the schema note in Analytics.swift.
            Analytics.log(event: .eventSaved, params: ["category": event.category.rawValue])
            // C3: the first save is a value moment — they've just told us what
            // they care about, so "we'll tell you when a friend is going" now
            // has an obvious referent. Only ever sets a flag; the primer sheet
            // decides whether to appear, and only the primer's own button ever
            // asks iOS.
            pendingNotificationPrimer = .firstSave
        }
    }

    /// Set when something has just earned the right to ask about notifications.
    /// Consumed by whichever screen is on top; nil means don't ask.
    var pendingNotificationPrimer: NotificationPrimer.Trigger?

    // MARK: - Place Collection (secondary, small points)

    /// Collect a place. Same optimistic-then-server pattern as event check-in.
    /// The user's GPS fix is recorded server-side for spot-checking (places have
    /// no server registry to hard-validate against).
    @discardableResult
    func collectPlace(_ collectible: CollectiblePlace,
                      userCoordinate: CLLocationCoordinate2D? = nil) -> Int {
        guard !isCollected(collectible.id) else { return 0 }
        // Fixture content can never earn — not even under the QA harness.
        guard !SampleData.isSample(id: collectible.id) else { return 0 }
        collectedPlaceIDs.insert(collectible.id)
        let pts = collectible.pointValue
        pointsBalance += pts
        lifetimePoints += pts
        enqueue(PendingOp(kind: .collect, id: collectible.id, category: "", points: pts,
                          lat: userCoordinate?.latitude, lon: userCoordinate?.longitude))
        record(EarnRecord(kind: .place, id: collectible.id,
                          category: collectible.place.category.rawValue,
                          rarity: collectible.rarity.rawValue, points: pts, date: Date()))
        return pts
    }

    func isCollected(_ placeID: String) -> Bool {
        collectedPlaceIDs.contains(placeID)
    }

    // MARK: - Redeem (server-only when signed in — real money attached)

    enum RedeemResult: Equatable {
        case success
        case alreadyRedeemed
        case notEnoughPoints
        case offline
        case signInRequired
        case failed(String)
    }

    /// Single-flight guard so rapid double-taps can't fire two redemptions.
    private var isRedeeming = false

    /// What a redemption produced. Perks come back with a code the user must be
    /// shown — the previous API discarded it, so a perk purchase completed with
    /// nothing to display.
    struct RedeemOutcome: Equatable {
        let result: RedeemResult
        var kind: String = "cash"
        var code: String? = nil
        var title: String? = nil
        var partner: String? = nil
    }

    /// Redeem a reward. When signed in this goes through the server (no optimistic
    /// deduction — redemptions require connectivity). Signed out, it refuses:
    /// without an account no fulfilment is possible.
    func redeemReward(_ reward: Reward) async -> RedeemResult {
        await redeem(rewardId: reward.id, pointCost: reward.pointCost).result
    }

    /// ID-based redemption, used by both cash cards and partner perks. Perks
    /// exist only on the server, so there is no local `Reward` to pass.
    func redeem(rewardId: String, pointCost: Int) async -> RedeemOutcome {
        guard !isRedeeming else { return RedeemOutcome(result: .failed("A redemption is already in progress.")) }
        guard !redeemedRewardIDs.contains(rewardId) else { return RedeemOutcome(result: .alreadyRedeemed) }
        guard pointsBalance >= pointCost else { return RedeemOutcome(result: .notEnoughPoints) }
        isRedeeming = true
        defer { isRedeeming = false }

        guard let fx = functionsService else {
            // No account → no fulfilment is possible. Pretending to redeem takes
            // points and delivers nothing, which is a fabricated reward.
            return RedeemOutcome(result: .signInRequired)
        }

        // Land any queued earns first so the server balance is current.
        await flushPendingOps()

        do {
            let r = try await fx.redeemReward(rewardId: rewardId)
            guard r.redeemed else { return RedeemOutcome(result: .failed("Redemption failed. Please try again.")) }
            redeemedRewardIDs.insert(rewardId)
            pointsBalance = r.remaining
            return RedeemOutcome(result: .success, kind: r.kind, code: r.code,
                                 title: r.title, partner: r.partner)
        } catch ServerCallError.offline {
            return RedeemOutcome(result: .offline)
        } catch ServerCallError.alreadyRedeemed {
            redeemedRewardIDs.insert(rewardId)   // reconcile local view with server
            return RedeemOutcome(result: .alreadyRedeemed)
        } catch ServerCallError.notEnoughPoints {
            return RedeemOutcome(result: .notEnoughPoints)
        } catch {
            // Server refusal messages here are specific and user-facing
            // ("Verdure+ early access…", "out of codes for now") — surface them.
            return RedeemOutcome(result: .failed(error.localizedDescription))
        }
    }

    func isRedeemed(_ rewardID: String) -> Bool {
        redeemedRewardIDs.contains(rewardID)
    }

    func canAfford(_ reward: Reward) -> Bool {
        pointsBalance >= reward.pointCost
    }

    func uncollected(from places: [CollectiblePlace], nearbyOnly: Bool = false, userLocation: CLLocation? = nil) -> [CollectiblePlace] {
        places.filter { place in
            let notCollected = !isCollected(place.id)
            if nearbyOnly {
                return notCollected && place.isNearby(from: userLocation)
            }
            return notCollected
        }
    }

    func collectionsByCategory(from places: [CollectiblePlace]) -> [PlaceCategory: (collected: Int, total: Int)] {
        var result: [PlaceCategory: (collected: Int, total: Int)] = [:]
        for place in places {
            let cat = place.place.category
            let current = result[cat] ?? (0, 0)
            let isCol = isCollected(place.id) ? 1 : 0
            result[cat] = (current.collected + isCol, current.total + 1)
        }
        return result
    }

    // MARK: - Cloud Merge

    private func mergeCloudState(_ cloud: CloudGameState) {
        // IDs: keep the superset so nothing the user did disappears from the UI.
        collectedPlaceIDs = collectedPlaceIDs.union(cloud.collectedPlaceIDs)
        checkedInEventIDs = checkedInEventIDs.union(cloud.checkedInEventIDs)
        redeemedRewardIDs = redeemedRewardIDs.union(cloud.redeemedRewardIDs)

        // Adopt the cloud balance as truth ONLY when the server has actually proven
        // itself — a successful callable round-trip AND an empty queue. Merely having
        // a FunctionsService instance proves nothing: if the Functions aren't deployed
        // (or are unreachable), the cloud balance is a meaningless 0 and adopting it
        // would silently wipe legitimate optimistic points that can never be
        // re-credited (event check-ins are intentionally not backfilled — no proof).
        if serverConfirmed && pendingOps.isEmpty {
            pointsBalance = cloud.pointsBalance
            lifetimePoints = cloud.lifetimePoints
        } else {
            // Unproven server / work still queued → never destroy local progress.
            pointsBalance = max(pointsBalance, cloud.pointsBalance)
            lifetimePoints = max(lifetimePoints, cloud.lifetimePoints)
        }

        // Push merged client-owned state back to cloud
        syncToCloud()
    }

    private func scheduleSyncIfNeeded() {
        guard firestoreService != nil, currentUserID != nil else { return }

        // Debounce: cancel pending sync, schedule a new one
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.syncToCloud()
        }
    }

    private func syncToCloud() {
        guard let firestore = firestoreService, let userID = currentUserID else { return }

        // Only the client-owned slice syncs directly. Points, check-ins, and
        // redemptions are written by the Cloud Functions (rules deny us).
        Task {
            await firestore.syncGameState(
                userID: userID,
                collectedPlaceIDs: collectedPlaceIDs,
                savedEventIDs: savedEventIDs
            )
        }
    }

    // MARK: - Demo Seed

    private func seedDemoData() {
        collectedPlaceIDs = Set(["riverside-park"])
        checkedInEventIDs = Set(["river-cleanup-day", "weekend-farmers-market"])
        pointsBalance = 280
        lifetimePoints = 280
    }

    // MARK: - Persistence Helpers

    private func save(_ set: Set<String>, forKey key: String) {
        let array = Array(set)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadSet(forKey key: String) -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    // MARK: - Test seams
    //
    // mergeCloudState is private (it's only ever driven by connectCloud); these
    // expose it to the test target without widening the production surface.

    #if DEBUG
    func applyCloudStateForTesting(_ cloud: CloudGameState) { mergeCloudState(cloud) }
    func markServerConfirmedForTesting() { serverConfirmed = true }
    #endif

    /// Reset all game state (for testing)
    func resetAll() {
        collectedPlaceIDs = []
        checkedInEventIDs = []
        pointsBalance = 0
        lifetimePoints = 0
        redeemedRewardIDs = []
        pendingOps = []
        earnHistory = []
        currentStreak = 0
        streakInsuranceUsedOn = ""
        lastActiveDay = ""
        challengeBonusXP = 0
        completedChallengeKeys = []
        earnedBadges = [:]
        try? FileManager.default.removeItem(at: Self.proofsDirectory)   // clear spooled proof photos
        UserDefaults.standard.removeObject(forKey: "gameStateSeeded_v2")
    }
}
