import Foundation
import SwiftUI
import CoreLocation
import Observation

@Observable
final class GameStateManager {

    // MARK: - Persisted State

    var collectedPlaceIDs: Set<String> {
        didSet { save(collectedPlaceIDs, forKey: "collectedPlaceIDs") }
    }

    var checkedInEventIDs: Set<String> {
        didSet { save(checkedInEventIDs, forKey: "checkedInEventIDs") }
    }

    var pointsBalance: Int {
        didSet { UserDefaults.standard.set(pointsBalance, forKey: "pointsBalance") }
    }

    var lifetimePoints: Int {
        didSet { UserDefaults.standard.set(lifetimePoints, forKey: "lifetimePoints") }
    }

    var redeemedRewardIDs: Set<String> {
        didSet { save(redeemedRewardIDs, forKey: "redeemedRewardIDs") }
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

        // Seed demo data on first launch
        if !UserDefaults.standard.bool(forKey: "gameStateSeeded_v2") {
            seedDemoData()
            UserDefaults.standard.set(true, forKey: "gameStateSeeded_v2")
        }
    }

    // MARK: - Event Check-in (primary points source)

    /// Check in to an event and earn points. Returns points earned.
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

    // MARK: - Place Collection (secondary, small points)

    /// Collect a place — small bonus points
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

    /// Redeem a reward, returns true if successful
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

    /// Uncollected places, optionally filtered to GPS-nearby only
    func uncollected(from places: [CollectiblePlace], nearbyOnly: Bool = false, userLocation: CLLocation? = nil) -> [CollectiblePlace] {
        places.filter { place in
            let notCollected = !isCollected(place.id)
            if nearbyOnly {
                return notCollected && place.isNearby(from: userLocation)
            }
            return notCollected
        }
    }

    /// Collection count per category
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

    // MARK: - Demo Seed

    private func seedDemoData() {
        // Pre-attend 2 events for demo
        checkedInEventIDs = Set(["river-cleanup-day", "weekend-farmers-market"])
        // Pre-collect 1 place
        collectedPlaceIDs = Set(["riverside-park"])
        // 200 (cleanup) + 75 (market) + 5 (common place) = 280 starting points
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
