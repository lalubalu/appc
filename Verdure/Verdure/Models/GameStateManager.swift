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

    // MARK: - Cloud Sync

    private var firestoreService: FirestoreService?
    private var currentUserID: String?
    private var syncTask: Task<Void, Never>?

    /// Connect to Firestore for cloud sync. Call after authentication.
    func connectCloud(firestore: FirestoreService, userID: String) {
        self.firestoreService = firestore
        self.currentUserID = userID

        // Attempt to merge cloud state
        Task { @MainActor in
            if let cloudState = await firestore.fetchGameState(userID: userID) {
                self.mergeCloudState(cloudState)
            } else {
                self.syncToCloud()
            }
        }
    }

    /// Disconnect cloud sync (e.g., on sign out).
    func disconnectCloud() {
        syncTask?.cancel()
        firestoreService = nil
        currentUserID = nil
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

        // Seed demo data on first launch
        if !UserDefaults.standard.bool(forKey: "gameStateSeeded_v2") {
            seedDemoData()
            UserDefaults.standard.set(true, forKey: "gameStateSeeded_v2")
        }
    }

    // MARK: - Event Check-in (primary points source)

    @discardableResult
    func checkInEvent(_ event: Event) -> Int {
        guard !isCheckedIn(event.id) else { return 0 }
        checkedInEventIDs.insert(event.id)
        let pts = event.pointValue
        pointsBalance += pts
        lifetimePoints += pts
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

    @discardableResult
    func collectPlace(_ collectible: CollectiblePlace) -> Int {
        guard !isCollected(collectible.id) else { return 0 }
        collectedPlaceIDs.insert(collectible.id)
        let pts = collectible.pointValue
        pointsBalance += pts
        lifetimePoints += pts
        return pts
    }

    func isCollected(_ placeID: String) -> Bool {
        collectedPlaceIDs.contains(placeID)
    }

    @discardableResult
    func redeemReward(_ reward: Reward) -> Bool {
        guard pointsBalance >= reward.pointCost else { return false }
        guard !redeemedRewardIDs.contains(reward.id) else { return false }
        pointsBalance -= reward.pointCost
        redeemedRewardIDs.insert(reward.id)
        return true
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
        // Union strategy: keep the superset of collected items, max of points
        collectedPlaceIDs = collectedPlaceIDs.union(cloud.collectedPlaceIDs)
        checkedInEventIDs = checkedInEventIDs.union(cloud.checkedInEventIDs)
        redeemedRewardIDs = redeemedRewardIDs.union(cloud.redeemedRewardIDs)
        pointsBalance = max(pointsBalance, cloud.pointsBalance)
        lifetimePoints = max(lifetimePoints, cloud.lifetimePoints)

        // Push merged state back to cloud
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

        Task {
            await firestore.syncGameState(
                userID: userID,
                collectedPlaceIDs: collectedPlaceIDs,
                checkedInEventIDs: checkedInEventIDs,
                pointsBalance: pointsBalance,
                lifetimePoints: lifetimePoints,
                redeemedRewardIDs: redeemedRewardIDs
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
        UserDefaults.standard.removeObject(forKey: "gameStateSeeded_v2")
    }
}
