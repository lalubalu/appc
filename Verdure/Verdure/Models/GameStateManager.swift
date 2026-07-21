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
        didSet { save(savedEventIDs, forKey: "savedEventIDs") }
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
        if let data = UserDefaults.standard.data(forKey: "pendingServerOps"),
           let ops = try? JSONDecoder().decode([PendingOp].self, from: data) {
            self.pendingOps = ops
        } else {
            self.pendingOps = []
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
        }
    }

    // MARK: - Place Collection (secondary, small points)

    /// Collect a place. Same optimistic-then-server pattern as event check-in.
    /// The user's GPS fix is recorded server-side for spot-checking (places have
    /// no server registry to hard-validate against).
    @discardableResult
    func collectPlace(_ collectible: CollectiblePlace,
                      userCoordinate: CLLocationCoordinate2D? = nil) -> Int {
        guard !isCollected(collectible.id) else { return 0 }
        collectedPlaceIDs.insert(collectible.id)
        let pts = collectible.pointValue
        pointsBalance += pts
        lifetimePoints += pts
        enqueue(PendingOp(kind: .collect, id: collectible.id, category: "", points: pts,
                          lat: userCoordinate?.latitude, lon: userCoordinate?.longitude))
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
        case failed(String)
    }

    /// Single-flight guard so rapid double-taps can't fire two redemptions.
    private var isRedeeming = false

    /// Redeem a reward. When signed in this goes through the server (no optimistic
    /// deduction — redemptions require connectivity). Signed out, it falls back to
    /// local demo behavior since there's no real fulfillment without an account.
    func redeemReward(_ reward: Reward) async -> RedeemResult {
        guard !isRedeeming else { return .failed("A redemption is already in progress.") }
        guard !redeemedRewardIDs.contains(reward.id) else { return .alreadyRedeemed }
        guard pointsBalance >= reward.pointCost else { return .notEnoughPoints }
        isRedeeming = true
        defer { isRedeeming = false }

        guard let fx = functionsService else {
            // Signed-out demo mode: local-only redemption.
            pointsBalance -= reward.pointCost
            redeemedRewardIDs.insert(reward.id)
            return .success
        }

        // Land any queued earns first so the server balance is current.
        await flushPendingOps()

        do {
            let result = try await fx.redeemReward(rewardId: reward.id)
            guard result.redeemed else { return .failed("Redemption failed. Please try again.") }
            redeemedRewardIDs.insert(reward.id)
            pointsBalance = result.remaining
            return .success
        } catch ServerCallError.offline {
            return .offline
        } catch ServerCallError.alreadyRedeemed {
            redeemedRewardIDs.insert(reward.id)   // reconcile local view with server
            return .alreadyRedeemed
        } catch ServerCallError.notEnoughPoints {
            return .notEnoughPoints
        } catch {
            return .failed(error.localizedDescription)
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

        if functionsService != nil {
            // Server-authoritative: the cloud balance is truth. Locally-earned items
            // the server hasn't credited yet are re-submitted by the pending-op
            // queue/backfill right after this merge, which restores their points.
            pointsBalance = cloud.pointsBalance
            lifetimePoints = cloud.lifetimePoints
        } else {
            // Legacy/offline merge: keep the max.
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
                collectedPlaceIDs: collectedPlaceIDs
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

    /// Reset all game state (for testing)
    func resetAll() {
        collectedPlaceIDs = []
        checkedInEventIDs = []
        pointsBalance = 0
        lifetimePoints = 0
        redeemedRewardIDs = []
        pendingOps = []
        try? FileManager.default.removeItem(at: Self.proofsDirectory)   // clear spooled proof photos
        UserDefaults.standard.removeObject(forKey: "gameStateSeeded_v2")
    }
}
