import Foundation
import SwiftUI
import CoreLocation

// MARK: - Place Rarity

enum PlaceRarity: String, CaseIterable, Identifiable, Codable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case legendary = "Legendary"

    var id: String { rawValue }

    /// Place visit points — intentionally low; events are the main earner
    var pointValue: Int {
        switch self {
        case .common: return 5
        case .uncommon: return 10
        case .rare: return 25
        case .legendary: return 50
        }
    }

    var color: Color {
        switch self {
        case .common: return .verdureGreen
        case .uncommon: return .accentAmber
        case .rare: return .accentLavender
        case .legendary: return .accentCoral
        }
    }

    var icon: String {
        switch self {
        case .common: return "circle.fill"
        case .uncommon: return "diamond.fill"
        case .rare: return "star.fill"
        case .legendary: return "crown.fill"
        }
    }

    var glowOpacity: Double {
        switch self {
        case .common: return 0.0
        case .uncommon: return 0.15
        case .rare: return 0.25
        case .legendary: return 0.4
        }
    }
}

// MARK: - Collectible Place

struct CollectiblePlace: Identifiable, Hashable {
    let id: String               // stable ID based on place name
    let place: Place
    let rarity: PlaceRarity
    let coordinate: CLLocationCoordinate2D

    var pointValue: Int { rarity.pointValue }

    /// Distance in miles from a location to this place
    func distanceMiles(from location: CLLocation) -> Double {
        let placeLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: placeLoc) / 1609.34
    }

    /// Whether the place is within collectible radius (500 ft ≈ 0.0947 mi)
    func isNearby(from location: CLLocation?, radius: Double = 0.0947) -> Bool {
        guard let loc = location else { return false }
        return distanceMiles(from: loc) < radius
    }

    /// Legacy fallback using Place's static distanceValue (used when no GPS)
    var isNearbyStatic: Bool { place.distanceValue < 0.1 }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CollectiblePlace, rhs: CollectiblePlace) -> Bool { lhs.id == rhs.id }

    /// Assigns rarity based on place category
    static func rarityFor(_ category: PlaceCategory) -> PlaceRarity {
        switch category {
        case .parks, .playgrounds: return .common
        case .trails, .gardens, .community: return .uncommon
        case .waterfront, .sports: return .rare
        case .scenic: return .legendary
        }
    }
}

// MARK: - Reward Tier

enum RewardTier: String, CaseIterable, Identifiable, Codable {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    case platinum = "Platinum"

    var id: String { rawValue }

    var minPoints: Int {
        switch self {
        case .bronze: return 1000
        case .silver: return 2500
        case .gold: return 7500
        case .platinum: return 20000
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.78)
        case .gold: return .accentAmber
        case .platinum: return .accentLavender
        }
    }

    var icon: String {
        switch self {
        case .bronze: return "gift.fill"
        case .silver: return "gift.fill"
        case .gold: return "star.circle.fill"
        case .platinum: return "crown.fill"
        }
    }
}

// MARK: - Reward

struct Reward: Identifiable {
    let id: String
    let name: String
    let brand: String
    let icon: String           // SF Symbol
    let pointCost: Int
    let tier: RewardTier
}
