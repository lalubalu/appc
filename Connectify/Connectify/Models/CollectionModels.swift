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

    var pointValue: Int {
        switch self {
        case .common: return 50
        case .uncommon: return 150
        case .rare: return 400
        case .legendary: return 1000
        }
    }

    var color: Color {
        switch self {
        case .common: return .connectifyGreen
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

    var isNearby: Bool { place.distanceValue < 1.0 }

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
        case .bronze: return 200
        case .silver: return 500
        case .gold: return 1500
        case .platinum: return 5000
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
